#!/usr/bin/env python3
"""Select the newest compatible available iPhone simulator from simctl JSON."""

from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any

RUNTIME_RE = re.compile(r"\.iOS-(\d+)(?:-(\d+))?(?:-(\d+))?$")
PREFERRED_IPHONES = (
    "iPhone 17 Pro",
    "iPhone 17",
    "iPhone 16 Pro",
    "iPhone 16",
    "iPhone 15 Pro",
    "iPhone 15",
)


def runtime_version(identifier: str) -> tuple[int, int, int] | None:
    match = RUNTIME_RE.search(identifier)
    if match is None:
        return None
    return tuple(int(part or 0) for part in match.groups())


def sdk_major(version: str) -> int:
    match = re.match(r"^(\d+)", version)
    if match is None:
        raise ValueError(f"invalid iOS Simulator SDK version: {version!r}")
    return int(match.group(1))


def select_device(payload: dict[str, Any], sdk_version: str) -> tuple[str, str, tuple[int, int, int]]:
    maximum_major = sdk_major(sdk_version)
    preferred_rank = {name: index for index, name in enumerate(PREFERRED_IPHONES)}
    candidates: list[tuple[tuple[int, int, int], int, str, str]] = []

    devices_by_runtime = payload.get("devices")
    if not isinstance(devices_by_runtime, dict):
        raise ValueError("simctl JSON has no devices object")

    for runtime_identifier, devices in devices_by_runtime.items():
        version = runtime_version(runtime_identifier)
        if version is None or version[0] > maximum_major or not isinstance(devices, list):
            continue
        for device in devices:
            if not isinstance(device, dict) or device.get("isAvailable") is False:
                continue
            name = device.get("name")
            udid = device.get("udid")
            if not isinstance(name, str) or not name.startswith("iPhone"):
                continue
            if not isinstance(udid, str) or not udid:
                continue
            candidates.append((version, preferred_rank.get(name, len(preferred_rank)), name, udid))

    if not candidates:
        raise ValueError(f"no available iPhone simulator is compatible with SDK {sdk_version}")

    version, _, name, udid = sorted(
        candidates,
        key=lambda item: (-item[0][0], -item[0][1], -item[0][2], item[1], item[2], item[3]),
    )[0]
    return name, udid, version


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk-version", required=True)
    args = parser.parse_args()

    try:
        payload = json.load(sys.stdin)
        name, udid, version = select_device(payload, args.sdk_version)
    except (json.JSONDecodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Selected {name} on iOS {'.'.join(map(str, version[:2]))} ({udid})", file=sys.stderr)
    print(f"platform=iOS Simulator,id={udid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
