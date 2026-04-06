#!/bin/bash
set -euo pipefail

# release-sync-web.sh — Sync release version/download links into RockxyWeb.
#
# Usage:
#   scripts/release-sync-web.sh --version 0.1.1 --build 2
#   scripts/release-sync-web.sh --version 0.1.1 --build 2 --web-dir /path/to/RockxyWeb

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VERSION=""
BUILD=""
WEB_DIR="${ROCKXY_WEB_DIR:-$(cd "$PROJECT_DIR/.." && pwd)/RockxyWeb}"
REPO_SLUG="LocNguyenHuu/Rockxy"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --build) BUILD="$2"; shift 2 ;;
        --web-dir) WEB_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 --version X.Y.Z --build N [--web-dir /path/to/RockxyWeb]"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo -e "${RED}Error: --version and --build are required.${NC}"
    exit 1
fi

if [ ! -d "$WEB_DIR/.git" ]; then
    echo -e "${RED}Error: RockxyWeb git repo not found at $WEB_DIR${NC}"
    exit 1
fi

WEB_BRANCH="$(git -C "$WEB_DIR" branch --show-current 2>/dev/null || echo "")"
if [ "$WEB_BRANCH" != "develop" ]; then
    echo -e "${RED}Error: RockxyWeb must be on develop branch before syncing. Current branch: ${WEB_BRANCH:-<unknown>}${NC}"
    exit 1
fi

if ! git -C "$WEB_DIR" diff --quiet HEAD 2>/dev/null || ! git -C "$WEB_DIR" diff --cached --quiet 2>/dev/null; then
    echo -e "${RED}Error: RockxyWeb has uncommitted changes. Commit or stash them before syncing.${NC}"
    exit 1
fi

echo "==> Sync RockxyWeb release metadata"
echo "  Web dir:  $WEB_DIR"
echo "  Branch:   $WEB_BRANCH"
echo "  Version:  $VERSION (build $BUILD)"
echo ""

python3 - <<'PY' "$WEB_DIR" "$VERSION" "$BUILD" "$REPO_SLUG"
import re
import sys
from pathlib import Path

web_dir = Path(sys.argv[1])
version = sys.argv[2]
build = sys.argv[3]
repo_slug = sys.argv[4]

tag = f"v{version}"
dmg_filename = f"Rockxy-{version}-{build}.dmg"
dmg_url = f"https://github.com/{repo_slug}/releases/download/{tag}/{dmg_filename}"
sha_url = f"{dmg_url}.sha256"
tag_url = f"https://github.com/{repo_slug}/releases/tag/{tag}"

relative_paths = [
    "index.html",
    "download.html",
    "compare.html",
    "zh/index.html",
    "zh/download.html",
    "zh/compare.html",
    "ja/index.html",
    "ja/download.html",
    "ja/compare.html",
    "de/index.html",
    "de/download.html",
    "de/compare.html",
    "fr/index.html",
    "fr/download.html",
    "fr/compare.html",
]

version_pattern = re.compile(r"v\d+\.\d+\.\d+")
dmg_url_pattern = re.compile(
    r"https://github\.com/LocNguyenHuu/Rockxy/releases/download/v\d+\.\d+\.\d+/Rockxy-\d+\.\d+\.\d+-\d+\.dmg"
)
sha_url_pattern = re.compile(
    r"https://github\.com/LocNguyenHuu/Rockxy/releases/download/v\d+\.\d+\.\d+/Rockxy-\d+\.\d+\.\d+-\d+\.dmg\.sha256"
)
tag_url_pattern = re.compile(
    r"https://github\.com/LocNguyenHuu/Rockxy/releases/tag/v\d+\.\d+\.\d+"
)
dmg_filename_pattern = re.compile(r"Rockxy-\d+\.\d+\.\d+-\d+\.dmg")
software_version_pattern = re.compile(r'("softwareVersion":\s*")[^"]+(")')

literal_replacements = {
    "index.html": [
        ("Apple Silicon native", "Universal: Apple Silicon + Intel"),
    ],
    "de/index.html": [
        ("Apple Silicon nativ", "Universal: Apple Silicon + Intel"),
    ],
    "fr/index.html": [
        ("Apple Silicon natif", "Universel : Apple Silicon + Intel"),
    ],
    "ja/index.html": [
        ("Apple Silicon ネイティブ", "ユニバーサル: Apple Silicon + Intel"),
    ],
    "zh/index.html": [
        ("Apple Silicon 原生", "通用版：Apple Silicon + Intel"),
    ],
    "download.html": [
        ("Apple Silicon native, macOS 14+.", "Universal for Apple Silicon and Intel, macOS 14+."),
        ("A free, open-source native HTTP debugging proxy. Apple Silicon native, macOS 14+.", "A free, open-source universal HTTP debugging proxy for Apple Silicon and Intel, macOS 14+."),
        ("<span>Apple Silicon</span>", "<span>Universal: Apple Silicon + Intel</span>"),
        ("Apple Silicon only", "Apple Silicon or Intel"),
    ],
    "de/download.html": [
        ("<span>Apple Silicon</span>", "<span>Universal: Apple Silicon + Intel</span>"),
        ("Apple Silicon only", "Apple Silicon oder Intel"),
    ],
    "fr/download.html": [
        ("<span>Apple Silicon</span>", "<span>Universel : Apple Silicon + Intel</span>"),
        ("Apple Silicon only", "Apple Silicon ou Intel"),
    ],
    "ja/download.html": [
        ("<span>Apple Silicon</span>", "<span>ユニバーサル: Apple Silicon + Intel</span>"),
        ("Apple Silicon only", "Apple Silicon または Intel"),
    ],
    "zh/download.html": [
        ("<span>Apple Silicon</span>", "<span>通用版：Apple Silicon + Intel</span>"),
        ("Apple Silicon only", "Apple Silicon 或 Intel"),
    ],
    "compare.html": [
        ('"name": "Does Rockxy work on Apple Silicon?"', '"name": "Does Rockxy work on Apple Silicon and Intel Macs?"'),
        ('"text": "Yes. Rockxy is built natively with SwiftUI and AppKit, and runs natively on Apple Silicon (M1, M2, M3, M4) without Rosetta translation."', '"text": "Yes. Rockxy is built with SwiftUI and AppKit, ships as a signed universal macOS app, and runs on both Apple Silicon and Intel Macs. On Apple Silicon, it runs natively without Rosetta translation."'),
        ("Does Rockxy work on Apple Silicon?", "Does Rockxy work on Apple Silicon and Intel Macs?"),
        ("Yes. Rockxy is built natively with SwiftUI and AppKit, and runs natively on Apple Silicon (M1, M2, M3, M4) without Rosetta translation.", "Yes. Rockxy is built with SwiftUI and AppKit, ships as a signed universal macOS app, and runs on both Apple Silicon and Intel Macs. On Apple Silicon, it runs natively without Rosetta translation."),
    ],
    "de/compare.html": [
        ('"name": "Does Rockxy work on Apple Silicon?"', '"name": "Does Rockxy work on Apple Silicon and Intel Macs?"'),
        ('"text": "Yes. Rockxy is built natively with SwiftUI and AppKit, and runs natively on Apple Silicon (M1, M2, M3, M4) without Rosetta translation."', '"text": "Yes. Rockxy is built with SwiftUI and AppKit, ships as a signed universal macOS app, and runs on both Apple Silicon and Intel Macs. On Apple Silicon, it runs natively without Rosetta translation."'),
        ("Funktioniert Rockxy auf Apple Silicon?", "Funktioniert Rockxy auf Apple Silicon und Intel-Macs?"),
        ("Ja. Rockxy ist nativ mit SwiftUI und AppKit entwickelt und läuft nativ auf Apple Silicon (M1, M2, M3, M4) ohne Rosetta-Übersetzung.", "Ja. Rockxy ist mit SwiftUI und AppKit entwickelt, wird als signierte universelle macOS-App ausgeliefert und läuft auf Apple-Silicon- und Intel-Macs. Auf Apple Silicon läuft es nativ ohne Rosetta-Übersetzung."),
    ],
    "fr/compare.html": [
        ('"name": "Does Rockxy work on Apple Silicon?"', '"name": "Does Rockxy work on Apple Silicon and Intel Macs?"'),
        ('"text": "Yes. Rockxy is built natively with SwiftUI and AppKit, and runs natively on Apple Silicon (M1, M2, M3, M4) without Rosetta translation."', '"text": "Yes. Rockxy is built with SwiftUI and AppKit, ships as a signed universal macOS app, and runs on both Apple Silicon and Intel Macs. On Apple Silicon, it runs natively without Rosetta translation."'),
        ("Rockxy fonctionne-t-il sur Apple Silicon ?", "Rockxy fonctionne-t-il sur les Mac Apple Silicon et Intel ?"),
        ("Oui. Rockxy est construit nativement avec SwiftUI et AppKit, et s'exécute nativement sur Apple Silicon (M1, M2, M3, M4) sans traduction Rosetta.", "Oui. Rockxy est développé avec SwiftUI et AppKit, distribué comme une app macOS universelle signée, et fonctionne sur les Mac Apple Silicon comme Intel. Sur Apple Silicon, il s'exécute nativement sans traduction Rosetta."),
    ],
    "ja/compare.html": [
        ('"name": "Does Rockxy work on Apple Silicon?"', '"name": "Does Rockxy work on Apple Silicon and Intel Macs?"'),
        ('"text": "Yes. Rockxy is built natively with SwiftUI and AppKit, and runs natively on Apple Silicon (M1, M2, M3, M4) without Rosetta translation."', '"text": "Yes. Rockxy is built with SwiftUI and AppKit, ships as a signed universal macOS app, and runs on both Apple Silicon and Intel Macs. On Apple Silicon, it runs natively without Rosetta translation."'),
        ("Rockxy は Apple Silicon で動作しますか?", "Rockxy は Apple Silicon と Intel Mac の両方で動作しますか?"),
        ("はい。Rockxy は SwiftUI と AppKit でネイティブに構築されており、Apple Silicon (M1、M2、M3、M4) 上で Rosetta 変換なしにネイティブで動作します。", "はい。Rockxy は SwiftUI と AppKit で構築され、署名済みのユニバーサル macOS アプリとして提供されており、Apple Silicon と Intel Mac の両方で動作します。Apple Silicon では Rosetta 変換なしでネイティブ動作します。"),
    ],
    "zh/compare.html": [
        ('"name": "Does Rockxy work on Apple Silicon?"', '"name": "Does Rockxy work on Apple Silicon and Intel Macs?"'),
        ('"text": "Yes. Rockxy is built natively with SwiftUI and AppKit, and runs natively on Apple Silicon (M1, M2, M3, M4) without Rosetta translation."', '"text": "Yes. Rockxy is built with SwiftUI and AppKit, ships as a signed universal macOS app, and runs on both Apple Silicon and Intel Macs. On Apple Silicon, it runs natively without Rosetta translation."'),
        ("Rockxy 支持 Apple Silicon 吗？", "Rockxy 支持 Apple Silicon 和 Intel Mac 吗？"),
        ("支持。Rockxy 使用 SwiftUI 和 AppKit 原生构建，在 Apple Silicon（M1、M2、M3、M4）上原生运行，无需 Rosetta 转译。", "支持。Rockxy 使用 SwiftUI 和 AppKit 构建，作为已签名的通用 macOS 应用发布，可在 Apple Silicon 和 Intel Mac 上运行。在 Apple Silicon 上无需 Rosetta 即可原生运行。"),
    ],
}

block_replacements = {
    "download.html": [
        (
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">Choose your architecture</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">Recommended</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <div class="relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center opacity-50 cursor-not-allowed">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-txt-secondary dark:bg-txt-dark-secondary text-white text-[11px] font-semibold tracking-wide">Coming soon</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1 text-txt-secondary dark:text-txt-dark-secondary">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </div>

      </div>
    </section>""",
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">Universal macOS download</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">Included</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-surface-alt dark:bg-surface-dark-alt border border-card-border dark:border-card-dark-border text-[11px] font-semibold tracking-wide">Included</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </a>

      </div>
      <p class="text-sm text-txt-secondary dark:text-txt-dark-secondary text-center mt-4">Both buttons download the same signed universal .dmg.</p>
    </section>""",
        ),
    ],
    "de/download.html": [
        (
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">Architektur wählen</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">Empfohlen</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <div class="relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center opacity-50 cursor-not-allowed">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-txt-secondary dark:bg-txt-dark-secondary text-white text-[11px] font-semibold tracking-wide">Demnächst</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1 text-txt-secondary dark:text-txt-dark-secondary">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </div>

      </div>
    </section>""",
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">Universeller macOS-Download</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">Enthalten</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-surface-alt dark:bg-surface-dark-alt border border-card-border dark:border-card-dark-border text-[11px] font-semibold tracking-wide">Enthalten</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </a>

      </div>
      <p class="text-sm text-txt-secondary dark:text-txt-dark-secondary text-center mt-4">Beide Schaltflächen laden dieselbe signierte universelle .dmg herunter.</p>
    </section>""",
        ),
    ],
    "fr/download.html": [
        (
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">Choisissez votre architecture</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">Recommandé</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <div class="relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center opacity-50 cursor-not-allowed">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-txt-secondary dark:bg-txt-dark-secondary text-white text-[11px] font-semibold tracking-wide">Bientôt</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1 text-txt-secondary dark:text-txt-dark-secondary">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </div>

      </div>
    </section>""",
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">Téléchargement macOS universel</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">Inclus</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-surface-alt dark:bg-surface-dark-alt border border-card-border dark:border-card-dark-border text-[11px] font-semibold tracking-wide">Inclus</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </a>

      </div>
      <p class="text-sm text-txt-secondary dark:text-txt-dark-secondary text-center mt-4">Les deux boutons téléchargent le même fichier .dmg universel signé.</p>
    </section>""",
        ),
    ],
    "ja/download.html": [
        (
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">アーキテクチャを選択</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">推奨</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <div class="relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center opacity-50 cursor-not-allowed">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-txt-secondary dark:bg-txt-dark-secondary text-white text-[11px] font-semibold tracking-wide">近日対応</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1 text-txt-secondary dark:text-txt-dark-secondary">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </div>

      </div>
    </section>""",
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">ユニバーサル macOS ダウンロード</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">同梱</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-surface-alt dark:bg-surface-dark-alt border border-card-border dark:border-card-dark-border text-[11px] font-semibold tracking-wide">同梱</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </a>

      </div>
      <p class="text-sm text-txt-secondary dark:text-txt-dark-secondary text-center mt-4">どちらのボタンでも同じ署名済みユニバーサル .dmg をダウンロードします。</p>
    </section>""",
        ),
    ],
    "zh/download.html": [
        (
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">选择架构</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">推荐</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <div class="relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center opacity-50 cursor-not-allowed">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-txt-secondary dark:bg-txt-dark-secondary text-white text-[11px] font-semibold tracking-wide">即将推出</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1 text-txt-secondary dark:text-txt-dark-secondary">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </div>

      </div>
    </section>""",
            """      <h2 class="font-display text-xl font-semibold tracking-tight text-center mb-6">通用 macOS 下载</h2>
      <div class="grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">

        <!-- Apple Silicon -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border-2 border-accent bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-accent text-white text-[11px] font-semibold tracking-wide">已包含</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt dark:text-txt-dark" fill="currentColor" viewBox="0 0 24 24"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <div class="font-semibold text-lg mb-1">Apple Silicon</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">M1 / M2 / M3 / M4</div>
        </a>

        <!-- Intel -->
        <a href="{dmg_url}" class="group relative block rounded-2xl border border-card-border dark:border-card-dark-border bg-card dark:bg-card-dark p-6 text-center hover:shadow-lg transition-all">
          <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 px-3 py-0.5 rounded-full bg-surface-alt dark:bg-surface-dark-alt border border-card-border dark:border-card-dark-border text-[11px] font-semibold tracking-wide">已包含</span>
          <svg class="w-10 h-10 mx-auto mb-3 text-txt-secondary dark:text-txt-dark-secondary" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/><rect x="8" y="8" width="8" height="8" rx="1"/></svg>
          <div class="font-semibold text-lg mb-1">Intel</div>
          <div class="text-sm text-txt-secondary dark:text-txt-dark-secondary">x86_64</div>
        </a>

      </div>
      <p class="text-sm text-txt-secondary dark:text-txt-dark-secondary text-center mt-4">两个按钮下载的都是同一个已签名通用版 .dmg。</p>
    </section>""",
        ),
    ],
}

missing = [path for path in relative_paths if not (web_dir / path).is_file()]
if missing:
    raise SystemExit(f"Missing required RockxyWeb files: {', '.join(missing)}")

changed = []
for relative_path in relative_paths:
    path = web_dir / relative_path
    original = path.read_text()
    updated = original
    updated = sha_url_pattern.sub(sha_url, updated)
    updated = dmg_url_pattern.sub(dmg_url, updated)
    updated = tag_url_pattern.sub(tag_url, updated)
    updated = dmg_filename_pattern.sub(dmg_filename, updated)
    updated = version_pattern.sub(f"v{version}", updated)

    if relative_path == "index.html":
        updated = software_version_pattern.sub(lambda match: f'{match.group(1)}{version}{match.group(2)}', updated)

    for before, after in literal_replacements.get(relative_path, []):
        updated = updated.replace(before, after)

    for before, after in block_replacements.get(relative_path, []):
        updated = updated.replace(before.format(dmg_url=dmg_url), after.format(dmg_url=dmg_url))

    if updated != original:
        path.write_text(updated)
        changed.append(relative_path)

if not changed:
    print("No RockxyWeb files needed updates.")
else:
    print("Updated RockxyWeb files:")
    for relative_path in changed:
        print(f"  - {relative_path}")
PY

echo ""
if ! "$SCRIPT_DIR/release-verify-web.sh" --web-dir "$WEB_DIR"; then
    echo -e "${RED}Error: RockxyWeb universal download verification failed after sync.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}==> RockxyWeb sync complete${NC}"
