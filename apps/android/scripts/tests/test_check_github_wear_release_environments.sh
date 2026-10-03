#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
script=./scripts/check-github-wear-release-environments.sh
if grep -q 'GITHUB_REPOSITORY_OVERRIDE' "$script"; then
  echo 'GitHub environment proof must not support repository redirection' >&2
  exit 1
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
report="$tmp/report.json"

cat >"$report" <<'JSON'
{
  "schemaVersion": 1,
  "repository": "CodyBontecou/health-md",
  "environments": [
    {
      "name": "google-play-qa",
      "exists": true,
      "customBranchPolicies": true,
      "protectedBranches": false,
      "protectionRuleTypes": ["required_reviewers", "branch_policy"],
      "reviewerCount": 1,
      "preventSelfReview": true,
      "secretNames": ["ANDROID_RELEASE_KEYSTORE_BASE64", "PLAY_CONSOLE_KEY_JSON", "RELEASE_KEY_ALIAS", "RELEASE_KEY_PASSWORD", "RELEASE_STORE_PASSWORD"],
      "variableNames": ["PLAY_APP_SIGNING_CERT_SHA256", "WEAR_SCREENSHOT_REVIEW_TICKET", "WEAR_SCREENSHOT_REVIEWER"],
      "deploymentPolicies": [{"name": "android/v*", "type": "tag"}]
    },
    {
      "name": "google-play-production",
      "exists": true,
      "customBranchPolicies": true,
      "protectedBranches": false,
      "protectionRuleTypes": ["required_reviewers", "branch_policy"],
      "reviewerCount": 2,
      "preventSelfReview": true,
      "secretNames": ["PLAY_CONSOLE_KEY_JSON", "WEAR_RELEASE_EVIDENCE_HMAC_KEY"],
      "variableNames": ["PLAY_APP_SIGNING_CERT_SHA256", "WEAR_BATTERY_CONTROL_PROFILE", "WEAR_BATTERY_REVIEW_TICKET", "WEAR_BATTERY_REVIEWER", "WEAR_PAIRED_REVIEW_TICKET", "WEAR_PAIRED_REVIEWER", "WEAR_RELEASE_EVIDENCE_ATTESTOR", "WEAR_SCREENSHOT_REVIEW_TICKET", "WEAR_SCREENSHOT_REVIEWER", "WEAR_SOURCE_REVIEW_TICKET", "WEAR_SOURCE_REVIEWER"],
      "deploymentPolicies": [{"name": "android/v*", "type": "tag"}]
    },
    {
      "name": "wear-evidence-submission",
      "exists": true,
      "customBranchPolicies": true,
      "protectedBranches": false,
      "protectionRuleTypes": ["required_reviewers", "branch_policy"],
      "reviewerCount": 1,
      "preventSelfReview": true,
      "secretNames": ["WEAR_RELEASE_EVIDENCE_URL"],
      "variableNames": [],
      "deploymentPolicies": [{"name": "android/v*", "type": "tag"}]
    },
    {
      "name": "google-play-announce",
      "exists": true,
      "customBranchPolicies": true,
      "protectedBranches": false,
      "protectionRuleTypes": ["branch_policy"],
      "reviewerCount": 0,
      "preventSelfReview": false,
      "secretNames": ["PLAY_CONSOLE_KEY_JSON"],
      "variableNames": [],
      "deploymentPolicies": [{"name": "main", "type": "branch"}]
    }
  ]
}
JSON

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == api && $# -ge 2 ]]
endpoint=${!#}
python3 - "$MOCK_GITHUB_ENV_REPORT" "$endpoint" <<'PY'
from pathlib import Path
import json,sys
report=json.loads(Path(sys.argv[1]).read_text())
endpoint=sys.argv[2]
prefix=f"repos/{report['repository']}/environments/"
if not endpoint.startswith(prefix): raise SystemExit(1)
remainder=endpoint[len(prefix):]
name, separator, suffix=remainder.partition('/')
entry=next((item for item in report['environments'] if item['name'] == name and item.get('exists') is True), None)
if entry is None: raise SystemExit(1)
if suffix in entry.get('failRequests', []): raise SystemExit(1)
if not separator:
 rules=[]
 for kind in entry.get('protectionRuleTypes', []):
  rule={'type':kind}
  if kind == 'required_reviewers':
   rule['reviewers']=[{'type':'User','reviewer':{'login':f'reviewer-{index}'}} for index in range(entry.get('reviewerCount', 0))]
   rule['prevent_self_review']=entry.get('preventSelfReview', False)
  rules.append(rule)
 print(json.dumps({
  'name':name,
  'protection_rules':rules,
  'reviewers':None,
  'deployment_branch_policy':{
   'custom_branch_policies':entry.get('customBranchPolicies'),
   'protected_branches':entry.get('protectedBranches'),
  },
 }))
elif suffix == 'secrets':
 names=entry.get('secretNames', [])
 print(json.dumps([{'total_count':entry.get('secretTotalCount', len(names)), 'secrets':[{'name':value} for value in names]}]))
elif suffix == 'variables':
 names=entry.get('variableNames', [])
 print(json.dumps([{'total_count':entry.get('variableTotalCount', len(names)), 'variables':[{'name':value} for value in names]}]))
elif suffix == 'deployment-branch-policies':
 policies=entry.get('deploymentPolicies', [])
 print(json.dumps([{'total_count':entry.get('policyTotalCount', len(policies)), 'branch_policies':policies}]))
else:
 raise SystemExit(1)
PY
BASH
chmod +x "$tmp/bin/gh"

run_check() {
  PATH="$tmp/bin:$PATH" MOCK_GITHUB_ENV_REPORT="$1" GITHUB_REPOSITORY_OVERRIDE=CodyBontecou/health-md \
    "$script" >"$tmp/out" 2>"$tmp/error"
}
expect_failure() {
  local name=$1 expected=$2
  local fixture="$tmp/$name.json"
  cp "$report" "$fixture"
  shift 2
  python3 - "$fixture" "$@" <<'PY'
from pathlib import Path
import json,sys
path=Path(sys.argv[1]); operation=sys.argv[2:]
data=json.loads(path.read_text())
kind=operation[0]
if kind == 'remove-environment':
 data['environments']=[entry for entry in data['environments'] if entry['name'] != operation[1]]
elif kind == 'reviewers':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['reviewerCount']=0
 entry['protectionRuleTypes']=[value for value in entry['protectionRuleTypes'] if value != 'required_reviewers']
elif kind == 'allow-self-review':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['preventSelfReview']=False
elif kind == 'remove-secret':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['secretNames'].remove(operation[2])
elif kind == 'remove-variable':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['variableNames'].remove(operation[2])
elif kind == 'remove-policy':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['deploymentPolicies']=[]
elif kind == 'add-policy':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['deploymentPolicies'].append({'name':operation[2], 'type':operation[3]})
elif kind == 'add-secret':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['secretNames'].append(operation[2])
elif kind == 'add-variable':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['variableNames'].append(operation[2])
elif kind == 'truncate-secrets':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['secretTotalCount']=len(entry['secretNames']) + 1
elif kind == 'disable-custom-policy':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry['customBranchPolicies']=False
elif kind == 'fail-request':
 entry=next(item for item in data['environments'] if item['name'] == operation[1])
 entry.setdefault('failRequests', []).append(operation[2])
else:
 raise AssertionError(operation)
path.write_text(json.dumps(data))
PY
  if run_check "$fixture"; then
    echo "environment policy fixture unexpectedly passed: $name" >&2
    exit 1
  fi
  grep -q "$expected" "$tmp/error"
}

run_check "$report"
grep -q 'reviewer-protected' "$tmp/out"
expect_failure missing-qa 'missing environment google-play-qa' remove-environment google-play-qa
expect_failure unreviewed-production 'google-play-production lacks required human reviewers' reviewers google-play-production
expect_failure self-review-qa 'google-play-qa allows deployment self-review' allow-self-review google-play-qa
expect_failure missing-qa-secret 'google-play-qa missing secrets: PLAY_CONSOLE_KEY_JSON' remove-secret google-play-qa PLAY_CONSOLE_KEY_JSON
expect_failure missing-qa-variable 'google-play-qa missing variables: WEAR_SCREENSHOT_REVIEWER' remove-variable google-play-qa WEAR_SCREENSHOT_REVIEWER
expect_failure missing-production-variable 'google-play-production missing variables: WEAR_SOURCE_REVIEWER' remove-variable google-play-production WEAR_SOURCE_REVIEWER
expect_failure missing-submission-policy 'wear-evidence-submission deployment policies must equal tag:android/v\*' remove-policy wear-evidence-submission
expect_failure extra-production-policy 'google-play-production deployment policies must equal tag:android/v\*' add-policy google-play-production '*' branch
expect_failure extra-submission-secret 'wear-evidence-submission has unexpected secrets: PLAY_CONSOLE_KEY_JSON' add-secret wear-evidence-submission PLAY_CONSOLE_KEY_JSON
expect_failure extra-announcement-variable 'google-play-announce has unexpected variables: PLAY_CONSOLE_KEY_JSON' add-variable google-play-announce PLAY_CONSOLE_KEY_JSON
expect_failure truncated-secret-page 'google-play-qa has incomplete secret pagination' truncate-secrets google-play-qa
expect_failure failed-empty-variables-request 'google-play-qa configuration API queries are incomplete' fail-request google-play-qa variables
expect_failure failed-secrets-request 'google-play-production configuration API queries are incomplete' fail-request google-play-production secrets
expect_failure failed-policy-request 'wear-evidence-submission configuration API queries are incomplete' fail-request wear-evidence-submission deployment-branch-policies
expect_failure custom-policy-disabled 'google-play-production does not enforce exact custom deployment policies' disable-custom-policy google-play-production
expect_failure missing-announce-secret 'google-play-announce missing secrets: PLAY_CONSOLE_KEY_JSON' remove-secret google-play-announce PLAY_CONSOLE_KEY_JSON

echo 'GitHub Wear release environment policy tests passed'
