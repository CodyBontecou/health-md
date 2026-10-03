#!/usr/bin/env bash
set -euo pipefail
manifest="wear/src/main/AndroidManifest.xml"; wear="wear/build.gradle.kts"; phone="app/build.gradle.kts"
fail(){ echo "wear validation: $*" >&2; exit 1; }
grep -q 'android.hardware.type.watch.*required="true"' "$manifest" || fail "required watch feature missing"
grep -q 'com.google.android.wearable.standalone.*false' "$manifest" || fail "standalone=false missing"
test "$(grep -c 'ComplicationService" android:exported' "$manifest")" -eq 10 || fail "expected 10 complications"
test "$(grep -c 'TileService" android:exported' "$manifest")" -eq 2 || fail "expected 2 Tiles"
! grep -Eq 'HealthConnect|Health Services|READ_HEART_RATE|BODY_SENSORS|ACTIVITY_RECOGNITION' "$manifest" || fail "watch health API/permission forbidden"
grep -q 'WearDiagnosticsProvider' "$manifest" && grep -q 'android:permission="android.permission.DUMP"' "$manifest" \
  || fail "release diagnostics must be DUMP-protected"
wear_package=$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' "$wear" | head -1)
phone_package=$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' "$phone" | head -1)
wear_min_sdk=$(sed -n 's/.*minSdk = \([0-9_]*\).*/\1/p' "$wear" | head -1 | tr -d _)
phone_min_sdk=$(sed -n 's/.*minSdk = \([0-9_]*\).*/\1/p' "$phone" | head -1 | tr -d _)
wear_target_sdk=$(sed -n 's/.*targetSdk = \([0-9_]*\).*/\1/p' "$wear" | head -1 | tr -d _)
phone_target_sdk=$(sed -n 's/.*targetSdk = \([0-9_]*\).*/\1/p' "$phone" | head -1 | tr -d _)
wear_name=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' "$wear" | head -1)
phone_name=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' "$phone" | head -1)
wear_code=$(sed -n 's/.*versionCode = \([0-9_]*\).*/\1/p' "$wear" | head -1 | tr -d _)
phone_code=$(sed -n 's/.*versionCode = \([0-9_]*\).*/\1/p' "$phone" | head -1 | tr -d _)
[[ -n "$wear_package" && "$wear_package" == "$phone_package" ]] || fail "application IDs differ"
[[ "$wear_min_sdk" == 30 && "$wear_target_sdk" == 36 ]] || fail "Wear SDK contract"
[[ -n "$phone_min_sdk" && -n "$phone_target_sdk" ]] || fail "phone SDK contract unavailable"
test "$wear_name" = "$phone_name" || fail "version names differ"
test "$phone_code" -lt 1000000 && test "$wear_code" -ge 1000000 && test "$wear_code" != "$phone_code" || fail "version-code range collision"
app_locales=$(find app/src/main/res -maxdepth 1 -type d -name 'values-*' ! -name 'values-night*' -exec basename {} \;|sort); wear_locales=$(find wear/src/main/res -maxdepth 1 -type d -name 'values-*' ! -name 'values-night*' -exec basename {} \;|sort)
test "$app_locales" = "$wear_locales" || fail "Wear locale directory parity"
python3 - <<'PY' || fail "locale key parity/nonblank"
import xml.etree.ElementTree as E, pathlib

def resources(path):
 values = {}
 for node in E.parse(path).getroot():
  if node.tag not in {'string', 'plurals'}: continue
  key = (node.tag, node.attrib['name'])
  assert key not in values, (path, key)
  if node.tag == 'string':
   text = ''.join(node.itertext()).strip()
   assert text, (path, key)
   values[key] = text
  else:
   items = {item.attrib.get('quantity'): ''.join(item.itertext()).strip() for item in node if item.tag == 'item'}
   assert items and all(items.values()) and 'other' in items, (path, key, items)
   values[key] = items
 return values

base = set(resources('wear/src/main/res/values/strings.xml'))
for path in pathlib.Path('wear/src/main/res').glob('values-*/strings.xml'):
 if path.parent.name.startswith('values-night'): continue
 localized = set(resources(path))
 assert localized == base, (path, base-localized, localized-base)
PY

wear_artifact="${1:-wear/build/outputs/apk/debug/wear-debug.apk}"
phone_artifact="${2:-}"
require_signing_attestation="${WEAR_REQUIRE_SIGNING_ATTESTATION:-false}"
if [[ "$require_signing_attestation" == true ]]; then
  [[ -f "$wear_artifact" ]] || fail "Wear AAB required for signing attestation"
  [[ "$wear_artifact" == *.aab ]] || fail "strict signing attestation requires a Wear AAB"
  [[ -n "$phone_artifact" && -f "$phone_artifact" ]] || fail "phone AAB required for signing attestation"
  [[ "$phone_artifact" == *.aab ]] || fail "strict signing attestation requires a phone AAB"
  [[ -n "${RELEASE_STORE_FILE:-}" ]] || fail "RELEASE_STORE_FILE required to attest release signing"
  [[ -n "${RELEASE_STORE_PASSWORD:-}" ]] || fail "RELEASE_STORE_PASSWORD required to attest release signing"
  [[ -n "${RELEASE_KEY_ALIAS:-}" ]] || fail "RELEASE_KEY_ALIAS required to attest release signing"
  [[ -n "${RELEASE_KEY_PASSWORD:-}" ]] || fail "RELEASE_KEY_PASSWORD required to attest release signing"
fi

# Artifact validation must never degrade to source-only success. In particular, callers that omit
# or mistype a release output must not receive a passing packaging result, and an AAB is always
# validated as the paired phone/Wear release rather than as an isolated form-factor upload.
[[ -f "$wear_artifact" ]] || fail "Wear artifact is missing: $wear_artifact"
case "$wear_artifact" in
  *.aab)
    [[ -n "$phone_artifact" && -f "$phone_artifact" ]] \
      || fail "phone AAB required for paired Wear AAB validation"
    [[ "$phone_artifact" == *.aab ]] || fail "paired phone artifact must be an AAB"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    unzip -tqq "$wear_artifact" || fail "invalid Wear AAB ZIP"
    # Parse the actual AAPT2 protobuf manifest rather than grepping opaque bytes or trusting source
    # Gradle values. Dependencies are resolved from the pinned local Gradle cache; validation fails
    # closed if CI has not resolved the Android plugin's matching protobuf runtime.
    proto_jar=$(find "$HOME/.gradle/caches/modules-2/files-2.1/com.android.tools.build/aapt2-proto" -name 'aapt2-proto-*.jar' -print | sort -V | tail -1)
    protobuf_jar=$(find "$HOME/.gradle/caches/modules-2/files-2.1/com.google.protobuf/protobuf-java" -name 'protobuf-java-*.jar' -print | sort -V | tail -1)
    [[ -f "$proto_jar" && -f "$protobuf_jar" ]] || fail "AAPT2 protobuf parser dependencies unavailable"
    javac -cp "$proto_jar:$protobuf_jar" -d "$tmp" scripts/WearBundleManifestVerifier.java \
      || fail "Wear manifest verifier compilation failed"
    java -cp "$tmp:$proto_jar:$protobuf_jar" WearBundleManifestVerifier wear \
      "$wear_artifact" "$wear_package" "$wear_code" "$wear_name" "$wear_min_sdk" "$wear_target_sdk" \
      || fail "packaged Wear manifest contract"
    unzip -tqq "$phone_artifact" || fail "invalid phone AAB ZIP"
    java -cp "$tmp:$proto_jar:$protobuf_jar" WearBundleManifestVerifier phone \
      "$phone_artifact" "$phone_package" "$phone_code" "$phone_name" "$phone_min_sdk" "$phone_target_sdk" \
      || fail "packaged phone manifest contract"
    if [[ "$require_signing_attestation" == true ]]; then
      # App Bundles are signed JARs. Verify both archives, extract each embedded upload signer,
      # and compare it to the configured upload certificate. Play App Signing identity remains a
      # separate credentialed Play Console gate because Play re-signs delivered APKs.
      test -f "$RELEASE_STORE_FILE" || fail "release keystore unavailable"
      expected_digest=$(keytool -exportcert -keystore "$RELEASE_STORE_FILE" \
        -storepass "$RELEASE_STORE_PASSWORD" -alias "$RELEASE_KEY_ALIAS" \
        -keypass "$RELEASE_KEY_PASSWORD" 2>/dev/null | sha256sum | awk '{print $1}')
      [[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]] || fail "upload certificate digest unavailable"
      for artifact in "$phone_artifact" "$wear_artifact"; do
        # jarsigner -strict rejects expected self-signed upload certificates and current AAB ZIP
        # ordering warnings; plain verification still cryptographically checks every signed entry.
        jarsigner -verify "$artifact" >/dev/null 2>&1 || fail "invalid AAB JAR signature: $artifact"
        signature_file=$(zipinfo -1 "$artifact" | grep -E '^META-INF/[^/]+\.(RSA|DSA|EC)$' | head -1)
        [[ -n "$signature_file" ]] || fail "AAB signer block missing: $artifact"
        unzip -p "$artifact" "$signature_file" > "$tmp/signer.p7"
        keytool -printcert -jarfile "$artifact" -rfc 2>/dev/null \
          | awk '/-----BEGIN CERTIFICATE-----/{capture=1} capture{print} /-----END CERTIFICATE-----/{exit}' \
          | openssl x509 -outform DER 2>/dev/null > "$tmp/signer.der" \
          || fail "AAB signer certificate unavailable: $artifact"
        artifact_digest=$(sha256sum "$tmp/signer.der" | awk '{print $1}')
        test "$artifact_digest" = "$expected_digest" || fail "AAB signer does not match configured upload key: $artifact"
      done
      for module in app wear; do
        for key in RELEASE_STORE_FILE RELEASE_STORE_PASSWORD RELEASE_KEY_ALIAS RELEASE_KEY_PASSWORD; do
          grep -q "getProperty(\"$key\"" "$module/build.gradle.kts" || fail "$module does not use shared $key"
        done
      done
      echo "Both AAB signatures match upload certificate SHA-256 $expected_digest; Play signer identity requires credentialed Play verification"
    else
      echo "Signing comparison not performed (set WEAR_REQUIRE_SIGNING_ATTESTATION=true with release keystore environment)"
    fi
    ;;
  *.apk)
    aapt="${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/aapt"; test -x "$aapt" || fail "aapt unavailable"
    "$aapt" dump badging "$wear_artifact" | grep -q "package: name='com.healthmd.android'.*versionCode='$wear_code'" || fail "packaged identity"
    "$aapt" dump badging "$wear_artifact" | grep -q "uses-feature: name='android.hardware.type.watch'" || fail "packaged watch feature"
    ;;
  *) fail "unsupported Wear artifact type (expected .apk or .aab): $wear_artifact" ;;
esac
echo "Wear artifact contract valid"
