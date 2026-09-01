#!/usr/bin/env python3
"""Tests for exact-SHA release CI reuse and recovery policy."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("qualify-exact-ci.py")
SPEC = importlib.util.spec_from_file_location("qualify_exact_ci", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {MODULE_PATH}")
qualify_exact_ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qualify_exact_ci)

SHA = "a" * 40


def run(
    *,
    run_id: int,
    event: str = "push",
    status: str = "completed",
    conclusion: str | None = "success",
    sha: str = SHA,
    created_at: str = "2026-09-01T00:00:00Z",
    attempt: int = 1,
) -> dict[str, object]:
    return {
        "id": run_id,
        "event": event,
        "head_sha": sha,
        "status": status,
        "conclusion": conclusion,
        "created_at": created_at,
        "run_attempt": attempt,
        "html_url": f"https://example.invalid/runs/{run_id}",
    }


class ClassifyRunsTests(unittest.TestCase):
    def test_successful_exact_push_is_reused(self) -> None:
        state = qualify_exact_ci.classify_runs([run(run_id=1)], SHA)
        self.assertEqual(state.kind, "success")
        self.assertEqual(state.run["id"], 1)

    def test_other_commits_and_pull_requests_are_not_qualification(self) -> None:
        state = qualify_exact_ci.classify_runs(
            [
                run(run_id=1, sha="b" * 40),
                run(run_id=2, event="pull_request"),
            ],
            SHA,
        )
        self.assertEqual(state.kind, "missing")

    def test_active_dispatch_recovers_an_older_cancelled_push(self) -> None:
        state = qualify_exact_ci.classify_runs(
            [
                run(run_id=1, conclusion="cancelled"),
                run(
                    run_id=2,
                    event="workflow_dispatch",
                    status="in_progress",
                    conclusion=None,
                    created_at="2026-09-01T00:01:00Z",
                ),
            ],
            SHA,
        )
        self.assertEqual(state.kind, "active")
        self.assertEqual(state.run["id"], 2)

    def test_hard_push_failure_is_not_masked_by_successful_dispatch(self) -> None:
        state = qualify_exact_ci.classify_runs(
            [
                run(run_id=3, conclusion="failure"),
                run(run_id=4, event="workflow_dispatch"),
            ],
            SHA,
        )
        self.assertEqual(state.kind, "failure")
        self.assertEqual(state.run["id"], 3)

    def test_cancelled_push_is_recoverable_at_the_immutable_tag(self) -> None:
        state = qualify_exact_ci.classify_runs(
            [run(run_id=4, conclusion="cancelled")], SHA
        )
        self.assertEqual(state.kind, "recoverable")

    def test_successful_dispatch_is_accepted_for_exact_sha(self) -> None:
        state = qualify_exact_ci.classify_runs(
            [run(run_id=5, event="workflow_dispatch")], SHA
        )
        self.assertEqual(state.kind, "success")


if __name__ == "__main__":
    unittest.main()
