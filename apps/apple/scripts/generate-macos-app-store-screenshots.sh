#!/usr/bin/env bash
set -euo pipefail

LOCALE="${1:-en-US}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAPTURES="$ROOT/screenshots/macos/captures/$LOCALE"
OUTPUT="$ROOT/fastlane/screenshots-macos/$LOCALE"
REVIEW="$ROOT/screenshots/macos/review/$LOCALE"

if [ "${MAC_SCREENSHOT_SKIP_CAPTURE:-0}" != "1" ]; then
  "$ROOT/scripts/capture-macos-app-store-screenshots.sh" "$LOCALE"
fi

swift "$ROOT/scripts/compose-macos-app-store-screenshots.swift" \
  --copy "$ROOT/screenshots/macos/copy.json" \
  --locale "$LOCALE" \
  --captures "$CAPTURES" \
  --output "$OUTPUT" \
  --review "$REVIEW"

if [ "$LOCALE" = "en-US" ] && [ -f "$OUTPUT/04_track_every_export.png" ]; then
  mv "$OUTPUT/04_track_every_export.png" "$REVIEW/previous_04_track_every_export.png"
fi

EXPECTED_FILES=(
  01_sync_with_iphone.png
  02_export_health_data.png
  03_automate_every_export.png
  04_preview_before_export.png
  05_configure_your_app.png
)

PNG_COUNT="$(find "$OUTPUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
if [ "$PNG_COUNT" != "5" ]; then
  echo "Expected exactly five final PNGs in $OUTPUT; found $PNG_COUNT" >&2
  exit 1
fi

for FILE in "${EXPECTED_FILES[@]}"; do
  PATH_TO_IMAGE="$OUTPUT/$FILE"
  if [ ! -f "$PATH_TO_IMAGE" ]; then
    echo "Missing ordered screenshot: $PATH_TO_IMAGE" >&2
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

VALIDATION_OUTPUT="$(asc screenshots validate \
  --path "$OUTPUT" \
  --device-type DESKTOP \
  --output json)"
printf '%s\n' "$VALIDATION_OUTPUT" \
  | sed "s|$ROOT/||g" \
  | tee "$REVIEW/asc-validation.json"

echo "Generated and validated $LOCALE Mac App Store screenshots. No upload was performed."
