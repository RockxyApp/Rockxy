#!/bin/bash
set -euo pipefail

# rockxy-publish.sh — Publish a prepared release: tag, GitHub Release, upload.
#
# Default: dry run.
# With --confirm: publish for real.
#
# Usage:
#   scripts/rockxy-publish.sh
#   scripts/rockxy-publish.sh --confirm

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/_release-common.sh"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

CONFIRM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --confirm) CONFIRM=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--confirm]"
            echo ""
            echo "  Default:    Dry run — show what will be published"
            echo "  --confirm   Publish for real"
            exit 0
            ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_URL="https://github.com/LocNguyenHuu/Rockxy"
REPO_SLUG="LocNguyenHuu/Rockxy"
CHANNEL="community-prod"
CHANNEL_DIR="$PROJECT_DIR/build/release/$CHANNEL"
WEB_PROJECT_DIR="${ROCKXY_WEB_DIR:-$(cd "$PROJECT_DIR/.." && pwd)/RockxyWeb}"
WEB_REQUIRED_BRANCH="develop"

# ---------------------------------------------------------------------------
# Find and verify prepared artifacts
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}==> Rockxy Publish${NC}"
echo ""

MANIFEST_PATH="$CHANNEL_DIR/manifest.json"

if [ ! -f "$MANIFEST_PATH" ]; then
    echo -e "${RED}Error: No prepared release found at $CHANNEL_DIR/manifest.json${NC}"
    echo "  Run scripts/rockxy-release.sh first."
    exit 1
fi

# Parse manifest
read_manifest() {
    python3 -c "import json; print(json.load(open('$MANIFEST_PATH'))['$1'])"
}

APP_VERSION="$(read_manifest "appVersion")"
APP_BUILD="$(read_manifest "appBuild")"
GIT_COMMIT="$(read_manifest "gitCommit")"
DMG_FILENAME="$(read_manifest "dmgFilename")"
EXPECTED_SHA256="$(read_manifest "sha256")"

TAG="v${APP_VERSION}"
DMG_PATH="$CHANNEL_DIR/$DMG_FILENAME"
SHA_PATH="$CHANNEL_DIR/${DMG_FILENAME}.sha256"
NOTES_PATH="$CHANNEL_DIR/release-notes.md"

# Verify DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo -e "${RED}Error: DMG not found at $DMG_PATH${NC}"
    exit 1
fi

# Verify SHA-256
echo -e "${CYAN}Verifying artifact integrity...${NC}"
ACTUAL_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo -e "${RED}Error: SHA-256 mismatch!${NC}"
    echo "  Expected: $EXPECTED_SHA256"
    echo "  Actual:   $ACTUAL_SHA256"
    echo "  The DMG may have been modified after preparation. Re-run rockxy-release.sh."
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  SHA-256 matches: ${ACTUAL_SHA256:0:16}..."

# Verify the commit in the manifest exists
if ! git -C "$PROJECT_DIR" cat-file -e "$GIT_COMMIT" 2>/dev/null; then
    echo -e "${RED}Error: Release commit $GIT_COMMIT not found in git history.${NC}"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  Release commit exists: ${GIT_COMMIT:0:12}"

# Publish must happen from main, with HEAD exactly at the prepared release commit.
CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Must publish from main branch. Current branch: $CURRENT_BRANCH${NC}"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  On main branch"

CURRENT_HEAD="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")"
if [ "$CURRENT_HEAD" != "$GIT_COMMIT" ]; then
    echo -e "${RED}Error: HEAD does not match the prepared release commit.${NC}"
    echo "  Prepared commit: ${GIT_COMMIT:0:12}"
    echo "  Current HEAD:    ${CURRENT_HEAD:0:12}"
    echo "  Re-run rockxy-release.sh or reset main to the prepared release commit before publishing."
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  HEAD matches prepared release commit"

if ! git -C "$PROJECT_DIR" diff --quiet HEAD 2>/dev/null || \
   ! git -C "$PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    echo -e "${RED}Error: Working tree has uncommitted changes. Commit or stash first.${NC}"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  Working tree is clean"

# Check tag doesn't already exist
if git -C "$PROJECT_DIR" rev-parse "$TAG" > /dev/null 2>&1; then
    echo -e "${RED}Error: Tag $TAG already exists.${NC}"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  Tag $TAG is available"

echo ""

# ---------------------------------------------------------------------------
# Environment verification
# ---------------------------------------------------------------------------

echo -e "${CYAN}Verifying publish environment...${NC}"

ORIGIN_URL="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || echo "")"
if [[ "$ORIGIN_URL" != *"$REPO_SLUG"* ]]; then
    echo -e "${RED}Error: git remote 'origin' does not point to $REPO_SLUG.${NC}"
    echo "  Current origin: ${ORIGIN_URL:-<unset>}"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  origin points to $REPO_SLUG"

if ! gh auth status > /dev/null 2>&1; then
    echo -e "${RED}Error: gh is not authenticated.${NC}"
    echo "  Run: gh auth login"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  gh is authenticated"

if [ ! -d "$WEB_PROJECT_DIR/.git" ]; then
    echo -e "${RED}Error: RockxyWeb repo not found at $WEB_PROJECT_DIR${NC}"
    exit 1
fi

WEB_BRANCH="$(git -C "$WEB_PROJECT_DIR" branch --show-current 2>/dev/null || echo "")"
if [ "$WEB_BRANCH" != "$WEB_REQUIRED_BRANCH" ]; then
    echo -e "${RED}Error: RockxyWeb must be on $WEB_REQUIRED_BRANCH before publishing. Current branch: ${WEB_BRANCH:-<unknown>}${NC}"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  RockxyWeb is on $WEB_REQUIRED_BRANCH"

if ! git -C "$WEB_PROJECT_DIR" diff --quiet HEAD 2>/dev/null || \
   ! git -C "$WEB_PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    echo -e "${RED}Error: RockxyWeb has uncommitted changes. Commit or stash first.${NC}"
    exit 1
fi
echo -e "  ${GREEN}PASS${NC}  RockxyWeb working tree is clean"

echo ""

# ---------------------------------------------------------------------------
# Show publish plan
# ---------------------------------------------------------------------------

echo -e "${CYAN}Publish Plan${NC}"
echo "─────────────────────────────────────────────"
echo -e "  Version:    ${BOLD}$APP_VERSION${NC} (build $APP_BUILD)"
echo -e "  Tag:        ${BOLD}$TAG${NC}  at commit ${GIT_COMMIT:0:12}"
echo -e "  DMG:        $DMG_FILENAME"
echo -e "  Repo:       $REPO_SLUG"
echo ""
echo "  Will upload:"
echo "    - $DMG_FILENAME"
echo "    - ${DMG_FILENAME}.sha256"
echo "    - manifest.json"
echo "  Will push:"
echo "    - main (release-prep commit with updated CHANGELOG.md and Versions.xcconfig)"
echo "    - RockxyWeb develop (landing + download pages in all supported languages)"

if [ -f "$NOTES_PATH" ]; then
    echo "  Release notes from: $NOTES_PATH"
fi

echo "  RockxyWeb repo: $WEB_PROJECT_DIR"

echo ""

# ---------------------------------------------------------------------------
# Dry run — stop here
# ---------------------------------------------------------------------------

if ! $CONFIRM; then
    echo -e "${YELLOW}DRY RUN — nothing was published.${NC}"
    echo ""
    echo "  To publish this release: scripts/rockxy-publish.sh --confirm"
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Confirm mode — publish
# ---------------------------------------------------------------------------

echo -e "${BOLD}Publishing...${NC}"
echo ""

# Create and push tag (at the prepared release commit, NOT arbitrary HEAD)
echo -e "${YELLOW}==> Creating git tag $TAG at ${GIT_COMMIT:0:12}...${NC}"
TAG_PUSHED=false
RELEASE_CREATED=false
MANIFEST_BACKUP="$(mktemp)"
cp "$MANIFEST_PATH" "$MANIFEST_BACKUP"

git -C "$PROJECT_DIR" tag -a "$TAG" "$GIT_COMMIT" -m "Release $APP_VERSION (build $APP_BUILD)"
git -C "$PROJECT_DIR" push origin "$TAG"
TAG_PUSHED=true

echo -e "  ${GREEN}Tag $TAG pushed to origin.${NC}"

# Rollback function
rollback_tag() {
    if $TAG_PUSHED; then
        echo ""
        echo -e "${RED}==> Rolling back: deleting tag $TAG from local and remote...${NC}"
        git -C "$PROJECT_DIR" tag -d "$TAG" 2>/dev/null || true
        git -C "$PROJECT_DIR" push origin ":refs/tags/$TAG" 2>/dev/null || true
        echo -e "${YELLOW}  Tag $TAG deleted.${NC}"
    fi
}

rollback_release_and_tag() {
    echo ""
    echo -e "${RED}==> Rolling back published release state...${NC}"
    if $RELEASE_CREATED; then
        gh release delete "$TAG" --repo "$REPO_SLUG" --yes 2>/dev/null || true
    fi
    rollback_tag
    cp "$MANIFEST_BACKUP" "$MANIFEST_PATH"
    echo -e "${YELLOW}  Local manifest restored.${NC}"
}

# Build release notes flag
NOTES_FLAG=""
if [ -f "$NOTES_PATH" ]; then
    NOTES_FLAG="--notes-file $NOTES_PATH"
fi

# Create GitHub Release and upload artifacts
echo -e "${YELLOW}==> Creating GitHub Release...${NC}"
RELEASE_URL=""
if ! RELEASE_URL=$(gh release create "$TAG" \
    --repo "$REPO_SLUG" \
    --title "Rockxy $APP_VERSION (build $APP_BUILD)" \
    $NOTES_FLAG \
    "$DMG_PATH" \
    "$SHA_PATH" \
    "$MANIFEST_PATH" \
    2>&1); then
    echo -e "${RED}Error: GitHub Release creation failed:${NC}"
    echo "$RELEASE_URL"
    rollback_tag
    rm -f "$MANIFEST_BACKUP"
    exit 1
fi

RELEASE_CREATED=true
echo -e "  ${GREEN}Release created: $RELEASE_URL${NC}"

# Update manifest with real download URL
DOWNLOAD_URL="${REPO_URL}/releases/download/${TAG}/${DMG_FILENAME}"

python3 -c "
import json
with open('$MANIFEST_PATH', 'r') as f:
    m = json.load(f)
m['downloadURL'] = '$DOWNLOAD_URL'
with open('$MANIFEST_PATH', 'w') as f:
    json.dump(m, f, indent=2)
    f.write('\n')
"

# Upload updated manifest (replaces the placeholder version)
echo -e "${YELLOW}==> Uploading final manifest...${NC}"
if ! gh release upload "$TAG" \
    --repo "$REPO_SLUG" \
    --clobber \
    "$MANIFEST_PATH"; then
    echo -e "${RED}Error: Final manifest upload failed. Rolling back the release.${NC}"
    rollback_release_and_tag
    rm -f "$MANIFEST_BACKUP"
    exit 1
fi

# Push main so the release-prep commit updates remote CHANGELOG/version files too.
echo -e "${YELLOW}==> Pushing main branch...${NC}"
if ! git -C "$PROJECT_DIR" push origin main; then
    echo -e "${RED}Error: Failed to push main branch. Rolling back the published release.${NC}"
    rollback_release_and_tag
    rm -f "$MANIFEST_BACKUP"
    exit 1
fi

rm -f "$MANIFEST_BACKUP"

echo -e "${YELLOW}==> Syncing RockxyWeb...${NC}"
if ! "$SCRIPT_DIR/release-sync-web.sh" \
    --web-dir "$WEB_PROJECT_DIR" \
    --version "$APP_VERSION" \
    --build "$APP_BUILD"; then
    echo -e "${RED}Error: RockxyWeb sync failed after release publish.${NC}"
    echo "  The GitHub release is already live. Fix RockxyWeb and publish its develop branch manually."
    exit 1
fi

echo -e "${YELLOW}==> Committing RockxyWeb updates...${NC}"
git -C "$WEB_PROJECT_DIR" add \
    "index.html" \
    "download.html" \
    "compare.html" \
    "zh/index.html" \
    "zh/download.html" \
    "zh/compare.html" \
    "ja/index.html" \
    "ja/download.html" \
    "ja/compare.html" \
    "de/index.html" \
    "de/download.html" \
    "de/compare.html" \
    "fr/index.html" \
    "fr/download.html" \
    "fr/compare.html"

if git -C "$WEB_PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    echo "  RockxyWeb already matched the published release."
else
    if ! git -C "$WEB_PROJECT_DIR" commit -m "content: sync release website to v$APP_VERSION"; then
        echo -e "${RED}Error: Failed to commit RockxyWeb updates.${NC}"
        exit 1
    fi

    if ! git -C "$WEB_PROJECT_DIR" push origin "$WEB_REQUIRED_BRANCH"; then
        echo -e "${RED}Error: Failed to push RockxyWeb develop branch.${NC}"
        exit 1
    fi
fi

echo ""
echo "═════════════════════════════════════════════"
echo -e "  ${GREEN}${BOLD}Release published!${NC}"
echo ""
echo -e "  Tag:       $TAG"
echo -e "  Release:   $RELEASE_URL"
echo -e "  Download:  $DOWNLOAD_URL"
echo "═════════════════════════════════════════════"
echo ""
