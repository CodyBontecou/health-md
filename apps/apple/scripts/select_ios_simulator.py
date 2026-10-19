#!/usr/bin/env python3
"""Select the newest compatible available iPhone or iPad from simctl JSON."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import uuid
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


def select_device(
    payload: dict[str, Any], sdk_version: str, device_family: str = "iPhone"
) -> tuple[str, str, tuple[int, int, int]]:
    if device_family not in ("iPhone", "iPad"):
        raise ValueError(f"invalid iOS Simulator device family: {device_family!r}")
    maximum_major = sdk_major(sdk_version)
    preferred_rank = (
        {name: index for index, name in enumerate(PREFERRED_IPHONES)}
        if device_family == "iPhone"
        else {}
    )
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
            if not isinstance(name, str) or not name.startswith(device_family):
                continue
            if not isinstance(udid, str) or not udid:
                continue
            candidates.append((version, preferred_rank.get(name, len(preferred_rank)), name, udid))

    if not candidates:
        raise ValueError(f"no available {device_family} simulator is compatible with SDK {sdk_version}")

    version, _, name, udid = sorted(
        candidates,
        key=lambda item: (-item[0][0], -item[0][1], -item[0][2], item[1], item[2], item[3]),
    )[0]
    return name, udid, version


def select_ci_ipad(payload: dict[str, Any], sdk_version: str) -> tuple[str, str, tuple[int, int, int]]:
    """Reuse or create an iPad on the newest available compatible runtime."""
    maximum_major = sdk_major(sdk_version)
    runtimes_payload = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "runtimes", "available", "-j"], text=True
    ))
    runtimes = runtimes_payload.get("runtimes")
    if not isinstance(runtimes, list):
        raise ValueError("simctl JSON has no runtimes array")
    candidates = []
    for runtime in runtimes:
        if not isinstance(runtime, dict) or runtime.get("isAvailable") is not True:
            continue
        identifier = runtime.get("identifier")
        version = runtime_version(identifier) if isinstance(identifier, str) else None
        if version is not None and version[0] <= maximum_major:
            candidates.append((version, identifier, runtime))
    if not candidates:
        raise ValueError(f"no available iOS runtime is compatible with SDK {sdk_version}")
    version, identifier, runtime = sorted(candidates, key=lambda item: (item[0], item[1]), reverse=True)[0]

    devices_by_runtime = payload.get("devices")
    if not isinstance(devices_by_runtime, dict):
        raise ValueError("simctl JSON has no devices object")
    devices = devices_by_runtime.get(identifier, [])
    if not isinstance(devices, list):
        raise ValueError("simctl JSON has no devices array for the selected runtime")
    try:
        return select_device({"devices": {identifier: devices}}, sdk_version, "iPad")
    except ValueError:
        # No available iPad exists on this runtime. Its supported-device metadata
        # binds creation to an actual compatible type, without an older/beta fallback.
        types = runtime.get("supportedDeviceTypes")
        if not isinstance(types, list):
            raise ValueError("selected runtime has no supported iPad device types")
        ipad_types = [
            device_type for device_type in types
            if isinstance(device_type, dict)
            and device_type.get("productFamily") == "iPad"
            and isinstance(device_type.get("name"), str)
            and isinstance(device_type.get("identifier"), str)
            and device_type["identifier"]
        ]
        if not ipad_types:
            raise ValueError("selected runtime has no supported iPad device types")
        device_type = sorted(ipad_types, key=lambda item: (
            not item["name"].startswith(("iPad Air", "iPad Pro")), item["name"], item["identifier"]
        ))[0]
        name = "iPad HealthMd CI"
        created = subprocess.check_output(
            ["xcrun", "simctl", "create", name, device_type["identifier"], identifier], text=True
        ).strip()
        udid = str(uuid.UUID(created)).upper()
        print(f"Created {device_type['name']} on iOS {'.'.join(map(str, version[:2]))}", file=sys.stderr)
        return name, udid, version


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk-version", required=True)
    parser.add_argument("--device-family", choices=("iPhone", "iPad"), default="iPhone")
    parser.add_argument("--create-missing", action="store_true",
                        help="reuse/create an iPad on the newest compatible installed runtime (CI only)")
    args = parser.parse_args()
    if args.create_missing and args.device_family != "iPad":
        parser.error("--create-missing requires --device-family iPad")

    try:
        payload = json.load(sys.stdin)
        if args.create_missing:
            name, udid, version = select_ci_ipad(payload, args.sdk_version)
        else:
            name, udid, version = select_device(payload, args.sdk_version, args.device_family)
    except (json.JSONDecodeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Selected {name} on iOS {'.'.join(map(str, version[:2]))} ({udid})", file=sys.stderr)
    print(f"platform=iOS Simulator,id={udid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
