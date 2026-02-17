#!/bin/sh
set -eu

# AppsFlyer is intentionally disabled for Debug/local builds.
if [ "${CONFIGURATION:-}" = "Debug" ]; then
  exit 0
fi

SERVICE_NAME="healthmd.appsflyer.devkey"
KEY="${APPS_FLYER_DEV_KEY:-}"

if [ -z "$KEY" ] && command -v security >/dev/null 2>&1; then
  KEY="$(security find-generic-password -a "${USER:-}" -s "$SERVICE_NAME" -w 2>/dev/null || true)"
  if [ -z "$KEY" ]; then
    KEY="$(security find-generic-password -s "$SERVICE_NAME" -w 2>/dev/null || true)"
  fi
fi

if [ -z "$KEY" ]; then
  echo "error: Missing AppsFlyer dev key for non-Debug build."
  echo "error: Set it once in keychain and future builds are automatic:"
  echo "error: security add-generic-password -U -a \"$USER\" -s \"$SERVICE_NAME\" -w \"<APPS_FLYER_DEV_KEY>\""
  echo "error: (or export APPS_FLYER_DEV_KEY before invoking xcodebuild/fastlane)"
  exit 1
fi

BUNDLE_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
PLIST_PATH="${BUNDLE_DIR}/AppsFlyerSecrets.plist"

mkdir -p "$BUNDLE_DIR"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>devKey</key>
	<string>$KEY</string>
</dict>
</plist>
EOF

echo "Injected AppsFlyerSecrets.plist into app bundle for ${CONFIGURATION} build."
