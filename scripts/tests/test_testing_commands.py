"""Exercise the root command router without invoking a compiler or device."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TestingCommandTests(unittest.TestCase):
    def dry_run(self, *args):
        return subprocess.run(["make", "--no-print-directory", "-n", *args], cwd=ROOT, text=True, capture_output=True, check=True).stdout

    def test_default_command_shows_help_instead_of_running_suites(self):
        output = self.dry_run()
        self.assertNotIn("cargo test", output)
        self.assertNotIn("xcodebuild test", output)
        self.assertNotIn("./gradlew", output)

    def test_test_requires_explicit_component(self):
        # Dry-run first: running the old unscoped target would launch every suite.
        output = self.dry_run("test")
        self.assertNotIn("xcodebuild test", output)
        self.assertIn("COMPONENT", output)

    def test_cli_selection_does_not_run_other_components(self):
        output = self.dry_run("test", "COMPONENT=cli")
        self.assertIn("cargo test --workspace --all-features --locked", output)
        for unwanted in ("xcodebuild", "./gradlew", "npm", "packages/contracts/validate.py"):
            self.assertNotIn(unwanted, output)

    def test_unknown_component_fails_without_running_a_command(self):
        for component in ("unknown", "cli core", "cli unknown", "%", ""):
            with self.subTest(component=component):
                output = self.dry_run("test", f"COMPONENT={component}")
                self.assertNotIn("xcodebuild", output)
                self.assertNotIn("cargo test", output)
                result = subprocess.run(["make", "test", f"COMPONENT={component}"], cwd=ROOT, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("COMPONENT", result.stdout + result.stderr)

    def test_broad_sweep_remains_explicitly_available(self):
        output = self.dry_run("test-all")
        for expected in ("packages/contracts/validate.py", "cargo test", "xcodebuild test", "./gradlew", "npm"):
            self.assertIn(expected, output)
        self.assertNotIn("select-ios-simulator", output)

    def test_android_feedback_selects_one_bounded_debug_variant_and_shared_modules(self):
        output = self.dry_run("test", "COMPONENT=android")
        for task in (":app:testPlayDebugUnitTest", ":healthmd-core:testDebugUnitTest", ":wearable-contract:test", ":wear:testDebugUnitTest", ":direct-protocol:test", "--max-workers=2"):
            self.assertIn(task, output)
        self.assertNotIn("./gradlew test", output)
        self.assertNotIn("connected", output)
        self.assertNotIn("testPlayRelease", output)

    def test_all_android_variants_remain_explicitly_available(self):
        self.assertIn("./gradlew test", self.dry_run("test-android-all"))

    def test_selected_cli_command_executes_once_with_lockfile_protection(self):
        # Fails safely before execution on the old router rather than starting it.
        self.assertNotIn("xcodebuild", self.dry_run("test", "COMPONENT=cli"))
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "cargo"
            log = Path(directory) / "calls"
            stub.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$COMMAND_LOG"\n')
            stub.chmod(0o755)
            env = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}", "COMMAND_LOG": str(log)}
            subprocess.run(["make", "test", "COMPONENT=cli"], cwd=ROOT, env=env, check=True, capture_output=True)
            self.assertEqual(log.read_text().splitlines(), ["test --workspace --all-features --locked"])


if __name__ == "__main__":
    unittest.main()
