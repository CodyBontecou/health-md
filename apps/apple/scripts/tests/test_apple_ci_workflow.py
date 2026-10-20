#!/usr/bin/env python3
"""Exercise the real Apple final-gate shell and PR dependency wiring without Xcode."""
from __future__ import annotations

import itertools
import os
import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
WORKFLOW = REPO / ".github/workflows/apple-ci.yml"
JOBS = {"prepare": "prepare-shared-core", "ios": "test-ios", "ios_ui": "test-ios-ui",
        "macos": "test-macos", "connectivity": "connectivity-package", "policy": "workflow-policy"}


def jobs():
    pieces = re.split(r"^  ([a-z][a-z0-9-]*):\n", WORKFLOW.read_text(), flags=re.MULTILINE)
    return dict(zip(pieces[1::2], pieces[2::2]))


def gate_script():
    return "\n".join(line[10:] for line in jobs()["gate"].split("        run: |\n", 1)[1].splitlines())


class WorkflowRoutingTests(unittest.TestCase):
    def test_each_job_uses_its_own_planner_output_and_keeps_existing_dependencies(self):
        blocks = jobs()
        for output, job in JOBS.items():
            with self.subTest(job=job):
                if output == "ios_ui":
                    self.assertIn("if: ${{ always() && needs.changes.outputs.ios_ui == 'true' }}", blocks[job])
                    self.assertIn("needs: [changes, prepare-ui-artifacts, ios-ui-shards]", blocks[job])
                    self.assertIn("test \"$SHARDS_RESULT\" = success", blocks[job])
                    self.assertIn("ios_ui_shards.py verify", blocks[job])
                else:
                    self.assertIn(f"if: ${{{{ needs.changes.outputs.{output} == 'true' }}}}", blocks[job])
                if output in {"ios", "macos"}:
                    self.assertIn("needs: [changes, prepare-shared-core]", blocks[job])
                    self.assertIn("name: apple-sdk27-shared-core", blocks[job])
                self.assertIn(f"      {output}: ${{{{ steps.detect.outputs.{output} }}}}", blocks["changes"])

    def test_planner_and_gate_regressions_and_links_run_before_selection_on_every_pr(self):
        changes = jobs()["changes"]
        self.assertIn("runs-on: ubuntu-24.04", changes)
        self.assertIn("python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_apple_ci_*.py'", changes)
        self.assertIn("python3 apps/apple/scripts/check-documentation-links.py", changes)
        self.assertLess(changes.index("test_apple_ci_*.py"), changes.index("id: detect"))
        self.assertNotIn("if:", changes)
        self.assertIn("FORCE_FULL_QUALIFICATION: ${{ inputs.full_qualification || false }}", changes)
        self.assertIn('python3 apps/apple/scripts/apple-ci-plan.py --release-sha "$RELEASE_SHA"', changes)
        call = WORKFLOW.read_text().split("  workflow_call:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.assertRegex(call, r"full_qualification:[\s\S]+type: boolean\s+default: true")

    def test_gate_waits_for_all_preserved_jobs_and_keeps_stable_status_name(self):
        gate = jobs()["gate"]
        self.assertIn("name: Apple CI", gate)
        self.assertIn("if: ${{ always() }}", gate)
        self.assertIn("      - changes", gate)
        for output, job in JOBS.items():
            with self.subTest(job=job):
                self.assertIn(f"      - {job}\n", gate)
                self.assertIn(f"{output.upper()}_SELECTED: ${{{{ needs.changes.outputs.{output} }}}}", gate)
                self.assertIn(f"{output.upper()}_RESULT: ${{{{ needs.{job}.result }}}}", gate)

    def test_known_external_test_inputs_trigger_push_qualification(self):
        push = WORKFLOW.read_text().split("  push:\n", 1)[1].split("  pull_request:", 1)[0]
        for path in ("apps/website/external-sources.json", "apps/website/assets/healthmd-plugin-visualizations.js",
                     "apps/website/assets/visualizations-data/health-sample.json",
                     "apps/website/assets/visualizations-data/health-rollups.json",
                     ".github/workflows/apple-nightly.yml", ".github/workflows/release-ios.yml",
                     "packages/contracts/**", "packages/healthmd-core-rust/**"):
            with self.subTest(path=path):
                self.assertIn(f"'{path}'", push)
        self.assertIn("      - main\n", push)
        self.assertIn("      - testing\n", push)

    def test_all_original_test_commands_and_ui_coverage_remain(self):
        workflow = WORKFLOW.read_text()
        for command in ("make test-ios CORE_RUST_PREPARE=:", "make coverage CORE_RUST_PREPARE=:",
                        "make check-export-docs-after-tests", "scripts/check-coverage.sh build/coverage/HealthMd.xcresult",
                        "swift test --package-path apps/apple/Packages/HealthMdConnectivity"):
            self.assertIn(command, workflow)
        import sys
        sys.path.insert(0, str(REPO / "apps/apple/scripts"))
        from ios_ui_shards import SHARDS
        self.assertEqual(21, sum(map(len, SHARDS)))
        workers = jobs()["ios-ui-shards"]
        self.assertIn("shard: [0, 1, 2, 3]", workers)
        self.assertIn("fail-fast: false", workers)
        self.assertIn("needs: [changes, prepare-shared-core, prepare-ui-artifacts]", workers)
        self.assertIn("name: apple-sdk27-shared-core", workers)
        self.assertIn("ios_ui_shards.py run", workers)
        self.assertNotIn("continue-on-error", workflow)

    def test_native_parallel_slices_remain_complete_and_source_validated(self):
        blocks = jobs()
        workers = blocks['prepare-core-slices']
        self.assertIn('fail-fast: false', workers)
        self.assertIn('target: [aarch64-apple-ios, aarch64-apple-ios-sim, x86_64-apple-ios, aarch64-apple-darwin, x86_64-apple-darwin]', workers)
        self.assertIn("--slice '${{ matrix.target }}'", workers)
        self.assertIn('ci_apple_core_slices.py receipt', workers)
        collector = blocks['prepare-shared-core']
        self.assertIn('needs: [changes, prepare-core-slices]', collector)
        self.assertIn('ci_apple_core_slices.py verify', collector)
        self.assertIn('generate-apple-bindings.sh --check', collector)
        self.assertIn('--assemble "$PWD/build/apple-core-slices"', collector)
        self.assertIn('validate-apple-xcframework.sh', collector)
        self.assertIn('name: apple-sdk27-shared-core', collector)

    def test_main_native_tests_keep_complete_suite_and_overlap_boot_with_compile(self):
        native = jobs()['test-ios']
        self.assertIn('IOS_TEST_BUILD_FLAGS="ARCHS=$(uname -m) ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"', native)
        self.assertNotIn('-only-testing', native)
        self.assertNotIn('-skip-testing', native)
        self.assertLess(native.index('scripts/start-ci-ios-simulator.sh'), native.index('make test-ios'))


class GateExecutionTests(unittest.TestCase):
    def run_gate(self, selected=(), **updates):
        environment = dict(os.environ, CHANGES_RESULT="success")
        for output in JOBS:
            environment[output.upper() + "_SELECTED"] = str(output in selected).lower()
            environment[output.upper() + "_RESULT"] = "success" if output in selected else "skipped"
        environment["PREPARE_UI_RESULT"] = "success" if "ios_ui" in selected else "skipped"
        environment.update(updates)
        return subprocess.run(["bash", "-e", "-c", gate_script()], env=environment, text=True, capture_output=True)

    def test_all_selection_combinations_pass_only_when_selected_jobs_succeeded(self):
        for flags in itertools.product((False, True), repeat=len(JOBS)):
            selected = {job for job, enabled in zip(JOBS, flags) if enabled}
            with self.subTest(selected=selected):
                result = self.run_gate(selected)
                self.assertEqual(0, result.returncode, result.stderr + result.stdout)

    def test_selected_jobs_skipped_failed_cancelled_or_missing_never_pass(self):
        for job in JOBS:
            for status in ("skipped", "failure", "cancelled", "", "unknown"):
                with self.subTest(job=job, status=status):
                    result = self.run_gate({job}, **{job.upper() + "_RESULT": status})
                    self.assertNotEqual(0, result.returncode)

    def test_selected_ui_preparation_must_succeed(self):
        for status in ("skipped", "failure", "cancelled", "", "unknown"):
            self.assertNotEqual(0, self.run_gate({"ios_ui"}, PREPARE_UI_RESULT=status).returncode)

    def test_empty_or_invalid_selection_never_passes_as_an_unrelated_pr(self):
        for job in JOBS:
            for selected in ("", "FALSE", "0", "unexpected"):
                with self.subTest(job=job, selected=selected):
                    result = self.run_gate(**{job.upper() + "_SELECTED": selected})
                    self.assertNotEqual(0, result.returncode)

    def test_failed_or_missing_planner_never_passes(self):
        for status in ("failure", "cancelled", "skipped", ""):
            with self.subTest(status=status):
                self.assertNotEqual(0, self.run_gate(CHANGES_RESULT=status).returncode)

    def test_unselected_jobs_cannot_hide_failures_but_extra_success_is_safe(self):
        for job in JOBS:
            for status in ("failure", "cancelled", "", "unknown"):
                with self.subTest(job=job, status=status):
                    self.assertNotEqual(0, self.run_gate(**{job.upper() + "_RESULT": status}).returncode)
            self.assertEqual(0, self.run_gate(**{job.upper() + "_RESULT": "success"}).returncode)


if __name__ == "__main__":
    unittest.main()
