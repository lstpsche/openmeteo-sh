#!/usr/bin/env bash
# release.sh — automate the full openmeteo-sh release process
#
# Usage:
#   ./scripts/release.sh <VERSION>
#
# Example:
#   ./scripts/release.sh 1.1.0
#
# What it does (in order):
#   1. Validates version format (X.Y.Z)
#   2. Bumps OPENMETEO_VERSION in lib/core.sh
#   3. Adds a debian/changelog entry
#   4. Commits the version bump (signed)
#   5. Creates a signed git tag
#   6. Pushes commit + tag to origin
#   7. Creates a GitHub release (requires `gh` CLI)
#   8. Downloads the tarball, computes SHA-256
#   9. Updates the Homebrew formula in the tap repo
#  10. Commits and pushes the tap repo
#
# Requirements:
#   - gh CLI (https://cli.github.com) — for creating the GitHub release
#   - GPG key configured for signed commits/tags
#   - TAP_REPO_PATH env var or ../homebrew-tap relative to this repo
#
# Environment variables:
#   TAP_REPO_PATH  — absolute path to the homebrew-tap repo
#                    (default: ../homebrew-tap relative to repo root)

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()   { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Resolve paths ───────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAP_REPO_PATH="${TAP_REPO_PATH:-${REPO_ROOT}/../homebrew-tap}"

# ── Validate arguments ──────────────────────────────────────────────────
VERSION="${1:-}"

if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 <VERSION>"
  echo "  e.g. $0 1.1.0"
  exit 1
fi

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Invalid version format '${VERSION}'. Expected X.Y.Z (e.g. 1.1.0)"
fi

CURRENT_VERSION=$(grep -oP 'OPENMETEO_VERSION="\K[^"]+' "${REPO_ROOT}/lib/core.sh" 2>/dev/null || true)
if [[ -z "${CURRENT_VERSION}" ]]; then
  # macOS grep doesn't support -P; try sed
  CURRENT_VERSION=$(sed -n 's/^OPENMETEO_VERSION="\(.*\)"/\1/p' "${REPO_ROOT}/lib/core.sh")
fi

if [[ "${VERSION}" == "${CURRENT_VERSION}" ]]; then
  die "Version ${VERSION} is already set in lib/core.sh. Nothing to release."
fi

# ── Pre-flight checks ──────────────────────────────────────────────────
step "Pre-flight checks"

command -v gh  >/dev/null 2>&1 || die "'gh' CLI not found. Install: https://cli.github.com"
command -v jq  >/dev/null 2>&1 || die "'jq' not found."
command -v git >/dev/null 2>&1 || die "'git' not found."

cd "${REPO_ROOT}"

# Ensure we're on main and clean
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "${BRANCH}" != "main" ]]; then
  warn "You're on branch '${BRANCH}', not 'main'. Proceeding anyway."
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "Working tree is dirty. Commit or stash your changes first."
fi

# Check tap repo exists
if [[ ! -d "${TAP_REPO_PATH}" ]]; then
  die "Homebrew tap repo not found at '${TAP_REPO_PATH}'.\n       Set TAP_REPO_PATH env var or clone it next to this repo."
fi

if [[ ! -f "${TAP_REPO_PATH}/Formula/openmeteo-sh.rb" ]]; then
  die "Formula not found at '${TAP_REPO_PATH}/Formula/openmeteo-sh.rb'"
fi

ok "All checks passed (current: ${CURRENT_VERSION} → new: ${VERSION})"

# ── Step 1: Bump version in lib/core.sh ─────────────────────────────────
step "1/7  Bumping version to ${VERSION}"

sed -i.bak "s/OPENMETEO_VERSION=\"${CURRENT_VERSION}\"/OPENMETEO_VERSION=\"${VERSION}\"/" \
  "${REPO_ROOT}/lib/core.sh"
rm -f "${REPO_ROOT}/lib/core.sh.bak"

ok "lib/core.sh updated"

# ── Step 2: Update debian/changelog ─────────────────────────────────────
step "2/7  Updating debian/changelog"

TIMESTAMP=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
CHANGELOG_ENTRY="openmeteo-sh (${VERSION}-1) stable; urgency=low

  * Release ${VERSION}.

 -- Nikita Shkoda <lstpsche@gmail.com>  ${TIMESTAMP}
"

# Prepend to existing changelog
EXISTING=$(cat "${REPO_ROOT}/debian/changelog")
printf '%s\n\n%s' "${CHANGELOG_ENTRY}" "${EXISTING}" > "${REPO_ROOT}/debian/changelog"

ok "debian/changelog updated"

# ── Step 3: Commit version bump ─────────────────────────────────────────
step "3/7  Committing version bump"

cd "${REPO_ROOT}"
git add lib/core.sh debian/changelog
git commit -S -m "chore: bump version to ${VERSION}"

ok "Committed"

# ── Step 4: Tag ─────────────────────────────────────────────────────────
step "4/7  Creating tag ${VERSION}"

git tag -s "${VERSION}" -m "Release ${VERSION}"

ok "Tag ${VERSION} created"

# ── Step 5: Push ────────────────────────────────────────────────────────
step "5/7  Pushing to origin"

git push origin main
git push origin "${VERSION}"

ok "Pushed commit and tag"

# ── Step 6: Create GitHub release ───────────────────────────────────────
step "6/7  Creating GitHub release"

gh release create "${VERSION}" \
  --repo lstpsche/openmeteo-sh \
  --title "v${VERSION}" \
  --generate-notes

ok "GitHub release created"

# Wait a moment for GitHub to generate the tarball
info "Waiting for GitHub to generate tarball..."
sleep 5

# ── Step 7: Update Homebrew tap ─────────────────────────────────────────
step "7/7  Updating Homebrew formula"

TARBALL_URL="https://github.com/lstpsche/openmeteo-sh/archive/refs/tags/${VERSION}.tar.gz"

info "Downloading tarball to compute SHA-256..."
SHA256=$(curl -sL "${TARBALL_URL}" | shasum -a 256 | awk '{print $1}')

if [[ -z "${SHA256}" || "${#SHA256}" -ne 64 ]]; then
  die "Failed to compute SHA-256. Check if the tarball is available:\n       ${TARBALL_URL}"
fi

ok "SHA-256: ${SHA256}"

cd "${TAP_REPO_PATH}"

# Pull latest
git pull --ff-only origin main 2>/dev/null || true

# Update URL and SHA in the formula
FORMULA="${TAP_REPO_PATH}/Formula/openmeteo-sh.rb"

sed -i.bak "s|url \"https://github.com/lstpsche/openmeteo-sh/archive/refs/tags/.*\.tar\.gz\"|url \"${TARBALL_URL}\"|" "${FORMULA}"
sed -i.bak "s|sha256 \"[a-f0-9]\{64\}\"|sha256 \"${SHA256}\"|" "${FORMULA}"
rm -f "${FORMULA}.bak"

info "Updated formula:"
grep -E '^\s*(url|sha256)' "${FORMULA}"

git add Formula/openmeteo-sh.rb
git commit -S -m "openmeteo-sh ${VERSION}"
git push origin main

ok "Homebrew tap updated and pushed"

# ── Done ────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✅ Release ${VERSION} complete!${NC}"
echo ""
echo "  Users can now run:"
echo "    brew update && brew upgrade openmeteo-sh"
echo ""
echo "  To also publish a .deb, run:"
echo "    docker run --rm -v \"\$(pwd)\":/src -w /src debian:bookworm bash -c '"
echo "      apt-get update && apt-get install -y build-essential debhelper devscripts &&"
echo "      dpkg-buildpackage -us -uc -b && cp ../openmeteo-sh_*.deb /src/'"
echo "    gh release upload ${VERSION} openmeteo-sh_${VERSION}-1_all.deb"
