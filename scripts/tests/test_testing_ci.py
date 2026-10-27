"""Exercise CI path selection and final-gate behavior without Gradle/emulators."""

from pathlib import Path
import ast
import importlib.util
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


SPEC = importlib.util.spec_from_file_location("android_ci_plan", ROOT / "apps/android/scripts/android-ci-plan.py")
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)


class CIOrchestrationTests(unittest.TestCase):
    def test_cli_sources_keep_device_interop_and_readme_skips_native_jobs(self):
        for path in ("apps/cli/crates/healthmd-mcp/src/lib.rs", "apps/cli/crates/healthmd-cli/src/main.rs"):
            selected = ci.plan({path})
            self.assertTrue(selected["run"])
            self.assertFalse(selected["test"])
            self.assertTrue(selected["instrumentation"])
            self.assertTrue(selected["interop"])
        self.assertFalse(ci.plan({"apps/cli/README.md"})["run"])

    def test_android_core_and_contract_changes_keep_active_consumers(self):
        cases = {
            "apps/android/app/src/main/java/com/healthmd/Example.kt": {"test", "instrumentation"},
            "apps/android/app/src/androidTest/java/Example.kt": {"test", "instrumentation"},
            "apps/android/wear/src/main/Example.kt": {"test"},
            "packages/contracts/direct-protocol/v2/protocol.md": {"test", "instrumentation", "interop"},
            "packages/healthmd-core-rust/crates/healthmd-core/src/lib.rs": {"test", "instrumentation", "interop"},
            ".github/workflows/android-ci.yml": {"test", "instrumentation", "interop"},
            "docs/migration/README.md": set(),
            "apps/cli/crates/healthmd-client/src/direct.rs": {"instrumentation", "interop"},
            "apps/cli/crates/healthmd-client/tests/android_live_listener.rs": {"instrumentation", "interop"},
            "apps/cli/Cargo.lock": {"instrumentation", "interop"},
            "apps/cli/Cargo.toml": {"instrumentation", "interop"},
            "apps/cli/rust-toolchain.toml": {"instrumentation", "interop"},
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                selected = ci.plan({path})
                self.assertTrue(selected["run"])
                self.assertEqual({job for job in ci.JOBS if selected[job]}, expected)

    def test_push_trigger_includes_every_component_consumer(self):
        triggers = WORKFLOW.get("on", WORKFLOW.get(True))
        patterns = triggers["push"]["paths"]
        for path in ("AGENTS.md", "Makefile", "apps/android/app/src/Main.kt", "apps/cli/Cargo.toml",
                     "packages/contracts/example.json", "packages/healthmd-core-rust/Cargo.toml",
                     "docs/migration/README.md", ".github/workflows/android-ci.yml"):
            self.assertTrue(any(pattern_to_regex(pattern).match(path) for pattern in patterns), path)
        detector = next(step for step in JOBS["changes"]["steps"] if step.get("id") == "detect")
        self.assertIn("apps/android/scripts/android-ci-plan.py", detector["run"])
        for flag in ("run", *ci.JOBS):
            self.assertEqual(JOBS["changes"]["outputs"][flag], "${{ steps.detect.outputs." + flag + " }}")

    def test_each_job_uses_its_own_selection_flag(self):
        for job, flag in (("test", "test"), ("jvm-tests", "test"), ("instrumentation", "instrumentation"),
                          ("fdroid", "fdroid"), ("wear-emulator-smoke", "wear"),
                          ("rust-kotlin-direct-interop", "interop")):
            prefix = "always() && " if job in {"test", "instrumentation", "fdroid"} else ""
            self.assertEqual(JOBS[job]["if"], "${{ " + prefix + "needs.changes.outputs." + flag + " == 'true' }}")

    def test_play_jvm_lanes_preserve_every_variant_and_shared_gate(self):
        lanes = JOBS["jvm-tests"]
        self.assertFalse(lanes["strategy"]["fail-fast"])
        self.assertLessEqual(lanes["timeout-minutes"], 60)
        self.assertEqual(lanes["strategy"]["matrix"]["include"], [
            {"variant": "debug", "app-task": "testPlayDebugUnitTest"},
            {"variant": "release", "app-task": "testPlayReleaseUnitTest"},
            {"variant": "e2e", "app-task": "testPlayE2eUnitTest"},
        ])
        step = next(s for s in lanes["steps"] if s.get("name") == "Run Play app, shared contract, core, and protocol tests")
        self.assertIn('--no-daemon --max-workers=2 "${tasks[@]}"', step["run"])
        self.assertIn('tasks=(":app:${{ matrix.app-task }}")', step["run"])
        self.assertEqual(step['env']['HEALTHMD_CI_APP_TEST_FORKS'], '2')
        self.assertNotIn('--tests', step['run'])
        self.assertNotIn('--exclude-task', step['run'])
        for task in (":healthmd-core:testDebugUnitTest", ":wearable-contract:test", ":direct-protocol:test"):
            self.assertIn(task, step["run"])
        for name in ("Run Android lint", "Assemble Play debug app and validate phone APK policy"):
            self.assertEqual(next(s for s in lanes["steps"] if s.get("name") == name)["if"], "${{ matrix.variant == 'debug' }}")
        self.assertEqual(set(JOBS["test"]["needs"]), {"changes", "jvm-tests"})
        self.assertIn("test", JOBS["gate"]["needs"])

    def test_play_jvm_gate_rejects_missing_failed_cancelled_or_skipped_lanes(self):
        step = JOBS["test"]["steps"][0]
        self.assertEqual(step["env"]["JVM_RESULT"], "${{ needs.jvm-tests.result }}")
        for result in ("success", "failure", "cancelled", "skipped", ""):
            with self.subTest(result=result):
                run = subprocess.run(["bash", "-c", step["run"]], env={**os.environ, "JVM_RESULT": result}, capture_output=True)
                self.assertEqual(run.returncode == 0, result == "success")

    def gate(self, **overrides):
        env = {**os.environ, "CHANGES_RESULT": "success", "CHANGES_RUN": "true", "POLICY_RESULT": "success"}
        for job in ci.JOBS:
            env[job.upper() + "_RUN"] = "true"
            env[job.upper() + "_RESULT"] = "success"
        env.update(overrides)
        return subprocess.run(["bash", "-c", JOBS["gate"]["steps"][0]["run"]], env=env, capture_output=True).returncode

    def test_gate_accepts_complete_successful_qualification(self):
        self.assertEqual(self.gate(), 0)

    def test_gate_accepts_selected_interop_and_explicitly_skipped_jobs(self):
        overrides = {}
        for job in ("TEST", "FDROID", "WEAR", "INSTRUMENTATION"):
            overrides[job + "_RUN"] = "false"
            overrides[job + "_RESULT"] = "skipped"
        self.assertEqual(self.gate(**overrides), 0)

    def test_gate_rejects_failed_or_skipped_selected_jobs(self):
        for job in ("POLICY", "TEST", "FDROID", "INTEROP", "WEAR", "INSTRUMENTATION"):
            for result in ("failure", "skipped", "cancelled", ""):
                with self.subTest(job=job, result=result):
                    self.assertNotEqual(self.gate(**{job + "_RESULT": result}), 0)

    def test_gate_rejects_detector_failure_missing_flags_and_inconsistent_scope(self):
        for changes in ({"CHANGES_RESULT": "failure"}, {"CHANGES_RUN": ""},
                        {"TEST_RUN": ""}, {"TEST_RUN": "unexpected"},
                        {"CHANGES_RUN": "false", "TEST_RUN": "true"}):
            self.assertNotEqual(self.gate(**changes), 0)

    def test_gate_accepts_unaffected_pr_only_with_all_jobs_skipped(self):
        skipped = {"CHANGES_RUN": "false", "POLICY_RESULT": "skipped"}
        for job in ci.JOBS:
            skipped[job.upper() + "_RUN"] = "false"
            skipped[job.upper() + "_RESULT"] = "skipped"
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

    def test_practice_browser_cache_is_bound_to_pinned_system_library_abi(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/practice-ci.yml").read_text())["jobs"]
        validate = jobs["validate"]
        self.assertEqual(validate["runs-on"], "ubuntu-24.04")
        cache = next(step["with"] for step in validate["steps"]
                     if step.get("uses", "").startswith("actions/cache@"))
        self.assertEqual(cache["path"], "~/.cache/ms-playwright")
        self.assertEqual(cache["key"], "practice-playwright-ubuntu24-${{ runner.arch }}-${{ hashFiles('apps/practice/package-lock.json') }}")
        self.assertEqual(cache["restore-keys"], "practice-playwright-ubuntu24-${{ runner.arch }}-")
        commands = [step.get("run", "") for step in validate["steps"]]
        self.assertIn("npx playwright install --with-deps chromium firefox webkit", commands)
        self.assertIn("npm run check:ci", commands)
        self.assertFalse(any(step.get("continue-on-error") for step in validate["steps"]))

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
        self.assertEqual(commands.count("npm run docs:check-built"), 1)
        self.assertLess(commands.index("npm run build:ci"), commands.index("npm run docs:check-built"))


if __name__ == "__main__":
    unittest.main()
