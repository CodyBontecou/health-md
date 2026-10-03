#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: capture-wear-paired-qa-evidence.sh OUTPUT_DIR PHONE_SERIAL WATCH_SERIAL OEM CHECKPOINT
  OEM: pixel | samsung
  CHECKPOINT: installed | synced | offline | reconnected | cleared | rebooted | final

Capture only after manually reaching the named state. Both exact test artifacts must already be
installed. Set EXPECTED_PHONE_APK_SHA256 and EXPECTED_WEAR_APK_SHA256 to the approved exact
installed artifact hashes and EXPECTED_PLAY_APP_SIGNING_CERT_SHA256 to the authorized Play App
Signing identity; set EXPECTED_PHONE_VERSION_CODE, EXPECTED_WEAR_VERSION_CODE, and
EXPECTED_VERSION_NAME to the exact release identity. Omission or signer mismatch is rejected. This script is read-only: it does not install,
pair, refresh, clear, reboot, or alter radios. Set REVIEWER_ID and REVIEW_TICKET to the
independent protected manual QA approval covering the named checkpoint's visible action/result.
EOF
  exit 64
}
[[ $# -eq 5 ]] || usage
out=$1; phone=$2; watch=$3; oem=$4; checkpoint=$5
case "$oem" in pixel|samsung) ;; *) usage ;; esac
case "$checkpoint" in installed|synced|offline|reconnected|cleared|rebooted|final) ;; *) usage ;; esac
if [[ "$out" != /* && "$out" == .pi/* ]]; then out="$(git rev-parse --show-toplevel)/$out"; fi
adb_bin=${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}
[[ -x "$adb_bin" ]] || { echo "adb not found: $adb_bin" >&2; exit 69; }
expected_phone=${EXPECTED_PHONE_APK_SHA256:-}
expected_wear=${EXPECTED_WEAR_APK_SHA256:-}
expected_play_signer=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
expected_phone_code=${EXPECTED_PHONE_VERSION_CODE:-}
expected_wear_code=${EXPECTED_WEAR_VERSION_CODE:-}
expected_version=${EXPECTED_VERSION_NAME:-}
reviewer=${REVIEWER_ID:-}; review_ticket=${REVIEW_TICKET:-}
[[ "$expected_phone" =~ ^[0-9a-f]{64}$ && "$expected_wear" =~ ^[0-9a-f]{64}$ ]] || {
  echo 'Set lowercase EXPECTED_PHONE_APK_SHA256 and EXPECTED_WEAR_APK_SHA256' >&2; exit 64;
}
[[ -n "$reviewer" && -n "$review_ticket" ]] || { echo 'Set REVIEWER_ID and REVIEW_TICKET' >&2; exit 64; }
[[ "$expected_phone_code" =~ ^[1-9][0-9]*$ && "$expected_wear_code" =~ ^[1-9][0-9]*$ && "$expected_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo 'Set EXPECTED_PHONE_VERSION_CODE, EXPECTED_WEAR_VERSION_CODE, and EXPECTED_VERSION_NAME' >&2; exit 64;
}
[[ "$expected_play_signer" =~ ^[0-9a-f]{64}$ ]] || {
  echo 'Set lowercase EXPECTED_PLAY_APP_SIGNING_CERT_SHA256 from authorized Play identity evidence' >&2; exit 64;
}
[[ ! -e "$out" ]] || { echo "Refusing to overwrite existing path $out" >&2; exit 73; }
for serial in "$phone" "$watch"; do
  "$adb_bin" -s "$serial" get-state 2>/dev/null | grep -qx device || { echo "Device not ready: $serial" >&2; exit 69; }
done
mkdir -p "$out/phone" "$out/watch"
package=com.healthmd.android
capture() { local serial=$1; shift; "$adb_bin" -s "$serial" shell "$@" 2>&1 | tr -d '\r'; }
package_field() { capture "$1" dumpsys package "$package" | sed -n "$2" | head -1; }
phone_code=$(package_field "$phone" 's/.*versionCode=\([0-9][0-9]*\).*/\1/p')
watch_code=$(package_field "$watch" 's/.*versionCode=\([0-9][0-9]*\).*/\1/p')
phone_version=$(package_field "$phone" 's/.*versionName=\([^[:space:]]*\).*/\1/p')
watch_version=$(package_field "$watch" 's/.*versionName=\([^[:space:]]*\).*/\1/p')
[[ "$phone_code" == "$expected_phone_code" ]] || { echo "Phone versionCode must be $expected_phone_code; got $phone_code" >&2; exit 65; }
[[ "$watch_code" == "$expected_wear_code" ]] || { echo "Watch versionCode must be $expected_wear_code; got $watch_code" >&2; exit 65; }
[[ "$phone_version" == "$expected_version" && "$watch_version" == "$expected_version" ]] || {
  echo "Phone/Wear versionName must be $expected_version; got $phone_version/$watch_version" >&2; exit 65;
}

# Pull the installed base APKs and bind every checkpoint to their exact bytes and app signer.
# Play-generated split inventory remains captured in package.txt; the base digest is still enough
# to detect an unintended binary swap between checkpoints. Keep serials as function arguments:
# wireless ADB serials contain ':' and must never be parsed as delimiter-joined records.
apksigner=${APKSIGNER:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/apksigner}
[[ -x "$apksigner" ]] || { echo "apksigner unavailable: $apksigner" >&2; exit 69; }
verify_installed() {
  local label=$1 serial=$2 expected=$3 apk_path actual
  apk_path=$(capture "$serial" pm path "$package" | sed -n 's/^package:\(.*\/base\.apk\)$/\1/p' | head -1)
  [[ -n "$apk_path" ]] || { echo "Installed base APK unavailable on $label" >&2; exit 65; }
  "$adb_bin" -s "$serial" pull "$apk_path" "$out/$label/base.apk" >/dev/null
  actual=$(shasum -a 256 "$out/$label/base.apk" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || { echo "$label base APK digest mismatch: $actual" >&2; exit 65; }
  "$apksigner" verify --print-certs "$out/$label/base.apk" >"$out/$label/signer.txt"
  signer=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$out/$label/signer.txt" | head -1 | tr '[:upper:]' '[:lower:]')
  [[ "$signer" == "$expected_play_signer" ]] || {
    echo "$label Play App Signing certificate mismatch: $signer" >&2; exit 65;
  }
}
verify_installed phone "$phone" "$expected_phone"
verify_installed watch "$watch" "$expected_wear"

{
  printf 'captured_utc=%s\noem=%s\ncheckpoint=%s\npackage=%s\nphone_serial=%s\nwatch_serial=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$oem" "$checkpoint" "$package" "$phone" "$watch"
  printf 'phone_version_code=%s\nwatch_version_code=%s\nversion_name=%s\n' "$phone_code" "$watch_code" "$expected_version"
  printf 'phone_base_apk_sha256=%s\nwatch_base_apk_sha256=%s\n' "$expected_phone" "$expected_wear"
  printf 'expected_play_app_signing_cert_sha256=%s\nreviewer_id=%s\nreview_ticket=%s\n' "$expected_play_signer" "$reviewer" "$review_ticket"
  printf 'phone_model=%s\nwatch_model=%s\n' "$(capture "$phone" getprop ro.product.model)" "$(capture "$watch" getprop ro.product.model)"
  printf 'phone_manufacturer=%s\nwatch_manufacturer=%s\n' "$(capture "$phone" getprop ro.product.manufacturer)" "$(capture "$watch" getprop ro.product.manufacturer)"
  printf 'phone_build=%s\nwatch_build=%s\n' "$(capture "$phone" getprop ro.build.fingerprint)" "$(capture "$watch" getprop ro.build.fingerprint)"
} >"$out/metadata.txt"
watch_manufacturer=$(sed -n 's/^watch_manufacturer=//p' "$out/metadata.txt" | tr '[:upper:]' '[:lower:]')
case "$oem" in
  pixel) [[ "$watch_manufacturer" == *google* ]] || { echo "Expected Google Pixel watch; got $watch_manufacturer" >&2; exit 65; } ;;
  samsung) [[ "$watch_manufacturer" == *samsung* ]] || { echo "Expected Samsung watch; got $watch_manufacturer" >&2; exit 65; } ;;
esac

capture_device() {
  local label=$1 serial=$2 dir="$out/$1"
  capture "$serial" dumpsys package "$package" >"$dir/package.txt"
  capture "$serial" dumpsys activity services "$package" >"$dir/services.txt"
  capture "$serial" dumpsys activity broadcasts history >"$dir/broadcast-history.txt"
  capture "$serial" dumpsys connectivity >"$dir/connectivity.txt"
  capture "$serial" dumpsys battery >"$dir/battery.txt"
  capture "$serial" logcat -d -v threadtime >"$dir/logcat.txt"
}
capture_device phone "$phone"
capture_device watch "$watch"

# Query the release-safe, DUMP-protected diagnostic provider. This works for non-debuggable
# Play releases and emits bounded metadata only—never health values or encoded payload bytes.
diag=$(capture "$watch" content query --uri content://com.healthmd.android.wear.diagnostics/state)
[[ "$diag" == Row:* ]] || { echo "Wear diagnostics provider unavailable: $diag" >&2; exit 65; }
python3 - "$diag" "$out/watch/private-state.txt" <<'PY'
import re, sys
row, output = sys.argv[1:]
keys = (
    "uid", "cache_file_present", "cache_size", "cache_sha256",
    "mismatch_marker_present", "clear_tombstone_present", "ordering_corrupt",
)
values = {}
for key in keys:
    match = re.search(rf"(?:^|[, ]){re.escape(key)}=([^,]*)", row)
    if match is None:
        raise SystemExit(f"Wear diagnostics missing {key}: {row}")
    values[key] = match.group(1).strip()
with open(output, "w", encoding="utf-8") as handle:
    for key in keys:
        if values[key] or key not in {"cache_size", "cache_sha256"}:
            handle.write(f"{key}={values[key]}\n")
PY
if grep -q '^cache_file_present=true$' "$out/watch/private-state.txt"; then
  cache_size=$(sed -n 's/^cache_size=//p' "$out/watch/private-state.txt")
  cache_sha=$(sed -n 's/^cache_sha256=//p' "$out/watch/private-state.txt")
  [[ "$cache_size" =~ ^[0-9]+$ && "$cache_size" -ge 1 && "$cache_size" -le 65536 ]] || {
    echo "Watch cache size is outside the bounded contract: $cache_size" >&2; exit 65;
  }
  [[ "$cache_sha" =~ ^[0-9a-f]{64}$ ]] || { echo 'Watch cache digest is invalid' >&2; exit 65; }
fi

# Fail evidence capture if app logs contain serialized contract fields; keep full logs for crash/ANR review.
if grep -E 'bloodOxygenPercent|hrvRmssdMillis|capturedAtEpochMillis|"permissionState"|"days"' "$out/phone/logcat.txt" "$out/watch/logcat.txt" >/dev/null; then
  echo 'Health aggregate/contract field leaked to logcat' >&2
  exit 65
fi
if grep -E 'FATAL EXCEPTION|ANR in com\.healthmd\.android' "$out/phone/logcat.txt" "$out/watch/logcat.txt" >/dev/null; then
  echo 'Health.md crash or ANR present in captured logs' >&2
  exit 65
fi

( cd "$out" && find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done >SHA256SUMS )
echo "Captured paired Wear QA evidence at $out"
