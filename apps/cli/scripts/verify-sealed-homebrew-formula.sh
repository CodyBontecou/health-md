#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: verify-sealed-homebrew-formula.sh ARTIFACT_ROOT TAG OUTPUT_FORMULA" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
artifact_root="$1"
tag="$2"
output_formula="$3"
[[ ! -L "$output_formula" ]] || {
  echo "verified formula output must not be a symlink" >&2
  exit 1
}
[[ -d "$artifact_root" && ! -L "$artifact_root" ]] || {
  echo "sealed artifact root is missing or symlinked" >&2
  exit 1
}
[[ "$tag" =~ ^healthmd-cli/v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?$ ]] || {
  echo "invalid Health.md CLI release tag" >&2
  exit 1
}
for name in GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_REF; do
  [[ -n "${!name:-}" ]] || {
    echo "required GitHub Actions identity input $name is missing" >&2
    exit 1
  }
done
command -v cosign >/dev/null 2>&1 || {
  echo "cosign is required to verify the sealed formula" >&2
  exit 1
}

count_named_file() {
  find "$artifact_root" -type f -name "$1" | wc -l | tr -d ' '
}
[[ "$(count_named_file healthmd.rb)" == 1 ]] || {
  echo "sealed artifacts must contain exactly one healthmd.rb" >&2
  exit 1
}
[[ "$(count_named_file sha256.sum)" == 1 ]] || {
  echo "sealed artifacts must contain exactly one sha256.sum" >&2
  exit 1
}
[[ "$(count_named_file sha256.sum.sigstore.json)" == 1 ]] || {
  echo "sealed artifacts must contain exactly one Sigstore bundle" >&2
  exit 1
}
formula="$(find "$artifact_root" -type f -name healthmd.rb -print)"
manifest="$(find "$artifact_root" -type f -name sha256.sum -print)"
bundle="$(find "$artifact_root" -type f -name sha256.sum.sigstore.json -print)"
expected_identity="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/.github/workflows/cli-release.yml@${GITHUB_REF}"
cosign verify-blob \
  --bundle "$bundle" \
  --certificate-identity "$expected_identity" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$manifest"

[[ "$(awk '$2 == "healthmd.rb" { count++ } END { print count + 0 }' "$manifest")" == 1 ]] || {
  echo "signed checksum manifest must contain exactly one healthmd.rb row" >&2
  exit 1
}
expected_digest="$(awk '$2 == "healthmd.rb" { print $1 }' "$manifest")"
if command -v sha256sum >/dev/null 2>&1; then
  actual_digest="$(sha256sum "$formula" | awk '{ print $1 }')"
else
  actual_digest="$(shasum -a 256 "$formula" | awk '{ print $1 }')"
fi
[[ "$actual_digest" == "$expected_digest" ]] || {
  echo "sealed Homebrew formula digest differs from the signed manifest" >&2
  exit 1
}
if grep -F '/releases/latest' "$formula" >/dev/null; then
  echo "Homebrew formula must not use the repository-wide latest release" >&2
  exit 1
fi
grep -F "$tag" "$formula" >/dev/null || {
  echo "Homebrew formula does not reference the exact release tag" >&2
  exit 1
}

mkdir -p "$(dirname "$output_formula")"
cp "$formula" "$output_formula"
cmp "$formula" "$output_formula"
