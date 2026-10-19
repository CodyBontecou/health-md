#!/usr/bin/env python3
"""Select active Android CI jobs from a complete change list.

Uncertainty and non-PR events run all active jobs. F-Droid and Wear execution
remain paused while those builds are not distributed; their output keys stay
present so the final CI gate can verify that the jobs were skipped.
--files-json accepts offline paths or GitHub file records for regression tests.
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


JOBS = ("test", "fdroid", "instrumentation", "wear", "interop")
# Re-enable these jobs when distribution resumes. Applies even to release qualification.
PAUSED_JOBS = frozenset(("fdroid", "wear"))
PHONE = frozenset(("test", "fdroid", "instrumentation"))
ALL = frozenset(JOBS)
MAX_PR_FILES = 3000
STATUSES = {"added", "modified", "removed", "renamed", "copied", "changed", "unchanged"}

# These inputs have JVM source/document contract assertions, so retain that job
# even though documentation and release tooling need no device execution.
JVM_POLICY_PREFIXES = (
    "apps/android/docs/export-contract/",
    "apps/android/play-console/listing/",
    "apps/android/app/src/main/play/",
)
JVM_POLICY_FILES = {
    "apps/android/docs/android-desktop-destination.md",
    "apps/android/release-scope.json",
    "apps/android/scripts/upload-google-play-phone-release.sh",
}
SCRIPT_JOBS = {
    "run-accessibility-ui-tests.sh": {"instrumentation"},
    "test-accessibility-ui-runner.sh": {"instrumentation"},
    "run-direct-cli-ui-e2e.sh": {"instrumentation"},
    "run-wear-emulator-smoke.sh": {"test", "wear"},
    "WearBundleFixtureMutator.java": {"test", "wear"},
    "WearBundleManifestVerifier.java": {"test", "wear"},
    "test-wear-bundle-manifest-verifier.sh": {"test", "wear"},
    "validate-wear-artifact.sh": {"test", "wear"},
    "check-fdroid-reproducibility.sh": {"fdroid"},
    "validate-fdroid-metadata.sh": {"fdroid"},
    "verify-fdroid-artifact.sh": {"fdroid"},
    "verify-google-play-generated-apk-evidence.sh": {"test"},
}
# Explicit release/listing/evidence tooling exclusions. New scripts default to
# all jobs until reviewed, so introducing a build helper cannot bypass coverage.
POLICY_SCRIPTS = {
    "android-ci-plan.py", "android-release-scope.sh",
    "capture-google-play-generated-apk-evidence.sh",
    "capture-localized-play-screenshots.py", "capture-wear-battery-evidence.sh",
    "capture-wear-paired-qa-evidence.sh", "capture-wear-play-screenshot.sh",
    "capture-wear-remote-ci-evidence.sh", "check-github-wear-release-environments.sh",
    "check-wear-adb-pair-readiness.sh", "extract-wear-release-evidence-archive.py",
    "finalize-ai-localized-play-screenshots.py", "google-play-paired-policy.sh",
    "google-play-phone-policy.sh", "inspect-google-play-wear-readiness.sh",
    "prepare-play-metadata.py", "report-wear-release-blockers.sh",
    "seal-wear-release-evidence.sh", "sync-google-play-wear-screenshots.sh",
    "test-android-promotion-policy.sh", "upload-google-play-paired-release.sh",
    "validate-clinician-report-localizations.py", "validate-play-listing.sh",
    "validate-wear-play-assets.py", "validate-wear-release-attestation.py",
    "verify-android-production-promotion-evidence.sh",
    "verify-android-production-promotion-recovery-evidence.sh",
    "verify-github-source-review-evidence.py", "verify-phone-only-artifact.sh",
    "verify-wear-audit-evidence.sh", "verify-wear-battery-evidence.py",
    "verify-wear-paired-qa-evidence.py", "verify-wear-play-screenshot-evidence.py",
    "verify-wear-play-screenshot-upload-evidence.py", "verify-wear-release-evidence-bundle.sh",
}
POLICY_ANDROID_FILES = {
    ".gitignore", "AGENTS.md", "DESIGN.md", "DESIGN.dark.md", "Gemfile", "Gemfile.lock",
    "GOOGLE_PLAY_BILLING_SETUP.md", "GRADLE_PLAY_PUBLISHER_SETUP.md", "LICENSE",
    "OAUTH_SETUP.md", "PLAY_CONSOLE_BROWSER_PROMPT.md", "PLAY_STORE_COMMANDS.md",
    "PLAY_STORE_SETUP.md", "README.md", "dashboard.yaml", "health_md_analytics.yaml",
}
POLICY_ANDROID_PREFIXES = (
    "advertising/", "fastlane/", "play-console/", "play-store/",
    "play-store-screenshots/", "screenshots/", "scripts/tests/", "scripts/fixtures/",
)
UNAFFECTED_PREFIXES = (
    "apps/apple/", "apps/website/", "apps/practice/", "apps/wake/", "app-store-input/",
    ".agents/", "docs/", "scripts/",
)
UNAFFECTED_FILES = {
    ".env.example", ".gitattributes", ".gitignore", "CONTRIBUTING.md", "LICENSE",
    "LICENSES.md", "README.md", "deny.toml",
}


class IncompleteChanges(ValueError):
    """The change source does not prove a complete, well-formed change list."""


def valid_path(value: Any) -> str:
    if (not isinstance(value, str) or not value or value.startswith("/")
            or "\\" in value or any(ord(character) < 32 for character in value)
            or any(part in {"", ".", ".."} for part in value.split("/"))):
        raise IncompleteChanges("invalid repository path")
    if str(PurePosixPath(value)) != value:
        raise IncompleteChanges("non-canonical repository path")
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
            raise IncompleteChanges("rename/copy has no previous filename")
        if previous is not None:
            paths.add(valid_path(previous))
    return paths


def jobs_for_path(path: str) -> tuple[bool, frozenset[str]]:
    """Return policy relevance and job set; unclassified component files run all."""
    if path.startswith(("packages/contracts/", "packages/healthmd-core-rust/", ".github/actions/")):
        return True, ALL
    if path in {"AGENTS.md", "Makefile", ".github/workflows/README.md"}:
        return True, ALL
    if path.startswith(".github/workflows/android-"):
        return True, ALL
    if path.startswith("docs/migration/"):
        return True, frozenset()
    if path.startswith("apps/cli/"):
        relative = path.removeprefix("apps/cli/")
        if (relative.startswith(("docs/", "scripts/", ".github/"))
                or PurePosixPath(relative).suffix == ".md"
                or PurePosixPath(relative).name in {"LICENSE", ".gitignore", "rustfmt.toml", "release-identities.json", "dist-workspace.toml"}):
            return False, frozenset()
        return True, frozenset(("instrumentation", "interop"))
    if path.startswith("apps/android/"):
        relative = path.removeprefix("apps/android/")
        # All Gradle and toolchain configuration can affect module dependency
        # resolution, generated sources, or flavor behavior across the graph.
        if (relative.startswith("gradle/") or relative in {"gradlew", "gradlew.bat", "gradle.properties"}
                or PurePosixPath(relative).name.endswith((".gradle", ".gradle.kts"))):
            return True, ALL
        if path.startswith(JVM_POLICY_PREFIXES) or path in JVM_POLICY_FILES:
            return True, frozenset(("test",))
        if relative.startswith("wearable-contract/"):
            return True, PHONE | {"wear"}
        if relative.startswith("wear/"):
            return True, frozenset(("test", "wear"))
        if relative.startswith("direct-protocol/"):
            return True, frozenset(("test", "instrumentation", "interop"))
        if relative.startswith(("app/", "healthmd-core/")):
            return True, PHONE
        if relative.startswith("fdroid/"):
            return True, frozenset(("fdroid",))
        if relative.startswith("scripts/"):
            name = relative.removeprefix("scripts/")
            if name in SCRIPT_JOBS:
                return True, frozenset(SCRIPT_JOBS[name])
            if name in POLICY_SCRIPTS or relative.startswith(("scripts/tests/", "scripts/fixtures/")):
                return True, frozenset()
            return True, ALL
        if relative.startswith("docs/") and PurePosixPath(relative).suffix == ".md":
            return True, frozenset()
        if relative in POLICY_ANDROID_FILES or relative.startswith(POLICY_ANDROID_PREFIXES):
            return True, frozenset()
        return True, ALL
    if path.startswith(UNAFFECTED_PREFIXES) or path in UNAFFECTED_FILES:
        return False, frozenset()
    if path.startswith(".github/workflows/"):
        return False, frozenset()
    # Newly introduced packages, root build files, or shared configuration must
    # be reviewed before the classifier may exclude their Android consumers.
    return True, ALL


def plan(paths: set[str], matrix: str = "standard") -> dict[str, bool | str]:
    selected: set[str] = set()
    relevant = False
    for path in paths:
        affected, jobs = jobs_for_path(valid_path(path))
        relevant |= affected
        selected.update(jobs)
    return {"run": relevant, **{job: job in selected and job not in PAUSED_JOBS for job in JOBS}, "accessibility_matrix": matrix}


def full_plan(matrix: str = "full") -> dict[str, bool | str]:
    return {"run": True, **{job: job not in PAUSED_JOBS for job in JOBS}, "accessibility_matrix": matrix}


def pr_files(event: dict[str, Any], repository: str, token: str) -> set[str]:
    pr = event.get("pull_request", {})
    if not isinstance(pr, dict):
        raise IncompleteChanges("invalid pull request event")
    expected = pr.get("changed_files")
    number = event.get("number", pr.get("number"))
    if (not isinstance(expected, int) or isinstance(expected, bool) or expected < 0
            or expected >= MAX_PR_FILES):
        raise IncompleteChanges("missing changed_files count or GitHub's 3000-file limit reached")
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

    def verify_current_revision() -> None:
        # The files endpoint follows the current PR rather than a supplied SHA.
        # Check before and after pagination so an older event cannot classify a
        # newer diff (including same-file-count updates and base-branch moves).
        current, _ = request("")
        if (not isinstance(current, dict) or pinned_sha(current, "head") != head
                or pinned_sha(current, "base") != base or current.get("changed_files") != expected):
            raise IncompleteChanges("pull request revision changed since the event or during pagination")

    verify_current_revision()
    records: list[Any] = []
    for page in range(1, MAX_PR_FILES // 100 + 1):
        batch, headers = request(f"/files?per_page=100&page={page}")
        link = headers.get("Link", "")
        if not isinstance(batch, list) or len(batch) > 100:
            raise IncompleteChanges("invalid pull request files API response")
        records.extend(batch)
        if len(records) >= MAX_PR_FILES:
            raise IncompleteChanges("GitHub's pull request files limit reached")
        if 'rel="next"' not in link:
            if len(records) != expected:
                raise IncompleteChanges("pull request file count does not match the complete API result")
            # A duplicate record can otherwise conceal a missing file.
            if len({record.get("filename") for record in records if isinstance(record, dict)}) != expected:
                raise IncompleteChanges("duplicate or malformed pull request files")
            paths = record_paths(records)
            verify_current_revision()
            return paths
        if not batch:
            raise IncompleteChanges("empty intermediate pull request files page")
    raise IncompleteChanges("pull request pagination exceeded the API limit")


def determine_plan(args: argparse.Namespace) -> tuple[dict[str, bool | str], str]:
    # Reusable workflows inherit the caller's event name. The caller must pass
    # this explicit qualification input, rather than relying on workflow_call
    # appearing in GITHUB_EVENT_NAME. Invalid values also fail closed.
    if (args.force_full_qualification != "false" or args.release_sha
            or args.event_name != "pull_request"):
        return full_plan(), "standalone push, manual, reusable, or release qualification runs every active job and the full Play matrix"
    try:
        if args.files_json:
            records = json.loads(Path(args.files_json).read_text())
            if not isinstance(records, list) or len(records) >= MAX_PR_FILES:
                raise IncompleteChanges("offline changed-file list is invalid or reaches the API limit")
            paths = record_paths(records)
        else:
            event = json.loads(Path(args.event_path).read_text())
            if not isinstance(event, dict):
                raise IncompleteChanges("invalid event payload")
            paths = pr_files(event, args.repository, args.token)
        return plan(paths), f"classified {len(paths)} changed path(s), including rename sources"
    except (OSError, ValueError, KeyError, TypeError) as error:
        return full_plan(), f"complete change detection unavailable ({type(error).__name__}); running every active job"


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
    print(f"Android CI: {reason}.")
    print(json.dumps(result, sort_keys=True))
    if args.output:
        with Path(args.output).open("a") as output:
            for name, value in result.items():
                output.write(f"{name}={str(value).lower() if isinstance(value, bool) else value}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
