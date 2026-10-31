#!/usr/bin/env bash
# Read owner-prepared synthetic Health Connect sleep; never insert or modify health records.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ANDROID_ROOT/../.." && pwd)"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
SERIAL="${ANDROID_SERIAL:-2C061FDH200CJN}"
DATES="${HEALTHMD_LIVE_SLEEP_DATES:?Supply comma-separated synthetic sleep wake dates (YYYY-MM-DD)}"
ZONE="${HEALTHMD_LIVE_SLEEP_ZONE:?Supply the captured IANA calendar timezone}"
PLUGIN="${HEALTHMD_OBSIDIAN_PLUGIN_REPO:?Supply the clean, pinned Obsidian reader checkout with installed dependencies}"
[[ "$SERIAL" == "2C061FDH200CJN" ]] || { echo "Use the designated Pixel 7 test phone." >&2; exit 2; }
python3 - "$DATES" "$ZONE" <<'PY'
import datetime, re, sys, zoneinfo
values = sys.argv[1].split(',')
assert 1 <= len(values) <= 31 and all(re.fullmatch(r'\d{4}-\d{2}-\d{2}', v) for v in values)
dates = [datetime.date.fromisoformat(v) for v in values]
assert (max(dates) - min(dates)).days <= 30
assert re.fullmatch(r'[A-Za-z0-9_+\-]+(?:/[A-Za-z0-9_+\-]+)*', sys.argv[2])
zoneinfo.ZoneInfo(sys.argv[2])
PY
node "$SCRIPT_DIR/verify-live-sleep-export.mjs" --check-reader "$PLUGIN"
APP="com.healthmd.android.e2e"
TEST_APP="$APP.test"
for package in "$APP" "$TEST_APP"; do
    if [[ -n "$("$ADB" -s "$SERIAL" shell pm path "$package" | tr -d '\r')" ]]; then
        echo "Existing isolated package $package must be preserved; stop its owner before using this runner." >&2
        exit 2
    fi
done

OUTPUT="${HEALTHMD_LIVE_SLEEP_OUTPUT:-$REPO_ROOT/.pi/live-sleep-acceptance/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$(dirname "$OUTPUT")"
mkdir "$OUTPUT"
echo "Building isolated read-only provider acceptance artifacts."
(
    cd "$ANDROID_ROOT"
    ./gradlew --no-daemon -PhealthmdInstrumentedTestBuildType=e2e \
        :app:assemblePlayE2e :app:assemblePlayE2eAndroidTest
) >"$OUTPUT/build.log" 2>&1
APP_APK="$ANDROID_ROOT/app/build/outputs/apk/play/e2e/app-play-e2e.apk"
TEST_APK="$ANDROID_ROOT/app/build/outputs/apk/androidTest/play/e2e/app-play-e2e-androidTest.apk"
ACCEPTANCE_SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
python3 - "$REPO_ROOT" "$APP_APK" "$TEST_APK" "$OUTPUT" "$ACCEPTANCE_SDK_ROOT" "$DATES" "$ZONE" <<'PY'
import hashlib, json, pathlib, re, subprocess, sys
root, app, test, output, sdk = map(pathlib.Path, sys.argv[1:6])
aapt = sorted((sdk/'build-tools').glob('*/aapt'))[-1]
packages = {}
for apk, expected in [(app,'com.healthmd.android.e2e'), (test,'com.healthmd.android.e2e.test')]:
    badging = subprocess.check_output([str(aapt),'dump','badging',str(apk)], text=True)
    package = re.search(r"^package: name='([^']+)'", badging, re.MULTILINE)
    assert package and package.group(1) == expected, 'Refusing an APK outside the isolated application'
    packages[apk.name] = expected
paths = [app, test, root/'apps/android/app/src/androidTest/java/com/healthmd/data/health/LiveSleepCaptureAcceptanceTest.kt',
         root/'apps/android/app/src/main/java/com/healthmd/data/health/HealthConnectManager.kt',
         root/'apps/android/app/src/main/java/com/healthmd/data/health/SleepJournalSummary.kt']
source = {'commit': subprocess.check_output(['git','rev-parse','HEAD'], cwd=root, text=True).strip(),
          'dirty': bool(subprocess.check_output(['git','status','--porcelain'], cwd=root, text=True).strip()),
          'scope': {'wakeDates': sorted(set(sys.argv[6].split(','))), 'calendarTimeZone': sys.argv[7], 'readOnly': True},
          'apkPackages': packages,
          'sha256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
(output/'source.json').write_text(json.dumps(source, indent=2)+'\n')
PY
OWN_APP=false
OWN_TEST=false
APP_PATH=""
TEST_PATH=""
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    for package in "$TEST_APP" "$APP"; do
        local owned=false expected=""
        if [[ "$package" == "$APP" ]]; then owned="$OWN_APP"; expected="$APP_PATH";
        else owned="$OWN_TEST"; expected="$TEST_PATH"; fi
        if [[ "$owned" == true ]]; then
            local current
            current="$("$ADB" -s "$SERIAL" shell pm path "$package" 2>/dev/null | tr -d '\r' || true)"
            if [[ -n "$current" && "$current" == "$expected" ]]; then
                "$ADB" -s "$SERIAL" uninstall "$package" >/dev/null 2>&1 || status=1
            elif [[ -n "$current" ]]; then
                echo "Preserved changed package $package; cleanup requires its owner." >&2
                status=1
            fi
        fi
    done
    exit "$status"
}
trap cleanup EXIT INT TERM
# No replacement install: a concurrently installed package makes this operation fail safely.
"$ADB" -s "$SERIAL" install -t "$APP_APK" >"$OUTPUT/install-app.log" 2>&1
OWN_APP=true
APP_PATH="$("$ADB" -s "$SERIAL" shell pm path "$APP" | tr -d '\r')"
"$ADB" -s "$SERIAL" install -t "$TEST_APK" >"$OUTPUT/install-test.log" 2>&1
OWN_TEST=true
TEST_PATH="$("$ADB" -s "$SERIAL" shell pm path "$TEST_APP" | tr -d '\r')"
"$ADB" -s "$SERIAL" shell pm grant "$APP" android.permission.health.READ_SLEEP
DEVICE_EPOCH="$("$ADB" -s "$SERIAL" shell date +%s | tr -d '\r')"
NEEDS_HISTORY="$(python3 - "$DATES" "$ZONE" "$DEVICE_EPOCH" <<'PY'
import datetime, sys, zoneinfo
zone = zoneinfo.ZoneInfo(sys.argv[2])
first = min(datetime.date.fromisoformat(v) for v in sys.argv[1].split(',')) - datetime.timedelta(days=2)
print('yes' if datetime.datetime.combine(first, datetime.time(), zone).timestamp() < int(sys.argv[3])-30*86400 else 'no')
PY
)"
if [[ "$NEEDS_HISTORY" == yes ]]; then
    "$ADB" -s "$SERIAL" shell pm grant "$APP" android.permission.health.READ_HEALTH_DATA_HISTORY
fi
"$ADB" -s "$SERIAL" shell am instrument -w -r \
    -e class com.healthmd.data.health.LiveSleepCaptureAcceptanceTest \
    -e healthmdLiveSleepCapture true -e healthmdSleepDates "$DATES" -e healthmdSleepZone "$ZONE" \
    "$TEST_APP/androidx.test.runner.AndroidJUnitRunner" >"$OUTPUT/instrumentation.log" 2>&1
grep -Eq '^OK \(1 test\)' "$OUTPUT/instrumentation.log" || {
    echo "Provider acceptance did not pass; private evidence: $OUTPUT" >&2; exit 1;
}
"$ADB" -s "$SERIAL" exec-out run-as "$APP" tar -C cache -cf - live-sleep-acceptance >"$OUTPUT/native.tar"
python3 - "$OUTPUT" <<'PY'
import hashlib, json, pathlib, sys, tarfile
root = pathlib.Path(sys.argv[1]).resolve()
with tarfile.open(root/'native.tar') as archive:
    for item in archive:
        path = (root/item.name).resolve()
        assert path.is_relative_to(root) and (item.isfile() or item.isdir())
        if item.isdir(): path.mkdir(parents=True, exist_ok=True)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(archive.extractfile(item).read())
capture = root/'live-sleep-acceptance'
receipt = json.loads((capture/'receipt.json').read_text())
assert receipt['sourceRecords'] > 0 and receipt['artifacts'] >= 8 and receipt['productionAdmissionEnabled'] is False
files = [p for p in capture.rglob('*') if p.is_file() and p.name not in ['receipt.json','sdk-baseline.json']]
assert len(files) == receipt['artifacts']
(root/'artifact-sha256.json').write_text(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}, indent=2)+'\n')
PY
node "$SCRIPT_DIR/verify-live-sleep-export.mjs" "$OUTPUT/live-sleep-acceptance" "$PLUGIN" "$ZONE"
echo "Provider acceptance passed; private local evidence: $OUTPUT"
