#!/usr/bin/env python3
"""Validate canonical App Store metadata before it is applied by release workflows.

Checks every locale under apps/apple/metadata:
  * app-info: name and subtitle Unicode length (30 each), privacy URL present.
  * version/<v>/<locale>.json: keywords length (100 Unicode code points), comma
    formatting, intra-field duplicate terms, exact duplication against the
    visible name/subtitle tokens, required keys, and locale parity with
    app-info and en-US.

The gate enforces the mechanical App Store Connect field contract only. It does
not judge linguistic quality, trademark clearance, or medical-claim boundaries,
which require native and legal review.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys
import unicodedata

APPLE_ROOT = Path(__file__).resolve().parents[1]
METADATA_ROOT = APPLE_ROOT / "metadata"
APP_INFO_DIR = METADATA_ROOT / "app-info"
VERSION_DIR = METADATA_ROOT / "version"

NAME_LIMIT = 30
SUBTITLE_LIMIT = 30
KEYWORDS_LIMIT = 100

REQUIRED_VERSION_KEYS = ("description", "keywords", "marketingUrl", "supportUrl", "whatsNew")


def code_points(text: str) -> int:
    return len(text)


def check(condition: bool, errors: list[str], message: str) -> None:
    if not condition:
        errors.append(message)


def visible_tokens(name: str, subtitle: str) -> set[str]:
    """Lowercased word tokens used by the visible fields, for exact-duplicate checks."""
    tokens: set[str] = set()
    for field in (name, subtitle):
        normalized = unicodedata.normalize("NFC", field).lower()
        for token in normalized.replace(",", " ").replace("、", " ").replace("·", " ").split():
            tokens.add(token.strip(".。"))
    return tokens


def validate_app_info(errors: list[str]) -> dict[str, dict]:
    locales: dict[str, dict] = {}
    for path in sorted(APP_INFO_DIR.glob("*.json")):
        locale = path.stem
        data = json.loads(path.read_text())
        locales[locale] = data
        name = data.get("name", "")
        subtitle = data.get("subtitle", "")
        check(0 < code_points(name) <= NAME_LIMIT, errors,
              f"app-info/{locale}: name is {code_points(name)} chars (limit {NAME_LIMIT})")
        check(0 < code_points(subtitle) <= SUBTITLE_LIMIT, errors,
              f"app-info/{locale}: subtitle is {code_points(subtitle)} chars (limit {SUBTITLE_LIMIT})")
        check(bool(data.get("privacyPolicyUrl")), errors,
              f"app-info/{locale}: privacyPolicyUrl missing")
    return locales


def validate_keywords(locale: str, keywords: str, visible: set[str], errors: list[str]) -> None:
    where = f"{locale}"
    check(0 < code_points(keywords) <= KEYWORDS_LIMIT, errors,
          f"{where}: keywords are {code_points(keywords)} chars (limit {KEYWORDS_LIMIT})")
    check(", " not in keywords, errors, f"{where}: keywords contain a space after a comma")
    check(" ," not in keywords, errors, f"{where}: keywords contain a space before a comma")
    terms = keywords.split(",")
    seen: set[str] = set()
    for term in terms:
        check(bool(term.strip()), errors, f"{where}: empty keyword term between commas")
        normalized = unicodedata.normalize("NFC", term).lower()
        check(term == unicodedata.normalize("NFC", term), errors,
              f"{where}: keyword term is not NFC-normalized: {term!r}")
        check(normalized not in seen, errors, f"{where}: duplicate keyword term {term!r}")
        seen.add(normalized)
        check(normalized not in visible, errors,
              f"{where}: keyword {term!r} exactly duplicates a visible name/subtitle token")


def validate_version(errors: list[str], app_info: dict[str, dict]) -> bool:
    """Return False when no local version metadata exists (clean checkout)."""
    if not VERSION_DIR.exists() or not any(VERSION_DIR.glob("*/en-US.json")):
        return False
    for version_path in sorted(VERSION_DIR.iterdir()):
        if not version_path.is_dir():
            errors.append(f"metadata/version: unexpected file {version_path.name}")
            continue
        version = version_path.name
        locales = sorted(p.stem for p in version_path.glob("*.json"))
        missing = sorted(set(app_info) - set(locales))
        extra = sorted(set(locales) - set(app_info))
        check(not missing, errors,
              f"version/{version}: missing locales present in app-info: {missing}")
        check(not extra, errors,
              f"version/{version}: locales missing from app-info: {extra}")
        for path in sorted(version_path.glob("*.json")):
            locale = path.stem
            where = f"version/{version}/{locale}"
            data = json.loads(path.read_text())
            for key in REQUIRED_VERSION_KEYS:
                check(key in data, errors, f"{where}: missing key {key!r}")
            keywords = data.get("keywords", "")
            if keywords:
                info = app_info.get(locale, {})
                visible = visible_tokens(info.get("name", ""), info.get("subtitle", ""))
                validate_keywords(where, keywords, visible, errors)
            for key in ("description", "whatsNew"):
                value = data.get(key, "")
                check(bool(value.strip()), errors, f"{where}: empty {key}")
    return True


def main() -> int:
    errors: list[str] = []
    check(APP_INFO_DIR.is_dir(), errors, "metadata/app-info directory missing")
    if not errors:
        app_info = validate_app_info(errors)
        has_versions = validate_version(errors, app_info)
    if errors:
        print(f"App Store metadata validation FAILED ({len(errors)} error(s)):")
        for error in errors:
            print(f"  - {error}")
        return 1
    scope = "app-info + all local version metadata" if has_versions else "app-info (no local version metadata present)"
    print(f"App Store metadata validation passed: {scope}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
