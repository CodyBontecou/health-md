"""Final 120-second gate, including checkout, setup, queue, cache and reporting."""
import datetime as dt
import json
import os
from pathlib import Path
import urllib.request


def verify(receipts, sha, started, now):
    expected = {"contracts", "core", "cli", "practice", "wake", "consumer"}
    if len(receipts) != 6 or {r.get("lane") for r in receipts} != expected:
        raise ValueError("Exactly six distinct group receipts are required")
    elapsed = (now - started).total_seconds()
    for r in receipts:
        if r.get("status") != "passed" or r.get("exit_code") != 0 or r.get("source_sha") != sha or r.get("working_tree_dirty"):
            raise ValueError(f"Unqualified lane: {r.get('lane')}")
        begin = dt.datetime.fromisoformat(r["started_at"])
        end = dt.datetime.fromisoformat(r["finished_at"])
        if not started <= begin <= end <= now or not 0 <= r["elapsed_seconds"] <= 90:
            raise ValueError("Stale or over-budget lane receipt")
    if not 0 <= elapsed <= 120:
        raise ValueError(f"End-to-end CI took {elapsed:.3f}s; limit is 120s")
    return elapsed


if __name__ == "__main__":
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    url = f"{api}/repos/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=10) as response:
        run = json.load(response)
    # A rerun starts a new attempt. Initial runs count from workflow creation,
    # including initial runner queue time; no attempt may reuse old receipts.
    start = run["created_at"] if run["run_attempt"] == 1 else run["run_started_at"]
    started = dt.datetime.fromisoformat(start.replace("Z", "+00:00"))
    receipts = [json.loads(p.read_text()) for p in Path(".pi/ci-receipts").rglob("*.json")]
    elapsed = verify(receipts, os.environ.get("HEALTHMD_CI_SOURCE_SHA", os.environ["GITHUB_SHA"]), started, dt.datetime.now(dt.timezone.utc))
    print(f"All six groups passed in {elapsed:.3f}s including orchestration")
