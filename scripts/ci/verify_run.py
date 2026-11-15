"""Final 120-second gate, including checkout, setup, queue, cache and reporting."""
import datetime as dt
import json
import os
import sys
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


def lookup_run_start(timeout=10):
    """Use GitHub's authoritative attempt clock, including the initial queue."""
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    url = f"{api}/repos/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        run = json.load(response)
    # A rerun starts a new attempt. Initial runs count from workflow creation,
    # including initial runner queue time; no attempt may reuse old receipts.
    start = run["created_at"] if run["run_attempt"] == 1 else run["run_started_at"]
    return dt.datetime.fromisoformat(start.replace("Z", "+00:00"))


def cache_publication_allowed(started, now):
    # Optional publication must leave twenty seconds for upload, the mandatory
    # final API/receipt gate and job finalization. Never reset the attempt clock.
    elapsed = (now - started).total_seconds()
    return 0 <= elapsed <= 120 - 20


def write_cache_publication_decision():
    allowed = False
    try:
        started = lookup_run_start(timeout=2)
        allowed = cache_publication_allowed(started, dt.datetime.now(dt.timezone.utc))
    except Exception:
        # Missing credentials, API errors or malformed/uncertain time disable
        # only this optional upload. The final verifier still fails closed.
        pass
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"save={'true' if allowed else 'false'}\n")
    print("Cargo cache publication allowed" if allowed else "Cargo cache publication skipped")


if __name__ == "__main__":
    if sys.argv[1:] == ["--cache-publication"]:
        write_cache_publication_decision()
        sys.exit(0)
    started = lookup_run_start()
    receipts = [json.loads(p.read_text()) for p in Path(".pi/ci-receipts").rglob("*.json")]
    elapsed = verify(receipts, os.environ.get("HEALTHMD_CI_SOURCE_SHA", os.environ["GITHUB_SHA"]), started, dt.datetime.now(dt.timezone.utc))
    print(f"All six groups passed in {elapsed:.3f}s including orchestration")
