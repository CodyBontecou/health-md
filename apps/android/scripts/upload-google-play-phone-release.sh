#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=google-play-phone-policy.sh
source ./scripts/google-play-phone-policy.sh

key=${PLAY_CONSOLE_KEY_PATH:-}
package=${PLAY_PACKAGE_NAME:-com.healthmd.android}
track=${PHONE_PLAY_TRACK:-internal}
release_status=${PLAY_RELEASE_STATUS:-completed}
version_code=${PHONE_VERSION_CODE:-}
aab=${PHONE_AAB:-app/build/outputs/bundle/playRelease/app-play-release.aab}
locale=${PLAY_LISTING_LOCALE:-en-US}
release_notes=${PLAY_RELEASE_NOTES:-play-console/listing/$locale/release-notes/$locale/default.txt}
confirmation=${CONFIRM_PLAY_PHONE_UPLOAD:-}
expected_confirmation="$package:$track:$version_code"
receipt=${PLAY_UPLOAD_RECEIPT_PATH:-}

fail() { printf 'Phone Play upload: %s\n' "$*" >&2; exit 1; }
[[ -n "$key" && -r "$key" ]] || fail 'PLAY_CONSOLE_KEY_PATH must name a readable service-account JSON file'
play_phone_assert_version_code "$version_code" || exit 1
[[ "$track" == internal ]] || fail 'the release workflow may upload only to the internal track'
[[ "$confirmation" == "$expected_confirmation" ]] || fail "set CONFIRM_PLAY_PHONE_UPLOAD=$expected_confirmation"
[[ -f "$aab" ]] || fail "phone AAB is missing: $aab"
[[ -s "$release_notes" ]] || fail "release notes are missing: $release_notes"
for command in curl jq openssl sha256sum; do command -v "$command" >/dev/null || fail "$command is required"; done

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
private_key=$(mktemp)
work=$(mktemp -d)
edit_id=''
committed=false
cleanup() {
  rm -f "$private_key"
  rm -rf "$work"
  if [[ -n "$edit_id" && "$committed" != true && -n ${token:-} ]]; then
    curl -fsS --retry 2 -X DELETE -H "Authorization: Bearer $token" \
      "$api/edits/$edit_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

jq -er .private_key "$key" >"$private_key"
chmod 600 "$private_key"
now=$(date +%s)
header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)
claims=$(jq -nc \
  --arg iss "$(jq -er .client_email "$key")" \
  --arg aud "$(jq -er .token_uri "$key")" \
  --argjson iat "$now" \
  '{iss:$iss,scope:"https://www.googleapis.com/auth/androidpublisher",aud:$aud,iat:$iat,exp:($iat+1200)}' | base64url)
signature=$(printf '%s' "$header.$claims" | openssl dgst -sha256 -sign "$private_key" | base64url)
token=$(curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS \
  --data-urlencode "assertion=$header.$claims.$signature" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  "$(jq -er .token_uri "$key")" | jq -er .access_token)
api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package"
upload_api="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package"
auth=(-H "Authorization: Bearer $token")

track_contains_code() {
  local path=$1 code=$2
  jq -e --argjson code "$code" '
    any(.releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))
  ' "$path" >/dev/null
}

# A rerun after a lost workflow response must not consume or re-upload a versionCode. Reconcile the
# exact immutable code first. The initial workflow's retained pre-mutation intent binds its AAB hash.
encoded_track=${track//:/%3A}
if curl --fail-with-body --retry 2 --retry-all-errors --max-time 30 -sS "${auth[@]}" \
    "$api/tracks/$encoded_track/releases" -o "$work/track-before.json" \
  && track_contains_code "$work/track-before.json" "$version_code"; then
  if [[ -n "$receipt" ]]; then
    mkdir -p "$(dirname "$receipt")"
    jq -n --argjson code "$version_code" --arg track "$track" \
      --arg aabSha256 "$(sha256sum "$aab" | awk '{print $1}')" \
      --arg reconciledAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{schemaVersion:1,versionCode:$code,track:$track,aabSha256:$aabSha256,
        editCommitted:true,commitResponseReceived:false,reconciledExisting:true,
        verifiedAtUtc:$reconciledAt}' >"$receipt"
  fi
  printf 'Phone %s is already active on %s; reconciled without another upload.\n' "$version_code" "$track"
  exit 0
fi

edit_id=$(curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS \
  -X POST "${auth[@]}" -H 'Content-Type: application/json' -d '{}' "$api/edits" | jq -er .id)

actual=$(curl --fail-with-body --retry 3 --retry-all-errors --max-time 300 -sS \
  -X POST "${auth[@]}" -H 'Content-Type: application/octet-stream' --data-binary "@$aab" \
  "$upload_api/edits/$edit_id/bundles?uploadType=media" | jq -er '.versionCode | tostring')
[[ "$actual" == "$version_code" ]] || fail "$aab uploaded unexpected versionCode $actual"

release_payload=$(play_phone_release_payload "$version_code" "$release_status" "$locale" "$release_notes")
curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS \
  -X PUT "${auth[@]}" -H 'Content-Type: application/json' --data "$release_payload" \
  "$api/edits/$edit_id/tracks/$encoded_track" >"$work/track-update.json"
play_phone_validate_track_response "$work/track-update.json" "$version_code" "$release_status" \
  || fail "$track update response did not contain only versionCode $version_code"

validation_response=$(curl -sS --max-time 30 -w '\n%{http_code}' "${auth[@]}" \
  -X POST -H 'Content-Type: application/json' -d '' "$api/edits/$edit_id:validate")
validation_http=$(printf '%s' "$validation_response" | tail -n 1)
validation_body=$(printf '%s' "$validation_response" | sed '$d')
validation_errors=$(printf '%s' "$validation_body" \
  | jq -r '(.error.message // .errorMessage // empty)' 2>/dev/null || true)
if [[ "$validation_http" != 200 || -n "$validation_errors" ]]; then
  fail "Play rejected the phone edit at validation: $validation_errors${validation_body:+ ($validation_body)}"
fi

# The edit commit is non-idempotent: issue it exactly once. A lost transport response is reconciled
# against the exact committed track instead of retrying the POST.
commit_response_received=true
set +e
curl --fail-with-body --max-time 30 -sS \
  -X POST "${auth[@]}" -H 'Content-Type: application/json' \
  "$api/edits/$edit_id:commit?changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW" \
  --data '' -o "$work/commit-response.json"
commit_exit_code=$?
set -e
if [[ $commit_exit_code -eq 22 ]]; then
  jq -r '.error.message // .errorMessage // "(no body)"' "$work/commit-response.json" >&2 2>/dev/null || true
  fail 'phone Play commit received a definite HTTP rejection; reconciliation is forbidden'
elif [[ $commit_exit_code -ne 0 ]]; then
  commit_response_received=false
fi

commit_visible=false
for _ in $(seq 1 20); do
  if curl --fail-with-body --retry 2 --retry-all-errors --max-time 30 -sS "${auth[@]}" \
      "$api/tracks/$encoded_track/releases" -o "$work/track-after.json" \
    && track_contains_code "$work/track-after.json" "$version_code"; then
    commit_visible=true
    break
  fi
  sleep 5
done
$commit_visible || fail 'phone Play commit response/postcondition is absent; edit was not proven committed'
committed=true

if [[ -n "$receipt" ]]; then
  mkdir -p "$(dirname "$receipt")"
  jq -n --arg edit "$edit_id" --argjson code "$version_code" --arg track "$track" \
    --arg aabSha256 "$(sha256sum "$aab" | awk '{print $1}')" \
    --argjson response "$commit_response_received" \
    --arg completedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
      schemaVersion:1,versionCode:$code,track:$track,aabSha256:$aabSha256,
      playEditId:$edit,editCommitted:true,commitResponseReceived:$response,
      reconciledExisting:false,verifiedAtUtc:$completedAt
    }' >"$receipt"
fi
printf 'Uploaded phone %s to %s in one Play edit (commit response received: %s).\n' \
  "$version_code" "$track" "$commit_response_received"
