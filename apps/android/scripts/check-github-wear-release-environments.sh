#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

expected_repo_slug=CodyBontecou/health-md
repo_slug=$(git config --get remote.origin.url 2>/dev/null | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')
[[ "$repo_slug" == "$expected_repo_slug" ]] \
  || { echo "GitHub repository identity mismatch: expected $expected_repo_slug" >&2; exit 65; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
report="$tmp/environments.json"

command -v gh >/dev/null 2>&1 || { echo 'GitHub CLI unavailable for protected-environment proof' >&2; exit 69; }
required=(google-play-qa google-play-production wear-evidence-submission google-play-announce)
entries=()
for environment in "${required[@]}"; do
  environment_json="$tmp/$environment.environment.json"
  secrets_json="$tmp/$environment.secrets.json"
  variables_json="$tmp/$environment.variables.json"
  policies_json="$tmp/$environment.policies.json"
  if ! gh api "repos/$repo_slug/environments/$environment" >"$environment_json" 2>/dev/null; then
    entries+=("$(jq -cn --arg name "$environment" '{name:$name,exists:false,acquisitionComplete:false,customBranchPolicies:false,protectedBranches:false,protectionRuleTypes:[],reviewerCount:0,preventSelfReview:false,secretNames:[],secretTotalCount:0,secretReturnedCount:0,variableNames:[],variableTotalCount:0,variableReturnedCount:0,deploymentPolicies:[],policyTotalCount:0,policyReturnedCount:0}')")
    continue
  fi
  acquisition_complete=true
  if ! gh api --paginate --slurp "repos/$repo_slug/environments/$environment/secrets" >"$secrets_json" 2>/dev/null; then
    acquisition_complete=false
    printf '[{"total_count":0,"secrets":[]}]' >"$secrets_json"
  fi
  if ! gh api --paginate --slurp "repos/$repo_slug/environments/$environment/variables" >"$variables_json" 2>/dev/null; then
    acquisition_complete=false
    printf '[{"total_count":0,"variables":[]}]' >"$variables_json"
  fi
  if ! gh api --paginate --slurp "repos/$repo_slug/environments/$environment/deployment-branch-policies" >"$policies_json" 2>/dev/null; then
    acquisition_complete=false
    printf '[{"total_count":0,"branch_policies":[]}]' >"$policies_json"
  fi
  entries+=("$(jq -cn \
    --arg name "$environment" \
    --argjson acquisitionComplete "$acquisition_complete" \
    --slurpfile environment "$environment_json" \
    --slurpfile secrets "$secrets_json" \
    --slurpfile variables "$variables_json" \
    --slurpfile policies "$policies_json" '
      ($environment[0]) as $e |
      ($secrets[0]) as $secretPages |
      ($variables[0]) as $variablePages |
      ($policies[0]) as $policyPages |
      {
        name:$name,
        exists:true,
        acquisitionComplete:$acquisitionComplete,
        customBranchPolicies:($e.deployment_branch_policy.custom_branch_policies == true),
        protectedBranches:($e.deployment_branch_policy.protected_branches == true),
        protectionRuleTypes:[$e.protection_rules[]?.type],
        reviewerCount:([
          $e.reviewers[]?,
          ($e.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]?)
        ] | length),
        preventSelfReview:any($e.protection_rules[]?;
          .type == "required_reviewers" and .prevent_self_review == true),
        secretNames:[$secretPages[]?.secrets[]?.name],
        secretTotalCount:([$secretPages[]?.total_count // 0] | max // 0),
        secretReturnedCount:([$secretPages[]?.secrets[]?] | length),
        variableNames:[$variablePages[]?.variables[]?.name],
        variableTotalCount:([$variablePages[]?.total_count // 0] | max // 0),
        variableReturnedCount:([$variablePages[]?.variables[]?] | length),
        deploymentPolicies:[$policyPages[]?.branch_policies[]? | {name,type}],
        policyTotalCount:([$policyPages[]?.total_count // 0] | max // 0),
        policyReturnedCount:([$policyPages[]?.branch_policies[]?] | length)
      }
    ')")
done
printf '%s\n' "${entries[@]}" | jq -s --arg repository "$repo_slug" '{schemaVersion:1,repository:$repository,environments:.}' >"$report"

python3 - "$report" "$repo_slug" <<'PY'
from __future__ import annotations
import json
from pathlib import Path
import sys

report_path = Path(sys.argv[1])
repository = sys.argv[2]
try:
    report = json.loads(report_path.read_text())
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"GitHub environment report is invalid: {error}")

if report.get("schemaVersion") != 1 or report.get("repository") != repository:
    raise SystemExit("GitHub environment report identity mismatch")
entries = report.get("environments")
if not isinstance(entries, list):
    raise SystemExit("GitHub environment report has no environment list")
by_name = {entry.get("name"): entry for entry in entries if isinstance(entry, dict)}
errors: list[str] = []

required_secrets = {
    "google-play-qa": {
        "ANDROID_RELEASE_KEYSTORE_BASE64",
        "PLAY_CONSOLE_KEY_JSON",
        "RELEASE_KEY_ALIAS",
        "RELEASE_KEY_PASSWORD",
        "RELEASE_STORE_PASSWORD",
    },
    "google-play-production": {
        "PLAY_CONSOLE_KEY_JSON",
        "WEAR_RELEASE_EVIDENCE_HMAC_KEY",
    },
    "wear-evidence-submission": {"WEAR_RELEASE_EVIDENCE_URL"},
    "google-play-announce": {"PLAY_CONSOLE_KEY_JSON"},
}
required_variables = {
    "google-play-qa": {
        "PLAY_APP_SIGNING_CERT_SHA256",
        "WEAR_SCREENSHOT_REVIEW_TICKET",
        "WEAR_SCREENSHOT_REVIEWER",
    },
    "google-play-production": {
        "PLAY_APP_SIGNING_CERT_SHA256",
        "WEAR_BATTERY_CONTROL_PROFILE",
        "WEAR_BATTERY_REVIEW_TICKET",
        "WEAR_BATTERY_REVIEWER",
        "WEAR_PAIRED_REVIEW_TICKET",
        "WEAR_PAIRED_REVIEWER",
        "WEAR_RELEASE_EVIDENCE_ATTESTOR",
        "WEAR_SCREENSHOT_REVIEW_TICKET",
        "WEAR_SCREENSHOT_REVIEWER",
        "WEAR_SOURCE_REVIEW_TICKET",
        "WEAR_SOURCE_REVIEWER",
    },
    "wear-evidence-submission": set(),
    "google-play-announce": set(),
}
protected = {"google-play-qa", "google-play-production", "wear-evidence-submission"}

def check_exact_inventory(name: str, kind: str, entry: dict, expected: set[str]) -> None:
    values = entry.get(f"{kind}Names")
    total = entry.get(f"{kind}TotalCount")
    returned = entry.get(f"{kind}ReturnedCount")
    if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
        errors.append(f"{name} has invalid {kind} inventory")
        return
    if not isinstance(total, int) or not isinstance(returned, int) or total != returned or returned != len(values):
        errors.append(f"{name} has incomplete {kind} pagination")
    actual = set(values)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing:
        errors.append(f"{name} missing {kind}s: {','.join(missing)}")
    if unexpected:
        errors.append(f"{name} has unexpected {kind}s: {','.join(unexpected)}")

for name, secrets in required_secrets.items():
    entry = by_name.get(name)
    if not entry or entry.get("exists") is not True:
        errors.append(f"missing environment {name}")
        continue
    if entry.get("acquisitionComplete") is not True:
        errors.append(f"{name} configuration API queries are incomplete")
        continue
    check_exact_inventory(name, "secret", entry, secrets)
    check_exact_inventory(name, "variable", entry, required_variables[name])
    if name in protected:
        reviewer_count = entry.get("reviewerCount")
        rule_types = set(entry.get("protectionRuleTypes") or [])
        if not isinstance(reviewer_count, int) or reviewer_count < 1 or "required_reviewers" not in rule_types:
            errors.append(f"{name} lacks required human reviewers")
        if entry.get("preventSelfReview") is not True:
            errors.append(f"{name} allows deployment self-review")
    expected_policy = {"name": "main", "type": "branch"} if name == "google-play-announce" else {"name": "android/v*", "type": "tag"}
    policies = entry.get("deploymentPolicies")
    policy_total = entry.get("policyTotalCount")
    policy_returned = entry.get("policyReturnedCount")
    if not isinstance(policies, list) or not isinstance(policy_total, int) or not isinstance(policy_returned, int):
        errors.append(f"{name} has invalid deployment-policy inventory")
    elif policy_total != policy_returned or policy_returned != len(policies):
        errors.append(f"{name} has incomplete deployment-policy pagination")
    elif policies != [expected_policy]:
        errors.append(f"{name} deployment policies must equal {expected_policy['type']}:{expected_policy['name']}")
    if entry.get("customBranchPolicies") is not True or entry.get("protectedBranches") is not False:
        errors.append(f"{name} does not enforce exact custom deployment policies")

if errors:
    for error in errors:
        print(f"BLOCK {error}", file=sys.stderr)
    raise SystemExit(1)
print("GitHub Wear release environments are present, reviewer-protected, policy-restricted, and configured by name")
PY
