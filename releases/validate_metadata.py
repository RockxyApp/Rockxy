#!/usr/bin/env python3
"""Validate public Rockxy release metadata.

This script checks only public release metadata. It does not know about private
license validation, entitlement payloads, or update-window internals.
"""

from __future__ import annotations

import argparse
import email.utils
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ROCKXY_NS = "https://rockxy.io/xml-namespaces/release"

CATALOG_REQUIRED = {
    "version",
    "build",
    "release_date",
    "download_url",
    "checksum_sha256",
    "dmg_length",
    "sparkle_ed_signature",
    "release_notes_url",
    "minimum_system_version",
}

APPCAST_REQUIRED = {
    "pubDate",
    "enclosure.url",
    "enclosure.sparkle:version",
    "enclosure.sparkle:shortVersionString",
    "enclosure.sparkle:edSignature",
    "enclosure.length",
    "sparkle:minimumSystemVersion",
    "sparkle:releaseNotesLink",
    "rockxy:releaseDate",
}

PRIVATE_TOKEN_RE = re.compile(
    r"RockxyPro|Lemon|licenseProviderMode|licensingMode|licenseEndpoint|"
    r"lemon(Store|Product|Pro|Enterprise)|entitlement|keychain|"
    r"supportedPaidTiers|ROCKXY_NOTARY|SPARKLE_PRIVATE",
    re.IGNORECASE,
)


def fail(message: str) -> None:
    raise SystemExit(f"release metadata validation failed: {message}")


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        fail(f"{path} is missing")
    except json.JSONDecodeError as error:
        fail(f"{path} is not valid JSON: {error}")
    if not isinstance(data, dict):
        fail(f"{path} must contain a JSON object")
    return data


def normalize_release_date(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", raw):
        return f"{raw}T00:00:00Z"
    candidate = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError:
        fail(f"release_date is not UTC ISO-8601: {raw}")
    if parsed.tzinfo is None:
        fail(f"release_date must include a timezone: {raw}")
    parsed = parsed.astimezone(timezone.utc).replace(microsecond=0)
    return parsed.isoformat().replace("+00:00", "Z")


def comparable_version(version: str) -> tuple[int, ...]:
    parts = []
    for part in version.split("."):
        match = re.match(r"\d+", part)
        parts.append(int(match.group(0)) if match else 0)
    return tuple(parts)


def release_identity(release: dict[str, Any]) -> tuple[str, str, str]:
    return (
        str(release.get("version", "")),
        str(release.get("build", "")),
        normalize_release_date(release.get("release_date")),
    )


def ensure_public_safe(path: Path, value: Any) -> None:
    text = json.dumps(value, sort_keys=True) if not isinstance(value, str) else value
    match = PRIVATE_TOKEN_RE.search(text)
    if match:
        fail(f"{path} contains private release metadata token {match.group(0)!r}")


def validate_catalog(path: Path) -> dict[str, Any]:
    catalog = load_json(path)
    ensure_public_safe(path, catalog)
    releases = catalog.get("releases")
    if not isinstance(releases, list) or not releases:
        fail(f"{path} must contain a non-empty releases array")
    if len(releases) < 2:
        fail(f"{path} must keep older signed releases discoverable")

    seen: set[tuple[str, str]] = set()
    previous: tuple[tuple[int, ...], int] | None = None
    for index, release in enumerate(releases):
        if not isinstance(release, dict):
            fail(f"{path} release at index {index} must be an object")
        missing = sorted(key for key in CATALOG_REQUIRED if release.get(key) in ("", None))
        if missing:
            fail(f"{path} release {index} missing required fields: {', '.join(missing)}")
        identity = (str(release["version"]), str(release["build"]))
        if identity in seen:
            fail(f"{path} contains duplicate release {identity[0]} build {identity[1]}")
        seen.add(identity)
        normalize_release_date(release["release_date"])
        if not str(release["download_url"]).startswith("https://github.com/RockxyApp/Rockxy/releases/download/"):
            fail(f"{path} release {identity[0]} has a non-canonical download_url")
        if not re.fullmatch(r"[0-9a-f]{64}", str(release["checksum_sha256"])):
            fail(f"{path} release {identity[0]} checksum_sha256 must be a SHA-256 hex digest")
        if int(release["dmg_length"]) <= 0:
            fail(f"{path} release {identity[0]} dmg_length must be positive")
        current = (comparable_version(str(release["version"])), int(str(release["build"])))
        if previous is not None and current > previous:
            fail(f"{path} releases must be sorted newest first")
        previous = current
    return catalog


def find_text(parent: ET.Element, path: str) -> str:
    found = parent.find(path, {"sparkle": SPARKLE_NS, "rockxy": ROCKXY_NS})
    return (found.text or "").strip() if found is not None else ""


def validate_appcast(path: Path) -> list[dict[str, str]]:
    try:
        root = ET.parse(path).getroot()
    except FileNotFoundError:
        fail(f"{path} is missing")
    except ET.ParseError as error:
        fail(f"{path} is not valid XML: {error}")

    channel = root.find("channel")
    if channel is None:
        fail(f"{path} is missing channel")
    items = channel.findall("item")
    if not items:
        fail(f"{path} must contain at least one release item")

    releases: list[dict[str, str]] = []
    for index, item in enumerate(items):
        enclosure = item.find("enclosure")
        values = {
            "pubDate": find_text(item, "pubDate"),
            "enclosure.url": enclosure.attrib.get("url", "") if enclosure is not None else "",
            "enclosure.sparkle:version": enclosure.attrib.get(f"{{{SPARKLE_NS}}}version", "") if enclosure is not None else "",
            "enclosure.sparkle:shortVersionString": (
                enclosure.attrib.get(f"{{{SPARKLE_NS}}}shortVersionString", "") if enclosure is not None else ""
            ),
            "enclosure.sparkle:edSignature": (
                enclosure.attrib.get(f"{{{SPARKLE_NS}}}edSignature", "") if enclosure is not None else ""
            ),
            "enclosure.length": enclosure.attrib.get("length", "") if enclosure is not None else "",
            "sparkle:minimumSystemVersion": find_text(item, "sparkle:minimumSystemVersion"),
            "sparkle:releaseNotesLink": find_text(item, "sparkle:releaseNotesLink"),
            "rockxy:releaseDate": find_text(item, "rockxy:releaseDate"),
        }
        missing = sorted(key for key in APPCAST_REQUIRED if not values[key])
        if missing:
            fail(f"{path} item {index} missing required fields: {', '.join(missing)}")
        pub_date = email.utils.parsedate_to_datetime(values["pubDate"]).astimezone(timezone.utc)
        release_date = normalize_release_date(values["rockxy:releaseDate"])
        if normalize_release_date(pub_date.isoformat()) != release_date:
            fail(f"{path} item {index} pubDate and rockxy:releaseDate differ")
        releases.append(
            {
                "version": values["enclosure.sparkle:shortVersionString"],
                "build": values["enclosure.sparkle:version"],
                "release_date": release_date,
                "download_url": values["enclosure.url"],
                "dmg_length": values["enclosure.length"],
                "sparkle_ed_signature": values["enclosure.sparkle:edSignature"],
                "release_notes_url": values["sparkle:releaseNotesLink"],
                "minimum_system_version": values["sparkle:minimumSystemVersion"],
            }
        )
    return releases


def latest_release_object(data: dict[str, Any]) -> dict[str, Any]:
    release_date = data.get("release_date") or data.get("releaseDateUtc") or data.get("releaseDate")
    return {
        "version": data.get("version"),
        "build": data.get("build"),
        "release_date": release_date,
        "download_url": data.get("download_url") or data.get("downloadUrl"),
        "checksum_sha256": data.get("checksum_sha256") or data.get("checksumSha256"),
        "dmg_length": data.get("dmg_length") or data.get("artifactLength"),
        "sparkle_ed_signature": data.get("sparkle_ed_signature") or data.get("sparkleEdSignature"),
        "release_notes_url": data.get("release_notes_url") or data.get("releaseUrl"),
        "minimum_system_version": data.get("minimum_system_version") or data.get("minimumSystemVersion"),
    }


def validate_latest(path: Path) -> dict[str, Any]:
    latest = load_json(path)
    ensure_public_safe(path, latest)
    release = latest_release_object(latest)
    missing = sorted(key for key in CATALOG_REQUIRED if release.get(key) in ("", None))
    if missing:
        fail(f"{path} missing required latest metadata: {', '.join(missing)}")
    normalize_release_date(release["release_date"])
    return release


def validate_manifest(path: Path) -> dict[str, Any]:
    manifest = load_json(path)
    ensure_public_safe(path, manifest)
    release = latest_release_object(manifest)
    missing = sorted(key for key in CATALOG_REQUIRED if release.get(key) in ("", None))
    if missing:
        fail(f"{path} missing required public manifest metadata: {', '.join(missing)}")
    return release


def validate_app_bundle(app_path: Path, expected: dict[str, Any]) -> None:
    info_path = app_path
    if app_path.suffix == ".app":
        info_path = app_path / "Contents" / "Info.plist"
    if not info_path.exists():
        fail(f"{info_path} is missing")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    checks = {
        "CFBundleShortVersionString": expected["version"],
        "CFBundleVersion": expected["build"],
    }
    for key, expected_value in checks.items():
        if str(info.get(key, "")) != str(expected_value):
            fail(f"{info_path} {key} is {info.get(key)!r}, expected {expected_value!r}")
    actual_date = normalize_release_date(info.get("RockxyBuildReleaseDate"))
    expected_date = normalize_release_date(expected["release_date"])
    if actual_date != expected_date:
        fail(f"{info_path} RockxyBuildReleaseDate is {actual_date}, expected {expected_date}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", default="appcast.xml", type=Path)
    parser.add_argument("--latest", default="releases/latest.json", type=Path)
    parser.add_argument("--catalog", default="releases/catalog.json", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--app", type=Path, help="Path to Rockxy.app or an Info.plist to compare against metadata")
    args = parser.parse_args()

    catalog = validate_catalog(args.catalog)
    latest = validate_latest(args.latest)
    appcast_releases = validate_appcast(args.appcast)
    newest_catalog = catalog["releases"][0]

    if release_identity(latest) != release_identity(newest_catalog):
        fail("latest.json does not match the newest release in catalog.json")
    if release_identity(appcast_releases[0]) != release_identity(newest_catalog):
        fail("appcast.xml newest item does not match catalog.json")

    for key in ("download_url", "dmg_length", "sparkle_ed_signature", "release_notes_url", "minimum_system_version"):
        if str(latest[key]) != str(newest_catalog[key]):
            fail(f"latest.json {key} does not match catalog.json")

    if args.manifest:
        manifest = validate_manifest(args.manifest)
        if release_identity(manifest) != release_identity(newest_catalog):
            fail("public manifest does not match catalog.json")
    if args.app:
        validate_app_bundle(args.app, newest_catalog)

    print("release metadata validation OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
