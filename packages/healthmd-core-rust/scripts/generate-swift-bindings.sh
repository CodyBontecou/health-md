#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${1:-"$workspace_root/target/generated-bindings/swift"}

cd "$workspace_root"
cargo run --locked -p xtask -- bindings swift "$out_dir"
