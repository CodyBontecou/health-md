"""Exercise CI path selection and final-gate behavior without Gradle/emulators."""

from pathlib import Path
import ast
import os
import re
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = yaml.safe_load((ROOT / ".github/workflows/android-ci.yml").read_text())
JOBS = WORKFLOW["jobs"]
ACTION = yaml.safe_load((ROOT / ".github/actions/component-changes/action.yml").read_text())
ACTION_SHELL = ACTION["runs"]["steps"][0]["run"]
# Use the detector's real glob implementation, not a second interpretation.
namespace = {}
python_source = ACTION_SHELL.split("python3 - <<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
function = next(node for node in ast.parse(python_source).body if isinstance(node, ast.FunctionDef) and node.name == "pattern_to_regex")
exec(compile(ast.Module(body=[function], type_ignores=[]), "<component-detector>", "exec"), {"re": re}, namespace)
pattern_to_regex = namespace["pattern_to_regex"]


class CIOrchestrationTests(unittest.TestCase):
    def filters(self, flag):
        expression = JOBS["changes"]["outputs"][flag]
        step_id = re.search(r"steps\.([\w-]+)\.outputs\.run", expression).group(1)
        return next(step["with"]["paths"].splitlines() for step in JOBS["changes"]["steps"] if step.get("id") == step_id)

    def selected(self, flag, *paths):
        return any(pattern_to_regex(pattern.strip()).match(path) for pattern in self.filters(flag) if pattern.strip() for path in paths)

    def test_cli_only_keeps_interop_without_native_matrix(self):
        for path in ("apps/cli/crates/healthmd-mcp/src/lib.rs", "apps/cli/crates/healthmd-cli/src/main.rs", "apps/cli/README.md"):
            with self.subTest(path=path):
                self.assertFalse(self.selected("native", path))
                self.assertTrue(self.selected("run", path))

    def test_android_core_and_contract_changes_keep_all_checks(self):
        for path in ("apps/android/app/src/main/java/com/healthmd/Example.kt", "apps/android/app/src/androidTest/java/Example.kt", "apps/android/wear/src/main/Example.kt", "packages/contracts/direct-protocol/v2/protocol.md", "packages/healthmd-core-rust/crates/healthmd-core/src/lib.rs", ".github/workflows/android-ci.yml", "docs/migration/README.md", "apps/cli/crates/healthmd-client/src/direct.rs", "apps/cli/crates/healthmd-client/tests/android_live_listener.rs", "apps/cli/Cargo.lock", "apps/cli/Cargo.toml", "apps/cli/rust-toolchain.toml"):
            with self.subTest(path=path):
                self.assertTrue(self.selected("native", path))
                self.assertTrue(self.selected("run", path))

    def test_push_filter_is_union_of_job_filters(self):
        triggers = WORKFLOW.get("on", WORKFLOW.get(True))
        self.assertEqual(set(triggers["push"]["paths"]), set(self.filters("run")))
        for native_pattern in self.filters("native"):
            self.assertTrue(any(pattern_to_regex(pattern).match(native_pattern) for pattern in self.filters("run")), native_pattern)

    def test_native_jobs_use_native_flag_and_interop_uses_component_flag(self):
        for job in ("test", "instrumentation", "fdroid", "wear-emulator-smoke"):
            self.assertEqual(JOBS[job]["if"], "${{ needs.changes.outputs.native == 'true' }}")
        self.assertEqual(JOBS["rust-kotlin-direct-interop"]["if"], "${{ needs.changes.outputs.run == 'true' }}")

    def gate(self, **overrides):
        env = {**os.environ, "CHANGES_RESULT": "success", "CHANGES_RUN": "true", "NATIVE_RUN": "true", "TEST_RESULT": "success", "FDROID_RESULT": "success", "INTEROP_RESULT": "success", "WEAR_RESULT": "success", "INSTRUMENTATION_RESULT": "success", **overrides}
        return subprocess.run(["bash", "-c", JOBS["gate"]["steps"][0]["run"]], env=env, capture_output=True).returncode

    def test_gate_accepts_complete_successful_native_qualification(self):
        self.assertEqual(self.gate(), 0)

    def test_gate_accepts_selected_interop_and_explicitly_skipped_native_jobs(self):
        self.assertEqual(self.gate(NATIVE_RUN="false", TEST_RESULT="skipped", FDROID_RESULT="skipped", WEAR_RESULT="skipped", INSTRUMENTATION_RESULT="skipped"), 0)

    def test_gate_rejects_failed_or_skipped_selected_jobs(self):
        for job in ("TEST_RESULT", "FDROID_RESULT", "INTEROP_RESULT", "WEAR_RESULT", "INSTRUMENTATION_RESULT"):
            for result in ("failure", "skipped", "cancelled", ""):
                with self.subTest(job=job, result=result):
                    self.assertNotEqual(self.gate(**{job: result}), 0)

    def test_gate_rejects_detector_failure_missing_flags_and_inconsistent_scope(self):
        for changes in ({"CHANGES_RESULT": "failure"}, {"CHANGES_RUN": ""}, {"NATIVE_RUN": ""}, {"NATIVE_RUN": "unexpected"}, {"CHANGES_RUN": "false", "NATIVE_RUN": "true"}):
            with self.subTest(changes=changes):
                self.assertNotEqual(self.gate(**changes), 0)

    def test_gate_accepts_unaffected_pr_only_with_all_jobs_skipped(self):
        skipped = dict(CHANGES_RUN="false", NATIVE_RUN="false", TEST_RESULT="skipped", FDROID_RESULT="skipped", INTEROP_RESULT="skipped", WEAR_RESULT="skipped", INSTRUMENTATION_RESULT="skipped")
        self.assertEqual(self.gate(**skipped), 0)
        self.assertNotEqual(self.gate(**{**skipped, "INTEROP_RESULT": "failure"}), 0)

    def test_non_pr_events_always_select_full_qualification(self):
        preamble = ACTION_SHELL.split("python3 - <<'PY'", 1)[0]
        import tempfile
        for event in ("push", "workflow_dispatch", "workflow_call", "schedule"):
            with self.subTest(event=event), tempfile.NamedTemporaryFile() as output:
                subprocess.run(["bash", "-c", preamble], env={**os.environ, "EVENT_NAME": event, "COMPONENT": "Android", "GITHUB_OUTPUT": output.name}, check=True, capture_output=True)
                self.assertEqual(Path(output.name).read_text().strip(), "run=true")

    def test_sdk_setup_omits_removed_legacy_tools_package(self):
        for filename in ("android-ci.yml", "practice-ci.yml"):
            jobs = yaml.safe_load((ROOT / ".github/workflows" / filename).read_text())["jobs"]
            for job in jobs.values():
                for step in job.get("steps", []):
                    if step.get("uses", "").startswith("android-actions/setup-android@"):
                        self.assertEqual(step.get("with", {}).get("packages"), "platform-tools")

    def test_apple_nightly_runs_one_coverage_enabled_macos_suite(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/apple-nightly.yml").read_text())["jobs"]
        commands = [step.get("run", "") for step in jobs["extended-macos"]["steps"]]
        self.assertEqual(sum("make coverage" in command for command in commands), 1)
        self.assertFalse(any("make test-macos" in command for command in commands))
        self.assertTrue(any("tee build/logs/build-macos.log" in command and "make coverage" in command for command in commands))

    def test_apple_ci_docs_keep_coverage_build_profile(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/apple-ci.yml").read_text())["jobs"]
        self.assertEqual(jobs["test-macos"].get("env", {}).get("MACOS_CODE_COVERAGE"), "YES")

    def test_website_ci_installs_and_builds_docs_once_without_losing_checks(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/website-ci.yml").read_text())["jobs"]
        commands = [step.get("run", "") for step in jobs["validate"]["steps"]]
        self.assertEqual(sum(command.count("npm --prefix docs-src ci") for command in commands), 1)
        self.assertEqual(sum(command.count("npm run build:ci") for command in commands), 1)
        self.assertFalse(any(re.search(r"npm run (?:docs:check|docs:build|build)(?:\\s|$)", command) for command in commands))
        self.assertTrue(any("npm test" in command for command in commands))
        self.assertTrue(any("npm run reference:check" in command for command in commands))
        self.assertTrue(any("npm run visualizations:sync" in command for command in commands))


if __name__ == "__main__":
    unittest.main()
