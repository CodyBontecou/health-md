#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-export-lab-cli.sh [--identity CERTIFICATE] [--destination ABSOLUTE_PATH]

Builds the current standalone Rust healthmd CLI, signs it with a stable Apple
Development identity and fixed identifier, then atomically installs it. The
script never resets direct trust or Keychain credentials.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
IDENTITY="${HEALTHMD_LAB_CODESIGN_IDENTITY:-}"
DESTINATION="${HEALTHMD_LAB_CLI_PATH:-$HOME/Library/Application Support/HealthMdPerformanceLab/bin/healthmd}"
IDENTIFIER="com.codybontecou.healthmd.export-lab-cli"

while (($#)); do
  case "$1" in
    --identity)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      IDENTITY="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      DESTINATION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$DESTINATION" = /* ]] || { echo "Destination must be absolute." >&2; exit 2; }
case "$DESTINATION" in
  "$HOME"/Library/Application\ Support/HealthMdPerformanceLab/bin/*) ;;
  *) echo "Destination must stay under the private HealthMdPerformanceLab bin directory." >&2; exit 2 ;;
esac

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development:/ && !/CSSMERR/{print $2; exit}')"
fi
[[ -n "$IDENTITY" ]] || {
  echo "No Apple Development code-signing identity is available." >&2
  exit 1
}

CLI_WORKSPACE="$REPO_ROOT/apps/cli"
(
  cd "$CLI_WORKSPACE"
  cargo build --release --locked --bin healthmd
)
SOURCE="$CLI_WORKSPACE/target/release/healthmd"
[[ -x "$SOURCE" ]] || { echo "Cargo did not produce healthmd." >&2; exit 1; }

DESTINATION_DIR="$(dirname "$DESTINATION")"
mkdir -p "$DESTINATION_DIR"
chmod 700 "$DESTINATION_DIR"
TEMPORARY="$DESTINATION_DIR/.healthmd.$$.tmp"
trap 'rm -f "$TEMPORARY"' EXIT
cp "$SOURCE" "$TEMPORARY"
chmod 700 "$TEMPORARY"

codesign --force \
  --sign "$IDENTITY" \
  --identifier "$IDENTIFIER" \
  --options runtime \
  --timestamp=none \
  "$TEMPORARY"
codesign --verify --strict --verbose=2 "$TEMPORARY"
DESIGNATED_REQUIREMENT="$(codesign -dr - "$TEMPORARY" 2>&1 | tail -1)"
[[ "$DESIGNATED_REQUIREMENT" == *"identifier \"$IDENTIFIER\""* ]] || {
  echo "Signed CLI does not have the fixed designated identifier." >&2
  exit 1
}

mv -f "$TEMPORARY" "$DESTINATION"
trap - EXIT
VERSION="$(NO_COLOR=1 TERM=dumb "$DESTINATION" --version </dev/null)"

python3 - "$DESTINATION" "$VERSION" "$IDENTIFIER" <<'PY'
import json
import sys
print(json.dumps({
    "schema": "healthmd.export_lab_cli_install",
    "status": "success",
    "path": sys.argv[1],
    "version": sys.argv[2],
    "identifier": sys.argv[3],
}, sort_keys=True))
PY
