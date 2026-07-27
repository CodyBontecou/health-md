#!/usr/bin/env python3
"""Normalize XCFramework metadata that xcodebuild emits in nondeterministic array order."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <xcframework>", file=sys.stderr)
        return 64

    info_path = Path(sys.argv[1]) / "Info.plist"
    if not info_path.is_file():
        print(f"error: missing XCFramework Info.plist: {info_path}", file=sys.stderr)
        return 1

    with info_path.open("rb") as handle:
        info = plistlib.load(handle)

    libraries = info.get("AvailableLibraries")
    if not isinstance(libraries, list):
        print("error: XCFramework AvailableLibraries is not an array", file=sys.stderr)
        return 1
    if not all(isinstance(item, dict) and isinstance(item.get("LibraryIdentifier"), str) for item in libraries):
        print("error: XCFramework library entry has no identifier", file=sys.stderr)
        return 1

    libraries.sort(key=lambda item: item["LibraryIdentifier"])
    with info_path.open("wb") as handle:
        plistlib.dump(info, handle, fmt=plistlib.FMT_XML, sort_keys=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
