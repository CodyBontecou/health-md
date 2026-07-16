#!/usr/bin/env python3
"""Validate local links in Health.md Markdown documentation."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def destination(raw: str) -> str:
    value = raw.strip()
    if value.startswith("<") and ">" in value:
        return value[1 : value.index(">")]
    # Markdown permits an optional quoted title after a whitespace-separated URL.
    return value.split(maxsplit=1)[0]


def main() -> int:
    errors: list[str] = []
    checked = 0

    for document in sorted(DOCS.rglob("*.md")):
        text = document.read_text(encoding="utf-8")
        for match in LINK.finditer(text):
            target = destination(match.group(1))
            if not target or target.startswith(("#", "http://", "https://", "mailto:")):
                continue

            relative = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not relative:
                continue

            resolved = (document.parent / relative).resolve()
            checked += 1
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                errors.append(f"{document.relative_to(ROOT)}: link escapes repository: {target}")
                continue

            if not resolved.exists():
                line = text.count("\n", 0, match.start()) + 1
                errors.append(
                    f"{document.relative_to(ROOT)}:{line}: missing local target {target}"
                )

    if errors:
        print("Documentation link check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Documentation links valid: {checked} local links checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
