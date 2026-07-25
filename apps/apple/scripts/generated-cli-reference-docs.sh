#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE="$ROOT/HealthMdCLI"
OUTPUT_DIR="$ROOT/docs/reference/generated/cli"
MODE=${1:-check}
TEST_FILTER="CLIReferenceDocumentationTests/testGeneratedCLIReferenceDocumentationIsCurrent"

usage() {
    printf 'usage: %s {update|check}\n' "${0##*/}" >&2
}

case "$MODE" in
    check)
        swift test --package-path "$PACKAGE" --filter "$TEST_FILTER"
        ;;
    update)
        TEMP_OUTPUT=$(mktemp -d "${TMPDIR:-/tmp}/healthmd-cli-reference.XXXXXX")
        trap 'rm -rf "$TEMP_OUTPUT"' EXIT
        HEALTHMD_CLI_REFERENCE_OUTPUT="$TEMP_OUTPUT" \
            swift test --package-path "$PACKAGE" --filter "$TEST_FILTER"
        rm -rf "$OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
        cp "$TEMP_OUTPUT"/* "$OUTPUT_DIR"/
        printf 'Updated %s\n' "$OUTPUT_DIR"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac
