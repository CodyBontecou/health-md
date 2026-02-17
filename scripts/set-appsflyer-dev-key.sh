#!/bin/sh
set -eu

SERVICE_NAME="healthmd.appsflyer.devkey"

if [ "${1:-}" != "" ]; then
  KEY="$1"
else
  printf "Enter AppsFlyer dev key: "
  stty -echo
  IFS= read -r KEY
  stty echo
  printf "\n"
fi

if [ -z "$KEY" ]; then
  echo "No key provided."
  exit 1
fi

security add-generic-password -U -a "${USER:-}" -s "$SERVICE_NAME" -w "$KEY" >/dev/null

echo "Saved AppsFlyer dev key to macOS Keychain service: $SERVICE_NAME"
echo "Future non-Debug builds will inject it automatically."
