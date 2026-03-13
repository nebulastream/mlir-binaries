#!/bin/bash
set -euo pipefail

# Script to bump the llvm-project submodule to the latest LLVM release tag.
# Usage: ./bump_llvm.sh [version]
#   If version is not provided, the latest llvmorg-* release tag is fetched automatically.

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SUBMODULE_PATH="${REPO_ROOT}/llvm-project"
BUILD_WORKFLOW="${REPO_ROOT}/.github/workflows/build.yml"

cd "${SUBMODULE_PATH}"

echo "Fetching tags from llvm-project upstream..."
git fetch origin --tags

if [ -n "${1:-}" ]; then
    NEW_VERSION="$1"
else
    # Find the latest stable llvmorg-X.Y.Z tag (exclude rc tags)
    NEW_VERSION=$(git tag -l 'llvmorg-*' \
        | grep -E '^llvmorg-[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V \
        | tail -1 \
        | sed 's/^llvmorg-//')

    if [ -z "${NEW_VERSION}" ]; then
        echo "ERROR: Could not determine latest LLVM release tag."
        exit 1
    fi
fi

TAG="llvmorg-${NEW_VERSION}"

# Read current version from build.yml
CURRENT_VERSION=$(grep -oP '^\s*MLIR_VERSION:\s*\K.*' "${BUILD_WORKFLOW}" | tr -d '[:space:]')

if [ "${CURRENT_VERSION}" = "${NEW_VERSION}" ]; then
    echo "Already at LLVM ${NEW_VERSION}. Nothing to do."
    exit 0
fi

echo "Bumping LLVM from ${CURRENT_VERSION} to ${NEW_VERSION} (tag: ${TAG})"

# Verify the tag exists
if ! git rev-parse "${TAG}" >/dev/null 2>&1; then
    echo "ERROR: Tag ${TAG} does not exist in llvm-project."
    exit 1
fi

# Reset submodule to the new release tag
git reset --hard "${TAG}"

# Update MLIR_VERSION in build.yml
cd "${REPO_ROOT}"
sed -i "s/^  MLIR_VERSION: .*/  MLIR_VERSION: ${NEW_VERSION}/" "${BUILD_WORKFLOW}"

echo ""
echo "Done. Summary of changes:"
echo "  - llvm-project submodule reset to ${TAG}"
echo "  - MLIR_VERSION updated to ${NEW_VERSION} in build.yml"
echo ""
echo "Next steps:"
echo "  git add llvm-project .github/workflows/build.yml"
echo "  git commit -m 'update to llvm ${NEW_VERSION}'"
echo "  git tag v${NEW_VERSION}"
