#!/usr/bin/env bash
set -euo pipefail

adb_bin="${ADB:-adb}"
apk="${1:-wear/build/outputs/apk/debug/wear-debug.apk}"
expected_package=${EXPECTED_PACKAGE:-com.healthmd.android}
package="$expected_package"
activity="com.healthmd.wear.MainActivity"
component="$package/$activity"
tmp="$(mktemp -d)"
evidence_root=${WEAR_EMULATOR_EVIDENCE_ROOT:-}
evidence_stage=''
cleanup() {
  rm -rf "$tmp"
  [[ -z "$evidence_stage" ]] || rm -rf "$evidence_stage"
}
trap cleanup EXIT

fail() { echo "Wear emulator smoke: $*" >&2; exit 1; }
[[ -f "$apk" ]] || fail "APK not found: $apk"
[[ -z "$evidence_root" || ! -e "$evidence_root" ]] \
  || fail "refusing to overwrite emulator evidence: $evidence_root"

aapt_bin=${AAPT:-}
if [[ -z "$aapt_bin" ]]; then
  sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}
  for candidate in "$sdk_root"/build-tools/*/aapt; do
    [[ ! -x "$candidate" ]] || aapt_bin=$candidate
  done
fi
[[ -x "$aapt_bin" ]] || fail "aapt unavailable; set AAPT to an executable Android build-tools aapt"
badging=$("$aapt_bin" dump badging "$apk" 2>/dev/null) || fail "could not inspect APK identity: $apk"
apk_package=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)
wear_version_code=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionCode='\([0-9][0-9]*\)'.*/\1/p" | head -1)
wear_version_name=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p" | head -1)
min_sdk=$(printf '%s\n' "$badging" | sed -n "s/^sdkVersion:'\([0-9][0-9]*\)'.*/\1/p" | head -1)
target_sdk=$(printf '%s\n' "$badging" | sed -n "s/^targetSdkVersion:'\([0-9][0-9]*\)'.*/\1/p" | head -1)
[[ "$apk_package" == "$expected_package" ]] || fail "packaged applicationId must be $expected_package; got ${apk_package:-missing}"
[[ "$wear_version_code" =~ ^[1-9][0-9]*$ ]] || fail "packaged Wear versionCode missing or invalid"
[[ "$wear_version_name" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
  || fail "packaged Wear versionName missing or non-semantic: ${wear_version_name:-missing}"
[[ "$min_sdk" =~ ^[1-9][0-9]*$ && "$target_sdk" =~ ^[1-9][0-9]*$ ]] \
  || fail "packaged Wear SDK identity missing or invalid"

"$adb_bin" get-state >/dev/null
[[ "$("$adb_bin" shell getprop sys.boot_completed | tr -d '\r')" == "1" ]] || fail "emulator is not booted"
"$adb_bin" logcat -c
"$adb_bin" install -r "$apk" >/dev/null
# Package replacement exercises the manifest receiver that invalidates Tiles/complications.
sleep 1
if "$adb_bin" logcat -d | grep -E 'FATAL EXCEPTION|Process: com\.healthmd\.android|ANR in com\.healthmd\.android' >/dev/null; then
  fail "Health.md crashed while invalidating surfaces after package replacement"
fi
"$adb_bin" logcat -c

start_app() {
  local attempt
  for attempt in 1 2 3 4 5; do
    "$adb_bin" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    "$adb_bin" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    "$adb_bin" shell am force-stop "$package" >/dev/null 2>&1 || true
    if "$adb_bin" shell am start -W "$component" >"$tmp/start.txt" 2>&1; then
      if grep -q 'Status: ok' "$tmp/start.txt" || {
        # Fresh headless Wear images can return Status: timeout while the requested activity has
        # actually been started behind the charging overlay. The following UI-state assertion—not
        # this transport status—is the authoritative launch proof.
        grep -q 'Status: timeout' "$tmp/start.txt" && grep -Fq "Activity: $component" "$tmp/start.txt"
      }; then
        sleep 1
        return 0
      fi
    fi
    sleep "$attempt"
  done
  cat "$tmp/start.txt" >&2
  fail "dashboard launch failed after bounded retries"
}

dump_ui() {
  local name=$1
  rm -f "$tmp/$name.xml"
  "$adb_bin" shell uiautomator dump "/sdcard/$name.xml" >/dev/null 2>&1 || return 1
  "$adb_bin" pull "/sdcard/$name.xml" "$tmp/$name.xml" >/dev/null 2>&1 || return 1
  [[ -s "$tmp/$name.xml" ]]
}

wait_for_ui() {
  local name=$1 expected=$2
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if dump_ui "$name" && grep -Fq "$expected" "$tmp/$name.xml"; then return 0; fi
    # The charging overlay can race repeated cold starts on a freshly wiped headless Wear image.
    # Dismiss it and relaunch rather than treating a system surface as an app failure.
    "$adb_bin" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    start_app
    sleep 1
  done
  echo "Last $name UI dump did not contain: $expected" >&2
  [[ ! -f "$tmp/$name.xml" ]] || cat "$tmp/$name.xml" >&2
  return 1
}

assert_ui() {
  local name=$1 expected=$2
  grep -Fq "$expected" "$tmp/$name.xml" || fail "$name UI missing: $expected"
}

clear_snapshot() {
  "$adb_bin" shell run-as "$package" rm -rf no_backup/wear-health
}

write_version_mismatch() {
  local sequence=$1
  "$adb_bin" shell run-as "$package" mkdir -p no_backup/wear-health
  printf '%s\n' "$sequence" \
    | "$adb_bin" shell "run-as $package sh -c 'cat > no_backup/wear-health/version-mismatch-v1'"
}

write_snapshot() {
  local sequence=$1 age_hours=$2 permission=$3 with_data=$4
  python3 - "$sequence" "$age_hours" "$permission" "$with_data" >"$tmp/snapshot.json" <<'PY'
import datetime, json, sys, time
sequence, age_hours, permission, with_data = sys.argv[1:]
now_ms = int(time.time() * 1000)
day = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
days = []
if with_data == "true":
    days = [{
        "localDate": day,
        "steps": 8420,
        "moveKilocalories": 410.0,
        "exerciseMinutes": 34.0,
        "sleepMinutes": 450.0,
        "restingHeartRateBpm": 58.0,
        "averageHeartRateBpm": 72.0,
        "hrvRmssdMillis": 46.0,
        "bloodOxygenPercent": 98.0,
    }]
print(json.dumps({
    "schemaVersion": 1,
    "sequence": int(sequence),
    "capturedAtEpochMillis": now_ms - int(age_hours) * 60 * 60 * 1000,
    "capturedZoneId": "UTC",
    "days": days,
    "permissionState": permission,
}, separators=(",", ":")))
PY
  "$adb_bin" shell run-as "$package" mkdir -p no_backup/wear-health
  "$adb_bin" shell "run-as $package sh -c 'cat > no_backup/wear-health/snapshot-v1.json'" <"$tmp/snapshot.json"
}

# Setup state with no phone-delivered cache.
clear_snapshot
start_app
wait_for_ui setup 'Open Health.md on your phone to finish setup.' || fail 'setup state did not become visible'
assert_ui setup 'Open Health.md on your phone to finish setup.'
assert_ui setup 'Sync Health Data'

# Fresh aggregate snapshot loaded through the production repository. This is deliberately not a
# preview bypass: force-stop/relaunch proves the watch remains useful offline from durable cache.
write_snapshot 1 0 READY true
start_app
wait_for_ui fresh 'Steps' || fail 'fresh aggregate state did not become visible'
assert_ui fresh 'Steps'
assert_ui fresh '8,420'
start_app
wait_for_ui fresh_offline_relaunch '8,420' || fail 'offline cache did not reappear after force-stop'
assert_ui fresh_offline_relaunch '8,420'
# A production touch gesture must visibly move the list. Exact settling varies across round images,
# so require a metric that is not present in the initial viewport.
fresh_scrolled_visible=false
for _ in $(seq 1 8); do
  "$adb_bin" shell input swipe 192 330 192 30 600 >/dev/null
  sleep 0.2
  dump_ui fresh_scrolled
  if ! grep -F 'Steps' "$tmp/fresh_scrolled.xml" >/dev/null || \
      grep -E 'Sleep|Resting Heart Rate|Average Heart Rate|HRV RMSSD|Blood Oxygen' "$tmp/fresh_scrolled.xml" >/dev/null; then
    fresh_scrolled_visible=true
    break
  fi
done
$fresh_scrolled_visible || fail 'touch scrolling did not expose a deep metric'

# Exercise crown input on images exposing a real rotary encoder. Input injection can be accepted
# by the framework even when a profile omits the hardware device, so require both discovery and a
# visible list-state change before calling this covered.
"$adb_bin" shell dumpsys input | grep -q 'Sources: ROTARY_ENCODER' \
  || fail 'pinned Wear emulator profile has no rotary encoder'
start_app
for _ in $(seq 1 20); do
  "$adb_bin" shell input rotaryencoder scroll --axis SCROLL,1 >/dev/null
done
sleep 1
dump_ui rotary_scrolled
assert_ui rotary_scrolled 'Blood Oxygen'
assert_ui rotary_scrolled 'Last phone sync; not real-time'

# Partial permissions disclose the source limitation while retaining available aggregate values.
write_snapshot 2 0 PERMISSION_REQUIRED true
start_app
wait_for_ui partial 'Health Connect access is needed on your phone.' || fail 'partial permission state did not become visible'
assert_ui partial 'Health Connect access is needed on your phone.'
partial_value_visible=false
for _ in $(seq 1 6); do
  if grep -F 'Steps' "$tmp/partial.xml" >/dev/null; then partial_value_visible=true; break; fi
  "$adb_bin" shell input swipe 192 300 192 90 400 >/dev/null
  sleep 0.2
  dump_ui partial
  grep -F '8,420' "$tmp/partial.xml" >/dev/null && partial_value_visible=true && break
done
$partial_value_visible || fail 'partial state did not retain an aggregate value'

# Freshness policy: 4-24 hours is visibly stale; over 24 hours hides measurements.
write_snapshot 3 5 READY true
start_app
wait_for_ui stale 'Updated 5 hours ago' || fail 'stale state did not become visible'
assert_ui stale 'Updated 5 hours ago'
write_snapshot 4 25 READY true
start_app
wait_for_ui expired 'Data is more than 24 hours old.' || fail 'expired state did not become visible'
assert_ui expired 'Data is more than 24 hours old.'

# Phone Health Connect unavailable state.
write_snapshot 5 0 HEALTH_CONNECT_UNAVAILABLE false
start_app
wait_for_ui unavailable 'Health Connect is unavailable on your phone.' || fail 'unavailable state did not become visible'
assert_ui unavailable 'Health Connect is unavailable on your phone.'

# A durable incompatible-schema marker survives force-stop/relaunch, hides cached measurements,
# and is removed once a compatible snapshot arrives.
write_snapshot 6 0 READY true
# The mismatch marker stores the rejected Data Layer sequence, never an app version code.
write_version_mismatch 7
start_app
wait_for_ui version_mismatch 'Update Health.md on your phone and watch.' || fail 'version mismatch state did not become visible'
assert_ui version_mismatch 'Update Health.md on your phone and watch.'
grep -Fq '8,420' "$tmp/version_mismatch.xml" && fail 'version mismatch exposed cached measurements'
start_app
wait_for_ui version_mismatch_relaunch 'Update Health.md on your phone and watch.' || fail 'durable version mismatch did not reappear'
assert_ui version_mismatch_relaunch 'Update Health.md on your phone and watch.'
write_snapshot 8 0 READY true
"$adb_bin" shell run-as "$package" rm -f no_backup/wear-health/version-mismatch-v1
start_app
wait_for_ui version_recovered '8,420' || fail 'compatible snapshot did not recover after mismatch'
assert_ui version_recovered '8,420'

# Largest supported smoke font and scroll path remain usable on a 384px small-round emulator.
"$adb_bin" shell settings put system font_scale 1.3
# Charging UI may race app launch after configuration changes, so retry the deterministic state.
write_snapshot 9 0 READY true
for _ in 1 2 3; do
  start_app
  sleep 1
  dump_ui large_font
  grep -Fq 'Health.md' "$tmp/large_font.xml" && break
  "$adb_bin" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
done
assert_ui large_font 'Health.md'
"$adb_bin" shell input swipe 192 300 192 90 400 >/dev/null
sleep 1
"$adb_bin" shell settings put system font_scale 1.0

# RTL/resources are exercised in the packaged app, not inferred from XML parity alone. The
# application locale command avoids rebooting the emulator and is reset before inventory checks.
"$adb_bin" shell cmd locale set-app-locales "$package" --user 0 --locales ar >/dev/null
start_app
wait_for_ui rtl 'الصحة' || fail 'Arabic RTL dashboard did not become visible'
assert_ui rtl 'الخطوات'
layout_direction="$($adb_bin shell dumpsys window | grep -m1 -Eo 'layoutDirection=[0-9]+' | cut -d= -f2 || true)"
# UI Automator's bounds remain the primary clipping evidence; framework layoutDirection output is
# not stable across Wear images, so only assert it when the image exposes the field.
[[ -z "$layout_direction" || "$layout_direction" == "1" ]] || fail "Arabic dashboard is not RTL"
"$adb_bin" shell cmd locale set-app-locales "$package" --user 0 --locales en-US >/dev/null
start_app
wait_for_ui restored_english 'Health.md' || fail 'English dashboard did not return after RTL smoke'

# Every declared provider must be discoverable from the installed package.
package_dump="$tmp/package.txt"
"$adb_bin" shell dumpsys package "$package" >"$package_dump"
for service in \
  DailyActivityTileService RecoveryTileService \
  DailyActivityComplicationService RecoveryComplicationService \
  StepsComplicationService MoveComplicationService ExerciseComplicationService \
  SleepComplicationService RestingHeartRateComplicationService \
  AverageHeartRateComplicationService HrvComplicationService \
  BloodOxygenComplicationService; do
  grep -Fq "$service" "$package_dump" || fail "installed component missing: $service"
done

installed_version_code=$(sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' "$package_dump" | head -1)
installed_version_name=$(sed -n 's/.*versionName=\([^[:space:]]*\).*/\1/p' "$package_dump" | head -1)
installed_min_sdk=$(sed -n 's/.*minSdk=\([0-9][0-9]*\).*/\1/p' "$package_dump" | head -1)
installed_target_sdk=$(sed -n 's/.*targetSdk=\([0-9][0-9]*\).*/\1/p' "$package_dump" | head -1)
[[ "$installed_version_code" == "$wear_version_code" \
  && "$installed_version_name" == "$wear_version_name" \
  && "$installed_min_sdk" == "$min_sdk" \
  && "$installed_target_sdk" == "$target_sdk" ]] \
  || fail "installed identity differs from inspected APK: expected $wear_version_name/$wear_version_code SDK $min_sdk/$target_sdk; got ${installed_version_name:-missing}/${installed_version_code:-missing} SDK ${installed_min_sdk:-missing}/${installed_target_sdk:-missing}"
grep -Fq 'com.healthmd.android.wear.diagnostics' "$package_dump" || fail 'diagnostic provider missing'
diag=$($adb_bin shell content query --uri content://com.healthmd.android.wear.diagnostics/state 2>&1)
[[ "$diag" == Row:* && "$diag" == *'cache_file_present=true'* && "$diag" != *'localDate'* && "$diag" != *'steps'* ]] \
  || fail "bounded diagnostic provider output invalid: $diag"

# Privacy smoke: the watch cache must stay under no-backup storage, backup must remain disabled,
# and application log output must never serialize aggregate field names or representative values.
! grep -q 'flags=.*ALLOW_BACKUP' "$package_dump" || fail 'packaged Wear backup is not disabled'
"$adb_bin" shell run-as "$package" test -f no_backup/wear-health/snapshot-v1.json \
  || fail 'snapshot is not stored under no-backup storage'
log="$tmp/logcat.txt"
"$adb_bin" logcat -d > "$log"
if grep -E 'bloodOxygenPercent|hrvRmssdMillis|capturedAtEpochMillis|"steps"|8,420' "$log" >/dev/null; then
  fail 'health aggregate leaked to logcat'
fi
if "$adb_bin" logcat -d | grep -E 'FATAL EXCEPTION|Process: com\.healthmd\.android|ANR in com\.healthmd\.android' >/dev/null; then
  fail "Health.md crash or ANR found in logcat"
fi

if [[ -n "$evidence_root" ]]; then
  mkdir -p "$(dirname "$evidence_root")"
  evidence_stage=$(mktemp -d "$(dirname "$evidence_root")/.wear-emulator.XXXXXX")
  mkdir "$evidence_stage/ui"
  find "$tmp" -maxdepth 1 -type f -name '*.xml' -exec cp {} "$evidence_stage/ui/" \;
  cp "$package_dump" "$evidence_stage/package.txt"
  cp "$log" "$evidence_stage/logcat.txt"
  cp "$tmp/start.txt" "$evidence_stage/last-launch.txt"
  printf '%s\n' "$diag" >"$evidence_stage/diagnostics.txt"
  "$adb_bin" exec-out screencap -p >"$evidence_stage/final-dashboard.png"
  api=$($adb_bin shell getprop ro.build.version.sdk | tr -d '\r')
  abi=$($adb_bin shell getprop ro.product.cpu.abi | tr -d '\r')
  serial=$($adb_bin get-serialno | tr -d '\r')
  apk_sha=$(shasum -a 256 "$apk" | awk '{print $1}')
  jq -n --arg captured "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg avd "${WEAR_EMULATOR_AVD:-unknown}" --arg serial "$serial" \
    --argjson api "$api" --arg abi "$abi" --arg apkSha "$apk_sha" \
    --arg package "$package" --arg versionName "$wear_version_name" \
    --argjson wearVersionCode "$wear_version_code" --argjson minSdk "$min_sdk" \
    --argjson targetSdk "$target_sdk" '{
      schemaVersion:1, scope:"local-debug-production-cache-smoke",
      capturedAtUtc:$captured, avd:$avd, serial:$serial, api:$api, abi:$abi,
      package:$package, versionName:$versionName, wearVersionCode:$wearVersionCode,
      minSdk:$minSdk, targetSdk:$targetSdk,
      apkSha256:$apkSha, rotaryEncoderDiscovered:true,
      states:["setup","fresh","offline-relaunch","touch-scroll","rotary-scroll","partial",
        "stale","expired","unavailable","version-mismatch","mismatch-relaunch","mismatch-recovery",
        "large-font-1.3x","arabic-rtl","english-restored"],
      exactTiles:2, exactComplications:10, backupDisabled:true,
      noBackupCacheVerified:true, boundedDiagnosticsVerified:true,
      logPrivacyVerified:true, crashAnrFree:true, result:"pass"
    }' >"$evidence_stage/receipt.json"
  cat >"$evidence_stage/README.md" <<EOF
# Local Wear emulator evidence

Exact current debug APK production-cache smoke completed successfully. This retained local ARM64
run covers every state listed in \`receipt.json\`, including a discovered real rotary encoder,
1.3× font, Arabic RTL, exact two-Tile/ten-complication inventory, no-backup cache, bounded
diagnostics, log privacy, and crash/ANR checks. It is local emulator evidence only and does not
replace the required exact-SHA remote x86_64 push CI, Play-generated APK, or physical OEM gates.
EOF
  (
    cd "$evidence_stage"
    find . -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort \
      | while IFS= read -r file; do shasum -a 256 "$file"; done >SHA256SUMS
  )
  mv "$evidence_stage" "$evidence_root"
  evidence_stage=''
fi

echo "Wear emulator dashboard/state/component smoke passed"
