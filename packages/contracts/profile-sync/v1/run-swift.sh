#!/bin/bash
# Invoke THROUGH the fleet heavy-slot guard (or your own approved admission guard).
set -eu
root=$(cd "$(dirname "$0")/../../../.." && pwd)
out=${PROFILE_SYNC_BUILD_DIR:-"$root/packages/contracts/profile-sync/v1/.build/swift"}
mkdir -p "$out"
swiftc -D PROFILE_SYNC_HOST -module-cache-path "$out/module-cache" \
  "$root/apps/apple/HealthMd/Shared/SharedSetup/SharedSetupV2.swift" \
  "$root/apps/apple/HealthMd/Shared/AccountSync/ProfileSyncV1.swift" \
  "$root/apps/apple/HealthMdTests/AccountSync/ProfileSyncV1Tests.swift" \
  "$root/packages/contracts/profile-sync/v1/conformance/SwiftMain.swift" \
  -o "$out/profile-sync-swift"
"$out/profile-sync-swift" "$root"
