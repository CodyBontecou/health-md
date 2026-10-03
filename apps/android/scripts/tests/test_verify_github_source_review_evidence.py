#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify-github-source-review-evidence.py"
SPEC = importlib.util.spec_from_file_location("source_review", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

REPOSITORY = "CodyBontecou/health-md"
SHA = "1" * 40
VERSION = "9.8.7"
REVIEWER = "independent-reviewer"
PULL_NUMBER = 321
REVIEW_ID = 987654
PULL_URL = f"https://github.com/{REPOSITORY}/pull/{PULL_NUMBER}"
REVIEW_URL = f"{PULL_URL}#pullrequestreview-{REVIEW_ID}"


class GitHubSourceReviewEvidenceTest(unittest.TestCase):
    def fixture(self) -> tuple[dict, dict, dict]:
        pull = {
            "number": PULL_NUMBER,
            "url": f"https://api.github.com/repos/{REPOSITORY}/pulls/{PULL_NUMBER}",
            "html_url": PULL_URL,
            "state": "closed",
            "merged": True,
            "merged_at": "2026-08-14T10:30:00Z",
            "user": {"login": "source-author"},
            "head": {"sha": SHA},
            "base": {"ref": "main", "repo": {"full_name": REPOSITORY}},
        }
        review = {
            "id": REVIEW_ID,
            "pull_request_url": f"https://api.github.com/repos/{REPOSITORY}/pulls/{PULL_NUMBER}",
            "html_url": REVIEW_URL,
            "state": "APPROVED",
            "commit_id": SHA,
            "submitted_at": "2026-08-14T10:00:00Z",
            "author_association": "MEMBER",
            "user": {"login": REVIEWER, "type": "User"},
        }
        proof = {
            "schemaVersion": 1,
            "repository": REPOSITORY,
            "releaseSha": SHA,
            "versionName": VERSION,
            "pullRequestNumber": PULL_NUMBER,
            "pullRequestUrl": PULL_URL,
            "reviewId": REVIEW_ID,
            "reviewer": REVIEWER,
            "reviewTicket": REVIEW_URL,
            "reviewedAtUtc": "2026-08-14T10:00:00Z",
            "mergedAtUtc": "2026-08-14T10:30:00Z",
            "verifiedAtUtc": "2026-08-14T11:00:00Z",
            "ingestRunId": 1234,
            "ingestRunAttempt": 2,
            "authenticatedByGitHubApi": True,
        }
        return pull, review, proof

    def write(self, root: Path, values: tuple[dict, dict, dict]) -> None:
        for name, value in zip(("pull-request.json", "review.json", "proof.json"), values):
            (root / name).write_text(json.dumps(value), encoding="utf-8")

    def verify(self, root: Path, reviewer: str = REVIEWER, ticket: str = REVIEW_URL) -> None:
        MODULE.verify(root, REPOSITORY, SHA, VERSION, reviewer, ticket, PULL_NUMBER, REVIEW_ID)

    def test_exact_authenticated_review_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.write(root, self.fixture())
            self.verify(root)

    def test_wrong_commit_or_dismissed_review_fails(self) -> None:
        for field, value in (("commit_id", "2" * 40), ("state", "DISMISSED")):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                values = self.fixture()
                values[1][field] = value
                self.write(root, values)
                with self.assertRaises(SystemExit):
                    self.verify(root)

    def test_wrong_reviewer_or_author_self_review_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            values = self.fixture()
            values[1]["user"]["login"] = "someone-else"
            self.write(root, values)
            with self.assertRaises(SystemExit):
                self.verify(root)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            values = self.fixture()
            values[0]["user"]["login"] = REVIEWER
            self.write(root, values)
            with self.assertRaises(SystemExit):
                self.verify(root)

    def test_unmerged_or_wrong_base_pull_request_fails(self) -> None:
        for mutate in (
            lambda pull: pull.update(merged=False),
            lambda pull: pull["base"].update(ref="release"),
        ):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                values = self.fixture()
                mutate(values[0])
                self.write(root, values)
                with self.assertRaises(SystemExit):
                    self.verify(root)

    def test_untrusted_association_or_forged_ticket_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            values = self.fixture()
            values[1]["author_association"] = "CONTRIBUTOR"
            self.write(root, values)
            with self.assertRaises(SystemExit):
                self.verify(root)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            values = self.fixture()
            values[1]["html_url"] = "https://example.invalid/ticket"
            self.write(root, values)
            with self.assertRaises(SystemExit):
                self.verify(root)

    def test_proof_identity_or_timestamp_mismatch_fails(self) -> None:
        for field, value in (
            ("reviewId", REVIEW_ID + 1),
            ("reviewedAtUtc", "2026-08-14T09:59:59Z"),
            ("authenticatedByGitHubApi", False),
        ):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                values = self.fixture()
                values[2][field] = value
                self.write(root, values)
                with self.assertRaises(SystemExit):
                    self.verify(root)

    def test_review_after_merge_or_verification_before_merge_fails(self) -> None:
        for proof_verified, review_submitted in (
            ("2026-08-14T11:00:00Z", "2026-08-14T10:31:00Z"),
            ("2026-08-14T10:29:00Z", "2026-08-14T10:00:00Z"),
        ):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                values = self.fixture()
                values[1]["submitted_at"] = review_submitted
                values[2]["reviewedAtUtc"] = review_submitted
                values[2]["verifiedAtUtc"] = proof_verified
                self.write(root, values)
                with self.assertRaises(SystemExit):
                    self.verify(root)


if __name__ == "__main__":
    unittest.main()
