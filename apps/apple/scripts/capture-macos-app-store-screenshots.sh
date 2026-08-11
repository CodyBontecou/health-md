#!/usr/bin/env bash
set -euo pipefail

SUPPORTED_LOCALES=(en-US de-DE es-ES fr-FR it ja ko nl-NL pt-BR zh-Hans)
SCREENS=(sync destination readiness activity settings)
LOCALE="${1:-en-US}"
SCREENSHOT_BUNDLE_ID="com.codybontecou.obsidianhealth.screenshot"
DERIVED_DATA="build/macos-screenshots-dd"
CAPTURE_DESTINATION="screenshots/macos/captures/$LOCALE"
CONTAINER_CAPTURE_ROOT="/Users/${USER}/Library/Containers/$SCREENSHOT_BUNDLE_ID/Data/Documents/mac-app-store-captures/$LOCALE"
TIMEOUT_SECONDS="${MAC_SCREENSHOT_CAPTURE_TIMEOUT:-30}"
SKIP_BUILD="${MAC_SCREENSHOT_SKIP_BUILD:-0}"

cd "$(dirname "$0")/.."
APP_PATH="$(pwd)/$DERIVED_DATA/Build/Products/Debug/Health.md.app"

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
    -AppleInterfaceStyle Light

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
  if [ "$WIDTH" != "2200" ] || [ "$HEIGHT" != "1464" ]; then
    echo "Unexpected capture size for $SCREEN: ${WIDTH}x${HEIGHT}" >&2
    exit 1
  fi
  cp "$SOURCE" "$CAPTURE_DESTINATION/$SCREEN.png"
done

echo "Captured five native 2200x1464 app windows in $CAPTURE_DESTINATION"
