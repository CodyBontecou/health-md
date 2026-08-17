#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: EXPECTED_WEAR_APK_SHA256=<sha256> EXPECTED_WEAR_VERSION_CODE=<integer> \
       EXPECTED_VERSION_NAME=<semantic-version> EXPECTED_PLAY_APP_SIGNING_CERT_SHA256=<sha256> \
       CONFIRM_EXACT_RELEASE_UI=yes \
       CONFIRM_NO_PRODUCTION_HEALTH_VALUES=yes REVIEWER_ID=<independent-reviewer> \
       REVIEW_TICKET=<approval-record-id-or-url> \
       capture-wear-play-screenshot.sh WATCH_SERIAL app|tile

Before running, manually open the exact screen on a physical watch:
  app  - an ordinary release dashboard state
  tile - an installed Health.md Tile rendered by the system host (not its picker preview)

The watch framebuffer must be square and at least 400px. The command does not navigate, inject
health data, frame, mask, scale, crop, or decorate the image.
EOF
  exit 64
}
[[ $# -eq 2 ]] || usage
serial=$1; kind=$2
case "$kind" in app|tile) ;; *) usage ;; esac
expected=${EXPECTED_WEAR_APK_SHA256:-}
expected_signer=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
expected_wear_code=${EXPECTED_WEAR_VERSION_CODE:-}
expected_version=${EXPECTED_VERSION_NAME:-}
[[ "$expected" =~ ^[0-9a-f]{64}$ && "$expected_signer" =~ ^[0-9a-f]{64}$ && "$expected_wear_code" =~ ^[1-9][0-9]*$ && "$expected_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || usage
[[ ${CONFIRM_EXACT_RELEASE_UI:-} == yes && ${CONFIRM_NO_PRODUCTION_HEALTH_VALUES:-} == yes ]] || usage
reviewer=${REVIEWER_ID:-}; review_ticket=${REVIEW_TICKET:-}
[[ -n "$reviewer" && -n "$review_ticket" ]] || usage
adb_bin=${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}
[[ -x "$adb_bin" ]] || { echo "adb not found: $adb_bin" >&2; exit 69; }
"$adb_bin" -s "$serial" get-state 2>/dev/null | grep -qx device || { echo "Watch not ready: $serial" >&2; exit 69; }
package=com.healthmd.android
package_dump=$(mktemp); apk=$(mktemp); raw=$(mktemp); trap 'rm -f "$package_dump" "$apk" "$raw"' EXIT
"$adb_bin" -s "$serial" shell dumpsys package "$package" >"$package_dump"
code=$(sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' "$package_dump" | head -1)
version=$(sed -n 's/.*versionName=\([^[:space:]]*\).*/\1/p' "$package_dump" | head -1)
[[ "$code" == "$expected_wear_code" ]] || { echo "Wear versionCode must be $expected_wear_code; got $code" >&2; exit 65; }
[[ "$version" == "$expected_version" ]] || { echo "Wear versionName must be $expected_version; got $version" >&2; exit 65; }
apk_path=$("$adb_bin" -s "$serial" shell pm path "$package" | tr -d '\r' | sed -n 's/^package:\(.*\/base\.apk\)$/\1/p' | head -1)
[[ -n "$apk_path" ]] || { echo 'Installed Wear base APK unavailable' >&2; exit 65; }
"$adb_bin" -s "$serial" pull "$apk_path" "$apk" >/dev/null
actual=$(shasum -a 256 "$apk" | awk '{print $1}')
[[ "$actual" == "$expected" ]] || { echo "Installed Wear APK digest mismatch: $actual" >&2; exit 65; }
apksigner=${APKSIGNER:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/apksigner}
[[ -x "$apksigner" ]] || { echo "apksigner unavailable: $apksigner" >&2; exit 69; }
signer_output=$($apksigner verify --print-certs "$apk")
actual_signer=$(printf '%s\n' "$signer_output" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1 | tr '[:upper:]' '[:lower:]')
[[ "$actual_signer" == "$expected_signer" ]] || { echo "Installed Wear Play signer mismatch: $actual_signer" >&2; exit 65; }

# `exec-out` preserves exact PNG bytes emitted by the device without host-side image transforms.
"$adb_bin" -s "$serial" exec-out screencap -p >"$raw"
output="play-store/wear/screenshots/wear-$kind.png"
python3 - "$raw" "$output" <<'PY'
from pathlib import Path
import shutil, struct, sys, zlib
source, output = map(Path, sys.argv[1:])
data = source.read_bytes()
if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("watch screencap is not PNG")
length = struct.unpack(">I", data[8:12])[0]
if data[12:16] != b"IHDR" or length != 13:
    raise SystemExit("watch screencap has invalid IHDR")
payload = data[16:29]
if zlib.crc32(b"IHDR" + payload) & 0xffffffff != struct.unpack(">I", data[29:33])[0]:
    raise SystemExit("watch screencap IHDR CRC mismatch")
width, height = struct.unpack(">II", payload[:8])
if width != height or width < 400:
    raise SystemExit(f"physical watch framebuffer must be square and >=400px; got {width}x{height}")
output.parent.mkdir(parents=True, exist_ok=True)
if output.exists():
    raise SystemExit(f"refusing to overwrite {output}")
shutil.copyfile(source, output)
print(f"Captured exact {width}x{height} framebuffer: {output}")
PY

# Bind visual-review evidence to the installed binary without placing sidecars in Play assets.
evidence=".pi/evidence/wear-play-screenshots/$kind"
[[ ! -e "$evidence/receipt.txt" ]] || { echo "refusing to overwrite $evidence evidence" >&2; exit 73; }
mkdir -p "$evidence"
printf 'captured_utc=%s\nkind=%s\nwatch_serial=%s\nversion_code=%s\nversion_name=%s\nwear_base_apk_sha256=%s\nplay_app_signing_cert_sha256=%s\nimage_sha256=%s\nexact_release_ui_confirmed=yes\nno_production_health_values_confirmed=yes\nreviewer_id=%s\nreview_ticket=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$kind" "$serial" "$code" "$version" "$actual" "$actual_signer" \
  "$(shasum -a 256 "$output" | awk '{print $1}')" "$reviewer" "$review_ticket" >"$evidence/receipt.txt"
printf '%s\n' "$signer_output" >"$evidence/signer.txt"
cp "$package_dump" "$evidence/package.txt"
(
  cd "$evidence"
  shasum -a 256 receipt.txt signer.txt package.txt >SHA256SUMS
)
echo "Manual visual review is still required before running validate-wear-play-assets.py"
