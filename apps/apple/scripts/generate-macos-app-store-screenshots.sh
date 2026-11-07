#!/usr/bin/env bash
# Captures the Mac app (unless MAC_SCREENSHOT_SKIP_CAPTURE=1), lays the captures into the
# AS_Mac_* boards and validates the result. Never uploads.
set -euo pipefail

LOCALE="${1:-en-US}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPY="$ROOT/screenshots/macos/copy.json"
CAPTURES="$ROOT/screenshots/macos/captures/$LOCALE"
OUTPUT="$ROOT/fastlane/screenshots-macos/$LOCALE"
REVIEW="$ROOT/screenshots/macos/review/$LOCALE"

if [ "${MAC_SCREENSHOT_SKIP_CAPTURE:-0}" != "1" ]; then
  "$ROOT/scripts/capture-macos-app-store-screenshots.sh" "$LOCALE"
fi

# The board set replaces whatever slides this locale had; compose into a fresh folder first so a
# failed run leaves the committed slides untouched.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

swift "$ROOT/scripts/app-store-screenshots/compose.swift" \
  --copy "$COPY" \
  --locale "$LOCALE" \
  --captures "$CAPTURES" \
  --output "$STAGING"

EXPECTED_FILES=()
while IFS= read -r FILE; do EXPECTED_FILES+=("$FILE"); done < <(
  python3 -c 'import json,sys; [print(s["output"]) for s in json.load(open(sys.argv[1]))["slides"]]' "$COPY"
)

for FILE in "${EXPECTED_FILES[@]}"; do
  PATH_TO_IMAGE="$STAGING/$FILE"
  if [ ! -f "$PATH_TO_IMAGE" ]; then
    echo "Missing ordered screenshot: $FILE" >&2
    exit 1
  fi
  WIDTH="$(sips -g pixelWidth "$PATH_TO_IMAGE" | awk '/pixelWidth/ { print $2 }')"
  HEIGHT="$(sips -g pixelHeight "$PATH_TO_IMAGE" | awk '/pixelHeight/ { print $2 }')"
  PROFILE="$(sips -g profile "$PATH_TO_IMAGE" | awk -F': ' '/profile/ { print $2 }')"
  if [ "$WIDTH" != "2880" ] || [ "$HEIGHT" != "1800" ] || [ "$PROFILE" != "sRGB IEC61966-2.1" ]; then
    echo "Invalid final image $FILE: ${WIDTH}x${HEIGHT}, profile=$PROFILE" >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT" "$REVIEW"
find "$OUTPUT" -maxdepth 1 -type f -name '*.png' -delete
cp "$STAGING"/*.png "$OUTPUT/"

VALIDATION_OUTPUT="$(asc screenshots validate \
  --path "$OUTPUT" \
  --device-type DESKTOP \
  --output json)"
printf '%s\n' "$VALIDATION_OUTPUT" \
  | sed "s|$ROOT/||g" \
  | tee "$REVIEW/asc-validation.json"

echo "Generated and validated $LOCALE Mac App Store screenshots. No upload was performed."
