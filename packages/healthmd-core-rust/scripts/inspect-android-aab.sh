#!/bin/sh
set -eu

ABIS="arm64-v8a armeabi-v7a x86_64 x86"
LIBRARIES="libhealthmd_core_uniffi.so libjnidispatch.so"
CORE_LIBRARY="libhealthmd_core_uniffi.so"

fail() {
    echo "healthmd-core Android package inspection error: $*" >&2
    exit 1
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo "usage: $0 <app.aab> [native-debug-symbols.zip]" >&2
    exit 64
}

aab=$1
symbols=${2:-}
command -v unzip >/dev/null 2>&1 || fail "unzip is required to inspect Android artifacts"
[ -f "$aab" ] || fail "AAB not found: $aab"

entries=$(unzip -Z1 "$aab")
for abi in $ABIS; do
    for library in $LIBRARIES; do
        entry="base/lib/$abi/$library"
        printf '%s\n' "$entries" | grep -Fx "$entry" >/dev/null 2>&1 || fail "$entry is missing from $aab"
        size=$(unzip -p "$aab" "$entry" | wc -c | tr -d '[:space:]')
        [ "${size:-0}" -gt 0 ] || fail "$entry is empty"
    done

    symbol_entry="BUNDLE-METADATA/com.android.tools.build.debugsymbols/$abi/$CORE_LIBRARY.dbg"
    printf '%s\n' "$entries" | grep -Fx "$symbol_entry" >/dev/null 2>&1 ||
        fail "retained symbols $symbol_entry are missing from $aab"
    size=$(unzip -p "$aab" "$symbol_entry" | wc -c | tr -d '[:space:]')
    [ "${size:-0}" -gt 0 ] || fail "$symbol_entry is empty"
done

if [ -n "$symbols" ]; then
    [ -f "$symbols" ] || fail "native debug symbols archive not found: $symbols"
    symbol_entries=$(unzip -Z1 "$symbols")
    for abi in $ABIS; do
        symbol_entry=$(printf '%s\n' "$symbol_entries" | grep -E "(^|/)$abi/$CORE_LIBRARY(\\.sym|\\.dbg)?$" | head -n 1 || true)
        [ -n "$symbol_entry" ] || fail "retained symbols for $abi/$CORE_LIBRARY are missing from $symbols"
        size=$(unzip -p "$symbols" "$symbol_entry" | wc -c | tr -d '[:space:]')
        [ "${size:-0}" -gt 0 ] || fail "$symbol_entry is empty"
    done
fi

printf 'Verified %s and retained Health.md core symbols in Android ABIs: %s\n' "$LIBRARIES" "$ABIS"
if [ -n "$symbols" ]; then
    printf 'Verified retained native symbols in %s\n' "$symbols"
fi
