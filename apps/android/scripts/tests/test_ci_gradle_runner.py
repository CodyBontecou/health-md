#!/usr/bin/env python3
"""Check CI Gradle invocation and process behavior without starting a build."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


RUNNER = Path(__file__).resolve().parents[1] / "run-ci-gradle.sh"

FAKE_GRADLE = r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

Path(os.environ["MOCK_GRADLE_CALL"]).write_text(json.dumps({
    "arguments": sys.argv[1:],
    "directory": str(Path.cwd()),
    "stdin": sys.stdin.read(),
}))
sys.stdout.write("gradle stdout\n")
sys.stderr.write("gradle stderr\n")
raise SystemExit(int(os.environ.get("MOCK_GRADLE_EXIT", "0")))
'''


class CiGradleRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="healthmd-ci-gradle-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.android = self.root / "android with spaces"
        self.scripts = self.android / "scripts"
        self.scripts.mkdir(parents=True)
        self.runner = self.scripts / RUNNER.name
        shutil.copy2(RUNNER, self.runner)
        self.init_script = self.scripts / "ci-gradle.init.gradle"
        self.init_script.write_text("// The real Gradle fixture tests this policy.\n")
        gradle = self.android / "gradlew"
        gradle.write_text(FAKE_GRADLE)
        gradle.chmod(0o755)
        self.call_file = self.root / "call.json"

    def run_runner(self, *arguments: str, exit_code: int = 0) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(self.runner), *arguments],
            cwd=self.root,
            env={
                **os.environ,
                "MOCK_GRADLE_CALL": str(self.call_file),
                "MOCK_GRADLE_EXIT": str(exit_code),
            },
            input="build input\n",
            capture_output=True,
            text=True,
        )

    def test_arbitrary_tasks_options_and_shell_characters_reach_gradle_unchanged(self) -> None:
        marker = self.root / "must-not-exist"
        arguments = [
            "--no-daemon", "--max-workers=2",
            ":app:testPlayDebugUnitTest", ":wearable-contract:test",
            "--tests", "com.healthmd.Example test",
            f"-Pvalue=$(touch {marker});quoted='value'", "--stacktrace",
        ]
        result = self.run_runner(*arguments)
        self.assertEqual(0, result.returncode, result.stderr)
        call = json.loads(self.call_file.read_text())
        self.assertEqual(
            ["--build-cache", "--init-script", str(self.init_script), "--profile", *arguments],
            call["arguments"],
        )
        self.assertEqual(str(self.android.resolve()), call["directory"])
        self.assertFalse(marker.exists(), "Arguments must never be evaluated as shell code")

    def test_standard_streams_and_gradle_failure_reach_the_caller(self) -> None:
        result = self.run_runner(":direct-protocol:test", exit_code=23)
        self.assertEqual(23, result.returncode)
        self.assertEqual("gradle stdout\n", result.stdout)
        self.assertEqual("gradle stderr\n", result.stderr)
        self.assertEqual("build input\n", json.loads(self.call_file.read_text())["stdin"])

    def test_missing_tasks_fail_before_starting_gradle(self) -> None:
        result = self.run_runner()
        self.assertEqual(2, result.returncode)
        self.assertIn("Usage:", result.stderr)
        self.assertFalse(self.call_file.exists())


if __name__ == "__main__":
    unittest.main()
