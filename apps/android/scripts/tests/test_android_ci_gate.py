#!/usr/bin/env python3
"""Execute the final CI gate with job results to protect intentional skip behavior."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[4]
WORKFLOW = ROOT / ".github/workflows/android-ci.yml"
JOBS = ("TEST", "FDROID", "INTEROP", "WEAR", "INSTRUMENTATION")


class AndroidCIGateTest(unittest.TestCase):
    def gate(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        # The gate is the last workflow job. Run its actual shell with synthetic
        # GitHub results, so these cases catch accidental weakening of its checks.
        gate = WORKFLOW.read_text().split("\n  gate:\n", 1)[1]
        command = textwrap.dedent(gate.split("        run: |\n", 1)[1])
        environment = {
            **os.environ,
            "CHANGES_RESULT": "success",
            "CHANGES_RUN": "true",
            "POLICY_RESULT": "success",
            **{f"{job}_RUN": "true" for job in JOBS},
            **{f"{job}_RESULT": "success" for job in JOBS},
            **overrides,
        }
        return subprocess.run(
            ["bash", "-c", command], env=environment, capture_output=True, text=True,
        )

    def test_complete_qualification_requires_all_successes(self) -> None:
        self.assertEqual(0, self.gate().returncode)
        for job in (*JOBS, "POLICY"):
            for result in ("failure", "cancelled", "skipped", ""):
                with self.subTest(job=job, result=result):
                    self.assertNotEqual(0, self.gate(**{f"{job}_RESULT": result}).returncode)

    def test_unselected_jobs_must_be_skipped(self) -> None:
        for job in JOBS:
            with self.subTest(job=job):
                selected = {f"{job}_RUN": "false", f"{job}_RESULT": "skipped"}
                self.assertEqual(0, self.gate(**selected).returncode)
                for unexpected in ("success", "failure", "cancelled", ""):
                    self.assertNotEqual(
                        0, self.gate(**{**selected, f"{job}_RESULT": unexpected}).returncode,
                    )

    def test_policy_only_change_keeps_a_conclusive_gate(self) -> None:
        skips = {
            **{f"{job}_RUN": "false" for job in JOBS},
            **{f"{job}_RESULT": "skipped" for job in JOBS},
        }
        self.assertEqual(0, self.gate(**skips).returncode)
        self.assertNotEqual(0, self.gate(**skips, POLICY_RESULT="skipped").returncode)

    def test_unrelated_change_requires_every_downstream_job_to_skip(self) -> None:
        skips = {
            "CHANGES_RUN": "false", "POLICY_RESULT": "skipped",
            **{f"{job}_RUN": "false" for job in JOBS},
            **{f"{job}_RESULT": "skipped" for job in JOBS},
        }
        self.assertEqual(0, self.gate(**skips).returncode)
        self.assertNotEqual(0, self.gate(**{**skips, "TEST_RUN": "true"}).returncode)
        for job in (*JOBS, "POLICY"):
            self.assertNotEqual(
                0, self.gate(**{**skips, f"{job}_RESULT": "failure"}).returncode,
            )

    def test_missing_or_invalid_selection_and_detection_errors_fail(self) -> None:
        for result in ("failure", "cancelled", "skipped", ""):
            self.assertNotEqual(0, self.gate(CHANGES_RESULT=result).returncode)
        for invalid in ("", "maybe"):
            self.assertNotEqual(0, self.gate(CHANGES_RUN=invalid).returncode)
            for job in JOBS:
                self.assertNotEqual(0, self.gate(**{f"{job}_RUN": invalid}).returncode)


if __name__ == "__main__":
    unittest.main()
