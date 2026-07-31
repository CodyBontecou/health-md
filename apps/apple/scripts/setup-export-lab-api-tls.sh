#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-export-lab-api-tls.sh [--host LAN_IP_OR_DNS]

Creates a private local CA, a server certificate for the selected Mac LAN host,
and a bearer-token file under HealthMdPerformanceLab/TLS. The CA private key is
never printed. Installing and fully trusting the generated CA certificate on the
supervised iPhone remains an explicit user action.
EOF
}

HOST=""
while (($#)); do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      HOST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  HOST="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
[[ -n "$HOST" ]] || { echo "Pass --host with the Mac LAN IP or DNS name." >&2; exit 1; }
[[ "$HOST" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Host contains unsupported characters." >&2; exit 2; }

OPENSSL="${OPENSSL_BIN:-$(command -v openssl || true)}"
[[ -x "$OPENSSL" ]] || { echo "openssl is required." >&2; exit 1; }
ROOT="$HOME/Library/Application Support/HealthMdPerformanceLab/TLS"
mkdir -p "$ROOT"
chmod 700 "$ROOT"
CA_KEY="$ROOT/ca-key.pem"
CA_CERT="$ROOT/ca-certificate.pem"
SERVER_KEY="$ROOT/server-key.pem"
SERVER_CERT="$ROOT/server-certificate.pem"
TOKEN_FILE="$ROOT/api-token"
CONFIG="$ROOT/server-cert.cnf"

if [[ -f "$CA_CERT" ]]; then
  CA_DESCRIPTION="$("$OPENSSL" x509 -in "$CA_CERT" -noout -text 2>/dev/null || true)"
  if [[ "$CA_DESCRIPTION" != *"CA:TRUE"* || "$CA_DESCRIPTION" != *"X509v3 Key Usage"* ]]; then
    rm -f "$CA_KEY" "$CA_CERT" "$ROOT/ca-certificate.srl"
  fi
fi
if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
  "$OPENSSL" genrsa -out "$CA_KEY" 4096 >/dev/null 2>&1
  chmod 600 "$CA_KEY"
  "$OPENSSL" req -x509 -new -sha256 -days 825 \
    -key "$CA_KEY" \
    -subj "/CN=HealthMd Physical Export Lab CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" \
    -out "$CA_CERT"
  chmod 600 "$CA_CERT"
fi

if [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  SAN="IP.1 = $HOST"
else
  SAN="DNS.1 = $HOST"
fi
cat >"$CONFIG" <<EOF
[req]
prompt = no
distinguished_name = subject
req_extensions = extensions
[subject]
CN = $HOST
[extensions]
subjectAltName = @alt_names
extendedKeyUsage = serverAuth
keyUsage = digitalSignature, keyEncipherment
[alt_names]
$SAN
DNS.2 = localhost
IP.2 = 127.0.0.1
EOF
chmod 600 "$CONFIG"

"$OPENSSL" genrsa -out "$SERVER_KEY" 3072 >/dev/null 2>&1
chmod 600 "$SERVER_KEY"
CSR="$ROOT/server.csr"
"$OPENSSL" req -new -key "$SERVER_KEY" -out "$CSR" -config "$CONFIG"
"$OPENSSL" x509 -req -sha256 -days 397 \
  -in "$CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -extensions extensions \
  -extfile "$CONFIG" \
  -out "$SERVER_CERT" >/dev/null 2>&1
rm -f "$CSR"
chmod 600 "$SERVER_CERT"

if [[ ! -f "$TOKEN_FILE" ]]; then
  "$OPENSSL" rand -hex 32 >"$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"

python3 - "$HOST" "$CA_CERT" "$SERVER_CERT" "$SERVER_KEY" "$TOKEN_FILE" <<'PY'
import json
import sys
print(json.dumps({
    "schema": "healthmd.export_lab_tls_setup",
    "status": "success",
    "api_url": f"https://{sys.argv[1]}:18443/export",
    "iphone_ca_certificate": sys.argv[2],
    "server_certificate": sys.argv[3],
    "server_private_key": sys.argv[4],
    "token_file": sys.argv[5],
    "next_action": "Install the CA certificate on iPhone and enable full trust, then configure the API Endpoint URL and bearer token in Health.md.",
}, sort_keys=True, indent=2))
PY
