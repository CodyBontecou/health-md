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

cd "$ANDROID_DIR"
./gradlew :app:installPlayDebug :app:assemblePlayDebugAndroidTest --console=plain
"$ADB" -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/androidTest/play/debug/app-play-debug-androidTest.apk
mkdir -p app/build/reports/accessibility
LOG="app/build/reports/accessibility/instrumentation.log"
ARGS=(-w -e class com.healthmd.presentation.accessibility.LargeDisplayAccessibilityTest,com.healthmd.presentation.common.ConfigurationProtectionTest)
if [[ -n "$SCREENSHOTS" ]]; then
    ARGS+=(-e healthmd.captureAccessibility true)
fi
"$ADB" -s "$ANDROID_SERIAL" shell am instrument "${ARGS[@]}" \
    com.healthmd.android.test/androidx.test.runner.AndroidJUnitRunner | tee "$LOG"
# am instrument can exit zero for failures or an empty filter: require a nonempty success.
grep -Eq '^OK \([1-9][0-9]* tests?\)' "$LOG"

if [[ -n "$SCREENSHOTS" ]]; then
    "$ADB" -s "$ANDROID_SERIAL" exec-out run-as com.healthmd.android \
        tar -C cache/accessibility-screenshots -cf - . | tar -xf - -C "$SCREENSHOTS"
    echo "Screenshots: $SCREENSHOTS"
fi
