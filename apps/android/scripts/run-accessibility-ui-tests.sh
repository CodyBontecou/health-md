#!/usr/bin/env bash
# Exercise synthetic UI on the local Pixel without connected-test cleanup uninstalling
# the app (and its data). Optionally copy screenshots to the supplied host directory.
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/platform-tools/adb"
export ANDROID_SERIAL="${ANDROID_SERIAL:-2C061FDH200CJN}"
SCREENSHOTS="${1:-}"
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [screenshot-output-directory]" >&2
    exit 2
fi
if [[ -n "$SCREENSHOTS" ]]; then
    mkdir -p "$SCREENSHOTS"
    SCREENSHOTS="$(cd "$SCREENSHOTS" && pwd)"
fi

# Check the selected device before building, and never let a Gradle install task select
# another attached device. Every installation/instrumentation command targets this serial.
if [[ "$("$ADB" -s "$ANDROID_SERIAL" get-state 2>/dev/null)" != "device" ]]; then
    echo "Device $ANDROID_SERIAL is unavailable. Connect and authorize it before running UI tests." >&2
    exit 1
fi

cd "$ANDROID_DIR"
./gradlew :app:assemblePlayDebug :app:assemblePlayDebugAndroidTest --console=plain
"$ADB" -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/play/debug/app-play-debug.apk
"$ADB" -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/androidTest/play/debug/app-play-debug-androidTest.apk
mkdir -p app/build/reports/accessibility
LOG="app/build/reports/accessibility/instrumentation.log"
CLASSES=(
    com.healthmd.presentation.accessibility.LargeDisplayAccessibilityTest
    com.healthmd.presentation.accessibility.MetricSelectionAccessibilityTest
    com.healthmd.presentation.accessibility.ProfileScheduleAccessibilityTest
    com.healthmd.presentation.accessibility.FormatCustomizationAccessibilityTest
    com.healthmd.presentation.accessibility.FrontmatterCustomizationAccessibilityTest
    com.healthmd.presentation.accessibility.SecondaryControlsAccessibilityTest
    com.healthmd.presentation.common.ConfigurationProtectionTest
)
# 40 parameterized methods x 10 displays, plus two protection regressions. Keep this
# inventory in sync with intentional test additions; a partial/stale APK is not a pass.
EXPECTED_TESTS=402
CLASS_FILTER="$(IFS=,; printf '%s' "${CLASSES[*]}")"
ARGS=(-w -e class "$CLASS_FILTER")
if [[ -n "$SCREENSHOTS" ]]; then
    ARGS+=(-e healthmd.captureAccessibility true)
fi
"$ADB" -s "$ANDROID_SERIAL" shell am instrument "${ARGS[@]}" \
    com.healthmd.android.test/androidx.test.runner.AndroidJUnitRunner | tee "$LOG"
# am instrument can exit zero for runner failures, empty filters, or a partial selection.
if grep -Eq '(^FAILURES!!!|^INSTRUMENTATION_(FAILED|ABORTED)|^Error:|INSTRUMENTATION_RESULT: (shortMsg|longMsg)=)' "$LOG" ||
    ! grep -Eq "^OK \\($EXPECTED_TESTS tests?\\)" "$LOG"; then
    echo "Accessibility UI validation failed or did not execute all $EXPECTED_TESTS tests. See $ANDROID_DIR/$LOG" >&2
    exit 1
fi

if [[ -n "$SCREENSHOTS" ]]; then
    "$ADB" -s "$ANDROID_SERIAL" exec-out run-as com.healthmd.android \
        tar -C cache/accessibility-screenshots -cf - . | tar -xf - -C "$SCREENSHOTS"
    echo "Screenshots: $SCREENSHOTS"
fi
