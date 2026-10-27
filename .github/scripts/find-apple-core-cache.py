#!/usr/bin/env python3
"""Find short-lived compiled inputs, never a prior qualification result."""
import json
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request


WORKFLOW = ".github/workflows/apple-ci.yml"


def find_cache(get, repository, current_id, fingerprint, source_digest):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
        raise ValueError("invalid repository")
    if not all(re.fullmatch(r"[a-f0-9]{64}", value) for value in (fingerprint, source_digest)):
        raise ValueError("invalid compiled-input identity")
    prefix = f"/repos/{repository}"
    current = get(f"{prefix}/actions/runs/{current_id}")
    if current.get("id") != current_id or current.get("path") != WORKFLOW:
        return None
    repository_id = current["repository"]["id"]
    # PR/fork jobs may read main's compiled inputs, but never publish or select
    # another PR's inputs. A normal same-repository branch may reuse itself.
    trusted_branch = "main"
    if (current.get("event") in ("push", "workflow_dispatch")
            and (current.get("head_repository") or {}).get("id") == repository_id):
        trusted_branch = current["head_branch"]
    workflow_id = current["workflow_id"]
    query = urllib.parse.urlencode({"branch": trusted_branch, "per_page": 10})
    runs = get(f"{prefix}/actions/workflows/{workflow_id}/runs?{query}")
    name = f"apple-core-inputs-v1-{fingerprint}-{source_digest}"
    # Bound network/setup work even when many earlier runs lack usable inputs.
    for run in runs["workflow_runs"][:5]:
        if not (isinstance(run.get("id"), int) and 0 < run["id"] < current_id
                and re.fullmatch(r"[a-f0-9]{40}", run.get("head_sha", ""))
                and run.get("workflow_id") == workflow_id and run.get("path") == WORKFLOW
                and run.get("head_branch") == trusted_branch
                and run.get("event") in ("push", "workflow_dispatch")
                and (run.get("head_repository") or {}).get("id") == repository_id
                and (run.get("repository") or {}).get("id") == repository_id):
            continue
        artifacts = get(f"{prefix}/actions/runs/{run['id']}/artifacts?per_page=100")
        matches = [artifact for artifact in artifacts["artifacts"] if artifact.get("name") == name]
        if len(matches) != 1:
            continue
        artifact = matches[0]
        origin = artifact.get("workflow_run") or {}
        if (artifact.get("expired") is False
                and re.fullmatch(r"sha256:[a-f0-9]{64}", artifact.get("digest", ""))
                and origin.get("id") == run["id"]
                and origin.get("repository_id") == repository_id
                and origin.get("head_repository_id") == repository_id
                and origin.get("head_branch") == trusted_branch
                and origin.get("head_sha") == run.get("head_sha")):
            return {"run-id": str(run["id"]), "name": name}
    return None


def main():
    token = os.environ["GH_TOKEN"]

    def get(path):
        request = urllib.request.Request("https://api.github.com" + path, headers={
            "Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        })
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.load(response)

    try:
        match = find_cache(get, os.environ["GITHUB_REPOSITORY"], int(os.environ["GITHUB_RUN_ID"]),
                           os.environ["CORE_TOOLCHAIN"], os.environ["CORE_SOURCE"])
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        # Missing/unavailable cache metadata requires the original cold build.
        # Never print a request or response containing authentication metadata.
        print("Compiled core artifact lookup unavailable; retaining cold preparation.")
        match = None
    if match:
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
            for key, value in match.items():
                output.write(f"{key}={value}\n")
        print(f"Found exact compiled core inputs in earlier run {match['run-id']}.")
    else:
        print("No trusted exact compiled core artifact; retaining cold preparation.")


if __name__ == "__main__":
    main()
