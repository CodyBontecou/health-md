#!/usr/bin/env python3
"""Partition the compiled native test inventory and qualify every selected method."""
from __future__ import annotations

import hashlib
import json
import re


def identifiers(payload: dict) -> list[str]:
    """Read Xcode's flat enumeration, never a source-code approximation."""
    if payload.get("errors") != []:
        raise ValueError("Compiled test enumeration reported errors")
    plans = payload.get("values")
    if not isinstance(plans, list) or len(plans) != 1:
        raise ValueError("Exactly one enumerated test plan is required")
    plan = plans[0]
    if not isinstance(plan.get("testPlan"), str) or not plan["testPlan"]:
        raise ValueError("Missing compiled test plan identity")
    enabled, disabled = plan.get("enabledTests"), plan.get("disabledTests")
    if not isinstance(enabled, list) or not enabled or not isinstance(disabled, list):
        raise ValueError("Missing enabled/disabled compiled inventory")
    result = []
    for item in enabled + disabled:
        name = item.get("identifier") if isinstance(item, dict) else None
        if not isinstance(name, str) or len(name.split("/")) < 3 or any(ord(c) < 32 for c in name):
            raise ValueError("Invalid compiled method identifier")
        result.append(name)
    if len(result) != len(set(result)):
        raise ValueError("Duplicate compiled method identifier")
    return sorted(item["identifier"] for item in enabled)


def identity(source_sha: str, run_id: str, attempt: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("Exact source SHA is required")
    if any(not value.isdecimal() or int(value) < 1 for value in (run_id, attempt)):
        raise ValueError("Positive current run ID and attempt are required")


def make_plan(payload: dict, source_sha: str, run_id: str, attempt: str, count: int = 4, platform: str = "macOS") -> dict:
    identity(source_sha, run_id, attempt)
    if platform not in {"macOS", "iOS Simulator"}:
        raise ValueError("Unsupported native execution platform")
    names = identifiers(payload)
    if type(count) is not int or not 1 <= count <= min(16, len(names)):
        raise ValueError("Invalid shard count")
    # Hosted measurements put this class at ~28m out of ~31m of Mac tests.
    # Weights only schedule methods; they never select, exclude or cache tests.
    def weight(name):
        return 6 if "/AgentBridgeExportPlanningTests/" in name else 1
    shards = [[] for _ in range(count)]
    loads = [0] * count
    for name in sorted(names, key=lambda name: (-weight(name), name)):
        index = min(range(count), key=lambda index: (loads[index], index))
        shards[index].append(name)
        loads[index] += weight(name)
    return {"source_sha": source_sha, "run_id": run_id, "attempt": attempt, "platform": platform,
            "inventory_sha256": hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest(),
            "inventory": payload, "shards": [sorted(shard) for shard in shards]}


def validate_plan(plan: dict) -> None:
    expected = make_plan(plan["inventory"], plan["source_sha"], plan["run_id"], plan["attempt"], len(plan["shards"]), plan["platform"])
    if plan != expected:
        raise ValueError("Shard plan differs from the complete compiled inventory")


def qualify_results(plan: dict, index: int, tree: dict, summary: dict, *, maximum_devices: int = 1, expected_device_id: str | None = None) -> dict:
    validate_plan(plan)
    if type(index) is not int or not 0 <= index < len(plan["shards"]):
        raise ValueError("Unknown native shard")
    cases = {}
    def visit(node, bundle=None):
        if isinstance(node, list):
            for child in node: visit(child, bundle)
        elif isinstance(node, dict):
            if node.get("nodeType") == "Unit test bundle":
                bundle = node.get("name")
            if node.get("nodeType") == "Test Case":
                name, result = node.get("nodeIdentifier"), node.get("result")
                if not isinstance(bundle, str) or not isinstance(name, str) or result not in {"Passed", "Skipped"}:
                    raise ValueError("Every native method must finish passed or explicitly skipped")
                full = bundle + "/" + name
                if full in cases:
                    raise ValueError("Duplicate actual native method")
                # Swift Testing parameterized arguments are children of the method.
                # They must all finish too; summary counts methods, not arguments.
                def arguments(value):
                    if isinstance(value, dict):
                        if value.get("nodeType") == "Arguments" and value.get("result") not in {"Passed", "Skipped"}:
                            raise ValueError("Native test argument did not finish")
                        for child in value.values(): arguments(child)
                    elif isinstance(value, list):
                        for child in value: arguments(child)
                arguments(node)
                cases[full] = result
            for child in node.values(): visit(child, bundle)
    visit(tree)
    devices = tree.get("devices")
    if (not isinstance(devices, list) or not 1 <= len(devices) <= maximum_devices
            or any(device.get("platform") != plan["platform"] or device.get("architecture") != "arm64" for device in devices)):
        raise ValueError("Native results must come from qualified arm64 devices within the worker inventory")
    if expected_device_id is not None and (len(devices) != 1 or devices[0].get("deviceId", "").lower() != expected_device_id.lower()):
        raise ValueError("Native result device differs from the selected simulator")
    expected = plan["shards"][index]
    passed = sum(value == "Passed" for value in cases.values())
    skipped = len(cases) - passed
    if sorted(cases) != expected:
        raise ValueError("Actual native methods differ from the complete shard selection")
    if (summary.get("result") != "Passed" or summary.get("totalTestCount") != len(expected)
            or summary.get("passedTests") != passed or summary.get("skippedTests") != skipped
            or summary.get("failedTests") != 0):
        raise ValueError("Native summary disagrees with the actual method inventory")
    return {key: plan[key] for key in ("source_sha", "run_id", "attempt", "inventory_sha256", "platform")} | {
        "shard": index, "cases": cases, "passed": passed, "skipped": skipped}


def verify_receipts(plan: dict, receipts: list[dict]) -> dict:
    validate_plan(plan)
    if len(receipts) != len(plan["shards"]):
        raise ValueError("Missing native shard receipt")
    actual = {}
    seen = set()
    for receipt in receipts:
        index = receipt.get("shard")
        if type(index) is not int or index in seen or not 0 <= index < len(plan["shards"]):
            raise ValueError("Missing or duplicate native shard")
        seen.add(index)
        if any(receipt.get(key) != plan[key] for key in ("source_sha", "run_id", "attempt", "inventory_sha256", "platform")):
            raise ValueError("Native receipt is from different source/run/inventory")
        cases = receipt.get("cases")
        if not isinstance(cases, dict) or sorted(cases) != plan["shards"][index] or any(value not in {"Passed", "Skipped"} for value in cases.values()):
            raise ValueError("Native receipt omits or changes selected methods")
        passed = sum(value == "Passed" for value in cases.values())
        if receipt.get("passed") != passed or receipt.get("skipped") != len(cases) - passed:
            raise ValueError("Native receipt counts differ from its methods")
        if actual.keys() & cases.keys():
            raise ValueError("Native method ran in multiple shards")
        actual.update(cases)
    if sorted(actual) != identifiers(plan["inventory"]):
        raise ValueError("Combined native inventory is incomplete")
    return {"source_sha": plan["source_sha"], "run_id": plan["run_id"], "attempt": plan["attempt"],
            "methods": len(actual), "passed": sum(value == "Passed" for value in actual.values()),
            "skipped": sum(value == "Skipped" for value in actual.values())}


def file_digest(path):
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
        return digest.hexdigest()


def sdk_digest(path):
    # Use the same accepted SDK provenance comparison as the native workflow;
    # an overlapping runner ImageVersion rollout is diagnostic, not ABI drift.
    import importlib.util
    from pathlib import Path
    spec = importlib.util.spec_from_file_location("native_sdk_receipts", Path(__file__).with_name("compare-history-sdk27-receipts.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return hashlib.sha256(module.build_identity(path.read_bytes().decode("utf-8")).encode()).hexdigest()


def check_identity(value, args):
    identity(args.source_sha, args.run_id, args.attempt)
    if any(value.get(key) != getattr(args, key) for key in ("source_sha", "run_id", "attempt")):
        raise ValueError("Native products belong to another source/run/attempt")


def execution_destination(platform: str, destination: str) -> str:
    if platform == "macOS" and destination == "platform=macOS,arch=arm64":
        return destination
    if platform == "iOS Simulator" and re.fullmatch(r"platform=iOS Simulator,id=[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", destination):
        return destination
    raise ValueError("An exact native destination for the compiled platform is required")


def qualify_simulator(payload: dict, destination: str) -> str:
    execution_destination("iOS Simulator", destination)
    device_id = destination.split("id=", 1)[1]
    devices = payload.get("devices")
    if not isinstance(devices, dict) or any(not isinstance(values, list) for values in devices.values()):
        raise ValueError("Invalid available simulator inventory")
    selected = [(runtime, device) for runtime, values in devices.items() for device in values
                if isinstance(device, dict) and device.get("udid", "").lower() == device_id.lower()]
    if (len(selected) != 1 or not selected[0][0].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            or selected[0][1].get("isAvailable") is not True):
        raise ValueError("Selected native destination is not an available iOS simulator")
    return device_id


def prepare(args):
    import os
    import subprocess
    products = args.derived / "Build/Products"
    manifests = list(products.glob("*.xctestrun"))
    if len(manifests) != 1:
        raise ValueError("Exactly one compiled macOS manifest is required")
    args.output.mkdir(parents=True, exist_ok=True)
    raw = args.output / "compiled-inventory.json"
    subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", str(manifests[0]),
                    "-destination", execution_destination(args.platform, args.destination), "-enumerate-tests",
                    "-test-enumeration-style", "flat", "-test-enumeration-format", "json",
                    "-test-enumeration-output-path", str(raw)], check=True, timeout=120)
    plan = make_plan(json.loads(raw.read_text()), args.source_sha, args.run_id, args.attempt, platform=args.platform)
    (args.output / "native-test-plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    archive = args.output / "native-products.tar.gz"
    # Keep every product/permission/link; spend less CPU on transport compression.
    subprocess.run(["tar", "--options", "gzip:compression-level=1", "-czf",
                    str(archive.resolve()), "-C", str(args.derived), "Build/Products"],
                   env=dict(os.environ, COPYFILE_DISABLE="1"), check=True, timeout=120)
    receipt = {key: plan[key] for key in ("source_sha", "run_id", "attempt", "platform")}
    receipt.update(prepared_archive_sha256=file_digest(archive),
                   xctestrun=str(manifests[0].relative_to(args.derived)),
                   sdk_receipt_sha256=sdk_digest(args.sdk_receipt))
    (args.output / "native-products-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(receipt["prepared_archive_sha256"])


def restore(args):
    from pathlib import PurePosixPath
    import posixpath
    import tarfile
    receipt = json.loads((args.products / "native-products-receipt.json").read_text())
    plan = json.loads((args.products / "native-test-plan.json").read_text())
    check_identity(receipt, args)
    check_identity(plan, args)
    validate_plan(plan)
    if receipt.get("platform") != plan["platform"]:
        raise ValueError("Native archive platform differs from the compiled inventory")
    archive = args.products / "native-products.tar.gz"
    if (not re.fullmatch(r"[0-9a-f]{64}", args.prepared_sha256)
            or receipt.get("prepared_archive_sha256") != args.prepared_sha256
            or file_digest(archive) != args.prepared_sha256
            or sdk_digest(args.sdk_receipt) != receipt.get("sdk_receipt_sha256")):
        raise ValueError("Native products differ from the current producer archive/SDK")
    manifest = PurePosixPath(receipt["xctestrun"])
    if manifest.is_absolute() or ".." in manifest.parts or manifest.parts[:2] != ("Build", "Products"):
        raise ValueError("Invalid native manifest path")
    if args.derived.exists():
        raise ValueError("Native products must restore into a fresh derived-data directory")
    with tarfile.open(archive) as bundle:
        for member in bundle.getmembers():
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or name.parts[:2] != ("Build", "Products"):
                raise ValueError("Native archive escapes its products directory")
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise ValueError("Unsupported native archive member")
            if member.issym() or member.islnk():
                target = posixpath.normpath(posixpath.join(str(name.parent) if member.issym() else "", member.linkname))
                if PurePosixPath(target).parts[:2] != ("Build", "Products"):
                    raise ValueError("Native archive link escapes its products directory")
        args.derived.mkdir(parents=True)
        # The archive digest is the trusted producer's job output. Validate paths
        # explicitly above for older macOS Python versions without data_filter.
        bundle.extractall(args.derived, **({"filter": "data"} if hasattr(tarfile, "data_filter") else {}))
    path = args.derived / str(manifest)
    if not path.is_file() or path.is_symlink():
        raise ValueError("Restored native manifest is missing")
    return plan, path


def test_command(plan: dict, manifest, destination: str, result, shard: int) -> list[str]:
    validate_plan(plan)
    if type(shard) is not int or not 0 <= shard < len(plan["shards"]):
        raise ValueError("Unknown native shard")
    return ["xcodebuild", "test-without-building", "-xctestrun", str(manifest),
               "-destination", execution_destination(plan["platform"], destination),
               "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
               *(["-enableCodeCoverage", "YES", "-test-timeouts-enabled", "YES",
                  "-default-test-execution-time-allowance", "120", "-maximum-test-execution-time-allowance", "300"]
                 if plan["platform"] == "macOS" else ["-test-timeouts-enabled", "NO"]),
               *["-only-testing:" + name for name in plan["shards"][shard]]]


def run_shard(args):
    import subprocess
    plan, manifest = restore(args)
    if type(args.shard) is not int or not 0 <= args.shard < len(plan["shards"]):
        raise ValueError("Unknown native shard")
    args.output.mkdir(parents=True, exist_ok=True)
    result = args.output / "native.xcresult"
    if result.exists():
        raise ValueError("Native result must be fresh")
    command = test_command(plan, manifest, args.destination, result, args.shard)
    device_id = None
    if plan["platform"] == "iOS Simulator":
        raw_devices = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True, timeout=15)
        device_id = qualify_simulator(json.loads(raw_devices), args.destination)
    print(json.dumps({"source_sha": args.source_sha, "command": command}), flush=True)
    with (args.output / "native-test.log").open("w") as log:
        execution = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                   timeout=2700 if plan["platform"] == "macOS" else 4500)
    values = {}
    for kind in ("tests", "summary"):
        raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(result)], text=True, timeout=60)
        (args.output / (kind + ".json")).write_text(raw)
        values[kind] = json.loads(raw)
    if execution.returncode:
        raise ValueError("Native test execution failed; inspect retained raw log/result")
    receipt = qualify_results(plan, args.shard, values["tests"], values["summary"], expected_device_id=device_id)
    (args.output / "native-case-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def combine(args):
    import subprocess
    import shutil
    plan, _ = restore(args)
    prefix = "macos-native" if plan["platform"] == "macOS" else "ios-native"
    log_name = "build-macos.log" if plan["platform"] == "macOS" else "build-ios.log"
    expected = {f"{prefix}-{args.run_id}-{args.attempt}-{i}" for i in range(len(plan["shards"]))}
    if {path.name for path in args.reports.iterdir()} != expected:
        raise ValueError("Missing or unexpected native shard artifacts")
    receipts, results = [], []
    args.output.mkdir(parents=True, exist_ok=True)
    with (args.output / log_name).open("wb") as log:
        log.write((args.products / log_name).read_bytes())
        for index in range(len(plan["shards"])):
            folder = args.reports / f"{prefix}-{args.run_id}-{args.attempt}-{index}"
            if folder.is_symlink() or not folder.is_dir():
                raise ValueError("Native report must be a regular directory")
            receipt = json.loads((folder / "native-case-receipt.json").read_text())
            actual = qualify_results(plan, index, json.loads((folder / "tests.json").read_text()), json.loads((folder / "summary.json").read_text()))
            if actual != receipt:
                raise ValueError("Native receipt differs from retained actual test results")
            receipts.append(actual)
            results.append(str(folder / "native.xcresult"))
            log.write((folder / "native-test.log").read_bytes())
            reference = folder / "generated-automation-reference"
            if reference.exists():
                for source in reference.rglob("*"):
                    if source.is_file():
                        destination = args.output / "generated-automation-reference" / source.relative_to(reference)
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        if destination.exists() and file_digest(destination) != file_digest(source):
                            raise ValueError("Native-generated reference files disagree across shards")
                        shutil.copy2(source, destination)
    if plan["platform"] == "iOS Simulator":
        shutil.copy2(args.output / log_name, args.output / "xcodebuild-ios-raw.log")
    verified = verify_receipts(plan, receipts)
    (args.output / "native-case-inventory.json").write_text(json.dumps(verified, indent=2) + "\n")
    if args.result.exists():
        raise ValueError("Merged native result must be fresh")
    args.result.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "xcresulttool", "merge", "--output-path", str(args.result), *results], check=True, timeout=120)
    merged = {kind: json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(args.result)], text=True, timeout=60)) for kind in ("tests", "summary")}
    complete = make_plan(plan["inventory"], args.source_sha, args.run_id, args.attempt, 1, plan["platform"])
    qualify_results(complete, 0, merged["tests"], merged["summary"], maximum_devices=len(plan["shards"]))


def main():
    import argparse
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "run", "combine"):
        command = sub.add_parser(name)
        for key in ("source-sha", "run-id", "attempt"):
            command.add_argument("--" + key, required=True)
        command.add_argument("--derived", type=Path, required=True)
        command.add_argument("--output", type=Path, required=True)
        command.add_argument("--sdk-receipt", type=Path, required=True)
        command.add_argument("--destination", default="platform=macOS,arch=arm64")
        if name == "prepare": command.add_argument("--platform", choices=("macOS", "iOS Simulator"), default="macOS")
        if name != "prepare":
            command.add_argument("--products", type=Path, required=True)
            command.add_argument("--prepared-sha256", required=True)
        if name == "run": command.add_argument("--shard", type=int, required=True)
        if name == "combine":
            command.add_argument("--reports", type=Path, required=True)
            command.add_argument("--result", type=Path, required=True)
    args = parser.parse_args()
    {"prepare": prepare, "run": run_shard, "combine": combine}[args.command](args)


if __name__ == "__main__": main()
