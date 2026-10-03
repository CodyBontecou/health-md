#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
verifier=./scripts/verify-google-play-generated-apk-evidence.sh
phone_source=app/build/outputs/apk/play/debug/app-play-debug.apk
wear_source=wear/build/outputs/apk/debug/wear-debug.apk
[[ -f "$phone_source" && -f "$wear_source" ]] || {
  echo 'Build :app:assemblePlayDebug :wear:assembleDebug before this test' >&2; exit 1;
}
build_tools=${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0
apksigner=${APKSIGNER:-$build_tools/apksigner}
aapt=${AAPT:-$build_tools/aapt}
[[ -x "$apksigner" && -x "$aapt" ]] || {
  echo 'Android build-tools 35.0.0 apksigner/aapt are required' >&2; exit 1;
}
signer=$("$apksigner" verify --print-certs "$wear_source" \
  | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1 | tr '[:upper:]' '[:lower:]')
[[ "$signer" =~ ^[0-9a-f]{64}$ ]] || exit 1

apk_identity() {
  local label=$1 apk=$2 badging package code version
  badging=$("$aapt" dump badging "$apk" 2>/dev/null) || {
    echo "Could not inspect $label APK identity" >&2; return 1;
  }
  package=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)
  code=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionCode='\([0-9][0-9]*\)'.*/\1/p" | head -1)
  version=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p" | head -1)
  [[ "$package" == com.healthmd.android && "$code" =~ ^[1-9][0-9]*$ \
    && "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
    echo "Invalid $label APK identity" >&2; return 1;
  }
  printf '%s %s\n' "$code" "$version"
}
# The synthetic fixture follows the APKs built immediately before this test so
# routine release bumps cannot stale it. The production verifier still requires
# independently supplied EXPECTED_* release identity and never derives trust
# from the retained receipt or APK.
read -r phone_code phone_version_name < <(apk_identity phone "$phone_source")
read -r wear_code wear_version_name < <(apk_identity wear "$wear_source")
[[ "$phone_version_name" == "$wear_version_name" ]] || {
  echo 'Phone and Wear APK version names differ' >&2; exit 1;
}
(( phone_code < 1000000 && wear_code >= 1000000 )) || {
  echo 'Phone/Wear APK version codes are outside their reserved ranges' >&2; exit 1;
}
version_name=$phone_version_name
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/evidence"
mkdir -p "$fixture"
cp "$phone_source" "$fixture/phone-generated.apk"
cp "$wear_source" "$fixture/wear-generated.apk"
printf '{"generatedApks":[{"certificateSha256Hash":"%s","generatedSplitApks":[{"downloadId":"phone-id","moduleName":"base","splitId":""}]}]}\n' "$signer" >"$fixture/phone-generated-apks.json"
printf '{"generatedApks":[{"certificateSha256Hash":"%s","generatedSplitApks":[{"downloadId":"wear-id","moduleName":"base","splitId":""}]}]}\n' "$signer" >"$fixture/wear-generated-apks.json"
phone_sha=$(shasum -a 256 "$phone_source" | awk '{print $1}')
wear_sha=$(shasum -a 256 "$wear_source" | awk '{print $1}')
jq -n --arg signer "$signer" --arg phone "$phone_sha" --arg wear "$wear_sha" \
  --argjson phone_code "$phone_code" --argjson wear_code "$wear_code" \
  --arg version_name "$version_name" '{
  schemaVersion:1,capturedAtUtc:"2026-08-13T00:00:00Z",package:"com.healthmd.android",
  expectedPlayAppSigningCertSha256:$signer,
  phone:{versionCode:$phone_code,versionName:$version_name,apkSha256:$phone,certSha256:$signer,downloadId:"phone-id"},
  wear:{versionCode:$wear_code,versionName:$version_name,apkSha256:$wear,certSha256:$signer,downloadId:"wear-id"}
}' >"$fixture/play-app-signing.json"
checksums() {
  (cd "$fixture" && shasum -a 256 \
    play-app-signing.json phone-generated.apk wear-generated.apk \
    phone-generated-apks.json wear-generated-apks.json >play-app-signing-SHA256SUMS)
}
checksums
EXPECTED_PHONE_VERSION_CODE="$phone_code" EXPECTED_WEAR_VERSION_CODE="$wear_code" \
  EXPECTED_VERSION_NAME="$version_name" EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$signer" \
  "$verifier" "$fixture/play-app-signing.json" >/dev/null

expect_failure() {
  local name=$1 expected=$2; shift 2
  rm -rf "$fixture"; mkdir -p "$fixture"
  cp "$tmp/pristine/"* "$fixture/"
  "$@"
  checksums
  if EXPECTED_PHONE_VERSION_CODE="$phone_code" EXPECTED_WEAR_VERSION_CODE="$wear_code" \
    EXPECTED_VERSION_NAME="$version_name" EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$signer" \
    "$verifier" "$fixture/play-app-signing.json" >"$tmp/out" 2>"$tmp/err"; then
    echo "negative generated-APK fixture unexpectedly passed: $name" >&2; exit 1
  fi
  grep -q "$expected" "$tmp/err" || { cat "$tmp/err" >&2; exit 1; }
}
mkdir "$tmp/pristine"; cp "$fixture/"* "$tmp/pristine/"
wrong_phone_code() { jq --argjson code "$((phone_code + 1))" '.phone.versionCode=$code' "$fixture/play-app-signing.json" >"$tmp/j"; mv "$tmp/j" "$fixture/play-app-signing.json"; }
wrong_version_name() { jq '.wear.versionName="invalid"' "$fixture/play-app-signing.json" >"$tmp/j"; mv "$tmp/j" "$fixture/play-app-signing.json"; }
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

# Bind receipt and independent expectation to the same wrong code so this case
# reaches the retained APK boundary rather than failing the earlier receipt check.
rm -rf "$fixture"; mkdir -p "$fixture"
cp "$tmp/pristine/"* "$fixture/"
wrong_packaged_phone_code=$((phone_code + 1))
jq --argjson code "$wrong_packaged_phone_code" '.phone.versionCode=$code' \
  "$fixture/play-app-signing.json" >"$tmp/j"
mv "$tmp/j" "$fixture/play-app-signing.json"
checksums
if EXPECTED_PHONE_VERSION_CODE="$wrong_packaged_phone_code" EXPECTED_WEAR_VERSION_CODE="$wear_code" \
  EXPECTED_VERSION_NAME="$version_name" EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$signer" \
  "$verifier" "$fixture/play-app-signing.json" >"$tmp/out" 2>"$tmp/err"; then
  echo 'wrong packaged phone identity unexpectedly passed' >&2; exit 1
fi
grep -q 'phone package/version differs' "$tmp/err" || { cat "$tmp/err" >&2; exit 1; }

if EXPECTED_PHONE_VERSION_CODE="$phone_code" EXPECTED_WEAR_VERSION_CODE="$wear_code" \
  EXPECTED_VERSION_NAME="$version_name" EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$(printf 'f%.0s' {1..64})" \
  "$verifier" "$tmp/pristine/play-app-signing.json" >"$tmp/out" 2>"$tmp/err"; then
  echo 'wrong independently supplied signer unexpectedly passed' >&2; exit 1
fi
grep -q 'receipt signer differs from independently supplied signer' "$tmp/err"

echo 'Google Play generated APK retained-evidence positive/negative tests passed'
