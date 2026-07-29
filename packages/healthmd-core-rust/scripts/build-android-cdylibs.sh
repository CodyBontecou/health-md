#!/bin/sh
set -eu

ANDROID_NDK_VERSION="27.1.12297006"
CARGO_NDK_VERSION="4.1.2"
RUST_TOOLCHAIN="1.88.0"
ANDROID_MIN_API="28"
EXPECTED_LIBRARY="libhealthmd_core_uniffi.so"
TARGETS="aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android"
ABIS="arm64-v8a armeabi-v7a x86_64 x86"

usage() {
    echo "usage: $0 <debug|release> <jni-output-directory>" >&2
    exit 64
}

fail() {
    echo "healthmd-core Android build error: $*" >&2
    exit 1
}

[ "$#" -eq 2 ] || usage
profile=$1
output_dir=$2
case "$profile" in
    debug|release) ;;
    *) usage ;;
esac

command -v cargo >/dev/null 2>&1 || fail "cargo is missing; install Rust toolchain $RUST_TOOLCHAIN with rustup"
command -v rustup >/dev/null 2>&1 || fail "rustup is missing; install rustup and Rust toolchain $RUST_TOOLCHAIN"
command -v cargo-ndk >/dev/null 2>&1 || fail "cargo-ndk $CARGO_NDK_VERSION is missing; run: cargo install cargo-ndk --version $CARGO_NDK_VERSION --locked"

cargo_ndk_version=$(rustup run "$RUST_TOOLCHAIN" cargo ndk --version 2>/dev/null || true)
case "$cargo_ndk_version" in
    *" $CARGO_NDK_VERSION") ;;
    *) fail "cargo-ndk $CARGO_NDK_VERSION is required, found '${cargo_ndk_version:-unknown}'; reinstall with: cargo install cargo-ndk --version $CARGO_NDK_VERSION --locked --force" ;;
esac

rustup run "$RUST_TOOLCHAIN" rustc --version >/dev/null 2>&1 ||
    fail "Rust toolchain $RUST_TOOLCHAIN is missing; run: rustup toolchain install $RUST_TOOLCHAIN --profile minimal"
toolchain_cargo=$(rustup which --toolchain "$RUST_TOOLCHAIN" cargo) ||
    fail "cargo is missing from Rust toolchain $RUST_TOOLCHAIN"
toolchain_rustc=$(rustup which --toolchain "$RUST_TOOLCHAIN" rustc) ||
    fail "rustc is missing from Rust toolchain $RUST_TOOLCHAIN"
export RUSTC="$toolchain_rustc"
installed_targets=$(rustup target list --installed --toolchain "$RUST_TOOLCHAIN")
for target in $TARGETS; do
    printf '%s\n' "$installed_targets" | grep -Fx "$target" >/dev/null 2>&1 ||
        fail "Rust target $target is missing; run: rustup target add --toolchain $RUST_TOOLCHAIN $target"
done

ndk_dir=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
if [ -z "$ndk_dir" ]; then
    android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
    [ -n "$android_sdk" ] ||
        fail "ANDROID_NDK_HOME is unset; install Android NDK $ANDROID_NDK_VERSION and set ANDROID_NDK_HOME"
    ndk_dir="$android_sdk/ndk/$ANDROID_NDK_VERSION"
fi
[ -d "$ndk_dir" ] ||
    fail "Android NDK $ANDROID_NDK_VERSION was not found at $ndk_dir; install it with: sdkmanager 'ndk;$ANDROID_NDK_VERSION'"
[ -f "$ndk_dir/source.properties" ] || fail "NDK metadata is missing at $ndk_dir/source.properties"
grep -Eq "^Pkg\.Revision[[:space:]]*=[[:space:]]*$ANDROID_NDK_VERSION([[:space:]]*)$" "$ndk_dir/source.properties" ||
    fail "Android NDK $ANDROID_NDK_VERSION is required; $ndk_dir contains a different revision"

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$workspace_root/../.." && pwd)
source_revision=${HEALTHMD_CORE_SOURCE_REVISION:-$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf development)}
if [ "$source_revision" != development ] && [ -n "$(git -C "$repo_root" status --porcelain -- packages/healthmd-core-rust 2>/dev/null)" ]; then
    source_revision="$source_revision-dirty"
fi
export HEALTHMD_CORE_SOURCE_REVISION="$source_revision"
case "$output_dir" in
    /*) ;;
    *) output_dir="$(pwd)/$output_dir" ;;
esac

rm -rf "$output_dir"
mkdir -p "$output_dir"

export ANDROID_NDK_HOME="$ndk_dir"
export ANDROID_NDK_ROOT="$ndk_dir"
if [ "$profile" = release ]; then
    # Keep full Rust debug information in the source artifact. AGP strips the AAB copy
    # and writes the retained symbols to its native-debug-symbols archive.
    export CARGO_PROFILE_RELEASE_DEBUG=2
    export CARGO_PROFILE_RELEASE_STRIP=none
    release_flag="--release"
else
    release_flag=""
fi

cd "$workspace_root"
# shellcheck disable=SC2086
"$toolchain_cargo" ndk \
    --platform "$ANDROID_MIN_API" \
    --target arm64-v8a \
    --target armeabi-v7a \
    --target x86_64 \
    --target x86 \
    --output-dir "$output_dir" \
    build --locked --package healthmd-core-uniffi $release_flag

for abi in $ABIS; do
    library="$output_dir/$abi/$EXPECTED_LIBRARY"
    [ -s "$library" ] || fail "cargo-ndk did not produce $library"
done

printf 'Built %s for Android ABIs: %s\n' "$EXPECTED_LIBRARY" "$ABIS"
