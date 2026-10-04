#!/bin/bash
# Invoke VIA BASH under the coordinator's unchanged heavy-slot guard. Not a component/core build.
set -euo pipefail
if [ "$#" -ne 1 ]; then
    printf 'Usage: bash test-account-auth-source.sh <new lane-owned output directory>\n' >&2
    exit 2
fi
root=$(cd -P "$(dirname "$0")/../../.." && pwd)
mkdir -p "$1"
out=$(cd -P "$1" && pwd)
case "$out" in
    "$root/apps/apple/build/account-auth-source/"*|*/healthmd-account-sync.O0LAHV/evidence/as03-source-*) ;;
    *) printf 'Refusing output outside AS03 namespace.\n' >&2; exit 2;;
esac
if [ -e "$out/compiler.log" ] || [ -e "$out/source-input-sha256.log" ]; then
    printf 'Refusing to overwrite earlier artifacts. Choose a new directory.\n' >&2
    exit 2
fi
mkdir -p "$out/module-cache"
/usr/bin/swiftc --version
printf 'host_flags=-swift-version 6 -strict-concurrency=complete -warnings-as-errors -D ACCOUNT_AUTH_SOURCE_HOST\n'
sources=("$root"/apps/apple/HealthMd/Shared/AccountAuth/*.swift)
tests=("$root"/apps/apple/HealthMdTests/AccountAuth/*.swift)
printf 'source_head=%s\n' "$(git -C "$root" rev-parse HEAD)"
git -C "$root" status --porcelain=v1 -- apps/apple/HealthMd/Shared/AccountAuth \
    apps/apple/HealthMdTests/AccountAuth apps/apple/scripts/test-account-auth-source.swift \
    apps/apple/scripts/test-account-auth-source.sh > "$out/source-status.log"
shasum -a 256 "${sources[@]}" "${tests[@]}" "$root/apps/apple/HealthMd/Shared/AccountAuth/README.md" \
    "$root/apps/apple/scripts/test-account-auth-source.swift" "$root/apps/apple/scripts/test-account-auth-source.sh" \
    > "$out/source-input-sha256.log"
/usr/bin/swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -D ACCOUNT_AUTH_SOURCE_HOST -module-name AccountAuthSource \
    -module-cache-path "$out/module-cache" -parse-as-library \
    "${sources[@]}" "${tests[@]}" "$root/apps/apple/scripts/test-account-auth-source.swift" \
    -o "$out/account-auth-source" > "$out/compiler.log" 2>&1 || {
        printf 'FAIL compilation (retained compiler.log)\n' >&2; exit 1;
    }
/usr/bin/perl -e 'alarm 120; exec @ARGV or exit 2' "$out/account-auth-source" "$root" > "$out/tests.log" 2>&1 || {
    printf 'FAIL tests (retained tests.log)\n' >&2; exit 1;
}
printf 'PASS strict Swift 6 source harness\n'
# Selected-source comparison to the project's Swift 5/MainActor/approachable settings.
# Neither this nor XCTest import typechecking is a full HealthMd/iOS/macOS target qualification.
target_flags=(-swift-version 5 -strict-concurrency=complete -warnings-as-errors -default-isolation MainActor
    -enable-upcoming-feature DisableOutwardActorInference
    -enable-upcoming-feature InferSendableFromCaptures
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature MemberImportVisibility)
printf 'target_like_flags='; printf '%s ' "${target_flags[@]}"; printf '\n'
mkdir -p "$out/mainactor-cache" "$out/testable-module" "$out/xctest-cache"
/usr/bin/swiftc "${target_flags[@]}" -D ACCOUNT_AUTH_SOURCE_HOST -module-name AccountAuthSourceMainActor \
    -module-cache-path "$out/mainactor-cache" -parse-as-library \
    "${sources[@]}" "${tests[@]}" "$root/apps/apple/scripts/test-account-auth-source.swift" \
    -o "$out/account-auth-source-mainactor" > "$out/mainactor-compiler.log" 2>&1 || {
        printf 'FAIL target-like compilation (retained mainactor-compiler.log)\n' >&2; exit 1;
    }
/usr/bin/perl -e 'alarm 120; exec @ARGV or exit 2' "$out/account-auth-source-mainactor" "$root" \
    > "$out/mainactor-tests.log" 2>&1 || {
        printf 'FAIL target-like tests (retained mainactor-tests.log)\n' >&2; exit 1;
    }
/usr/bin/swiftc "${target_flags[@]}" -emit-module -enable-testing -module-name HealthMd \
    -module-cache-path "$out/xctest-cache" "${sources[@]}" \
    -emit-module-path "$out/testable-module/HealthMd.swiftmodule" > "$out/testable-module.log" 2>&1 || {
        printf 'FAIL selected testable module (retained testable-module.log)\n' >&2; exit 1;
    }
/usr/bin/swiftc "${target_flags[@]}" -typecheck -module-name AccountAuthTests \
    -I "$out/testable-module" -module-cache-path "$out/xctest-cache" "${tests[@]}" \
    > "$out/xctest-typecheck.log" 2>&1 || {
        printf 'FAIL XCTest import typecheck (retained xctest-typecheck.log)\n' >&2; exit 1;
    }
printf 'PASS target-like source harness and selected XCTest imports; logs=%s\n' "$out"
