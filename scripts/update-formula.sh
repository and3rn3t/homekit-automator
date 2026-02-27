#!/bin/bash
# Update Homebrew formula with the correct sha256 for a given release tag.
#
# Usage:
#   ./scripts/update-formula.sh v1.2.0
#   ./scripts/update-formula.sh v1.2.0 --dry-run
#
# This downloads the source tarball from GitHub, computes its sha256,
# and updates Formula/homekit-automator.rb in place.

set -euo pipefail

TAG="${1:?Usage: update-formula.sh <tag> [--dry-run]}"
DRY_RUN="${2:-}"

REPO="and3rn3t/homekit-automator"
TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"
FORMULA="Formula/homekit-automator.rb"

# Strip leading 'v' for version string
VERSION="${TAG#v}"

echo "==> Fetching tarball for ${TAG}..."
SHA256=$(curl -sL "$TARBALL_URL" | shasum -a 256 | awk '{print $1}')

if [[ "$SHA256" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
    echo "ERROR: Got empty file sha256 — tag ${TAG} may not exist yet"
    exit 1
fi

echo "    URL: $TARBALL_URL"
echo "    SHA256: $SHA256"
echo "    Version: $VERSION"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "(dry-run) Would update ${FORMULA}"
    exit 0
fi

# Update the formula
sed -i '' \
    -e "s|url \"https://github.com/${REPO}/archive/refs/tags/.*\"|url \"${TARBALL_URL}\"|" \
    -e "s|sha256 \".*\"|sha256 \"${SHA256}\"|" \
    -e "s|# TODO: Update sha256.*||" \
    "$FORMULA"

echo "==> Updated ${FORMULA}"
grep -E "url |sha256 " "$FORMULA"
