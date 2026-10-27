#!/usr/bin/env python3
"""Run balanced UI lanes and require the complete, successful current inventory."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shlex
import time
import subprocess
import sys

from validate_ios_ui_xctestrun import qualify

# Preserve the phone inventory, including history and folder-browser regressions, plus four tablet cases.
# Keep stateful XCTest classes together within each device family.
SHARDS = (
    (
        "ExportProfilesJourneyUITests/testQA_ManagementDuplicateRenameDeleteAndLastProfileGuard",
        "ExportProfilesJourneyUITests/testQA_ManageProfilesViewDetailCopyIDActivateAndRename",
        "ExportProfilesJourneyUITests/testQA_MigrationShowsDefaultProfileInSettings",
        "ExportProfilesJourneyUITests/testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter",
        "ExportProfilesJourneyUITests/testQA_ProfileThirtyMinuteRefreshPersistsWithWeeklyCadence",
        "ExportProfilesJourneyUITests/testQA_ProfileHourlyRefreshPersistsWithWeeklyCadence",
    ),
    (
        "ConfigurationProtectionJourneyUITests/testProtectedProfileDetailActionsAreBlocked",
        "ConfigurationProtectionJourneyUITests/testProtectedProfileSchedulesCardIsLockedOnScheduleTab",
        "ConfigurationProtectionJourneyUITests/testTurningProtectionOffRestoresConfigurationControls",
        "HealthMdUILaunchTests/testAppLaunches",
        "OnboardingJourneyUITests/testReleaseNotesStillAppearForReturningUsers",
        "ScheduleSyncJourneyUITests/testSyncView_showsDisconnectedState",
    ),
    (
        "ExportJourneyUITests/testDateRangePresets_selectedCustomRemainsEnabledAfterLeavingAndReopeningExport",
        "ExportJourneyUITests/testDateRangePresets_customRevealsStartAndEndPickers",
        "ExportJourneyUITests/testDateRangePresets_visibleAndCustomPickersHiddenByDefault",
        "ExportJourneyUITests/testFirstRunExportJourney_showsExportButton_andCompletesExport",
        "ExportJourneyUITests/testConfiguredGateway_admitsExportWithoutLocalFolder",
        "ExportJourneyUITests/testSuccessfulExport_folderBrowserRendersOnFirstPresentationAndReopens",
        "PaywallJourneyUITests/testPaywallShown_whenQuotaExhausted",
        "HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide",
        "HistoryAuthorizationJourneyUITests/testBoundedUnknownHistoryRechecksExecutionWithoutClaimingFullAccess",
        "HistoryAuthorizationJourneyUITests/testDelayedAssessmentCanContinueUnverifiedWithoutBlockingReadableExport",
    ),
    (
        "ExportJourneyUITests/testNoDataExport_showsGuidanceInsteadOfGenericError",
        "HistoryAuthorizationJourneyUITests/testUnavailableHistoryAtLargeTextHasAccessibleAction",
        "HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide",
        "HistoryAuthorizationJourneyUITests/testUnknownHistoryPreviewHasAccessibleActionOnNativeRoot",
    ),
)
DEVICE_FAMILIES = ("iPhone", "iPhone", "iPhone", "iPad")


def device_family(index: int) -> str:
    selection(index)
    return DEVICE_FAMILIES[index]


def qualify_device(payload: dict, destination: str, index: int) -> str:
    prefix = "platform=iOS Simulator,id="
    if not destination.startswith(prefix):
        raise ValueError("One explicit simulator destination is required")
    udid = destination[len(prefix):]
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", udid):
        raise ValueError("An exact simulator UUID is required")
    devices = payload.get("devices")
    if not isinstance(devices, dict) or any(not isinstance(v, list) for v in devices.values()):
        raise ValueError("Invalid simulator device inventory")
    matches = [d for values in devices.values() for d in values if isinstance(d, dict) and d.get("udid") == udid]
    family = device_family(index)
    if len(matches) != 1 or matches[0].get("isAvailable") is not True or not str(matches[0].get("deviceTypeIdentifier", "")).startswith("com.apple.CoreSimulator.SimDeviceType." + family + "-"):
        raise ValueError("Actual simulator does not match the required device family")
    return family


def metadata(run_id: str, attempt: str, source_sha: str) -> None:
    if not run_id.isdecimal() or int(run_id) < 1 or not attempt.isdecimal() or int(attempt) < 1:
        raise ValueError("Run ID and attempt must be positive integers")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("The exact source SHA is required")


def selection(index: int) -> tuple[str, ...]:
    if type(index) is not int or not 0 <= index < len(SHARDS):
        raise ValueError("Unknown UI shard")
    return SHARDS[index]


def test_command(manifest: Path, destination: str, result: Path, index: int) -> list[str]:
    if not destination.startswith("platform=iOS Simulator,id="):
        raise ValueError("One explicit iOS simulator destination is required")
    return [
        "xcodebuild", "test-without-building", "-xctestrun", str(manifest),
        "-destination", destination, "-resultBundlePath", str(result),
        # Each hosted lane owns one already-booting simulator, avoiding Xcode's
        # extra cloned simulators and their redundant startup/install costs.
        "-parallel-testing-enabled", "NO",
        *["-only-testing:HealthMdUITests/" + name for name in selection(index)],
        "-test-timeouts-enabled", "YES",
        "-default-test-execution-time-allowance", "180",
        "-maximum-test-execution-time-allowance", "300",
    ]


def qualify_results(tree: dict, summary: dict, index: int) -> dict:
    expected = set(selection(index))
    cases = []

    def visit(node):
        if isinstance(node, dict):
            if node.get("nodeType") == "Test Case":
                name = node.get("nodeIdentifier")
                if not isinstance(name, str) or node.get("result") != "Passed":
                    raise ValueError("Every selected UI case must actually pass")
                cases.append(name.removesuffix("()"))
            for value in node.values(): visit(value)
        elif isinstance(node, list):
            for value in node: visit(value)

    visit(tree)
    if len(cases) != len(set(cases)) or set(cases) != expected:
        raise ValueError("Actual UI cases do not exactly match this lane's selection")
    if (summary.get("result") != "Passed" or summary.get("totalTestCount") != len(expected)
            or summary.get("passedTests") != len(expected) or summary.get("failedTests") != 0
            or summary.get("skippedTests") != 0):
        raise ValueError("UI xcresult summary disagrees with the complete passing selection")
    return {"cases": sorted(cases), "passed": len(cases), "device_family": device_family(index)}


def verify_shards(reports: Path, run_id: str, attempt: str, source_sha: str) -> dict:
    metadata(run_id, attempt, source_sha)
    expected_dirs = {f"ios-ui-{run_id}-{attempt}-shard-{i}" for i in range(len(SHARDS))}
    if {p.name for p in reports.iterdir()} != expected_dirs:
        raise ValueError("Missing or unexpected UI shard artifacts")
    combined = []
    for index in range(len(SHARDS)):
        folder = reports / f"ios-ui-{run_id}-{attempt}-shard-{index}"
        if folder.is_symlink() or not folder.is_dir():
            raise ValueError("UI artifact must be a regular directory")
        files = list(folder.rglob("ui-case-receipt.json"))
        if len(files) != 1 or files[0].is_symlink():
            raise ValueError("Exactly one UI case receipt is required per shard")
        receipt = json.loads(files[0].read_text())
        if any(receipt.get(k) != v for k, v in {
            "source_sha": source_sha, "run_id": run_id, "attempt": attempt, "shard": index,
            "cases": sorted(selection(index)), "passed": len(selection(index)), "device_family": device_family(index),
        }.items()):
            raise ValueError("UI receipt source, run, shard or actual case inventory mismatch")
        combined.extend((device_family(index), case) for case in receipt["cases"])
    if len(combined) != len(set(combined)):
        raise ValueError("Duplicate UI cases within a device family")
    return {"source_sha": source_sha, "run_id": run_id, "attempt": attempt,
            "shards": len(SHARDS), "passed": len(combined),
            "cases": [{"device_family": family, "case": case} for family, case in sorted(combined)]}


def run(args) -> int:
    started = time.monotonic()
    metadata(args.run_id, args.attempt, args.source_sha)
    # Requalify the freshly built, unmodified manifest and its actual binaries.
    manifest, current = qualify(args.xctestrun.parent.parent.parent, args.source_sha)
    receipt = json.loads(args.build_receipt.read_text())
    archive_digest = receipt.pop("prepared_archive_sha256", None)
    if not re.fullmatch(r"[0-9a-f]{64}", args.prepared_sha256) or archive_digest != args.prepared_sha256:
        raise ValueError("Restored products lack the exact producer archive receipt")
    if manifest != args.xctestrun.resolve() or current != receipt:
        raise ValueError("UI built products differ from the qualified source receipt")
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.result.parent.mkdir(parents=True, exist_ok=True)
    if args.result.exists():
        raise ValueError("UI result path must be fresh")
    command = test_command(manifest, args.destination, args.result, args.shard)
    print(json.dumps({"source_sha": args.source_sha, "command": command}), flush=True)
    raw_devices = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                                 check=True, capture_output=True, text=True, timeout=15).stdout
    family = qualify_device(json.loads(raw_devices), args.destination, args.shard)
    # Setup and native execution share the original 35m phone / 15m tablet budget,
    # with 30s reserved for owned cleanup and post-execution qualification.
    seconds = (870 if family == "iPad" else 2070) - (time.monotonic() - started)
    if seconds <= 0:
        raise ValueError("UI admission exhausted the native deadline")
    setup = shlex.join([sys.executable, str(Path(__file__).with_name("apple_nightly_ui.py")),
                        "ready-simulator", "--destination", args.destination, "--root", str(args.log.parent / "ui-simulator"),
                        "--source-sha", args.source_sha]) + "\n" + shlex.join([
                            "xcrun", "simctl", "install", args.destination.split("id=", 1)[1], current["products"][0]["path"]])
    plan = {"setup": setup, "pipelines": [{"command": command, "raw": str(args.log),
             "filter": "Test Case|error:|PASSED|FAILED|Executed"}]}
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("run-owned-ui.py")),
                             "--lane", "shard", "--records", str(args.log.parent), "--seconds", str(seconds)],
                            input=json.dumps(plan), text=True, check=False)
    if result.returncode:
        return result.returncode
    owner = json.loads((args.log.parent / "ui-owner-shard.json").read_text())
    if owner.get("eligible_to_continue") is not True or (args.log.parent / "ui-owner-shard.abort").exists():
        raise ValueError("Native execution lacks clean owned completion")
    values = {}
    for kind in ("summary", "tests"):
        raw = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind,
                              "--path", str(args.result)], check=True, capture_output=True, text=True).stdout
        (args.log.parent / f"ui-{kind}.json").write_text(raw)
        values[kind] = json.loads(raw)
    actual = qualify_results(values["tests"], values["summary"], args.shard)
    actual.update(source_sha=args.source_sha, run_id=args.run_id, attempt=args.attempt, shard=args.shard)
    args.receipt.write_text(json.dumps(actual, indent=2) + "\n")
    print(f"Verified UI shard {args.shard}: {actual['passed']} selected cases actually passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    worker = commands.add_parser("run")
    for name in ("xctestrun", "build-receipt", "result", "log", "receipt"):
        worker.add_argument("--" + name, type=Path, required=True)
    worker.add_argument("--destination", required=True)
    worker.add_argument("--prepared-sha256", required=True)
    worker.add_argument("--shard", type=int, required=True)
    aggregate = commands.add_parser("verify")
    aggregate.add_argument("--reports", type=Path, required=True)
    aggregate.add_argument("--output", type=Path, required=True)
    for command in (worker, aggregate):
        command.add_argument("--source-sha", required=True)
        command.add_argument("--run-id", required=True)
        command.add_argument("--attempt", required=True)
    args = parser.parse_args()
    try:
        if args.command == "run": return run(args)
        result = verify_shards(args.reports, args.run_id, args.attempt, args.source_sha)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(f"Verified all {result['shards']} UI shards: {result['passed']} actual passing cases")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"UI shard qualification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__": sys.exit(main())
