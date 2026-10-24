#!/usr/bin/env python3
"""Keep Files-visible synthetic documents confined to simulator UI products."""
from __future__ import annotations
import argparse
import plistlib
from pathlib import Path

MARKER = "HealthMdUITestBrowsableDocuments"


def verify_device(info: dict) -> None:
    if info.get("UIFileSharingEnabled") not in (None, False) or info.get(MARKER) not in (None, False):
        raise ValueError("ordinary device plist must not expose the synthetic document fixture")


def verify_simulator(info: dict) -> None:
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneSimulator"]:
        raise ValueError("browsable fixture requires an iPhone Simulator product")
    if any(info.get(key) is not True for key in ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace", MARKER)):
        raise ValueError("UI product is missing the Files-visible synthetic document fixture")


def create(source: Path, output: Path) -> None:
    if source.resolve() == output.resolve():
        raise ValueError("fixture plist must not replace the production source")
    info = plistlib.loads(source.read_bytes())
    verify_device(info)
    if info.get("LSSupportsOpeningDocumentsInPlace") is not True:
        raise ValueError("source must retain the production open-in-place setting")
    info.update(UIFileSharingEnabled=True)
    info[MARKER] = True
    with output.open("xb") as stream:
        plistlib.dump(info, stream)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    build = modes.add_parser("create")
    build.add_argument("--source", type=Path, required=True)
    build.add_argument("--output", type=Path, required=True)
    device = modes.add_parser("verify-device")
    device.add_argument("--plist", type=Path, required=True)
    args = parser.parse_args()
    if args.mode == "create":
        create(args.source, args.output)
    else:
        verify_device(plistlib.loads(args.plist.read_bytes()))


if __name__ == "__main__":
    main()
