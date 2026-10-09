#!/usr/bin/env python3
"""SDK-free regressions for fresh UI artifacts and the actual CI shell commands."""

from __future__ import annotations

import copy
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parents[2]
sys.path.insert(0, str(SCRIPTS))
from validate_ios_ui_xctestrun import BUILD_MARKER, qualify  # noqa: E402

SOURCE_SHA = "a" * 40
EXPECTED_TESTS = [
    "HealthMdUILaunchTests/testAppLaunches",
    "ExportJourneyUITests/testFirstRunExportJourney_showsExportButton_andCompletesExport",
    "ExportJourneyUITests/testDateRangePresets_visibleAndCustomPickersHiddenByDefault",
    "ExportJourneyUITests/testDateRangePresets_customRevealsStartAndEndPickers",
    "OnboardingJourneyUITests/testReleaseNotesStillAppearForReturningUsers",
    "PaywallJourneyUITests/testPaywallShown_whenQuotaExhausted",
    "ScheduleSyncJourneyUITests/testSyncView_showsDisconnectedState",
    "ConfigurationProtectionJourneyUITests/testProtectedProfileDetailActionsAreBlocked",
    "ConfigurationProtectionJourneyUITests/testProtectedProfileSchedulesCardIsLockedOnScheduleTab",
    "ConfigurationProtectionJourneyUITests/testBlockedChangeToastNavigatesToProtectionToggle",
    "ConfigurationProtectionJourneyUITests/testTurningProtectionOffRestoresConfigurationControls",
    "ExportProfilesJourneyUITests/testQA_MigrationShowsDefaultProfileInSettings",
    "ExportProfilesJourneyUITests/testQA_ManagementDuplicateRenameDeleteAndLastProfileGuard",
    "ExportProfilesJourneyUITests/testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter",
    "ExportProfilesJourneyUITests/testQA_ManageProfilesViewDetailCopyIDActivateAndRename",
]


def make_products(derived: Path, version: int = 1) -> tuple[Path, dict]:
    products = derived / "Build/Products"
    base = "Debug-iOS-iphonesimulator/"
    bundles = [
        (base + "HealthMd.app", "HealthMd", "com.codybontecou.obsidianhealth"),
        (base + "HealthMdUITests-Runner.app", "HealthMdUITests-Runner", "com.codybontecou.HealthMdUITests.xctrunner"),
        (base + "HealthMdUITests-Runner.app/PlugIns/HealthMdUITests.xctest", "HealthMdUITests", "com.codybontecou.HealthMdUITests"),
    ]
    for relative, executable, identifier in bundles:
        bundle = products / relative
        bundle.mkdir(parents=True, exist_ok=True)
        (bundle / executable).write_bytes(b"synthetic SDK-free executable")
        (bundle / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": executable,
            "CFBundleIdentifier": identifier,
            "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
        }))
    target = {
        "BlueprintName": "HealthMdUITests", "ProductModuleName": "HealthMdUITests", "IsUITestBundle": True,
        "TestHostPath": "__TESTROOT__/" + bundles[1][0],
        "UITargetAppPath": "__TESTROOT__/" + bundles[0][0],
        "TestBundlePath": "__TESTHOST__/PlugIns/HealthMdUITests.xctest",
        "DependentProductPaths": ["__TESTROOT__/" + b[0] for b in bundles],
        "TestTimeoutsEnabled": False, "DefaultTestExecutionTimeAllowance": 600,
        "UITargetAppCommandLineArguments": ["synthetic-qa-argument"],
        "UITargetAppEnvironmentVariables": {"SYNTHETIC_QA": "preserve-this-value"},
    }
    payload = {"__xctestrun_metadata__": {
        "FormatVersion": version, "ContainerInfo": {"SchemeName": "HealthMd-UITests-iOS"},
    }}
    if version == 1:
        payload["HealthMdUITests"] = target
    else:
        payload["TestConfigurations"] = [{"Name": "Test Scheme Action", "IsEnabled": True, "TestTargets": [target]}]
    manifest = products / "HealthMd-UITests-iOS_iphonesimulator26.5-arm64-x86_64.xctestrun"
    manifest.write_bytes(plistlib.dumps(payload))
    return manifest, payload


def selected_target(payload: dict) -> dict:
    return payload.get("HealthMdUITests") or payload["TestConfigurations"][0]["TestTargets"][0]


class ArtifactQualificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.derived = (Path(self.temporary.name) / "fresh-derived-data").resolve()
        self.derived.mkdir()
        (self.derived / BUILD_MARKER).touch()

    def test_formats_one_and_two_preserve_generated_bytes_and_bind_products(self) -> None:
        for version in (1, 2):
            with self.subTest(version=version):
                manifest, _ = make_products(self.derived, version)
                original = manifest.read_bytes()
                selected, receipt = qualify(self.derived, SOURCE_SHA)
                self.assertEqual(selected, manifest)
                self.assertEqual(manifest.read_bytes(), original)
                self.assertEqual(receipt["format_version"], version)
                self.assertEqual(receipt["source_sha"], SOURCE_SHA)
                self.assertEqual(len(receipt["products"]), 3)
                self.assertNotIn("preserve-this-value", json.dumps(receipt))

    def test_missing_ambiguous_stale_and_unmarked_artifacts_fail_closed(self) -> None:
        with self.assertRaises(ValueError):
            qualify(self.derived, SOURCE_SHA)
        manifest, _ = make_products(self.derived)
        extra = manifest.with_name("old.xctestrun")
        extra.write_bytes(manifest.read_bytes())
        with self.assertRaisesRegex(ValueError, "exactly one"):
            qualify(self.derived, SOURCE_SHA)
        extra.unlink()
        stamp = (self.derived / BUILD_MARKER).stat().st_mtime_ns
        os.utime(manifest, ns=(stamp - 1_000_000_000, stamp - 1_000_000_000))
        with self.assertRaisesRegex(ValueError, "stale"):
            qualify(self.derived, SOURCE_SHA)
        manifest.touch()
        (self.derived / BUILD_MARKER).unlink()
        with self.assertRaisesRegex(ValueError, "marker"):
            qualify(self.derived, SOURCE_SHA)

    def test_manifest_identity_filters_and_destination_artifacts_fail_closed(self) -> None:
        for version in (1, 2):
            for key, bad in [
                ("BlueprintName", "OtherUITests"), ("ProductModuleName", "OtherModule"),
                ("IsUITestBundle", False), ("IsEnabled", "true"),
                ("OnlyTestIdentifiers", ["testUnrelated"]), ("SkipTestIdentifiers", ["testNoData"]),
                ("UseDestinationArtifacts", True), ("UseDestinationArtifacts", "false"),
                ("TestHostBundleIdentifier", "other.runner"), ("UITargetAppBundleIdentifier", "other.app"),
            ]:
                with self.subTest(version=version, key=key, bad=bad):
                    manifest, payload = make_products(self.derived, version)
                    selected_target(payload)[key] = bad
                    manifest.write_bytes(plistlib.dumps(payload))
                    with self.assertRaises(ValueError):
                        qualify(self.derived, SOURCE_SHA)

    def test_wrong_scheme_unsupported_format_and_enabled_extra_targets_are_rejected(self) -> None:
        for version in (1, 2):
            for scenario in ("scheme", "format", "extra-target", "extra-configuration"):
                if version == 1 and scenario == "extra-configuration":
                    continue
                with self.subTest(version=version, scenario=scenario):
                    manifest, payload = make_products(self.derived, version)
                    if scenario == "scheme":
                        payload["__xctestrun_metadata__"]["ContainerInfo"]["SchemeName"] = "OtherScheme"
                    elif scenario == "format":
                        payload["__xctestrun_metadata__"]["FormatVersion"] = 3
                    elif scenario == "extra-configuration":
                        payload["TestConfigurations"].append(copy.deepcopy(payload["TestConfigurations"][0]))
                    elif version == 1:
                        payload["OtherTests"] = copy.deepcopy(payload["HealthMdUITests"])
                    else:
                        payload["TestConfigurations"][0]["TestTargets"].append(copy.deepcopy(selected_target(payload)))
                    manifest.write_bytes(plistlib.dumps(payload))
                    with self.assertRaises(ValueError):
                        qualify(self.derived, SOURCE_SHA)

    def test_disabled_extra_configuration_does_not_change_qualification(self) -> None:
        manifest, payload = make_products(self.derived, 2)
        payload["TestConfigurations"].append({"IsEnabled": False, "Name": "Dormant"})
        selected_target(payload)["UseDestinationArtifacts"] = False
        manifest.write_bytes(plistlib.dumps(payload))
        self.assertEqual(qualify(self.derived, SOURCE_SHA)[0], manifest)

    def test_missing_wrong_and_outside_products_are_rejected(self) -> None:
        for scenario in ("executable", "dependency", "platform", "identifier", "outside", "wrong-configuration"):
            with self.subTest(scenario=scenario):
                manifest, payload = make_products(self.derived)
                app = manifest.parent / "Debug-iOS-iphonesimulator/HealthMd.app"
                if scenario == "executable":
                    (app / "HealthMd").unlink()
                elif scenario == "dependency":
                    selected_target(payload)["DependentProductPaths"].append("__TESTROOT__/missing.appex")
                elif scenario in ("platform", "identifier"):
                    info = plistlib.loads((app / "Info.plist").read_bytes())
                    info["CFBundleSupportedPlatforms" if scenario == "platform" else "CFBundleIdentifier"] = ["iPhoneOS"] if scenario == "platform" else "other.app"
                    (app / "Info.plist").write_bytes(plistlib.dumps(info))
                elif scenario == "outside":
                    selected_target(payload)["UITargetAppPath"] = "__TESTROOT__/../../outside.app"
                else:
                    selected_target(payload)["UITargetAppPath"] = "__TESTROOT__/Release-iphonesimulator/HealthMd.app"
                manifest.write_bytes(plistlib.dumps(payload))
                with self.assertRaises(ValueError):
                    qualify(self.derived, SOURCE_SHA)

    def test_missing_scheme_metadata_is_supported_but_source_sha_is_required(self) -> None:
        manifest, payload = make_products(self.derived)
        del payload["__xctestrun_metadata__"]["ContainerInfo"]
        manifest.write_bytes(plistlib.dumps(payload))
        self.assertEqual(qualify(self.derived, SOURCE_SHA)[0], manifest)
        with self.assertRaisesRegex(ValueError, "source SHA"):
            qualify(self.derived, "branch-name")

    def test_owned_product_root_can_contain_double_underscores(self) -> None:
        derived = self.derived / "owned__ui__artifacts"
        derived.mkdir()
        (derived / BUILD_MARKER).touch()
        manifest, _ = make_products(derived)
        original = manifest.read_bytes()
        selected, receipt = qualify(derived, SOURCE_SHA)
        self.assertEqual(selected, manifest)
        self.assertEqual(receipt["source_sha"], SOURCE_SHA)
        self.assertEqual(manifest.read_bytes(), original)

    def test_receipt_binds_debug_code_without_rewriting_the_manifest(self) -> None:
        manifest, _ = make_products(self.derived)
        original = manifest.read_bytes()
        app = manifest.parent / "Debug-iOS-iphonesimulator/HealthMd.app"
        debug_binary = app / "HealthMd.debug.dylib"
        debug_binary.write_bytes(b"first synthetic debug payload")
        first = qualify(self.derived, SOURCE_SHA)[1]
        debug_binary.write_bytes(b"different synthetic debug payload")
        second = qualify(self.derived, SOURCE_SHA)[1]
        self.assertNotEqual(first["products"][0]["sha256"], second["products"][0]["sha256"])
        self.assertEqual(first["xctestrun_sha256"], second["xctestrun_sha256"])
        self.assertEqual(manifest.read_bytes(), original)


def ui_steps() -> tuple[str, dict[str, str]]:
    workflow = (REPO / ".github/workflows/apple-ci.yml").read_text()
    job = workflow.split("  test-ios-ui:\n", 1)[1].split("\n  connectivity-package:", 1)[0]
    pieces = re.split(r"^      - name: ", job, flags=re.MULTILINE)[1:]
    return job, {piece.splitlines()[0]: piece for piece in pieces}


def shell_body(step: str) -> str:
    body = step.split("        run: |\n", 1)[1]
    return "\n".join(line[10:] if line.startswith("          ") else line for line in body.splitlines())


class WorkflowExecutionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        scripts = self.root / "scripts"
        scripts.mkdir()
        shutil.copy(SCRIPTS / "validate_ios_ui_xctestrun.py", scripts)
        self.calls = self.root / "calls.jsonl"
        self.device_calls = self.root / "device-calls.jsonl"
        self.output = self.root / "github-output"
        stub = (
            "#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\n"
            f"sys.path.insert(0,{str(Path(__file__).parent)!r})\n"
            "from test_ios_ui_build_contract import make_products\n"
            "args=sys.argv[1:]\n"
            "with Path(os.environ['MD_MOCK_CALLS']).open('a') as f: f.write(json.dumps(args)+'\\n')\n"
            "if os.environ.get('MD_MOCK_FAILURE')==args[0]:\n"
            "    print('error: controlled Xcode failure');sys.exit(73)\n"
            "if args[0]=='build-for-testing':\n"
            "    make_products(Path(args[args.index('-derivedDataPath')+1]))\n"
            "    print('** TEST BUILD SUCCEEDED **')\n"
            "else:\n"
            "    print(\"Test Case 'synthetic SDK-free command contract' passed\")\n"
            "    print('Executed 1 test, with 0 failures')\n"
        )
        self.executable(self.bin / "xcodebuild", stub)
        self.executable(self.bin / "git", f"#!/bin/sh\nprintf '%s\\n' '{SOURCE_SHA}'\n")
        self.executable(self.bin / "xcrun", (
            "#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\n"
            "args=sys.argv[1:]\n"
            "with Path(os.environ['MD_MOCK_DEVICE_CALLS']).open('a') as f: f.write(json.dumps(args)+'\\n')\n"
            "if os.environ.get('MD_MOCK_SIMCTL_FAILURE')==args[1]: sys.exit(73)\n"
            "if args[:2]==['simctl','install'] and not Path(args[3]).is_dir(): sys.exit(74)\n"
        ))
        self.executable(scripts / "select-ios-simulator.sh", (
            "#!/bin/sh\ncase \"$*\" in\n"
            "  *iPad*) printf '%s\\n' 'platform=iOS Simulator,id=SYNTHETIC-IPAD';;\n"
            "  *) printf '%s\\n' 'platform=iOS Simulator,id=SYNTHETIC-IPHONE';;\nesac\n"
        ))
        self.environment = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", GITHUB_OUTPUT=str(self.output), MD_MOCK_CALLS=str(self.calls), MD_MOCK_DEVICE_CALLS=str(self.device_calls))
        self.job, self.steps = ui_steps()

    @staticmethod
    def executable(path: Path, content: str) -> None:
        path.write_text(content)
        path.chmod(0o755)

    def run_step(self, name: str, artifact: str = "") -> subprocess.CompletedProcess:
        script = shell_body(self.steps[name])
        script = script.replace("${{ steps.ui_artifacts.outputs.xctestrun }}", artifact)
        script = script.replace("${{ steps.ui_artifacts.outputs.app }}", self.app if artifact else "")
        script = script.replace("${{ steps.simulator.outputs.ios_destination }}", "platform=iOS Simulator,id=SYNTHETIC-IPHONE")
        return subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], cwd=self.root, env=self.environment, text=True, capture_output=True)

    def build(self) -> str:
        result = self.run_step("Build UI test artifacts once")
        self.assertEqual(result.returncode, 0, result.stderr)
        outputs = dict(line.split("=", 1) for line in self.output.read_text().splitlines())
        self.assertEqual(set(outputs), {"xctestrun", "app"})
        receipt = json.loads((self.root / "build/logs/ios-ui-build-receipt.json").read_text())
        self.app = outputs["app"]
        self.assertEqual(self.app, receipt["products"][0]["path"])
        return outputs["xctestrun"]

    def test_one_generic_build_and_two_run_only_commands_share_exact_artifact(self) -> None:
        artifact = self.build()
        for name in ("Select newest compatible iOS Simulator", "Run UI smoke tests (iOS)"):
            result = self.run_step(name, artifact)
            self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([args[0] for args in calls], ["build-for-testing"] + ["test-without-building"] * 2)
        build = calls[0]
        self.assertEqual(build[build.index("-destination") + 1], "generic/platform=iOS Simulator")
        self.assertEqual(build[build.index("-configuration") + 1], "Debug-iOS")
        self.assertEqual(build[build.index("-scheme") + 1], "HealthMd-UITests-iOS")
        self.assertTrue(Path(build[build.index("-derivedDataPath") + 1]).name.startswith("ios-ui-derived-data."))
        for setting in ("CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER="):
            self.assertIn(setting, build)
        selections = []
        for args, count in zip(calls[1:], (9, 6)):
            self.assertEqual(args[args.index("-xctestrun") + 1], artifact)
            self.assertFalse(set(args) & {"-project", "-workspace", "-scheme", "-configuration"})
            self.assertEqual(args[args.index("-test-timeouts-enabled") + 1], "YES")
            self.assertEqual(args[args.index("-default-test-execution-time-allowance") + 1], "180")
            self.assertEqual(args[args.index("-maximum-test-execution-time-allowance") + 1], "300")
            selected = [a.split("HealthMdUITests/", 1)[1] for a in args if a.startswith("-only-testing:")]
            self.assertEqual(len(selected), count)
            selections.extend(selected)
        self.assertEqual(selections, EXPECTED_TESTS)
        self.assertEqual(
            [json.loads(line) for line in self.device_calls.read_text().splitlines()],
            [
                ["simctl", "bootstatus", "SYNTHETIC-IPHONE", "-b"],
                ["simctl", "install", "SYNTHETIC-IPHONE", self.app],
            ],
        )
        self.assertTrue((self.root / "build/logs/build-ios-ui-compile.log").is_file())
        self.assertTrue((self.root / "build/logs/ios-ui-build-receipt.json").is_file())

    def test_a_second_build_uses_a_new_directory_instead_of_old_artifacts(self) -> None:
        first = self.build()
        self.output.write_text("")
        second = self.build()
        self.assertNotEqual(first, second)
        self.assertTrue(Path(first).is_file())
        self.assertTrue(Path(second).is_file())

    def test_compile_and_test_failures_propagate_through_tee_and_grep(self) -> None:
        self.environment["MD_MOCK_FAILURE"] = "build-for-testing"
        self.assertEqual(self.run_step("Build UI test artifacts once").returncode, 73)
        self.assertFalse(self.output.exists())
        self.environment.pop("MD_MOCK_FAILURE")
        artifact = self.build()
        self.environment["MD_MOCK_FAILURE"] = "test-without-building"
        self.assertEqual(self.run_step("Run UI smoke tests (iOS)", artifact).returncode, 73)
        self.environment.pop("MD_MOCK_FAILURE")
        self.environment["MD_MOCK_SIMCTL_FAILURE"] = "install"
        self.assertEqual(self.run_step("Select newest compatible iOS Simulator", artifact).returncode, 73)

    def test_existing_gate_budgets_and_compile_warning_retention_are_preserved(self) -> None:
        self.assertIn("timeout-minutes: 60", self.job)
        self.assertIn("timeout-minutes: 35", self.steps["Run UI smoke tests (iOS)"])
        for name in ("Check warnings (iOS UI)", "Upload iOS UI artifacts"):
            self.assertIn("!cancelled()", self.steps[name])
            self.assertIn("build/logs/build-ios-ui-compile.log", self.steps[name])
            self.assertIn("build/logs/build-ios-ui.log", self.steps[name])
        self.assertNotIn("continue-on-error", self.job)
        self.assertNotIn("-retry-tests-on-failure", self.job)
        self.assertIn("test_ios_ui_build_contract.py", self.steps["Test UI build and execution contract"])


if __name__ == "__main__":
    unittest.main()
