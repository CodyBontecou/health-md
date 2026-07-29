#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$workspace_root/../.." && pwd)
package_root="$repo_root/apps/apple/Packages/HealthMdCoreRust"
xcframework=${1:-"$package_root/Artifacts/HealthmdCore.xcframework"}
stamp="$(dirname -- "$xcframework")/.healthmd-core-source.sha256"

"$workspace_root/scripts/generate-apple-bindings.sh" --check

source_digest=$(
    (
        cd "$workspace_root"
        {
            printf '%s\n' Cargo.toml Cargo.lock rust-toolchain.toml
            find crates/healthmd-core crates/healthmd-core-uniffi crates/healthmd-protocol -type f -print
            printf '%s\n' \
                scripts/build-apple-xcframework.sh \
                scripts/normalize-apple-xcframework.py \
                scripts/validate-apple-xcframework.sh
        } | LC_ALL=C sort | while IFS= read -r file; do
            shasum -a 256 "$file"
        done

        cd "$package_root"
        find Bindings -type f -print | LC_ALL=C sort | while IFS= read -r file; do
            shasum -a 256 "$file"
        done
    ) | shasum -a 256 | awk '{ print $1 }'
)

prepared_digest=""
if [ -f "$stamp" ]; then
    prepared_digest=$(tr -d '[:space:]' < "$stamp")
fi

if [ "${HEALTHMD_CORE_FORCE_REBUILD:-0}" = "1" ] \
    || [ ! -f "$xcframework/Info.plist" ] \
    || [ "$prepared_digest" != "$source_digest" ]; then
    "$workspace_root/scripts/build-apple-xcframework.sh" "$xcframework"
    printf '%s\n' "$source_digest" > "$stamp"
else
    echo "HealthmdCore XCFramework already matches the current shared Rust source"
fi

"$workspace_root/scripts/validate-apple-xcframework.sh" "$xcframework"
