#!/usr/bin/env bash
set -euo pipefail

fail() { echo "generated APK policy test: $*" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/list.json" <<'JSON'
{
  "generatedApks": [
    {
      "certificateSha256Hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "generatedSplitApks": [{"downloadId":"wrong-signer","moduleName":"base","splitId":""}]
    },
    {
      "certificateSha256Hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "generatedSplitApks": [
        {"downloadId":"config","moduleName":"base","splitId":"config.arm64_v8a"},
        {"downloadId":"base-master","moduleName":"base","splitId":""}
      ]
    }
  ]
}
JSON
expected=a$(printf 'a%.0s' {1..63})
select_download() {
  jq -er --arg expected "$expected" '
    first(
      .generatedApks[]? |
      select((.certificateSha256Hash | ascii_downcase) == $expected) |
      (.generatedSplitApks[]? | select(.moduleName == "base" and .splitId == "")) |
      select(.downloadId? != null)
    ).downloadId
  ' "$1"
}
[[ $(select_download "$tmp/list.json") == base-master ]] || fail 'base master fallback selection'

jq --arg id universal '.generatedApks[1].generatedUniversalApk={downloadId:$id}' "$tmp/list.json" >"$tmp/universal.json"
[[ $(select_download "$tmp/universal.json") == base-master ]] || fail 'universal must not replace base-master binding'
jq --arg id standalone '.generatedApks[1].generatedStandaloneApks=[{downloadId:$id}]' "$tmp/list.json" >"$tmp/standalone.json"
[[ $(select_download "$tmp/standalone.json") == base-master ]] || fail 'standalone must not replace base-master binding'

jq 'del(.generatedApks[1].generatedSplitApks)' "$tmp/list.json" >"$tmp/none.json"
if select_download "$tmp/none.json" >/dev/null 2>&1; then fail 'missing installable/base APK accepted'; fi

script="$(dirname "$0")/../capture-google-play-generated-apk-evidence.sh"
grep -Fq '$api/$code/downloads/$download:download' "$script" || fail 'official download endpoint missing'
grep -q 'apksigner.*verify --print-certs' "$script" || fail 'downloaded APK signer not verified'
grep -Fq "package: name='\$package'.*versionCode='\$code'" "$script" || fail 'downloaded APK identity not verified'
grep -q 'refusing to overwrite' "$script" || fail 'receipt overwrite protection missing'
grep -q 'EXPECTED_PHONE_VERSION_CODE' "$script" || fail 'collector phone code is not supplied by exact release'
grep -q 'EXPECTED_WEAR_VERSION_CODE' "$script" || fail 'collector Wear code is not supplied by exact release'
grep -q 'EXPECTED_VERSION_NAME' "$script" || fail 'collector version name is not supplied by exact release'
grep -q 'verify-google-play-generated-apk-evidence.sh' "$script" || fail 'collector does not independently reverify retained evidence'
verifier="$(dirname "$0")/../verify-google-play-generated-apk-evidence.sh"
grep -q 'play-app-signing-SHA256SUMS' "$verifier" || fail 'retained evidence lacks checksum verification'
grep -q 'apksigner.*verify --print-certs' "$verifier" || fail 'retained APK signer is not independently reverified'
grep -q 'downloadId absent from raw authorized inventory' "$verifier" || fail 'receipt is not rebound to retained raw Play inventory'
grep -q 'EXPECTED_VERSION_NAME' "$verifier" || fail 'retained APK verifier version name is not supplied'
for stale_default in \
  '${EXPECTED_PHONE_VERSION_CODE:-29}' \
  '${EXPECTED_WEAR_VERSION_CODE:-1000029}' \
  '${EXPECTED_VERSION_NAME:-1.8.0}'; do
  if grep -Fq "$stale_default" "$verifier"; then
    fail "retained APK verifier has stale release default: $stale_default"
  fi
done
report="$(dirname "$0")/../report-wear-release-blockers.sh"
grep -q 'verify-google-play-generated-apk-evidence.sh' "$report" || fail 'release blocker report trusts receipt fields without retained-byte verification'
grep -q 'EXPECTED_PHONE_VERSION_CODE="$phone_version_code" EXPECTED_WEAR_VERSION_CODE="$wear_version_code"' "$report" \
  || fail 'release blocker report does not propagate exact future codes to retained APK verification'
readiness="$(dirname "$0")/../inspect-google-play-wear-readiness.sh"
grep -q 'EXPECTED_PHONE_VERSION_CODE' "$readiness" || fail 'Play readiness phone code is hard-coded'
grep -q 'EXPECTED_WEAR_VERSION_CODE' "$readiness" || fail 'Play readiness Wear code is not supplied'
if grep -Fq '${EXPECTED_PHONE_VERSION_CODE:-29}' "$readiness" \
  || grep -Fq '${EXPECTED_WEAR_VERSION_CODE:-1000029}' "$readiness"; then
  fail 'Play readiness retains stale version-code defaults'
fi
for protected_binding in \
  EXPECTED_BATTERY_REVIEWER EXPECTED_BATTERY_REVIEW_TICKET EXPECTED_BATTERY_CONTROL_PROFILE \
  EXPECTED_PAIRED_REVIEWER EXPECTED_PAIRED_REVIEW_TICKET \
  EXPECTED_SCREENSHOT_REVIEWER EXPECTED_SCREENSHOT_REVIEW_TICKET; do
  grep -q "$protected_binding" "$report" \
    || fail "diagnostic blocker report cannot bind protected input: $protected_binding"
done
grep -q 'check-wear-adb-pair-readiness.sh' "$report" \
  || fail 'diagnostic blocker report still counts generic ADB rows as a phone/watch pair'
grep -q 'retained protected paired-QA evidence, not current ADB presence, is the completion gate' "$report" \
  || fail 'diagnostic blocker report mislabels current ADB presence as completion proof'
grep -q 'availability only' "$(dirname "$report")/check-wear-adb-pair-readiness.sh" \
  || fail 'ADB classifier does not identify its output as availability-only'
if grep -Fq 'block "$readiness"' "$report"; then
  fail 'current ADB presence is still treated as completion evidence'
fi
grep -q 'Play exact qa/wear:qa2 pair is currently observable' "$report" \
  || fail 'diagnostic blocker report lost the exact live QA track gate'
grep -q 'signer-bound retained base-master APK evidence remains the completion gate' "$report" \
  || fail 'generated inventory counts are still mislabeled as completion proof'
grep -q 'git ls-remote --exit-code origin refs/heads/main' "$report" \
  || fail 'diagnostic source gate trusts only the local origin/main tracking ref'
grep -q 'git ls-remote --tags origin' "$report" \
  || fail 'diagnostic source gate does not verify the annotated tag on the authoritative remote'
grep -q 'remote_tag_peeled.*current_head' "$report" \
  || fail 'diagnostic source gate does not bind the remote peeled tag to exact HEAD'
grep -q 'fromdateiso8601' "$report" \
  || fail 'diagnostic source review timestamp is not validated as UTC chronology input'

echo 'Google Play generated APK evidence policy tests passed'
