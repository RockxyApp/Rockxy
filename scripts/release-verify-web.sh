#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

WEB_DIR="${ROCKXY_WEB_DIR:-$(cd "$PROJECT_DIR/.." && pwd)/RockxyWeb}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --web-dir) WEB_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--web-dir /path/to/RockxyWeb]"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [ ! -d "$WEB_DIR" ]; then
    echo -e "${RED}Error: RockxyWeb directory not found at $WEB_DIR${NC}"
    exit 1
fi

python3 - <<'PY' "$WEB_DIR"
import sys
from pathlib import Path

web_dir = Path(sys.argv[1])

required = {
    "download.html": [
        "Universal: Apple Silicon + Intel",
        "Universal macOS download",
        "Both buttons download the same signed universal .dmg.",
        "Apple Silicon or Intel",
    ],
    "de/download.html": [
        "Universal: Apple Silicon + Intel",
        "Universeller macOS-Download",
        "Beide Schaltflächen laden dieselbe signierte universelle .dmg herunter.",
        "Apple Silicon oder Intel",
    ],
    "fr/download.html": [
        "Universel : Apple Silicon + Intel",
        "Téléchargement macOS universel",
        "Les deux boutons téléchargent le même fichier .dmg universel signé.",
        "Apple Silicon ou Intel",
    ],
    "ja/download.html": [
        "ユニバーサル: Apple Silicon + Intel",
        "ユニバーサル macOS ダウンロード",
        "どちらのボタンでも同じ署名済みユニバーサル .dmg をダウンロードします。",
        "Apple Silicon または Intel",
    ],
    "zh/download.html": [
        "通用版：Apple Silicon + Intel",
        "通用 macOS 下载",
        "两个按钮都会下载同一个已签名的通用 .dmg。",
        "Apple Silicon 或 Intel",
    ],
    "index.html": ["Universal: Apple Silicon + Intel"],
    "de/index.html": ["Universal: Apple Silicon + Intel"],
    "fr/index.html": ["Universel : Apple Silicon + Intel"],
    "ja/index.html": ["ユニバーサル: Apple Silicon + Intel"],
    "zh/index.html": ["通用版：Apple Silicon + Intel"],
    "compare.html": ["Does Rockxy work on Apple Silicon and Intel Macs?"],
    "de/compare.html": ["Funktioniert Rockxy auf Apple Silicon und Intel-Macs?"],
    "fr/compare.html": ["Rockxy fonctionne-t-il sur les Mac Apple Silicon et Intel ?"],
    "ja/compare.html": ["Rockxy は Apple Silicon と Intel Mac の両方で動作しますか?"],
    "zh/compare.html": ["Rockxy 支持 Apple Silicon 和 Intel Mac 吗？"],
}

forbidden_by_file = {
    "download.html": [
        "Coming soon",
        "Apple Silicon native",
        "cursor-not-allowed",
    ],
    "de/download.html": [
        "Demnächst",
        "cursor-not-allowed",
    ],
    "fr/download.html": [
        "Bientôt",
        "cursor-not-allowed",
    ],
    "ja/download.html": [
        "近日対応",
        "cursor-not-allowed",
    ],
    "zh/download.html": [
        "即将推出",
        "cursor-not-allowed",
    ],
    "index.html": ["Apple Silicon native"],
    "de/index.html": ["Apple Silicon nativ"],
    "fr/index.html": ["Apple Silicon natif"],
    "ja/index.html": ["Apple Silicon ネイティブ"],
    "zh/index.html": ["Apple Silicon 原生"],
}

errors = []

for relative_path, expected_strings in required.items():
    path = web_dir / relative_path
    if not path.is_file():
        errors.append(f"Missing required file: {relative_path}")
        continue

    content = path.read_text()

    for needle in expected_strings:
        if needle not in content:
            errors.append(f"{relative_path}: missing required text: {needle}")

    for needle in forbidden_by_file.get(relative_path, []):
        if needle in content:
            errors.append(f"{relative_path}: found forbidden text: {needle}")

if errors:
    print("Web release verification failed:")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("Web release verification passed.")
PY

echo -e "${GREEN}==> RockxyWeb universal download verification passed${NC}"
