#!/usr/bin/env bash
set -euo pipefail

# Capture auditable, comparable Wear battery evidence without changing device state.
# Run at each baseline/start/end checkpoint of the documented physical protocol.
usage() {
  cat >&2 <<'EOF'
Usage: capture-wear-battery-evidence.sh OUTPUT_DIR DEVICE MODEL SCENARIO CHECKPOINT
  DEVICE: pixel | samsung
  SCENARIO: paired-24h | disconnected-12h
  CHECKPOINT: baseline-start | baseline-end | healthmd-start | healthmd-end

Required environment:
  EXPECTED_WEAR_APK_SHA256=<approved Play-generated installed base.apk SHA-256>
  EXPECTED_PLAY_APP_SIGNING_CERT_SHA256=<authorized Play App Signing certificate SHA-256>
  EXPECTED_WEAR_VERSION_CODE=<exact installed Wear version code>
  EXPECTED_VERSION_NAME=<exact installed Wear semantic version>
  REVIEWER_ID=<independent reviewer> REVIEW_TICKET=<protected approval record>
  CONTROL_PROFILE_ID=<same controlled brightness/radios/watch-face/activity protocol ID>
  CONFIRM_CONTROLLED_CONDITIONS=yes CONFIRM_NO_USER_REFRESH=yes
  CONFIRM_NO_WAKELOCK_ANR=yes

Optional environment:
  ADB=/path/to/adb
  ANDROID_SERIAL=<serial>   Required when more than one device is attached.

This command reads device state only. It does not reset batterystats, change charging,
or enable/disable radios. It binds every checkpoint to the exact installed Play-generated Wear APK.
EOF
  exit 64
}

[[ $# -eq 5 ]] || usage
out=$1
reviewer=${REVIEWER_ID:-}; review_ticket=${REVIEW_TICKET:-}; control_profile=${CONTROL_PROFILE_ID:-}
expected_wear_apk=${EXPECTED_WEAR_APK_SHA256:-}
expected_play_signer=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
expected_wear_code=${EXPECTED_WEAR_VERSION_CODE:-}
expected_version=${EXPECTED_VERSION_NAME:-}
[[ -n "$reviewer" && -n "$review_ticket" && -n "$control_profile" && ${CONFIRM_CONTROLLED_CONDITIONS:-} == yes && ${CONFIRM_NO_USER_REFRESH:-} == yes && ${CONFIRM_NO_WAKELOCK_ANR:-} == yes ]] || usage
[[ "$expected_wear_apk" =~ ^[0-9a-f]{64}$ && "$expected_play_signer" =~ ^[0-9a-f]{64}$ ]] || usage
[[ "$expected_wear_code" =~ ^[1-9][0-9]*$ && "$expected_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || usage
device=$2
model=$3
scenario=$4
checkpoint=$5
case "$device" in pixel|samsung) ;; *) usage ;; esac
case "$scenario" in paired-24h|disconnected-12h) ;; *) usage ;; esac
case "$checkpoint" in baseline-start|baseline-end|healthmd-start|healthmd-end) ;; *) usage ;; esac

adb_bin=${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}
[[ -x "$adb_bin" ]] || { echo "adb not found: $adb_bin" >&2; exit 69; }
serial_list=$("$adb_bin" devices | awk 'NR > 1 && $2 == "device" { print $1 }')
serial_count=$(printf '%s\n' "$serial_list" | awk 'NF { count++ } END { print count + 0 }')
if [[ -z ${ANDROID_SERIAL:-} && $serial_count -ne 1 ]]; then
  echo "Set ANDROID_SERIAL; found $serial_count ready devices" >&2
  exit 69
fi
serial=${ANDROID_SERIAL:-$(printf '%s\n' "$serial_list" | awk 'NF { print; exit }')}
export ANDROID_SERIAL=$serial

[[ ! -e "$out" ]] || { echo "Refusing to overwrite existing path $out" >&2; exit 73; }
mkdir -p "$out"
package=com.healthmd.android
capture() { "$adb_bin" shell "$@" 2>&1 | tr -d '\r'; }
package_dump=$(capture dumpsys package "$package")
uid=$(printf '%s\n' "$package_dump" | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' | head -1)
version_code=$(printf '%s\n' "$package_dump" | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -1)
version_name=$(printf '%s\n' "$package_dump" | sed -n 's/.*versionName=\([^[:space:]]*\).*/\1/p' | head -1)
[[ -n "$uid" ]] || { echo "$package is not installed on $serial" >&2; exit 69; }
[[ "$version_code" == "$expected_wear_code" && "$version_name" == "$expected_version" ]] || {
  echo "Expected Wear $expected_version/$expected_wear_code; got $version_name/$version_code" >&2; exit 65;
}

apksigner=${APKSIGNER:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/apksigner}
[[ -x "$apksigner" ]] || { echo "apksigner unavailable: $apksigner" >&2; exit 69; }
base_path=$(capture pm path "$package" | sed -n 's/^package:\(.*\/base\.apk\)$/\1/p' | head -1)
[[ -n "$base_path" ]] || { echo 'Installed Wear base.apk unavailable' >&2; exit 65; }
tmp_apk=$(mktemp); trap 'rm -f "$tmp_apk"' EXIT
"$adb_bin" pull "$base_path" "$tmp_apk" >/dev/null
actual_wear_apk=$(shasum -a 256 "$tmp_apk" | awk '{print $1}')
[[ "$actual_wear_apk" == "$expected_wear_apk" ]] || {
  echo "Installed Wear base APK digest mismatch: $actual_wear_apk" >&2; exit 65;
}
"$apksigner" verify --print-certs "$tmp_apk" >"$out/signer.txt"
actual_signer=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$out/signer.txt" | head -1 | tr '[:upper:]' '[:lower:]')
[[ "$actual_signer" == "$expected_play_signer" ]] || {
  echo "Installed Wear Play App Signing certificate mismatch: $actual_signer" >&2; exit 65;
}

features_dump=$(capture pm list features)
display_dump=$(printf '%s\n' '--- dumpsys window displays ---'; capture dumpsys window displays; printf '%s\n' '--- dumpsys activity settings ---'; capture dumpsys activity settings; printf '%s\n' '--- wm size ---'; capture wm size; printf '%s\n' '--- wm density ---'; capture wm density)
build_characteristics=$(capture getprop ro.build.characteristics)
hardware=$(capture getprop ro.hardware)
kernel_qemu=$(capture getprop ro.kernel.qemu)
boot_qemu=$(capture getprop ro.boot.qemu)
build_fingerprint=$(capture getprop ro.build.fingerprint)
product_model=$(capture getprop ro.product.model)
watch_feature=false
printf '%s\n' "$features_dump" | grep -Fxq 'feature:android.hardware.type.watch' && watch_feature=true
screen_round=false
printf '%s\n' "$display_dump" | grep -Eiq '(^|[^[:alnum:]_])(mIsRound|isRound)[=: ]+true([^[:alnum:]_]|$)|FLAG_ROUND|screenRound[=: ]+(true|yes|round)' && screen_round=true
physical_size=$(printf '%s\n' "$display_dump" | sed -n 's/.*Physical size: \([0-9][0-9]*x[0-9][0-9]*\).*/\1/p' | head -1)
emulator=false
if [[ "$kernel_qemu" =~ ^(1|true)$ || "$boot_qemu" =~ ^(1|true)$ ]] \
  || printf '%s\n%s\n%s\n' "$hardware" "$build_fingerprint" "$product_model" \
    | grep -Eiq '(^|[/ _.-])(goldfish|ranchu|cuttlefish|vsoc|emulator|sdk_gphone)([/ _.-]|$)'; then
  emulator=true
fi
[[ "$watch_feature" == true && "$screen_round" == true && "$emulator" == false && "$physical_size" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] || {
  echo "Battery evidence requires a physical round Wear OS watch (watch=$watch_feature round=$screen_round emulator=$emulator size=${physical_size:-unknown})" >&2
  exit 65
}

battery_dump=$(capture dumpsys battery)
battery_level=$(printf '%s\n' "$battery_dump" | sed -n 's/^  level: //p' | head -1)
battery_scale=$(printf '%s\n' "$battery_dump" | sed -n 's/^  scale: //p' | head -1)
battery_status=$(printf '%s\n' "$battery_dump" | sed -n 's/^  status: //p' | head -1)
[[ "$battery_level" =~ ^[0-9]+$ && "$battery_scale" =~ ^[1-9][0-9]*$ && "$battery_status" =~ ^[0-9]+$ ]] || {
  echo 'Unable to determine raw battery level/scale/status' >&2; exit 65;
}
[[ "$battery_status" != 2 && "$battery_status" != 5 ]] || {
  echo "Battery status reports charging/full: $battery_status" >&2; exit 65;
}
ac_powered=$(printf '%s\n' "$battery_dump" | sed -n 's/^  AC powered: //p' | head -1)
usb_powered=$(printf '%s\n' "$battery_dump" | sed -n 's/^  USB powered: //p' | head -1)
wireless_powered=$(printf '%s\n' "$battery_dump" | sed -n 's/^  Wireless powered: //p' | head -1)
dock_powered=$(printf '%s\n' "$battery_dump" | sed -n 's/^  Dock powered: //p' | head -1)
[[ -n "$dock_powered" ]] || dock_powered=false
legacy_plugged=$(printf '%s\n' "$battery_dump" | sed -n 's/^  plugged: //p' | head -1)
if [[ "$ac_powered" =~ ^(true|false)$ && "$usb_powered" =~ ^(true|false)$ && "$wireless_powered" =~ ^(true|false)$ && "$dock_powered" =~ ^(true|false)$ ]]; then
  plugged=0
  [[ "$ac_powered" == true || "$usb_powered" == true || "$wireless_powered" == true || "$dock_powered" == true ]] && plugged=1
  # A numeric OEM bitmask is independent raw evidence. Never let false booleans override a
  # contradictory nonzero bitmask when both representations are present.
  [[ "$legacy_plugged" =~ ^[0-9]+$ && "$legacy_plugged" != 0 ]] && plugged=1
elif [[ "$legacy_plugged" =~ ^[0-9]+$ ]]; then
  plugged=0; [[ "$legacy_plugged" != 0 ]] && plugged=1
else
  echo 'Unable to determine charging connection from dumpsys battery' >&2
  exit 65
fi
{
  printf 'captured_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'serial=%s\n' "$serial"
  printf 'device=%s\nmodel_label=%s\nscenario=%s\ncheckpoint=%s\n' "$device" "$model" "$scenario" "$checkpoint"
  protocol_mode=baseline; [[ "$checkpoint" == healthmd-* ]] && protocol_mode=healthmd
  printf 'package=%s\nuid=%s\nversion_code=%s\nversion_name=%s\nwear_base_apk_sha256=%s\nplay_app_signing_cert_sha256=%s\n' \
    "$package" "$uid" "$version_code" "$version_name" "$actual_wear_apk" "$actual_signer"
  printf 'reviewer_id=%s\nreview_ticket=%s\ncontrol_profile_id=%s\ncontrolled_conditions=yes\nno_user_refresh=yes\nno_wakelock_anr_confirmed=yes\nprotocol_mode=%s\n' \
    "$reviewer" "$review_ticket" "$control_profile" "$protocol_mode"
  printf 'manufacturer=%s\n' "$(capture getprop ro.product.manufacturer)"
  printf 'product_model=%s\n' "$product_model"
  printf 'build_fingerprint=%s\n' "$build_fingerprint"
  printf 'build_characteristics=%s\nhardware=%s\nro_kernel_qemu=%s\nro_boot_qemu=%s\n' \
    "$build_characteristics" "$hardware" "$kernel_qemu" "$boot_qemu"
  printf 'watch_feature=%s\nscreen_round=%s\nemulator=%s\nphysical_size=%s\n' \
    "$watch_feature" "$screen_round" "$emulator" "$physical_size"
  printf 'sdk=%s\n' "$(capture getprop ro.build.version.sdk)"
  printf 'battery_level=%s\n' "$battery_level"
  printf 'battery_scale=%s\n' "$battery_scale"
  printf 'battery_status=%s\n' "$battery_status"
  printf 'ac_powered=%s\nusb_powered=%s\nwireless_powered=%s\ndock_powered=%s\nplugged=%s\n' "$ac_powered" "$usb_powered" "$wireless_powered" "$dock_powered" "$plugged"
  printf 'temperature_tenths_c=%s\n' "$(printf '%s\n' "$battery_dump" | sed -n 's/^  temperature: //p' | head -1)"
} >"$out/metadata.txt"
printf '%s\n' "$battery_dump" >"$out/battery.txt"
printf '%s\n' "$features_dump" >"$out/features.txt"
printf '%s\n' "$display_dump" >"$out/display.txt"
capture dumpsys batterystats --checkin "$package" >"$out/batterystats-checkin.txt"
capture dumpsys batterystats "$package" >"$out/batterystats.txt"
capture dumpsys batterystats --history >"$out/batterystats-history.txt"
capture dumpsys power >"$out/power.txt"
capture dumpsys alarm >"$out/alarm.txt"
capture dumpsys jobscheduler "$package" >"$out/jobscheduler.txt"
printf '%s\n' "$package_dump" >"$out/package.txt"
capture logcat -d -v threadtime >"$out/logcat.txt"

# Reject evidence captured while plugged: battery deltas would not be comparable.
plugged=$(sed -n 's/^plugged=//p' "$out/metadata.txt")
[[ "$plugged" == 0 ]] || {
  echo "Evidence saved, but checkpoint is invalid because plugged=$plugged" >&2
  exit 65
}

( cd "$out" && shasum -a 256 metadata.txt signer.txt battery.txt features.txt display.txt batterystats-checkin.txt batterystats.txt batterystats-history.txt power.txt alarm.txt jobscheduler.txt package.txt logcat.txt >SHA256SUMS )
echo "Captured $device $scenario $checkpoint evidence at $out"
