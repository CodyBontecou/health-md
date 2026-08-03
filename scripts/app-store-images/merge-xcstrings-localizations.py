#!/usr/bin/env python3
"""Merge reviewed locale maps into Health.md's string catalog with token checks."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "apps/apple/HealthMd/Localizable.xcstrings"
FORMAT_TOKEN = re.compile(r"%(?:\d+\$)?(?:[-+#0 ]*(?:\d+|\*)?(?:\.\d+)?)?(?:lld|ld|d|@|f|s)|\{[^{}]+\}")


def tokens(value: str) -> Counter[str]:
    return Counter(FORMAT_TOKEN.findall(value))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--locale-map",
        action="append",
        required=True,
        metavar="LOCALE=PATH",
        help="Target catalog locale and JSON source-key map; repeat for each locale",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    catalog = json.loads(CATALOG_PATH.read_text())
    strings = catalog["strings"]

    updates: list[tuple[str, Path]] = []
    for item in args.locale_map:
        if "=" not in item:
            raise SystemExit(f"Invalid --locale-map value: {item}")
        locale, relative_path = item.split("=", 1)
        updates.append((locale, REPO_ROOT / relative_path))

    for locale, map_path in updates:
        mapping = json.loads(map_path.read_text())
        if not isinstance(mapping, dict):
            raise SystemExit(f"Expected a JSON object in {map_path}")
        actual = set(mapping)
        missing_target = {
            key
            for key, entry in strings.items()
            if "es" in entry.get("localizations", {}) and locale not in entry.get("localizations", {})
        }
        uncovered = sorted(missing_target - actual)
        unknown = sorted(key for key in actual if key not in strings or "es" not in strings[key].get("localizations", {}))
        if uncovered or unknown:
            raise SystemExit(
                f"{locale}: locale map coverage mismatch; uncovered={uncovered[:8]} ({len(uncovered)}), "
                f"unknown={unknown[:8]} ({len(unknown)})"
            )

        for key, value in mapping.items():
            if not isinstance(value, str) or not value.strip():
                raise SystemExit(f"{locale}: empty/non-string translation for {key!r}")
            if tokens(key) != tokens(value):
                raise SystemExit(
                    f"{locale}: format token mismatch for {key!r}: "
                    f"source={dict(tokens(key))}, translation={dict(tokens(value))}"
                )
            strings[key].setdefault("localizations", {})[locale] = {
                "stringUnit": {"state": "translated", "value": value}
            }
        print(f"{locale}: merged {len(mapping)} translations from {map_path.relative_to(REPO_ROOT)}")

    CATALOG_PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
