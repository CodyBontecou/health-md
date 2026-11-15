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

    def test_component_wrappers_keep_exact_release_inputs(self):
        for name in ("android", "apple", "practice"):
            workflow = yaml.safe_load((ROOT / f".github/workflows/{name}-ci.yml").read_text())
            test = workflow["jobs"]["test"]
            self.assertEqual(test["uses"], "./.github/workflows/ci.yml")
            self.assertIn("inputs.release_sha", test["with"]["release_sha"])
            self.assertTrue(test["with"]["full_qualification"])

    def test_portable_gate_retains_current_source_and_budget_verification(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())
        test = workflow["jobs"]["test"]
        self.assertEqual(test["timeout-minutes"], 2)
        commands = "\n".join(step.get("run", "") for step in test["steps"])
        self.assertIn("python3 scripts/ci/run.py", commands)
        self.assertIn("scripts/ci/verify_run.py", commands)
        self.assertIn("SOURCE_REVISION", commands)
        self.assertEqual(test["env"]["HEALTHMD_CI_RESULTS"], ".pi/ci-receipts")

    def test_cloud_host_regressions_are_portable_and_broad_diagnostics_manual(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/cloud-ci.yml").read_text())
        # PyYAML's YAML 1.1 loader resolves the unquoted Actions `on` key as True.
        self.assertEqual(set(workflow.get("on", workflow.get(True))), {"workflow_dispatch"})
        job = workflow["jobs"]["validate"]
        self.assertEqual(job["defaults"]["run"]["working-directory"], "apps/cloud")
        commands = "\n".join(step.get("run", "") for step in job["steps"])
        self.assertIn("npm run check", commands)
        self.assertIn("npm run test:smoke", commands)
        self.assertIn("bash scripts/ci/cloud.sh", (ROOT / "scripts/ci/wake.sh").read_text())
        cloud = (ROOT / "scripts/ci/cloud.sh").read_text()
        for command in ("npm run typecheck", "npm run typecheck:vm",
                        "npm exec -- vitest run --maxWorkers=1",
                        "npm run verify:production-safety", "npm audit --audit-level=moderate"):
            self.assertIn(command, cloud)

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


if __name__ == "__main__":
    unittest.main()
