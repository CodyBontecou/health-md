#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
fail() { printf 'Wear screenshot upload: %s\n' "$*" >&2; exit 1; }

key=${PLAY_CONSOLE_KEY_PATH:-}
package=${PLAY_PACKAGE_NAME:-com.healthmd.android}
language=${WEAR_SCREENSHOT_LANGUAGE:-en-US}
image_type=wearScreenshots
confirmation=${CONFIRM_WEAR_SCREENSHOT_REPLACEMENT:-}
expected_wear_apk=${EXPECTED_WEAR_APK_SHA256:-}
expected_play_signer=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
expected_reviewer=${EXPECTED_SCREENSHOT_REVIEWER:-}
expected_review_ticket=${EXPECTED_SCREENSHOT_REVIEW_TICKET:-}
evidence_root=${WEAR_SCREENSHOT_EVIDENCE_ROOT:-$(git rev-parse --show-toplevel)/.pi/evidence/wear-play-screenshots}
upload_evidence_root=${WEAR_SCREENSHOT_UPLOAD_EVIDENCE_ROOT:-$(git rev-parse --show-toplevel)/.pi/evidence/wear-play-screenshot-upload}
version_name=$(sed -n 's/^[[:space:]]*versionName = "\([^"]*\)".*/\1/p' app/build.gradle.kts | head -1)
phone_version_code=$(sed -n 's/^[[:space:]]*versionCode = \([0-9][0-9]*\).*/\1/p' app/build.gradle.kts | head -1)
wear_version_code=$(sed -n 's/^[[:space:]]*versionCode = \([0-9][0-9_]*\).*/\1/p' wear/build.gradle.kts | head -1 | tr -d '_')
[[ "$version_name" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ && "$phone_version_code" =~ ^[1-9][0-9]*$ && "$wear_version_code" =~ ^[1-9][0-9]*$ ]] \
  || fail 'unable to derive exact Wear version identity from Gradle'
expected_confirmation="$package:$language:$image_type:$expected_wear_apk:$expected_play_signer"
screenshots=(
  play-store/wear/screenshots/wear-app.png
  play-store/wear/screenshots/wear-tile.png
)

[[ -n "$key" && -r "$key" ]] || fail 'PLAY_CONSOLE_KEY_PATH must name a readable service-account JSON file'
[[ "$language" == en-US && "$image_type" == wearScreenshots ]] \
  || fail 'protected Wear screenshot publication is restricted to en-US wearScreenshots'
[[ "$expected_wear_apk" =~ ^[0-9a-f]{64}$ && "$expected_play_signer" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'set lowercase EXPECTED_WEAR_APK_SHA256 and EXPECTED_PLAY_APP_SIGNING_CERT_SHA256'
[[ -n "$expected_reviewer" && -n "$expected_review_ticket" ]] \
  || fail 'EXPECTED_SCREENSHOT_REVIEWER and EXPECTED_SCREENSHOT_REVIEW_TICKET are protected required inputs'
[[ ! -e "$upload_evidence_root" ]] || fail "refusing to overwrite screenshot upload evidence: $upload_evidence_root"
[[ "$confirmation" == "$expected_confirmation" ]] || fail "set CONFIRM_WEAR_SCREENSHOT_REPLACEMENT=$expected_confirmation"
python3 ./scripts/validate-wear-play-assets.py >/dev/null
play_evidence=${WEAR_PLAY_EVIDENCE_RECEIPT:-$(git rev-parse --show-toplevel)/.pi/evidence/wear-play/play-app-signing.json}
EXPECTED_PHONE_VERSION_CODE="$phone_version_code" EXPECTED_WEAR_VERSION_CODE="$wear_version_code" \
EXPECTED_VERSION_NAME="$version_name" EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$expected_play_signer" \
  ./scripts/verify-google-play-generated-apk-evidence.sh "$play_evidence" >/dev/null
play_wear_apk=$(jq -er .wear.apkSha256 "$play_evidence")
[[ "$expected_wear_apk" == "$play_wear_apk" ]] \
  || fail 'EXPECTED_WEAR_APK_SHA256 differs from the retained Play-generated base-master Wear APK'
python3 ./scripts/verify-wear-play-screenshot-evidence.py \
  --evidence "$evidence_root" \
  --wear-apk-sha256 "$expected_wear_apk" \
  --play-signer-sha256 "$expected_play_signer" \
  --wear-version-code "$wear_version_code" --version-name "$version_name" \
  --expected-reviewer "$expected_reviewer" --expected-review-ticket "$expected_review_ticket" >/dev/null
for path in "${screenshots[@]}"; do [[ -f "$path" ]] || fail "missing $path"; done

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s)
header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)
claims=$(jq -nc \
  --arg iss "$(jq -er .client_email "$key")" \
  --arg aud "$(jq -er .token_uri "$key")" \
  --argjson iat "$now" \
  '{iss:$iss,scope:"https://www.googleapis.com/auth/androidpublisher",aud:$aud,iat:$iat,exp:($iat+1200)}' | base64url)
signature=$(printf '%s' "$header.$claims" | openssl dgst -sha256 -sign <(jq -r .private_key "$key") | base64url)
token=$(curl -fsS --retry 3 --retry-all-errors \
  --data-urlencode "assertion=$header.$claims.$signature" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  "$(jq -er .token_uri "$key")" | jq -er .access_token)
auth=(-H "Authorization: Bearer $token")
api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package"
upload_api="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package"
edit_id=''
verification_edit_id=''
committed=false
evidence_stage=''
cleanup() {
  if [[ -n "$edit_id" && "$committed" != true ]]; then
    curl -fsS --retry 2 -X DELETE "${auth[@]}" "$api/edits/$edit_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$verification_edit_id" ]]; then
    curl -fsS --retry 2 -X DELETE "${auth[@]}" "$api/edits/$verification_edit_id" >/dev/null 2>&1 || true
  fi
  [[ -z "$evidence_stage" ]] || rm -rf "$evidence_stage"
}
trap cleanup EXIT

edit_id=$(curl -fsS --retry 3 --retry-all-errors -X POST "${auth[@]}" \
  -H 'Content-Type: application/json' -d '{}' "$api/edits" | jq -er .id)
precommit_listing=$(curl -fsS --retry 3 --retry-all-errors "${auth[@]}" \
  "$api/edits/$edit_id/listings/$language/$image_type")
app_sha=$(shasum -a 256 "${screenshots[0]}" | awk '{print $1}')
tile_sha=$(shasum -a 256 "${screenshots[1]}" | awk '{print $1}')
precommit_already_matched=false
if jq -e --arg app "$app_sha" --arg tile "$tile_sha" '
  ([.images[]?.sha256 | ascii_downcase] | sort) == ([$app,$tile] | sort) and
  ([.images[]?] | length) == 2
' <<<"$precommit_listing" >/dev/null; then
  precommit_already_matched=true
fi

# Replace the Wear screenshot set atomically inside one Play edit. Deleting first is safe because
# the edit is abandoned automatically unless every upload, digest check, and commit succeeds.
curl -fsS --retry 3 --retry-all-errors -X DELETE "${auth[@]}" \
  "$api/edits/$edit_id/listings/$language/$image_type" >/dev/null
for path in "${screenshots[@]}"; do
  response=$(curl -fsS --retry 3 --retry-all-errors -X POST "${auth[@]}" \
    -H 'Content-Type: image/png' --data-binary "@$path" \
    "$upload_api/edits/$edit_id/listings/$language/$image_type?uploadType=media")
  remote_sha=$(printf '%s' "$response" | jq -er .image.sha256 | tr '[:upper:]' '[:lower:]')
  local_sha=$(shasum -a 256 "$path" | awk '{print $1}')
  [[ "$remote_sha" == "$local_sha" ]] || fail "Play digest mismatch for $path"
done

listed=$(curl -fsS --retry 3 --retry-all-errors "${auth[@]}" \
  "$api/edits/$edit_id/listings/$language/$image_type")
for path in "${screenshots[@]}"; do
  local_sha=$(shasum -a 256 "$path" | awk '{print $1}')
  jq -e --arg digest "$local_sha" \
    '[.images[]?.sha256 | ascii_downcase] | index($digest) != null' \
    <<<"$listed" >/dev/null || fail "Play edit does not list $path by digest"
done
[[ $(jq '.images | length' <<<"$listed") -eq ${#screenshots[@]} ]] || fail 'Play edit has an unexpected Wear screenshot count'

committed_edit_id=$edit_id
commit_response_received=true
commit_response='null'
commit_exit_code=0
# The edit commit is non-idempotent. Issue it once, then inspect committed state through a fresh,
# disposable edit only for an ambiguous transport failure. A definite HTTP rejection cannot be
# relabeled success, and an already-matching precondition cannot prove that this edit committed.
set +e
response=$(curl -sS --fail-with-body -X POST "${auth[@]}" \
  "$api/edits/$edit_id:commit?changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW")
commit_exit_code=$?
set -e
if [[ $commit_exit_code -eq 0 ]]; then
  printf '%s' "$response" | jq -e --arg edit "$committed_edit_id" \
    'type == "object" and .id == $edit' >/dev/null \
    || fail 'Play screenshot commit response is not the expected edit object'
  commit_response=$response
elif [[ $commit_exit_code -eq 22 ]]; then
  fail 'Play screenshot commit received a definite HTTP rejection; reconciliation is forbidden'
else
  commit_response_received=false
  [[ "$precommit_already_matched" == false ]] \
    || fail 'ambiguous Play screenshot commit cannot be attributed because committed state already matched before mutation'
fi
verification_edit_id=$(curl -fsS --retry 3 --retry-all-errors -X POST "${auth[@]}" \
  -H 'Content-Type: application/json' -d '{}' "$api/edits" | jq -er .id)
committed_listing=$(curl -fsS --retry 3 --retry-all-errors "${auth[@]}" \
  "$api/edits/$verification_edit_id/listings/$language/$image_type")
for path in "${screenshots[@]}"; do
  local_sha=$(shasum -a 256 "$path" | awk '{print $1}')
  jq -e --arg digest "$local_sha" \
    '[.images[]?.sha256 | ascii_downcase] | index($digest) != null' \
    <<<"$committed_listing" >/dev/null || fail "committed Play state does not list $path by digest"
done
[[ $(jq '.images | length' <<<"$committed_listing") -eq ${#screenshots[@]} ]] \
  || fail 'committed Play state has an unexpected Wear screenshot count'
curl -fsS --retry 2 -X DELETE "${auth[@]}" "$api/edits/$verification_edit_id" >/dev/null
verification_edit_id=''
committed=true
edit_id=''

# Retain a non-overwritable, checksum-covered receipt that binds the committed metadata edit to the
# exact Play-generated Wear APK, protected visual reviewer/ticket, and approved local/remote hashes.
mkdir -p "$(dirname "$upload_evidence_root")"
evidence_stage=$(mktemp -d "$(dirname "$upload_evidence_root")/.wear-screenshot-upload.XXXXXX")
printf '%s\n' "$precommit_listing" | jq . >"$evidence_stage/pre-commit-listing.json"
printf '%s\n' "$committed_listing" | jq . >"$evidence_stage/remote-listing.json"
jq -n --arg edit "$committed_edit_id" --arg responseReceived "$commit_response_received" \
  --arg preMatched "$precommit_already_matched" --argjson exitCode "$commit_exit_code" \
  --argjson response "$commit_response" '{
    editId:$edit, responseReceived:($responseReceived == "true"),
    preCommitAlreadyMatched:($preMatched == "true"), commitExitCode:$exitCode,
    reconciledAgainstCommittedListing:true, response:$response
  }' >"$evidence_stage/commit-response.json"
jq -n \
  --arg package "$package" --arg version "$version_name" \
  --argjson phone "$phone_version_code" --argjson wear "$wear_version_code" \
  --arg wearApk "$expected_wear_apk" --arg signer "$expected_play_signer" \
  --arg language "$language" --arg imageType "$image_type" \
  --arg reviewer "$expected_reviewer" --arg ticket "$expected_review_ticket" \
  --arg edit "$committed_edit_id" --arg commitResponse "$commit_response_received" \
  --arg preMatched "$precommit_already_matched" \
  --arg committedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg appSha "$app_sha" --arg tileSha "$tile_sha" '{
    schemaVersion:1, package:$package, versionName:$version,
    phoneVersionCode:$phone, wearVersionCode:$wear,
    wearApkSha256:$wearApk, playAppSigningCertSha256:$signer,
    language:$language, imageType:$imageType,
    reviewer:$reviewer, reviewTicket:$ticket,
    playEditId:$edit, commitResponseReceived:($commitResponse == "true"),
    preCommitAlreadyMatched:($preMatched == "true"),
    committed:true, committedAtUtc:$committedAt,
    images:[
      {fileName:"wear-app.png",sha256:$appSha},
      {fileName:"wear-tile.png",sha256:$tileSha}
    ]
  }' >"$evidence_stage/receipt.json"
(
  cd "$evidence_stage"
  shasum -a 256 commit-response.json pre-commit-listing.json receipt.json remote-listing.json >SHA256SUMS
)
python3 ./scripts/verify-wear-play-screenshot-upload-evidence.py "$evidence_stage" \
  --assets play-store/wear/screenshots \
  --wear-apk-sha256 "$expected_wear_apk" --play-signer-sha256 "$expected_play_signer" \
  --version-name "$version_name" --phone-version-code "$phone_version_code" \
  --wear-version-code "$wear_version_code" --expected-reviewer "$expected_reviewer" \
  --expected-review-ticket "$expected_review_ticket" >/dev/null
mv "$evidence_stage" "$upload_evidence_root"
evidence_stage=''
printf 'Uploaded and verified %d Wear screenshots for %s (%s); receipt: %s\n' \
  "${#screenshots[@]}" "$package" "$language" "$upload_evidence_root"
