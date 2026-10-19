#!/usr/bin/env bash
set -euo pipefail

case "$CACHE_TARGETS" in
  android|android-cli|cli|none) ;;
  *) echo "Unsupported cache-targets: $CACHE_TARGETS" >&2; exit 64 ;;
esac
case "$ANDROID_TOOLCHAIN" in
  true|false) ;;
  *) echo "android-toolchain must be true or false" >&2; exit 64 ;;
esac

cargo_cache_root="${CARGO_HOME:-$HOME/.cargo}"
native_tools_root="${HEALTHMD_NATIVE_TOOLS_ROOT:-$HOME/.cache/healthmd-cargo-ndk}"
{
  echo 'dependencies<<NATIVE_CACHE_PATHS'
  echo "$cargo_cache_root/registry"
  echo "$cargo_cache_root/git/db"
  echo "$cargo_cache_root/git/checkouts"
  if [[ "$ANDROID_TOOLCHAIN" == true ]]; then
    echo "$native_tools_root/rust-1.88.0-cargo-ndk-4.1.2"
  fi
  echo 'NATIVE_CACHE_PATHS'
  echo 'targets<<NATIVE_CACHE_PATHS'
  if [[ "$CACHE_TARGETS" == android || "$CACHE_TARGETS" == android-cli ]]; then
    # Both native libraries and host binding generation override CARGO_TARGET_DIR
    # here; the shared-core workspace's default target directory is unused.
    echo "$GITHUB_WORKSPACE/apps/android/healthmd-core/build/rust-target"
  fi
  if [[ "$CACHE_TARGETS" == cli || "$CACHE_TARGETS" == android-cli ]]; then
    echo "$GITHUB_WORKSPACE/apps/cli/target"
  fi
  echo 'NATIVE_CACHE_PATHS'
  # Qualification may check out release_sha instead of github.sha. Use the source
  # actually built for the immutable cache key, then reuse dependency fingerprints.
  echo "source=$(git -C "$GITHUB_WORKSPACE" rev-parse HEAD)"
} >> "$GITHUB_OUTPUT"
