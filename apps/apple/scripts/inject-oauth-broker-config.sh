#!/bin/sh
set -eu

BUNDLE_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
PLIST_PATH="${BUNDLE_DIR}/OAuthBrokerConfig.plist"
rm -f "$PLIST_PATH"

case "${CONNECTED_APPS_WHOOP_ENABLED:-}" in
  1|true|TRUE|yes|YES) ;;
  *) exit 0 ;;
esac

ENDPOINT_SERVICE="healthmd.oauth-broker.endpoint"
TOKEN_SERVICE="healthmd.oauth-broker.client-token"
ENDPOINT="${OAUTH_BROKER_ENDPOINT_URL:-}"
CLIENT_TOKEN="${OAUTH_BROKER_CLIENT_TOKEN:-}"

read_keychain() {
  service="$1"
  security find-generic-password -a "${USER:-}" -s "$service" -w 2>/dev/null \
    || security find-generic-password -s "$service" -w 2>/dev/null \
    || true
}

if [ -z "$ENDPOINT" ] && command -v security >/dev/null 2>&1; then
  ENDPOINT="$(read_keychain "$ENDPOINT_SERVICE")"
fi
if [ -z "$CLIENT_TOKEN" ] && command -v security >/dev/null 2>&1; then
  CLIENT_TOKEN="$(read_keychain "$TOKEN_SERVICE")"
fi

case "$ENDPOINT" in
  https://*) ;;
  *)
    echo "error: WHOOP Connected Apps is enabled but OAUTH_BROKER_ENDPOINT_URL is missing or is not HTTPS."
    echo "error: Run scripts/set-oauth-broker-config.sh once, or export the build variables."
    exit 1
    ;;
esac

if [ -z "$CLIENT_TOKEN" ]; then
  echo "error: WHOOP Connected Apps is enabled but OAUTH_BROKER_CLIENT_TOKEN is missing."
  echo "error: Run scripts/set-oauth-broker-config.sh once, or export the build variables."
  exit 1
fi

mkdir -p "$BUNDLE_DIR"
/usr/bin/plutil -create xml1 "$PLIST_PATH"
/usr/bin/plutil -insert OAUTH_BROKER_ENDPOINT_URL -string "$ENDPOINT" "$PLIST_PATH"
/usr/bin/plutil -insert OAUTH_BROKER_CLIENT_TOKEN -string "$CLIENT_TOKEN" "$PLIST_PATH"

printf 'Injected OAuthBrokerConfig.plist for WHOOP Connected Apps (%s).\n' "$CONFIGURATION"
