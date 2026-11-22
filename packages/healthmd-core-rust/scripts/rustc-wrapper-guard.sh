# Sourced by the shared-core build scripts; POSIX sh.
#
# A configured rustc wrapper (for example sccache via `build.rustc-wrapper` in
# ~/.cargo/config.toml) may write compiler outputs from a long-lived server
# process. When that server was started under another sandbox it cannot write
# this checkout's target directory, and every crate fails with "Operation not
# permitted". Probe once with a throwaway crate in the real target directory,
# built non-incrementally because sccache hands incremental builds to a local
# rustc and would skip the server. If only the wrapped build fails, build
# without the wrapper. Compilation errors are unaffected: the probe crate is
# empty, and a probe that fails without the wrapper too changes nothing.
#
# Usage: healthmd_guard_rustc_wrapper TARGET_DIR [CARGO]
healthmd_guard_rustc_wrapper() {
    [ "${HEALTHMD_RUSTC_WRAPPER_CHECKED:-}" = "1" ] && return 0
    HEALTHMD_RUSTC_WRAPPER_CHECKED=1
    export HEALTHMD_RUSTC_WRAPPER_CHECKED
    # An explicitly empty wrapper is already the no-wrapper configuration.
    if [ "${RUSTC_WRAPPER+set}" = "set" ] && [ -z "$RUSTC_WRAPPER" ]; then return 0; fi

    guard_cargo=${2:-cargo}
    guard_dir="$1/.rustc-wrapper-probe"
    rm -rf "$guard_dir"
    mkdir -p "$guard_dir/src" 2>/dev/null || return 0
    printf '[package]\nname = "rustc-wrapper-probe"\nversion = "0.0.0"\nedition = "2021"\npublish = false\n\n[lib]\npath = "src/lib.rs"\n\n[workspace]\n' \
        > "$guard_dir/Cargo.toml"
    : > "$guard_dir/src/lib.rs"

    if (cd "$guard_dir" && CARGO_INCREMENTAL=0 "$guard_cargo" build --quiet --offline --target-dir "$guard_dir/target") \
        > "$guard_dir/wrapped.log" 2>&1; then
        rm -rf "$guard_dir"
        return 0
    fi
    if (cd "$guard_dir" && CARGO_INCREMENTAL=0 RUSTC_WRAPPER='' "$guard_cargo" build --quiet --offline --target-dir "$guard_dir/target-unwrapped") \
        > "$guard_dir/unwrapped.log" 2>&1; then
        echo "warning: the configured rustc wrapper cannot write $1; building without it" >&2
        sed -n '1,3p' "$guard_dir/wrapped.log" >&2
        RUSTC_WRAPPER=''
        export RUSTC_WRAPPER
    fi
    rm -rf "$guard_dir"
    return 0
}
