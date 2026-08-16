#!/usr/bin/env python3
"""Verify protected GitHub PR-review evidence for the exact Android release SHA."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Optional

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
PROOF_KEYS = {
    "schemaVersion",
    "repository",
    "releaseSha",
    "versionName",
    "pullRequestNumber",
    "pullRequestUrl",
    "reviewId",
    "reviewer",
    "reviewTicket",
    "reviewedAtUtc",
    "mergedAtUtc",
    "verifiedAtUtc",
    "ingestRunId",
    "ingestRunAttempt",
    "authenticatedByGitHubApi",
}
TRUSTED_ASSOCIATIONS = {"OWNER", "MEMBER", "COLLABORATOR"}


def fail(message: str) -> None:
    raise SystemExit(f"GitHub source review evidence: {message}")


def load_object(path: Path, label: str) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"{label} is invalid: {error}")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def positive_integer(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        fail(f"{label} must be a positive integer")
    return value


def required_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        fail(f"{label} must be a nonempty unpadded string")
    return value


def utc_instant(value: object, label: str) -> dt.datetime:
    text = required_string(value, label)
    if not text.endswith("Z"):
        fail(f"{label} must end in Z")
    try:
        parsed = dt.datetime.fromisoformat(text[:-1] + "+00:00")
    except ValueError:
        fail(f"{label} must be an ISO-8601 UTC instant")
    if parsed.utcoffset() != dt.timedelta(0):
        fail(f"{label} must be UTC")
    return parsed


def nested(value: dict, *keys: str) -> object:
    current: object = value
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            fail(f"GitHub API response lacks {'.'.join(keys)}")
        current = current[key]
    return current


def verify(
    root: Path,
    repository: str,
    release_sha: str,
    version_name: str,
    expected_reviewer: str,
    expected_ticket: str,
    expected_pull_request: Optional[int] = None,
    expected_review_id: Optional[int] = None,
) -> None:
    if not root.is_dir():
        fail(f"evidence directory missing: {root}")
    if not REPOSITORY.fullmatch(repository):
        fail("expected repository is invalid")
    if not SHA40.fullmatch(release_sha) or not SEMVER.fullmatch(version_name):
        fail("expected release SHA/version is invalid")
    expected_reviewer = required_string(expected_reviewer, "expected reviewer")
    expected_ticket = required_string(expected_ticket, "expected review ticket")

    pull = load_object(root / "pull-request.json", "pull-request.json")
    review = load_object(root / "review.json", "review.json")
    proof = load_object(root / "proof.json", "proof.json")
    if set(proof) != PROOF_KEYS:
        fail(f"proof keys differ; missing={sorted(PROOF_KEYS - set(proof))}, extra={sorted(set(proof) - PROOF_KEYS)}")

    pull_number = positive_integer(proof.get("pullRequestNumber"), "proof.pullRequestNumber")
    review_id = positive_integer(proof.get("reviewId"), "proof.reviewId")
    if expected_pull_request is not None and pull_number != expected_pull_request:
        fail("pull request number differs from protected workflow input")
    if expected_review_id is not None and review_id != expected_review_id:
        fail("review ID differs from protected workflow input")
    if proof.get("schemaVersion") != 1 or proof.get("authenticatedByGitHubApi") is not True:
        fail("proof is not a protected GitHub API authentication record")
    expected_proof = {
        "repository": repository,
        "releaseSha": release_sha,
        "versionName": version_name,
        "reviewer": expected_reviewer,
        "reviewTicket": expected_ticket,
    }
    for key, expected in expected_proof.items():
        if proof.get(key) != expected:
            fail(f"proof.{key} differs from protected expected value")
    positive_integer(proof.get("ingestRunId"), "proof.ingestRunId")
    positive_integer(proof.get("ingestRunAttempt"), "proof.ingestRunAttempt")

    pull_url = f"https://github.com/{repository}/pull/{pull_number}"
    pull_api_url = f"https://api.github.com/repos/{repository}/pulls/{pull_number}"
    if proof.get("pullRequestUrl") != pull_url:
        fail("proof pull request URL is not canonical")
    if pull.get("number") != pull_number or pull.get("html_url") != pull_url or pull.get("url") != pull_api_url:
        fail("pull request identity/URL differs from protected proof")
    if pull.get("state") != "closed" or pull.get("merged") is not True:
        fail("pull request is not merged")
    if nested(pull, "base", "ref") != "main" or nested(pull, "base", "repo", "full_name") != repository:
        fail("pull request is not merged to canonical main")
    if nested(pull, "head", "sha") != release_sha:
        fail("pull request head is not the exact release SHA")
    pull_author = required_string(nested(pull, "user", "login"), "pull request author")
    if pull_author.casefold() == expected_reviewer.casefold():
        fail("source reviewer is not independent from the pull request author")

    if review.get("id") != review_id or review.get("pull_request_url") != pull_api_url:
        fail("review identity does not belong to the exact pull request")
    if review.get("state") != "APPROVED" or review.get("commit_id") != release_sha:
        fail("review is not a current approval of the exact release SHA")
    if nested(review, "user", "login") != expected_reviewer or nested(review, "user", "type") != "User":
        fail("review author differs from protected expected GitHub user")
    if review.get("author_association") not in TRUSTED_ASSOCIATIONS:
        fail("review author is not a repository owner/member/collaborator")
    if review.get("html_url") != expected_ticket:
        fail("review ticket is not the authoritative GitHub review URL")

    reviewed_at_text = required_string(review.get("submitted_at"), "review.submitted_at")
    merged_at_text = required_string(pull.get("merged_at"), "pull.merged_at")
    reviewed_at = utc_instant(reviewed_at_text, "review.submitted_at")
    merged_at = utc_instant(merged_at_text, "pull.merged_at")
    verified_at = utc_instant(proof.get("verifiedAtUtc"), "proof.verifiedAtUtc")
    if reviewed_at > merged_at or merged_at > verified_at:
        fail("review, merge, and protected verification times are not ordered")
    if proof.get("reviewedAtUtc") != reviewed_at_text or proof.get("mergedAtUtc") != merged_at_text:
        fail("proof timestamps differ from authoritative GitHub API responses")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_root", type=Path)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--release-sha", required=True)
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--expected-reviewer", required=True)
    parser.add_argument("--expected-review-ticket", required=True)
    parser.add_argument("--expected-pull-request", type=int)
    parser.add_argument("--expected-review-id", type=int)
    args = parser.parse_args()
    verify(
        args.evidence_root,
        args.repository,
        args.release_sha,
        args.version_name,
        args.expected_reviewer,
        args.expected_review_ticket,
        args.expected_pull_request,
        args.expected_review_id,
    )
    print("GitHub source review evidence: exact SHA approval is authenticated")


if __name__ == "__main__":
    main()
