#!/usr/bin/env bash
# Run instrumentation for the distributed Play phone app and shared core.
set -euo pipefail

if [[ $# -ne 0 ]]; then
    echo "Usage: HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX=standard|full $0" >&2
    exit 2
fi
# Retain the CI mode interface; both modes now run the complete Play matrix.
# An empty or invalid selection still fails.
MATRIX="${HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX-full}"
case "$MATRIX" in
    standard|full) ;;
    *)
        echo "HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX must be standard or full; received '$MATRIX'" >&2
        exit 2
        ;;
esac

# Both values must be explicit; standalone runs remain unsharded.
SHARD_ARGS=()
if [[ ${HEALTHMD_ANDROID_SHARD_INDEX+x} == x || ${HEALTHMD_ANDROID_SHARD_COUNT+x} == x ]]; then
    SHARD_INDEX="${HEALTHMD_ANDROID_SHARD_INDEX:-}"
    SHARD_COUNT="${HEALTHMD_ANDROID_SHARD_COUNT:-}"
    if [[ ! "$SHARD_INDEX" =~ ^(0|[1-9][0-9]*)$ || ! "$SHARD_COUNT" =~ ^[1-9][0-9]*$ ]] \
        || (( ${#SHARD_INDEX} > 2 || ${#SHARD_COUNT} > 2 )) \
        || (( 10#$SHARD_COUNT > 16 || 10#$SHARD_INDEX >= 10#$SHARD_COUNT )); then
        echo 'Explicit shard index/count must satisfy 0 <= index < count <= 16' >&2
        exit 2
    fi
    SHARD_ARGS=(
        "-Pandroid.testInstrumentationRunnerArguments.numShards=$SHARD_COUNT"
        "-Pandroid.testInstrumentationRunnerArguments.shardIndex=$SHARD_INDEX"
    )
fi

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ANDROID_DIR"

capture_focus_failure() {
    local status=$?
    # Only the disposable hosted AVD may expose platform window identities. Do
    # not collect window titles or other apps' state on a developer's device.
    if [[ "${GITHUB_ACTIONS:-}" == true ]] && \
        [[ "$(timeout 10 adb -s emulator-5554 shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r')" == 1 ]] && \
        mkdir -p build/logs; then
        # A launcher can ANR after HOME readiness and before instrumentation.
        # Retain its platform reason, rather than guessing from a focus failure.
        # Diagnostics neither recover a running test nor change its exit status.
        {
            echo 'Hosted AVD focus at instrumentation failure:'
            timeout 10 adb -s emulator-5554 shell dumpsys -t 2 window \
                | sed -n '/mCurrentFocus=/p; /mFocusedApp=/p' || true
            echo 'Last platform ANR:'
            timeout 10 adb -s emulator-5554 shell dumpsys -t 2 activity lastanr \
                | head -n 160 || true
            echo 'Recent platform input errors:'
            timeout 10 adb -s emulator-5554 logcat -d -v threadtime \
                'ActivityManager:E' 'InputDispatcher:E' 'WindowManager:E' '*:S' \
                | tail -n 160 || true
        } > build/logs/instrumentation-platform-failure.log 2>&1 || true
        cat build/logs/instrumentation-platform-failure.log >&2 || true
    fi
    exit "$status"
}
trap capture_focus_failure ERR

# Only the hosted emulator is allowed to retain the platform focus identity at
# the point of failure, before the activity rule tears down the window.
CI_INPUT_DIAGNOSTICS="-Pandroid.testInstrumentationRunnerArguments.healthmd.ciInputDiagnostics=${GITHUB_ACTIONS:-false}"

# Fail early on the actual native input admission contract. A focus blocker
# otherwise repeats through hundreds of fixture tests before surfacing.
./gradlew "$CI_INPUT_DIAGNOSTICS" :app:connectedPlayDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=com.healthmd.presentation.accessibility.NativeInputReadinessTest \
    --stacktrace

# No class/package filter: all core, shared app, and flavor-specific test methods run.
if [[ ${HEALTHMD_ANDROID_SHARD_COUNT+x} != x ]]; then
    ./gradlew "$CI_INPUT_DIAGNOSTICS" :healthmd-core:connectedDebugAndroidTest :app:connectedPlayDebugAndroidTest --stacktrace
else
    # Core has two cases: run them once, without filtering, on shard zero.
    if [[ "$SHARD_INDEX" == 0 ]]; then
        ./gradlew "$CI_INPUT_DIAGNOSTICS" :healthmd-core:connectedDebugAndroidTest --stacktrace
    fi
    ./gradlew "$CI_INPUT_DIAGNOSTICS" "${SHARD_ARGS[@]}" :app:connectedPlayDebugAndroidTest --stacktrace
fi

# F-Droid instrumentation is paused while that build is not distributed.
