#!/bin/bash
# Required hosted compilation gate. No runtime HealthKit calls or health data.
set -euo pipefail
cd "$(dirname "$0")/.."
expected=/Applications/Xcode_27.app/Contents/Developer
selected=${DEVELOPER_DIR:-$(xcode-select -p)}
[[ "$selected" == "$expected" ]] || { echo "::error::Expected selected Xcode27 at $expected, got $selected"; exit 1; }
# Fail closed before any cache restore: this tranche's namespace identifies the
# actually qualified compiler/SDK, not merely a floating Xcode_27.app path.
[[ "$(uname -m)" == arm64 ]] || { echo "::error::Qualified arm64 toolchain required"; exit 1; }
xcode_version=$(xcodebuild -version)
[[ "$xcode_version" == $'Xcode 27.0\nBuild version 27A266a' ]] || { echo "::error::Qualified Xcode 27A266a required; got $xcode_version"; exit 1; }
swift_version=$(xcrun swiftc --version)
[[ "${swift_version%%$'\n'*}" == 'Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)' ]] || { echo "::error::Qualified Swift/Clang compiler build required; got $swift_version"; exit 1; }
mkdir -p build/logs
receipt=build/logs/history-sdk27-receipt.txt
{
    echo "HEAD=$(git rev-parse HEAD)"
    echo "TREE=$(git rev-parse HEAD^{tree})"
    echo "ImageOS=${ImageOS:-unknown} ImageVersion=${ImageVersion:-unknown}"
    echo "DEVELOPER_DIR=$selected ARCH=$(uname -m)"
    sw_vers
    xcodebuild -version
    xcrun swiftc --version
    xcodebuild -showsdks
} | tee "$receipt"
for sdk in iphonesimulator iphoneos macosx; do
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    sdk_version=$(xcrun --sdk "$sdk" --show-sdk-version)
    [[ "$sdk_version" == 27.0 ]] || { echo "::error::Qualified SDK27.0 required for $sdk, got $sdk_version"; exit 1; }
    case "$sdk" in
        iphonesimulator) target=arm64-apple-ios17.0-simulator ;;
        iphoneos) target=arm64-apple-ios17.0 ;;
        macosx) target=arm64-apple-macosx14.0 ;;
    esac
    echo "SDK=$sdk VERSION=$sdk_version PATH=$sdk_path TARGET=$target" | tee -a "$receipt"
    xcrun --sdk "$sdk" swiftc -typecheck -sdk "$sdk_path" -target "$target" \
        scripts/fixtures/HealthHistoryAuthorizationSDKProbe.swift 2>&1 | tee -a "$receipt"
    echo "PASS public declaration: $sdk (compilation only)" | tee -a "$receipt"
done
