#!/bin/bash
# Invoke THROUGH the fleet heavy-slot guard (or your own approved admission guard).
set -eu
# Clang PCM identity must not mix macOS /var and /private/var path aliases.
root=$(cd "$(dirname "$0")/../../../.." && pwd -P)
out=${PROFILE_SYNC_BUILD_DIR:-"$root/packages/contracts/profile-sync/v1/.build/swift"}
mkdir -p "$out"
out=$(cd "$out" && pwd -P)
# Preserve any older alias-poisoned PCM cache; compile into the physical-path namespace.
swiftc -D PROFILE_SYNC_HOST -module-cache-path "$out/module-cache-physical" \
  "$root/apps/apple/HealthMd/Shared/SharedSetup/SharedSetupV2.swift" \
  "$root/apps/apple/HealthMd/Shared/AccountSync/ProfileSyncV1.swift" \
  "$root/apps/apple/HealthMdTests/AccountSync/ProfileSyncV1Tests.swift" \
  "$root/packages/contracts/profile-sync/v1/conformance/SwiftMain.swift" \
  -o "$out/profile-sync-swift"
"$out/profile-sync-swift" "$root"
