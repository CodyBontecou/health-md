#!/usr/bin/env python3
"""Reuse or recover exact-SHA CI qualification for a CLI release tag."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, NamedTuple

WORKFLOWS = (
    ("CLI CI", "cli-ci.yml"),
    ("Core Rust CI", "core-rust-ci.yml"),
    ("Apple CI", "apple-ci.yml"),
    ("Android CI", "android-ci.yml"),
)
ACTIVE_STATUSES = {"requested", "waiting", "pending", "queued", "in_progress"}
HARD_FAILURES = {"failure", "timed_out", "action_required", "startup_failure", "stale"}
RECOVERABLE_CONCLUSIONS = {"cancelled", "skipped", "neutral"}


class RunState(NamedTuple):
    kind: str
    run: dict[str, Any] | None


class GitHubAPI:
    def __init__(self, repo: str, token: str, api_url: str) -> None:
        self.repo = repo
        self.token = token
        self.api_url = api_url.rstrip("/")

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> Any:
        body = None
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.token}",
            "User-Agent": "healthmd-cli-exact-ci-qualifier/1",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if payload is not None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.api_url}/repos/{self.repo}/{path.lstrip('/')}",
            data=body,
            headers=headers,
            method=method,
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
        return json.loads(raw) if raw else None

    def runs(self, workflow: str) -> list[dict[str, Any]]:
        encoded = urllib.parse.quote(workflow, safe="")
        result = self.request(
            "GET", f"actions/workflows/{encoded}/runs?per_page=50&exclude_pull_requests=true"
        )
        runs = result.get("workflow_runs") if isinstance(result, dict) else None
        if not isinstance(runs, list):
            raise RuntimeError(f"GitHub returned an invalid run list for {workflow}")
        return runs

    def dispatch(self, workflow: str, ref: str) -> None:
        encoded = urllib.parse.quote(workflow, safe="")
        self.request("POST", f"actions/workflows/{encoded}/dispatches", {"ref": ref})


def classify_event_runs(runs: list[dict[str, Any]]) -> RunState:
    for run in runs:
        if run.get("status") == "completed" and run.get("conclusion") in HARD_FAILURES:
            return RunState("failure", run)
    for run in runs:
        if run.get("status") == "completed" and run.get("conclusion") == "success":
            return RunState("success", run)
    for run in runs:
        if run.get("status") in ACTIVE_STATUSES:
            return RunState("active", run)
    for run in runs:
        if run.get("status") == "completed" and run.get("conclusion") in RECOVERABLE_CONCLUSIONS:
            return RunState("recoverable", run)
    return RunState("missing", None)


def classify_runs(runs: list[dict[str, Any]], sha: str) -> RunState:
    exact = [
        run
        for run in runs
        if run.get("head_sha") == sha
        and run.get("event") in {"push", "workflow_dispatch"}
    ]
    exact.sort(
        key=lambda run: (str(run.get("created_at") or ""), int(run.get("run_attempt") or 0)),
        reverse=True,
    )

    # A hard failure in the canonical main-push run is release evidence and may not be
    # hidden by starting a separate workflow_dispatch run. Dispatch is recovery only for
    # a path-filtered/missing or concurrency-cancelled push run.
    push_state = classify_event_runs([run for run in exact if run.get("event") == "push"])
    if push_state.kind in {"failure", "success", "active"}:
        return push_state
    dispatch_state = classify_event_runs(
        [run for run in exact if run.get("event") == "workflow_dispatch"]
    )
    if dispatch_state.kind != "missing":
        return dispatch_state
    return push_state


def run_label(run: dict[str, Any] | None) -> str:
    if not run:
        return "not found"
    return f"run {run.get('id')} ({run.get('status')}/{run.get('conclusion') or '-'})"


def qualify(
    api: GitHubAPI,
    sha: str,
    ref: str,
    discovery_timeout: float,
    completion_timeout: float,
    poll_seconds: float,
) -> None:
    started = time.monotonic()
    discovery_deadline = started + discovery_timeout
    completion_deadline = started + completion_timeout
    dispatched: set[str] = set()
    completed: set[str] = set()
    last_messages: dict[str, str] = {}

    while len(completed) != len(WORKFLOWS):
        now = time.monotonic()
        if now >= completion_deadline:
            pending = ", ".join(name for name, _ in WORKFLOWS if name not in completed)
            raise RuntimeError(f"exact-SHA CI qualification timed out: {pending}")

        transient_error = False
        for name, workflow in WORKFLOWS:
            if name in completed:
                continue
            try:
                state = classify_runs(api.runs(workflow), sha)
            except (OSError, RuntimeError, urllib.error.HTTPError) as error:
                message = f"{name}: transient GitHub API error: {error}"
                if last_messages.get(name) != message:
                    print(f"::warning::{message}")
                    last_messages[name] = message
                transient_error = True
                continue

            message = f"{name}: {state.kind}; {run_label(state.run)}"
            if last_messages.get(name) != message:
                print(message, flush=True)
                last_messages[name] = message

            if state.kind == "success":
                completed.add(name)
                continue
            if state.kind == "failure":
                url = state.run.get("html_url") if state.run else None
                raise RuntimeError(f"{name} failed for release SHA {sha}: {url or run_label(state.run)}")

            should_dispatch = state.kind == "recoverable" or (
                state.kind == "missing" and now >= discovery_deadline
            )
            if should_dispatch and workflow not in dispatched:
                print(
                    f"::notice::{name} has no reusable exact-SHA push result; "
                    f"dispatching {workflow} at {ref}",
                    flush=True,
                )
                try:
                    api.dispatch(workflow, ref)
                except (OSError, RuntimeError, urllib.error.HTTPError) as error:
                    print(f"::warning::{name}: dispatch failed transiently: {error}")
                    transient_error = True
                    continue
                dispatched.add(workflow)

        if len(completed) != len(WORKFLOWS):
            time.sleep(max(1.0, poll_seconds if not transient_error else min(30.0, poll_seconds * 2)))

    print(f"All exact-SHA CI workflows qualified {sha}.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Reuse successful main-push CI for an exact CLI release SHA. Missing or cancelled "
            "runs are recovered by workflow_dispatch at the immutable release tag."
        )
    )
    parser.add_argument("--repo", required=True, help="GitHub owner/repository")
    parser.add_argument("--sha", required=True, help="40-character release commit")
    parser.add_argument("--ref", required=True, help="immutable healthmd-cli/v* tag")
    parser.add_argument("--discovery-timeout", type=float, default=90.0)
    parser.add_argument("--completion-timeout", type=float, default=5400.0)
    parser.add_argument("--poll-seconds", type=float, default=15.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if len(args.sha) != 40 or any(character not in "0123456789abcdef" for character in args.sha):
        raise SystemExit("--sha must be a 40-character lowercase hexadecimal commit")
    if not args.ref.startswith("healthmd-cli/v"):
        raise SystemExit("--ref must be an immutable healthmd-cli/v* tag")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise SystemExit("GH_TOKEN or GITHUB_TOKEN is required")
    api = GitHubAPI(
        repo=args.repo,
        token=token,
        api_url=os.environ.get("GITHUB_API_URL", "https://api.github.com"),
    )
    try:
        qualify(
            api,
            args.sha,
            args.ref,
            args.discovery_timeout,
            args.completion_timeout,
            args.poll_seconds,
        )
    except RuntimeError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
