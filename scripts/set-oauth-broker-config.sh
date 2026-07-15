#!/bin/sh
set -eu

ENDPOINT_SERVICE="healthmd.oauth-broker.endpoint"
TOKEN_SERVICE="healthmd.oauth-broker.client-token"
ENDPOINT="${1:-}"
CLIENT_TOKEN="${2:-}"

if [ -z "$ENDPOINT" ]; then
  printf "OAuth broker HTTPS endpoint: "
  IFS= read -r ENDPOINT
fi
case "$ENDPOINT" in
  https://*) ;;
  *) echo "Endpoint must use https://"; exit 1 ;;
esac

if [ -z "$CLIENT_TOKEN" ]; then
  printf "Broker mobile client token: "
  stty -echo
  IFS= read -r CLIENT_TOKEN
  stty echo
  printf "\n"
fi
if [ -z "$CLIENT_TOKEN" ]; then
  echo "No broker client token provided."
  exit 1
fi

security add-generic-password -U -a "${USER:-}" -s "$ENDPOINT_SERVICE" -w "$ENDPOINT" >/dev/null
security add-generic-password -U -a "${USER:-}" -s "$TOKEN_SERVICE" -w "$CLIENT_TOKEN" >/dev/null

printf 'Saved OAuth broker endpoint and mobile gate token to macOS Keychain.\n'
printf 'Enable a beta build with CONNECTED_APPS_WHOOP_ENABLED=YES.\n'
