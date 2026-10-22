#!/bin/bash
# Read-only output admission; sourcing this file performs no validation or mutation.
# Caller supplies the physical repository root and a fresh ALREADY EXISTING directory.
account_auth_source_validate_output() {
    if [ "$#" -ne 2 ]; then
        printf 'Output admission requires root and existing directory.\n' >&2
        return 2
    fi
    local root out entry
    # A non-newline sentinel preserves every physical path byte through shell capture.
    root=$(cd -P -- "$1" 2>/dev/null && printf '%s.' "$PWD") || return 2
    root=${root%.}
    out=$(cd -P -- "$2" 2>/dev/null && printf '%s.' "$PWD") || {
        printf 'Refusing output: a fresh existing directory is required.\n' >&2
        return 2
    }
    out=${out%.}
    case "$root$out" in
        *$'\n'*|*$'\r'*) printf 'Refusing unsupported newline-bearing physical path.\n' >&2; return 2;;
    esac
    case "$out" in
        "$root/apps/apple/build/account-auth-source/"*|*/healthmd-account-sync.O0LAHV/evidence/as03-source-*) ;;
        *) printf 'Refusing output outside AS03 namespace.\n' >&2; return 2;;
    esac
    # The outer guard may already be writing this regular log. Everything else is reused
    # output, including hidden files, partial receipts/caches and dangling artifact symlinks.
    for entry in "$out"/* "$out"/.[!.]* "$out"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        if [ "$entry" = "$out/guard.log" ] && [ -f "$entry" ] && [ ! -L "$entry" ]; then continue; fi
        printf 'Refusing earlier artifacts; choose a fresh existing directory.\n' >&2
        return 2
    done
    printf '%s\n' "$out"
}
