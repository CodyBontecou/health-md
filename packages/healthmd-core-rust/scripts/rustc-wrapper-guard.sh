# shellcheck shell=sh
# Sourced by the shared-core build entry points. A developer's cargo config may set
# build.rustc-wrapper (for example a shared sccache). A wrapper server started outside the
# current sandbox cannot write this worktree's target directory, which fails every crate with
# "Operation not permitted" (sccache exit 254). Probe once with a throwaway crate in the real
# target directory and disable only an unusable wrapper. An explicit RUSTC_WRAPPER (including
# an empty one) is respected; HEALTHMD_SKIP_RUSTC_WRAPPER_PROBE=1 skips the probe.

healthmd_guard_rustc_wrapper() {
    probe_parent=$1
    [ "${HEALTHMD_SKIP_RUSTC_WRAPPER_PROBE:-0}" = 1 ] && return 0
    [ -n "${RUSTC_WRAPPER+set}" ] && return 0
    command -v cargo >/dev/null 2>&1 || return 0

    probe_src=$(mktemp -d "${TMPDIR:-/tmp}/healthmd-rustc-wrapper-probe.XXXXXX") || return 0
    probe_target="$probe_parent/.rustc-wrapper-probe"
    mkdir -p "$probe_src/src" "$probe_parent" 2>/dev/null || true
    printf '[package]\nname = "healthmd_rustc_wrapper_probe"\nversion = "0.0.0"\nedition = "2021"\n\n[workspace]\n' > "$probe_src/Cargo.toml"
    : > "$probe_src/src/lib.rs"

    # A wrapper only changes the result when it cannot write the target directory; a probe
    # that fails both ways (no toolchain, offline) leaves the configuration alone.
    # Incremental (path-crate) compiles bypass sccache, so probe the non-incremental path the
    # registry dependencies take.
    if ! CARGO_INCREMENTAL=0 cargo build --quiet --offline --manifest-path "$probe_src/Cargo.toml" --target-dir "$probe_target" >/dev/null 2>&1 \
        && RUSTC_WRAPPER='' CARGO_INCREMENTAL=0 cargo build --quiet --offline --manifest-path "$probe_src/Cargo.toml" --target-dir "$probe_target" >/dev/null 2>&1; then
        echo "warning: the configured rustc wrapper cannot write $probe_parent; building without it (RUSTC_WRAPPER='')" >&2
        RUSTC_WRAPPER=''
        export RUSTC_WRAPPER
    fi
    rm -rf "$probe_src" "$probe_target"
}
