#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root="$tmp/evidence"
mkdir -p "$root/nested"
printf '{}\n' >"$root/release-attestation.json"
printf 'evidence\n' >"$root/nested/file.txt"
WEAR_EVIDENCE_HMAC_KEY=test-key ./scripts/seal-wear-release-evidence.sh "$root" >/dev/null
[[ -s "$root/SHA256SUMS" && -s "$root/SHA256SUMS.hmac-sha256" ]]
expected=$(openssl dgst -sha256 -hmac test-key "$root/SHA256SUMS" | awk '{print $NF}')
[[ $(tr -d '[:space:]' <"$root/SHA256SUMS.hmac-sha256") == "$expected" ]]
actual=$(awk '{print $2}' "$root/SHA256SUMS" | LC_ALL=C sort)
[[ "$actual" == $'nested/file.txt\nrelease-attestation.json' ]]
if WEAR_EVIDENCE_HMAC_KEY=test-key ./scripts/seal-wear-release-evidence.sh "$root" >/dev/null 2>&1; then
  echo 'seal helper overwrote an existing protected seal' >&2; exit 1
fi
printf 'Wear evidence protected-seal tests passed\n'
