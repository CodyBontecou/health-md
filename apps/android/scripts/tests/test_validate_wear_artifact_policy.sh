#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
script=scripts/validate-wear-artifact.sh

for spec in \
  'RELEASE_STORE_FILE:RELEASE_STORE_FILE required to attest release signing' \
  'RELEASE_STORE_PASSWORD:RELEASE_STORE_PASSWORD required to attest release signing' \
  'RELEASE_KEY_ALIAS:RELEASE_KEY_ALIAS required to attest release signing' \
  'RELEASE_KEY_PASSWORD:RELEASE_KEY_PASSWORD required to attest release signing'; do
  key=${spec%%:*}
  message=${spec#*:}
  grep -Fq "[[ -n \"\${$key:-}\" ]] || fail \"$message\"" "$script" || {
    echo "missing explicit fail-closed signing input check: $key" >&2
    exit 1
  }
done

if grep -Eq 'RELEASE_(STORE_FILE|STORE_PASSWORD|KEY_ALIAS|KEY_PASSWORD):\?' "$script"; then
  echo 'parameter-expansion signing checks can return a false-success status from the artifact validator' >&2
  exit 1
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
expect_strict_failure() {
  local expected=$1 name=$2 wear_path=$3 phone_path=$4
  if env -u RELEASE_STORE_FILE -u RELEASE_STORE_PASSWORD -u RELEASE_KEY_ALIAS -u RELEASE_KEY_PASSWORD \
      WEAR_REQUIRE_SIGNING_ATTESTATION=true \
      "$script" "$wear_path" "$phone_path" >"$tmp/$name.out" 2>&1; then
    echo "strict artifact validator unexpectedly accepted: $name" >&2
    exit 1
  fi
  grep -Fq "$expected" "$tmp/$name.out" || {
    cat "$tmp/$name.out" >&2
    echo "strict artifact validator failed for the wrong reason: $name" >&2
    exit 1
  }
}

# These behavioral negatives are unconditional and require no built artifact, keystore, SDK, or
# external service. They prove strict mode cannot skip attestation on absent/wrong-type inputs.
expect_strict_failure 'Wear AAB required for signing attestation' missing-wear \
  "$tmp/missing-wear.aab" "$tmp/missing-phone.aab"
touch "$tmp/wear.apk" "$tmp/phone.aab"
expect_strict_failure 'strict signing attestation requires a Wear AAB' wrong-wear-type \
  "$tmp/wear.apk" "$tmp/phone.aab"
touch "$tmp/wear.aab"
rm -f "$tmp/phone.aab"
expect_strict_failure 'phone AAB required for signing attestation' missing-phone \
  "$tmp/wear.aab" "$tmp/missing-phone.aab"
touch "$tmp/phone.apk"
expect_strict_failure 'strict signing attestation requires a phone AAB' wrong-phone-type-strict \
  "$tmp/wear.aab" "$tmp/phone.apk"
touch "$tmp/phone.aab"
expect_strict_failure 'RELEASE_STORE_FILE required to attest release signing' missing-signing-inputs \
  "$tmp/wear.aab" "$tmp/phone.aab"

expect_validation_failure() {
  local expected=$1 name=$2 wear_path=$3 phone_path=${4:-}
  if WEAR_REQUIRE_SIGNING_ATTESTATION=false \
      "$script" "$wear_path" "$phone_path" >"$tmp/$name.out" 2>&1; then
    echo "artifact validator unexpectedly accepted: $name" >&2
    exit 1
  fi
  grep -Fq "$expected" "$tmp/$name.out" || {
    cat "$tmp/$name.out" >&2
    echo "artifact validator failed for the wrong reason: $name" >&2
    exit 1
  }
}

# Non-strict packaging validation is still artifact validation. It must not return source-only
# success for a missing output, an unknown archive type, or an unpaired Wear AAB.
expect_validation_failure 'Wear artifact is missing:' missing-nonstrict \
  "$tmp/missing-nonstrict.aab" "$tmp/phone.aab"
touch "$tmp/wear.bin"
expect_validation_failure 'unsupported Wear artifact type' unsupported-type \
  "$tmp/wear.bin" "$tmp/phone.aab"
expect_validation_failure 'phone AAB required for paired Wear AAB validation' unpaired-wear-aab \
  "$tmp/wear.aab" "$tmp/missing-paired-phone.aab"
touch "$tmp/phone.apk"
expect_validation_failure 'paired phone artifact must be an AAB' wrong-phone-type \
  "$tmp/wear.aab" "$tmp/phone.apk"

echo 'Wear artifact fail-closed policy checks passed'
