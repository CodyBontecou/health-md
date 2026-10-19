#!/usr/bin/env bash
# Reuse compilation outputs while the CI init script keeps tests executing.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <Gradle tasks and options>" >&2
    exit 2
fi

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ANDROID_DIR"

exec ./gradlew --build-cache --init-script "$ANDROID_DIR/scripts/ci-gradle.init.gradle" --profile "$@"
