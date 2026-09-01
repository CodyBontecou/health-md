#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ANDROID_ROOT/../.." && pwd)"
CLI_ROOT="$REPO_ROOT/apps/cli"
if [[ -z "${ADB:-}" ]]; then
    if command -v adb >/dev/null 2>&1; then
        ADB="$(command -v adb)"
    else
        ADB="$HOME/Library/Android/sdk/platform-tools/adb"
    fi
fi
SERIAL="${ANDROID_SERIAL:-2C061FDH200CJN}"
HOST="${HEALTHMD_ANDROID_E2E_HOST:-}"
BIND_ADDRESS="${HEALTHMD_ANDROID_E2E_BIND:-0.0.0.0}"
PORT="${HEALTHMD_ANDROID_E2E_PORT:-18648}"
PAIRING_CODE="${HEALTHMD_ANDROID_E2E_PAIRING_CODE:-}"
LISTENER_TEST="accepts_android_ui_pair_reconnect_disconnect_status_and_repair"
INSTRUMENTATION_TEST="com.healthmd.presentation.directcli.DirectCliLiveE2ETest"
E2E_APP_ID="com.healthmd.android.e2e"
E2E_TEST_APP_ID="com.healthmd.android.e2e.test"

if [[ -z "$HOST" ]]; then
    cat >&2 <<'USAGE'
Set HEALTHMD_ANDROID_E2E_HOST to an address the Android device can reach.

Physical Pixel 7 LAN example:
  HEALTHMD_ANDROID_E2E_HOST=192.168.1.20 \
    apps/android/scripts/run-direct-cli-ui-e2e.sh

Android emulator example:
  ANDROID_SERIAL=emulator-5554 HEALTHMD_ANDROID_E2E_HOST=10.0.2.2 \
    apps/android/scripts/run-direct-cli-ui-e2e.sh
USAGE
    exit 2
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
    echo "HEALTHMD_ANDROID_E2E_PORT must be an integer from 1 through 65535." >&2
    exit 2
fi

if [[ -z "$PAIRING_CODE" ]]; then
    PAIRING_CODE="$(python3 - <<'PY'
import secrets
print(''.join(str(secrets.randbelow(10)) for _ in range(20)))
PY
)"
fi
if [[ ! "$PAIRING_CODE" =~ ^[0-9]{20}$ ]]; then
    echo "HEALTHMD_ANDROID_E2E_PAIRING_CODE must contain exactly 20 ASCII digits." >&2
    exit 2
fi

if [[ ! -x "$ADB" ]]; then
    echo "adb was not found at $ADB. Set ADB to the Android SDK adb path." >&2
    exit 2
fi

NO_COLOR=1 TERM=dumb timeout 15 "$ADB" -s "$SERIAL" get-state </dev/null \
    | grep -qx "device" || {
        echo "Android device $SERIAL is not connected and authorized." >&2
        exit 1
    }
MODEL="$(NO_COLOR=1 TERM=dumb timeout 15 "$ADB" -s "$SERIAL" shell getprop ro.product.model </dev/null | tr -d '\r')"

echo "Prebuilding isolated Direct CLI UI E2E artifacts before opening the bounded listener."
(
    cd "$ANDROID_ROOT"
    NO_COLOR=1 TERM=dumb timeout 600 ./gradlew \
        --no-daemon \
        -Pkotlin.compiler.execution.strategy=in-process \
        -PhealthmdInstrumentedTestBuildType=e2e \
        :app:assemblePlayE2e \
        :app:assemblePlayE2eAndroidTest \
        --stacktrace </dev/null
)

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/healthmd-android-ui-e2e.XXXXXX")"
RUST_LOG="$TEMP_DIR/rust-listener.log"
LISTENER_PID=""

cleanup() {
    local exit_status=$?
    trap - EXIT INT TERM
    if [[ -n "$LISTENER_PID" ]] && kill -0 "$LISTENER_PID" 2>/dev/null; then
        kill "$LISTENER_PID" 2>/dev/null || true
        wait "$LISTENER_PID" 2>/dev/null || true
    fi
    NO_COLOR=1 TERM=dumb timeout 20 "$ADB" -s "$SERIAL" uninstall "$E2E_TEST_APP_ID" \
        </dev/null >/dev/null 2>&1 || true
    NO_COLOR=1 TERM=dumb timeout 20 "$ADB" -s "$SERIAL" uninstall "$E2E_APP_ID" \
        </dev/null >/dev/null 2>&1 || true
    rm -rf "$TEMP_DIR"
    exit "$exit_status"
}
trap cleanup EXIT INT TERM

# Remove any interrupted prior run before opening the listener, so a stale isolated service cannot
# consume the first expected connection. Production package data is never touched.
NO_COLOR=1 TERM=dumb timeout 20 "$ADB" -s "$SERIAL" uninstall "$E2E_TEST_APP_ID" \
    </dev/null >/dev/null 2>&1 || true
NO_COLOR=1 TERM=dumb timeout 20 "$ADB" -s "$SERIAL" uninstall "$E2E_APP_ID" \
    </dev/null >/dev/null 2>&1 || true

echo "Running isolated Direct CLI UI E2E on $MODEL ($SERIAL), target $E2E_APP_ID."
echo "The gate covers wrong-code rejection, pair, reconnect, disconnect, status, forget, and re-pair."

(
    cd "$CLI_ROOT"
    HEALTHMD_ANDROID_UI_E2E_BIND="$BIND_ADDRESS" \
    HEALTHMD_ANDROID_UI_E2E_PORT="$PORT" \
    HEALTHMD_ANDROID_UI_E2E_PAIRING_CODE="$PAIRING_CODE" \
    NO_COLOR=1 TERM=dumb timeout 600 cargo test \
        --locked \
        -p healthmd-client \
        --test android_live_listener \
        "$LISTENER_TEST" \
        -- --ignored --nocapture </dev/null
) >"$RUST_LOG" 2>&1 &
LISTENER_PID=$!

ready=false
for _ in $(seq 1 300); do
    if grep -q "ANDROID_UI_E2E_LISTENER_READY:$PORT" "$RUST_LOG"; then
        ready=true
        break
    fi
    if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
        echo "Rust Direct CLI UI E2E listener exited before becoming ready." >&2
        head -200 "$RUST_LOG" >&2
        wait "$LISTENER_PID" || true
        exit 1
    fi
    sleep 1
done
if [[ "$ready" != true ]]; then
    echo "Rust Direct CLI UI E2E listener did not become ready within 300 seconds." >&2
    head -200 "$RUST_LOG" >&2
    exit 1
fi

set +e
(
    cd "$ANDROID_ROOT"
    ANDROID_SERIAL="$SERIAL" NO_COLOR=1 TERM=dumb timeout 600 ./gradlew \
        --no-daemon \
        -Pkotlin.compiler.execution.strategy=in-process \
        -PhealthmdInstrumentedTestBuildType=e2e \
        :app:connectedPlayE2eAndroidTest \
        -Pandroid.testInstrumentationRunnerArguments.class="$INSTRUMENTATION_TEST" \
        -Pandroid.testInstrumentationRunnerArguments.directCliE2E=true \
        -Pandroid.testInstrumentationRunnerArguments.directCliHost="$HOST" \
        -Pandroid.testInstrumentationRunnerArguments.directCliPort="$PORT" \
        -Pandroid.testInstrumentationRunnerArguments.directCliPairingCode="$PAIRING_CODE" \
        --stacktrace </dev/null
)
android_status=$?
set -e
if (( android_status != 0 )); then
    echo "Android Direct CLI UI E2E failed; health-free Rust listener diagnostics follow." >&2
    head -300 "$RUST_LOG" >&2
    exit "$android_status"
fi

set +e
wait "$LISTENER_PID"
listener_status=$?
set -e
LISTENER_PID=""
if (( listener_status != 0 )); then
    echo "Rust Direct CLI UI E2E listener failed." >&2
    head -300 "$RUST_LOG" >&2
    exit "$listener_status"
fi

required_markers=(
    ANDROID_UI_E2E_WRONG_CODE_REJECTED
    ANDROID_UI_E2E_PAIRED
    ANDROID_UI_E2E_DISCONNECTED
    ANDROID_UI_E2E_STATUS_COMPLETE
    ANDROID_UI_E2E_COMPLETE
)
for marker in "${required_markers[@]}"; do
    if ! grep -q "$marker" "$RUST_LOG"; then
        echo "Rust listener did not report required marker: $marker" >&2
        head -300 "$RUST_LOG" >&2
        exit 1
    fi
done

echo "Direct CLI UI E2E passed with health-free status evidence only."
