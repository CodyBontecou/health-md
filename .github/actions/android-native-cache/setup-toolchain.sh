#!/usr/bin/env bash
set -euo pipefail

case "$ANDROID_TOOLCHAIN" in
  true|false) ;;
  *) echo "android-toolchain must be true or false" >&2; exit 64 ;;
esac

rustup toolchain install 1.88.0 --profile minimal
# Installing a toolchain alone does not select it for plain cargo commands from
# the repository root (the host interop job has no local rust-toolchain.toml).
echo 'RUSTUP_TOOLCHAIN=1.88.0' >> "$GITHUB_ENV"
if [[ "$ANDROID_TOOLCHAIN" == false ]]; then
  exit 0
fi

rustup target add --toolchain 1.88.0 \
  aarch64-linux-android \
  armv7-linux-androideabi \
  x86_64-linux-android \
  i686-linux-android

native_tools_root="${HEALTHMD_NATIVE_TOOLS_ROOT:-$HOME/.cache/healthmd-cargo-ndk}"
tool_root="$native_tools_root/rust-1.88.0-cargo-ndk-4.1.2"
export PATH="$tool_root/bin:$PATH"
version=''
if [[ -x "$tool_root/bin/cargo-ndk" ]]; then
  version=$(rustup run 1.88.0 cargo ndk --version 2>/dev/null || true)
fi
if [[ "$version" != 'cargo-ndk 4.1.2' ]]; then
  rustup run 1.88.0 cargo install cargo-ndk --version 4.1.2 --locked \
    --root "$tool_root" --force
fi
# Validate cache hits too; neither a cache key nor a preinstalled binary replaces
# the native builder's exact tool version requirement.
test "$(rustup run 1.88.0 cargo ndk --version)" = 'cargo-ndk 4.1.2'
echo "$tool_root/bin" >> "$GITHUB_PATH"
