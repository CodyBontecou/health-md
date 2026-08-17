#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root="$tmp/evidence"; mkdir "$root"
sha=1111111111111111111111111111111111111111
app=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tile=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
jq -n --arg sha "$sha" --arg app "$app" --arg tile "$tile" '{
  schemaVersion:1,repository:"owner/repo",workflow:".github/workflows/android-promote-production.yml",
  runId:123,runAttempt:1,evidenceRunId:88,evidenceRunAttempt:3,releaseSha:$sha,versionName:"1.7.1",
  phoneVersionCode:29,wearVersionCode:1000029,sourceTracks:["qa","wear:qa"],
  destinationTracks:["production","wear:production"],wearAppScreenshotSha256:$app,
  wearTileScreenshotSha256:$tile,promotionPrepared:true,preparedAtUtc:"2026-08-14T00:00:00Z"
}' >"$root/intent.json"
jq -n --arg sha "$sha" '{id:123,run_attempt:1,head_sha:$sha,repository:{full_name:"owner/repo"},path:".github/workflows/android-promote-production.yml",event:"workflow_dispatch",status:"completed",conclusion:"failure"}' >"$root/original-run.json"
jq -n '{jobs:[{name:"Promote Android release to production",conclusion:"failure",steps:[
  {name:"Verify mandatory Wear release evidence before production mutation",conclusion:"success"},
  {name:"Retain immutable production-promotion intent",conclusion:"success"},
  {name:"Verify committed Play Wear screenshots match sealed approvals",conclusion:"success"},
  {name:"Verify internal source and production precondition",conclusion:"success"},
  {name:"Promote exact paired internal release to production",conclusion:"success"},
  {name:"Remove ephemeral credentials",conclusion:"success"}
]}]}' >"$root/original-jobs.json"
phone='{"releases":[{"activeArtifacts":[{"versionCode":"29"}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_PUBLISHED"}]}'
wear='{"releases":[{"activeArtifacts":[{"versionCode":"1000029"}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_IN_REVIEW"}]}'
printf '%s\n' "$phone" >"$root/google-play-production-current.json"
printf '%s\n' "$wear" >"$root/google-play-wear-production-current.json"
printf '{"images":[{"sha256":"%s"},{"sha256":"%s"}]}\n' "$app" "$tile" >"$root/google-play-wear-screenshots-current.json"
jq -n --arg sha "$sha" --arg app "$app" --arg tile "$tile" '{
  schemaVersion:1,repository:"owner/repo",workflow:".github/workflows/android-promote-production-recover.yml",
  recoveryRunId:456,recoveryRunAttempt:1,originalPromotionRunId:123,originalPromotionRunAttempt:1,
  evidenceRunId:88,evidenceRunAttempt:3,releaseSha:$sha,versionName:"1.7.1",
  phoneVersionCode:29,wearVersionCode:1000029,wearAppScreenshotSha256:$app,wearTileScreenshotSha256:$tile,
  originalPairedEditStepSucceeded:true,currentProductionPairVerified:true,currentScreenshotsVerified:true,
  recoveryOnly:true,recoveredAtUtc:"2026-08-14T01:00:00Z"
}' >"$root/receipt.json"
seal(){ (cd "$root" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort | while IFS= read -r file; do sha256sum "$file"; done >SHA256SUMS); }
verify(){ EXPECTED_RELEASE_SHA="$sha" EXPECTED_VERSION_NAME=1.7.1 EXPECTED_PHONE_VERSION_CODE=29 EXPECTED_WEAR_VERSION_CODE=1000029 EXPECTED_WEAR_APP_SCREENSHOT_SHA256="$app" EXPECTED_WEAR_TILE_SCREENSHOT_SHA256="$tile" ./scripts/verify-android-production-promotion-recovery-evidence.sh "$root" >/dev/null; }
seal; verify; cp -R "$root" "$tmp/good"
jq '.originalPromotionRunAttempt=2' "$root/receipt.json" >"$tmp/receipt"; mv "$tmp/receipt" "$root/receipt.json"; seal
if verify 2>/dev/null; then echo 'accepted recovery receipt for a different original run attempt' >&2; exit 1; fi
rm -rf "$root"; cp -R "$tmp/good" "$root"
jq '.evidenceRunAttempt=4' "$root/receipt.json" >"$tmp/receipt"; mv "$tmp/receipt" "$root/receipt.json"; seal
if verify 2>/dev/null; then echo 'accepted recovery receipt for a substituted evidence-ingest attempt' >&2; exit 1; fi
rm -rf "$root"; cp -R "$tmp/good" "$root"
jq '.head_sha="2222222222222222222222222222222222222222"' "$root/original-run.json" >"$tmp/run"; mv "$tmp/run" "$root/original-run.json"; seal
if verify 2>/dev/null; then echo 'accepted original promotion run from a different release SHA' >&2; exit 1; fi
rm -rf "$root"; cp -R "$tmp/good" "$root"
jq '.jobs[0].steps |= map(if .name == "Promote exact paired internal release to production" then .conclusion="failure" else . end)' "$root/original-jobs.json" >"$tmp/jobs"; mv "$tmp/jobs" "$root/original-jobs.json"; seal
if verify 2>/dev/null; then echo 'accepted failed original paired edit step' >&2; exit 1; fi
rm -rf "$root"; cp -R "$tmp/good" "$root"
printf '%s\n' '{"images":[]}' >"$root/google-play-wear-screenshots-current.json"; seal
if verify 2>/dev/null; then echo 'accepted missing current screenshots' >&2; exit 1; fi
echo 'Android production promotion recovery evidence tests passed'
