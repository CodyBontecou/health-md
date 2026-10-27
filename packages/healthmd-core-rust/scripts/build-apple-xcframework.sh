#!/bin/sh
set -eu

workspace_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH='' cd -- "$workspace_root/../.." && pwd)
package_root="$repo_root/apps/apple/Packages/HealthMdCoreRust"
output=${1:-"$package_root/Artifacts/HealthmdCore.xcframework"}
target_dir=${CARGO_TARGET_DIR:-"$workspace_root/target/apple"}
ios_deployment_target=17.0
macos_deployment_target=14.0
scope=${HEALTHMD_CORE_APPLE_SCOPE:-full}
case "$scope" in
    full)
        build_profile=release
        release_flag=--release
        build_targets="aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin"
        ;;
    ci-arm64)
        [ "$(uname -m)" = arm64 ] || { echo "error: ci-arm64 requires an arm64 Mac" >&2; exit 1; }
        build_profile=debug
        release_flag=""
        build_targets="aarch64-apple-ios-sim aarch64-apple-darwin"
        ;;
    *) echo "error: HEALTHMD_CORE_APPLE_SCOPE must be full or ci-arm64" >&2; exit 1 ;;
esac

case $(uname -s) in
    Darwin) ;;
    *)
        echo "error: Apple XCFrameworks must be built on macOS" >&2
        exit 1
        ;;
esac

for command_name in python3 rustup xcodebuild xcrun; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "error: required command not found: $command_name" >&2
        exit 1
    fi
done

toolchain=$(awk -F'"' '/^[[:space:]]*channel[[:space:]]*=/ { print $2; exit }' "$workspace_root/rust-toolchain.toml")
if [ -z "$toolchain" ]; then
    echo "error: unable to read pinned Rust toolchain" >&2
    exit 1
fi

if ! rustup run "$toolchain" rustc --version >/dev/null 2>&1; then
    rustup toolchain install "$toolchain" --profile minimal
fi
# Only install the architectures this invocation will actually compile.
installed_targets=$(rustup target list --installed --toolchain "$toolchain")
for rust_target in $build_targets; do
    if ! printf '%s\n' "$installed_targets" | grep -Fx "$rust_target" >/dev/null; then
        rustup target add --toolchain "$toolchain" "$rust_target"
    fi
done
rustc_path=$(rustup which --toolchain "$toolchain" rustc)
toolchain_bin=$(dirname -- "$rustc_path")
cargo_path="$toolchain_bin/cargo"
source_revision=${HEALTHMD_CORE_SOURCE_REVISION:-$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf development)}
if [ "$source_revision" != development ] && [ -n "$(git -C "$repo_root" status --porcelain -- packages/healthmd-core-rust 2>/dev/null)" ]; then
    source_revision="$source_revision-dirty"
fi
export HEALTHMD_CORE_SOURCE_REVISION="$source_revision"

build_target() {
    target=$1
    platform=$2
    echo "Building healthmd-core-uniffi for $target"
    case "$platform" in
        ios)
            env -u RUSTFLAGS -u CARGO_ENCODED_RUSTFLAGS \
                CARGO_INCREMENTAL=0 \
                CARGO_TARGET_DIR="$target_dir" \
                IPHONEOS_DEPLOYMENT_TARGET="$ios_deployment_target" \
                PATH="$toolchain_bin:$PATH" \
                RUSTC="$rustc_path" \
                SOURCE_DATE_EPOCH=0 \
                ZERO_AR_DATE=1 \
                "$cargo_path" build \
                    --manifest-path "$workspace_root/Cargo.toml" \
                    --locked \
                    $release_flag \
                    --package healthmd-core-uniffi \
                    --target "$target"
            ;;
        macos)
            env -u RUSTFLAGS -u CARGO_ENCODED_RUSTFLAGS \
                CARGO_INCREMENTAL=0 \
                CARGO_TARGET_DIR="$target_dir" \
                MACOSX_DEPLOYMENT_TARGET="$macos_deployment_target" \
                PATH="$toolchain_bin:$PATH" \
                RUSTC="$rustc_path" \
                SOURCE_DATE_EPOCH=0 \
                ZERO_AR_DATE=1 \
                "$cargo_path" build \
                    --manifest-path "$workspace_root/Cargo.toml" \
                    --locked \
                    $release_flag \
                    --package healthmd-core-uniffi \
                    --target "$target"
            ;;
        *)
            echo "error: unsupported Apple platform: $platform" >&2
            exit 1
            ;;
    esac
}

for rust_target in $build_targets; do
    case "$rust_target" in
        *-apple-darwin) build_target "$rust_target" macos ;;
        *) build_target "$rust_target" ios ;;
    esac
done

artifact_parent=$(dirname -- "$output")
mkdir -p "$artifact_parent"
temp_dir=$(mktemp -d "$artifact_parent/.healthmd-core-xcframework.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

headers="$temp_dir/Headers"
mkdir -p "$headers"
cp "$package_root/Bindings/HealthmdCoreFFI.h" "$headers/HealthmdCoreFFI.h"
cp "$package_root/Bindings/HealthmdCoreFFI.modulemap" "$headers/module.modulemap"

device_library="$temp_dir/ios-device/libHealthmdCoreFFI.a"
simulator_library="$temp_dir/ios-simulator/libHealthmdCoreFFI.a"
macos_library="$temp_dir/macos/libHealthmdCoreFFI.a"
mkdir -p "$(dirname -- "$device_library")" "$(dirname -- "$simulator_library")" "$(dirname -- "$macos_library")"

if [ "$scope" = full ]; then
    cp "$target_dir/aarch64-apple-ios/$build_profile/libhealthmd_core_uniffi.a" "$device_library"
    xcrun lipo -create \
        "$target_dir/aarch64-apple-ios-sim/$build_profile/libhealthmd_core_uniffi.a" \
        "$target_dir/x86_64-apple-ios/$build_profile/libhealthmd_core_uniffi.a" \
        -output "$simulator_library"
    xcrun lipo -create \
        "$target_dir/aarch64-apple-darwin/$build_profile/libhealthmd_core_uniffi.a" \
        "$target_dir/x86_64-apple-darwin/$build_profile/libhealthmd_core_uniffi.a" \
        -output "$macos_library"
    set -- -library "$device_library" -headers "$headers" \
        -library "$simulator_library" -headers "$headers" \
        -library "$macos_library" -headers "$headers"
else
    # CI links the same production bridge into its arm64 simulator and Mac apps.
    # This deliberately has no device slice and cannot qualify a release archive.
    cp "$target_dir/aarch64-apple-ios-sim/$build_profile/libhealthmd_core_uniffi.a" "$simulator_library"
    cp "$target_dir/aarch64-apple-darwin/$build_profile/libhealthmd_core_uniffi.a" "$macos_library"
    set -- -library "$simulator_library" -headers "$headers" \
        -library "$macos_library" -headers "$headers"
fi
xcodebuild -create-xcframework "$@" -output "$temp_dir/HealthmdCore.xcframework"
"$workspace_root/scripts/normalize-apple-xcframework.py" "$temp_dir/HealthmdCore.xcframework"

rm -rf "$output"
mv "$temp_dir/HealthmdCore.xcframework" "$output"
echo "Built static HealthmdCore XCFramework from $workspace_root"
echo "Artifact: $output"
