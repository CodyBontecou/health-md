#!/usr/bin/env python3
"""Run balanced UI lanes and require the complete, successful current inventory."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

from validate_ios_ui_xctestrun import qualify

# All fourteen pre-existing CI selectors plus the Custom reentry regression. Keep XCTest classes together: their
# journeys intentionally share installed-app fixture state within a class.
SHARDS = (
    (
        "ExportProfilesJourneyUITests/testQA_ManagementDuplicateRenameDeleteAndLastProfileGuard",
        "ExportProfilesJourneyUITests/testQA_ManageProfilesViewDetailCopyIDActivateAndRename",
        "ExportProfilesJourneyUITests/testQA_MigrationShowsDefaultProfileInSettings",
        "ExportProfilesJourneyUITests/testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter",
    ),
    (
        "ConfigurationProtectionJourneyUITests/testProtectedProfileDetailActionsAreBlocked",
        "ConfigurationProtectionJourneyUITests/testProtectedProfileSchedulesCardIsLockedOnScheduleTab",
        "ConfigurationProtectionJourneyUITests/testTurningProtectionOffRestoresConfigurationControls",
        "HealthMdUILaunchTests/testAppLaunches",
        "OnboardingJourneyUITests/testReleaseNotesStillAppearForReturningUsers",
    ),
    (
        "ExportJourneyUITests/testDateRangePresets_selectedCustomRemainsEnabledAfterLeavingAndReopeningExport",
        "ExportJourneyUITests/testDateRangePresets_customRevealsStartAndEndPickers",
        "ExportJourneyUITests/testDateRangePresets_visibleAndCustomPickersHiddenByDefault",
        "ExportJourneyUITests/testFirstRunExportJourney_showsExportButton_andCompletesExport",
        "PaywallJourneyUITests/testPaywallShown_whenQuotaExhausted",
        "ScheduleSyncJourneyUITests/testSyncView_showsDisconnectedState",
    ),
)


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
    return {"cases": sorted(cases), "passed": len(cases)}


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
            "cases": sorted(selection(index)), "passed": len(selection(index)),
        }.items()):
            raise ValueError("UI receipt source, run, shard or actual case inventory mismatch")
        combined.extend(receipt["cases"])
    if len(combined) != len(set(combined)):
        raise ValueError("Duplicate UI cases across shards")
    return {"source_sha": source_sha, "run_id": run_id, "attempt": attempt,
            "shards": len(SHARDS), "passed": len(combined), "cases": sorted(combined)}


def run(args) -> int:
    metadata(args.run_id, args.attempt, args.source_sha)
    # Requalify the freshly built, unmodified manifest and its actual binaries.
    manifest, current = qualify(args.xctestrun.parent.parent.parent, args.source_sha)
    receipt = json.loads(args.build_receipt.read_text())
    if manifest != args.xctestrun.resolve() or current != receipt:
        raise ValueError("UI built products differ from the qualified source receipt")
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.result.parent.mkdir(parents=True, exist_ok=True)
    if args.result.exists():
        raise ValueError("UI result path must be fresh")
    command = test_command(manifest, args.destination, args.result, args.shard)
    print(json.dumps({"source_sha": args.source_sha, "command": command}), flush=True)
    with args.log.open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
    for line in args.log.read_text().splitlines():
        if re.search(r"Test Case|error:|PASSED|FAILED|Executed", line): print(line)
    if result.returncode:
        return result.returncode
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
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"UI shard qualification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__": sys.exit(main())
