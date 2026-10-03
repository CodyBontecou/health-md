#!/usr/bin/env python3
"""Watch a CLI release and promptly perform its two reviewed approvals."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from typing import Any

ALLOWED_ENVIRONMENTS = {"cli-signing", "cli-release"}


def gh_json(arguments: list[str], payload: dict[str, Any] | None = None) -> Any:
    command = ["gh", *arguments]
    completed = subprocess.run(
        command,
        input=(json.dumps(payload, separators=(",", ":")) if payload is not None else None),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip() or "GitHub CLI failed"
        raise RuntimeError(message)
    return json.loads(completed.stdout) if completed.stdout.strip() else None


def jobs_by_name(repo: str, run_id: int, attempt: int) -> dict[str, str | None]:
    result = gh_json(
        [
            "api",
            f"repos/{repo}/actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100",
        ]
    )
    jobs = result.get("jobs") if isinstance(result, dict) else None
    if not isinstance(jobs, list):
        raise RuntimeError("GitHub returned an invalid job list")
    return {str(job.get("name")): job.get("conclusion") for job in jobs}


def approval_ready(environment: str, jobs: dict[str, str | None]) -> tuple[bool, str]:
    if environment == "cli-signing":
        if jobs.get("Qualify exact main CI") != "success":
            return False, "exact-SHA main CI has not qualified"
        builds = {
            name: conclusion
            for name, conclusion in jobs.items()
            if name.startswith("Build local artifacts (")
        }
        if len(builds) != 5 or any(result != "success" for result in builds.values()):
            return False, "all five exact candidate builds have not succeeded"
        return True, "exact-SHA CI and all five candidate builds succeeded"
    if environment == "cli-release":
        if jobs.get("Verify remote draft bytes") != "success":
            return False, "remote draft bytes have not been verified"
        return True, "the signed checksum closure and remote draft bytes were verified"
    return False, "environment is not an approved CLI release gate"


def approve(repo: str, run_id: int, environment_id: int, environment: str) -> None:
    gh_json(
        [
            "api",
            "--method",
            "POST",
            f"repos/{repo}/actions/runs/{run_id}/pending_deployments",
            "--input",
            "-",
        ],
        {
            "environment_ids": [environment_id],
            "state": "approved",
            "comment": (
                f"Reviewed with watch-cli-release.py: approve {environment} after its "
                "immutable release prerequisites passed."
            ),
        },
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Watch a healthmd-cli release, alert as soon as cli-signing or cli-release is "
            "ready, verify the prerequisite jobs, and request an explicit reviewer decision."
        )
    )
    parser.add_argument("run_id", type=int, help="CLI Release Actions run ID")
    parser.add_argument("--repo", help="GitHub owner/repository; defaults to gh repo view")
    parser.add_argument("--poll-seconds", type=float, default=10.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = args.repo
    if not repo:
        result = gh_json(["repo", "view", "--json", "nameWithOwner"])
        repo = result.get("nameWithOwner") if isinstance(result, dict) else None
    if not isinstance(repo, str) or "/" not in repo:
        raise SystemExit("could not resolve --repo owner/repository")

    approved: set[str] = set()
    last_status = ""
    print(f"Watching CLI release run {args.run_id} in {repo}.")
    while True:
        try:
            release = gh_json(["api", f"repos/{repo}/actions/runs/{args.run_id}"])
            if not isinstance(release, dict):
                raise RuntimeError("GitHub returned an invalid workflow run")
            if release.get("path") != ".github/workflows/cli-release.yml":
                raise RuntimeError("run is not .github/workflows/cli-release.yml")
            if release.get("event") != "push" or not str(release.get("head_branch", "")).startswith(
                "healthmd-cli/v"
            ):
                raise RuntimeError("run is not an immutable healthmd-cli tag push")

            status = str(release.get("status"))
            conclusion = release.get("conclusion")
            current = f"attempt {release.get('run_attempt')}: {status}/{conclusion or '-'}"
            if current != last_status:
                print(current, flush=True)
                last_status = current
            if status == "completed":
                print(str(release.get("html_url") or ""))
                return 0 if conclusion == "success" else 1

            attempt = int(release.get("run_attempt") or 1)
            jobs = jobs_by_name(repo, args.run_id, attempt)
            pending = gh_json(
                ["api", f"repos/{repo}/actions/runs/{args.run_id}/pending_deployments"]
            )
            if not isinstance(pending, list):
                raise RuntimeError("GitHub returned invalid pending deployments")
            for deployment in pending:
                environment_info = deployment.get("environment") or {}
                environment = environment_info.get("name")
                environment_id = environment_info.get("id")
                if environment in approved or environment not in ALLOWED_ENVIRONMENTS:
                    continue
                if deployment.get("current_user_can_approve") is not True:
                    print(f"{environment} is waiting for a different authorized reviewer.")
                    approved.add(str(environment))
                    continue
                ready, reason = approval_ready(str(environment), jobs)
                if not ready:
                    print(f"{environment} is pending but not approvable: {reason}")
                    continue
                print(f"\a{environment} is ready: {reason}.", flush=True)
                response = input(f"Approve {environment} for run {args.run_id}? [y/N] ").strip().lower()
                if response not in {"y", "yes"}:
                    print(f"Left {environment} pending.")
                    approved.add(str(environment))
                    continue
                approve(repo, args.run_id, int(environment_id), str(environment))
                approved.add(str(environment))
                print(f"Approved {environment}.", flush=True)
        except (OSError, RuntimeError, json.JSONDecodeError) as error:
            print(f"warning: {error}", file=sys.stderr, flush=True)
        time.sleep(max(2.0, args.poll_seconds))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nStopped watching; no pending approval was changed.")
        raise SystemExit(130)
