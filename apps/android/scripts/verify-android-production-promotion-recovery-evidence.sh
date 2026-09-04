#!/usr/bin/env bash
set -euo pipefail

root=${1:-}
expected_sha=${EXPECTED_RELEASE_SHA:-}
expected_version=${EXPECTED_VERSION_NAME:-}
expected_phone=${EXPECTED_PHONE_VERSION_CODE:-}
expected_wear=${EXPECTED_WEAR_VERSION_CODE:-}
expected_app=${EXPECTED_WEAR_APP_SCREENSHOT_SHA256:-}
expected_tile=${EXPECTED_WEAR_TILE_SCREENSHOT_SHA256:-}
fail() { printf 'Android production promotion recovery evidence: %s\n' "$*" >&2; exit 1; }
[[ -d "$root" ]] || fail 'evidence directory is required'
[[ "$expected_sha" =~ ^[0-9a-f]{40}$ && "$expected_app" =~ ^[0-9a-f]{64}$ && "$expected_tile" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'expected release and screenshot SHA values are required'
[[ "$expected_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
  || fail 'EXPECTED_VERSION_NAME must be semantic version'
[[ "$expected_phone" =~ ^[1-9][0-9]*$ && "$expected_wear" =~ ^[1-9][0-9]*$ ]] \
  || fail 'expected version codes are required'
expected_files=$(printf '%s\n' intent.json original-run.json original-jobs.json receipt.json \
  google-play-production-current.json google-play-wear-production-current.json \
  google-play-wear-screenshots-current.json | LC_ALL=C sort)
[[ -f "$root/SHA256SUMS" ]] || fail 'SHA256SUMS missing'
actual=$(cd "$root" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort)
listed=$(awk '{print $2}' "$root/SHA256SUMS" | sed 's/^\*//' | LC_ALL=C sort)
[[ "$actual" == "$expected_files" && "$listed" == "$expected_files" ]] || fail 'file/checksum inventory differs'
(cd "$root" && sha256sum --check --strict SHA256SUMS >/dev/null) || fail 'checksum mismatch'

intent="$root/intent.json"; receipt="$root/receipt.json"
original_run=$(jq -er .runId "$intent")
original_attempt=$(jq -er .runAttempt "$intent")
evidence_run=$(jq -er .evidenceRunId "$intent")
evidence_attempt=$(jq -er .evidenceRunAttempt "$intent")
intent_repository=$(jq -er .repository "$intent")
[[ "$original_run" =~ ^[1-9][0-9]*$ && "$original_attempt" =~ ^[1-9][0-9]*$ && "$evidence_run" =~ ^[1-9][0-9]*$ && "$evidence_attempt" =~ ^[1-9][0-9]*$ && -n "$intent_repository" ]] \
  || fail 'intent run/repository identity invalid'
jq -e --arg sha "$expected_sha" --arg version "$expected_version" \
  --arg app "$expected_app" --arg tile "$expected_tile" \
  --argjson phone "$expected_phone" --argjson wear "$expected_wear" '
  .schemaVersion == 1 and .workflow == ".github/workflows/android-promote-production.yml" and
  (.evidenceRunAttempt | type == "number" and . > 0) and
  .releaseSha == $sha and .versionName == $version and
  .phoneVersionCode == $phone and .wearVersionCode == $wear and
  .sourceTracks == ["qa","wear:qa2"] and .destinationTracks == ["production","wear:production"] and
  .wearAppScreenshotSha256 == $app and .wearTileScreenshotSha256 == $tile and
  .promotionPrepared == true
' "$intent" >/dev/null || fail 'immutable promotion intent differs'
jq -e --arg sha "$expected_sha" --arg version "$expected_version" \
  --arg app "$expected_app" --arg tile "$expected_tile" --arg repository "$intent_repository" \
  --argjson phone "$expected_phone" --argjson wear "$expected_wear" \
  --argjson original "$original_run" --argjson attempt "$original_attempt" \
  --argjson evidence "$evidence_run" --argjson evidenceAttempt "$evidence_attempt" '
  .schemaVersion == 1 and .workflow == ".github/workflows/android-promote-production-recover.yml" and
  .repository == $repository and .evidenceRunId == $evidence and .evidenceRunAttempt == $evidenceAttempt and
  .releaseSha == $sha and .versionName == $version and
  .phoneVersionCode == $phone and .wearVersionCode == $wear and
  .originalPromotionRunId == $original and .originalPromotionRunAttempt == $attempt and
  (.recoveryRunId | type == "number" and . > 0) and
  (.recoveryRunAttempt | type == "number" and . > 0) and
  .wearAppScreenshotSha256 == $app and .wearTileScreenshotSha256 == $tile and
  .originalPairedEditStepSucceeded == true and .currentProductionPairVerified == true and
  .currentScreenshotsVerified == true and .recoveryOnly == true and
  (.recoveredAtUtc | type == "string" and endswith("Z"))
' "$receipt" >/dev/null || fail 'recovery receipt differs'
jq -e --argjson run "$original_run" --argjson attempt "$original_attempt" \
  --arg repository "$intent_repository" --arg sha "$expected_sha" '
  .id == $run and .run_attempt == $attempt and .repository.full_name == $repository and .head_sha == $sha and
  .path == ".github/workflows/android-promote-production.yml" and
  .event == "workflow_dispatch" and .status == "completed"
' "$root/original-run.json" >/dev/null || fail 'original promotion run provenance differs'
jq -e --argjson attempt "$original_attempt" '
  any(.jobs[]?; .name == "Promote Android release to production" and
    (.run_attempt // $attempt) == $attempt and
    any(.steps[]?; .name == "Verify mandatory Wear release evidence before production mutation" and .conclusion == "success") and
    any(.steps[]?; .name == "Retain immutable production-promotion intent" and .conclusion == "success") and
    any(.steps[]?; .name == "Verify committed Play Wear screenshots match sealed approvals" and .conclusion == "success") and
    any(.steps[]?; .name == "Verify internal source and production precondition" and .conclusion == "success") and
    any(.steps[]?; .name == "Promote exact paired internal release to production" and .conclusion == "success") and
    any(.steps[]?; .name == "Remove ephemeral credentials" and .conclusion == "success"))
' "$root/original-jobs.json" >/dev/null || fail 'original exact paired edit or credential cleanup step did not succeed'

verify_current() {
  local file=$1 code=$2
  jq -e --argjson code "$code" '
    first(.releases[]? | select(any(.activeArtifacts[]?; (.versionCode | tonumber) == $code)) | .releaseLifecycleState) as $state |
    $state == "RELEASE_LIFECYCLE_STATE_IN_REVIEW" or
    $state == "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED" or
    $state == "RELEASE_LIFECYCLE_STATE_PUBLISHED"
  ' "$file" >/dev/null
}
verify_current "$root/google-play-production-current.json" "$expected_phone" || fail 'current phone production state invalid'
verify_current "$root/google-play-wear-production-current.json" "$expected_wear" || fail 'current Wear production state invalid'
jq -e --arg app "$expected_app" --arg tile "$expected_tile" '
  ([.images[]?.sha256 | ascii_downcase] | sort) == ([$app,$tile] | sort) and
  ([.images[]?] | length) == 2
' "$root/google-play-wear-screenshots-current.json" >/dev/null || fail 'current screenshot state differs'
echo 'Android production promotion recovery evidence: original exact edit is independently recovered'
