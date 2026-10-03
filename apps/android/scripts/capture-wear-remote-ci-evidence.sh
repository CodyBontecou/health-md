#!/usr/bin/env bash
set -euo pipefail

repo=$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)
cd "$repo"
usage() {
  echo "Usage: $0 RUN_ID_OR_URL [OUTPUT_JSON]" >&2
  exit 64
}
[[ $# -ge 1 && $# -le 2 ]] || usage
run=$1
out=${2:-.pi/evidence/wear-ci/verified-run.json}
command -v gh >/dev/null || { echo 'gh CLI is required' >&2; exit 69; }
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 69; }

head_sha=$(git rev-parse HEAD)
repo_slug=$(gh repo view --json nameWithOwner -q .nameWithOwner)
[[ -n "$repo_slug" ]] || { echo 'Could not resolve canonical GitHub repository' >&2; exit 65; }
[[ $(git status --porcelain | wc -l | tr -d ' ') == 0 ]] || {
  echo 'Refusing CI evidence for a dirty source tree' >&2; exit 65;
}
run_id=$(gh run view "$run" --json databaseId -q .databaseId)
[[ "$run_id" =~ ^[1-9][0-9]*$ ]] || { echo 'Could not resolve Actions run ID' >&2; exit 65; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gh api "repos/$repo_slug/actions/runs/$run_id" >"$work/run.json"
run_attempt=$(jq -er '.run_attempt | select(type == "number" and . > 0)' "$work/run.json")
gh api "repos/$repo_slug/actions/runs/$run_id/attempts/$run_attempt/jobs?per_page=100" >"$work/jobs.json"

receipt=$(jq -c --arg expected "$head_sha" --arg repo "$repo_slug" --argjson attempt "$run_attempt" \
  --slurpfile jobs "$work/jobs.json" '
  . as $run |
  ($jobs[0].jobs // []) as $allJobs |
  (first($allJobs[]? | select(.name == "Wear emulator smoke"))) as $wear |
  (first($allJobs[]? | select(.name == "Android CI"))) as $gate |
  select(.name == "Android CI") |
  select(.path == ".github/workflows/android-ci.yml") |
  select(.head_sha == $expected and .run_attempt == $attempt) |
  select(.html_url | startswith("https://github.com/" + $repo + "/actions/runs/")) |
  select(.event == "push") |
  select(.status == "completed" and .conclusion == "success") |
  select(($wear.run_attempt // $attempt) == $attempt and $wear.conclusion == "success") |
  select(($gate.run_attempt // $attempt) == $attempt and $gate.conclusion == "success") |
  {
    schemaVersion: 1,
    capturedAtUtc: (now | todateiso8601),
    repository: $repo,
    workflow: .name,
    workflowPath: .path,
    runId: .id,
    runAttempt: .run_attempt,
    runUrl: .html_url,
    headSha: .head_sha,
    status: .status,
    conclusion: .conclusion,
    event: .event,
    createdAt: .created_at,
    updatedAt: .updated_at,
    wearJob: {name: $wear.name, conclusion: $wear.conclusion, startedAt: $wear.started_at, completedAt: $wear.completed_at},
    gateJob: {name: $gate.name, conclusion: $gate.conclusion, startedAt: $gate.started_at, completedAt: $gate.completed_at}
  }
' "$work/run.json")
[[ -n "$receipt" ]] || {
  echo 'Run attempt does not prove successful Wear emulator + Android CI gate for current clean HEAD' >&2
  exit 65
}
[[ ! -e "$out" ]] || { echo "Refusing to overwrite $out" >&2; exit 73; }
mkdir -p "$(dirname "$out")"
printf '%s\n' "$receipt" >"$out"
printf 'Captured verified Android CI receipt at %s\n' "$out"
