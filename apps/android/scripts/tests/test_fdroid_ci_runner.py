#!/usr/bin/env python3
"""Protect fresh F-Droid validation and the aggregate required by releases."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[4]
WORKFLOW = ROOT / ".github/workflows/android-ci.yml"
OPTIONS = {
    "--no-daemon", "--max-workers=2", "--no-build-cache",
    "--no-configuration-cache", "--profile", "--stacktrace",
}
DEBUG_TASKS = [
    ":app:testFdroidDebugUnitTest", ":app:lintFdroidDebug", ":app:assembleFdroidDebug",
]

FAKE_GRADLE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
with Path(os.environ["FDROID_TEST_CALLS"]).open("a") as calls:
    calls.write(json.dumps({"program": "gradle", "args": sys.argv[1:],
                           "cwd": str(Path.cwd())}) + "\n")
print("fake Gradle stdout")
print("fake Gradle stderr", file=sys.stderr)
raise SystemExit(int(os.environ.get("FDROID_TEST_GRADLE_EXIT", "0")))
'''
FAKE_VERIFIER = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
with Path(os.environ["FDROID_TEST_CALLS"]).open("a") as calls:
    calls.write(json.dumps({"program": "verifier", "args": sys.argv[1:],
                           "cwd": str(Path.cwd())}) + "\n")
raise SystemExit(int(os.environ.get("FDROID_TEST_VERIFIER_EXIT", "0")))
'''


# GNU time is an external Linux system dependency. This boundary shim keeps its
# child-status semantics while allowing these policy tests on a macOS host.
FAKE_TIMER = r'''#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
arguments = sys.argv[1:]
if arguments[:2] != ["-v", "-o"] or len(arguments) < 4:
    raise SystemExit("Unexpected profiler arguments")
output = Path(arguments[2])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text("fixture resource profile\n")
raise SystemExit(subprocess.run(arguments[3:]).returncode)
'''


def job(name: str) -> str:
    match = re.search(rf"^  {re.escape(name)}:\n(.*?)(?=^  [\w-]+:\n|\Z)",
                      WORKFLOW.read_text(), flags=re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"Missing workflow job: {name}")
    return match.group(1)


def steps(block: str) -> list[str]:
    return re.findall(r"^      - .*?(?=^      - |\Z)", block,
                      flags=re.MULTILINE | re.DOTALL)


class FdroidRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="healthmd-fdroid-ci-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.android = self.root / "Android project with spaces"
        self.scripts = self.android / "scripts"
        self.scripts.mkdir(parents=True)
        # Execute the real workflow command, including failure propagation, in an
        # old-source fixture that intentionally has no newly added build helper.
        commands = [step for step in steps(job("fdroid-build"))
                    if "name: Build and validate clean F-Droid lane" in step]
        self.assertEqual(1, len(commands))
        self.assertIn("        run: |\n", commands[0])
        command = textwrap.dedent(commands[0].split("        run: |\n", 1)[1])
        timer = self.root / "GNU time boundary"
        timer.write_text(FAKE_TIMER)
        timer.chmod(0o755)
        command = command.replace("/usr/bin/time", shlex.quote(str(timer)))
        self.runner = self.root / "workflow command.sh"
        self.runner.write_text(command)
        self.calls = self.root / "commands.jsonl"
        for path, content in ((self.android / "gradlew", FAKE_GRADLE),
                              (self.scripts / "verify-fdroid-artifact.sh", FAKE_VERIFIER)):
            path.write_text(content)
            path.chmod(0o755)

    def run_runner(self, variant: str | None, *, gradle_exit: int = 0,
                   verifier_exit: int = 0) -> tuple[subprocess.CompletedProcess[str], list[dict]]:
        environment = {**os.environ, "FDROID_TEST_CALLS": str(self.calls),
                       "FDROID_TEST_GRADLE_EXIT": str(gradle_exit),
                       "FDROID_TEST_VERIFIER_EXIT": str(verifier_exit)}
        environment.pop("FDROID_VARIANT", None)
        if variant is not None:
            environment["FDROID_VARIANT"] = variant
        result = subprocess.run(
            ["bash", str(self.runner)], cwd=self.android, env=environment,
            capture_output=True, text=True,
        )
        records = [json.loads(line) for line in self.calls.read_text().splitlines()] \
            if self.calls.exists() else []
        return result, records

    def assert_gradle(self, call: dict, tasks: list[str]) -> None:
        self.assertEqual("gradle", call["program"])
        self.assertEqual(str(self.android.resolve()), call["cwd"])
        args = call["args"]
        self.assertEqual(tasks, [arg for arg in args if arg.startswith(":")])
        self.assertEqual(OPTIONS, {arg for arg in args if arg.startswith("--")})
        self.assertEqual(len(OPTIONS) + len(tasks), len(args),
                         "Every invocation must keep exactly its original selectors and clean-build options")

    def test_debug_runs_every_original_validation_selector_in_checkout_with_spaces(self) -> None:
        result, calls = self.run_runner("debug")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(1, len(calls), "Debug must not run the release-only verifier")
        self.assert_gradle(calls[0], DEBUG_TASKS)
        self.assertIn("fake Gradle stdout", result.stdout)
        self.assertIn("fake Gradle stderr", result.stderr)

    def test_release_builds_then_verifies_its_fresh_unsigned_artifact(self) -> None:
        result, calls = self.run_runner("release")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["gradle", "verifier"], [call["program"] for call in calls])
        self.assert_gradle(calls[0], [":app:assembleFdroidRelease"])
        self.assertEqual([], calls[1]["args"])
        self.assertEqual(str(self.android.resolve()), calls[1]["cwd"])

    def test_invalid_or_missing_variant_fails_before_any_build(self) -> None:
        for variant in (None, "", "all", "Debug", "debug release", "release; exit 0"):
            with self.subTest(variant=variant):
                result, calls = self.run_runner(variant)
                self.assertNotEqual(0, result.returncode)
                self.assertEqual([], calls)

    def test_failed_build_propagates_and_never_verifies_an_old_artifact(self) -> None:
        for variant in ("debug", "release"):
            with self.subTest(variant=variant):
                self.calls.unlink(missing_ok=True)
                result, calls = self.run_runner(variant, gradle_exit=23)
                self.assertEqual(23, result.returncode)
                self.assertEqual(["gradle"], [call["program"] for call in calls])

    def test_failed_release_verification_fails_the_lane(self) -> None:
        result, calls = self.run_runner("release", verifier_exit=19)
        self.assertEqual(19, result.returncode)
        self.assertEqual(["gradle", "verifier"], [call["program"] for call in calls])


class FdroidWorkflowTest(unittest.TestCase):
    def test_both_fresh_profiles_run_in_parallel_without_cancelling_coverage(self) -> None:
        build = job("fdroid-build")
        self.assertRegex(build, r"fail-fast:\s*false\b")
        matrix = re.search(r"^      matrix:\s*\n(.*?)(?=^    \S|\Z)", build,
                           flags=re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(matrix, "Both original build profiles require explicit matrix lanes")
        text = matrix.group(1)
        inline = re.search(r"^        variant:\s*\[([^\]]+)\]", text, flags=re.MULTILINE)
        if inline:
            variants = [item.strip().strip("'\"") for item in inline.group(1).split(",")]
        else:
            variant = re.search(r"^        variant:\s*\n(.*?)(?=^        \w|\Z)", text,
                                flags=re.MULTILINE | re.DOTALL)
            self.assertIsNotNone(variant)
            variants = re.findall(r"^          -\s*['\"]?([\w-]+)", variant.group(1),
                                  flags=re.MULTILINE)
        self.assertCountEqual(["debug", "release"], variants)
        self.assertEqual(2, len(variants))
        self.assertNotRegex(build, r"continue-on-error:\s*true")
        self.assertNotRegex(build, r"max-parallel:\s*1\b")
        self.assertIn("FDROID_VARIANT: ${{ matrix.variant }}", build)
        self.assertNotIn("run-fdroid-ci.sh", build,
                         "Reusable release qualification must work when release_sha predates this CI change")
        self.assertIn("needs.changes.outputs.fdroid == 'true'", build)

    def test_each_profile_restores_dependencies_but_no_compiled_native_outputs(self) -> None:
        build = job("fdroid-build")
        native = [step for step in steps(build) if "uses: ./.github/actions/android-native-cache" in step]
        self.assertEqual(1, len(native))
        self.assertRegex(native[0], r"cache-targets:\s*none\b")
        self.assertIn("test ! -e local.properties", build)
        self.assertIn('test -z "${HEALTHMD_ANDROID_KEYSTORE_PATH:-}"', build)
        self.assertIn("ndk;27.1.12297006", build)
        self.assertNotIn("actions/cache", build,
                         "The fresh-source lanes must not add a project output cache")

    def test_scanner_and_unsigned_release_evidence_only_run_in_release_lane(self) -> None:
        build_steps = steps(job("fdroid-build"))
        scanners = [step for step in build_steps if "scanner --json --exit-code" in step]
        self.assertEqual(1, len(scanners))
        self.assertIn("matrix.variant == 'release'", scanners[0])
        self.assertIn("validate-fdroid-metadata.sh", scanners[0])
        self.assertIn("fdroidserver==2.4.5", scanners[0])
        self.assertIn('test "$scanner_status" -eq 0', scanners[0])
        release_evidence = [step for step in build_steps
                            if "uses: actions/upload-artifact@" in step
                            and "app-fdroid-release-unsigned.apk.sha256" in step]
        self.assertEqual(1, len(release_evidence))
        self.assertIn("matrix.variant == 'release'", release_evidence[0])
        self.assertIn("always()", release_evidence[0])
        self.assertIn("if-no-files-found: error", release_evidence[0])
        for required in ("app-fdroid-release-unsigned.apk", "fdroid-release-runtime-classpath.txt",
                         "fdroid-scanner.json", "fdroid-scanner.log"):
            self.assertIn(required, release_evidence[0])

    def test_diagnostics_keep_profiles_and_real_test_xml_without_artifact_collisions(self) -> None:
        artifacts = [step for step in steps(job("fdroid-build"))
                     if "uses: actions/upload-artifact@" in step]
        diagnostics = [step for step in artifacts if "build/reports/profile" in step]
        self.assertEqual(1, len(diagnostics))
        diagnostic = diagnostics[0]
        self.assertIn("always()", diagnostic)
        self.assertIn("app/build/test-results/testFdroidDebugUnitTest", diagnostic)
        self.assertIn("app/build/reports/tests/testFdroidDebugUnitTest", diagnostic)
        self.assertIn("lint-results-fdroidDebug", diagnostic)
        name = re.search(r"^          name:\s*(.+)$", diagnostic, flags=re.MULTILINE)
        self.assertIsNotNone(name)
        self.assertIn("${{ matrix.variant }}", name.group(1))
        self.assertIn("${{ github.run_id }}", name.group(1))
        self.assertIn("${{ github.run_attempt }}", name.group(1))
        self.assertNotIn("if-no-files-found: error", diagnostic,
                         "A failed build must retain partial diagnostics without requiring debug XML in release")

    def test_stable_fdroid_name_requires_the_entire_matrix_and_final_gate(self) -> None:
        aggregate = job("fdroid")
        self.assertRegex(aggregate, r"(?m)^    name:[ \t]*F-Droid clean build[ \t]*$")
        self.assertIn("fdroid-build", aggregate.split("steps:", 1)[0])
        self.assertIn("always()", aggregate.split("steps:", 1)[0])
        self.assertIn("needs.changes.outputs.fdroid == 'true'", aggregate.split("steps:", 1)[0])
        self.assertIn("FDROID_BUILD_RESULT: ${{ needs.fdroid-build.result }}", aggregate)
        final = job("gate")
        self.assertRegex(final, r"(?m)^      - fdroid[ \t]*$")
        self.assertIn("FDROID_RESULT: ${{ needs.fdroid.result }}", final)
        self.assertIn('require_job "$FDROID_RUN" "$FDROID_RESULT"', final)

    def test_aggregate_cannot_hide_a_failed_cancelled_skipped_or_missing_lane(self) -> None:
        aggregate = job("fdroid")
        self.assertIn("FDROID_BUILD_RESULT: ${{ needs.fdroid-build.result }}", aggregate)
        self.assertIn("        run: |\n", aggregate)
        command = textwrap.dedent(aggregate.split("        run: |\n", 1)[1])
        for result in ("success", "failure", "cancelled", "skipped", "", "unknown"):
            with self.subTest(result=result):
                run = subprocess.run(
                    ["bash", "-c", command],
                    env={**os.environ, "FDROID_BUILD_RESULT": result,
                         "CHANGES_RESULT": "success", "FDROID_RUN": "true"},
                    capture_output=True, text=True,
                )
                if result == "success":
                    self.assertEqual(0, run.returncode, run.stderr)
                else:
                    self.assertNotEqual(0, run.returncode,
                                        "The release qualification name must cover both lanes")


if __name__ == "__main__":
    unittest.main()
