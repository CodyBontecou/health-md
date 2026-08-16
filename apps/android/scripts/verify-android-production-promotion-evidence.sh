#!/usr/bin/env bash
set -euo pipefail

root=${1:-}
expected_sha=${EXPECTED_RELEASE_SHA:-}
expected_version=${EXPECTED_VERSION_NAME:-}
expected_phone=${EXPECTED_PHONE_VERSION_CODE:-}
expected_wear=${EXPECTED_WEAR_VERSION_CODE:-}
expected_app_screenshot=${EXPECTED_WEAR_APP_SCREENSHOT_SHA256:-}
expected_tile_screenshot=${EXPECTED_WEAR_TILE_SCREENSHOT_SHA256:-}
fail() { printf 'Android production promotion evidence: %s\n' "$*" >&2; exit 1; }
[[ -d "$root" ]] || fail 'evidence directory is required'
[[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]] || fail 'EXPECTED_RELEASE_SHA must be lowercase 40-hex'
[[ "$expected_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
  || fail 'EXPECTED_VERSION_NAME must be semantic version'
[[ "$expected_phone" =~ ^[1-9][0-9]*$ && "$expected_wear" =~ ^[1-9][0-9]*$ ]] \
  || fail 'expected phone/Wear version codes are required'
[[ "$expected_app_screenshot" =~ ^[0-9a-f]{64}$ && "$expected_tile_screenshot" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'expected sealed screenshot SHA-256 values are required'

expected_files=$(printf '%s\n' \
  google-play-qa.json google-play-wear-qa.json \
  google-play-production-before.json google-play-wear-production-before.json \
  google-play-qa-edit.json google-play-wear-qa-edit.json \
  google-play-production-payload.json google-play-wear-production-payload.json \
  google-play-production-after.json google-play-wear-production-after.json \
  google-play-production-review.json google-play-wear-production-review.json \
  google-play-wear-screenshots-before.json receipt.json | LC_ALL=C sort)
sums="$root/SHA256SUMS"
[[ -f "$sums" ]] || fail 'SHA256SUMS missing'
actual_files=$(cd "$root" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort)
[[ "$actual_files" == "$expected_files" ]] || fail 'retained evidence file inventory differs'
listed=$(awk '{print $2}' "$sums" | sed 's/^\*//' | LC_ALL=C sort)
[[ "$listed" == "$expected_files" ]] || fail 'checksum inventory differs'
(
  cd "$root"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || fail 'checksum mismatch'

receipt="$root/receipt.json"
jq -e --arg sha "$expected_sha" --arg version "$expected_version" \
  --argjson phone "$expected_phone" --argjson wear "$expected_wear" \
  --arg app "$expected_app_screenshot" --arg tile "$expected_tile_screenshot" '
  .schemaVersion == 1 and .workflow == ".github/workflows/android-promote-production.yml" and
  (.repository | type == "string" and length > 0) and (.runId | type == "number" and . > 0) and
  (.runAttempt | type == "number" and . > 0) and .releaseSha == $sha and .versionName == $version and
  .phoneVersionCode == $phone and .wearVersionCode == $wear and
  .sourceTracks == ["qa","wear:qa"] and
  .destinationTracks == ["production","wear:production"] and
  (.promotionEditId | type == "string" and length > 0) and
  (.commitResponseReceived | type == "boolean") and
  .pairedEditCommitted == true and .productionPairVerified == true and
  .reviewLifecycleVerified == true and
  .wearAppScreenshotSha256 == $app and .wearTileScreenshotSha256 == $tile and
  (.completedAtUtc | type == "string" and endswith("Z"))
' "$receipt" >/dev/null || fail 'receipt identity or atomic-edit result differs'

has_active() {
  local file=$1 code=$2
  jq -e --argjson code "$code" '
    any(.releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))
  ' "$file" >/dev/null
}
has_edit_code() {
  local file=$1 code=$2
  jq -e --arg code "$code" 'any(.releases[]?; any(.versionCodes[]?; tostring == $code))' "$file" >/dev/null
}

has_active "$root/google-play-qa.json" "$expected_phone" || fail 'phone code absent from QA precondition'
has_active "$root/google-play-wear-qa.json" "$expected_wear" || fail 'Wear code absent from wear:qa precondition'
if has_active "$root/google-play-production-before.json" "$expected_phone"; then
  fail 'phone code was already on production before the paired edit'
fi
if has_active "$root/google-play-wear-production-before.json" "$expected_wear"; then
  fail 'Wear code was already on production before the paired edit'
fi
has_edit_code "$root/google-play-qa-edit.json" "$expected_phone" || fail 'paired edit source lacks phone code'
has_edit_code "$root/google-play-wear-qa-edit.json" "$expected_wear" || fail 'paired edit source lacks Wear code'
jq -e --arg code "$expected_phone" '
  .track == "production" and .releases == [{versionCodes:[$code],status:"completed"}]
' "$root/google-play-production-payload.json" >/dev/null || fail 'phone promotion payload differs'
jq -e --arg code "$expected_wear" '
  .track == "wear:production" and .releases == [{versionCodes:[$code],status:"completed"}]
' "$root/google-play-wear-production-payload.json" >/dev/null || fail 'Wear promotion payload differs'
has_active "$root/google-play-production-after.json" "$expected_phone" || fail 'phone postcondition absent'
has_active "$root/google-play-wear-production-after.json" "$expected_wear" || fail 'Wear postcondition absent'
has_active "$root/google-play-production-review.json" "$expected_phone" || fail 'phone review state absent'
has_active "$root/google-play-wear-production-review.json" "$expected_wear" || fail 'Wear review state absent'
for spec in "google-play-production-review.json:$expected_phone" "google-play-wear-production-review.json:$expected_wear"; do
  file=${spec%%:*}; code=${spec#*:}
  jq -e --argjson code "$code" '
    first(.releases[]? | select(any(.activeArtifacts[]?; (.versionCode | tonumber) == $code)) | .releaseLifecycleState) as $state |
    $state == "RELEASE_LIFECYCLE_STATE_IN_REVIEW" or
    $state == "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED" or
    $state == "RELEASE_LIFECYCLE_STATE_PUBLISHED"
  ' "$root/$file" >/dev/null || fail "$file lacks accepted review lifecycle"
done
jq -e --arg app "$expected_app_screenshot" --arg tile "$expected_tile_screenshot" '
  ([.images[]?.sha256 | ascii_downcase] | sort) == ([$app,$tile] | sort) and
  ([.images[]?] | length) == 2
' "$root/google-play-wear-screenshots-before.json" >/dev/null \
  || fail 'pre-promotion committed Wear screenshots differ from sealed assets'

echo 'Android production promotion evidence: exact paired edit receipt is valid'
