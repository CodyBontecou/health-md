#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: WEAR_EVIDENCE_HMAC_KEY=<protected key> seal-wear-release-evidence.sh EVIDENCE_ROOT

Run only inside the protected evidence-ingest job after safe archive extraction. The submitted
archive must not contain SHA256SUMS or SHA256SUMS.hmac-sha256; this command creates both and refuses
to overwrite any seal. The symmetric seal protects the retained artifact against post-ingest
mutation. It does not prove the human attestor identity by itself; protected-environment approval
and the configured EXPECTED_ATTESTOR remain separate trust inputs.
EOF
  exit 64
}
[[ $# -eq 1 ]] || usage
root=$1
key=${WEAR_EVIDENCE_HMAC_KEY:-}
[[ -n "$key" ]] || usage
[[ -d "$root" ]] || { echo "Evidence root missing: $root" >&2; exit 65; }
[[ ! -e "$root/SHA256SUMS" && ! -e "$root/SHA256SUMS.hmac-sha256" ]] || {
  echo 'Refusing to overwrite submitted or existing evidence seal' >&2; exit 73;
}
(
  cd "$root"
  find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.hmac-sha256 -print \
    | sed 's#^\./##' | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done >SHA256SUMS
  openssl dgst -sha256 -hmac "$key" SHA256SUMS | awk '{print $NF}' >SHA256SUMS.hmac-sha256
)
echo "Protected Wear evidence seal created at $root"
