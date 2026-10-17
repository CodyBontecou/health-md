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

# No class/package filter: all core, shared app, and flavor-specific test methods run.
./gradlew :healthmd-core:connectedDebugAndroidTest :app:connectedPlayDebugAndroidTest --stacktrace

# The scope argument is confined to this separate invocation. Full qualification
# omits it so both flavors exercise all ten viewports, just like standalone runs.
if [[ "$MATRIX" == standard ]]; then
    ./gradlew :app:connectedFdroidDebugAndroidTest \
        -Pandroid.testInstrumentationRunnerArguments.healthmd.accessibility.matrix=smoke --stacktrace
else
    ./gradlew :app:connectedFdroidDebugAndroidTest --stacktrace
fi
