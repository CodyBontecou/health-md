#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version)

# GitHub's macOS images retain several simulator runtimes. Selecting the first
# listed device can pair a current Xcode with an old runtime and trigger
# framework crashes. Choose the newest runtime supported by the active SDK and
# exclude newer beta runtimes that may also be installed on developer hosts.
xcrun simctl list devices available -j \
    | python3 "$script_dir/select_ios_simulator.py" --sdk-version "$sdk_version"
