#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: sign-macos-archive.sh ARCHIVE TARGET VERSION" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
[[ "$(uname -s)" == Darwin ]] || { echo "macOS signing must run on macOS" >&2; exit 1; }

archive="$1"
target="$2"
version="$3"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
identity_ledger="$script_directory/../release-identities.json"
[[ -f "$identity_ledger" ]] || { echo "release identity ledger is missing" >&2; exit 1; }
apple_team_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apple"]["team_id"])' "$identity_ledger")"
healthmd_identifier="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apple"]["healthmd_identifier"])' "$identity_ledger")"
healthmd_mcp_identifier="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apple"]["healthmd_mcp_identifier"])' "$identity_ledger")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || {
  echo "invalid release version" >&2
  exit 1
}
[[ -f "$archive" && "$archive" == *.tar.xz ]] || { echo "candidate archive is missing or unsupported" >&2; exit 1; }
[[ "$target" == aarch64-apple-darwin || "$target" == x86_64-apple-darwin ]] || {
  echo "unsupported macOS release target" >&2
  exit 1
}
[[ "$archive" == *"healthmd-cli-${target}.tar.xz" ]] || {
  echo "archive does not match the requested target" >&2
  exit 1
}

required_environment=(
  APPLE_CLI_CERTIFICATE_P12
  APPLE_CLI_CERTIFICATE_PASSWORD
  APPLE_TEAM_ID
  APPLE_NOTARY_KEY_P8_BASE64
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
)
for name in "${required_environment[@]}"; do
  [[ -n "${!name:-}" ]] || { echo "required signing input $name is missing" >&2; exit 1; }
done
# APPLE_TEAM_ID is validated through the indirect required_environment loop above.
# shellcheck disable=SC2153
[[ "$APPLE_TEAM_ID" == "$apple_team_id" ]] || {
  echo "Apple signing team differs from the committed release identity" >&2
  exit 1
}

archive="$(python3 - "$archive" <<'PY'
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
)"
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/healthmd-cli-sign.XXXXXX")"
keychain="$work/signing.keychain-db"
keychain_password="$(openssl rand -base64 32)"
certificate="$work/developer-id.p12"
notary_key="$work/AuthKey_${APPLE_NOTARY_KEY_ID}.p8"
original_default="$(security default-keychain -d user 2>/dev/null | tr -d '"' || true)"
original_keychains=()
while IFS= read -r existing; do
  existing="$(printf '%s' "$existing" | tr -d '"' | sed 's/^[[:space:]]*//')"
  [[ -n "$existing" ]] && original_keychains+=("$existing")
done < <(security list-keychains -d user 2>/dev/null || true)

cleanup() {
  set +e
  if [[ -n "$original_default" ]]; then
    security default-keychain -d user -s "$original_default" >/dev/null 2>&1
  fi
  if [[ ${#original_keychains[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1
  fi
  security delete-keychain "$keychain" >/dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
printf '%s' "$APPLE_CLI_CERTIFICATE_P12" | base64 --decode > "$certificate"
security import "$certificate" -P "$APPLE_CLI_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
security default-keychain -d user -s "$keychain"
security set-key-partition-list \
  -S apple-tool:,apple:,codesign:,productsign: -s -k "$keychain_password" "$keychain" >/dev/null
rm -f "$certificate"

identities="$work/identities.txt"
security find-identity -v -p codesigning "$keychain" > "$identities"
identity_count="$(grep -c "Developer ID Application: .*(${APPLE_TEAM_ID})" "$identities" || true)"
[[ "$identity_count" == 1 ]] || {
  echo "expected exactly one Developer ID Application identity for APPLE_TEAM_ID" >&2
  exit 1
}
signing_identity="$(grep "Developer ID Application: .*(${APPLE_TEAM_ID})" "$identities" | awk '{print $2}')"
[[ "$signing_identity" =~ ^[0-9A-Fa-f]{40}$ ]] || { echo "invalid signing identity" >&2; exit 1; }

unpacked="$work/unpacked"
python3 "$script_directory/safe-extract-release.py" "$archive" "$unpacked"
chmod -R u+w "$unpacked"
root_count="$(find "$unpacked" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
[[ "$root_count" == 1 ]] || { echo "candidate archive must contain one top-level directory" >&2; exit 1; }
root="$(find "$unpacked" -mindepth 1 -maxdepth 1 -type d -print -quit)"
healthmd="$(find "$root" -type f -name healthmd -perm -111 -print -quit)"
mcp="$(find "$root" -type f -name healthmd-mcp -perm -111 -print -quit)"
[[ -n "$healthmd" && -n "$mcp" ]] || { echo "candidate archive is missing both executables" >&2; exit 1; }
[[ "$(find "$root" -type f -name healthmd -perm -111 | wc -l | tr -d ' ')" == 1 ]] || exit 1
[[ "$(find "$root" -type f -name healthmd-mcp -perm -111 | wc -l | tr -d ' ')" == 1 ]] || exit 1

# Sign two independently produced copies with one fixed identifier. The old copy is used below to
# prove that the Keychain ACL's designated requirement survives replacement by the release copy.
upgrade_old="$work/healthmd-previous"
cp "$healthmd" "$upgrade_old"
codesign --force --timestamp --options runtime \
  --identifier "$healthmd_identifier" --sign "$signing_identity" "$upgrade_old"
codesign --force --timestamp --options runtime \
  --identifier "$healthmd_identifier" --sign "$signing_identity" "$healthmd"
codesign --force --timestamp --options runtime \
  --identifier "$healthmd_mcp_identifier" --sign "$signing_identity" "$mcp"

for executable in "$upgrade_old" "$healthmd" "$mcp"; do
  codesign --verify --strict --verbose=2 "$executable"
  details="$(codesign -dv --verbose=4 "$executable" 2>&1)"
  grep -F "TeamIdentifier=${APPLE_TEAM_ID}" <<<"$details" >/dev/null
  expected_identifier="$healthmd_identifier"
  [[ "$(basename "$executable")" == healthmd-mcp ]] && expected_identifier="$healthmd_mcp_identifier"
  [[ "$(sed -n 's/^Identifier=//p' <<<"$details")" == "$expected_identifier" ]] || {
    echo "signed executable identifier differs from the committed release identity" >&2
    exit 1
  }
done
codesign -d -r- "$upgrade_old" 2>&1 | grep '^designated =>' > "$work/old.requirement"
codesign -d -r- "$healthmd" 2>&1 | grep '^designated =>' > "$work/new.requirement"
cmp "$work/old.requirement" "$work/new.requirement"
grep -F "identifier \"${healthmd_identifier}\"" "$work/new.requirement" >/dev/null
codesign -d -r- "$mcp" 2>&1 | grep '^designated =>' > "$work/mcp.requirement"
grep -F "identifier \"${healthmd_mcp_identifier}\"" "$work/mcp.requirement" >/dev/null

# A signed update must retain access to the deployed native trust service without allowing a hidden
# authorization prompt. Exercise the real same-executable credential helper against an ACL granted
# to the previous signed copy. The fixture is a synthetic, health-free trusted-device record whose
# fixed identity proves that the exact deployed service/account was read.
credential_state="$work/credential-state"
mkdir -m 700 "$credential_state"
HEALTHMD_CLI_DATA_DIR="$credential_state" "$upgrade_old" --backend direct direct devices \
  > "$work/previous-devices.json"
owner_id="$(python3 - "$credential_state/identity.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["installationID"])
PY
)"
python3 - "$owner_id" > "$work/trust.json" <<'PY'
import base64, json, sys
json.dump({
    "ownerInstallationID": sys.argv[1],
    "trustedClients": [{
        "installationID": "11111111-1111-4111-8111-111111111111",
        "displayName": "Signing Fixture",
        "platform": "ios",
        "reconnectSecret": base64.b64encode(bytes(32)).decode("ascii"),
        "pairedAt": 800000000.0,
        "lastConnectedAt": 800000000.0,
    }],
}, sys.stdout, separators=(",", ":"))
PY
security add-generic-password -U \
  -a trust-state-v1 \
  -s com.codybontecou.obsidianhealth.direct-cli-trust \
  -w "$(cat "$work/trust.json")" \
  -T "$upgrade_old" \
  "$keychain" >/dev/null
HEALTHMD_CLI_DATA_DIR="$credential_state" "$healthmd" --backend direct direct devices \
  > "$work/upgraded-devices.json"
python3 - "$work/upgraded-devices.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
assert value["schema"] == "healthmd.direct_devices", value
assert len(value["devices"]) == 1, value
device = value["devices"][0]
assert device["installation_id"] == "11111111-1111-4111-8111-111111111111", value
assert device["name"] == "Signing Fixture", value
assert device["platform"] == "ios", value
PY
security delete-generic-password \
  -a trust-state-v1 \
  -s com.codybontecou.obsidianhealth.direct-cli-trust \
  "$keychain" >/dev/null

# Apple's documented custom workflow for staple-able command-line tools submits the
# executables inside a zip archive, waits for acceptance, and staples the tickets onto the
# unzipped binaries. Tickets are not retrievable for executables that were only submitted
# inside a DMG (stapler reports a missing ticket indefinitely), so the binaries get their own
# zip submission and the DMG is assembled afterwards from the stapled executables.
root_name="$(basename "$root")"

submit_and_wait() {
  xcrun notarytool submit "$1" \
    --key "$notary_key" \
    --key-id "$APPLE_NOTARY_KEY_ID" \
    --issuer "$APPLE_NOTARY_ISSUER_ID" \
    --wait --output-format json > "$work/notary-result.json"
  python3 - "$work/notary-result.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
assert value.get("status") == "Accepted", value
assert value.get("id"), value
PY
}

# Ticket propagation for code nested inside an accepted submission lags the acceptance by
# seconds to minutes; stapler reports a missing ticket (error 73) until it has propagated.
staple_with_retry() {
  local item="$1" attempt
  for attempt in $(seq 1 10); do
    if xcrun stapler staple "$item"; then
      xcrun stapler validate "$item"
      return 0
    fi
    echo "staple attempt ${attempt} for $(basename "$item") failed; waiting for ticket propagation" >&2
    sleep 45
  done
  echo "staple for $(basename "$item") never succeeded" >&2
  return 1
}

printf '%s' "$APPLE_NOTARY_KEY_P8_BASE64" | base64 --decode > "$notary_key"
chmod 600 "$notary_key"

binaries_zip="$work/healthmd-cli-${TARGET}-binaries.zip"
rm -f "$binaries_zip"
( cd "$root" && zip -q -X "$binaries_zip" "$(basename "$healthmd")" "$(basename "$mcp")" )
submit_and_wait "$binaries_zip"
staple_with_retry "$healthmd"
staple_with_retry "$mcp"

# Assemble the DMG from the stapled executables, notarize it, and staple it.
dmg="${archive%.tar.xz}.dmg"
rm -f "$dmg"
COPYFILE_DISABLE=1 hdiutil create \
  -quiet -format UDZO -fs HFS+ -volname "Health.md CLI" -srcfolder "$root" "$dmg"
codesign --force --timestamp --sign "$signing_identity" "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
submit_and_wait "$dmg"
staple_with_retry "$dmg"

# Repack the tar archive from the same stapled executables the DMG carries.
rm -f "$archive"
COPYFILE_DISABLE=1 tar -cJf "$archive" -C "$unpacked" "$root_name"

spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
spctl --assess --type execute --verbose=2 "$healthmd"
spctl --assess --type execute --verbose=2 "$mcp"

printf 'signed_archive=%s\nstapled_dmg=%s\n' "$archive" "$dmg"
