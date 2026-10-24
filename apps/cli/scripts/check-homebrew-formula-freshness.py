#!/usr/bin/env python3
"""Reject stale or in-place Homebrew formula publication."""

from __future__ import annotations

import pathlib
import re
import sys

PRERELEASE_IDENTIFIER = r"(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    rf"(?:-({PRERELEASE_IDENTIFIER}(?:\.{PRERELEASE_IDENTIFIER})*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
FORMULA_VERSION = re.compile(r'^\s*version\s+"([^"]+)"\s*$', re.MULTILINE)


def fail(message: str) -> None:
    raise SystemExit(f"Homebrew formula freshness error: {message}")


def parse_version(
    value: str, label: str
) -> tuple[tuple[int, ...], bool, tuple[tuple[int, int | str], ...]]:
    match = SEMVER.fullmatch(value)
    if match is None:
        fail(f"{label} is not a valid SemVer: {value!r}")
    core = tuple(int(component) for component in match.groups()[:3])
    prerelease = match.group(4)
    identifiers = tuple(
        (0, int(part)) if part.isdigit() else (1, part)
        for part in prerelease.split(".")
    ) if prerelease is not None else ()
    # Stable beats previews; numeric identifiers sort numerically and before text.
    # Build metadata never changes precedence, so same-precedence rewrites stay forbidden.
    return core, prerelease is None, identifiers


def formula_version(path: pathlib.Path, label: str) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"{label} is missing or symlinked")
    matches = FORMULA_VERSION.findall(path.read_text(encoding="utf-8"))
    if len(matches) != 1:
        fail(f"{label} must contain exactly one version declaration")
    return matches[0]


def main() -> int:
    if len(sys.argv) != 4:
        fail(
            "usage: check-homebrew-formula-freshness.py "
            "CANDIDATE_VERSION CURRENT_FORMULA CANDIDATE_FORMULA"
        )
    candidate_text = sys.argv[1]
    current_path = pathlib.Path(sys.argv[2])
    candidate_path = pathlib.Path(sys.argv[3])
    candidate = parse_version(candidate_text, "candidate version")
    embedded_candidate_text = formula_version(candidate_path, "candidate formula")
    embedded_candidate = parse_version(
        embedded_candidate_text, "candidate formula version"
    )
    if embedded_candidate != candidate or embedded_candidate_text != candidate_text:
        fail(
            "candidate formula version differs from the release plan: "
            f"{embedded_candidate_text!r} != {candidate_text!r}"
        )

    if not current_path.exists():
        print(f"Homebrew formula freshness passed: first release {candidate_text}")
        return 0
    current_text = formula_version(current_path, "current tap formula")
    current = parse_version(current_text, "current tap formula version")
    if current > candidate:
        fail(
            f"refusing signed rollback from {current_text} to {candidate_text}; "
            "use the separately reviewed recovery path"
        )
    if current == candidate:
        if current_path.read_bytes() != candidate_path.read_bytes():
            fail(
                f"version {candidate_text} already exists with different formula bytes; "
                "published versions are immutable"
            )
        print(f"Homebrew formula freshness passed: idempotent {candidate_text}")
        return 0

    print(f"Homebrew formula freshness passed: {current_text} -> {candidate_text}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
