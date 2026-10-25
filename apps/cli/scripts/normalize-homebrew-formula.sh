#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: normalize-homebrew-formula.sh FORMULA [SHA256_MANIFEST]" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

formula="$1"
checksum_manifest="${2:-}"
[[ -f "$formula" && ! -L "$formula" && "$formula" == *.rb ]] || {
  echo "Homebrew formula is missing, symlinked, or not a Ruby file" >&2
  exit 1
}
if [[ -n "$checksum_manifest" ]]; then
  [[ -f "$checksum_manifest" && ! -L "$checksum_manifest" ]] || {
    echo "checksum manifest is missing or symlinked" >&2
    exit 1
  }
fi

brew_executable="$(command -v brew || true)"
[[ -n "$brew_executable" ]] || {
  echo "Homebrew is required to normalize the generated formula" >&2
  exit 1
}

formula="$(cd "$(dirname "$formula")" && pwd)/$(basename "$formula")"
if [[ -n "$checksum_manifest" ]]; then
  checksum_manifest="$(cd "$(dirname "$checksum_manifest")" && pwd)/$(basename "$checksum_manifest")"
fi
filename="$(basename "$formula")"
[[ "$filename" == healthmd.rb ]] || {
  echo "expected the generated healthmd.rb formula" >&2
  exit 1
}
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/healthmd-homebrew-style.XXXXXX")"
cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT

# `brew style` applies the formula cops only when the file belongs to a tap. Use an isolated,
# synthetic tap so formatter output cannot depend on or mutate the publication repository.
git -C "$work" init -q
git -C "$work" remote add origin https://github.com/CodyBontecou/homebrew-tap.git
mkdir -p "$work/Formula"
# Current Homebrew requires a Sorbet sigil that its style wrapper cannot exclude.
# Add it before sealing, never to an already signed formula during qualification.
if grep -q '^# typed:' "$formula"; then
  cp "$formula" "$work/Formula/$filename"
else
  {
    printf '# typed: strict\n\n'
    awk '1' "$formula"
  } > "$work/Formula/$filename"
fi
# cargo-dist does not emit a formula test. Add a device-free check of the
# installed binary before styling/sealing; preserve an existing custom test.
python3 - "$work/Formula/$filename" <<'PYFORMULA'
import pathlib
import re
import sys

formula = pathlib.Path(sys.argv[1])
text = formula.read_text()
if not re.search(r"^\s*test do\s*$", text, re.MULTILINE):
    if not text.endswith("\nend\n"):
        raise SystemExit("generated formula has no final class terminator")
    test = ('  test do\n'
            '    result = JSON.parse(shell_output("#{bin}/healthmd mcp schema healthmd_sleep_sessions"))\n'
            '    assert_equal "healthmd.mcp_tool_schema", result.fetch("schema")\n'
            '    assert_equal "healthmd_sleep_sessions", result.fetch("tool").fetch("name")\n'
            '  end\n')
    formula.write_text(text[:-4] + "\n" + test + "end\n")
PYFORMULA
(
  cd "$work"
  "$brew_executable" style \
    --except-cops FormulaAudit/Homepage,FormulaAudit/Desc,FormulaAuditStrict \
    --fix "Formula/$filename" || true
  "$brew_executable" style \
    --except-cops FormulaAudit/Homepage,FormulaAudit/Desc,FormulaAuditStrict \
    "Formula/$filename"
)
cp "$work/Formula/$filename" "$formula"

if [[ -n "$checksum_manifest" ]]; then
  manifest_tmp="$work/sha256.sum"
  awk -v filename="$filename" 'NF > 0 && $2 != filename' "$checksum_manifest" > "$manifest_tmp"
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "$formula" | cut -d ' ' -f 1)"
  else
    digest="$(shasum -a 256 "$formula" | cut -d ' ' -f 1)"
  fi
  printf '%s  %s\n' "$digest" "$filename" >> "$manifest_tmp"
  LC_ALL=C sort -k2,2 -o "$manifest_tmp" "$manifest_tmp"
  mv "$manifest_tmp" "$checksum_manifest"
fi
