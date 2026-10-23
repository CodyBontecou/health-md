#!/usr/bin/env python3
"""SDK-free regressions for fresh UI artifacts and the actual CI shell commands."""

from __future__ import annotations

import copy
import hashlib
import io
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parents[2]
sys.path.insert(0, str(SCRIPTS))
from validate_ios_ui_xctestrun import BUILD_MARKER, qualify  # noqa: E402
from prepared_ios_ui_artifacts import digest, pack, restore  # noqa: E402

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
    "ConfigurationProtectionJourneyUITests/testTurningProtectionOffRestoresConfigurationControls",
    "ExportProfilesJourneyUITests/testQA_MigrationShowsDefaultProfileInSettings",
    "ExportProfilesJourneyUITests/testQA_ManagementDuplicateRenameDeleteAndLastProfileGuard",
    "ExportProfilesJourneyUITests/testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter",
    "ExportProfilesJourneyUITests/testQA_ManageProfilesViewDetailCopyIDActivateAndRename",
    "HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide",
    "HistoryAuthorizationJourneyUITests/testBoundedUnknownHistoryRechecksExecutionWithoutClaimingFullAccess",
    "HistoryAuthorizationJourneyUITests/testDelayedAssessmentCanContinueUnverifiedWithoutBlockingReadableExport",
    "ExportJourneyUITests/testDateRangePresets_selectedCustomRemainsEnabledAfterLeavingAndReopeningExport",
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

    def test_prepared_transfer_preserves_manifest_bytes_modes_and_compile_log(self) -> None:
        manifest, _ = make_products(self.derived)
        (self.derived / "compile.log").write_text("original compiler warning evidence\n")
        app_binary = manifest.parent / "Debug-iOS-iphonesimulator/HealthMd.app/HealthMd"
        app_binary.chmod(0o755)
        archive = self.derived.parent / "products.tar.gz"
        checksum = pack(self.derived, SOURCE_SHA, archive)
        destination = self.derived.parent / "another-runner-root"
        destination.mkdir()
        copied, receipt = restore(archive, destination, SOURCE_SHA, checksum)
        self.assertEqual(copied.read_bytes(), manifest.read_bytes())
        self.assertEqual((destination / "compile.log").read_text(), "original compiler warning evidence\n")
        self.assertEqual((destination / app_binary.relative_to(self.derived)).stat().st_mode & 0o777, 0o755)
        self.assertEqual(receipt["prepared_archive_sha256"], checksum)
        for source, digest in (("b" * 40, checksum), (SOURCE_SHA, "0" * 64)):
            empty = self.derived.parent / ("rejected-" + source[:1] + digest[:1])
            empty.mkdir()
            with self.assertRaises(ValueError):
                restore(archive, empty, source, digest)
            self.assertEqual(list(empty.iterdir()), [])

    def test_prepared_transfer_rejects_modified_archive_and_nonempty_restore(self) -> None:
        make_products(self.derived)
        (self.derived / "compile.log").write_text("compiler evidence\n")
        archive = self.derived.parent / "products.tar.gz"
        checksum = pack(self.derived, SOURCE_SHA, archive)
        with self.assertRaisesRegex(ValueError, "empty"):
            restore(archive, self.derived, SOURCE_SHA, checksum)
        with archive.open("ab") as file:
            file.write(b"altered transport")
        empty = self.derived.parent / "empty"
        empty.mkdir()
        with self.assertRaisesRegex(ValueError, "digest"):
            restore(archive, empty, SOURCE_SHA, checksum)
        self.assertEqual(list(empty.iterdir()), [])

    def test_prepared_inventory_and_native_attestation_fail_closed(self) -> None:
        make_products(self.derived)
        (self.derived / "compile.log").write_text("compiler evidence\n")
        archive = self.derived.parent / "original.tar.gz"
        pack(self.derived, SOURCE_SHA, archive)
        for scenario in ("path", "symlink", "size", "mode", "content", "attestation", "missing-log", "duplicate"):
            with self.subTest(scenario=scenario):
                with tarfile.open(archive) as bundle:
                    entries = [(copy.copy(member), bundle.extractfile(member).read()) for member in bundle.getmembers()]
                metadata = json.loads(entries[0][1])
                index = next(i for i, (member, _) in enumerate(entries)
                             if member.name.endswith("/HealthMd.app/HealthMd"))
                member, data = entries[index]
                inventory = next(item for item in metadata["files"] if "products/" + item["path"] == member.name)
                if scenario == "path":
                    member.name = "products/../../outside"
                    inventory["path"] = "../../outside"
                elif scenario == "symlink":
                    member.type = tarfile.SYMTYPE
                    member.linkname = "../../outside"
                elif scenario == "size":
                    inventory["size"] += 1
                elif scenario == "mode":
                    member.mode ^= 0o100
                elif scenario in ("content", "attestation"):
                    data = b"altered native bytes"
                    member.size = len(data)
                    inventory["size"] = len(data)
                    if scenario == "attestation":
                        inventory["sha256"] = hashlib.sha256(data).hexdigest()
                elif scenario == "missing-log":
                    metadata["files"] = [item for item in metadata["files"] if item["path"] != "compile.log"]
                    entries = [(m, d) for m, d in entries if m.name != "products/compile.log"]
                elif scenario == "duplicate":
                    entries.append((copy.copy(member), data))
                if scenario in ("content", "attestation"):
                    entries[index] = (member, data)
                encoded = json.dumps(metadata).encode()
                entries[0][0].size = len(encoded)
                entries[0] = (entries[0][0], encoded)
                changed = self.derived.parent / (scenario + ".tar.gz")
                with tarfile.open(changed, "w:gz") as bundle:
                    for info, content in entries:
                        bundle.addfile(info, io.BytesIO(content))
                destination = self.derived.parent / (scenario + "-restore")
                destination.mkdir()
                with self.assertRaises(ValueError):
                    restore(changed, destination, SOURCE_SHA, digest(changed))
                self.assertFalse((self.derived.parent / "outside").exists())

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

    def test_literal_double_underscores_in_build_root_are_not_placeholders(self) -> None:
        derived = self.derived.parent / "fresh__derived__data"
        derived.mkdir()
        (derived / BUILD_MARKER).touch()
        manifest, _ = make_products(derived)
        self.assertEqual(qualify(derived, SOURCE_SHA)[0], manifest)

    def test_unresolved_product_placeholder_is_rejected(self) -> None:
        manifest, payload = make_products(self.derived)
        selected_target(payload)["TestBundlePath"] = "__TESTHOST__/__UNKNOWN__/HealthMdUITests.xctest"
        manifest.write_bytes(plistlib.dumps(payload))
        with self.assertRaisesRegex(ValueError, "placeholder"):
            qualify(self.derived, SOURCE_SHA)

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
    job = workflow.split("  ios-ui-shards:\n", 1)[1].split("\n  test-ios-ui:", 1)[0]
    preparation = workflow.split("  prepare-ui-artifacts:\n", 1)[1].split("\n  ios-ui-shards:", 1)[0]
    pieces = re.split(r"^      - name: ", preparation, flags=re.MULTILINE)[1:]
    pieces += re.split(r"^      - name: ", job, flags=re.MULTILINE)[1:]
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
        shutil.copy(SCRIPTS / "ios_ui_shards.py", scripts)
        shutil.copy(SCRIPTS / "start-ci-ios-simulator.sh", scripts)
        shutil.copy(SCRIPTS / "apple_nightly_ui.py", scripts)
        shutil.copy(SCRIPTS / "run-owned-ui.py", scripts)
        shutil.copy(SCRIPTS / "prepared_ios_ui_artifacts.py", scripts)
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
            "    Path(args[args.index('-resultBundlePath')+1]).mkdir(parents=True)\n"
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
            "state=Path('mock-simulator-state')\n"
            "if args[:2]==['simctl','boot']: state.write_text('Booted')\n"
            "if args[:3]==['simctl','list','devices']:\n"
            "    print(json.dumps({'devices':{'runtime':[{'udid':u,'state':state.read_text() if state.exists() else 'Shutdown','isAvailable':True,'deviceTypeIdentifier':'com.apple.CoreSimulator.SimDeviceType.'+(('iPad' if family=='iPhone' else 'iPhone') if os.environ.get('MD_MOCK_WRONG_FAMILY') else family)+'-Synthetic'} for u,family in [('11111111-1111-1111-1111-111111111111','iPhone'),('22222222-2222-2222-2222-222222222222','iPad')]]}}))\n"
            "if args[:2]==['simctl','install'] and not Path(args[3]).is_dir(): sys.exit(74)\n"
            "if args[:3]==['xcresulttool','get','test-results']:\n"
            "    calls=[json.loads(x) for x in Path(os.environ['MD_MOCK_CALLS']).read_text().splitlines()]\n"
            "    selected=[a.split('HealthMdUITests/',1)[1] for a in calls[-1] if a.startswith('-only-testing:')]\n"
            "    if args[3]=='summary':\n"
            "        print(json.dumps(dict(result='Passed',totalTestCount=len(selected),passedTests=len(selected),failedTests=0,skippedTests=0)))\n"
            "    else:\n"
            "        print(json.dumps(dict(testNodes=[dict(nodeType='Test Case',nodeIdentifier=n+'()',result='Passed') for n in selected])))\n"
        ))
        self.executable(scripts / "select-ios-simulator.sh", (
            "#!/bin/sh\ncase \"$*\" in\n"
            "  *iPad*) printf '%s\\n' 'platform=iOS Simulator,id=SYNTHETIC-IPAD';;\n"
            "  *) printf '%s\\n' 'platform=iOS Simulator,id=11111111-1111-1111-1111-111111111111';;\nesac\n"
        ))
        self.environment = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", GITHUB_OUTPUT=str(self.output), MD_MOCK_CALLS=str(self.calls), MD_MOCK_DEVICE_CALLS=str(self.device_calls))
        self.job, self.steps = ui_steps()

    @staticmethod
    def executable(path: Path, content: str) -> None:
        path.write_text(content)
        path.chmod(0o755)

    def run_step(self, name: str, artifact: str = "", shard: int = 0) -> subprocess.CompletedProcess:
        script = shell_body(self.steps[name])
        script = script.replace("${{ steps.ui_artifacts.outputs.xctestrun }}", artifact)
        script = script.replace("${{ steps.ui_artifacts.outputs.app }}", self.app if artifact else "")
        script = script.replace("${{ steps.simulator.outputs.ios_destination }}", "platform=iOS Simulator,id=" + ("22222222-2222-2222-2222-222222222222" if shard == 3 else "11111111-1111-1111-1111-111111111111"))
        script = script.replace("${{ steps.ui_artifacts.outputs.derived_data }}", getattr(self, "derived", ""))
        script = script.replace("${{ needs.prepare-ui-artifacts.outputs.sha256 }}", getattr(self, "archive_sha", ""))
        script = script.replace("${{ matrix.shard }}", str(shard))
        script = script.replace("${{ github.run_id }}", "12").replace("${{ github.run_attempt }}", "1")
        return subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], cwd=self.root, env=self.environment, text=True, capture_output=True)

    def build(self) -> str:
        result = self.run_step("Build UI test artifacts once")
        self.assertEqual(result.returncode, 0, result.stderr)
        outputs = dict(line.split("=", 1) for line in self.output.read_text().splitlines())
        self.assertEqual(set(outputs), {"xctestrun", "app", "derived_data"})
        receipt = json.loads((self.root / "build/logs/ios-ui-build-receipt.json").read_text())
        self.app = outputs["app"]
        self.assertEqual(self.app, receipt["products"][0]["path"])
        self.derived = outputs["derived_data"]
        self.output.write_text("")
        packed = self.run_step("Package qualified UI products and compile log")
        self.assertEqual(packed.returncode, 0, packed.stderr)
        self.archive_sha = dict(line.split("=", 1) for line in self.output.read_text().splitlines())["sha256"]
        self.output.write_text("")
        restored = self.run_step("Verify restored UI products")
        self.assertEqual(restored.returncode, 0, restored.stderr)
        consumer = dict(line.split("=", 1) for line in self.output.read_text().splitlines())
        self.assertEqual(set(consumer), {"xctestrun", "app"})
        self.app = consumer["app"]
        return consumer["xctestrun"]

    def test_compile_once_archive_feeds_every_device_attributed_lane(self) -> None:
        from ios_ui_shards import SHARDS, DEVICE_FAMILIES
        self.assertNotIn("Build UI test artifacts once", self.job)
        self.assertIn("prepare-ui-artifacts", self.job.split("    steps:", 1)[0])
        artifact = self.build()
        for index in range(len(SHARDS)):
            result_path = self.root / "build/test-results/HealthMd-UI-Shard.xcresult"
            if result_path.exists(): shutil.rmtree(result_path)
            # Actual matrix jobs have independent filesystems, including ownership records.
            for record in (self.root / "build/logs").glob("ui-owner-*"): record.unlink()
            result = self.run_step("Run UI smoke tests (iOS)", artifact, index)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            receipt = json.loads((self.root / "build/logs/ui-case-receipt.json").read_text())
            self.assertEqual(receipt["cases"], sorted(SHARDS[index]))
            self.assertEqual(receipt["shard"], index)
            self.assertEqual(receipt["device_family"], DEVICE_FAMILIES[index])
            owner = json.loads((self.root / "build/logs/ui-owner-shard.json").read_text())
            self.assertTrue(owner["eligible_to_continue"])
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([args[0] for args in calls], ["build-for-testing"] + ["test-without-building"] * 4)
        build = calls[0]
        self.assertEqual(build[build.index("-destination") + 1], "generic/platform=iOS Simulator")
        self.assertEqual(build[build.index("-configuration") + 1], "Debug-iOS")
        self.assertEqual(build[build.index("-scheme") + 1], "HealthMd-UITests-iOS")
        self.assertIn("ONLY_ACTIVE_ARCH=YES", build)
        self.assertIn("COMPILER_INDEX_STORE_ENABLE=NO", build)
        self.assertIn("ARCHS=" + os.uname().machine, build)
        for args, expected in zip(calls[1:], SHARDS):
            self.assertEqual(args[args.index("-xctestrun") + 1], artifact)
            self.assertFalse(set(args) & {"-project", "-workspace", "-scheme", "-configuration"})
            for flag, value in [("-test-timeouts-enabled", "YES"), ("-default-test-execution-time-allowance", "180"),
                                ("-maximum-test-execution-time-allowance", "300")]:
                self.assertEqual(args[args.index(flag) + 1], value)
            self.assertEqual([a.split("HealthMdUITests/", 1)[1] for a in args if a.startswith("-only-testing:")], list(expected))
        installs = [a for line in self.device_calls.read_text().splitlines()
                    if (a := json.loads(line))[:2] == ["simctl", "install"]]
        self.assertEqual([a[2] for a in installs], ["11111111-1111-1111-1111-111111111111"] * 3 + ["22222222-2222-2222-2222-222222222222"])
        self.assertTrue(all(a[3] == self.app for a in installs))
        self.assertTrue((self.root / "build/logs/build-ios-ui-compile.log").is_file())

    def test_wrong_family_or_archive_receipt_cannot_admit_native_execution(self) -> None:
        artifact = self.build()
        before = self.calls.read_bytes()
        self.environment["MD_MOCK_WRONG_FAMILY"] = "1"
        result = self.run_step("Run UI smoke tests (iOS)", artifact)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("device family", result.stderr)
        self.assertEqual(self.calls.read_bytes(), before)
        self.environment.pop("MD_MOCK_WRONG_FAMILY")
        path = self.root / "build/logs/ios-ui-build-receipt.json"
        original = json.loads(path.read_text())
        for mutation in (dict(original, prepared_archive_sha256="f" * 64),
                         {k: v for k, v in original.items() if k != "prepared_archive_sha256"},
                         dict(original, source_sha="b" * 40), dict(original, products=[])):
            path.write_text(json.dumps(mutation))
            result = self.run_step("Run UI smoke tests (iOS)", artifact)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.calls.read_bytes(), before)
        path.write_text(json.dumps(original))
        self.assertFalse((self.root / "build/logs/ui-case-receipt.json").exists())

    def test_every_phone_and_tablet_case_has_an_implemented_test_method(self) -> None:
        from ios_ui_shards import SHARDS
        self.assertEqual(sum(map(len, SHARDS)), 22)
        for lane in SHARDS:
            for selection in lane:
                suite, method = selection.split("/")
                source = (REPO / "apps/apple/HealthMdUITests" / (suite + ".swift")).read_text()
                self.assertRegex(source, r"\bfunc\s+" + re.escape(method) + r"\s*\(", selection)

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
        for record in (self.root / "build/logs").glob("ui-owner-*"): record.unlink()
        before = self.calls.read_bytes()
        self.assertEqual(self.run_step("Run UI smoke tests (iOS)", artifact).returncode, 125)
        self.assertEqual(self.calls.read_bytes(), before, "Failed setup must not admit native execution")
        owner = json.loads((self.root / "build/logs/ui-owner-shard.json").read_text())
        self.assertFalse(owner["eligible_to_continue"])
        self.assertFalse((self.root / "build/logs/ui-case-receipt.json").exists())

    def test_existing_gate_budgets_and_compile_warning_retention_are_preserved(self) -> None:
        self.assertIn("timeout-minutes: 60", self.job)
        self.assertIn("timeout-minutes: ${{ matrix.shard == 3 && 15 || 35 }}", self.steps["Run UI smoke tests (iOS)"])
        for name in ("Check warnings (iOS UI)", "Upload iOS UI artifacts"):
            self.assertIn("!cancelled()", self.steps[name])
            self.assertIn("build/logs/build-ios-ui-compile.log", self.steps[name])
            self.assertIn("build/logs/build-ios-ui.log", self.steps[name])
        self.assertNotIn("continue-on-error", self.job)
        self.assertNotIn("-retry-tests-on-failure", self.job)
        workflow = (REPO / ".github/workflows/apple-ci.yml").read_text()
        self.assertIn("test_ios_ui_build_contract.py", workflow)
        self.assertIn("test_ios_ui_shards.py", workflow)
        self.assertEqual(workflow.count("xcodebuild build-for-testing"), 1)
        self.assertIn("--device-family iPad --create-missing", self.steps["Select newest compatible iOS Simulator"])
        self.assertIn("PREPARE_RESULT: ${{ needs.prepare-ui-artifacts.result }}", workflow)


if __name__ == "__main__":
    unittest.main()
