#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
verifier=./scripts/verify-google-play-generated-apk-evidence.sh
phone_source=app/build/outputs/apk/debug/app-debug.apk
wear_source=wear/build/outputs/apk/debug/wear-debug.apk
[[ -f "$phone_source" && -f "$wear_source" ]] || {
  echo 'Build :app:assembleDebug :wear:assembleDebug before this test' >&2; exit 1;
}
apksigner=${APKSIGNER:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/apksigner}
signer=$("$apksigner" verify --print-certs "$wear_source" \
  | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1 | tr '[:upper:]' '[:lower:]')
[[ "$signer" =~ ^[0-9a-f]{64}$ ]] || exit 1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/evidence"
mkdir -p "$fixture"
cp "$phone_source" "$fixture/phone-generated.apk"
cp "$wear_source" "$fixture/wear-generated.apk"
printf '{"generatedApks":[{"certificateSha256Hash":"%s","generatedSplitApks":[{"downloadId":"phone-id","moduleName":"base","splitId":""}]}]}\n' "$signer" >"$fixture/phone-generated-apks.json"
printf '{"generatedApks":[{"certificateSha256Hash":"%s","generatedSplitApks":[{"downloadId":"wear-id","moduleName":"base","splitId":""}]}]}\n' "$signer" >"$fixture/wear-generated-apks.json"
phone_sha=$(shasum -a 256 "$phone_source" | awk '{print $1}')
wear_sha=$(shasum -a 256 "$wear_source" | awk '{print $1}')
jq -n --arg signer "$signer" --arg phone "$phone_sha" --arg wear "$wear_sha" '{
  schemaVersion:1,capturedAtUtc:"2026-08-13T00:00:00Z",package:"com.healthmd.android",
  expectedPlayAppSigningCertSha256:$signer,
  phone:{versionCode:29,versionName:"1.8.0",apkSha256:$phone,certSha256:$signer,downloadId:"phone-id"},
  wear:{versionCode:1000029,versionName:"1.8.0",apkSha256:$wear,certSha256:$signer,downloadId:"wear-id"}
}' >"$fixture/play-app-signing.json"
checksums() {
  (cd "$fixture" && shasum -a 256 \
    play-app-signing.json phone-generated.apk wear-generated.apk \
    phone-generated-apks.json wear-generated-apks.json >play-app-signing-SHA256SUMS)
}
checksums
EXPECTED_PHONE_VERSION_CODE=29 EXPECTED_WEAR_VERSION_CODE=1000029 \
  EXPECTED_VERSION_NAME=1.8.0 EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$signer" \
  "$verifier" "$fixture/play-app-signing.json" >/dev/null

expect_failure() {
  local name=$1 expected=$2; shift 2
  rm -rf "$fixture"; mkdir -p "$fixture"
  cp "$tmp/pristine/"* "$fixture/"
  "$@"
  checksums
  if EXPECTED_PHONE_VERSION_CODE=29 EXPECTED_WEAR_VERSION_CODE=1000029 \
    EXPECTED_VERSION_NAME=1.8.0 EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$signer" \
    "$verifier" "$fixture/play-app-signing.json" >"$tmp/out" 2>"$tmp/err"; then
    echo "negative generated-APK fixture unexpectedly passed: $name" >&2; exit 1
  fi
  grep -q "$expected" "$tmp/err" || { cat "$tmp/err" >&2; exit 1; }
}
mkdir "$tmp/pristine"; cp "$fixture/"* "$tmp/pristine/"
wrong_phone_code() { jq '.phone.versionCode=30' "$fixture/play-app-signing.json" >"$tmp/j"; mv "$tmp/j" "$fixture/play-app-signing.json"; }
wrong_version_name() { jq '.wear.versionName="1.7.2"' "$fixture/play-app-signing.json" >"$tmp/j"; mv "$tmp/j" "$fixture/play-app-signing.json"; }
tamper_phone() { printf x >>"$fixture/phone-generated.apk"; }
wrong_inventory() { jq '.generatedApks[0].certificateSha256Hash=("f"*64)' "$fixture/wear-generated-apks.json" >"$tmp/j"; mv "$tmp/j" "$fixture/wear-generated-apks.json"; }
wrong_download() { jq '.wear.downloadId="other"' "$fixture/play-app-signing.json" >"$tmp/j"; mv "$tmp/j" "$fixture/play-app-signing.json"; }
wrong_apk_class() { jq '.generatedApks[0] |= (del(.generatedSplitApks) | .generatedUniversalApk={downloadId:"wear-id"})' "$fixture/wear-generated-apks.json" >"$tmp/j"; mv "$tmp/j" "$fixture/wear-generated-apks.json"; }
wrong_independent_signer() { :; }
expect_failure wrong-code 'phone receipt versionCode differs' wrong_phone_code
expect_failure wrong-name 'wear receipt versionName differs' wrong_version_name
expect_failure tampered-apk 'phone APK digest differs from receipt' tamper_phone
expect_failure wrong-inventory 'wear raw inventory lacks authorized signing-key group' wrong_inventory
expect_failure wrong-download 'wear receipt downloadId absent' wrong_download
expect_failure wrong-apk-class 'wear receipt downloadId absent' wrong_apk_class
if EXPECTED_PHONE_VERSION_CODE=29 EXPECTED_WEAR_VERSION_CODE=1000029 \
  EXPECTED_VERSION_NAME=1.8.0 EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$(printf 'f%.0s' {1..64})" \
  "$verifier" "$tmp/pristine/play-app-signing.json" >"$tmp/out" 2>"$tmp/err"; then
  echo 'wrong independently supplied signer unexpectedly passed' >&2; exit 1
fi
grep -q 'receipt signer differs from independently supplied signer' "$tmp/err"

echo 'Google Play generated APK retained-evidence positive/negative tests passed'
