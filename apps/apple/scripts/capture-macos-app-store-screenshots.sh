#!/usr/bin/env bash
set -euo pipefail

SUPPORTED_LOCALES=(en-US de-DE es-ES fr-FR it ja ko nl-NL pt-BR zh-Hans)
# Screens behind the AS_Mac_* boards (sync = MacHomeG, cli = MacCLIG). Override with
# MAC_SCREENSHOT_SCREENS="sync destination readiness activity settings cli".
read -r -a SCREENS <<< "${MAC_SCREENSHOT_SCREENS:-sync cli}"
# The boards show the dark glass UI. MAC_SCREENSHOT_APPEARANCE=light reproduces the earlier light set.
APPEARANCE="${MAC_SCREENSHOT_APPEARANCE:-dark}"
LOCALE="${1:-en-US}"
SCREENSHOT_BUNDLE_ID="com.codybontecou.obsidianhealth.screenshot"
DERIVED_DATA="build/macos-screenshots-dd"
CAPTURE_DESTINATION="screenshots/macos/captures/$LOCALE"
CONTAINER_CAPTURE_ROOT="/Users/${USER}/Library/Containers/$SCREENSHOT_BUNDLE_ID/Data/Documents/mac-app-store-captures/$LOCALE"
TIMEOUT_SECONDS="${MAC_SCREENSHOT_CAPTURE_TIMEOUT:-30}"
SKIP_BUILD="${MAC_SCREENSHOT_SKIP_BUILD:-0}"

cd "$(dirname "$0")/.."
APP_PATH="$(pwd)/$DERIVED_DATA/Build/Products/Debug/Health.md.app"

case "$APPEARANCE" in
  dark) INTERFACE_STYLE="Dark" ;;
  light) INTERFACE_STYLE="Light" ;;
  *) echo "Unsupported appearance: $APPEARANCE (use dark or light)" >&2; exit 1 ;;
esac

if [[ ! " ${SUPPORTED_LOCALES[*]} " =~ " $LOCALE " ]]; then
  echo "Unsupported Mac screenshot locale: $LOCALE" >&2
  exit 1
fi

case "$LOCALE" in
  en-US) APPLE_LANGUAGE="en" ;;
  de-DE) APPLE_LANGUAGE="de" ;;
  es-ES) APPLE_LANGUAGE="es" ;;
  fr-FR) APPLE_LANGUAGE="fr" ;;
  nl-NL) APPLE_LANGUAGE="nl" ;;
  *) APPLE_LANGUAGE="$LOCALE" ;;
esac

if [ "$SKIP_BUILD" != "1" ]; then
  echo "==> Building isolated DEBUG screenshot app"
  xcodebuild \
    -project HealthMd.xcodeproj \
    -scheme HealthMd-macOS \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    build \
    PRODUCT_BUNDLE_IDENTIFIER="$SCREENSHOT_BUNDLE_ID" \
    CODE_SIGN_IDENTITY=- \
    -quiet
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Build did not produce $APP_PATH" >&2
  exit 1
fi

mkdir -p "$CAPTURE_DESTINATION"

for SCREEN in "${SCREENS[@]}"; do
  echo "==> Capturing $LOCALE / $SCREEN"
  SOURCE="$CONTAINER_CAPTURE_ROOT/$SCREEN.png"
  BEFORE_MTIME="0"
  if [ -f "$SOURCE" ]; then
    BEFORE_MTIME="$(stat -f %m "$SOURCE")"
  fi

  open -na "$APP_PATH" --args \
    -MacMarketingCapture 1 \
    -MacMarketingScreen "$SCREEN" \
    -MacMarketingLocale "$LOCALE" \
    -AppleLanguages "($APPLE_LANGUAGE)" \
    -AppleLocale "$LOCALE" \
    -MacMarketingAppearance "$APPEARANCE" \
    -AppleInterfaceStyle "$INTERFACE_STYLE"

  WAITED=0
  while true; do
    if [ -f "$SOURCE" ]; then
      AFTER_MTIME="$(stat -f %m "$SOURCE")"
      if [ "$AFTER_MTIME" -gt "$BEFORE_MTIME" ]; then
        break
      fi
    fi
    sleep 1
    WAITED=$((WAITED + 1))
    if [ "$WAITED" -ge "$TIMEOUT_SECONDS" ]; then
      echo "Timed out waiting for $SOURCE" >&2
      exit 1
    fi
  done

  WIDTH="$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/ { print $2 }')"
  HEIGHT="$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/ { print $2 }')"
  # 1100 x 720 pt window (title bar included) at 2x, the window the boards frame.
  if [ "$WIDTH" != "2200" ] || [ "$HEIGHT" != "1440" ]; then
    echo "Unexpected capture size for $SCREEN: ${WIDTH}x${HEIGHT}" >&2
    exit 1
  fi
  cp "$SOURCE" "$CAPTURE_DESTINATION/$SCREEN.png"
done

echo "Captured ${#SCREENS[@]} native 2200x1440 $APPEARANCE app windows in $CAPTURE_DESTINATION"
