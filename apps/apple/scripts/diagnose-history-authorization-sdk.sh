#!/bin/bash
# Cloud-only diagnostic, not runtime QA or a release qualification gate.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -version
xcrun swiftc --version
architecture=$(uname -m)
probe=scripts/fixtures/HealthHistoryAuthorizationSDKProbe.swift

for sdk in iphonesimulator macosx; do
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    sdk_version=$(xcrun --sdk "$sdk" --show-sdk-version)
    case "$sdk" in
        iphonesimulator) target="${architecture}-apple-ios26.0-simulator" ;;
        macosx) target="${architecture}-apple-macosx26.0" ;;
    esac
    echo "SDK probe: ${sdk} ${sdk_version}; target ${target}"
    # Preserve the compiler's real diagnostics. A failed probe is not proof of
    # absent runtime support; it says this declaration did not typecheck here.
    if xcrun swiftc -typecheck -sdk "$sdk_path" -target "$target" "$probe"; then
        result="public declaration typechecks (runtime behavior NOT verified)"
    else
        result="public declaration does NOT typecheck; inspect compiler diagnostics"
    fi
    echo "History authorization SDK: ${result}"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf -- '- HealthKit history API, %s SDK %s: %s\n' \
            "$sdk" "$sdk_version" "$result" >> "$GITHUB_STEP_SUMMARY"
    fi
done
