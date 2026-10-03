#!/usr/bin/env python3
"""Hosted-only propagation control: execute the actual workflow shell with mocks.

Mock execution is not native/UI qualification. No YAML dependency or alternate
aggregation implementation; selectors/commands come from the shipped run block.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[3]
workflow = (ROOT / ".github/workflows/apple-ci.yml").read_text()
block = workflow.split("      - name: Run UI smoke tests (iOS)\n", 1)[1].split(
    "      - name: Run App Review export regression (iPad)\n", 1
)[0]
assert "timeout-minutes: 35" in block
assert "timeout-minutes: 60" in workflow.split("  test-ios-ui:", 1)[1].split("    steps:", 1)[0]
script = textwrap.dedent(block.split("        run: |\n", 1)[1]).replace(
    "${{ steps.simulator.outputs.ios_destination }}", "platform=iOS Simulator,id=mock"
)
ipad_block = workflow.split("      - name: Run App Review export regression (iPad)\n", 1)[1].split(
    "      - name: Check warnings (iOS UI)\n", 1
)[0]
assert "timeout-minutes: 15" in ipad_block
ipad_script = textwrap.dedent(ipad_block.split("        run: |\n", 1)[1])
expected = [
    ["HealthMdUILaunchTests/testAppLaunches",
     "ExportJourneyUITests/testFirstRunExportJourney_showsExportButton_andCompletesExport",
     "ExportJourneyUITests/testDateRangePresets_visibleAndCustomPickersHiddenByDefault",
     "ExportJourneyUITests/testDateRangePresets_customRevealsStartAndEndPickers",
     "OnboardingJourneyUITests/testReleaseNotesStillAppearForReturningUsers",
     "PaywallJourneyUITests/testPaywallShown_whenQuotaExhausted",
     "ScheduleSyncJourneyUITests/testSyncView_showsDisconnectedState",
     "ConfigurationProtectionJourneyUITests/testProtectedProfileManagementBlocksCreationAndRoutesToSetting",
     "ConfigurationProtectionJourneyUITests/testProtectedProfileDetailActionsAreBlocked",
     "ConfigurationProtectionJourneyUITests/testProtectedProfileSchedulesCardIsLockedOnScheduleTab"],
    ["ConfigurationProtectionJourneyUITests/testBlockedChangeToastNavigatesToProtectionToggle",
     "ConfigurationProtectionJourneyUITests/testTurningProtectionOffRestoresConfigurationControls",
     "ExportProfilesJourneyUITests/testQA_MigrationShowsDefaultProfileInSettings",
     "ExportProfilesJourneyUITests/testQA_ManagementDuplicateRenameDeleteAndLastProfileGuard",
     "ExportProfilesJourneyUITests/testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter",
     "ExportProfilesJourneyUITests/testQA_ManageProfilesViewDetailCopyIDActivateAndRename",
     "HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide",
     "HistoryAuthorizationJourneyUITests/testBoundedUnknownHistoryRechecksExecutionWithoutClaimingFullAccess",
     "HistoryAuthorizationJourneyUITests/testDelayedAssessmentCanContinueUnverifiedWithoutBlockingReadableExport"],
]
mock = '''#!/usr/bin/env python3
import json, os, pathlib, sys
path = pathlib.Path('calls.jsonl')
call = len(path.read_text().splitlines()) + 1 if path.exists() else 1
with path.open('a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')
print('unmatched mock output' if int(os.environ['NO_MATCH']) == call else f'Test Case mock-{call}')
sys.exit(int(os.environ[f'MOCK_EXIT_{call}']))
'''
tee = '''#!/usr/bin/env bash
/usr/bin/tee "$@"
status=$?
call=$(wc -l < calls.jsonl)
if [[ "$call" -eq "$TEE_FAIL_CALL" ]]; then echo 'mock tee failure' >&2; exit 17; fi
exit "$status"
'''
grep = '''#!/usr/bin/env bash
/usr/bin/grep "$@"
status=$?
call=$(wc -l < calls.jsonl)
if [[ "$call" -eq "$GREP_FAIL_CALL" ]]; then echo 'mock grep parser failure' >&2; exit 2; fi
exit "$status"
'''
cases = [(0, 0, 0, 0, 0, 0), (65, 0, 0, 0, 0, 65), (0, 70, 0, 0, 0, 70),
         (65, 70, 0, 0, 0, 65), (0, 0, 1, 0, 0, 1), (0, 0, 0, 2, 0, 17),
         (0, 0, 0, 0, 1, 2), (65, 0, 0, 1, 0, 17), (65, 0, 0, 0, 1, 2)]
for first, second, no_match, tee_fail, grep_fail, expected_exit in cases:
    with tempfile.TemporaryDirectory(prefix="health172-ui-status-") as directory:
        cwd = Path(directory)
        scripts = cwd / "scripts"
        scripts.mkdir()
        # Execute the ACTUAL pinned wrapper/anchor, not a mock owner or a
        # parallel status aggregator. Only native/plumbing outputs are mocked.
        shutil.copyfile(ROOT / "apps/apple/scripts/run-owned-ui.py", scripts / "run-owned-ui.py")
        binaries = cwd / "bin"
        binaries.mkdir()
        xcrun = "#!/usr/bin/env bash\necho 'iPad Pro (10000000-0000-0000-0000-000000000001) (Shutdown)'\n"
        for name, content in [("xcodebuild", mock), ("tee", tee), ("grep", grep), ("xcrun", xcrun)]:
            file = binaries / name
            file.write_text(content)
            file.chmod(0o755)
        raw = cwd / "build/logs/build-ios-ui.log"
        raw.parent.mkdir(parents=True)
        raw.write_text("earlier raw receipt\n")
        env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                   MOCK_EXIT_1=str(first), MOCK_EXIT_2=str(second), MOCK_EXIT_3="0",
                   NO_MATCH=str(no_match), TEE_FAIL_CALL=str(tee_fail), GREP_FAIL_CALL=str(grep_fail))
        result = subprocess.run(["bash", "-c", script], cwd=cwd, env=env,
                                capture_output=True, text=True, timeout=10)
        assert result.returncode == expected_exit, (first, second, no_match, tee_fail, result)
        calls = [json.loads(line) for line in (cwd / "calls.jsonl").read_text().splitlines()]
        assert len(calls) == 2, calls
        for args, selectors in zip(calls, expected):
            actual = [arg.split("HealthMdUITests/", 1)[1] for arg in args if arg.startswith("-only-testing:")]
            assert actual == selectors, actual
            for flag, value in [("-destination", "platform=iOS Simulator,id=mock"),
                                ("-configuration", "Debug-iOS"), ("-test-timeouts-enabled", "YES"),
                                ("-default-test-execution-time-allowance", "180"),
                                ("-maximum-test-execution-time-allowance", "300")]:
                assert args[args.index(flag) + 1] == value, args
        receipt = raw.read_text()
        assert receipt.startswith("earlier raw receipt\n"), receipt
        assert ("unmatched mock output" if no_match == 1 else "Test Case mock-1") in receipt
        assert "Test Case mock-2" in receipt
        ownership = json.loads((raw.parent / "ui-owner-phone.json").read_text())
        assert ownership["process_clean"] is True and ownership["eligible_to_continue"] is True
        assert ownership["abort"] is None and ownership["exit_status"] == expected_exit
        for number, native in enumerate((first, second), 1):
            assert ownership["stages"][number - 1] == {
                "native": native, "tee": 17 if tee_fail == number else 0,
                "parser": 2 if grep_fail == number else (1 if no_match == number else 0),
            }, ownership
        assert "Owned UI lane=phone" in result.stdout
        if tee_fail: assert "mock tee failure" in result.stderr
        if grep_fail: assert "mock grep parser failure" in result.stderr
        print(f"PASS actual-shell first={first} second={second} no_match={no_match} tee_call={tee_fail} parser_call={grep_fail} exit={expected_exit}; both invoked/raw appended")
        if (first, second, no_match, tee_fail, grep_fail) == (0, 0, 0, 0, 0):
            tablet = subprocess.run(["bash", "-c", ipad_script], cwd=cwd, env=env,
                                    capture_output=True, text=True, timeout=10)
            assert tablet.returncode == 0, tablet
            third = json.loads((cwd / "calls.jsonl").read_text().splitlines()[2])
            assert [arg.split("HealthMdUITests/", 1)[1] for arg in third if arg.startswith("-only-testing:")] == [
                "ExportJourneyUITests/testNoDataExport_showsGuidanceInsteadOfGenericError",
                "HistoryAuthorizationJourneyUITests/testUnavailableHistoryAtLargeTextHasAccessibleAction",
                "HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide",
                "HistoryAuthorizationJourneyUITests/testUnknownHistoryPreviewHasAccessibleActionOnNativeRoot",
            ]
            assert third[third.index("-destination") + 1] == "platform=iOS Simulator,id=10000000-0000-0000-0000-000000000001"
            assert third[third.index("-default-test-execution-time-allowance") + 1] == "180"
            assert third[third.index("-maximum-test-execution-time-allowance") + 1] == "300"
            assert "Test Case mock-3" in raw.read_text()
            print("PASS actual tablet setup/ownership/four original selectors/15m step/180-300 case/raw append")
