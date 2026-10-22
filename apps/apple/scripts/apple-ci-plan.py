#!/usr/bin/env python3
"""Select Apple PR jobs from a complete diff; uncertain inputs run every job.

Standalone pushes, manual runs, reusable qualification, and release SHAs retain
all existing checks. Changes are classified by consumers rather than file type:
macOS generates documentation, while shared XCTest assertions also read selected
docs, release metadata, and website resources on both Apple unit-test runtimes.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path, PurePosixPath
from typing import Any

JOBS = ("prepare", "ios", "ios_ui", "macos", "connectivity", "policy")
ALL = frozenset(JOBS)
UNIT = frozenset(("ios", "macos"))
MAX_PR_FILES = 3000
STATUSES = {"added", "modified", "removed", "renamed", "copied", "changed", "unchanged"}
# These shared XCTest assertions have no macOS guard. Keep both unit suites even
# when a PR changes only these documents or the inherited App Store descriptions.
SHARED_TEST_FILES = frozenset((
    "apps/apple/docs/testing/lifecycle-audit.md",
    "apps/apple/docs/testing/appearance-audit.md",
    "apps/apple/docs/testing/apns-scheduling-preflight.md",
    "apps/apple/docs/testing/CI-QUALITY-GATES.md",
    "apps/apple/docs/features/scheduled-exports.md",
    "apps/apple/docs/experiments/health-md-1499-lifetime-price-experiment.md",
    "apps/website/external-sources.json",
    "apps/website/assets/healthmd-plugin-visualizations.js",
    "apps/website/assets/visualizations-data/health-sample.json",
    "apps/website/assets/visualizations-data/health-rollups.json",
    ".github/workflows/apple-nightly.yml",
    ".github/workflows/release-ios.yml",
))
SHARED_TEST_PREFIXES = (
    "apps/apple/docs/reference/generated/individual/",
    "apps/apple/metadata/version/",
)
MACOS_GENERATED_DOCS = (
    "apps/apple/docs/reference/generated/core/",
    "apps/apple/docs/reference/generated/automation/",
    "apps/apple/docs/reference/generated/rollups/",
    "apps/apple/docs/reference/generated/cli/",
)
UNAFFECTED_PREFIXES = (
    "apps/android/", "apps/cli/", "apps/practice/", "apps/wake/", "apps/website/",
    "docs/", ".agents/", "app-store-input/",
    ".github/workflows/android-", ".github/workflows/cli-",
)
UNAFFECTED_FILES = frozenset((
    ".env.example", ".gitattributes", ".gitignore", "CONTRIBUTING.md", "LICENSE",
    "LICENSES.md", "README.md", "deny.toml", ".github/workflows/website-ci.yml",
    ".github/workflows/practice-ci.yml", ".github/workflows/wake-ci.yml",
    ".github/workflows/core-rust-ci.yml",
))


class IncompleteChanges(ValueError):
    """The change source does not prove a complete, well-formed diff."""


def valid_path(value: Any) -> str:
    if (not isinstance(value, str) or not value or value.startswith("/") or "\\" in value
            or any(ord(character) < 32 for character in value)
            or any(part in {"", ".", ".."} for part in value.split("/"))
            or str(PurePosixPath(value)) != value):
        raise IncompleteChanges("invalid repository path")
    return value


def record_paths(records: Any) -> set[str]:
    if not isinstance(records, list):
        raise IncompleteChanges("changed files must be a list")
    paths: set[str] = set()
    for record in records:
        if isinstance(record, str):
            paths.add(valid_path(record))
            continue
        if not isinstance(record, dict) or record.get("status") not in STATUSES:
            raise IncompleteChanges("invalid changed-file record")
        paths.add(valid_path(record.get("filename")))
        previous = record.get("previous_filename")
        if record["status"] in {"renamed", "copied"} and previous is None:
            raise IncompleteChanges("rename/copy has no source filename")
        if previous is not None:
            paths.add(valid_path(previous))
    return paths


def jobs_for_path(path: str) -> frozenset[str]:
    if path in SHARED_TEST_FILES or path.startswith(SHARED_TEST_PREFIXES):
        return UNIT
    if path.startswith(MACOS_GENERATED_DOCS):
        return frozenset(("macos",))
    if path.startswith("apps/apple/HealthMdCLI/"):
        # Embedded macOS tools and the CLI documentation generator are tested by
        # the macOS coverage/check-export-docs-after-tests job.
        return frozenset(("macos",))
    if path.startswith("apps/apple/HealthMdUITests/"):
        return frozenset(("ios_ui",))
    if path == "apps/apple/README.md" or (
            path.startswith("apps/apple/docs/") and PurePosixPath(path).suffix == ".md"):
        return frozenset(("macos",))
    if path.startswith(("packages/contracts/", "packages/healthmd-core-rust/", ".github/actions/")):
        return ALL
    if path.startswith("apps/apple/") or path in {"AGENTS.md", "Makefile", ".github/workflows/README.md"}:
        # Shared tests scan production source, and Xcode target membership uses
        # synchronized groups plus exceptions. A platform-directory prefix alone
        # therefore does not prove that another runtime is unaffected.
        return ALL
    if path in UNAFFECTED_FILES or path.startswith(UNAFFECTED_PREFIXES):
        return frozenset()
    # New shared packages, build helpers, root configuration, and workflows must
    # be reviewed before their Apple consumers can be excluded.
    return ALL


def plan(paths: set[str]) -> dict[str, bool]:
    selected: set[str] = set()
    for path in paths:
        selected.update(jobs_for_path(valid_path(path)))
    if selected & {"ios", "ios_ui", "macos"}:
        selected.add("prepare")
    if selected:
        selected.add("policy")
    return {"run": bool(selected), **{job: job in selected for job in JOBS}}


def full_plan() -> dict[str, bool]:
    return {"run": True, **dict.fromkeys(JOBS, True)}


def pr_files(event: dict[str, Any], repository: str, token: str) -> set[str]:
    pr = event.get("pull_request", {})
    if not isinstance(pr, dict):
        raise IncompleteChanges("invalid pull request event")
    expected = pr.get("changed_files")
    number = event.get("number", pr.get("number"))
    if (not isinstance(expected, int) or isinstance(expected, bool)
            or expected < 0 or expected >= MAX_PR_FILES):
        raise IncompleteChanges("missing changed_files count or GitHub's 3000-file cap reached")
    if (not isinstance(number, int) or isinstance(number, bool) or number <= 0
            or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or not token):
        raise IncompleteChanges("missing pull request API context")

    def pinned_sha(metadata: dict[str, Any], side: str) -> str:
        value = metadata.get(side)
        sha = value.get("sha") if isinstance(value, dict) else None
        if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha) or set(sha) == {"0"}:
            raise IncompleteChanges(f"missing pinned pull request {side} SHA")
        return sha

    head, base = pinned_sha(pr, "head"), pinned_sha(pr, "base")

    def request(suffix: str) -> tuple[Any, Any]:
        request = urllib.request.Request(
            f"https://api.github.com/repos/{repository}/pulls/{number}{suffix}",
            headers={"Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}",
                     "X-GitHub-Api-Version": "2022-11-28"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response), response.headers

    def verify_revision() -> None:
        # GitHub's files endpoint follows the current PR, not the event revision.
        # Check both sides before/after pagination so rebases or pushes cannot
        # substitute a different diff with the same number of changed files.
        current, _ = request("")
        if (not isinstance(current, dict) or pinned_sha(current, "head") != head
                or pinned_sha(current, "base") != base or current.get("changed_files") != expected):
            raise IncompleteChanges("pull request revision changed before or during pagination")

    verify_revision()
    records: list[Any] = []
    for page in range(1, MAX_PR_FILES // 100 + 1):
        batch, headers = request(f"/files?per_page=100&page={page}")
        if not isinstance(batch, list) or len(batch) > 100:
            raise IncompleteChanges("invalid pull request files API response")
        records.extend(batch)
        if len(records) >= MAX_PR_FILES:
            raise IncompleteChanges("GitHub's pull request files cap reached")
        if 'rel="next"' not in headers.get("Link", ""):
            if len(records) != expected:
                raise IncompleteChanges("incomplete pull request file count")
            if len({record.get("filename") for record in records if isinstance(record, dict)}) != expected:
                raise IncompleteChanges("duplicate or malformed pull request files")
            paths = record_paths(records)
            verify_revision()
            return paths
        if not batch:
            raise IncompleteChanges("empty intermediate pull request files page")
    raise IncompleteChanges("pull request pagination exceeded the API cap")


def determine_plan(args: argparse.Namespace) -> tuple[dict[str, bool], str]:
    # Reusable workflows inherit the caller's event name, so they also pass an
    # explicit default-true qualification input. Invalid values fail closed.
    if args.force_full_qualification != "false" or args.release_sha or args.event_name != "pull_request":
        return full_plan(), "push, manual, reusable, or release qualification runs every job"
    try:
        if args.files_json:
            records = json.loads(Path(args.files_json).read_text())
            if not isinstance(records, list) or len(records) >= MAX_PR_FILES:
                raise IncompleteChanges("offline change list is invalid or reaches the API cap")
            paths = record_paths(records)
        else:
            event = json.loads(Path(args.event_path).read_text())
            if not isinstance(event, dict):
                raise IncompleteChanges("invalid event payload")
            paths = pr_files(event, args.repository, args.token)
        return plan(paths), f"classified {len(paths)} changed path(s), including rename sources"
    except (OSError, ValueError, KeyError, TypeError) as error:
        return full_plan(), f"complete change detection unavailable ({type(error).__name__}); running every job"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", default=os.environ.get("GITHUB_EVENT_NAME", "pull_request"))
    parser.add_argument("--event-path", default=os.environ.get("GITHUB_EVENT_PATH", ""))
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--token", default=os.environ.get("GH_TOKEN", ""))
    parser.add_argument("--release-sha", default="")
    parser.add_argument("--force-full-qualification", default=os.environ.get("FORCE_FULL_QUALIFICATION", "false"))
    parser.add_argument("--files-json", help="offline JSON paths or GitHub changed-file records")
    parser.add_argument("--output", default=os.environ.get("GITHUB_OUTPUT", ""))
    args = parser.parse_args()
    result, reason = determine_plan(args)
    print(f"Apple CI: {reason}.")
    print(json.dumps(result, sort_keys=True))
    if args.output:
        with Path(args.output).open("a") as output:
            for name, value in result.items():
                output.write(f"{name}={str(value).lower()}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
