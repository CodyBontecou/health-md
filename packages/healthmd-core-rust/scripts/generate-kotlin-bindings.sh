#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${1:-"$workspace_root/target/generated-bindings/kotlin"}
case "$out_dir" in
    /*) ;;
    *) out_dir="$(pwd)/$out_dir" ;;
esac

command -v cargo >/dev/null 2>&1 || {
    echo "Health.md Kotlin binding generation requires cargo and Rust 1.88.0" >&2
    exit 1
}
command -v rustup >/dev/null 2>&1 || {
    echo "Health.md Kotlin binding generation requires rustup and Rust 1.88.0" >&2
    exit 1
}
rustup run 1.88.0 rustc --version >/dev/null 2>&1 || {
    echo "Rust toolchain 1.88.0 is missing; run: rustup toolchain install 1.88.0 --profile minimal" >&2
    exit 1
}

cd "$workspace_root"
rustup run 1.88.0 cargo run --locked -p xtask -- bindings kotlin "$out_dir"
python3 "$workspace_root/scripts/normalize-kotlin-bindings.py" "$out_dir"
