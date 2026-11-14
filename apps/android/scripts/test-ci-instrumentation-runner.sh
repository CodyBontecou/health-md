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
    *:healthmd-core:connectedDebugAndroidTest*|*:app:connectedPlayDebugAndroidTest*) exit "${MOCK_PLAY_EXIT:-0}" ;;
    *) exit 19 ;;
esac
MOCK
chmod +x "$TEST_ROOT/android/gradlew"

mkdir -p "$TEST_ROOT/bin"
export MOCK_ADB_CALLS="$TEST_ROOT/adb-calls"
: > "$MOCK_ADB_CALLS"
cat > "$TEST_ROOT/bin/adb" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_ADB_CALLS"
case "$*" in
    '-s emulator-5554 shell getprop ro.boot.qemu') printf '1\n' ;;
    '-s emulator-5554 shell dumpsys -t 2 window')
        printf '  mCurrentFocus=Window{123 u0 Synthetic platform blocker}\n' ;;
    '-s emulator-5554 shell dumpsys -t 2 activity lastanr')
        printf 'Reason: Synthetic launcher ANR\n' ;;
    '-s emulator-5554 logcat -d -v threadtime ActivityManager:E InputDispatcher:E WindowManager:E *:S')
        printf 'Synthetic platform input error\n' ;;
    *) exit 31 ;;
esac
MOCK
chmod +x "$TEST_ROOT/bin/adb"
export PATH="$TEST_ROOT/bin:$PATH"

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

DIAGNOSTICS='-Pandroid.testInstrumentationRunnerArguments.healthmd.ciInputDiagnostics=false'
export GITHUB_ACTIONS=false
FOCUS_COMMAND=':app:connectedPlayDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.healthmd.presentation.accessibility.NativeInputReadinessTest --stacktrace'

PLAY_COMMAND=':healthmd-core:connectedDebugAndroidTest :app:connectedPlayDebugAndroidTest --stacktrace'

FOCUS_COMMAND="$DIAGNOSTICS $FOCUS_COMMAND"

PLAY_COMMAND="$DIAGNOSTICS $PLAY_COMMAND"



run_case standard 0
printf '%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"

run_case full 0
printf '%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"

run_case '' 2
[[ ! -s "$MOCK_CALLS" ]]

: > "$MOCK_CALLS"
env -u HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX bash "$TEST_ROOT/android/scripts/run-ci-instrumentation.sh"
CASES=$((CASES + 1))
printf '%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" > "$TEST_ROOT/expected"
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

[[ ! -s "$MOCK_ADB_CALLS" ]]
export GITHUB_ACTIONS=true MOCK_FOCUS_EXIT=25
run_case standard 25
printf '%s\n' "${FOCUS_COMMAND/Diagnostics=false/Diagnostics=true}" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"
printf '%s\n' \
    '-s emulator-5554 shell getprop ro.boot.qemu' \
    '-s emulator-5554 shell dumpsys -t 2 window' \
    '-s emulator-5554 shell dumpsys -t 2 activity lastanr' \
    '-s emulator-5554 logcat -d -v threadtime ActivityManager:E InputDispatcher:E WindowManager:E *:S' \
    > "$TEST_ROOT/expected-adb"
cmp "$TEST_ROOT/expected-adb" "$MOCK_ADB_CALLS"
grep -q 'Synthetic platform blocker' "$TEST_ROOT/result.log"
grep -q 'Reason: Synthetic launcher ANR' "$TEST_ROOT/result.log"
grep -q 'Synthetic platform input error' "$TEST_ROOT/android/build/logs/instrumentation-platform-failure.log"
export GITHUB_ACTIONS=false
unset MOCK_FOCUS_EXIT

export MOCK_PLAY_EXIT=23
run_case standard 23
printf '%s\n%s\n' "$FOCUS_COMMAND" "$PLAY_COMMAND" > "$TEST_ROOT/expected"
cmp "$TEST_ROOT/expected" "$MOCK_CALLS"
unset MOCK_PLAY_EXIT

for shard in 0 1 2 3 4 5; do
    export HEALTHMD_ANDROID_SHARD_INDEX="$shard" HEALTHMD_ANDROID_SHARD_COUNT=6
    run_case full 0
    printf '%s\n' "$FOCUS_COMMAND" > "$TEST_ROOT/expected"
    if [[ "$shard" == 0 ]]; then
        printf '%s\n' "$DIAGNOSTICS :healthmd-core:connectedDebugAndroidTest --stacktrace" >> "$TEST_ROOT/expected"
    fi
    FLAGS="-Pandroid.testInstrumentationRunnerArguments.numShards=6 -Pandroid.testInstrumentationRunnerArguments.shardIndex=$shard"
    printf '%s\n' "$DIAGNOSTICS $FLAGS :app:connectedPlayDebugAndroidTest --stacktrace" >> "$TEST_ROOT/expected"
    cmp "$TEST_ROOT/expected" "$MOCK_CALLS"
done
run_case standard 0
grep -q "numShards=6.*shardIndex=5.*connectedPlayDebugAndroidTest" "$MOCK_CALLS"
export MOCK_PLAY_EXIT=23
run_case full 23
[[ $(wc -l < "$MOCK_CALLS") -eq 2 ]]
unset MOCK_PLAY_EXIT
for pair in '0 0' '4 4' '-1 4' 'one 4' '00 4' '0 17' '0 9999999999999999999'; do
    read -r HEALTHMD_ANDROID_SHARD_INDEX HEALTHMD_ANDROID_SHARD_COUNT <<< "$pair"
    export HEALTHMD_ANDROID_SHARD_INDEX HEALTHMD_ANDROID_SHARD_COUNT
    run_case full 2
    [[ ! -s "$MOCK_CALLS" ]]
done
unset HEALTHMD_ANDROID_SHARD_COUNT
run_case full 2
[[ ! -s "$MOCK_CALLS" ]]
unset HEALTHMD_ANDROID_SHARD_INDEX
export HEALTHMD_ANDROID_SHARD_COUNT=6
run_case full 2
[[ ! -s "$MOCK_CALLS" ]]
unset HEALTHMD_ANDROID_SHARD_COUNT

printf 'CI instrumentation runner: %s mocked cases passed\n' "$CASES"
