#!/usr/bin/env python3
"""Tests for CLI release approval prerequisites."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("watch-cli-release.py")
SPEC = importlib.util.spec_from_file_location("watch_cli_release", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {MODULE_PATH}")
watch_cli_release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watch_cli_release)


class ApprovalReadinessTests(unittest.TestCase):
    def test_signing_requires_exact_ci_and_five_builds(self) -> None:
        jobs = {"Qualify exact main CI": "success"}
        jobs.update(
            {f"Build local artifacts (target-{index})": "success" for index in range(5)}
        )
        self.assertTrue(watch_cli_release.approval_ready("cli-signing", jobs)[0])

        jobs["Build local artifacts (target-4)"] = "failure"
        self.assertFalse(watch_cli_release.approval_ready("cli-signing", jobs)[0])

    def test_release_requires_remote_byte_verification(self) -> None:
        self.assertTrue(
            watch_cli_release.approval_ready(
                "cli-release", {"Verify remote draft bytes": "success"}
            )[0]
        )
        self.assertFalse(
            watch_cli_release.approval_ready(
                "cli-release", {"Verify remote draft bytes": "failure"}
            )[0]
        )

    def test_unknown_environments_never_become_approvable(self) -> None:
        ready, _ = watch_cli_release.approval_ready("production", {})
        self.assertFalse(ready)


if __name__ == "__main__":
    unittest.main()
