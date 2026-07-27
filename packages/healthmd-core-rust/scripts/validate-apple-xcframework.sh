#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$workspace_root/../.." && pwd)
package_root="$repo_root/apps/apple/Packages/HealthMdCoreRust"
xcframework=${1:-"$package_root/Artifacts/HealthmdCore.xcframework"}

fail() {
    echo "error: $*" >&2
    exit 1
}

[ -f "$xcframework/Info.plist" ] || fail "missing XCFramework Info.plist: $xcframework"

device_library="$xcframework/ios-arm64/libHealthmdCoreFFI.a"
simulator_library="$xcframework/ios-arm64_x86_64-simulator/libHealthmdCoreFFI.a"
macos_library="$xcframework/macos-arm64_x86_64/libHealthmdCoreFFI.a"

[ -f "$device_library" ] || fail "missing arm64 iOS device slice"
[ -f "$simulator_library" ] || fail "missing universal iOS Simulator slice"
[ -f "$macos_library" ] || fail "missing universal macOS slice"

library_count=$(find "$xcframework" -type f -name 'libHealthmdCoreFFI.a' | wc -l | tr -d ' ')
[ "$library_count" = "3" ] || fail "expected exactly three static libraries, found $library_count"

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

assert_architectures "$device_library" "arm64"
assert_architectures "$simulator_library" "arm64 x86_64"
assert_architectures "$macos_library" "arm64 x86_64"

required_symbols='uniffi_healthmd_core_uniffi_fn_func_get_build_info
uniffi_healthmd_core_uniffi_fn_func_run_self_test
uniffi_healthmd_core_uniffi_fn_func_validate_fixture
ffi_healthmd_core_uniffi_uniffi_contract_version'

for library in "$device_library" "$simulator_library" "$macos_library"; do
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

for identifier in ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64; do
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
