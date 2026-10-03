#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
receipt=${1:-$(git rev-parse --show-toplevel)/.pi/evidence/wear-play/play-app-signing.json}
expected_phone_code=${EXPECTED_PHONE_VERSION_CODE:-}
expected_wear_code=${EXPECTED_WEAR_VERSION_CODE:-}
expected_version_name=${EXPECTED_VERSION_NAME:-}
[[ "$expected_phone_code" =~ ^[1-9][0-9]*$ && "$expected_wear_code" =~ ^[1-9][0-9]*$ ]] || {
  echo 'EXPECTED_PHONE_VERSION_CODE and EXPECTED_WEAR_VERSION_CODE are required positive integers' >&2; exit 64;
}
(( expected_phone_code < 1000000 && expected_wear_code >= 1000000 )) || {
  echo 'expected phone/Wear codes are outside their reserved ranges' >&2; exit 64;
}
[[ "$expected_version_name" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo 'EXPECTED_VERSION_NAME must be a semantic version' >&2; exit 64;
}
dir=$(dirname "$receipt")
phone_apk="$dir/phone-generated.apk"
wear_apk="$dir/wear-generated.apk"
phone_list="$dir/phone-generated-apks.json"
wear_list="$dir/wear-generated-apks.json"
sums="$dir/play-app-signing-SHA256SUMS"
fail() { printf 'Play generated APK evidence verification: %s\n' "$*" >&2; exit 1; }
for path in "$receipt" "$phone_apk" "$wear_apk" "$phone_list" "$wear_list" "$sums"; do
  [[ -f "$path" ]] || fail "missing $path"
done
apksigner=${APKSIGNER:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/apksigner}
aapt=${AAPT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/aapt}
[[ -x "$apksigner" && -x "$aapt" ]] || fail 'Android build-tools 35.0.0 apksigner/aapt are required'
(
  cd "$dir"
  shasum -a 256 -c "$(basename "$sums")" >/dev/null
) || fail 'checksum coverage or content mismatch'
[[ $(wc -l <"$sums" | tr -d ' ') == 5 ]] || fail 'checksum file must cover exactly five evidence files'
expected_names=$(printf '%s\n' \
  play-app-signing.json phone-generated.apk wear-generated.apk \
  phone-generated-apks.json wear-generated-apks.json | LC_ALL=C sort)
actual_names=$(awk '{print $2}' "$sums" | sed 's/^\*//' | LC_ALL=C sort)
[[ "$actual_names" == "$expected_names" ]] || fail 'checksum file names differ from exact evidence inventory'

[[ $(jq -r .schemaVersion "$receipt") == 1 ]] || fail 'unsupported receipt schema'
[[ $(jq -r .package "$receipt") == com.healthmd.android ]] || fail 'wrong package'
expected=$(jq -er .expectedPlayAppSigningCertSha256 "$receipt")
independent_expected=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
[[ "$independent_expected" =~ ^[0-9a-f]{64}$ ]] || fail 'independently supplied EXPECTED_PLAY_APP_SIGNING_CERT_SHA256 is required'
[[ "$expected" == "$independent_expected" ]] || fail 'receipt signer differs from independently supplied signer'
verify_one() {
  local label=$1 code=$2 apk=$3 list=$4 recorded_code recorded_sha recorded_signer actual_sha actual_signer inventory_count
  recorded_code=$(jq -er ".${label}.versionCode" "$receipt")
  [[ "$recorded_code" == "$code" ]] || fail "$label receipt versionCode differs"
  [[ $(jq -er ".${label}.versionName" "$receipt") == "$expected_version_name" ]] \
    || fail "$label receipt versionName differs"
  recorded_sha=$(jq -er ".${label}.apkSha256" "$receipt")
  recorded_signer=$(jq -er ".${label}.certSha256" "$receipt")
  actual_sha=$(shasum -a 256 "$apk" | awk '{print $1}')
  [[ "$recorded_sha" == "$actual_sha" ]] || fail "$label APK digest differs from receipt"
  "$aapt" dump badging "$apk" | grep -q "package: name='com.healthmd.android'.*versionCode='$code'.*versionName='$expected_version_name'" \
    || fail "$label package/version differs"
  actual_signer=$("$apksigner" verify --print-certs "$apk" \
    | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1 | tr '[:upper:]' '[:lower:]')
  [[ "$actual_signer" == "$expected" && "$recorded_signer" == "$expected" ]] \
    || fail "$label signer differs from independently authorized identity"
  inventory_count=$(jq --arg expected "$expected" '[.generatedApks[]? | select((.certificateSha256Hash | ascii_downcase) == $expected)] | length' "$list")
  [[ "$inventory_count" -ge 1 ]] || fail "$label raw inventory lacks authorized signing-key group"
  download=$(jq -er ".${label}.downloadId" "$receipt")
  jq -e --arg expected "$expected" --arg download "$download" '
    [
      .generatedApks[]? |
      select((.certificateSha256Hash | ascii_downcase) == $expected) |
      .generatedSplitApks[]? |
      select(.moduleName == "base" and .splitId == "" and .downloadId? == $download)
    ] | length > 0
  ' "$list" >/dev/null || fail "$label receipt downloadId absent from raw authorized inventory"
}
verify_one phone "$expected_phone_code" "$phone_apk" "$phone_list"
verify_one wear "$expected_wear_code" "$wear_apk" "$wear_list"
echo 'Play-generated phone/Wear APK evidence is internally valid and independently re-verifiable'
