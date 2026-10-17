#!/usr/bin/env bash
# Host-only command/scope/failure checks; never starts Gradle or touches a device.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/healthmd-ci-instrumentation.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/android/scripts"
cp "$SCRIPT_DIR/run-ci-instrumentation.sh" "$TEST_ROOT/android/scripts/"
export MOCK_CALLS="$TEST_ROOT/calls"

cat > "$TEST_ROOT/android/gradlew" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_CALLS"
[[ "$PWD" == */android ]]
case "$*" in
    *RunnerArguments.class=*) exit "${MOCK_FOCUS_EXIT:-0}" ;;
    *:healthmd-core:connectedDebugAndroidTest*) exit "${MOCK_PLAY_EXIT:-0}" ;;
    *:app:connectedFdroidDebugAndroidTest*) exit "${MOCK_FDROID_EXIT:-0}" ;;
    *) exit 19 ;;
esac
MOCK
chmod +x "$TEST_ROOT/android/gradlew"

CASES=0
run_case() {
    local mode="$1" expected="$2" actual
    shift 2
    : > "$MOCK_CALLS"
    if HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX="$mode" \
        bash "$TEST_ROOT/android/scripts/run-ci-instrumentation.sh" "$@" > "$TEST_ROOT/result.log" 2>&1; then
        actual=0
    else
        actual=$?
    fi
    if [[ "$actual" -ne "$expected" ]]; then
        cat "$TEST_ROOT/result.log" >&2
        printf 'FAIL: mode %s expected exit %s, got %s\n' "$mode" "$expected" "$actual" >&2
        exit 1
    fi
    CASES=$((CASES + 1))
}

FOCUS_COMMAND=':app:connectedFdroidDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.healthmd.presentation.accessibility.NativeInputReadinessTest --stacktrace'

PLAY_COMMAND=':healthmd-core:connectedDebugAndroidTest :app:connectedPlayDebugAndroidTest --stacktrace'
FDROID_COMMAND=':app:connectedFdroidDebugAndroidTest --stacktrace'
SMOKE_COMMAND=':app:connectedFdroidDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.healthmd.accessibility.matrix=smoke --stacktrace'

run_case standard 0
printf '%s\n%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" "$SMOKE_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"

run_case full 0
printf '%s\n%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" "$FDROID_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"

run_case '' 2
[[ ! -s "$MOCK_CALLS" ]]

: > "$MOCK_CALLS"
env -u HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX bash "$TEST_ROOT/android/scripts/run-ci-instrumentation.sh"
CASES=$((CASES + 1))
printf '%s\n%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" "$FDROID_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"

run_case smoke 2
[[ ! -s "$MOCK_CALLS" ]]
run_case standard 2 --tests ignored
[[ ! -s "$MOCK_CALLS" ]]

export MOCK_FOCUS_EXIT=25
run_case standard 25
printf '%s\n' "$FOCUS_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"
unset MOCK_FOCUS_EXIT

export MOCK_PLAY_EXIT=23
run_case standard 23
printf '%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"
unset MOCK_PLAY_EXIT

export MOCK_FDROID_EXIT=24
run_case standard 24
printf '%s\n%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" "$SMOKE_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"

printf 'CI instrumentation runner: %s mocked cases passed\n' "$CASES"
