#!/usr/bin/env bash
# Synthetic content + cold/warm disclosure routing. Never clear or uninstall the owner app.
set -euo pipefail
ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/platform-tools/adb"
export ANDROID_SERIAL="${ANDROID_SERIAL:-2C061FDH200CJN}"
[[ "$ANDROID_SERIAL" == "2C061FDH200CJN" ]] || { echo "Use the configured Pixel 7." >&2; exit 1; }
[[ "$("$ADB" -s "$ANDROID_SERIAL" get-state)" == "device" ]]
cd "$ANDROID_DIR"
./gradlew :app:installPlayDebug :app:assemblePlayDebugAndroidTest --console=plain
"$ADB" -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/androidTest/play/debug/app-play-debug-androidTest.apk
mkdir -p app/build/reports/myself-claim
LOG=app/build/reports/myself-claim/instrumentation.log
"$ADB" -s "$ANDROID_SERIAL" shell am instrument -w \
  -e class com.healthmd.myselfclaim.MyselfClaimUiTest,com.healthmd.myselfclaim.MyselfClaimNavigationTest,com.healthmd.myselfclaim.MyselfClaimAccessibilityTest \
  -e healthmd.captureAccessibility true \
  com.healthmd.android.test/androidx.test.runner.AndroidJUnitRunner | tee "$LOG"
if grep -Eq '(^FAILURES!!!|^INSTRUMENTATION_(FAILED|ABORTED)|^Error:|INSTRUMENTATION_RESULT: (shortMsg|longMsg)=)' "$LOG" ||
   ! grep -Eq '^OK \(13 tests\)' "$LOG"; then
  echo "Claim UI validation failed or did not execute all 13 cases. See $LOG" >&2
  exit 1
fi
