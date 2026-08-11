#!/usr/bin/env bash
set -euo pipefail

android_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$android_root"

if ! command -v gplay >/dev/null 2>&1; then
  echo "error: gplay 0.8.0 is required (https://github.com/tamtom/play-console-cli)" >&2
  exit 1
fi

python3 -m unittest discover -s scripts/tests -p 'test_*.py'

all_metadata="$android_root/build/play-metadata/all"
reviewed_metadata="$android_root/build/play-metadata/reviewed"

python3 scripts/prepare-play-metadata.py \
  --include-drafts \
  --output-dir "$all_metadata"

NO_COLOR=1 TERM=dumb timeout 60 gplay validate listing \
  --dir "$all_metadata" \
  --output table \
  </dev/null
NO_COLOR=1 TERM=dumb timeout 60 gplay validate screenshots \
  --dir "$all_metadata" \
  --output table \
  </dev/null

python3 scripts/prepare-play-metadata.py \
  --output-dir "$reviewed_metadata"

NO_COLOR=1 TERM=dumb timeout 60 gplay validate listing \
  --dir "$reviewed_metadata" \
  --output table \
  </dev/null
NO_COLOR=1 TERM=dumb timeout 60 gplay validate screenshots \
  --dir "$reviewed_metadata" \
  --output table \
  </dev/null

echo "Google Play listing validation passed."
echo "Reviewed publishing input: $reviewed_metadata"
