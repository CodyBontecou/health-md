#!/bin/bash
set -euo pipefail

available_devices=$(xcrun simctl list devices available iOS)

device_line=$(
    printf '%s\n' "$available_devices" \
        | grep -E "iPhone (17 Pro|17|16 Pro|16|15 Pro|15)" \
        | head -n 1 \
        || true
)

if [[ -z "$device_line" ]]; then
    device_line=$(
        printf '%s\n' "$available_devices" \
            | grep -E "iPhone" \
            | head -n 1 \
            || true
    )
fi

if [[ -z "$device_line" ]]; then
    echo "error: no available iOS Simulator device found" >&2
    exit 1
fi

device_id=$(printf '%s\n' "$device_line" | sed -nE 's/.*\(([0-9A-Fa-f-]+)\).*/\1/p')
if [[ -z "$device_id" ]]; then
    echo "error: could not parse iOS Simulator identifier from: $device_line" >&2
    exit 1
fi

printf 'platform=iOS Simulator,id=%s\n' "$device_id"
