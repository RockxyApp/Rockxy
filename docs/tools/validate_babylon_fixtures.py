#!/usr/bin/env python3
"""Ensure Rockxy and Babylon consume the same versioned protocol fixtures."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_babylon_fixtures.py <babylon-repository>", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parents[2]
    rockxy_dir = root / "RockxyTests/Fixtures/BabylonProtocol/v1"
    babylon_dir = Path(sys.argv[1]).resolve() / "BabylonTests/Fixtures/RockxyProtocol/v1"
    rockxy_manifest = json.loads((rockxy_dir / "manifest.json").read_text())
    babylon_manifest = json.loads((babylon_dir / "manifest.json").read_text())
    if rockxy_manifest != babylon_manifest:
        print("fixture manifests differ", file=sys.stderr)
        return 1

    expected = set(rockxy_manifest["fixtures"]) | {"manifest.json"}
    if {path.name for path in rockxy_dir.iterdir()} != expected:
        print("Rockxy fixture directory does not match its manifest", file=sys.stderr)
        return 1
    if {path.name for path in babylon_dir.iterdir()} != expected:
        print("Babylon fixture directory does not match its manifest", file=sys.stderr)
        return 1

    mismatches = [
        name for name in sorted(expected)
        if digest(rockxy_dir / name) != digest(babylon_dir / name)
    ]
    if mismatches:
        print(f"fixture content differs: {', '.join(mismatches)}", file=sys.stderr)
        return 1
    print(f"Validated {len(expected) - 1} shared Babylon v1 fixtures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
