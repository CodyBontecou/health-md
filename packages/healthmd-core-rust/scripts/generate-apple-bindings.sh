#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$workspace_root/../.." && pwd)
package_root="$repo_root/apps/apple/Packages/HealthMdCoreRust"
mode=${1:---check}

case "$mode" in
    --check|--update) ;;
    *)
        echo "usage: $0 [--check|--update]" >&2
        exit 64
        ;;
esac

if ! grep -Fq 'uniffi = "=0.32.0"' "$workspace_root/Cargo.toml"; then
    echo "error: workspace UniFFI dependency is not pinned exactly to 0.32.0" >&2
    exit 1
fi
if ! awk '
    $0 == "name = \"uniffi\"" {
        getline
        if ($0 == "version = \"0.32.0\"") found = 1
    }
    END { exit found ? 0 : 1 }
' "$workspace_root/Cargo.lock"; then
    echo "error: Cargo.lock does not contain UniFFI 0.32.0" >&2
    exit 1
fi

toolchain=$(awk -F'"' '/^[[:space:]]*channel[[:space:]]*=/ { print $2; exit }' "$workspace_root/rust-toolchain.toml")
if [ -z "$toolchain" ]; then
    echo "error: unable to read pinned Rust toolchain" >&2
    exit 1
fi
if ! rustup run "$toolchain" rustc --version >/dev/null 2>&1; then
    rustup toolchain install "$toolchain" --profile minimal
fi
rustc_path=$(rustup which --toolchain "$toolchain" rustc)
toolchain_bin=$(dirname -- "$rustc_path")

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/healthmd-apple-bindings.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

env \
    CARGO="$toolchain_bin/cargo" \
    PATH="$toolchain_bin:$PATH" \
    RUSTC="$rustc_path" \
    "$workspace_root/scripts/generate-swift-bindings.sh" "$temp_dir"

swift_snapshot="$package_root/Sources/HealthMdCoreRust/Generated/HealthmdCore.swift"
header_snapshot="$package_root/Bindings/HealthmdCoreFFI.h"
modulemap_snapshot="$package_root/Bindings/HealthmdCoreFFI.modulemap"

if [ "$mode" = "--update" ]; then
    mkdir -p "$(dirname -- "$swift_snapshot")" "$(dirname -- "$header_snapshot")"
    cp "$temp_dir/HealthmdCore.swift" "$swift_snapshot"
    cp "$temp_dir/HealthmdCoreFFI.h" "$header_snapshot"
    cp "$temp_dir/HealthmdCoreFFI.modulemap" "$modulemap_snapshot"
    echo "updated committed UniFFI 0.32.0 Apple binding snapshots"
    exit 0
fi

status=0
compare_snapshot() {
    generated=$1
    snapshot=$2
    if [ ! -f "$snapshot" ]; then
        echo "error: missing committed binding snapshot: $snapshot" >&2
        status=1
    elif ! cmp -s "$generated" "$snapshot"; then
        echo "error: generated binding drift: $snapshot" >&2
        diff -u "$snapshot" "$generated" || true
        status=1
    fi
}

compare_snapshot "$temp_dir/HealthmdCore.swift" "$swift_snapshot"
compare_snapshot "$temp_dir/HealthmdCoreFFI.h" "$header_snapshot"
compare_snapshot "$temp_dir/HealthmdCoreFFI.modulemap" "$modulemap_snapshot"

if [ "$status" -ne 0 ]; then
    echo "Regenerate intentionally with: $0 --update" >&2
    exit "$status"
fi

echo "UniFFI 0.32.0 Apple binding snapshots are current"
