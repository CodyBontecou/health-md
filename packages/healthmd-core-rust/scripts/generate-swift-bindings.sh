#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${1:-"$workspace_root/target/generated-bindings/swift"}

cd "$workspace_root"
. "$workspace_root/scripts/rustc-wrapper-guard.sh"
healthmd_guard_rustc_wrapper "${CARGO_TARGET_DIR:-$workspace_root/target}" "${CARGO:-cargo}"
cargo run --locked -p xtask -- bindings swift "$out_dir"
