#!/usr/bin/env bash
# Host-only safety/selection checks. All Gradle/ADB calls run against disposable fakes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/healthmd-a11y-runner.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/android/scripts" "$ROOT/sdk/platform-tools" "$ROOT/shots"
cp "$SCRIPT_DIR/run-accessibility-ui-tests.sh" "$ROOT/android/scripts/"
export ANDROID_HOME="$ROOT/sdk" ANDROID_SERIAL=2C061FDH200CJN
export MOCK_CALLS="$ROOT/calls" MOCK_SHOTS="$ROOT/shots"
printf 'synthetic only\n' > "$MOCK_SHOTS/fixture.txt"

cat > "$ROOT/android/gradlew" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'gradle %s\n' "$*" >> "$MOCK_CALLS"
[[ "$*" == ':app:assemblePlayDebug :app:assemblePlayDebugAndroidTest --console=plain' ]]
MOCK
cat > "$ROOT/sdk/platform-tools/adb" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
# Any call without the exact selected serial fails; never use the real adb binary.
[[ "$1" == '-s' && "$2" == "$ANDROID_SERIAL" ]]
shift 2
printf 'adb %s\n' "$*" >> "$MOCK_CALLS"
case "$1" in
    get-state)
        [[ "$MOCK_MODE" != unavailable ]] || exit 1
        printf 'device\n'
        ;;
    install)
        [[ "$2" == '-r' ]]
        case "$3" in
            app/build/outputs/apk/play/debug/app-play-debug.apk|app/build/outputs/apk/androidTest/play/debug/app-play-debug-androidTest.apk) ;;
            *) exit 17 ;;
        esac
        ;;
    shell)
        [[ "$2" == am && "$3" == instrument && "$*" != *'#'* ]]
        case "$MOCK_MODE" in
            success) printf 'OK (402 tests)\n' ;;
            zero) printf 'OK (0 tests)\n' ;;
            partial) printf 'OK (82 tests)\n' ;;
            failure) printf 'FAILURES!!!\nTests run: 402, Failures: 1\n' ;;
            runner_error) printf 'INSTRUMENTATION_FAILED: synthetic runner failure\nOK (402 tests)\n' ;;
            adb_error) exit 23 ;;
            *) exit 18 ;;
        esac
        ;;
    exec-out)
        [[ "$2" == run-as && "$3" == com.healthmd.android ]]
        tar -C "$MOCK_SHOTS" -cf - .
        ;;
    *) exit 19 ;;
esac
MOCK
chmod +x "$ROOT/android/gradlew" "$ROOT/sdk/platform-tools/adb"

CASES=0
run_case() {
    local mode="$1" expected="$2" actual
    shift 2
    export MOCK_MODE="$mode"
    : > "$MOCK_CALLS"
    if "$ROOT/android/scripts/run-accessibility-ui-tests.sh" "$@" > "$ROOT/result.log" 2>&1; then
        actual=0
    else
        actual=$?
    fi
    if [[ "$actual" -ne "$expected" ]]; then
        printf 'FAIL: %s expected exit %s, got %s\n' "$mode" "$expected" "$actual" >&2
        exit 1
    fi
    # No mocked run may even attempt a destructive/untargeted Gradle install path.
    if grep -Eq '(uninstall|pm clear|connected.*AndroidTest|:app:install)' "$MOCK_CALLS"; then
        echo 'FAIL: unsafe invocation' >&2
        exit 1
    fi
    CASES=$((CASES + 1))
}

run_case success 0
[[ "$(grep -c '^adb install -r ' "$MOCK_CALLS")" -eq 2 ]]
for suite in LargeDisplay MetricSelection ProfileSchedule FormatCustomization FrontmatterCustomization SecondaryControls; do
    grep -Fq "com.healthmd.presentation.accessibility.${suite}AccessibilityTest" "$MOCK_CALLS"
done
grep -Fq 'com.healthmd.presentation.common.ConfigurationProtectionTest' "$MOCK_CALLS"
run_case zero 1
run_case partial 1
run_case failure 1
run_case runner_error 1
run_case adb_error 23
run_case unavailable 1
! grep -Eq '^(gradle|adb install|adb shell)' "$MOCK_CALLS"
run_case success 2 one two
[[ ! -s "$MOCK_CALLS" ]]
run_case success 0 "$ROOT/captured"
cmp "$MOCK_SHOTS/fixture.txt" "$ROOT/captured/fixture.txt"
grep -Fq -- '-e healthmd.captureAccessibility true' "$MOCK_CALLS"
printf 'Safe accessibility runner: %s mocked cases passed\n' "$CASES"
