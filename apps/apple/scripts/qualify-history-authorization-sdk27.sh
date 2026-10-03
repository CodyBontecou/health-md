#!/bin/bash
# Required hosted compilation gate. No runtime HealthKit calls or health data.
set -euo pipefail
cd "$(dirname "$0")/.."
expected=/Applications/Xcode_27.app/Contents/Developer
selected=${DEVELOPER_DIR:-$(xcode-select -p)}
[[ "$selected" == "$expected" ]] || { echo "::error::Expected selected Xcode27 at $expected, got $selected"; exit 1; }
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
    [[ "$sdk_version" == 27.* ]] || { echo "::error::SDK27 required for $sdk, got $sdk_version"; exit 1; }
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
