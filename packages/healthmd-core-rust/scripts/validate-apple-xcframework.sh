#!/bin/sh
set -eu

workspace_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH='' cd -- "$workspace_root/../.." && pwd)
package_root="$repo_root/apps/apple/Packages/HealthMdCoreRust"
xcframework=${1:-"$package_root/Artifacts/HealthmdCore.xcframework"}

fail() {
    echo "error: $*" >&2
    exit 1
}

[ -f "$xcframework/Info.plist" ] || fail "missing XCFramework Info.plist: $xcframework"

scope=${HEALTHMD_CORE_APPLE_SCOPE:-full}
case "$scope" in
    full)
        identifiers="ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64"
        expected_count=3
        ;;
    ci-arm64)
        identifiers="ios-arm64-simulator macos-arm64"
        expected_count=2
        ;;
    *) fail "HEALTHMD_CORE_APPLE_SCOPE must be full or ci-arm64" ;;
esac
for identifier in $identifiers; do
    [ -s "$xcframework/$identifier/libHealthmdCoreFFI.a" ] || fail "missing static library for $identifier"
done
library_count=$(find "$xcframework" -type f -name 'libHealthmdCoreFFI.a' | wc -l | tr -d ' ')
[ "$library_count" = "$expected_count" ] || fail "expected $expected_count static libraries, found $library_count"

assert_architectures() {
    library=$1
    expected=$2
    actual=$(xcrun lipo -archs "$library")

    for architecture in $expected; do
        case " $actual " in
            *" $architecture "*) ;;
            *) fail "$library is missing architecture $architecture (found: $actual)" ;;
        esac
    done
    for architecture in $actual; do
        case " $expected " in
            *" $architecture "*) ;;
            *) fail "$library has unexpected architecture $architecture (expected: $expected)" ;;
        esac
    done
}

for identifier in $identifiers; do
    case "$identifier" in
        *arm64_x86_64*) expected_architectures="arm64 x86_64" ;;
        *) expected_architectures="arm64" ;;
    esac
    assert_architectures "$xcframework/$identifier/libHealthmdCoreFFI.a" "$expected_architectures"
done

required_symbols='uniffi_healthmd_core_uniffi_fn_func_get_build_info
uniffi_healthmd_core_uniffi_fn_func_run_self_test
uniffi_healthmd_core_uniffi_fn_func_validate_fixture
ffi_healthmd_core_uniffi_uniffi_contract_version'

for identifier in $identifiers; do
    library="$xcframework/$identifier/libHealthmdCoreFFI.a"
    symbols_file=$(mktemp "${TMPDIR:-/tmp}/healthmd-core-symbols.XXXXXX")
    trap 'rm -f "$symbols_file"' EXIT HUP INT TERM
    xcrun nm -gjU "$library" > "$symbols_file" 2>/dev/null
    printf '%s\n' "$required_symbols" | while IFS= read -r symbol; do
        if ! grep -Eq "^_?${symbol}$" "$symbols_file"; then
            fail "$library does not export required symbol $symbol"
        fi
    done
    if xcrun otool -hv "$library" 2>/dev/null | grep -q 'MH_DYLIB'; then
        fail "$library contains a dynamic-library Mach-O member"
    fi
    rm -f "$symbols_file"
    trap - EXIT HUP INT TERM
done

if find "$xcframework" -type f \( -name '*.dylib' -o -name '*.so' \) | grep -q .; then
    fail "XCFramework contains a dynamic library"
fi

for identifier in $identifiers; do
    header_dir="$xcframework/$identifier/Headers"
    [ -f "$header_dir/HealthmdCoreFFI.h" ] || fail "missing generated header for $identifier"
    [ -f "$header_dir/module.modulemap" ] || fail "missing module map for $identifier"
    grep -Eq '^module HealthmdCoreFFI \{' "$header_dir/module.modulemap" \
        || fail "FFI module is not named HealthmdCoreFFI for $identifier"
done

if find "$package_root/Artifacts" -type f \( -name '*.dylib' -o -name '*.so' \) | grep -q .; then
    fail "Apple package artifacts contain a dynamic library"
fi

echo "Validated static Apple XCFramework slices, symbols, HealthmdCoreFFI module, and no-dylib policy"
