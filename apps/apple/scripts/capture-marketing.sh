#!/usr/bin/env bash
#
# Marketing screenshot capture for Health.md
# Builds once, installs to a simulator, then relaunches per locale
# with -MarketingCapture 1 and pulls PNGs from the app sandbox.

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

LOCALES=(en de es fr it ja ko nl pt-BR zh-Hans)
BUNDLE_ID="com.codybontecou.obsidianhealth"
SCHEME="HealthMd"
PROJECT="HealthMd.xcodeproj"
SIM_NAME="iPhone 16 Pro Max"
TIMEOUT=120

# ============================================================================
# INTERNALS
# ============================================================================

DERIVED="build/marketing-dd"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
OUT_ROOT="marketing"

cd "$(dirname "$0")/.."

PROJECT_FLAG="-project $PROJECT"

echo "==> Ensuring $SIM_NAME simulator exists and is booted"
DEVICE_ID=$(xcrun simctl list devices available -j 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    if 'iOS' not in runtime:
        continue
    for d in devices:
        if d['name'] == '$SIM_NAME':
            print(d['udid'])
            sys.exit()
" || true)

if [ -z "${DEVICE_ID:-}" ]; then
    echo "Creating $SIM_NAME simulator"
    RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data['runtimes']:
    if r.get('platform') == 'iOS' and r.get('isAvailable'):
        print(r['identifier']); sys.exit()
")
    DEVICE_TYPE=$(xcrun simctl list devicetypes -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for d in data['devicetypes']:
    if d['name'] == '$SIM_NAME':
        print(d['identifier']); sys.exit()
")
    DEVICE_ID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$DEVICE_ID" || true

echo "==> Building $SCHEME (Debug) for $SIM_NAME"
xcodebuild \
    $PROJECT_FLAG \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "id=$DEVICE_ID" \
    -derivedDataPath "$DERIVED" \
    build \
    -quiet

if [ ! -d "$APP_PATH" ]; then
    echo "Build did not produce $APP_PATH" >&2
    echo "Check that SCHEME and PROJECT are correct." >&2
    exit 1
fi

echo "==> Installing $APP_PATH"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

mkdir -p "$OUT_ROOT"

for L in "${LOCALES[@]}"; do
    echo "==> Capturing locale: $L"

    xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 0.5

    # Clear any prior sandbox output for this locale
    SBOX=$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)
    rm -rf "$SBOX/Documents/marketing/$L"

    # Launch with marketing capture mode and locale override.
    # -MarketingLocale passes the exact locale code for folder naming.
    # AppleLanguages requires the plist-array literal format with parens.
    xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" \
        -MarketingCapture 1 \
        -MarketingLocale "$L" \
        -AppleLanguages "($L)" \
        -AppleLocale "$L" > /dev/null

    # Wait for the coordinator's _done sentinel.
    WAITED=0
    SENTINEL="$SBOX/Documents/marketing/$L/_done"
    while [ ! -f "$SENTINEL" ]; do
        sleep 1
        WAITED=$((WAITED + 1))
        if [ "$WAITED" -gt "$TIMEOUT" ]; then
            echo "Timeout waiting for $SENTINEL after ${TIMEOUT}s" >&2
            echo "The app may have crashed. Check:" >&2
            echo "  ~/Library/Logs/DiagnosticReports/ for crash logs" >&2
            echo "  Console.app filtered to the app's process name" >&2
            exit 1
        fi
    done

    # Pull output
    rm -rf "$OUT_ROOT/$L"
    cp -R "$SBOX/Documents/marketing/$L" "$OUT_ROOT/$L"
    rm -f "$OUT_ROOT/$L/_done"
    echo "    -> $(find "$OUT_ROOT/$L" -name '*.png' | wc -l | tr -d ' ') PNGs written to $OUT_ROOT/$L"
done

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true

echo ""
echo "Done. Output in $OUT_ROOT/"
find "$OUT_ROOT" -name "*.png" | sort
