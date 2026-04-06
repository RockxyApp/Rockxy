#!/bin/bash
set -euo pipefail

# rockxy-doctor.sh — Release intelligence and readiness check.
#
# Read-only. Does not modify any files.
#
# Shows: branch eligibility, last release, categorized changes,
# proposed version/build numbers, environment checks, validation checks,
# and a final READY / NOT READY verdict.
#
# Usage:
#   scripts/rockxy-doctor.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/_release-common.sh"
source "$SCRIPT_DIR/_release-intelligence.sh"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

BLOCKERS=0

blocker() {
    echo -e "  ${RED}BLOCKER${NC}  $1"
    BLOCKERS=$((BLOCKERS + 1))
}

warn() {
    echo -e "  ${YELLOW}WARNING${NC}  $1"
}

ok() {
    echo -e "  ${GREEN}OK${NC}       $1"
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}==> Rockxy Release Doctor${NC}"
echo ""

# ---------------------------------------------------------------------------
# 1. Branch & Eligibility
# ---------------------------------------------------------------------------

echo -e "${CYAN}Branch & Eligibility${NC}"
echo "─────────────────────────────────────────────"

CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
echo -e "  Branch:     ${BOLD}$CURRENT_BRANCH${NC}"

if [ "$CURRENT_BRANCH" = "main" ]; then
    ok "On main branch — eligible for release"
else
    blocker "Not on main branch. Merge develop into main first, then run from main."
fi

# Check working tree clean
if git -C "$PROJECT_DIR" diff --quiet HEAD 2>/dev/null && \
   git -C "$PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    ok "Working tree is clean"
else
    blocker "Working tree has uncommitted changes. Commit or stash first."
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Last Release
# ---------------------------------------------------------------------------

echo -e "${CYAN}Last Release${NC}"
echo "─────────────────────────────────────────────"

LAST_TAG="$(find_last_release_tag)"
LAST_INFO="$(last_release_info)"

if [ -z "$LAST_TAG" ]; then
    echo -e "  ${DIM}No prior release tag found. This will be the first release.${NC}"
    echo -e "  Current xcconfig:  $(read_xcconfig_value "$VERSIONS_XCCONFIG_PATH" "ROCKXY_APP_VERSION") (build $(read_xcconfig_value "$VERSIONS_XCCONFIG_PATH" "ROCKXY_APP_BUILD"))"
else
    read -r _tag _ver _build _date _sha <<< "$LAST_INFO"
    echo -e "  Last release:  ${BOLD}$_ver${NC}  (build $_build)  —  $_date  [$_sha]"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Changes Since Last Release
# ---------------------------------------------------------------------------

echo -e "${CYAN}Changes Since Last Release${NC}"
echo "─────────────────────────────────────────────"

COMMIT_COUNT="$(commit_count_since_tag "$LAST_TAG")"
echo -e "  Commits:  ${BOLD}$COMMIT_COUNT${NC}"

if [ "$COMMIT_COUNT" -eq 0 ]; then
    blocker "No commits since last release. Nothing to ship."
    echo ""
else
    echo ""

    BREAKING="$(commits_breaking "$LAST_TAG")"
    FEAT="$(commits_feat "$LAST_TAG")"
    FIX="$(commits_fix "$LAST_TAG")"
    OTHER="$(commits_other "$LAST_TAG")"

    if [ -n "$BREAKING" ]; then
        echo -e "  ${RED}Breaking Changes:${NC}"
        while IFS= read -r line; do
            echo "    - $line"
        done <<< "$BREAKING"
        echo ""
    fi

    if [ -n "$FEAT" ]; then
        echo -e "  ${GREEN}Added (feat):${NC}"
        while IFS= read -r line; do
            echo "    - $line"
        done <<< "$FEAT"
        echo ""
    fi

    if [ -n "$FIX" ]; then
        echo -e "  ${YELLOW}Fixed (fix):${NC}"
        while IFS= read -r line; do
            echo "    - $line"
        done <<< "$FIX"
        echo ""
    fi

    if [ -n "$OTHER" ]; then
        echo -e "  ${DIM}Changed (other):${NC}"
        while IFS= read -r line; do
            echo "    - $line"
        done <<< "$OTHER"
        echo ""
    fi
fi

# ---------------------------------------------------------------------------
# 4. Helper Analysis
# ---------------------------------------------------------------------------

echo -e "${CYAN}Helper Analysis${NC}"
echo "─────────────────────────────────────────────"

if [ -z "$LAST_TAG" ]; then
    # First release — all files are new, not "changed"
    echo -e "  First release:   helper included as-is (version $(read_xcconfig_value "$VERSIONS_XCCONFIG_PATH" "ROCKXY_HELPER_VERSION"), build $(read_xcconfig_value "$VERSIONS_XCCONFIG_PATH" "ROCKXY_HELPER_BUILD"))"
    echo -e "  Protocol:        $(read_xcconfig_value "$VERSIONS_XCCONFIG_PATH" "ROCKXY_HELPER_PROTOCOL_VERSION") (initial)"
else
    HELPER_FILES="$(helper_changed_files "$LAST_TAG")"
    if [ -n "$HELPER_FILES" ]; then
        echo -e "  Helper changed:  ${BOLD}yes${NC}"
        while IFS= read -r f; do
            echo -e "    ${DIM}$f${NC}"
        done <<< "$HELPER_FILES"
    else
        echo -e "  Helper changed:  no"
    fi

    if protocol_file_changed "$LAST_TAG"; then
        if protocol_has_breaking_marker "$LAST_TAG"; then
            echo -e "  Protocol:        ${RED}breaking marker found — will bump protocol version${NC}"
        elif protocol_needs_review "$LAST_TAG"; then
            warn "Protocol file changed without breaking marker. Review required."
            echo -e "                   If this is a breaking protocol change, add 'protocol!' to a commit"
            echo -e "                   or pass --protocol-bump to rockxy-release.sh"
        fi
    else
        echo -e "  Protocol:        unchanged"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Proposed Next Release
# ---------------------------------------------------------------------------

echo -e "${CYAN}Proposed Next Release${NC}"
echo "─────────────────────────────────────────────"

if [ "$COMMIT_COUNT" -gt 0 ]; then
    compute_next_versions "$LAST_TAG"

    BUMP_REASON=""
    case "$BUMP_TYPE" in
        first) BUMP_REASON="first release — using xcconfig values" ;;
        major) BUMP_REASON="breaking changes detected" ;;
        minor) BUMP_REASON="new features detected" ;;
        patch) BUMP_REASON="fixes only" ;;
    esac

    echo -e "  App version:      ${BOLD}$NEXT_APP_VERSION${NC}  ($BUMP_REASON)"
    echo -e "  App build:        ${BOLD}$NEXT_APP_BUILD${NC}"
    echo -e "  Helper version:   ${BOLD}$NEXT_HELPER_VERSION${NC}  (mirrors app)"

    if $IS_FIRST_RELEASE; then
        echo -e "  Helper build:     ${BOLD}$NEXT_HELPER_BUILD${NC}  (included as-is for first release)"
    elif $HELPER_CHANGED; then
        echo -e "  Helper build:     ${BOLD}$NEXT_HELPER_BUILD${NC}  (helper files changed)"
    else
        echo -e "  Helper build:     $NEXT_HELPER_BUILD  (unchanged)"
    fi

    if $PROTOCOL_BUMP; then
        echo -e "  Protocol version: ${BOLD}$NEXT_PROTOCOL_VERSION${NC}  (breaking marker found)"
    elif $PROTOCOL_REVIEW_NEEDED; then
        echo -e "  Protocol version: $NEXT_PROTOCOL_VERSION  ${YELLOW}(review required)${NC}"
    else
        echo -e "  Protocol version: $NEXT_PROTOCOL_VERSION  (unchanged)"
    fi
else
    echo -e "  ${DIM}No commits — nothing to propose.${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# 6. Website Readiness
# ---------------------------------------------------------------------------

echo -e "${CYAN}Website Readiness${NC}"
echo "─────────────────────────────────────────────"

if web_repo_exists; then
    ok "RockxyWeb repo found at $WEB_PROJECT_DIR"
else
    blocker "RockxyWeb repo not found at $WEB_PROJECT_DIR"
fi

WEB_BRANCH="$(web_current_branch)"
if [ "${WEB_BRANCH:-}" = "$WEB_REQUIRED_BRANCH" ]; then
    ok "RockxyWeb on $WEB_REQUIRED_BRANCH branch"
else
    blocker "RockxyWeb must be on $WEB_REQUIRED_BRANCH. Current branch: ${WEB_BRANCH:-unknown}"
fi

if web_repo_exists && web_worktree_clean; then
    ok "RockxyWeb working tree is clean"
elif web_repo_exists; then
    blocker "RockxyWeb has uncommitted changes. Commit or stash first."
fi

if web_repo_exists; then
    if "$SCRIPT_DIR/release-verify-web.sh" --web-dir "$WEB_PROJECT_DIR" > /dev/null 2>&1; then
        ok "RockxyWeb universal download pages are ready for Apple Silicon and Intel"
    else
        blocker "RockxyWeb universal download pages are stale or Intel is still disabled"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# 7. Changelog Sync
# ---------------------------------------------------------------------------

echo -e "${CYAN}Changelog Sync${NC}"
echo "─────────────────────────────────────────────"

CHANGELOG_LATEST_VERSION="$(latest_changelog_version "$PROJECT_DIR/CHANGELOG.md")"
DOCS_CHANGELOG_LATEST_VERSION="$(latest_docs_changelog_version "$PROJECT_DIR/docs/changelog.mdx")"

if [ -n "$CHANGELOG_LATEST_VERSION" ] && [ "$CHANGELOG_LATEST_VERSION" = "$DOCS_CHANGELOG_LATEST_VERSION" ]; then
    ok "docs/changelog.mdx matches latest release version ($CHANGELOG_LATEST_VERSION)"
else
    blocker "docs/changelog.mdx is out of sync with CHANGELOG.md (CHANGELOG=$CHANGELOG_LATEST_VERSION, docs=${DOCS_CHANGELOG_LATEST_VERSION:-missing})"
fi

echo ""

# ---------------------------------------------------------------------------
# 8. Environment Checks
# ---------------------------------------------------------------------------

echo -e "${CYAN}Environment${NC}"
echo "─────────────────────────────────────────────"

ENV_PASS=0
ENV_FAIL=0

env_check() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${NC}  $label"
        ENV_PASS=$((ENV_PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}  $label"
        ENV_FAIL=$((ENV_FAIL + 1))
        BLOCKERS=$((BLOCKERS + 1))
    fi
}

env_check "Xcode command-line tools installed" xcode-select -p
env_check "xcodebuild available" xcodebuild -version

check_signing_identity() {
    security find-identity -v -p codesigning | grep -q "Developer ID Application:"
}
env_check "Developer ID Application identity" check_signing_identity

env_check "Versions.xcconfig exists" test -f "$VERSIONS_XCCONFIG_PATH"

check_versions_parseable() {
    grep -q "^ROCKXY_APP_VERSION " "$VERSIONS_XCCONFIG_PATH" && \
    grep -q "^ROCKXY_APP_BUILD " "$VERSIONS_XCCONFIG_PATH" && \
    grep -q "^ROCKXY_HELPER_VERSION " "$VERSIONS_XCCONFIG_PATH" && \
    grep -q "^ROCKXY_HELPER_BUILD " "$VERSIONS_XCCONFIG_PATH" && \
    grep -q "^ROCKXY_HELPER_PROTOCOL_VERSION " "$VERSIONS_XCCONFIG_PATH"
}
env_check "Versions.xcconfig parseable" check_versions_parseable

env_check "Developer.xcconfig exists" test -f "$DEVELOPER_XCCONFIG_PATH"

check_team_id() {
    [ -n "$(developer_team_id)" ]
}
env_check "Developer.xcconfig has team ID" check_team_id

check_release_identity_config() {
    local identity
    identity="$(developer_code_sign_identity)"
    require_developer_id_application_identity "$identity"
}
env_check "Developer ID Application resolved for release" check_release_identity_config

env_check "swiftlint available" swiftlint version
env_check "GitHub CLI (gh) available" gh --version
env_check "hdiutil available" hdiutil info
env_check "lipo available" which lipo
env_check "notarytool available" xcrun notarytool --version

echo ""

# ---------------------------------------------------------------------------
# 9. Validation
# ---------------------------------------------------------------------------

echo -e "${CYAN}Validation${NC}"
echo "─────────────────────────────────────────────"

validation_check() {
    local label="$1"
    shift

    echo -e "  ${DIM}Running:${NC} $label"
    if "$@"; then
        echo -e "  ${GREEN}PASS${NC}  $label"
    else
        echo -e "  ${RED}FAIL${NC}  $label"
        BLOCKERS=$((BLOCKERS + 1))
    fi
    echo ""
}

validation_check \
    "SwiftLint strict" \
    swiftlint lint --strict

validation_check \
    "macOS test suite" \
    xcodebuild -project "$PROJECT_DIR/Rockxy.xcodeproj" \
        -scheme Rockxy \
        -destination "platform=macOS" \
        test

# ---------------------------------------------------------------------------
# 10. Verdict
# ---------------------------------------------------------------------------

echo "═════════════════════════════════════════════"
if [ "$BLOCKERS" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}READY TO RELEASE${NC}"
    echo ""
    echo "  Next step:"
    echo "    scripts/rockxy-release.sh"
    echo "    scripts/rockxy-release.sh --confirm"
    echo "    scripts/rockxy-publish.sh"
    echo "    scripts/rockxy-publish.sh --confirm"
else
    echo -e "  ${RED}${BOLD}NOT READY${NC}  —  $BLOCKERS blocker(s) found"
    echo ""
    echo "  Fix the issues above and re-run this script."
fi
echo "═════════════════════════════════════════════"
echo ""

if [ "$BLOCKERS" -gt 0 ]; then
    exit 1
fi
