"""Behavioral tests for deadlines, exit propagation, receipts and cleanup."""

import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

SPEC = importlib.util.spec_from_file_location("ci_budget", Path(__file__).with_name("budget.py"))
budget = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(budget)


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        subprocess.run(["git", "-c", "user.name=CI", "-c", "user.email=ci@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "--allow-empty", "-m", "fixture"], cwd=self.root, check=True)
        self.receipt = self.root / "receipt.json"

    def execute(self, code, seconds=5):
        result = budget.run([sys.executable, "-c", code], lane="fixture", budget_seconds=seconds, receipt=self.receipt, cwd=self.root)
        return result, json.loads(self.receipt.read_text())

    def test_success_records_current_revision_and_elapsed_time(self):
        code, receipt = self.execute("pass")
        self.assertEqual(code, 0)
        self.assertEqual(receipt["status"], "passed")
        self.assertEqual(len(receipt["source_sha"]), 40)
        self.assertFalse(receipt["working_tree_dirty"])
        self.assertLess(receipt["elapsed_seconds"], 5)

    def test_prior_success_cannot_survive_a_running_attempt(self):
        self.receipt.write_text('{"status":"passed","exit_code":0}')
        code, receipt = self.execute(
            "import json; from pathlib import Path; "
            "assert json.loads(Path(" + repr(str(self.receipt)) + ").read_text())['status'] == 'running'"
        )
        self.assertEqual(code, 0)
        self.assertEqual(receipt["status"], "passed")

    def test_failure_preserves_exit_code(self):
        code, receipt = self.execute("raise SystemExit(23)")
        self.assertEqual(code, 23)
        self.assertEqual(receipt["status"], "failed")

    def test_timeout_is_a_failure_with_a_receipt(self):
        code, receipt = self.execute("import time; time.sleep(30)", seconds=0.2)
        self.assertEqual(code, 124)
        self.assertEqual(receipt["status"], "timed_out")
        self.assertLess(receipt["elapsed_seconds"], 3)

    def test_missing_command_does_not_pass(self):
        code = budget.run([str(self.root / "missing")], lane="fixture", budget_seconds=5, receipt=self.receipt, cwd=self.root)
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(self.receipt.read_text())["status"], "failed")

    def test_timeout_stops_a_descendant_that_ignores_termination(self):
        marker = self.root / "leaked"
        descendant = "import signal,time; from pathlib import Path; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(1); Path(" + repr(str(marker)) + ").touch(); time.sleep(30)"
        parent = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c'," + repr(descendant) + "]); time.sleep(30)"
        code, _ = self.execute(parent, seconds=0.3)
        self.assertEqual(code, 124)
        time.sleep(1.1)
        self.assertFalse(marker.exists(), "Timed-out subprocess must not outlive its lane")

    def test_cancellation_stops_lane_and_writes_receipt(self):
        ready = self.root / "ready"
        command = [sys.executable, str(Path(budget.__file__)), "--lane", "fixture", "--budget-seconds", "30", "--receipt", str(self.receipt), "--", sys.executable, "-c", "from pathlib import Path; import time; Path(" + repr(str(ready)) + ").touch(); time.sleep(30)"]
        child = subprocess.Popen(command, cwd=self.root)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            child.send_signal(signal.SIGTERM)
            self.assertEqual(child.wait(timeout=5), 130)
            self.assertEqual(json.loads(self.receipt.read_text())["status"], "cancelled")
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()

    def test_denied_group_cleanup_does_not_mask_the_attempt_verdict(self):
        child = Mock(pid=123)
        with patch.object(budget.os, "killpg", side_effect=PermissionError):
            self.assertEqual(budget.stop_process_group(child), "permission_denied")
        self.assertEqual(child.send_signal.call_count, 2)
        child.wait.assert_called()

    def test_invalid_budget_is_rejected(self):
        for value in (0, -1, float("nan"), float("inf")):
            with self.assertRaises(ValueError):
                budget.run(["true"], lane="fixture", budget_seconds=value, receipt=self.receipt, cwd=self.root)


if __name__ == "__main__":
    unittest.main()
