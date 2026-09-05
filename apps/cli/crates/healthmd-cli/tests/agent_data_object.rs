//! End-to-end coverage for the read-only S3-compatible object store Agent Data backing.
//!
//! These tests build a synthetic loopback S3 double — a minimal std HTTP/1.1 server that
//! implements EXACTLY the frozen subset (`ListObjectsV2` with prefix + continuation, `HEAD`
//! object, `GET` object with `Range`) at path-style addresses and verifies the AWS `SigV4`
//! signature of every request against fixed synthetic test keys — and then drive the REAL
//! `healthmd mcp serve-data --object-store-url http://127.0.0.1:<port> --bucket … --grant …`
//! binary over real newline-delimited JSON-RPC stdio.
//!
//! The synthetic corpus and the catalog expectations mirror `tests/agent_data_stdio.rs` (the
//! same five artifacts produce the same eight catalog entries), so object-store receipts
//! (`source_kind: "object_store"`) and query results are proven equivalent in shape to the
//! directory and database stores. The double records every request method and path so the
//! tests can assert the store never issues anything but GET/HEAD/list reads.
//!
//! No real R2/S3/Cloudflare endpoint is contacted: compatibility is exercised by spec through
//! the double. Real endpoints additionally require TLS egress, which this build does not
//! carry; the URL-policy tests cover that boundary without any network listener.

use std::{
    collections::BTreeMap,
    fmt::Write as _,
    io::{BufRead as _, Read as _, Write as _},
    net::{TcpListener, TcpStream},
    path::PathBuf,
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
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use tempfile::TempDir;

const PROTOCOL_VERSION: &str = "2025-11-25";
const RESPONSE_TIMEOUT: Duration = Duration::from_secs(30);
/// `CURSOR_RESPONSE_OVERHEAD_BYTES`: pages at or below this bound cannot carry a data chunk.
const CHUNK_OVERHEAD_BYTES: usize = 2_048;

/// Fixed synthetic credentials shared by the double and the spawned store. Never real.
const TEST_ACCESS_KEY_ID: &str = "HEALTHMDTESTACCESSKEY1";
const TEST_SECRET_ACCESS_KEY: &str = "healthmd-test-secret-key-0000000000000000000001";
/// The store signs with region `auto` (Cloudflare R2); the double verifies the same scope.
const TEST_REGION: &str = "auto";
const BUCKET: &str = "healthmd-test-bucket";
/// Fixed synthetic `LastModified` for every object so listings are stable across starts.
const FIXED_LAST_MODIFIED: &str = "2026-01-02T03:04:05.000Z";

// ---------------------------------------------------------------------------
// Corpus (mirrors tests/agent_data_stdio.rs; expectations derive from it)
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
            "exports/api-export.json",
            serde_json::to_vec(&api_export()).expect("api export artifact"),
        );
        insert(
            "exports/lossless.json",
            serde_json::to_vec(&lossless_daily()).expect("lossless artifact"),
        );
        insert("exports/raw-snapshot.ndjson", snapshot_ndjson_bytes());
        insert(
            "exports/raw-changes.json",
            serde_json::to_vec(&raw_changes()).expect("raw changes artifact"),
        );
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
        // Outside every prefix used below: never visible to a prefixed store.
        insert(
            "other/rogue.json",
            serde_json::to_vec(&bare_daily()).expect("rogue artifact"),
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

    fn grant_steps_only(&self) -> PathBuf {
        self.write_grant(
            "steps-only.json",
            &json!({
                "schema": "healthmd.agent_data_grant",
                "schema_version": 1,
                "metrics": {"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]},
                "sources": {"type": "all_available"},
                "dates": {"type": "all_available"},
                "times": {"type": "all_available"},
                "detail_levels": ["common"],
                "bulk_download": false
            }),
        )
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

fn api_export() -> Value {
    json!({
        "schema": "healthmd.api_export",
        "schema_version": 2,
        "failed_date_details": [],
        "records": [
            {
                "schema": "healthmd.health_data",
                "schema_version": 8,
                "date": "2026-03-16",
                "type": "health-data",
                "raw_capture_status": "complete",
                "heart": {"restingHeartRate": 58}
            }
        ]
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

fn raw_changes() -> Value {
    json!({
        "header": {
            "schema": "healthmd.raw-changes",
            "version": 1,
            "archiveId": "arch-1",
            "chainId": "chain-1",
            "sequence": 7
        },
        "manifest": {
            "schema": "healthmd.raw-changes.manifest",
            "version": 1,
            "status": "COMPLETE",
            "archiveId": "arch-1",
            "chainId": "chain-1",
            "sequence": 7,
            "eventCount": 1
        },
        "events": [
            {
                "observedAt": "2026-03-16T08:00:00Z",
                "record": {"wireType": "steps", "start_date": "2026-03-16T07:00:00Z", "value": 500}
            }
        ]
    })
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
/// ordering; identical to the stdio and HTTP harness expectations for the same corpus.
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
            "healthmd.health_data#/records/0/heart/restingHeartRate",
            "healthmd.health_data",
            "common",
            1,
            Some("2026-03-16"),
            Some("2026-03-16"),
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
            "healthmd.raw-changes#wire:steps",
            "healthmd.raw-changes",
            "lossless",
            1,
            Some("2026-03-16"),
            Some("2026-03-16"),
            Some("2026-03-16T07:00:00Z"),
            Some("2026-03-16T07:00:00Z"),
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
// Synthetic loopback S3 double
// ---------------------------------------------------------------------------

#[derive(Default)]
struct DoubleState {
    objects: BTreeMap<String, Vec<u8>>,
    request_log: Vec<(String, String)>,
    failures: Vec<String>,
    reject_all: bool,
    page_size: usize,
}

struct S3Double {
    port: u16,
    state: Arc<Mutex<DoubleState>>,
    stopped: Arc<AtomicBool>,
    listener: JoinHandle<()>,
}

impl S3Double {
    /// Start the double on the first loopback candidate port that answers.
    fn spawn(objects: BTreeMap<String, Vec<u8>>, ports: [u16; 2]) -> Self {
        for port in ports {
            let Ok(listener) = TcpListener::bind(("127.0.0.1", port)) else {
                continue;
            };
            let state = Arc::new(Mutex::new(DoubleState {
                objects,
                request_log: Vec::new(),
                failures: Vec::new(),
                reject_all: false,
                page_size: 3,
            }));
            let stopped = Arc::new(AtomicBool::new(false));
            let accept_state = Arc::clone(&state);
            let accept_stopped = Arc::clone(&stopped);
            let handle = thread::spawn(move || {
                for stream in listener.incoming() {
                    if accept_stopped.load(Ordering::SeqCst) {
                        break;
                    }
                    let Ok(stream) = stream else { break };
                    let state = Arc::clone(&accept_state);
                    thread::spawn(move || handle_connection(stream, &state));
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
        panic!("no loopback candidate port answered; attempted {ports:?}");
    }

    fn probe_ready(&self) {
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        loop {
            assert!(
                std::time::Instant::now() < deadline,
                "the synthetic S3 double never answered"
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

    fn reject_all(&self) {
        self.state.lock().expect("double state").reject_all = true;
    }

    fn requests(&self) -> Vec<(String, String)> {
        self.state.lock().expect("double state").request_log.clone()
    }

    fn assert_no_failures(&self, context: &str) {
        let failures = self.state.lock().expect("double state").failures.clone();
        assert!(
            failures.is_empty(),
            "S3 double verification failures ({context}): {failures:?}"
        );
    }
}

impl Drop for S3Double {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::SeqCst);
        // Wake the accept loop so it observes the stop flag and exits deterministically.
        let _ = TcpStream::connect(("127.0.0.1", self.port));
        let listener = std::mem::replace(&mut self.listener, thread::spawn(|| {}));
        let _ = listener.join();
    }
}

fn handle_connection(mut stream: TcpStream, state: &Arc<Mutex<DoubleState>>) {
    let mut buffer = Vec::new();
    let mut chunk = [0_u8; 8_192];
    // Read one complete request head (the store sends no bodies).
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
        if state.reject_all {
            error_response(403, "AccessDenied", "rejected by the synthetic double")
        } else {
            route_request(&method, &target, &headers, &state)
        }
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

fn run(arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(arguments)
        .env("HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID", TEST_ACCESS_KEY_ID)
        .env(
            "HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY",
            TEST_SECRET_ACCESS_KEY,
        )
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch")
}

fn object_store_arguments(
    url: &str,
    grant: &std::path::Path,
    index: Option<&std::path::Path>,
) -> Vec<String> {
    let mut arguments = vec![
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
    ];
    if let Some(index) = index {
        arguments.push("--index".to_owned());
        arguments.push(index.to_string_lossy().into_owned());
    }
    arguments
}

struct StdioMcpServer {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<String>,
    next_id: u64,
}

impl StdioMcpServer {
    fn spawn(arguments: &[String], credentials: bool) -> Self {
        let mut command = Command::new(env!("CARGO_BIN_EXE_healthmd"));
        command
            .args(arguments)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        if credentials {
            command
                .env("HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID", TEST_ACCESS_KEY_ID)
                .env(
                    "HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY",
                    TEST_SECRET_ACCESS_KEY,
                );
        } else {
            command.env_remove("HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID");
            command.env_remove("HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY");
        }
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
        let instructions = result["instructions"].as_str().expect("instructions");
        assert!(instructions.contains("healthmd_data_catalog"));
        assert!(!instructions.contains("pair"), "{instructions}");
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

/// Spawn a store server against the double under `grant`, with an explicit external index.
fn spawn_store(
    double: &S3Double,
    grant: &std::path::Path,
    index: &std::path::Path,
) -> StdioMcpServer {
    let url = format!("http://127.0.0.1:{}", double.port);
    let arguments = object_store_arguments(&url, grant, Some(index));
    StdioMcpServer::spawn(&arguments, true)
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
fn object_store_serves_the_agent_data_contract_over_stdio() {
    let corpus = Corpus::build();
    let double = S3Double::spawn(corpus.objects(), [48_311, 48_313]);
    let mut server = spawn_store(
        &double,
        &corpus.grant_bulk(),
        &fresh_index(&corpus, "catalog.json"),
    );

    let tools = server.request("tools/list", &json!({}));
    let tools = tools["result"]["tools"].as_array().expect("tools").clone();
    let names: Vec<&str> = tools
        .iter()
        .map(|tool| tool["name"].as_str().expect("tool name"))
        .collect();
    assert_eq!(
        names,
        [
            "healthmd_data_catalog",
            "healthmd_data_records",
            "healthmd_data_record_read",
            "healthmd_data_artifacts",
            "healthmd_data_artifact_read",
        ]
    );

    let (catalog, is_error) = server.call("healthmd_data_catalog", json!({"page": default_page()}));
    assert!(!is_error, "catalog query: {catalog}");
    assert_eq!(catalog["schema"], json!("healthmd.agent_query_response"));
    assert_eq!(catalog["schema_version"], json!(1));
    assert_eq!(catalog["operation"], json!("catalog"));
    assert_eq!(catalog["next_cursor"], Value::Null);
    assert_eq!(catalog["receipt"]["source_kind"], json!("object_store"));
    assert_eq!(catalog["receipt"]["policy_enforced"], json!(true));
    assert_eq!(catalog["receipt"]["returned_items"], json!(8));
    assert_eq!(
        catalog["items"].as_array().expect("catalog items"),
        &expected_bulk_catalog(),
        "the object-store catalog must equal the stdio directory-store catalog for the same corpus"
    );

    let (records, is_error) = server.call(
        "healthmd_data_records",
        json!({
            "metrics": {"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]},
            "sources": {"type": "all_available"},
            "dates": {"type": "all_available"},
            "times": {"type": "all_available"},
            "detail_level": "common",
            "page": default_page()
        }),
    );
    assert!(!is_error, "records query: {records}");
    assert_eq!(records["receipt"]["source_kind"], json!("object_store"));
    let items = records["items"].as_array().expect("record items");
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["value"], json!(12_345));
    assert_eq!(items[0]["inline"], json!(true));
    let encoded = serde_json::to_string(&records).expect("encoded records");
    assert!(
        !encoded.contains("restingHeartRate"),
        "an all-available grant still only exposes indexed metric records"
    );
    assert!(
        !encoded.contains("rogue"),
        "objects outside the served prefix are invisible"
    );

    double.assert_no_failures("catalog and records");
}

#[test]
fn object_store_chunked_record_read_reassembles_exactly_and_rejects_undersized_pages() {
    let corpus = Corpus::build();
    let double = S3Double::spawn(corpus.objects(), [48_321, 48_323]);
    let mut server = spawn_store(
        &double,
        &corpus.grant_bulk(),
        &fresh_index(&corpus, "record-read.json"),
    );

    let (records, is_error) = server.call(
        "healthmd_data_records",
        json!({
            "metrics": {"type": "all_available"},
            "detail_level": "lossless",
            "page": default_page()
        }),
    );
    assert!(!is_error, "records query: {records}");
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
    assert_eq!(assembled, expected_bytes, "exact chunk reassembly");

    // Pages at or below the chunk overhead bound are rejected before any bytes are returned.
    let (rejected, is_error) = server.call(
        "healthmd_data_record_read",
        json!({"record_id": record_id, "page": page(1, CHUNK_OVERHEAD_BYTES, None)}),
    );
    assert!(is_error, "undersized page: {rejected}");
    assert_eq!(rejected["error"], json!("healthmd_agent_page_too_small"));

    double.assert_no_failures("record read chunking");
}

#[test]
fn object_store_whole_artifact_read_is_chunked_and_exact() {
    let corpus = Corpus::build();
    let double = S3Double::spawn(corpus.objects(), [48_331, 48_333]);
    let mut server = spawn_store(
        &double,
        &corpus.grant_bulk(),
        &fresh_index(&corpus, "artifact-read.json"),
    );

    let (artifacts, is_error) =
        server.call("healthmd_data_artifacts", json!({"page": default_page()}));
    assert!(!is_error, "artifact listing: {artifacts}");
    assert_eq!(artifacts["receipt"]["source_kind"], json!("object_store"));
    let items = artifacts["items"].as_array().expect("artifact items");
    assert_eq!(items.len(), 5, "the five stdio corpus artifacts");
    assert!(items.iter().all(|item| {
        item["artifact_id"]
            .as_str()
            .is_some_and(|id| id.len() == 64)
    }));

    // Reassemble the whole lossless artifact through chunked reads with exact bytes.
    let expected = serde_json::to_vec(&lossless_daily()).expect("lossless artifact bytes");
    let target = items
        .iter()
        .find(|item| item["byte_count"].as_u64() == Some(expected.len() as u64))
        .expect("lossless artifact in listing");
    let artifact_id = target["artifact_id"]
        .as_str()
        .expect("artifact id")
        .to_owned();

    let mut cursor = None;
    let mut assembled = Vec::new();
    let mut chunks = 0_usize;
    loop {
        let (response, is_error) = server.call(
            "healthmd_data_artifact_read",
            json!({"artifact_id": artifact_id, "page": page(1, 4_096, cursor.as_deref())}),
        );
        assert!(!is_error, "artifact read: {response}");
        let item = &response["items"][0];
        assert_eq!(item["type"], json!("artifact_chunk"));
        assert_eq!(item["artifact_id"], json!(artifact_id));
        assert_eq!(item["sha256"], json!(artifact_id));
        assert_eq!(item["total_byte_count"], json!(expected.len()));
        assembled.extend_from_slice(
            &URL_SAFE_NO_PAD
                .decode(item["data"].as_str().expect("base64 data"))
                .expect("chunk decodes"),
        );
        chunks += 1;
        if item["complete"].as_bool().expect("complete flag") {
            break;
        }
        cursor = response["next_cursor"].as_str().map(str::to_owned);
    }
    assert!(chunks >= 2, "the whole artifact must need multiple chunks");
    assert_eq!(assembled, expected, "exact whole-artifact reassembly");
    assert_eq!(
        hex(&Sha256::digest(&assembled)),
        artifact_id,
        "the artifact id is the SHA-256 of the exact bytes"
    );

    let requests = double.requests();
    assert!(
        requests.iter().any(|(method, _)| method == "HEAD"),
        "verified byte access must head objects for a fast size check"
    );
    assert!(
        requests
            .iter()
            .all(|(method, _)| method == "GET" || method == "HEAD"),
        "only GET/HEAD methods may be sent, saw {requests:?}"
    );
    double.assert_no_failures("artifact chunking");
}

#[test]
fn object_store_bulk_download_stays_grant_gated() {
    let corpus = Corpus::build();
    let double = S3Double::spawn(corpus.objects(), [48_341, 48_343]);
    let mut server = spawn_store(
        &double,
        &corpus.grant_steps_only(),
        &fresh_index(&corpus, "denied.json"),
    );

    let (artifacts, is_error) =
        server.call("healthmd_data_artifacts", json!({"page": default_page()}));
    assert!(!is_error, "artifact listing: {artifacts}");
    assert_eq!(artifacts["items"], json!([]));
    assert_eq!(artifacts["receipt"]["returned_items"], json!(0));

    let (denied, is_error) = server.call(
        "healthmd_data_artifact_read",
        json!({"artifact_id": "0".repeat(64), "page": default_page()}),
    );
    assert!(is_error, "artifact read must be denied: {denied}");
    assert_eq!(
        denied["error"],
        json!("healthmd_agent_bulk_download_denied")
    );

    double.assert_no_failures("grant denial");
}

#[test]
fn object_store_never_issues_writes_and_restarts_are_idempotent() {
    let corpus = Corpus::build();
    let double = S3Double::spawn(corpus.objects(), [48_351, 48_353]);
    let shared_index = fresh_index(&corpus, "idempotent.json");

    let first_catalog = {
        let mut server = spawn_store(&double, &corpus.grant_bulk(), &shared_index);
        let (catalog, is_error) =
            server.call("healthmd_data_catalog", json!({"page": default_page()}));
        assert!(!is_error, "first catalog: {catalog}");
        catalog
    };
    let second_catalog = {
        let mut server = spawn_store(&double, &corpus.grant_bulk(), &shared_index);
        let (catalog, is_error) =
            server.call("healthmd_data_catalog", json!({"page": default_page()}));
        assert!(!is_error, "second catalog: {catalog}");
        catalog
    };
    assert_eq!(
        first_catalog["receipt"]["index_revision"], second_catalog["receipt"]["index_revision"],
        "identical bucket contents must produce an identical index revision across restarts"
    );
    assert_eq!(first_catalog["items"], second_catalog["items"]);

    // The store is read-only: only GET (list and object) and HEAD requests were recorded,
    // every path addressed the configured bucket, and no request carried a body.
    let requests = double.requests();
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
    double.assert_no_failures("read-only method set");
}

#[test]
fn object_store_parse_errors_reject_conflicting_and_incomplete_backing() {
    let corpus = Corpus::build();
    let grant = corpus.grant_bulk();
    let grant_text = grant.to_str().expect("utf-8 grant path").to_owned();
    let database = corpus.root.path().join("agent-data.sqlite");
    let database_text = database.to_str().expect("utf-8 database path").to_owned();
    let exports = corpus.root.path().join("exports-local");
    std::fs::create_dir(&exports).expect("local exports directory");
    let exports_text = exports.to_str().expect("utf-8 exports path").to_owned();

    let url = "http://127.0.0.1:1";
    let conflicting_directory = run(&[
        "mcp",
        "serve-data",
        "--object-store-url",
        url,
        "--bucket",
        BUCKET,
        "--prefix",
        "exports/",
        "--directory",
        &exports_text,
        "--grant",
        &grant_text,
    ]);
    assert!(!conflicting_directory.status.success());

    let conflicting_database = run(&[
        "mcp",
        "serve-data",
        "--object-store-url",
        url,
        "--bucket",
        BUCKET,
        "--database",
        &database_text,
        "--grant",
        &grant_text,
    ]);
    assert!(!conflicting_database.status.success());

    let missing_bucket = run(&[
        "mcp",
        "serve-data",
        "--object-store-url",
        url,
        "--grant",
        &grant_text,
    ]);
    assert!(!missing_bucket.status.success());

    let stray_prefix = run(&[
        "mcp",
        "serve-data",
        "--bucket",
        BUCKET,
        "--prefix",
        "exports/",
        "--grant",
        &grant_text,
    ]);
    assert!(!stray_prefix.status.success());

    let missing_backing = run(&["mcp", "serve-data", "--grant", &grant_text]);
    assert!(!missing_backing.status.success());

    // --index applies to object-store backing (accepted at parse; the run fails later on the
    // unreachable endpoint, proving the flag itself was not rejected). --index with
    // --database is still refused with the established message.
    let index_with_database = run(&[
        "mcp",
        "serve-data",
        "--object-store-url",
        "https://never-used.example",
        "--bucket",
        BUCKET,
        "--index",
        "/tmp/should-not-be-accepted.json",
        "--grant",
        &grant_text,
    ]);
    // The unreachable https endpoint fails at transport, not at parsing: exit 1 (not 2).
    assert_eq!(index_with_database.status.code(), Some(1));
    let stderr = String::from_utf8_lossy(&index_with_database.stderr);
    assert!(
        !stderr.contains("--index"),
        "object-store backing accepts --index: {stderr}"
    );
}

// Feature-off behavior assertion: with `object-store-tls` compiled in (e.g. --all-features)
// `https://` endpoints are spoken over TLS, so the "not available in this build" boundary
// this test pins no longer holds (and reaching it would contact a real endpoint). Default
// builds still run this test unchanged.
#[cfg(not(feature = "object-store-tls"))]
#[test]
fn object_store_url_policy_fails_closed_without_network() {
    let corpus = Corpus::build();
    let grant_text = corpus.grant_bulk().to_str().expect("utf-8 path").to_owned();

    let plain_http = run(&[
        "mcp",
        "serve-data",
        "--object-store-url",
        "http://accountid.r2.cloudflarestorage.com",
        "--bucket",
        BUCKET,
        "--grant",
        &grant_text,
    ]);
    assert!(!plain_http.status.success());
    let stderr = String::from_utf8_lossy(&plain_http.stderr);
    assert!(
        stderr.contains("https"),
        "the refusal must name the https requirement: {stderr}"
    );
    assert!(
        stderr.contains("loopback"),
        "and the loopback affordance: {stderr}"
    );

    let not_a_url = run(&[
        "mcp",
        "serve-data",
        "--object-store-url",
        "ftp://127.0.0.1:9876",
        "--bucket",
        BUCKET,
        "--grant",
        &grant_text,
    ]);
    assert!(!not_a_url.status.success());
    assert!(
        String::from_utf8_lossy(&not_a_url.stderr).contains("http"),
        "a stable URL-shape error"
    );

    // https endpoints pass the URL policy but this build carries no TLS socket layer, so the
    // open fails health-free at transport time instead of reaching any network endpoint.
    let https = run(&[
        "mcp",
        "serve-data",
        "--object-store-url",
        "https://accountid.r2.cloudflarestorage.com",
        "--bucket",
        BUCKET,
        "--grant",
        &grant_text,
    ]);
    assert!(!https.status.success());
    let stderr = String::from_utf8_lossy(&https.stderr);
    assert!(
        stderr.contains("https object-store transport is not available"),
        "the TLS boundary must be stated honestly: {stderr}"
    );
}

#[test]
fn object_store_missing_credentials_fail_closed_before_any_request() {
    let corpus = Corpus::build();
    let double = S3Double::spawn(corpus.objects(), [48_361, 48_363]);
    let url = format!("http://127.0.0.1:{}", double.port);
    let arguments = object_store_arguments(
        &url,
        &corpus.grant_bulk(),
        Some(&fresh_index(&corpus, "creds.json")),
    );
    // Spawn without credentials; the server must exit without ever touching the double.
    let child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(&arguments)
        .env_remove("HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID")
        .env_remove("HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("healthmd should launch without credentials");
    let output = child.wait_with_output().expect("child exits");
    assert!(!output.status.success(), "missing credentials must fail");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID"),
        "the failure names the required variables: {stderr}"
    );
    assert!(
        !stderr.contains(TEST_SECRET_ACCESS_KEY),
        "no credential material may appear in output"
    );
    assert!(
        double.requests().is_empty(),
        "no request may be sent before credentials exist"
    );
}

#[test]
fn object_store_access_denied_fails_with_a_health_free_open_error() {
    let corpus = Corpus::build();
    let mut objects = corpus.objects();
    objects.clear();
    let double = S3Double::spawn(objects, [48_371, 48_373]);
    double.reject_all();
    let url = format!("http://127.0.0.1:{}", double.port);
    let arguments = object_store_arguments(
        &url,
        &corpus.grant_bulk(),
        Some(&fresh_index(&corpus, "denied.json")),
    );
    let child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(&arguments)
        .env("HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID", TEST_ACCESS_KEY_ID)
        .env(
            "HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY",
            TEST_SECRET_ACCESS_KEY,
        )
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("healthmd should launch");
    let output = child.wait_with_output().expect("child exits");
    assert!(
        !output.status.success(),
        "a rejecting store must fail to open"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("the object store rejected the request"),
        "a stable health-free refusal: {stderr}"
    );
    assert!(
        !stderr.contains(TEST_ACCESS_KEY_ID),
        "no credential material may appear in output"
    );
}

#[test]
fn object_store_double_serves_ranged_gets_for_the_frozen_subset() {
    // Direct double probe: prove the double itself honors Range requests (the frozen S3
    // subset capability), independent of the store's current full-GET byte access.
    let corpus = Corpus::build();
    let double = S3Double::spawn(corpus.objects(), [48_381, 48_383]);
    let mut objects = corpus.objects();
    let key = "exports/bare.json".to_owned();
    let bytes = objects.remove(&key).expect("bare artifact bytes");
    let path = format!("/{BUCKET}/{key}");
    let range = (5, 20);
    let expected = &bytes[range.0..=range.1];

    let amz_date = "20260102T030405Z";
    let host = format!("127.0.0.1:{}", double.port);
    let headers = [
        ("host".to_owned(), host.clone()),
        ("range".to_owned(), format!("bytes={}-{}", range.0, range.1)),
        (
            "x-amz-content-sha256".to_owned(),
            "UNSIGNED-PAYLOAD".to_owned(),
        ),
        ("x-amz-date".to_owned(), amz_date.to_owned()),
    ];
    let signed_headers = "host;range;x-amz-content-sha256;x-amz-date";
    let mut canonical_headers = String::new();
    for (name, value) in &headers {
        canonical_headers.push_str(name);
        canonical_headers.push(':');
        canonical_headers.push_str(value);
        canonical_headers.push('\n');
    }
    let canonical_request =
        format!("GET\n{path}\n\n{canonical_headers}\n{signed_headers}\nUNSIGNED-PAYLOAD");
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{amz_date}\n20260102/{TEST_REGION}/s3/aws4_request\n{}",
        hex(&Sha256::digest(canonical_request.as_bytes()))
    );
    let mut key_material = hmac_sha256(
        format!("AWS4{TEST_SECRET_ACCESS_KEY}").as_bytes(),
        b"20260102",
    );
    for part in [TEST_REGION, "s3", "aws4_request"] {
        key_material = hmac_sha256(&key_material, part.as_bytes());
    }
    let signature = hex(&hmac_sha256(&key_material, string_to_sign.as_bytes()));
    let authorization = format!(
        "AWS4-HMAC-SHA256 Credential={TEST_ACCESS_KEY_ID}/20260102/{TEST_REGION}/s3/aws4_request, SignedHeaders={signed_headers}, Signature={signature}"
    );

    let mut stream = TcpStream::connect(("127.0.0.1", double.port)).expect("connect to double");
    let request = format!(
        "GET {path} HTTP/1.1\r\nHost: {host}\r\nRange: bytes={}-{}\r\nx-amz-content-sha256: UNSIGNED-PAYLOAD\r\nx-amz-date: {amz_date}\r\nAuthorization: {authorization}\r\nConnection: close\r\n\r\n",
        range.0, range.1
    );
    stream.write_all(request.as_bytes()).expect("write request");
    let raw = read_to_completion(&mut stream);
    let header_end = raw
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .expect("response headers");
    let head = String::from_utf8_lossy(&raw[..header_end]).into_owned();
    assert!(
        head.starts_with("HTTP/1.1 206"),
        "ranged GET returns 206: {head}"
    );
    assert_eq!(&raw[header_end + 4..], expected, "exact range window");
    double.assert_no_failures("ranged GET probe");
}

/// Read one complete `Connection: close` response framed by `Content-Length`.
fn read_to_completion(stream: &mut TcpStream) -> Vec<u8> {
    let mut raw = Vec::new();
    let mut chunk = [0_u8; 8_192];
    loop {
        match stream.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(read) => {
                raw.extend_from_slice(&chunk[..read]);
                if let Some(header_end) = raw.windows(4).position(|window| window == b"\r\n\r\n") {
                    let head = String::from_utf8_lossy(&raw[..header_end]).to_ascii_lowercase();
                    let length = head
                        .lines()
                        .find_map(|line| line.strip_prefix("content-length:"))
                        .and_then(|value| value.trim().parse::<usize>().ok());
                    if let Some(length) = length {
                        if raw.len() >= header_end + 4 + length {
                            break;
                        }
                    }
                }
            }
        }
    }
    raw
}
