#!/usr/bin/env bash
# Keep flavor-specific instrumentation while avoiding a second full display matrix.
set -euo pipefail

if [[ $# -ne 0 ]]; then
    echo "Usage: HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX=standard|full $0" >&2
    exit 2
fi
# Standalone/manual use stays complete. CI must explicitly request the reduced
# PR matrix; an empty selection must not silently weaken qualification.
MATRIX="${HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX-full}"
case "$MATRIX" in
    standard|full) ;;
    *)
        echo "HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX must be standard or full; received '$MATRIX'" >&2
        exit 2
        ;;
esac

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ANDROID_DIR"

capture_focus_failure() {
    local status=$?
    # Only the disposable hosted AVD may expose platform window identities. Do
    # not collect window titles or other apps' state on a developer's device.
    if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
        echo 'Hosted AVD focus at instrumentation failure:' >&2
        adb -s emulator-5554 shell dumpsys window windows \
            | sed -n '/mCurrentFocus=/p; /mFocusedApp=/p' >&2 || true
    fi
    exit "$status"
}
trap capture_focus_failure ERR

# Only the hosted emulator is allowed to retain the platform focus identity at
# the point of failure, before the activity rule tears down the window.
CI_INPUT_DIAGNOSTICS="-Pandroid.testInstrumentationRunnerArguments.healthmd.ciInputDiagnostics=${GITHUB_ACTIONS:-false}"

# Fail early on the actual native input admission contract. A focus blocker
# otherwise repeats through hundreds of fixture tests before surfacing.
./gradlew "$CI_INPUT_DIAGNOSTICS" :app:connectedFdroidDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=com.healthmd.presentation.accessibility.NativeInputReadinessTest \
    --stacktrace

# No class/package filter: all core, shared app, and flavor-specific test methods run.
./gradlew "$CI_INPUT_DIAGNOSTICS" :healthmd-core:connectedDebugAndroidTest :app:connectedPlayDebugAndroidTest --stacktrace

# The scope argument is confined to this separate invocation. Full qualification
# omits it so both flavors exercise all ten viewports, just like standalone runs.
if [[ "$MATRIX" == standard ]]; then
    ./gradlew "$CI_INPUT_DIAGNOSTICS" :app:connectedFdroidDebugAndroidTest \
        -Pandroid.testInstrumentationRunnerArguments.healthmd.accessibility.matrix=smoke --stacktrace
else
    ./gradlew "$CI_INPUT_DIAGNOSTICS" :app:connectedFdroidDebugAndroidTest --stacktrace
fi
