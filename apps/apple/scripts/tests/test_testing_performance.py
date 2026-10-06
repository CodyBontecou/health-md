"""Host-side regression tests for native test orchestration; no Xcode required."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

APPLE = Path(__file__).resolve().parents[2]
SCRIPTS = (
    "generated-export-docs.sh",
    "generated-individual-entry-docs.sh",
    "generated-rollup-reference-docs.sh",
    "generated-automation-reference-docs.sh",
)
FAKE_XCODE = '''#!/usr/bin/env python3
import json, os, pathlib, sys
with open(os.environ["XCODE_CALLS"], "a") as out:
    out.write(json.dumps({"args": sys.argv[1:], "tz": os.getenv("TZ")}) + "\\n")
if os.getenv("GENERATED_EXPORT_DOCS_OUTPUT_DIR") and not os.getenv("XCODE_NO_OUTPUT"):
    output = pathlib.Path(os.environ["GENERATED_EXPORT_DOCS_OUTPUT_DIR"])
    output.mkdir(parents=True, exist_ok=True)
    (output / "manifest.json").write_text("{}\\n")
if os.getenv("MUTATE_SCHEMA"):
    pathlib.Path("HealthMdTests/Fixtures/Export/export_schema_signature_v8.json").write_text("changed\\n")
sys.exit(int(os.getenv("XCODE_EXIT", "0")))
'''


class AppleTestingPerformanceTests(unittest.TestCase):
    def dry_run(self, target, *args):
        return subprocess.run(["make", "--no-print-directory", "-n", target, "CORE_RUST_PREPARE=:", *args], cwd=APPLE, text=True, capture_output=True, check=True).stdout

    def test_no_target_shows_help_without_preparing_native_core(self):
        result = subprocess.run(["make", "--no-print-directory", "-n", "CORE_RUST_PREPARE=TEST_DEFAULT_WOULD_PREPARE_CORE"], cwd=APPLE, text=True, capture_output=True, check=True)
        self.assertNotIn("TEST_DEFAULT_WOULD_PREPARE_CORE", result.stdout)

    def test_default_suite_does_not_select_a_simulator(self):
        output = self.dry_run("test")
        self.assertNotIn("select-ios-simulator", output)
        self.assertNotIn("HealthMd-Tests-iOS", output)
        self.assertIn("HealthMd-Tests-macOS", output)

    def test_full_platform_suite_is_explicit(self):
        output = self.dry_run("test-platforms")
        self.assertIn("HealthMd-Tests-iOS", output)
        self.assertIn("HealthMd-Tests-macOS", output)

    def test_focused_native_tests_use_the_requested_filter(self):
        for target in ("test-macos", "test-ios"):
            with self.subTest(target=target):
                output = self.dry_run(target, "TEST_FILTER=HealthMdTests/ExampleTests/testExample")
                self.assertIn("-only-testing:HealthMdTests/ExampleTests/testExample", output)

    def test_coverage_and_native_tests_share_worktree_scoped_build_directory(self):
        expected = str(APPLE / "build/DerivedData/macOS")
        for target in ("test-macos", "coverage"):
            with self.subTest(target=target):
                self.assertIn(f'-derivedDataPath "{expected}"', self.dry_run(target))
                self.assertIn('-derivedDataPath "/custom/build"', self.dry_run(target, "DERIVED_DATA_PATH=/custom/build"))

    def fixture(self, directory):
        root = Path(directory) / "apple"
        (root / "scripts").mkdir(parents=True)
        for script in SCRIPTS:
            shutil.copy2(APPLE / "scripts" / script, root / "scripts" / script)
        for path in ("HealthMdTests/Fixtures/Documentation", "HealthMdTests/Fixtures/Export", "HealthMdTests/Documentation", "docs/reference/generated/core"):
            (root / path).mkdir(parents=True, exist_ok=True)
        (root / "docs/reference/generated/core/manifest.json").write_text("{}\n")
        (root / "HealthMdTests/Fixtures/Export/export_schema_signature_v8.json").write_text("original\n")
        tools = Path(directory) / "bin"
        tools.mkdir()
        executable = tools / "xcodebuild"
        executable.write_text(FAKE_XCODE)
        executable.chmod(0o755)
        log = Path(directory) / "calls.jsonl"
        env = {**os.environ, "PATH": f"{tools}:{os.environ['PATH']}", "XCODE_CALLS": str(log)}
        env.pop("DERIVED_DATA_PATH", None)
        env.pop("MACOS_DEST", None)
        return root, log, env

    def test_all_documentation_checks_share_incremental_builds_and_keep_guards(self):
        with tempfile.TemporaryDirectory() as directory:
            root, log, env = self.fixture(directory)
            for script in SCRIPTS:
                subprocess.run(["bash", str(root / "scripts" / script), "check"], env=env, check=True, capture_output=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(len(calls), len(SCRIPTS))
            for call in calls:
                args = call["args"]
                # Ordinary `test` still rebuilds changed sources; never stale test-without-building.
                self.assertEqual(args[0], "test")
                self.assertEqual(args[args.index("-derivedDataPath") + 1], str(root / "build/DerivedData/macOS"))
                self.assertIn("arch=", args[args.index("-destination") + 1])
                self.assertIn("-enableCodeCoverage", args)
                self.assertTrue(any(value.startswith("-only-testing:") for value in args))
                self.assertIn("CODE_SIGNING_ALLOWED=NO", args)
                self.assertEqual(call["tz"], "UTC")
            self.assertFalse((root / "HealthMdTests/Fixtures/Documentation/.generated-export-docs-output").exists())
            self.assertEqual((root / "HealthMdTests/Fixtures/Export/export_schema_signature_v8.json").read_text(), "original\n")

    def test_documentation_preserves_caller_owned_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root, log, env = self.fixture(directory)
            cache = Path(directory) / "caller-cache"
            cache.mkdir()
            (cache / "sentinel").write_text("keep")
            subprocess.run(["bash", str(root / "scripts/generated-export-docs.sh"), "check"], env={**env, "DERIVED_DATA_PATH": str(cache), "MACOS_DEST": "platform=macOS,arch=x86_64"}, check=True, capture_output=True)
            args = json.loads(log.read_text())["args"]
            self.assertEqual(args[args.index("-derivedDataPath") + 1], str(cache))
            self.assertEqual(args[args.index("-destination") + 1], "platform=macOS,arch=x86_64")
            self.assertEqual((cache / "sentinel").read_text(), "keep")

    def test_export_check_fails_closed_on_fixture_mutation_and_cleans_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _, env = self.fixture(directory)
            result = subprocess.run(["bash", str(root / "scripts/generated-export-docs.sh"), "check"], env={**env, "MUTATE_SCHEMA": "1"}, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("schema-signature fixture changed", result.stderr)
            self.assertFalse((root / "HealthMdTests/Fixtures/Documentation/.generated-export-docs-output").exists())

    def test_export_check_rejects_success_without_fresh_staged_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _, env = self.fixture(directory)
            result = subprocess.run(["bash", str(root / "scripts/generated-export-docs.sh"), "check"], env={**env, "XCODE_NO_OUTPUT": "1"}, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("did not produce a complete output", result.stderr)
            self.assertFalse((root / "HealthMdTests/Fixtures/Documentation/.generated-export-docs-output").exists())

    def test_export_check_propagates_xcode_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _, env = self.fixture(directory)
            result = subprocess.run(["bash", str(root / "scripts/generated-export-docs.sh"), "check"], env={**env, "XCODE_EXIT": "7"}, capture_output=True)
            self.assertEqual(result.returncode, 7)
            self.assertFalse((root / "HealthMdTests/Fixtures/Documentation/.generated-export-docs-output").exists())


if __name__ == "__main__":
    unittest.main()
