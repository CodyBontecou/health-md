#!/bin/sh
# One fingerprint for locally prepared and CI-assembled native libraries.
set -eu
workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$workspace_root/../.." && pwd)
(
    cd "$workspace_root"
    {
        printf '%s\n' Cargo.toml Cargo.lock rust-toolchain.toml
        find crates/healthmd-core crates/healthmd-core-uniffi crates/healthmd-protocol vendor -type f -print
        printf '%s\n' scripts/build-apple-xcframework.sh scripts/normalize-apple-xcframework.py \
            scripts/validate-apple-xcframework.sh scripts/apple-source-digest.sh
    } | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done
    cd "$repo_root/apps/apple/Packages/HealthMdCoreRust"
    find Bindings -type f -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done
) | shasum -a 256 | awk '{ print $1 }'
