//! End-to-end TLS coverage for the read-only S3-compatible object store Agent Data backing.
//!
//! Everything in this file is gated behind the non-default `object-store-tls` cargo feature
//! (the established pattern — see `tests/agent_data_http.rs`): default-feature builds compile
//! this file to nothing, and the unedited `tests/agent_data_object.rs` keeps proving the
//! feature-off boundary there (`https://` fails health-free with the stable
//! `https object-store transport is not available` error).
//!
//! These tests build a synthetic loopback S3 double that speaks the SAME frozen subset
//! (`ListObjectsV2` with prefix + continuation, `HEAD` object, `GET` object with `Range`) at
//! path-style addresses, but over **TLS** (`rustls` server side), with a SYNTHETIC
//! self-signed certificate. The double `SigV4`-verifies every request against fixed synthetic
//! test keys — mirroring `tests/agent_data_object.rs`'s test-side signer discipline — and logs
//! every request method and path. The REAL `healthmd mcp serve-data
//! --object-store-url https://127.0.0.1:<port>` binary is then driven over newline-delimited
//! JSON-RPC stdio. Because every request is logged only after TLS decryption and every logged
//! request is signature-verified, the tests prove `SigV4` was spoken over the TLS channel.
//!
//! Trust model under test: the binary trusts the synthetic CA through the environment-only
//! `HEALTHMD_OBJECT_STORE_CA_CERT` variable pointing at the committed absolute-path PEM
//! fixture. WITHOUT that variable the build's default `webpki-roots` trust rejects the
//! synthetic certificate — proven health-free by a dedicated scenario. Certificate
//! verification is never disabled in any configuration; there is no insecure mode.
//!
//! NO real R2/S3/Cloudflare/TLS-authority endpoint is ever contacted: the only listener is
//! the loopback double, and the only certificate material is the synthetic fixture below.
//!
//! ## Fixtures (`tests/fixtures/`)
//!
//! - `object-store-tls-ca.pem` — SYNTHETIC self-signed test-only CA certificate. Test-only
//!   material; never a real identity.
//! - `object-store-tls-server.pem` — SYNTHETIC test-only leaf certificate with
//!   `subjectAltName = IP:127.0.0.1, DNS:localhost`, issued by the synthetic CA, followed by
//!   its private key. Test-only material.
//!
//! Offline regeneration (run from `crates/healthmd-cli`, synthetic, test-only):
//!
//! ```sh
//! TMP=$(mktemp -d)
//! openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/ca.key" -out "$TMP/ca.pem" \
//!   -subj "/CN=Health.md synthetic object-store test CA/O=Health.md tests" -days 36500 \
//!   -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
//! openssl req -new -newkey rsa:2048 -nodes -keyout "$TMP/server.key" -out "$TMP/server.csr" \
//!   -subj "/CN=localhost/O=Health.md tests"
//! printf 'subjectAltName=IP:127.0.0.1,DNS:localhost\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' > "$TMP/ext.cnf"
//! openssl x509 -req -in "$TMP/server.csr" -CA "$TMP/ca.pem" -CAkey "$TMP/ca.key" \
//!   -CAcreateserial -days 36500 -out "$TMP/server.crt" -extfile "$TMP/ext.cnf"
//! { printf '# SYNTHETIC test-only CA certificate (see tests/agent_data_object_tls.rs).\n'; cat "$TMP/ca.pem"; } \
//!   > tests/fixtures/object-store-tls-ca.pem
//! { printf '# SYNTHETIC test-only leaf certificate + private key (see tests/agent_data_object_tls.rs).\n'; \
//!   cat "$TMP/server.crt"; echo; cat "$TMP/server.key"; } > tests/fixtures/object-store-tls-server.pem
//! ```

#![cfg(feature = "object-store-tls")]

use std::{
    collections::BTreeMap,
    fmt::Write as _,
    io::{BufRead as _, Read, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, Command, Output, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{Receiver, channel},
    },
    thread::{self, JoinHandle},
    time::Duration,
};

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, pem::PemObject};
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use tempfile::TempDir;

const PROTOCOL_VERSION: &str = "2025-11-25";
const RESPONSE_TIMEOUT: Duration = Duration::from_secs(30);

/// Fixed synthetic credentials shared by the double and the spawned store. Never real.
const TEST_ACCESS_KEY_ID: &str = "HEALTHMDTESTACCESSKEY1";
const TEST_SECRET_ACCESS_KEY: &str = "healthmd-test-secret-key-0000000000000000000001";
/// The store signs with region `auto` (Cloudflare R2); the double verifies the same scope.
const TEST_REGION: &str = "auto";
const BUCKET: &str = "healthmd-test-bucket";
/// Fixed synthetic `LastModified` for every object so listings are stable across starts.
const FIXED_LAST_MODIFIED: &str = "2026-01-02T03:04:05.000Z";
/// Loopback port candidates for this suite (other suites own 481xx/482xx/483xx/484xx).
const PORT_CANDIDATES: [u16; 24] = [
    48_511, 48_513, 48_517, 48_519, 48_523, 48_529, 48_531, 48_537, 48_541, 48_543, 48_547, 48_551,
    48_553, 48_557, 48_559, 48_563, 48_567, 48_569, 48_571, 48_573, 48_577, 48_579, 48_583, 48_593,
];

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

// ---------------------------------------------------------------------------
// Corpus (mirrors tests/agent_data_object.rs; expectations derive from it)
// ---------------------------------------------------------------------------

struct Corpus {
    root: TempDir,
}

impl Corpus {
    fn build() -> Self {
        let root = TempDir::new().expect("temporary corpus root");
        Self { root }
    }

    /// The bucket contents as `key → exact bytes`: the five stdio artifacts under the
    /// `exports/` prefix, one unsupported file, one malformed candidate, and one
    /// grant-shaped object that must stay ordinary content (never a grant).
    #[allow(clippy::unused_self)]
    fn objects(&self) -> BTreeMap<String, Vec<u8>> {
        let mut objects = BTreeMap::new();
        let mut insert = |key: &str, bytes: Vec<u8>| {
            objects.insert(key.to_owned(), bytes);
        };
        insert(
            "exports/bare.json",
            serde_json::to_vec(&bare_daily()).expect("bare artifact"),
        );
        insert(
            "exports/lossless.json",
            serde_json::to_vec(&lossless_daily()).expect("lossless artifact"),
        );
        insert("exports/raw-snapshot.ndjson", snapshot_ndjson_bytes());
        insert("exports/notes.txt", b"not health data".to_vec());
        insert(
            "exports/broken.json",
            br#"{"schema":"healthmd.health_data","schema_version":8,"date":"2026-13-45","type":"health-data"}"#
                .to_vec(),
        );
        insert(
            "exports/misplaced-grant.json",
            serde_json::to_vec(&grant(true)).expect("misplaced grant object"),
        );
        objects
    }

    fn write_grant(&self, name: &str, value: &Value) -> PathBuf {
        let grants = self.root.path().join("grants");
        std::fs::create_dir_all(&grants).expect("grant directory");
        let path = grants.join(name);
        std::fs::write(&path, serde_json::to_string(value).expect("grant JSON"))
            .expect("grant file");
        path
    }

    fn grant_bulk(&self) -> PathBuf {
        self.write_grant("bulk.json", &grant(true))
    }
}

fn grant(bulk_download: bool) -> Value {
    json!({
        "schema": "healthmd.agent_data_grant",
        "schema_version": 1,
        "metrics": {"type": "all_available"},
        "sources": {"type": "all_available"},
        "dates": {"type": "all_available"},
        "times": {"type": "all_available"},
        "detail_levels": ["common", "lossless"],
        "bulk_download": bulk_download
    })
}

fn bare_daily() -> Value {
    json!({
        "schema": "healthmd.health_data",
        "schema_version": 8,
        "date": "2026-03-15",
        "type": "health-data",
        "raw_capture_status": "complete",
        "units": {},
        "activity": {"steps": 12_345}
    })
}

fn heart_rate_avg_record() -> Value {
    json!({
        "record_kind": "quantity",
        "start_date": "2026-03-15T12:00:00Z",
        "end_date": "2026-03-15T12:00:01Z",
        "metric_attribution": {"direct_metric_ids": ["heart_rate_avg"]},
        "payload": {"value": 72}
    })
}

fn heart_rate_multi_record() -> Value {
    json!({
        "record_kind": "quantity",
        "start_date": "2026-03-15T12:05:00Z",
        "end_date": "2026-03-15T12:05:30Z",
        "selected_metric_ids": ["heart_rate_avg", "heart_rate_min"],
        "payload": {"value": 64, "waveform": "x".repeat(6_000)}
    })
}

fn lossless_daily() -> Value {
    json!({
        "schema": "healthmd.health_data",
        "schema_version": 8,
        "date": "2026-03-15",
        "type": "health-data",
        "raw_capture_status": "complete",
        "sleep": {"asleep_minutes": 480},
        "healthkit_record_archive": {
            "schema": "healthmd.healthkit_records",
            "schema_version": 1,
            "capture_status": "complete",
            "records": [heart_rate_avg_record(), heart_rate_multi_record()],
            "external_records": [],
            "medication_inventory": []
        }
    })
}

const SNAPSHOT_LINES: [&str; 4] = [
    r#"{"kind":"header","header":{"schema":"healthmd.raw-snapshot","version":1,"snapshotId":"snap-1"}}"#,
    r#"{"kind":"record","record":{"wireType":"steps","start_date":"2026-03-15T12:00:00Z","value":9000}}"#,
    r#"{"kind":"record","record":{"wireType":"heart_rate_samples","samples":[{"timestamp":"2026-03-15T12:00:00Z","value":70}]}}"#,
    r#"{"kind":"manifest","manifest":{"schema":"healthmd.raw-snapshot.manifest","version":1,"status":"COMPLETE","snapshotId":"snap-1","recordCount":2}}"#,
];

fn snapshot_ndjson_bytes() -> Vec<u8> {
    let mut bytes = Vec::new();
    for line in SNAPSHOT_LINES {
        bytes.extend_from_slice(line.as_bytes());
        bytes.push(b'\n');
    }
    bytes
}

#[allow(clippy::too_many_arguments)]
fn catalog_item(
    metric_id: &str,
    source_id: &str,
    detail_level: &str,
    record_count: usize,
    first_owner_date: Option<&str>,
    last_owner_date: Option<&str>,
    first_time: Option<&str>,
    last_time: Option<&str>,
) -> Value {
    json!({
        "type": "metric",
        "metric_id": metric_id,
        "source_id": source_id,
        "detail_level": detail_level,
        "record_count": record_count,
        "coverage": {
            "first_owner_date": first_owner_date,
            "last_owner_date": last_owner_date,
            "first_time": first_time,
            "last_time": last_time
        }
    })
}

/// The complete bulk-grant catalog in the server's deterministic (metric, source, level)
/// ordering; identical to the stdio and plain-object-store harness expectations for the same
/// corpus — the TLS transport must not change one catalog byte.
fn expected_bulk_catalog() -> Vec<Value> {
    vec![
        catalog_item(
            "healthmd.health_data#/activity/steps",
            "healthmd.health_data",
            "common",
            1,
            Some("2026-03-15"),
            Some("2026-03-15"),
            None,
            None,
        ),
        catalog_item(
            "healthmd.health_data#/sleep/asleep_minutes",
            "healthmd.health_data",
            "common",
            1,
            Some("2026-03-15"),
            Some("2026-03-15"),
            None,
            None,
        ),
        catalog_item(
            "healthmd.healthkit_records#metric:heart_rate_avg",
            "healthmd.healthkit_records",
            "lossless",
            2,
            Some("2026-03-15"),
            Some("2026-03-15"),
            Some("2026-03-15T12:00:00Z"),
            Some("2026-03-15T12:05:00Z"),
        ),
        catalog_item(
            "healthmd.healthkit_records#metric:heart_rate_min",
            "healthmd.healthkit_records",
            "lossless",
            1,
            Some("2026-03-15"),
            Some("2026-03-15"),
            Some("2026-03-15T12:05:00Z"),
            Some("2026-03-15T12:05:00Z"),
        ),
        catalog_item(
            "healthmd.raw-snapshot#wire:heart_rate_samples",
            "healthmd.raw-snapshot",
            "lossless",
            1,
            None,
            None,
            None,
            None,
        ),
        catalog_item(
            "healthmd.raw-snapshot#wire:steps",
            "healthmd.raw-snapshot",
            "lossless",
            1,
            Some("2026-03-15"),
            Some("2026-03-15"),
            Some("2026-03-15T12:00:00Z"),
            Some("2026-03-15T12:00:00Z"),
        ),
    ]
}

fn default_page() -> Value {
    page(250, 262_144, None)
}

fn page(max_items: usize, max_bytes: usize, cursor: Option<&str>) -> Value {
    json!({"max_items": max_items, "max_bytes": max_bytes, "cursor": cursor})
}

// ---------------------------------------------------------------------------
// SigV4 (independent test-side implementation used to verify every request)
// ---------------------------------------------------------------------------

fn hmac_sha256(key: &[u8], data: &[u8]) -> Vec<u8> {
    use hmac::Mac as _;
    let mut mac = hmac::Hmac::<Sha256>::new_from_slice(key).expect("hmac accepts any key");
    mac.update(data);
    mac.finalize().into_bytes().to_vec()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().fold(
        String::with_capacity(bytes.len() * 2),
        |mut output, byte| {
            let _ = write!(output, "{byte:02x}");
            output
        },
    )
}

/// Percent-encode per the `SigV4` canonical rules (`keep_slash` preserves `/` separators).
fn aws_percent_encode(value: &str, keep_slash: bool) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                encoded.push(char::from(*byte));
            }
            b'/' if keep_slash => encoded.push('/'),
            _ => {
                let _ = write!(encoded, "%{byte:02X}");
            }
        }
    }
    encoded
}

fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'%' if index + 2 < bytes.len() => {
                let hex_pair = &value[index + 1..index + 3];
                if let Ok(byte) = u8::from_str_radix(hex_pair, 16) {
                    decoded.push(byte);
                    index += 3;
                    continue;
                }
                decoded.push(b'%');
                index += 1;
            }
            byte => {
                decoded.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8_lossy(&decoded).into_owned()
}

/// Verify one request's `SigV4` authorization. Returns a failure description when invalid.
fn verify_sigv4(
    method: &str,
    path_and_query: &str,
    headers: &[(String, String)],
) -> Result<(), String> {
    let header = |name: &str| {
        headers
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.clone())
    };
    let authorization =
        header("authorization").ok_or_else(|| "missing Authorization header".to_owned())?;
    let remainder = authorization
        .strip_prefix("AWS4-HMAC-SHA256 ")
        .ok_or_else(|| "authorization is not AWS4-HMAC-SHA256".to_owned())?;
    let mut credential = None;
    let mut signed_headers = None;
    let mut signature = None;
    for part in remainder.split(", ") {
        let (name, value) = part
            .split_once('=')
            .ok_or_else(|| format!("malformed authorization component {part:?}"))?;
        match name {
            "Credential" => credential = Some(value.to_owned()),
            "SignedHeaders" => signed_headers = Some(value.to_owned()),
            "Signature" => signature = Some(value.to_owned()),
            _ => return Err(format!("unexpected authorization component {name:?}")),
        }
    }
    let credential = credential.ok_or_else(|| "missing Credential".to_owned())?;
    let signed_headers = signed_headers.ok_or_else(|| "missing SignedHeaders".to_owned())?;
    let signature = signature.ok_or_else(|| "missing Signature".to_owned())?;
    if credential.split('/').next() != Some(TEST_ACCESS_KEY_ID) {
        return Err("credential is not the fixed synthetic access key id".to_owned());
    }
    let scope_parts: Vec<&str> = credential.split('/').collect();
    if scope_parts.len() != 5 {
        return Err("credential scope must have five components".to_owned());
    }
    let amz_date = header("x-amz-date").ok_or_else(|| "missing x-amz-date".to_owned())?;
    let scope_date = scope_parts[1];
    if scope_date.len() != 8 || scope_date != &amz_date[..8.min(amz_date.len())] {
        return Err("credential date does not match x-amz-date".to_owned());
    }
    if scope_parts[3] != "s3" || scope_parts[4] != "aws4_request" || scope_parts[2] != TEST_REGION {
        return Err(format!("unexpected credential scope {credential}"));
    }
    let payload_hash =
        header("x-amz-content-sha256").ok_or_else(|| "missing x-amz-content-sha256".to_owned())?;
    if payload_hash != "UNSIGNED-PAYLOAD" {
        return Err("payload hash must be UNSIGNED-PAYLOAD".to_owned());
    }
    for required in ["host", "x-amz-content-sha256", "x-amz-date"] {
        if !signed_headers.split(';').any(|name| name == required) {
            return Err(format!("SignedHeaders omits {required}"));
        }
    }
    let (path, query) = path_and_query
        .split_once('?')
        .unwrap_or((path_and_query, ""));
    let canonical_query = rebuild_canonical_query(query);
    let mut canonical_headers = String::new();
    for name in signed_headers.split(';') {
        let value = header(name).ok_or_else(|| format!("signed header {name:?} is absent"))?;
        canonical_headers.push_str(name);
        canonical_headers.push(':');
        canonical_headers.push_str(value.trim());
        canonical_headers.push('\n');
    }
    let canonical_request = format!(
        "{method}\n{path}\n{canonical_query}\n{canonical_headers}\n{signed_headers}\n{payload_hash}"
    );
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{amz_date}\n{scope_date}/{TEST_REGION}/s3/aws4_request\n{}",
        hex(&Sha256::digest(canonical_request.as_bytes()))
    );
    let mut key = hmac_sha256(
        format!("AWS4{TEST_SECRET_ACCESS_KEY}").as_bytes(),
        scope_date.as_bytes(),
    );
    for part in [TEST_REGION, "s3", "aws4_request"] {
        key = hmac_sha256(&key, part.as_bytes());
    }
    let expected = hex(&hmac_sha256(&key, string_to_sign.as_bytes()));
    if expected != signature {
        return Err(format!(
            "signature mismatch: expected {expected}, got {signature}"
        ));
    }
    Ok(())
}

/// Rebuild the canonical query from the received query string: decode each pair, re-encode,
/// and sort — the store must send its query already in canonical form.
fn rebuild_canonical_query(query: &str) -> String {
    let mut pairs: Vec<(String, String)> = query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| match pair.split_once('=') {
            Some((key, value)) => (percent_decode(key), percent_decode(value)),
            None => (percent_decode(pair), String::new()),
        })
        .collect();
    pairs.sort();
    pairs
        .iter()
        .map(|(key, value)| {
            format!(
                "{}={}",
                aws_percent_encode(key, false),
                aws_percent_encode(value, false)
            )
        })
        .collect::<Vec<_>>()
        .join("&")
}

// ---------------------------------------------------------------------------
// Synthetic loopback TLS S3 double (rustls server side, blocking std sockets)
// ---------------------------------------------------------------------------

#[derive(Default)]
struct DoubleState {
    objects: BTreeMap<String, Vec<u8>>,
    request_log: Vec<(String, String)>,
    failures: Vec<String>,
    /// Accepted connections where the peer sent bytes (a TLS client always sends its
    /// `ClientHello`; the readiness probe and shutdown wake-ups never do).
    connections: usize,
    /// Connections whose TLS handshake never completed (e.g. a client rejecting the
    /// synthetic certificate). Never logged as requests.
    handshake_failures: usize,
    page_size: usize,
}

struct TlsS3Double {
    port: u16,
    state: Arc<Mutex<DoubleState>>,
    stopped: Arc<AtomicBool>,
    listener: JoinHandle<()>,
}

/// The synthetic test-only server identity: the leaf certificate and private key committed
/// under `tests/fixtures/` (see the module header for the offline regeneration command).
fn server_config() -> Arc<rustls::ServerConfig> {
    let server_pem = fixture("object-store-tls-server.pem");
    let certificates = CertificateDer::pem_file_iter(&server_pem)
        .expect("open the server fixture")
        .collect::<Result<Vec<_>, _>>()
        .expect("parse the server certificate");
    assert_eq!(certificates.len(), 1, "the fixture holds one leaf");
    let key = PrivateKeyDer::from_pem_file(&server_pem).expect("parse the server key");
    let config = rustls::ServerConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .expect("safe protocol versions")
    .with_no_client_auth()
    .with_single_cert(certificates, key)
    .expect("the fixture certificate and key match");
    Arc::new(config)
}

impl TlsS3Double {
    /// Start the double on the first loopback candidate port that answers.
    fn spawn(objects: BTreeMap<String, Vec<u8>>) -> Self {
        for port in PORT_CANDIDATES {
            let Ok(listener) = TcpListener::bind(("127.0.0.1", port)) else {
                continue;
            };
            let state = Arc::new(Mutex::new(DoubleState {
                objects,
                request_log: Vec::new(),
                failures: Vec::new(),
                connections: 0,
                handshake_failures: 0,
                page_size: 3,
            }));
            let stopped = Arc::new(AtomicBool::new(false));
            let config = server_config();
            let accept_state = Arc::clone(&state);
            let accept_stopped = Arc::clone(&stopped);
            let handle = thread::spawn(move || {
                for stream in listener.incoming() {
                    if accept_stopped.load(Ordering::SeqCst) {
                        break;
                    }
                    // Transient accept failures (peers resetting before the accept
                    // completes, e.g. an environment port scanner probing freshly
                    // bound loopback ports) must not stop the double mid-test.
                    let Ok(stream) = stream else { continue };
                    let state = Arc::clone(&accept_state);
                    let config = Arc::clone(&config);
                    thread::spawn(move || handle_tls_connection(stream, &config, &state));
                }
            });
            let double = Self {
                port,
                state,
                stopped,
                listener: handle,
            };
            double.probe_ready();
            return double;
        }
        panic!("no loopback candidate port answered; attempted {PORT_CANDIDATES:?}");
    }

    fn probe_ready(&self) {
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        loop {
            assert!(
                std::time::Instant::now() < deadline,
                "the synthetic TLS S3 double never answered"
            );
            if TcpStream::connect_timeout(
                &std::net::SocketAddr::from(([127, 0, 0, 1], self.port)),
                Duration::from_millis(250),
            )
            .is_ok()
            {
                return;
            }
            thread::sleep(Duration::from_millis(25));
        }
    }

    fn requests(&self) -> Vec<(String, String)> {
        self.state.lock().expect("double state").request_log.clone()
    }

    fn connections(&self) -> usize {
        self.state.lock().expect("double state").connections
    }

    fn handshake_failures(&self) -> usize {
        self.state.lock().expect("double state").handshake_failures
    }

    fn assert_no_failures(&self, context: &str) {
        let failures = self.state.lock().expect("double state").failures.clone();
        assert!(
            failures.is_empty(),
            "S3 double verification failures ({context}): {failures:?}"
        );
    }

    /// Wait (bounded) until the double observes the given state, so assertions do not race
    /// the per-connection handler threads finishing their TLS work.
    fn await_state(&self, context: &str, condition: impl Fn(&DoubleState) -> bool) {
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        loop {
            if condition(&self.state.lock().expect("double state")) {
                return;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "the double never observed {context}"
            );
            thread::sleep(Duration::from_millis(10));
        }
    }
}

impl Drop for TlsS3Double {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::SeqCst);
        // Wake the accept loop so it observes the stop flag and exits deterministically.
        let _ = TcpStream::connect(("127.0.0.1", self.port));
        let listener = std::mem::replace(&mut self.listener, thread::spawn(|| {}));
        let _ = listener.join();
    }
}

/// Handshake one connection and, when it completes, serve exactly one request over the
/// established TLS channel. A connection counts as a client attempt only once the peer
/// sends bytes (the readiness probe and shutdown wake-ups connect and close silently).
/// A byte-sending connection that never completes TLS — for example a client rejecting the
/// synthetic certificate — is counted as a handshake failure and never produces a logged
/// request.
fn handle_tls_connection(
    tcp: TcpStream,
    config: &Arc<rustls::ServerConfig>,
    state: &Arc<Mutex<DoubleState>>,
) {
    let Ok(connection) = rustls::ServerConnection::new(Arc::clone(config)) else {
        return;
    };
    // Only TLS-speaking peers are served or counted: every real client opens with a TLS
    // `ClientHello` record (first byte `0x16`). Shared machines occasionally probe newly
    // bound loopback ports with plaintext `GET /` health checks; those are ignored.
    {
        let mut first = [0_u8; 1];
        match tcp.peek(&mut first) {
            Ok(1) if first[0] == 0x16 => {}
            _ => return,
        }
    }
    let mut stream = rustls::StreamOwned::new(connection, tcp);
    let mut saw_client_bytes = false;
    let mut failed = false;
    while stream.conn.is_handshaking() {
        match stream.conn.complete_io(&mut stream.sock) {
            Ok((read, _)) => {
                if read > 0 {
                    saw_client_bytes = true;
                }
            }
            Err(error) => {
                // A clean EOF can be a silent probe (connect-and-close); any other failure
                // (for example a fatal `UnknownCA` alert) proves the peer sent bytes.
                if error.kind() != std::io::ErrorKind::UnexpectedEof {
                    saw_client_bytes = true;
                }
                failed = true;
                break;
            }
        }
    }
    {
        let mut state = state.lock().expect("double state");
        if saw_client_bytes {
            state.connections += 1;
        }
        if failed {
            state.handshake_failures += 1;
        }
    }
    if failed {
        return;
    }
    handle_request(&mut stream, state);
    // Close the TLS session cleanly so the client observes the exact end of the response.
    stream.conn.send_close_notify();
    let _ = stream.conn.complete_io(&mut stream.sock);
}

/// Read one complete request head (the store sends no bodies), verify its `SigV4` signature,
/// route it, and write one response over the TLS channel.
fn handle_request<S>(stream: &mut S, state: &Arc<Mutex<DoubleState>>)
where
    S: Read + Write,
{
    let mut buffer = Vec::new();
    let mut chunk = [0_u8; 8_192];
    loop {
        if buffer.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
        match stream.read(&mut chunk) {
            Ok(0) | Err(_) => return,
            Ok(read) => buffer.extend_from_slice(&chunk[..read]),
        }
        if buffer.len() > 64 * 1_024 {
            return;
        }
    }
    let head_end = buffer
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .expect("checked above");
    let text = String::from_utf8_lossy(&buffer[..head_end]).into_owned();
    let mut lines = text.split("\r\n");
    let request_line = lines.next().unwrap_or_default();
    let mut parts = request_line.split_ascii_whitespace();
    let method = parts.next().unwrap_or_default().to_owned();
    let target = parts.next().unwrap_or_default().to_owned();
    let headers: Vec<(String, String)> = lines
        .filter(|line| !line.is_empty())
        .filter_map(|line| {
            line.split_once(':')
                .map(|(name, value)| (name.trim().to_ascii_lowercase(), value.trim().to_owned()))
        })
        .collect();

    let response = {
        let mut state = state.lock().expect("double state");
        state.request_log.push((method.clone(), target.clone()));
        if let Some(length) = headers
            .iter()
            .find(|(name, _)| name == "content-length")
            .and_then(|(_, value)| value.parse::<usize>().ok())
        {
            if length > 0 {
                state
                    .failures
                    .push("the read-only store must never send a request body".to_owned());
            }
        }
        if let Err(failure) = verify_sigv4(&method, &target, &headers) {
            state.failures.push(format!("SigV4: {failure}"));
        }
        route_request(&method, &target, &headers, &state)
    };
    let _ = stream.write_all(&response);
    let _ = stream.flush();
}

#[allow(clippy::ref_option)]
fn route_request(
    method: &str,
    target: &str,
    headers: &[(String, String)],
    state: &DoubleState,
) -> Vec<u8> {
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    if method == "GET" && query.contains("list-type=2") {
        return list_response(path, query, state);
    }
    let Some(key) = path.strip_prefix(&format!("/{BUCKET}/")) else {
        return error_response(404, "NoSuchBucket", "unexpected bucket");
    };
    let Some(bytes) = state.objects.get(key) else {
        return error_response(404, "NoSuchKey", "object not found");
    };
    match method {
        "HEAD" => {
            let head = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                bytes.len()
            );
            head.into_bytes()
        }
        // Range support (frozen subset): the double honors `Range: bytes=a-b` exactly.
        "GET" => object_response(bytes, parse_range_header(headers, bytes.len())),
        _ => error_response(
            403,
            "AccessDenied",
            "the double implements only the read subset",
        ),
    }
}

/// Parse one `Range: bytes=start-end` header (inclusive end, both bounds required) against
/// the object length; anything malformed falls back to a plain whole-object GET.
fn parse_range_header(headers: &[(String, String)], length: usize) -> Option<(usize, usize)> {
    let value = headers
        .iter()
        .find(|(name, _)| name == "range")
        .map(|(_, value)| value.trim().to_owned())?;
    let specification = value.strip_prefix("bytes=")?;
    let (start, end) = specification.split_once('-')?;
    let start = start.trim().parse::<usize>().ok()?;
    let end = end.trim().parse::<usize>().ok()?;
    (start <= end && start < length).then_some((start, end.min(length.saturating_sub(1))))
}

/// Serve one `ListObjectsV2` page from the (sorted) object map with the fixed page size and
/// opaque `page-<offset>` continuation tokens.
fn list_response(path: &str, query: &str, state: &DoubleState) -> Vec<u8> {
    if path != format!("/{BUCKET}") {
        return error_response(404, "NoSuchBucket", "unexpected bucket");
    }
    let mut prefix = String::new();
    let mut offset = 0_usize;
    for pair in query.split('&').filter(|pair| !pair.is_empty()) {
        let (name, value) = pair.split_once('=').unwrap_or((pair, ""));
        match percent_decode(name).as_str() {
            "prefix" => prefix = percent_decode(value),
            "continuation-token" => {
                let token = percent_decode(value);
                let Some(number) = token.strip_prefix("page-") else {
                    return error_response(400, "InvalidArgument", "bad continuation token");
                };
                offset = number.parse::<usize>().unwrap_or(0);
            }
            "list-type" | "max-keys" | "delimiter" | "encoding-type" => {}
            other => {
                return error_response(
                    400,
                    "InvalidArgument",
                    &format!("unknown parameter {other}"),
                );
            }
        }
    }
    let page_size = state.page_size.max(1);
    let matched: Vec<&String> = state
        .objects
        .keys()
        .filter(|key| key.starts_with(&prefix))
        .collect();
    let end = (offset + page_size).min(matched.len());
    let truncated = end < matched.len();
    let mut body = String::from(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">",
    );
    let _ = write!(body, "\n  <Name>{BUCKET}</Name>");
    let _ = write!(body, "\n  <Prefix>{}</Prefix>", xml_escape(&prefix));
    let _ = write!(body, "\n  <KeyCount>{}</KeyCount>", matched.len());
    let _ = write!(body, "\n  <IsTruncated>{truncated}</IsTruncated>");
    if truncated {
        let _ = write!(
            body,
            "\n  <NextContinuationToken>page-{end}</NextContinuationToken>"
        );
    }
    for key in &matched[offset..end] {
        let bytes = &state.objects[*key];
        let _ = write!(
            body,
            "\n  <Contents>\n    <Key>{}</Key>\n    <LastModified>{FIXED_LAST_MODIFIED}</LastModified>\n    <Size>{}</Size>\n  </Contents>",
            xml_escape(key),
            bytes.len()
        );
    }
    body.push_str("\n</ListBucketResult>");
    let head = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let mut response = head.into_bytes();
    response.extend_from_slice(body.as_bytes());
    response
}

fn object_response(bytes: &[u8], range: Option<(usize, usize)>) -> Vec<u8> {
    let Some((start, end)) = range else {
        let head = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            bytes.len()
        );
        let mut response = head.into_bytes();
        response.extend_from_slice(bytes);
        return response;
    };
    let end = (end + 1).min(bytes.len());
    let slice = &bytes[start.min(bytes.len())..end];
    let head = format!(
        "HTTP/1.1 206 Partial Content\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        slice.len()
    );
    let mut response = head.into_bytes();
    response.extend_from_slice(slice);
    response
}

fn error_response(status: u16, code: &str, message: &str) -> Vec<u8> {
    let body = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Error><Code>{code}</Code><Message>{message}</Message></Error>"
    );
    let head = format!(
        "HTTP/1.1 {status} Error\r\nContent-Type: application/xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let mut response = head.into_bytes();
    response.extend_from_slice(body.as_bytes());
    response
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

// ---------------------------------------------------------------------------
// Binary driving: one-shot runs and the stdio MCP server harness
// ---------------------------------------------------------------------------

/// Whether the spawned binary trusts the synthetic CA through
/// `HEALTHMD_OBJECT_STORE_CA_CERT` (`Some`) or runs on the default `webpki-roots` trust only
/// (`None`).
type CaTrust<'a> = Option<&'a Path>;

fn apply_common_environment(command: &mut Command, ca_trust: CaTrust) {
    command
        .env("HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID", TEST_ACCESS_KEY_ID)
        .env(
            "HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY",
            TEST_SECRET_ACCESS_KEY,
        );
    match ca_trust {
        Some(path) => {
            command.env(
                "HEALTHMD_OBJECT_STORE_CA_CERT",
                path.to_string_lossy().into_owned(),
            );
        }
        None => {
            command.env_remove("HEALTHMD_OBJECT_STORE_CA_CERT");
        }
    }
}

fn object_store_arguments(url: &str, grant: &Path, index: &Path) -> Vec<String> {
    vec![
        "mcp".to_owned(),
        "serve-data".to_owned(),
        "--object-store-url".to_owned(),
        url.to_owned(),
        "--bucket".to_owned(),
        BUCKET.to_owned(),
        "--prefix".to_owned(),
        "exports/".to_owned(),
        "--grant".to_owned(),
        grant.to_string_lossy().into_owned(),
        "--index".to_owned(),
        index.to_string_lossy().into_owned(),
    ]
}

/// One-shot run of the real binary with the synthetic credentials and the requested CA trust.
fn run(arguments: &[String], ca_trust: CaTrust) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_healthmd"));
    command.args(arguments).stdin(Stdio::null());
    apply_common_environment(&mut command, ca_trust);
    command.output().expect("healthmd should launch")
}

struct StdioMcpServer {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<String>,
    next_id: u64,
}

impl StdioMcpServer {
    fn spawn(arguments: &[String], ca_trust: CaTrust) -> Self {
        let mut command = Command::new(env!("CARGO_BIN_EXE_healthmd"));
        command
            .args(arguments)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        apply_common_environment(&mut command, ca_trust);
        let mut child = command
            .spawn()
            .expect("healthmd mcp serve-data should launch");
        let stdin = child.stdin.take().expect("piped stdin");
        let stdout = child.stdout.take().expect("piped stdout");
        let (sender, lines) = channel();
        thread::spawn(move || {
            let reader = std::io::BufReader::new(stdout);
            for line in reader.lines() {
                match line {
                    Ok(line) => {
                        if sender.send(line).is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
        });
        let mut server = Self {
            child,
            stdin,
            lines,
            next_id: 0,
        };
        server.initialize();
        server
    }

    fn initialize(&mut self) {
        let response = self.request(
            "initialize",
            &json!({"protocolVersion": PROTOCOL_VERSION, "capabilities": {}}),
        );
        let result = response["result"].as_object().expect("initialize result");
        assert_eq!(result["protocolVersion"], json!(PROTOCOL_VERSION));
        assert_eq!(result["serverInfo"]["name"], json!("healthmd-mcp"));
        self.notify("notifications/initialized");
    }

    fn notify(&mut self, method: &str) {
        self.write_line(&json!({"jsonrpc": "2.0", "method": method}).to_string());
    }

    fn request(&mut self, method: &str, params: &Value) -> Value {
        self.next_id += 1;
        let id = self.next_id;
        let request = json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params});
        self.write_line(&request.to_string());
        loop {
            let line = self
                .lines
                .recv_timeout(RESPONSE_TIMEOUT)
                .unwrap_or_else(|error| panic!("no response for {method} within timeout: {error}"));
            let value: Value = serde_json::from_str(&line)
                .unwrap_or_else(|error| panic!("response line is not JSON ({error}): {line}"));
            if value.get("id") == Some(&json!(id)) {
                return value;
            }
        }
    }

    #[allow(clippy::needless_pass_by_value)]
    fn call(&mut self, name: &str, arguments: Value) -> (Value, bool) {
        let response = self.request("tools/call", &json!({"name": name, "arguments": arguments}));
        let result = response["result"].as_object().expect("tools/call result");
        let payload: Value = serde_json::from_str(
            response
                .pointer("/result/content/0/text")
                .and_then(Value::as_str)
                .expect("tool text payload"),
        )
        .expect("tool payload JSON");
        (payload, result["isError"].as_bool().expect("isError"))
    }

    fn write_line(&mut self, line: &str) {
        writeln!(self.stdin, "{line}").expect("write request to server stdin");
        self.stdin.flush().expect("flush server stdin");
    }
}

impl Drop for StdioMcpServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn fresh_index(corpus: &Corpus, name: &str) -> PathBuf {
    let indexes = corpus.root.path().join("indexes");
    std::fs::create_dir_all(&indexes).expect("index directory");
    indexes.join(name)
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

#[test]
fn object_store_tls_serves_the_agent_data_contract_over_stdio() {
    let corpus = Corpus::build();
    let double = TlsS3Double::spawn(corpus.objects());
    let url = format!("https://127.0.0.1:{}", double.port);
    let arguments = object_store_arguments(
        &url,
        &corpus.grant_bulk(),
        &fresh_index(&corpus, "catalog.json"),
    );
    let mut server = StdioMcpServer::spawn(&arguments, Some(&fixture("object-store-tls-ca.pem")));

    let (catalog, is_error) = server.call("healthmd_data_catalog", json!({"page": default_page()}));
    assert!(!is_error, "catalog query: {catalog}");
    assert_eq!(catalog["schema"], json!("healthmd.agent_query_response"));
    assert_eq!(catalog["schema_version"], json!(1));
    assert_eq!(catalog["operation"], json!("catalog"));
    assert_eq!(catalog["next_cursor"], Value::Null);
    assert_eq!(catalog["receipt"]["source_kind"], json!("object_store"));
    assert_eq!(catalog["receipt"]["policy_enforced"], json!(true));
    assert_eq!(catalog["receipt"]["returned_items"], json!(6));
    assert_eq!(
        catalog["items"].as_array().expect("catalog items"),
        &expected_bulk_catalog(),
        "the TLS object-store catalog must equal the plain transport catalog for the same corpus"
    );

    // One lossless chunked record read: reassemble the exact serialized record bytes.
    let (records, is_error) = server.call(
        "healthmd_data_records",
        json!({
            "metrics": {"type": "all_available"},
            "detail_level": "lossless",
            "page": default_page()
        }),
    );
    assert!(!is_error, "records query: {records}");
    assert_eq!(records["receipt"]["source_kind"], json!("object_store"));
    let multi = records["items"]
        .as_array()
        .expect("records items")
        .iter()
        .find(|item| item["metric_ids"].as_array().map(Vec::len) == Some(2))
        .expect("multi-attributed record")
        .clone();
    let record_id = multi["record_id"].as_str().expect("record_id").to_owned();

    let expected_bytes =
        serde_json::to_vec(&heart_rate_multi_record()).expect("compact value bytes");
    let mut cursor = None;
    let mut assembled = Vec::new();
    let mut chunks = 0_usize;
    loop {
        let (response, is_error) = server.call(
            "healthmd_data_record_read",
            json!({"record_id": record_id, "page": page(1, 4_096, cursor.as_deref())}),
        );
        assert!(!is_error, "record read: {response}");
        assert_eq!(response["receipt"]["source_kind"], json!("object_store"));
        let item = &response["items"][0];
        assert_eq!(item["type"], json!("record_chunk"));
        assert_eq!(item["record_id"], json!(record_id));
        assembled.extend_from_slice(
            &URL_SAFE_NO_PAD
                .decode(item["data"].as_str().expect("base64 data"))
                .expect("chunk decodes"),
        );
        chunks += 1;
        if item["complete"].as_bool().expect("complete flag") {
            assert_eq!(response["next_cursor"], Value::Null);
            break;
        }
        cursor = response["next_cursor"].as_str().map(str::to_owned);
    }
    assert!(chunks >= 2, "an oversized record must need multiple chunks");
    assert_eq!(assembled, expected_bytes, "exact chunk reassembly over TLS");

    // Every request was SigV4-verified after TLS decryption, addressed the configured bucket,
    // and used only list/GET/HEAD methods.
    let requests = double.requests();
    assert!(!requests.is_empty(), "the double served requests over TLS");
    assert!(
        requests
            .iter()
            .all(|(method, _)| method == "GET" || method == "HEAD"),
        "only GET/HEAD methods may be sent, saw {requests:?}"
    );
    assert!(
        requests
            .iter()
            .all(|(_, target)| target.starts_with(&format!("/{BUCKET}"))),
        "every request must address the configured bucket, saw {requests:?}"
    );
    assert!(
        requests
            .iter()
            .any(|(method, target)| method == "GET" && target.contains("list-type=2")),
        "the double must have served at least one listing"
    );
    assert!(
        requests.iter().any(|(method, _)| method == "HEAD"),
        "verified byte access must head objects for a fast size check"
    );
    double.assert_no_failures("TLS catalog and chunked record read");
}

#[test]
fn object_store_tls_rejects_an_untrusted_certificate_health_free() {
    let corpus = Corpus::build();
    let double = TlsS3Double::spawn(corpus.objects());
    let url = format!("https://127.0.0.1:{}", double.port);
    let arguments = object_store_arguments(
        &url,
        &corpus.grant_bulk(),
        &fresh_index(&corpus, "untrusted.json"),
    );

    // No HEALTHMD_OBJECT_STORE_CA_CERT: the default webpki-roots trust must reject the
    // synthetic certificate health-free at transport, with a stable message.
    let output = run(&arguments, None);
    assert!(
        !output.status.success(),
        "an untrusted certificate must fail the open"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("the object store TLS connection failed"),
        "a stable health-free TLS failure: {stderr}"
    );
    assert!(
        !stderr.contains(TEST_ACCESS_KEY_ID) && !stderr.contains(TEST_SECRET_ACCESS_KEY),
        "no credential material may appear in output"
    );
    // The client attempted the connection and its ClientHello aborted on the synthetic
    // certificate, but no authorized request ever succeeded.
    double.await_state("the untrusted-certificate handshake failure", |state| {
        state.connections >= 1 && state.handshake_failures >= 1
    });
    assert!(
        double.requests().is_empty(),
        "no authorized request may succeed over an untrusted channel, saw {:?}",
        double.requests()
    );
    assert!(
        double.connections() >= 1,
        "the client sent its ClientHello and attempted the TLS connection"
    );
    assert!(
        double.handshake_failures() >= 1,
        "the untrusted certificate aborted the handshake"
    );
}

#[test]
fn object_store_tls_ca_file_failures_precede_any_connection() {
    let corpus = Corpus::build();
    let double = TlsS3Double::spawn(corpus.objects());
    let url = format!("https://127.0.0.1:{}", double.port);
    let grant = corpus.grant_bulk();
    let index = fresh_index(&corpus, "ca-policy.json");
    let scratch = corpus.root.path().join("ca-scratch");
    std::fs::create_dir(&scratch).expect("scratch directory");
    let garbage = scratch.join("garbage.pem");
    std::fs::write(&garbage, b"definitely not a PEM certificate").expect("write garbage");
    let directory = scratch.join("directory.pem");
    std::fs::create_dir(&directory).expect("scratch subdirectory");

    for (ca_value, expected) in [
        (
            "relative-ca.pem",
            "the object store CA certificate path must be absolute",
        ),
        (
            "/nonexistent/absolute/object-store-ca.pem",
            "the object store CA certificate could not be read",
        ),
        (
            directory.to_str().expect("utf-8 directory path"),
            "the object store CA certificate could not be read",
        ),
        (
            garbage.to_str().expect("utf-8 garbage path"),
            "the object store CA certificate is not valid PEM",
        ),
    ] {
        let arguments = object_store_arguments(&url, &grant, &index);
        let mut command = Command::new(env!("CARGO_BIN_EXE_healthmd"));
        command.args(&arguments).stdin(Stdio::null());
        apply_common_environment(&mut command, Some(Path::new(ca_value)));
        let output = command.output().expect("healthmd should launch");
        assert!(
            !output.status.success(),
            "CA value {ca_value:?} must fail the open"
        );
        assert_eq!(
            output.status.code(),
            Some(1),
            "a store-level failure exits 1, not a parse failure"
        );
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            stderr.contains(expected),
            "stable health-free failure for {ca_value:?}: expected {expected:?}, saw {stderr:?}"
        );
    }

    // Every rejection happened before any network I/O: the live double saw no client
    // connection and no request at all.
    assert_eq!(
        double.connections(),
        0,
        "CA policy failures must precede any connection attempt"
    );
    assert!(double.requests().is_empty());
}

// ---------------------------------------------------------------------------
// In-file units (fixture loading, root-store assembly, name canonicalization)
// ---------------------------------------------------------------------------

#[test]
fn tls_fixtures_load_and_the_ca_is_a_usable_trust_anchor() {
    let certificates = CertificateDer::pem_file_iter(fixture("object-store-tls-ca.pem"))
        .expect("open the CA fixture")
        .collect::<Result<Vec<_>, _>>()
        .expect("parse the CA fixture");
    assert_eq!(certificates.len(), 1, "the committed synthetic CA");

    let mut roots = rustls::RootCertStore {
        roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
    };
    let webpki_count = roots.len();
    assert!(webpki_count > 0, "the Mozilla root set is non-empty");
    for certificate in certificates {
        roots
            .add(certificate)
            .expect("the synthetic CA is a usable trust anchor");
    }
    assert_eq!(roots.len(), webpki_count + 1);

    // The server fixture parses as one leaf plus its private key.
    let server_pem = fixture("object-store-tls-server.pem");
    let leaves = CertificateDer::pem_file_iter(&server_pem)
        .expect("open the server fixture")
        .collect::<Result<Vec<_>, _>>()
        .expect("parse the server certificate");
    assert_eq!(leaves.len(), 1, "the fixture holds one leaf");
    assert!(
        PrivateKeyDer::from_pem_file(&server_pem).is_ok(),
        "the fixture holds the leaf private key"
    );

    let _config = server_config();
}

#[test]
fn tls_server_names_canonicalize_ips_and_dns_names() {
    assert!(matches!(
        ServerName::try_from("127.0.0.1".to_owned()),
        Ok(ServerName::IpAddress(_))
    ));
    assert!(matches!(
        ServerName::try_from("localhost".to_owned()),
        Ok(ServerName::DnsName(_))
    ));
    assert!(ServerName::try_from("not a host".to_owned()).is_err());
}
