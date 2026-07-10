# Fully Automatic MLIR Release Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One weekly GitHub Actions pipeline that detects new LLVM releases, commits the bump to `main`, tags `vX.Y.Z`, and builds all platforms in the same run — zero human interaction.

**Architecture:** `bump-llvm.yml` becomes a two-job pipeline (plan/commit/tag → chained build via `workflow_call`), sidestepping GitHub's rule that `GITHUB_TOKEN`-pushed tags never trigger workflows. The current LLVM version moves out of `build.yml` into a root-level `LLVM_VERSION` file because `GITHUB_TOKEN` cannot push commits touching `.github/workflows/` (confirmed root cause of the weekly failures since 2026-03-30). `build.yml` derives the version from the release tag.

**Tech Stack:** GitHub Actions YAML, bash, `softprops/action-gh-release@v1`, `actionlint` for verification.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-10-automated-release-pipeline-design.md`
- Only the default `GITHUB_TOKEN` — no PATs, no GitHub Apps, no new secrets.
- Commits pushed by workflows must never touch `.github/workflows/` files.
- Artifact naming scheme is frozen (consumers depend on it): `mlir-<version>-<osversion>-X64.tar.gz`, `mlir-<version>-<osversion>-arm64.tar.gz`, `mlir-<version>-osx-arm64.tar.gz`.
- Release tags are `v<version>` (e.g. `v22.1.8`); upstream tags are `llvmorg-<version>`.
- `on: push: tags: v*` in `build.yml` must keep working (manual escape hatch).
- Verification for workflow files is `actionlint` (no unit-test framework applies); behavioral verification is via `gh workflow run` dispatches in Task 5.
- Work on branch `automated-release-pipeline` off `main`.

---

### Task 1: Spec addendum — confirmed root cause and version-file decision

**Files:**
- Modify: `docs/superpowers/specs/2026-07-10-automated-release-pipeline-design.md`

**Interfaces:**
- Produces: the spec statement that later tasks implement — `LLVM_VERSION` root file is the version source of truth; `build.yml` carries no `MLIR_VERSION` env.

- [ ] **Step 1: Replace the two now-outdated spec statements**

In the spec file, replace this text in section "1. `bump-llvm.yml` → the whole pipeline":

```
- Compare against `MLIR_VERSION` in `.github/workflows/build.yml` on `main`.
```

with:

```
- Compare against the `LLVM_VERSION` file at the repo root on `main`.
```

and replace (same section):

```
  — no submodule clone needed — sed `MLIR_VERSION`, commit directly to `main`, then
  create annotated tag `vX.Y.Z` on that commit and push both.
```

with:

```
  — no submodule clone needed — write the new version to `LLVM_VERSION`, commit directly
  to `main`, then create annotated tag `vX.Y.Z` on that commit and push both.
```

In section "2. `build.yml` gains a `tag` input", replace:

```
- Artifact names derive the version from the tag (`${TAG#v}`) instead of relying solely on
  the baked-in `MLIR_VERSION` env (env stays as fallback for the plain tag-push trigger).
```

with:

```
- Artifact names derive the version from the tag (`${TAG#v}`); the `MLIR_VERSION` env is
  removed from `build.yml` entirely (see Addendum — workflow commits may not touch
  workflow files).
```

- [ ] **Step 2: Append the addendum section at the end of the spec**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-10-automated-release-pipeline-design.md
git commit -m "spec: confirmed root cause (workflow-file push restriction), move version to LLVM_VERSION file"
```

---

### Task 2: `LLVM_VERSION` file + rewrite `build.yml`

**Files:**
- Create: `LLVM_VERSION`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Produces: `build.yml` callable as a reusable workflow with `inputs.tag` (string, required, e.g. `v22.1.8`) — Tasks 3 and 4 call it with exactly `with: tag: <tag>`. `LLVM_VERSION` file containing the bare version (`22.1.8`), read by Tasks 3 and 4 via `tr -d '[:space:]' < LLVM_VERSION`.

- [ ] **Step 1: Create the version file**

```bash
printf '22.1.8\n' > LLVM_VERSION
```

- [ ] **Step 2: Replace `.github/workflows/build.yml` with this exact content**

Changes vs. current: `workflow_call`/`workflow_dispatch` gain a required `tag` input; workflow-level `RELEASE_TAG` env replaces `MLIR_VERSION`; every checkout pins `ref: RELEASE_TAG`; the dead deprecated "Set output vars" steps (`::set-output`, referenced nowhere) are removed; compress steps derive the version from the tag and export `MLIR_VERSION` to `GITHUB_ENV` so the Release step can name files exactly; Release steps get an explicit `tag_name` (fixes the latent workflow_call bug where `github.ref` is a branch).

```yaml
name: NES MLIR builder

on:
  push:
    tags:
      - 'v*'
  workflow_call:
    inputs:
      tag:
        description: 'Release tag to build (e.g. v22.1.8)'
        required: true
        type: string
  workflow_dispatch:
    inputs:
      tag:
        description: 'Existing release tag to build (e.g. v22.1.8)'
        required: true

env:
  RELEASE_TAG: ${{ inputs.tag || github.ref_name }}

jobs:
  build-x64-linux:
    timeout-minutes: 360
    env:
      VCPKG_DEP_LIST: x64-linux
      VCPKG_FEATURE_FLAGS: -binarycaching
    runs-on: [self-hosted, linux, x64]
    strategy:
      fail-fast: false
      matrix:
        osversion: [ubuntu-22.04, ubuntu-24.04]
    steps:
      - uses: AutoModality/action-clean@v1
      - uses: actions/checkout@v2
        with:
          ref: ${{ env.RELEASE_TAG }}
          submodules: 'recursive'
      - name: Build Docker
        id: builddocker
        working-directory: ${{ github.workspace }}/docker/
        run: docker build  -t nes_mlir_build_${{ matrix.osversion }} -f Dockerfile-${{ matrix.osversion }} .
      - name: Build MLIR
        id: installdeps
        run: |
          docker run -v ${{ github.workspace }}:/build_dir --rm nes_mlir_build_${{ matrix.osversion }} \
          ./build_dir/build_ubuntu-x64.sh
      - name: Compress artifacts
        id: compressdeps
        run: |
          MLIR_VERSION="${RELEASE_TAG#v}"
          echo "MLIR_VERSION=${MLIR_VERSION}" >> "$GITHUB_ENV"
          tar -czf "mlir-${MLIR_VERSION}-${{ matrix.osversion }}-X64.tar.gz" mlir
      - name: Release
        uses: softprops/action-gh-release@v1
        id: createrelease
        with:
          tag_name: ${{ env.RELEASE_TAG }}
          files: |
            mlir-${{ env.MLIR_VERSION }}-${{ matrix.osversion }}-X64.tar.gz
      - name: Clean build artifacts
        id: cleanbuildartifacts
        if: always()
        run: |
          rm -rf llvm-project
          rm -rf .git
          rm -rf mlir
      - name: Remove docker image
        id: removedockerimage
        if: always()
        run: |
          test -n "$(docker image ls -q nes_mlir_build_${{ matrix.osversion }})" && \
          docker image rm $(docker image ls -q nes_mlir_build_${{ matrix.osversion }}) || \
          true
  build-arm-linux:
    env:
      VCPKG_DEP_LIST: arm64-linux
      VCPKG_FEATURE_FLAGS: -binarycaching
    runs-on: [self-hosted, linux, arm64]
    strategy:
      matrix:
        osversion: [ubuntu-22.04, ubuntu-24.04]
    steps:
      - uses: AutoModality/action-clean@v1
      - uses: actions/checkout@v2
        with:
          ref: ${{ env.RELEASE_TAG }}
          submodules: 'recursive'
      - name: Build Docker
        id: builddocker
        working-directory: ${{ github.workspace }}/docker/
        run: docker build  -t nes_mlir_build_${{ matrix.osversion }} -f Dockerfile-${{ matrix.osversion }} .
      - name: Build MLIR
        id: installdeps
        run: |
          docker run -v ${{ github.workspace }}:/build_dir --rm nes_mlir_build_${{ matrix.osversion }} \
          ./build_dir/build_ubuntu-arm64.sh
      - name: Compress artifacts
        id: compressdeps
        run: |
          MLIR_VERSION="${RELEASE_TAG#v}"
          echo "MLIR_VERSION=${MLIR_VERSION}" >> "$GITHUB_ENV"
          tar -czf "mlir-${MLIR_VERSION}-${{ matrix.osversion }}-arm64.tar.gz" mlir
      - name: Release
        uses: softprops/action-gh-release@v1
        id: createrelease
        with:
          tag_name: ${{ env.RELEASE_TAG }}
          files: |
            mlir-${{ env.MLIR_VERSION }}-${{ matrix.osversion }}-arm64.tar.gz
      - name: Clean build artifacts
        id: cleanbuildartifacts
        if: always()
        run: |
          rm -rf mlir
          rm -rf llvm-project
          rm -rf .git
      - name: Remove docker image
        id: removedockerimage
        if: always()
        run: |
          test -n "$(docker image ls -q nes_mlir_build_${{ matrix.osversion }})" && \
          docker image rm $(docker image ls -q nes_mlir_build_${{ matrix.osversion }}) || \
          true
  build-arm-osx:
    timeout-minutes: 360
    env:
      VCPKG_DEP_LIST: arm64-osx
      VCPKG_FEATURE_FLAGS: -binarycaching
    runs-on: [macos-15]
    steps:
      - uses: lukka/get-cmake@latest
      - uses: actions/checkout@v2
        with:
          ref: ${{ env.RELEASE_TAG }}
          submodules: 'recursive'
      - name: Build OSX ARM MLIR
        id: buildmlir
        run: |
          ${{ github.workspace }}/build_osx-arm64.sh
        shell: bash
      - name: Compress artifacts
        id: compressdeps
        run: |
          MLIR_VERSION="${RELEASE_TAG#v}"
          echo "MLIR_VERSION=${MLIR_VERSION}" >> "$GITHUB_ENV"
          tar -czf "mlir-${MLIR_VERSION}-osx-arm64.tar.gz" mlir
      - name: Release
        uses: softprops/action-gh-release@v1
        id: createrelease
        with:
          tag_name: ${{ env.RELEASE_TAG }}
          files: |
            mlir-${{ env.MLIR_VERSION }}-osx-arm64.tar.gz
      - name: Clean build artifacts
        id: cleanbuildartifacts
        if: always()
        run: |
          rm -rf mlir
```

- [ ] **Step 3: Lint**

```bash
command -v actionlint >/dev/null || brew install actionlint
actionlint .github/workflows/build.yml
```

Expected: no output (exit 0). Note: `shellcheck` warnings about `${{ }}` interpolation in run blocks pre-exist in this repo's style; only fix findings introduced by this change.

- [ ] **Step 4: Verify no stale references remain**

```bash
grep -n "MLIR_VERSION:" .github/workflows/build.yml; echo "exit=$?"
grep -n "set-output" .github/workflows/build.yml; echo "exit=$?"
```

Expected: both greps print nothing, `exit=1`.

- [ ] **Step 5: Commit**

```bash
git add LLVM_VERSION .github/workflows/build.yml
git commit -m "build: take release tag as input, derive version from tag, add LLVM_VERSION file"
```

---

### Task 3: Rewrite `bump-llvm.yml` as the full pipeline

**Files:**
- Modify: `.github/workflows/bump-llvm.yml` (full replacement)

**Interfaces:**
- Consumes: `build.yml` `workflow_call` with `inputs.tag` (Task 2); `LLVM_VERSION` file (Task 2).
- Produces: weekly + dispatchable pipeline. Reconciler semantics: bump commit iff file version ≠ target version; tag + build iff tag `v<target>` missing on origin. So a deleted tag gets re-created and rebuilt, and dispatching with the current version after a test downgrade bumps `main` back without rebuilding.

- [ ] **Step 1: Replace `.github/workflows/bump-llvm.yml` with this exact content**

```yaml
name: Bump LLVM and Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'LLVM version (e.g. 22.1.9). Leave empty to auto-detect latest.'
        required: false
        default: ''
  schedule:
    # Run weekly on Monday at 08:00 UTC
    - cron: '0 8 * * 1'

permissions:
  contents: write

jobs:
  bump:
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.plan.outputs.tag }}
      proceed: ${{ steps.plan.outputs.proceed }}
    steps:
      - uses: actions/checkout@v4

      - name: Determine target LLVM version
        id: plan
        run: |
          set -euo pipefail
          LLVM_REPO=https://github.com/llvm/llvm-project

          if [ -n "${{ github.event.inputs.version }}" ]; then
            NEW_VERSION="${{ github.event.inputs.version }}"
          else
            NEW_VERSION=$(git ls-remote --tags "$LLVM_REPO" \
              | awk '{print $2}' \
              | grep -E '^refs/tags/llvmorg-[0-9]+\.[0-9]+\.[0-9]+$' \
              | sed 's|refs/tags/llvmorg-||' \
              | sort -V | tail -1)
          fi

          # Peeled commit SHA of the (annotated) upstream tag; fall back to
          # the plain ref in case it is a lightweight tag.
          LLVM_SHA=$(git ls-remote "$LLVM_REPO" "refs/tags/llvmorg-${NEW_VERSION}^{}" | awk '{print $1}')
          if [ -z "$LLVM_SHA" ]; then
            LLVM_SHA=$(git ls-remote "$LLVM_REPO" "refs/tags/llvmorg-${NEW_VERSION}" | awk '{print $1}')
          fi
          if [ -z "$LLVM_SHA" ]; then
            echo "::error::No tag llvmorg-${NEW_VERSION} found upstream"
            exit 1
          fi

          CURRENT_VERSION=$(tr -d '[:space:]' < LLVM_VERSION)
          TAG="v${NEW_VERSION}"

          if [ "${CURRENT_VERSION}" = "${NEW_VERSION}" ]; then
            BUMP=false
          else
            BUMP=true
          fi

          if git ls-remote --exit-code origin "refs/tags/${TAG}" >/dev/null; then
            PROCEED=false
            echo "Tag ${TAG} already exists — no release to create."
          else
            PROCEED=true
          fi

          {
            echo "new=${NEW_VERSION}"
            echo "sha=${LLVM_SHA}"
            echo "tag=${TAG}"
            echo "bump=${BUMP}"
            echo "proceed=${PROCEED}"
          } >> "$GITHUB_OUTPUT"
          echo "current=${CURRENT_VERSION} target=${NEW_VERSION} bump=${BUMP} tag=${TAG} create=${PROCEED}"

      - name: Commit version bump to main
        if: steps.plan.outputs.bump == 'true'
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git update-index --cacheinfo "160000,${{ steps.plan.outputs.sha }},llvm-project"
          echo "${{ steps.plan.outputs.new }}" > LLVM_VERSION
          git add LLVM_VERSION
          git commit -m "bump LLVM to ${{ steps.plan.outputs.new }}"
          git push origin HEAD:main

      - name: Create and push release tag
        if: steps.plan.outputs.proceed == 'true'
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git tag -a "${{ steps.plan.outputs.tag }}" -m "Release ${{ steps.plan.outputs.tag }}"
          git push origin "${{ steps.plan.outputs.tag }}"

  build:
    needs: bump
    if: needs.bump.outputs.proceed == 'true'
    permissions:
      contents: write
    uses: ./.github/workflows/build.yml
    with:
      tag: ${{ needs.bump.outputs.tag }}
```

- [ ] **Step 2: Lint**

```bash
actionlint .github/workflows/bump-llvm.yml
```

Expected: no output (exit 0).

- [ ] **Step 3: Sanity-check the detection one-liner locally**

```bash
git ls-remote --tags https://github.com/llvm/llvm-project \
  | awk '{print $2}' \
  | grep -E '^refs/tags/llvmorg-[0-9]+\.[0-9]+\.[0-9]+$' \
  | sed 's|refs/tags/llvmorg-||' \
  | sort -V | tail -1
```

Expected: prints the latest LLVM release (currently `22.1.8`), no `llvmorg-` prefix, no `-rc` suffixes.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/bump-llvm.yml
git commit -m "bump-llvm: full pipeline — detect, commit to main, tag, chained build"
```

---

### Task 4: Fix `create-release.yml`

**Files:**
- Modify: `.github/workflows/create-release.yml`

**Interfaces:**
- Consumes: `build.yml` `workflow_call` `inputs.tag` (Task 2); `LLVM_VERSION` file (Task 2).
- Produces: working manual utility "tag whatever version is on main and build it".

- [ ] **Step 1: Apply three edits**

Edit 1 — the "Determine version" step reads the version file instead of grepping build.yml. Replace:

```yaml
            VERSION=$(grep -oP '^\s*MLIR_VERSION:\s*\K.*' .github/workflows/build.yml | tr -d '[:space:]')
```

with:

```yaml
            VERSION=$(tr -d '[:space:]' < LLVM_VERSION)
```

Edit 2 + 3 — the build job: fix the never-true condition (`steps.create.outcome == 'success'` renders as the string `"true"`, but the `if:` compared it to `'success'`, so the build was always skipped) and pass the tag through. Replace:

```yaml
  build:
    needs: create-tag
    if: needs.create-tag.outputs.created == 'success'
    uses: ./.github/workflows/build.yml
```

with:

```yaml
  build:
    needs: create-tag
    if: needs.create-tag.outputs.created == 'true'
    permissions:
      contents: write
    uses: ./.github/workflows/build.yml
    with:
      tag: ${{ needs.create-tag.outputs.tag }}
```

- [ ] **Step 2: Lint**

```bash
actionlint .github/workflows/create-release.yml
```

Expected: no output (exit 0).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/create-release.yml
git commit -m "create-release: fix always-false build condition, pass tag to build"
```

---

### Task 5: Verification and rollout

**Files:** none (behavioral verification)

- [ ] **Step 1: Full lint + cross-file consistency check**

```bash
actionlint
grep -rn "MLIR_VERSION:" .github/workflows/        # expect: no matches
grep -rn "LLVM_VERSION" .github/workflows/         # expect: bump-llvm.yml and create-release.yml read it
grep -n "tag:" .github/workflows/bump-llvm.yml .github/workflows/create-release.yml   # expect: both pass tag to build.yml
```

- [ ] **Step 2: Push the branch and open a PR to main**

```bash
git push -u origin automated-release-pipeline
gh pr create --title "Fully automatic LLVM release pipeline" --body "$(cat <<'EOF'
Makes the weekly LLVM bump → tag → build flow fully automatic, per
docs/superpowers/specs/2026-07-10-automated-release-pipeline-design.md.

- bump-llvm.yml is now the whole pipeline: detects the latest llvmorg release via
  ls-remote (no submodule clone), commits the bump directly to main, tags vX.Y.Z, and
  chains the 4-platform build via workflow_call in the same run.
- The version moves from build.yml to a root LLVM_VERSION file: GITHUB_TOKEN cannot push
  commits touching .github/workflows/ — the confirmed root cause of every failed Monday
  bump run since 2026-03-30.
- build.yml takes the release tag as an input (fixes the latent workflow_call release
  bug), derives artifact versions from the tag, and gains workflow_dispatch to rerun a
  single platform against an existing tag.
- create-release.yml: fixes the always-false build condition ("true" == 'success'),
  which is why tags v22.1.1/v22.1.8 exist without built releases.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

(Repo convention is PR merges to main; `main` is unprotected but reviewable history is kept.)

- [ ] **Step 3: After merge — safe no-op dispatch**

```bash
gh workflow run bump-llvm.yml
gh run watch $(gh run list --workflow=bump-llvm.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

Expected: green run; `bump` job logs `current=22.1.8 target=22.1.8 bump=false ... create=false` (tag v22.1.8 exists), `build` job skipped. This exercises detection, version-file read, and tag check without side effects.

- [ ] **Step 4 (optional, real E2E — needs user go-ahead, occupies self-hosted runners for hours): downgrade test**

```bash
gh workflow run bump-llvm.yml -f version=22.1.7
```

Expected: commit "bump LLVM to 22.1.7" on main, tag v22.1.7, 4-platform build starts, draft release v22.1.7 accumulates artifacts. Cleanup: cancel the build once one artifact uploaded, run the Delete Release Tag workflow with `22.1.7`, then `gh workflow run bump-llvm.yml -f version=22.1.8` — reconciler semantics bump main back to 22.1.8 with no rebuild (tag exists).

- [ ] **Step 5: Confirm the Monday schedule is armed**

```bash
gh workflow list   # "Bump LLVM and Release" must be listed as active
```

Real full-path validation happens automatically when LLVM ships the next patch release; the run will appear under the "Bump LLVM and Release" workflow with the build chained in the same run.
