#!/usr/bin/env python3
"""Qualify one freshly generated UI test manifest without rewriting its paths."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import sys
from pathlib import Path
from typing import Any

SCHEME = "HealthMd-UITests-iOS"
TARGET = "HealthMdUITests"
CONFIGURATION = "Debug-iOS-iphonesimulator"
BUILD_MARKER = ".healthmd-ui-build-start"


def dictionary(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a dictionary")
    return value


def enabled(value: dict[str, Any], label: str) -> bool:
    flag = value.get("IsEnabled", True)
    if not isinstance(flag, bool):
        raise ValueError(f"{label} has an invalid IsEnabled flag")
    return flag


def no_embedded_filters(value: dict[str, Any]) -> None:
    for key in ("OnlyTestIdentifiers", "SkipTestIdentifiers"):
        if key in value and value[key] != []:
            raise ValueError(f"generated manifest must not restrict tests with {key}")
    if "UseDestinationArtifacts" in value and value["UseDestinationArtifacts"] is not False:
        raise ValueError("generated manifest must install the qualified built products")


def ui_target(payload: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    metadata = dictionary(payload.get("__xctestrun_metadata__"), "manifest metadata")
    version = metadata.get("FormatVersion")
    if type(version) is not int or version not in (1, 2):
        raise ValueError("unsupported xctestrun FormatVersion")
    container = dictionary(metadata.get("ContainerInfo", {}), "ContainerInfo")
    for info in (metadata, container):
        if "SchemeName" in info and info["SchemeName"] != SCHEME:
            raise ValueError("generated manifest has the wrong SchemeName")

    if version == 1:
        targets = []
        for name, value in payload.items():
            if name.startswith("__"):
                continue
            target = dictionary(value, f"target {name}")
            if enabled(target, f"target {name}"):
                if name != TARGET:
                    raise ValueError("generated manifest has an unexpected enabled target")
                targets.append(target)
    else:
        configurations = payload.get("TestConfigurations")
        if not isinstance(configurations, list) or not configurations:
            raise ValueError("generated manifest has no TestConfigurations")
        active = [dictionary(value, "test configuration") for value in configurations]
        active = [value for value in active if enabled(value, "test configuration")]
        if len(active) != 1:
            raise ValueError("generated manifest must have exactly one enabled configuration")
        no_embedded_filters(active[0])
        values = active[0].get("TestTargets")
        if not isinstance(values, list):
            raise ValueError("generated manifest has no TestTargets")
        targets = [dictionary(value, "test target") for value in values]
        targets = [value for value in targets if enabled(value, "test target")]

    if len(targets) != 1:
        raise ValueError("generated manifest must have exactly one enabled target")
    target = targets[0]
    if target.get("BlueprintName") != TARGET or target.get("IsUITestBundle") is not True:
        raise ValueError("generated manifest does not identify the HealthMd UI test target")
    if "ProductModuleName" in target and target["ProductModuleName"] != TARGET:
        raise ValueError("generated manifest has the wrong ProductModuleName")
    no_embedded_filters(target)
    return version, target


def staged_path(value: Any, products: Path, test_host: Path | None = None) -> Path:
    if not isinstance(value, str) or not value.startswith(("__TESTROOT__/", "__TESTHOST__/")):
        raise ValueError("product paths must use the generated test-root/host placeholders")
    # Inspect only the generated path. An owned absolute root may legitimately
    # contain double underscores (including randomly named CI temporary roots).
    unresolved = value.replace("__TESTROOT__", "")
    if test_host is not None:
        unresolved = unresolved.replace("__TESTHOST__", "")
    if "__" in unresolved:
        raise ValueError("unresolved product path placeholder")
    expanded = value.replace("__TESTROOT__", str(products))
    if test_host is not None:
        expanded = expanded.replace("__TESTHOST__", str(test_host))
    path = Path(expanded).resolve()
    if not path.is_relative_to(products) or not path.is_dir():
        raise ValueError("generated product is missing or outside the fresh Products directory")
    return path


def bundle_info(bundle: Path, products: Path) -> dict[str, Any]:
    try:
        info = dictionary(plistlib.loads((bundle / "Info.plist").read_bytes()), "bundle Info.plist")
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValueError(f"missing or invalid product Info.plist: {bundle.name}") from error
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or Path(executable).name != executable:
        raise ValueError("product has an invalid CFBundleExecutable")
    binary = (bundle / executable).resolve()
    if not binary.is_relative_to(products) or not binary.is_file():
        raise ValueError(f"missing staged executable: {bundle.name}")
    return info


def bundle_digest(bundle: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink() and (path.is_dir() or not path.resolve().is_relative_to(bundle)):
            raise ValueError("product contains an unqualified directory/external symlink")
        if path.is_file():
            relative = str(path.relative_to(bundle)).encode()
            digest.update(relative + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def qualify(derived_data: Path, source_sha: str) -> tuple[Path, dict[str, Any]]:
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("source SHA must be the exact checked-out commit")
    derived_data = derived_data.resolve()
    marker = derived_data / BUILD_MARKER
    if not marker.is_file() or marker.is_symlink():
        raise ValueError("fresh build-start marker is missing")
    products = (derived_data / "Build" / "Products").resolve()
    if not products.is_relative_to(derived_data) or not products.is_dir():
        raise ValueError("fresh Products directory is missing")
    candidates = list(products.glob("*.xctestrun"))
    if len(candidates) != 1:
        raise ValueError("fresh Products directory must contain exactly one xctestrun")
    manifest = candidates[0]
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_mtime_ns < marker.stat().st_mtime_ns:
        raise ValueError("generated manifest is stale or not a regular file")
    raw = manifest.read_bytes()
    try:
        payload = dictionary(plistlib.loads(raw), "generated manifest")
    except plistlib.InvalidFileException as error:
        raise ValueError("generated manifest is not a valid plist") from error
    version, target = ui_target(payload)
    host = staged_path(target.get("TestHostPath"), products)
    app = staged_path(target.get("UITargetAppPath"), products, host)
    test = staged_path(target.get("TestBundlePath"), products, host)
    expected = {
        host: (f"{CONFIGURATION}/HealthMdUITests-Runner.app", "com.codybontecou.HealthMdUITests.xctrunner"),
        app: (f"{CONFIGURATION}/HealthMd.app", "com.codybontecou.obsidianhealth"),
        test: (f"{CONFIGURATION}/HealthMdUITests-Runner.app/PlugIns/HealthMdUITests.xctest", "com.codybontecou.HealthMdUITests"),
    }
    for bundle, (relative, identifier) in expected.items():
        if bundle != products / relative:
            raise ValueError("generated manifest points to the wrong Debug-iOS product")
        info = bundle_info(bundle, products)
        if info.get("CFBundleIdentifier") != identifier or info.get("CFBundleSupportedPlatforms") != ["iPhoneSimulator"]:
            raise ValueError("generated manifest points to the wrong simulator bundle identity")
    if len(expected) != 3:
        raise ValueError("generated test, host, and app paths must be distinct")
    if "TestHostBundleIdentifier" in target and target["TestHostBundleIdentifier"] != expected[host][1]:
        raise ValueError("generated manifest has the wrong TestHostBundleIdentifier")
    if "UITargetAppBundleIdentifier" in target and target["UITargetAppBundleIdentifier"] != expected[app][1]:
        raise ValueError("generated manifest has the wrong UITargetAppBundleIdentifier")
    dependencies = target.get("DependentProductPaths", [])
    if not isinstance(dependencies, list):
        raise ValueError("DependentProductPaths must be an array")
    for value in dependencies:
        bundle_info(staged_path(value, products, host), products)
    receipt = {
        "source_sha": source_sha,
        "scheme": SCHEME,
        "configuration": "Debug-iOS",
        "format_version": version,
        "xctestrun_path": str(manifest),
        "xctestrun_sha256": hashlib.sha256(raw).hexdigest(),
        "build_start_marker": str(marker),
        "products": [{"path": str(bundle), "sha256": bundle_digest(bundle)} for bundle in (app, host, test)],
    }
    return manifest, receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--receipt", required=True, type=Path)
    args = parser.parse_args()
    try:
        manifest, receipt = qualify(args.derived_data, args.source_sha)
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(manifest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
