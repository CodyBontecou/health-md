#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
key=${PLAY_CONSOLE_KEY_PATH:-}
package=${PLAY_PACKAGE_NAME:-com.healthmd.android}
expected_play_signer=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
output=${1:-$(git rev-parse --show-toplevel)/.pi/evidence/wear-play/play-app-signing.json}
evidence_dir=$(dirname "$output")
phone_apk="$evidence_dir/phone-generated.apk"
wear_apk="$evidence_dir/wear-generated.apk"
phone_list="$evidence_dir/phone-generated-apks.json"
wear_list="$evidence_dir/wear-generated-apks.json"
sums="$evidence_dir/play-app-signing-SHA256SUMS"
phone_code=${EXPECTED_PHONE_VERSION_CODE:-}
wear_code=${EXPECTED_WEAR_VERSION_CODE:-}
version_name=${EXPECTED_VERSION_NAME:-}

fail() { printf 'Play generated APK evidence: %s\n' "$*" >&2; exit 1; }
[[ -n "$key" && -r "$key" ]] || fail 'PLAY_CONSOLE_KEY_PATH must name a readable service-account JSON file'
[[ "$expected_play_signer" =~ ^[0-9a-f]{64}$ ]] || fail 'set lowercase EXPECTED_PLAY_APP_SIGNING_CERT_SHA256 from an independently authorized source'
[[ "$phone_code" =~ ^[0-9]+$ && "$phone_code" -lt 1000000 ]] || fail 'set valid EXPECTED_PHONE_VERSION_CODE'
[[ "$wear_code" =~ ^[0-9]+$ && "$wear_code" -ge 1000000 ]] || fail 'set valid EXPECTED_WEAR_VERSION_CODE'
[[ "$version_name" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'set valid EXPECTED_VERSION_NAME'
for target in "$output" "$phone_apk" "$wear_apk" "$phone_list" "$wear_list" "$sums"; do
  [[ ! -e "$target" ]] || fail "refusing to overwrite $target"
done
for command in curl jq openssl shasum unzip; do command -v "$command" >/dev/null || fail "$command is required"; done
apksigner=${APKSIGNER:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/apksigner}
aapt=${AAPT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/aapt}
[[ -x "$apksigner" && -x "$aapt" ]] || fail 'Android build-tools 35.0.0 apksigner/aapt are required'

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
private_key=$(mktemp); work=$(mktemp -d)
trap 'rm -f "$private_key"; rm -rf "$work"' EXIT
jq -er .private_key "$key" >"$private_key"; chmod 600 "$private_key"
now=$(date +%s)
header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)
claims=$(jq -nc --arg iss "$(jq -er .client_email "$key")" --arg aud "$(jq -er .token_uri "$key")" --argjson iat "$now" \
  '{iss:$iss,scope:"https://www.googleapis.com/auth/androidpublisher",aud:$aud,iat:$iat,exp:($iat+1200)}' | base64url)
signature=$(printf '%s' "$header.$claims" | openssl dgst -sha256 -sign "$private_key" | base64url)
token=$(curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS \
  --data-urlencode "assertion=$header.$claims.$signature" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  "$(jq -er .token_uri "$key")" | jq -er .access_token)
api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package/generatedApks"
auth=(-H "Authorization: Bearer $token")

capture_one() {
  local label=$1 code=$2 list="$work/$label-generated-apks.json" apk="$work/$label-generated.apk" download cert apk_sha signer
  curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS "${auth[@]}" "$api/$code" >"$list"
  cert=$(jq -er --arg expected "$expected_play_signer" '
    first(.generatedApks[]? | select((.certificateSha256Hash | ascii_downcase) == $expected)).certificateSha256Hash
  ' "$list" | tr '[:upper:]' '[:lower:]')
  [[ "$cert" == "$expected_play_signer" ]] || fail "$label generated APK group does not match authorized Play signer"
  # Select the base module master split (`splitId` empty): this is the exact installed base.apk
  # identity used by physical checkpoint and screenshot capture. Universal/standalone hashes are
  # not interchangeable with split-delivered base.apk and must never be used for that binding.
  download=$(jq -er --arg expected "$expected_play_signer" '
    first(
      .generatedApks[]? |
      select((.certificateSha256Hash | ascii_downcase) == $expected) |
      (.generatedSplitApks[]? | select(.moduleName == "base" and .splitId == "")) |
      select(.downloadId? != null)
    ).downloadId
  ' "$list") || fail "$label has no base-master generated APK download"
  curl --fail-with-body --retry 3 --retry-all-errors --max-time 300 -sS "${auth[@]}" \
    "$api/$code/downloads/$download:download" -o "$apk"
  unzip -tqq "$apk" || fail "$label generated APK is not a valid APK ZIP"
  "$aapt" dump badging "$apk" | grep -q "package: name='$package'.*versionCode='$code'.*versionName='$version_name'" \
    || fail "$label downloaded APK package/version identity differs"
  apk_sha=$(shasum -a 256 "$apk" | awk '{print $1}')
  signer=$("$apksigner" verify --print-certs "$apk" \
    | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1 | tr '[:upper:]' '[:lower:]')
  [[ "$signer" == "$expected_play_signer" ]] || fail "$label downloaded APK signer differs from authorized Play identity"
  jq -n --argjson versionCode "$code" --arg versionName "$version_name" --arg apkSha256 "$apk_sha" --arg certSha256 "$signer" \
    --arg downloadId "$download" '{versionCode:$versionCode,versionName:$versionName,apkSha256:$apkSha256,certSha256:$certSha256,downloadId:$downloadId}' \
    >"$work/$label-result.json"
}

capture_one phone "$phone_code"
capture_one wear "$wear_code"
mkdir -p "$evidence_dir"
jq -n --arg package "$package" --arg captured "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg expected "$expected_play_signer" --slurpfile phone "$work/phone-result.json" --slurpfile wear "$work/wear-result.json" \
  '{schemaVersion:1,capturedAtUtc:$captured,package:$package,expectedPlayAppSigningCertSha256:$expected,phone:$phone[0],wear:$wear[0]}' \
  >"$work/play-app-signing.json"
# Retain the exact downloaded bytes and raw read-only inventory needed to independently re-verify
# the receipt. No credential or OAuth token is copied into evidence.
cp "$work/phone-generated.apk" "$work/retained-phone-generated.apk"
cp "$work/wear-generated.apk" "$work/retained-wear-generated.apk"
cp "$work/phone-generated-apks.json" "$work/retained-phone-generated-apks.json"
cp "$work/wear-generated-apks.json" "$work/retained-wear-generated-apks.json"
(
  cd "$work"
  shasum -a 256 \
    play-app-signing.json \
    retained-phone-generated.apk \
    retained-wear-generated.apk \
    retained-phone-generated-apks.json \
    retained-wear-generated-apks.json \
  | sed \
      -e 's/retained-phone-generated\.apk/phone-generated.apk/' \
      -e 's/retained-wear-generated\.apk/wear-generated.apk/' \
      -e 's/retained-phone-generated-apks\.json/phone-generated-apks.json/' \
      -e 's/retained-wear-generated-apks\.json/wear-generated-apks.json/' \
  >play-app-signing-SHA256SUMS
)
mv "$work/retained-phone-generated.apk" "$phone_apk"
mv "$work/retained-wear-generated.apk" "$wear_apk"
mv "$work/retained-phone-generated-apks.json" "$phone_list"
mv "$work/retained-wear-generated-apks.json" "$wear_list"
mv "$work/play-app-signing-SHA256SUMS" "$sums"
mv "$work/play-app-signing.json" "$output"
EXPECTED_PHONE_VERSION_CODE="$phone_code" EXPECTED_WEAR_VERSION_CODE="$wear_code" \
EXPECTED_VERSION_NAME="$version_name" EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$expected_play_signer" \
  ./scripts/verify-google-play-generated-apk-evidence.sh "$output" >/dev/null
printf 'Captured and independently re-verified exact Play-generated APK evidence: %s\n' "$output"
