#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .test-signing
chmod 700 .test-signing
key=.test-signing/candidate-test.p12
if [[ ! -f "$key" ]]; then
  # Private test identity only. Initial key generation is random; repeat builds retain this key.
  keytool -genkeypair -keystore "$key" -storetype PKCS12 -alias candidate-test \
    -storepass healthmd-private-test-only -keypass healthmd-private-test-only \
    -keyalg RSA -keysize 2048 -validity 3650 \
    -dname 'CN=Health.md private synthetic test,OU=Not distribution signing,O=Local candidate' >/dev/null 2>&1
  chmod 600 "$key"
fi
keytool -exportcert -keystore "$key" -storepass healthmd-private-test-only -alias candidate-test \
  -file .test-signing/candidate-test.der >/dev/null 2>&1
shasum -a 256 .test-signing/candidate-test.der | cut -d ' ' -f 1 > .test-signing/public-certificate.sha256
echo 'Private test certificate ready; distribution signing remains unqualified.'
