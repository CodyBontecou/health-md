#!/bin/bash
# Invoke VIA BASH under the coordinator's unchanged heavy-slot guard. Not a component/core build.
set -euo pipefail
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf 'Usage: bash test-account-auth-source.sh <fresh existing lane-owned output directory> [read-only reply-header fixture root]\n' >&2
    exit 2
fi
root=$(cd -P "$(dirname "$0")/../../.." && pwd)
source "$root/apps/apple/scripts/account-auth-source-output.sh"
out=$(account_auth_source_validate_output "$root" "$1") || exit 2
header_root=$root
if [ "$#" -eq 2 ]; then
    header_root=$(cd -P -- "$2" && printf '%s.' "$PWD") || exit 2
    header_root=${header_root%.}
    case "$header_root" in *$'\n'*|*$'\r'*) printf 'Refusing unsupported fixture-root path.\n' >&2; exit 2;; esac
fi
header_fixture="$header_root/packages/contracts/account-auth/v1/fixtures/native-reply-header-vectors.json"
[ -f "$header_fixture" ] || { printf 'Missing explicit read-only reply-header fixture.\n' >&2; exit 2; }
mkdir -p "$out/module-cache"
/usr/bin/swiftc --version
printf 'host_flags=-swift-version 6 -strict-concurrency=complete -warnings-as-errors -D ACCOUNT_AUTH_SOURCE_HOST\n'
sources=("$root"/apps/apple/HealthMd/Shared/AccountAuth/*.swift)
tests=("$root"/apps/apple/HealthMdTests/AccountAuth/*.swift)
printf 'source_head=%s\n' "$(git -C "$root" rev-parse HEAD)"
git -C "$root" status --porcelain=v1 -- apps/apple/HealthMd/Shared/AccountAuth \
    apps/apple/HealthMdTests/AccountAuth apps/apple/scripts/test-account-auth-source.swift \
    apps/apple/scripts/test-account-auth-source.sh apps/apple/scripts/account-auth-source-output.sh \
    apps/apple/scripts/test-account-auth-source-output.sh > "$out/source-status.log"
shasum -a 256 "${sources[@]}" "${tests[@]}" "$root/apps/apple/HealthMd/Shared/AccountAuth/README.md" \
    "$root/apps/apple/scripts/test-account-auth-source.swift" "$root/apps/apple/scripts/test-account-auth-source.sh" \
    "$root/apps/apple/scripts/account-auth-source-output.sh" "$root/apps/apple/scripts/test-account-auth-source-output.sh" \
    > "$out/source-input-sha256.log"
shasum -a 256 "$root/packages/contracts/account-auth/v1/fixtures/native-client-vectors.json" \
    "$root/packages/contracts/account-auth/v1/fixtures/security-vectors.json" "$header_fixture" > "$out/fixture-input-sha256.log"
/usr/bin/swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -D ACCOUNT_AUTH_SOURCE_HOST -module-name AccountAuthSource \
    -module-cache-path "$out/module-cache" -parse-as-library \
    "${sources[@]}" "${tests[@]}" "$root/apps/apple/scripts/test-account-auth-source.swift" \
    -o "$out/account-auth-source" > "$out/compiler.log" 2>&1 || {
        printf 'FAIL compilation (retained compiler.log)\n' >&2; exit 1;
    }
/usr/bin/perl -e 'alarm 120; exec @ARGV or exit 2' "$out/account-auth-source" "$root" "$header_root" > "$out/tests.log" 2>&1 || {
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
/usr/bin/perl -e 'alarm 120; exec @ARGV or exit 2' "$out/account-auth-source-mainactor" "$root" "$header_root" \
    > "$out/mainactor-tests.log" 2>&1 || {
        printf 'FAIL target-like tests (retained mainactor-tests.log)\n' >&2; exit 1;
    }
# Explicit already-installed inputs from the separately guarded bounded metadata command.
# Never search, install, stub or skip the conditional import branch.
sdk=${ACCOUNT_AUTH_SELECTED_SDK:-}
frameworks=${ACCOUNT_AUTH_DEVELOPER_FRAMEWORKS:-}
developer_lib=${ACCOUNT_AUTH_DEVELOPER_USR_LIB:-}
[ -n "$sdk" ] && [ -d "$sdk" ] && [ -n "$frameworks" ] && [ -d "$frameworks/XCTest.framework" ] && \
    [ -n "$developer_lib" ] && [ -d "$developer_lib" ] || {
    printf 'FAIL explicit installed selected SDK/XCTest inputs required.\n' >&2; exit 1;
}
printf 'sdk=%s\nframeworks=%s\ndeveloper_usr_lib=%s\n' "$sdk" "$frameworks" "$developer_lib" > "$out/xctest-inputs.log"
/usr/bin/swiftc "${target_flags[@]}" -sdk "$sdk" -emit-module -enable-testing -module-name HealthMd \
    -module-cache-path "$out/xctest-cache" "${sources[@]}" \
    -emit-module-path "$out/testable-module/HealthMd.swiftmodule" > "$out/testable-module.log" 2>&1 || {
        printf 'FAIL selected testable module (retained testable-module.log)\n' >&2; exit 1;
    }
/usr/bin/swiftc "${target_flags[@]}" -sdk "$sdk" -F "$frameworks" -I "$developer_lib" \
    -typecheck -module-name AccountAuthTests -I "$out/testable-module" -module-cache-path "$out/xctest-cache" "${tests[@]}" \
    > "$out/xctest-typecheck.log" 2>&1 || {
        printf 'FAIL XCTest import typecheck (retained xctest-typecheck.log)\n' >&2; exit 1;
    }
shasum -a 256 "${sources[@]}" "${tests[@]}" "$root/apps/apple/HealthMd/Shared/AccountAuth/README.md" \
    "$root/apps/apple/scripts/test-account-auth-source.swift" "$root/apps/apple/scripts/test-account-auth-source.sh" \
    "$root/apps/apple/scripts/account-auth-source-output.sh" "$root/apps/apple/scripts/test-account-auth-source-output.sh" \
    > "$out/source-final-input-sha256.log"
cmp -s "$out/source-input-sha256.log" "$out/source-final-input-sha256.log" || { printf 'FAIL source changed during runner.\n' >&2; exit 1; }
shasum -a 256 "$root/packages/contracts/account-auth/v1/fixtures/native-client-vectors.json" \
    "$root/packages/contracts/account-auth/v1/fixtures/security-vectors.json" "$header_fixture" > "$out/fixture-final-input-sha256.log"
cmp -s "$out/fixture-input-sha256.log" "$out/fixture-final-input-sha256.log" || { printf 'FAIL fixture changed during runner.\n' >&2; exit 1; }
printf 'final_source_head=%s\n' "$(git -C "$root" rev-parse HEAD)"
printf 'PASS target-like source harness and selected XCTest imports; logs=%s\n' "$out"
