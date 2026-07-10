# Fully Automatic MLIR Release Pipeline

**Date:** 2026-07-10
**Status:** Approved

## Problem

The intended flow — bump LLVM, create tag, create release, CI builds — only works when a
human manually pushes the tag. Three stacked failures cause this:

1. **Build-skip bug in `create-release.yml`.** The job output
   `created: ${{ steps.create.outcome == 'success' }}` evaluates to the string `"true"`,
   but the downstream build job checks `if: needs.create-tag.outputs.created == 'success'`.
   The comparison is never true, so the build job is always skipped (confirmed in run
   28643338135: `create-tag` succeeded, `build` skipped in 0s). Tags `v22.1.1` and
   `v22.1.8` exist with no built release; the newest complete release is `v21.1.2`.
2. **`GITHUB_TOKEN` recursion protection.** Tags pushed by a workflow using the default
   `GITHUB_TOKEN` never fire the `on: push: tags` trigger in `build.yml`. Only tags pushed
   by a human from their machine trigger the build.
3. **The weekly `bump-llvm.yml` schedule has failed every Monday since 2026-03-30**
   (logs expired; suspected cause is the full-history `llvm-project` submodule checkout).

Secondary issues: `build.yml`'s `workflow_call` path checks out `main` with a branch ref,
so `softprops/action-gh-release` has no tag to attach a release to (latent, never
exercised); there is no way to rerun a single failed platform, leaving stale draft
releases (v21.1.3, v21.1.4) behind.

## Decision

Fully automatic, zero-human-interaction flow (user's explicit choice). Because a bump PR
auto-merged by the github-actions bot would push to `main` with `GITHUB_TOKEN` — and
therefore not fire any `push`-triggered workflow (failure 2 again) — the PR step is
dropped entirely. One pipeline does everything in a single run and chains the build via
`workflow_call`, which is immune to the token-triggering restriction. `main` is
unprotected, so direct commits work.

## Design

### 1. `bump-llvm.yml` → the whole pipeline

Triggers: weekly schedule (Mon 08:00 UTC) + `workflow_dispatch` with optional `version`
input.

Job `bump`:

- Detect the latest `llvmorg-X.Y.Z` release tag via
  `git ls-remote --tags https://github.com/llvm/llvm-project` — **no submodule checkout**
  (removes the suspected cause of the weekly failures and is much faster). An explicit
  `version` input overrides detection.
- Compare against the `LLVM_VERSION` file at the repo root on `main`.
- If different: point the `llvm-project` submodule at the tag's commit SHA (taken from
  the same `ls-remote` output) with `git update-index --cacheinfo 160000,<sha>,llvm-project`
  — no submodule clone needed — write the new version to `LLVM_VERSION`, commit directly
  to `main`, then create annotated tag `vX.Y.Z` on that commit and push both.
- If the version is current or tag `vX.Y.Z` already exists: exit green ("nothing to do").
- Outputs: `tag`, `proceed`.

Job `build` (`if: proceed`): `uses: ./.github/workflows/build.yml` with
`tag: vX.Y.Z`, so the 4-platform build runs in the same workflow run.

### 2. `build.yml` gains a `tag` input

- `workflow_call` and a new `workflow_dispatch` both declare `inputs.tag` (dispatch input
  required; used to rerun any/all platforms against an existing tag).
- Every job: `actions/checkout` with `ref: ${{ inputs.tag || github.ref_name }}`.
- `softprops/action-gh-release` gets an explicit `tag_name: ${{ inputs.tag || github.ref_name }}`.
- Artifact names derive the version from the tag (`${TAG#v}`); the `MLIR_VERSION` env is
  removed from `build.yml` entirely (see Addendum — workflow commits may not touch
  workflow files).
- The `on: push: tags: v*` trigger stays as a manual escape hatch.

### 3. `create-release.yml` fixed, kept as manual utility

- Fix the condition: `if: needs.create-tag.outputs.created == 'true'`.
- Pass `tag` through to `build.yml`.
- Purpose: manually tag + build the version currently on `main`.

`delete-release.yml` is untouched.

## Error handling

- Partial platform failure: the release remains a draft with partial assets; re-dispatch
  `build.yml` with the tag to fill in missing artifacts.
- Re-running the pipeline is always safe: version compare and tag-exists checks make
  commit/tag steps idempotent.
- If the Monday schedule fails, a manual `workflow_dispatch` reproduces it with fresh logs.

## Testing

1. Dispatch the pipeline with an explicit older version → verify commit, tag, release
   draft, and at least the fastest platform artifact appear.
2. Dispatch `build.yml` alone with that tag → verify single-platform rerun works.
3. Clean up with `delete-release.yml` and revert the test bump commit.

## Out of scope

- Restoring a human review gate (branch protection / PR flow) — explicitly declined.
- The stateless "build whatever artifacts are missing" reconciler model — possible later
  evolution.
- Cleaning up existing stale draft releases (one-time manual task).

## Addendum (2026-07-10): root cause confirmed, version storage moved

Step-level data for failed run 26024152860 shows "Determine latest LLVM release" and
"Bump LLVM submodule" succeeded and **"Create Pull Request" failed** — consistent with
GitHub's restriction that the default `GITHUB_TOKEN` may not push commits modifying
`.github/workflows/` files. Every scheduled run since 2026-03-30 (when a new LLVM patch
release first made the job take the non-skip path) failed there. This same restriction
would break the new pipeline's direct commit, because the version lived in `build.yml`.

Decision: the current LLVM version moves to a plain `LLVM_VERSION` file at the repo
root. `bump-llvm.yml` reads and writes that file; `create-release.yml` reads it;
`build.yml` no longer stores a version at all — every trigger provides a `v<version>`
tag and jobs derive the version as `${TAG#v}`.
