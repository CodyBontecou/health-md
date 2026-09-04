#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=google-play-paired-policy.sh
source ./scripts/google-play-paired-policy.sh
key=${PLAY_CONSOLE_KEY_PATH:-}
package=${PLAY_PACKAGE_NAME:-com.healthmd.android}
phone_track=${PHONE_PLAY_TRACK:-qa}
wear_track=${WEAR_PLAY_TRACK:-wear:internal}
release_status=${PLAY_RELEASE_STATUS:-completed}
phone_code=${PHONE_VERSION_CODE:-}
wear_code=${WEAR_VERSION_CODE:-}
phone_aab=${PHONE_AAB:-app/build/outputs/bundle/playRelease/app-play-release.aab}
wear_aab=${WEAR_AAB:-wear/build/outputs/bundle/release/wear-release.aab}
confirmation=${CONFIRM_PLAY_PAIRED_UPLOAD:-}
expected_confirmation="$package:$phone_track:$wear_track:$phone_code:$wear_code"

fail() { printf 'Paired Play upload: %s\n' "$*" >&2; exit 1; }
[[ -n "$key" && -r "$key" ]] || fail 'PLAY_CONSOLE_KEY_PATH must name a readable service-account JSON file'
[[ "$phone_code" =~ ^[1-9][0-9]*$ && "$wear_code" =~ ^[1-9][0-9]*$ ]] \
  || fail 'PHONE_VERSION_CODE and WEAR_VERSION_CODE are required positive integers'
(( phone_code < 1000000 && wear_code >= 1000000 )) \
  || fail 'phone/Wear version codes are outside their reserved ranges'
[[ "$confirmation" == "$expected_confirmation" ]] || fail "set CONFIRM_PLAY_PAIRED_UPLOAD=$expected_confirmation"
[[ -f "$phone_aab" && -f "$wear_aab" ]] || fail 'phone/Wear AAB pair is missing'
case "$release_status" in completed|draft) ;; *) fail "unsupported release status: $release_status" ;; esac
play_assert_distinct_tracks "$phone_track" "$wear_track" || fail 'phone and Wear must use distinct default/form-factor tracks'
./scripts/validate-wear-artifact.sh "$wear_aab" "$phone_aab" >/dev/null
for command in curl jq openssl; do command -v "$command" >/dev/null || fail "$command is required"; done

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

edit_id=$(curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS \
  -X POST "${auth[@]}" -H 'Content-Type: application/json' -d '{}' "$api/edits" | jq -er .id)

upload_bundle() {
  local path=$1 expected=$2 actual
  actual=$(curl --fail-with-body --retry 3 --retry-all-errors --max-time 300 -sS \
    -X POST "${auth[@]}" -H 'Content-Type: application/octet-stream' --data-binary "@$path" \
    "$upload_api/edits/$edit_id/bundles?uploadType=media" | jq -er '.versionCode | tostring')
  [[ "$actual" == "$expected" ]] || fail "$path uploaded unexpected versionCode $actual"
}
upload_bundle "$phone_aab" "$phone_code"
upload_bundle "$wear_aab" "$wear_code"

# A Wear form-factor track only persists on Play when its creating commit also carries a
# real release: an empty track created ahead of the release is silently discarded. Create
# the track inside this edit (same commit as the release) when it does not exist yet.
ensure_form_factor_track() {
  local track=$1 encoded form_factor
  encoded=${track//:/%3A}
  if curl -fsS --max-time 30 -sS "${auth[@]}" \
      "$api/edits/$edit_id/tracks/$encoded" >/dev/null 2>&1; then
    return 0
  fi
  case "$track" in
    wear:*) form_factor=WEAR ;;
    *) form_factor=DEFAULT ;;
  esac
  create_response=$(curl -sS --max-time 30 -w '\n%{http_code}' \
    -X POST "${auth[@]}" -H 'Content-Type: application/json' \
    -d "{\"track\":\"$track\",\"formFactor\":\"$form_factor\",\"type\":\"CLOSED_TESTING\"}" \
    "$api/edits/$edit_id/tracks")
  create_http=$(printf '%s' "$create_response" | tail -n 1)
  if [[ "$create_http" != "200" && "$create_http" != "409" ]]; then
    fail "could not create form-factor track $track: $create_response"
  fi
}
ensure_form_factor_track "$wear_track"

release_payload() { play_release_payload "$1" "$release_status"; }
update_track() {
  local track=$1 code=$2 encoded response
  encoded=${track//:/%3A}
  response="$work/${encoded}.json"
  curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS \
    -X PUT "${auth[@]}" -H 'Content-Type: application/json' \
    --data "$(release_payload "$code")" "$api/edits/$edit_id/tracks/$encoded" >"$response"
  # Track update responses are Google EditTrack resources. Verify the semantic postcondition
  # without depending on the optional echoed track-name field.
  play_validate_track_response "$response" "$code" "$release_status" \
    || fail "$track update response did not contain only versionCode $code"
}
update_track "$phone_track" "$phone_code"
update_track "$wear_track" "$wear_code"

# Fail closed on Play validation errors before the non-idempotent commit. edits.validate
# is side-effect free: it reports exactly what a commit would reject (track/artifact kind
# mismatches, target-API policy floors, listing problems) without consuming the edit.
validation_response=$(curl -sS --max-time 30 -w '\n%{http_code}' "${auth[@]}" \
  -X POST -H 'Content-Type: application/json' -d '' \
  "$api/edits/$edit_id:validate")
validation_http=$(printf '%s' "$validation_response" | tail -n 1)
validation_body=$(printf '%s' "$validation_response" | sed '$d')
validation_errors=$(printf '%s' "$validation_body" \
  | jq -r '(.error.message // .errorMessage // empty)' 2>/dev/null || true)
if [[ "$validation_http" != "200" || -n "$validation_errors" ]]; then
  fail "Play rejected the paired edit at validation: $validation_errors${validation_body:+ ($validation_body)}"
fi

# Exact-release Wear screenshots cannot exist until Play has generated and signed an installable
# APK from this upload. Do not create a circular gate or replace listing assets here. After closed-
# track installation and physical capture, the separately confirmed screenshot-sync transaction
# verifies capture receipts, generated APK identity, signer identity, and remote image digests.

# Edit commit is a non-idempotent POST: issue it exactly once. If the HTTP response is lost after
# Play commits, reconcile the exact two track postconditions instead of blindly retrying and then
# misclassifying consumed version codes as an upload failure.
commit_response_received=true
set +e
curl --fail-with-body --max-time 30 -sS \
  -X POST "${auth[@]}" -H 'Content-Type: application/json' \
  "$api/edits/$edit_id:commit?changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW" \
  --data '' -o "$work/commit-response.json"
commit_exit_code=$?
set -e
if [[ $commit_exit_code -eq 22 ]]; then
  # Surface the definite HTTP rejection body; the commit is non-idempotent, so no retry.
  jq -r '.error.message // .errorMessage // "(no body)"' "$work/commit-response.json" >&2 2>/dev/null || true
  fail 'paired Play commit received a definite HTTP rejection; reconciliation is forbidden'
elif [[ $commit_exit_code -ne 0 ]]; then
  commit_response_received=false
fi
track_contains_code() {
  local path=$1 code=$2
  jq -e --argjson code "$code" '
    any(.releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))
  ' "$path" >/dev/null
}
paired_commit_visible=false
phone_encoded=${phone_track//:/%3A}
wear_encoded=${wear_track//:/%3A}
for _ in $(seq 1 20); do
  if curl --fail-with-body --retry 2 --retry-all-errors --max-time 30 -sS "${auth[@]}" \
      "$api/tracks/$phone_encoded/releases" -o "$work/phone-track-after.json" \
    && curl --fail-with-body --retry 2 --retry-all-errors --max-time 30 -sS "${auth[@]}" \
      "$api/tracks/$wear_encoded/releases" -o "$work/wear-track-after.json" \
    && track_contains_code "$work/phone-track-after.json" "$phone_code" \
    && track_contains_code "$work/wear-track-after.json" "$wear_code"; then
    paired_commit_visible=true
    break
  fi
  sleep 5
done
$paired_commit_visible || fail 'paired Play commit response/postcondition is absent; edit was not proven committed'
committed=true
printf 'Uploaded phone %s to %s and Wear %s to %s in one Play edit (commit response received: %s).\n' \
  "$phone_code" "$phone_track" "$wear_code" "$wear_track" "$commit_response_received"
