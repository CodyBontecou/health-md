//! End-to-end store-parity harness for the Health.md Agent Data MCP surface.
//!
//! These tests spawn the *shipped* `healthmd` binary (`mcp serve-data`) as a child process and
//! drive it over real newline-delimited JSON-RPC 2.0 on stdio: initialize handshake, `tools/list`,
//! and `tools/call` for every fixed Agent Data tool. The synthetic corpus and every expectation
//! below are derived from the normative v1 contract
//! (`packages/contracts/agent-data/v1/contract.md`, `apps/cli/docs/agent-data.md`) and from the
//! observed behavior of the shipped binary; opaque identifiers (record/artifact SHA-256 digests)
//! are discovered through the surface and cross-checked for consistency rather than predicted.
//!
//! Store-parity kit: the corpus builder and every scenario run unchanged against all THREE
//! store backings through [`StoreEndpoint`]: the v1 directory store
//! (`--directory/--grant/--index`), the Health.md-owned `SQLite` database, whose endpoints
//! [`StoreEndpoint::database`] populates by driving the real `healthmd data import` binary over
//! the corpus before the first spawn and then serves with `--database/--grant`, and the
//! read-only S3-compatible object store, whose endpoints [`StoreEndpoint::object_store`]
//! serve with `--object-store-url/--bucket/--prefix/--grant/--index` against an embedded
//! synthetic loopback S3 double holding the same corpus files under `exports/` and verifying
//! the AWS `SigV4` signature of every request. Per-store expectations are provided by the
//! endpoint itself (receipt `source_kind`, the misplaced-grant expectation: local backings
//! refuse grants stored inside their private backing, while the object store has no local
//! containment rule against a remote backing and its grant-shaped bucket object is ignored
//! content); everything else is store-neutral. Keep new scenarios parameterized by endpoint,
//! never by global state.
//!
//! Harness facts (observed, frozen): the server speaks one JSON document per `\n`-terminated
//! line, echoes the negotiated MCP protocol version, ignores notifications, rejects duplicate
//! request identifiers with `-32600`, and cancels in-flight requests when stdin closes, so the
//! child's stdin stays open for the life of each server handle.

use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::Write as _,
    io::{BufRead as _, Read as _, Write as _},
    net::{TcpListener, TcpStream},
    path::PathBuf,
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
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

static INDEX_SEQUENCE: AtomicUsize = AtomicUsize::new(0);

// ---------------------------------------------------------------------------
// Object-store double fixtures (fixed synthetic values, never real)
// ---------------------------------------------------------------------------

/// Fixed synthetic credentials shared by the embedded double and the spawned object store.
const OBJECT_TEST_ACCESS_KEY_ID: &str = "HEALTHMDTESTACCESSKEY1";
const OBJECT_TEST_SECRET_ACCESS_KEY: &str = "healthmd-test-secret-key-0000000000000000000001";
/// The store signs with region `auto` (Cloudflare R2); the double verifies the same scope.
const OBJECT_TEST_REGION: &str = "auto";
/// Fixed synthetic bucket whose prefix the object-store endpoints serve.
const OBJECT_BUCKET: &str = "healthmd-test-bucket";
/// Fixed synthetic `LastModified` for every object so index rebuilds/restarts are idempotent.
const FIXED_LAST_MODIFIED: &str = "2026-01-02T03:04:05.000Z";
/// The double pages listings at three keys, forcing `ListObjectsV2` continuation traffic.
const LIST_PAGE_SIZE: usize = 3;
/// Loopback port candidates for the embedded object-store double, probed before binding with
/// fall-through. This suite owns 48411–48493; sibling suites own 481xx/482xx/483xx/485xx.
const OBJECT_STORE_DOUBLE_PORTS: [u16; 23] = [
    48_411, 48_413, 48_417, 48_419, 48_423, 48_429, 48_431, 48_437, 48_441, 48_443, 48_447, 48_449,
    48_453, 48_459, 48_461, 48_467, 48_471, 48_473, 48_477, 48_479, 48_483, 48_489, 48_493,
];

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

/// The synthetic export corpus. Every expected value in the scenarios below is derived from
/// these documents, not from server output.
struct Corpus {
    root: TempDir,
}

impl Corpus {
    /// Build the corpus directory: five valid artifacts, one unsupported file, one malformed
    /// candidate, plus out-of-tree grant and index locations.
    fn build() -> Self {
        let root = TempDir::new().expect("temporary corpus root");
        let exports = root.path().join("exports");
        std::fs::create_dir(&exports).expect("export directory");
        write_json(&exports.join("bare.json"), &bare_daily());
        write_json(&exports.join("api-export.json"), &api_export());
        write_json(&exports.join("lossless.json"), &lossless_daily());
        let snapshot_bytes = snapshot_ndjson_bytes();
        std::fs::write(exports.join("raw-snapshot.ndjson"), &snapshot_bytes)
            .expect("raw snapshot artifact");
        write_json(&exports.join("raw-changes.json"), &raw_changes());
        std::fs::write(exports.join("notes.txt"), b"not health data").expect("unsupported file");
        std::fs::write(exports.join("broken.json"), BROKEN_JSON.as_bytes())
            .expect("malformed candidate");
        std::fs::create_dir(root.path().join("grants")).expect("grant directory");
        std::fs::create_dir(root.path().join("indexes")).expect("index directory");
        std::fs::create_dir(root.path().join("databases")).expect("database directory");
        Self { root }
    }

    fn exports(&self) -> PathBuf {
        self.root.path().join("exports")
    }

    /// The corpus as object-store bucket contents: every file under `exports/` served as-is
    /// under the same relative key — including the unsupported and malformed entries, so the
    /// never-queryable expectations hold identically — plus the grant-shaped object the
    /// misplaced-grant scenario proves is ignored content on this backing.
    fn object_corpus_objects(&self) -> BTreeMap<String, Vec<u8>> {
        let mut objects = BTreeMap::new();
        for entry in std::fs::read_dir(self.exports()).expect("corpus exports directory") {
            let entry = entry.expect("corpus file");
            if !entry.file_type().expect("corpus file").is_file() {
                continue;
            }
            let name = entry.file_name();
            let bytes = std::fs::read(entry.path()).expect("corpus bytes");
            objects.insert(format!("exports/{}", name.to_string_lossy()), bytes);
        }
        let misplaced = grant(
            all_available(),
            all_available(),
            all_available(),
            all_available(),
            json!(["common", "lossless"]),
            true,
        );
        objects.insert(
            "exports/misplaced-grant.json".to_owned(),
            serde_json::to_vec(&misplaced).expect("misplaced grant object"),
        );
        objects
    }

    fn write_grant(&self, name: &str, grant: &Value) -> PathBuf {
        let path = self.root.path().join("grants").join(name);
        write_json(&path, grant);
        path
    }

    /// Unrestricted bulk grant: both detail levels, every selection `all_available`, and
    /// `bulk_download: true` — the only shape that may list or read whole artifacts.
    fn grant_bulk(&self) -> PathBuf {
        self.write_grant(
            "bulk.json",
            &grant(
                all_available(),
                all_available(),
                all_available(),
                all_available(),
                json!(["common", "lossless"]),
                true,
            ),
        )
    }

    /// Narrow record-level grant: only the bare daily's steps pointer, common level, no bulk.
    fn grant_steps_only(&self) -> PathBuf {
        self.write_grant(
            "steps-only.json",
            &grant(
                json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common"]),
                false,
            ),
        )
    }

    /// Grant with only one of the two metrics attributed to the multi-metric `HealthKit` record.
    fn grant_one_of_two_attributions(&self) -> PathBuf {
        self.write_grant(
            "one-of-two.json",
            &grant(
                json!({"type": "explicit", "metric_ids": ["healthmd.healthkit_records#metric:heart_rate_avg"]}),
                all_available(),
                all_available(),
                all_available(),
                json!(["lossless"]),
                false,
            ),
        )
    }

    /// Grant with a two-second exact instant window on 2026-03-15.
    fn grant_exact_instant(&self) -> PathBuf {
        self.write_grant(
            "exact-instant.json",
            &grant(
                all_available(),
                all_available(),
                all_available(),
                json!({
                    "type": "exact",
                    "start_inclusive": "2026-03-15T12:00:00Z",
                    "end_exclusive": "2026-03-15T12:00:02Z"
                }),
                json!(["common", "lossless"]),
                false,
            ),
        )
    }

    /// Grant with an exact owner-date window on 2026-03-15 and unrestricted times.
    fn grant_exact_date(&self) -> PathBuf {
        self.write_grant(
            "exact-date.json",
            &grant(
                all_available(),
                all_available(),
                json!({"type": "exact", "start_date": "2026-03-15", "end_date": "2026-03-15"}),
                all_available(),
                json!(["common"]),
                false,
            ),
        )
    }

    /// One directory-store endpoint for the parity kit, with a fresh external index path.
    fn endpoint(&self, grant: &std::path::Path) -> StoreEndpoint {
        let sequence = INDEX_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        StoreEndpoint::directory(
            self.exports(),
            grant.to_path_buf(),
            self.root
                .path()
                .join("indexes")
                .join(format!("index-{sequence}.json")),
        )
    }

    /// One `SQLite`-store endpoint for the parity kit, backed by a fresh database populated
    /// from this corpus by the real `healthmd data import` binary.
    fn database_endpoint(&self, grant: &std::path::Path) -> StoreEndpoint {
        let sequence = INDEX_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        StoreEndpoint::database(
            self.root
                .path()
                .join("databases")
                .join(format!("store-{sequence}.sqlite")),
            &self.exports(),
            grant.to_path_buf(),
        )
    }

    /// One object-store endpoint for the parity kit: this corpus served under `exports/` by
    /// an embedded synthetic loopback S3 double, with a fresh external index path like the
    /// directory store (the default index is keyed by URL+bucket+prefix, so per-endpoint
    /// isolation must come from the explicit fresh path).
    fn object_store_endpoint(&self, grant: &std::path::Path) -> StoreEndpoint {
        let sequence = INDEX_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        StoreEndpoint::object_store(
            self.object_corpus_objects(),
            grant.to_path_buf(),
            self.root
                .path()
                .join("indexes")
                .join(format!("index-{sequence}.json")),
        )
    }

    /// Every store the parity kit proves, in a fixed order (directory first, then the
    /// Health.md-owned database, then the object store); each scenario iterates this list
    /// unchanged.
    fn endpoints(&self, grant: &std::path::Path) -> Vec<StoreEndpoint> {
        vec![
            self.endpoint(grant),
            self.database_endpoint(grant),
            self.object_store_endpoint(grant),
        ]
    }
}

fn all_available() -> Value {
    json!({"type": "all_available"})
}

#[allow(clippy::needless_pass_by_value)]
#[allow(clippy::too_many_arguments)]
fn grant(
    metrics: Value,
    sources: Value,
    dates: Value,
    times: Value,
    detail_levels: Value,
    bulk_download: bool,
) -> Value {
    json!({
        "schema": "healthmd.agent_data_grant",
        "schema_version": 1,
        "metrics": metrics,
        "sources": sources,
        "dates": dates,
        "times": times,
        "detail_levels": detail_levels,
        "bulk_download": bulk_download
    })
}

fn write_json(path: &std::path::Path, value: &Value) {
    std::fs::write(
        path,
        serde_json::to_string(value).expect("grant or artifact JSON"),
    )
    .expect("corpus file");
}

/// Minimal bare daily `health-data` document (outside any envelope).
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

/// The same daily shape wrapped in a `healthmd.api_export` envelope for a second owner date.
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

/// `HealthKit` archive record attributed to exactly one metric (12:00:00–12:00:01Z).
fn heart_rate_avg_record() -> Value {
    json!({
        "record_kind": "quantity",
        "start_date": "2026-03-15T12:00:00Z",
        "end_date": "2026-03-15T12:00:01Z",
        "metric_attribution": {"direct_metric_ids": ["heart_rate_avg"]},
        "payload": {"value": 72}
    })
}

/// `HealthKit` archive record attributed to TWO metrics, with a payload large enough to force
/// chunked `healthmd_data_record_read` reassembly (outside every instant gate used below).
fn heart_rate_multi_record() -> Value {
    json!({
        "record_kind": "quantity",
        "start_date": "2026-03-15T12:05:00Z",
        "end_date": "2026-03-15T12:05:30Z",
        "selected_metric_ids": ["heart_rate_avg", "heart_rate_min"],
        "payload": {"value": 64, "waveform": "x".repeat(6_000)}
    })
}

/// Daily export carrying a lossless `healthmd.healthkit_records` archive.
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

/// Complete Android raw snapshot as NDJSON. Line 3's record deliberately carries no parseable
/// instant key, so it is date-less and instant-less for the grant gates.
fn snapshot_ndjson_bytes() -> Vec<u8> {
    let mut bytes = Vec::new();
    for line in SNAPSHOT_LINES {
        bytes.extend_from_slice(line.as_bytes());
        bytes.push(b'\n');
    }
    bytes
}

/// Complete Android raw-changes archive with one observed upsert event.
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

/// Daily candidate whose date is unparseable: counted as an invalid artifact, never queryable.
const BROKEN_JSON: &str = r#"{"schema":"healthmd.health_data","schema_version":8,"date":"2026-13-45","type":"health-data"}"#;

// ---------------------------------------------------------------------------
// Synthetic loopback S3 double (object-store backing)
// ---------------------------------------------------------------------------

/// `SigV4` HMAC helper (independent test-side implementation).
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

/// Verify one request's `SigV4` authorization against the fixed synthetic test keys.
/// Returns a failure description when invalid.
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
    if credential.split('/').next() != Some(OBJECT_TEST_ACCESS_KEY_ID) {
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
    if scope_parts[3] != "s3"
        || scope_parts[4] != "aws4_request"
        || scope_parts[2] != OBJECT_TEST_REGION
    {
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
        "AWS4-HMAC-SHA256\n{amz_date}\n{scope_date}/{OBJECT_TEST_REGION}/s3/aws4_request\n{}",
        hex(&Sha256::digest(canonical_request.as_bytes()))
    );
    let mut key = hmac_sha256(
        format!("AWS4{OBJECT_TEST_SECRET_ACCESS_KEY}").as_bytes(),
        scope_date.as_bytes(),
    );
    for part in [OBJECT_TEST_REGION, "s3", "aws4_request"] {
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

#[derive(Debug)]
struct DoubleState {
    objects: BTreeMap<String, Vec<u8>>,
    request_log: Vec<(String, String)>,
    failures: Vec<String>,
}

/// A minimal std-only loopback S3 double implementing exactly the frozen subset the store
/// may use: `ListObjectsV2` (prefix + continuation) XML, `HEAD` object, and `GET` object
/// (with `Range`) at path-style addresses, plus `SigV4` verification of every request, a
/// request method+path log, and fixed `LastModified` values so index rebuilds are
/// idempotent. The double runs for the owning endpoint's lifetime (shared by its clones)
/// and stops deterministically when the last clone drops.
#[derive(Debug)]
struct S3Double {
    port: u16,
    state: Arc<Mutex<DoubleState>>,
    stopped: Arc<AtomicBool>,
    listener: JoinHandle<()>,
}

impl S3Double {
    /// Start the double on the first loopback candidate port that answers.
    fn spawn(objects: BTreeMap<String, Vec<u8>>, ports: &[u16]) -> Self {
        for port in ports {
            let Ok(listener) = TcpListener::bind(("127.0.0.1", *port)) else {
                continue;
            };
            let state = Arc::new(Mutex::new(DoubleState {
                objects,
                request_log: Vec::new(),
                failures: Vec::new(),
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
                port: *port,
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

    fn requests(&self) -> Vec<(String, String)> {
        self.state.lock().expect("double state").request_log.clone()
    }

    /// Assert every request observed so far was fully `SigV4`-verified, carried no body,
    /// used only the read-only method set, and addressed the configured bucket.
    fn assert_read_only_traffic(&self, context: &str) {
        let state = self.state.lock().expect("double state");
        assert!(
            state.failures.is_empty(),
            "S3 double verification failures ({context}): {:?}",
            state.failures
        );
        for (method, target) in &state.request_log {
            assert!(
                matches!(method.as_str(), "GET" | "HEAD"),
                "only GET/HEAD methods may be sent ({context}), saw {method} {target}"
            );
            assert!(
                target.starts_with(&format!("/{OBJECT_BUCKET}")),
                "every request must address the configured bucket ({context}), saw {method} {target}"
            );
        }
    }
}

impl Drop for S3Double {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::SeqCst);
        // Wake the accept loop so it observes the stop flag and exits deterministically.
        let _ = TcpStream::connect(("127.0.0.1", self.port));
        let listener = std::mem::replace(&mut self.listener, thread::spawn(|| {}));
        let _ = listener.join();
        // Failures never verified by a scenario hook are reported without panicking: a panic
        // from a destructor during an unwinding test would abort the whole test process.
        let failures = self.state.lock().expect("double state").failures.clone();
        if !failures.is_empty() {
            eprintln!("S3 double dropped with unverified failures: {failures:?}");
        }
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
        if method != "GET" && method != "HEAD" {
            state.failures.push(format!(
                "the read-only store must never issue {method} requests"
            ));
        }
        if let Err(failure) = verify_sigv4(&method, &target, &headers) {
            state.failures.push(format!("SigV4: {failure}"));
        }
        route_request(&method, &target, &headers, &state)
    };
    let _ = stream.write_all(&response);
    let _ = stream.flush();
}

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
    let Some(key) = path.strip_prefix(&format!("/{OBJECT_BUCKET}/")) else {
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
    if path != format!("/{OBJECT_BUCKET}") {
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
    let matched: Vec<&String> = state
        .objects
        .keys()
        .filter(|key| key.starts_with(&prefix))
        .collect();
    let end = (offset + LIST_PAGE_SIZE).min(matched.len());
    let truncated = end < matched.len();
    let mut body = String::from(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">",
    );
    let _ = write!(body, "\n  <Name>{OBJECT_BUCKET}</Name>");
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
// Store endpoint and stdio JSON-RPC client
// ---------------------------------------------------------------------------

/// One Agent Data store backing under test. The directory store is the v1 shape; the
/// Health.md-owned `SQLite` database is populated by `healthmd data import` and owns its
/// index internally; the object-store backing serves the corpus through an embedded
/// synthetic loopback S3 double (shared by an endpoint's clones, stopped when the last one
/// drops) with a fresh external index per endpoint.
#[derive(Clone, Debug)]
enum StoreBacking {
    Directory {
        directory: PathBuf,
        index: PathBuf,
    },
    Database {
        database: PathBuf,
    },
    ObjectStore {
        double: Arc<S3Double>,
        index: PathBuf,
    },
}

/// The misplaced-grant expectation for one backing, provided by the endpoint so scenario
/// bodies stay store-neutral. Local backings refuse grants stored inside their private
/// backing; the object store has no local containment rule against a remote backing, so its
/// grant-shaped bucket object is ordinary ignored content (counted, never loaded) and the
/// scenario asserts that documented asymmetry instead of a refusal.
#[derive(Debug)]
enum MisplacedGrant {
    /// `serve-data` must refuse the grant at `path`, printing `reason` on stderr.
    Refused { path: PathBuf, reason: &'static str },
    /// The corpus's grant-shaped bucket object must stay ignored content under a local grant.
    IgnoredBucketContent,
}

/// One configured store endpoint: a backing plus the serving grant. Scenarios never inspect
/// the backing directly; they ask the endpoint for its argv and its per-store expectations.
#[derive(Clone, Debug)]
struct StoreEndpoint {
    backing: StoreBacking,
    grant: PathBuf,
}

impl StoreEndpoint {
    /// Directory-store endpoint, served with `--directory … --grant … --index …`.
    fn directory(directory: PathBuf, grant: PathBuf, index: PathBuf) -> Self {
        Self {
            backing: StoreBacking::Directory { directory, index },
            grant,
        }
    }

    /// Database-store endpoint: populates `database` from `exports` by driving the real
    /// `healthmd data import` binary before the endpoint can ever serve, then serves it with
    /// `--database … --grant …` (the database store owns its index internally).
    fn database(database: PathBuf, exports: &std::path::Path, grant: PathBuf) -> Self {
        import_corpus_into_database(&database, exports);
        Self {
            backing: StoreBacking::Database { database },
            grant,
        }
    }

    /// Object-store endpoint: spawns the embedded synthetic loopback S3 double holding
    /// `objects` for the endpoint's lifetime (shared by its clones), then serves it with
    /// `--object-store-url … --bucket … --prefix exports/ --grant … --index …` under the
    /// fixed synthetic test credentials taken from the environment.
    fn object_store(objects: BTreeMap<String, Vec<u8>>, grant: PathBuf, index: PathBuf) -> Self {
        let double = S3Double::spawn(objects, &OBJECT_STORE_DOUBLE_PORTS);
        Self {
            backing: StoreBacking::ObjectStore {
                double: Arc::new(double),
                index,
            },
            grant,
        }
    }

    /// The same store under a different serving grant: scenarios re-authorize the identical
    /// corpus through grants bound to it.
    fn with_grant(&self, grant: &std::path::Path) -> Self {
        let mut endpoint = self.clone();
        endpoint.grant = grant.to_path_buf();
        endpoint
    }

    /// The receipt `source_kind` this store must report for every query response.
    fn expected_source_kind(&self) -> &'static str {
        match &self.backing {
            StoreBacking::Directory { .. } => "directory",
            StoreBacking::Database { .. } => "database",
            StoreBacking::ObjectStore { .. } => "object_store",
        }
    }

    /// A grant deliberately stored inside the store's private backing, together with the
    /// refusal reason `serve-data` must print for it — except the object store, which has no
    /// local containment rule against its remote backing (see [`MisplacedGrant`]).
    fn misplaced_grant(&self) -> MisplacedGrant {
        match &self.backing {
            StoreBacking::Directory { directory, .. } => MisplacedGrant::Refused {
                path: directory.join("inside-grant.json"),
                reason: "outside the export directory",
            },
            StoreBacking::Database { database } => MisplacedGrant::Refused {
                path: database.clone(),
                reason: "outside the Agent Data database",
            },
            StoreBacking::ObjectStore { .. } => MisplacedGrant::IgnoredBucketContent,
        }
    }

    /// The `mcp serve-data` argv for this store under `grant`.
    fn argv_with_grant(&self, grant: &std::path::Path) -> Vec<String> {
        let grant = grant.to_string_lossy().into_owned();
        let mut argv = vec!["mcp".to_owned(), "serve-data".to_owned()];
        match &self.backing {
            StoreBacking::Directory { directory, index } => {
                argv.push("--directory".to_owned());
                argv.push(directory.to_string_lossy().into_owned());
                argv.push("--grant".to_owned());
                argv.push(grant);
                argv.push("--index".to_owned());
                argv.push(index.to_string_lossy().into_owned());
            }
            StoreBacking::Database { database } => {
                argv.push("--database".to_owned());
                argv.push(database.to_string_lossy().into_owned());
                argv.push("--grant".to_owned());
                argv.push(grant);
            }
            StoreBacking::ObjectStore { double, index } => {
                argv.push("--object-store-url".to_owned());
                argv.push(format!("http://127.0.0.1:{}", double.port));
                argv.push("--bucket".to_owned());
                argv.push(OBJECT_BUCKET.to_owned());
                argv.push("--prefix".to_owned());
                argv.push("exports/".to_owned());
                argv.push("--grant".to_owned());
                argv.push(grant);
                argv.push("--index".to_owned());
                argv.push(index.to_string_lossy().into_owned());
            }
        }
        argv
    }

    fn argv(&self) -> Vec<String> {
        self.argv_with_grant(&self.grant)
    }

    /// Extra environment for spawning this store: the object store reads its credentials
    /// only from the environment (never flags), so the endpoint provides the fixed synthetic
    /// test keys; the local backings need none.
    fn environment(&self) -> Vec<(String, String)> {
        match &self.backing {
            StoreBacking::ObjectStore { .. } => vec![
                (
                    "HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID".to_owned(),
                    OBJECT_TEST_ACCESS_KEY_ID.to_owned(),
                ),
                (
                    "HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY".to_owned(),
                    OBJECT_TEST_SECRET_ACCESS_KEY.to_owned(),
                ),
            ],
            StoreBacking::Directory { .. } | StoreBacking::Database { .. } => Vec::new(),
        }
    }

    /// Spawn the shipped binary with piped stdio and perform the initialize handshake.
    fn serve(&self) -> StdioMcpServer {
        if let StoreBacking::ObjectStore { double, .. } = &self.backing {
            // Traffic observed so far on this endpoint's double must be read-only and fully
            // SigV4-verified before another server instance joins it.
            double.assert_read_only_traffic("before the next serve-data spawn");
        }
        StdioMcpServer::spawn(&self.argv(), &self.environment())
    }

    /// Verify the object-store endpoint's double observed only list/head/get traffic, every
    /// request fully verified, and at least one listing served. Local backings have no double.
    fn assert_double_clean(&self, context: &str) {
        if let StoreBacking::ObjectStore { double, .. } = &self.backing {
            double.assert_read_only_traffic(context);
            assert!(
                double
                    .requests()
                    .iter()
                    .any(|(method, target)| method == "GET" && target.contains("list-type=2")),
                "the double must have served at least one listing ({context})"
            );
        }
    }
}

/// Populate a `SQLite` store exactly as an operator would — by driving the real binary — and
/// verify the honest ingest report for this corpus: six supported-extension candidates are
/// scanned (unsupported files like `notes.txt` are never scanned at all), five artifacts are
/// imported carrying eight records, and the one malformed candidate (`broken.json`) is counted
/// invalid without failing the import.
fn import_corpus_into_database(database: &std::path::Path, exports: &std::path::Path) {
    let output = Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(["data", "import", "--database"])
        .arg(database)
        .args(["--directory"])
        .arg(exports)
        .stdin(Stdio::null())
        .output()
        .expect("healthmd data import should launch");
    assert!(
        output.status.success(),
        "data import should succeed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let report: Value = serde_json::from_slice(&output.stdout).expect("import report JSON");
    assert_eq!(report["schema"], json!("healthmd.agent_data_import"));
    assert_eq!(report["status"], json!("success"));
    assert_eq!(report["scanned_file_count"], json!(6));
    assert_eq!(report["imported_artifact_count"], json!(5));
    assert_eq!(report["duplicate_artifact_count"], json!(0));
    assert_eq!(report["ignored_file_count"], json!(0));
    assert_eq!(report["invalid_file_count"], json!(1));
    assert_eq!(report["artifact_count"], json!(5));
    assert_eq!(report["record_count"], json!(8));
}

#[derive(Debug)]
enum ToolResponse {
    /// A successful JSON-RPC `tools/call` result; `payload` is the parsed text content.
    Result { payload: Value, is_error: bool },
    /// A JSON-RPC-level error (unknown tool, invalid arguments, protocol misuse).
    RpcError { code: i64, message: String },
}

impl ToolResponse {
    fn expect_success(&self, tool: &str) -> Value {
        let ToolResponse::Result { payload, is_error } = self else {
            panic!("{tool} returned a JSON-RPC error instead of a tool result: {self:?}");
        };
        assert!(!is_error, "{tool} returned an error payload: {payload}");
        payload.clone()
    }

    fn expect_payload_error(&self, tool: &str, code: &str) {
        let ToolResponse::Result { payload, is_error } = self else {
            panic!("{tool} returned a JSON-RPC error instead of a tool payload: {self:?}");
        };
        assert!(is_error, "{tool} unexpectedly succeeded: {payload}");
        assert_eq!(payload["error"], json!(code), "{tool} payload: {payload}");
    }

    fn expect_rpc_error(&self, code: i64, message: &str) {
        let ToolResponse::RpcError {
            code: actual,
            message: actual_message,
        } = self
        else {
            panic!("expected a JSON-RPC error {code} ({message}), got a tool result: {self:?}");
        };
        assert_eq!(*actual, code);
        assert_eq!(actual_message, message);
    }
}

struct StdioMcpServer {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<String>,
    next_id: u64,
}

impl StdioMcpServer {
    fn spawn(argv: &[String], environment: &[(String, String)]) -> Self {
        let mut command = Command::new(env!("CARGO_BIN_EXE_healthmd"));
        command
            .args(argv)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        for (name, value) in environment {
            command.env(name, value);
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

    /// Perform the initialize handshake the server actually requires, then acknowledge it. The
    /// acknowledgement is a notification and produces no response line.
    fn initialize(&mut self) -> Value {
        let response = self.request(
            "initialize",
            json!({"protocolVersion": PROTOCOL_VERSION, "capabilities": {}}),
        );
        let result = response["result"].as_object().expect("initialize result");
        assert_eq!(result["protocolVersion"], json!(PROTOCOL_VERSION));
        assert_eq!(
            result["capabilities"],
            json!({"tools": {"listChanged": false}})
        );
        assert_eq!(result["serverInfo"]["name"], json!("healthmd-mcp"));
        self.notify("notifications/initialized");
        response
    }

    fn notify(&mut self, method: &str) {
        let notification = json!({"jsonrpc": "2.0", "method": method});
        self.write_line(&notification.to_string());
    }

    fn request(&mut self, method: &str, params: Value) -> Value {
        self.next_id += 1;
        self.request_with_id(self.next_id, method, params)
    }

    #[allow(clippy::needless_pass_by_value)]
    fn request_with_id(&mut self, id: u64, method: &str, params: Value) -> Value {
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
            // Stray notifications or out-of-order completions are skipped; ids are matched.
        }
    }

    /// Call one fixed MCP tool. Every result envelope is checked for the exact non-UI shape:
    /// one text content item, `isError`, and no `structuredContent` (no UI was negotiated).
    #[allow(clippy::needless_pass_by_value)]
    fn call(&mut self, name: &str, arguments: Value) -> ToolResponse {
        let response = self.request("tools/call", json!({"name": name, "arguments": arguments}));
        if let Some(error) = response.get("error") {
            return ToolResponse::RpcError {
                code: error["code"].as_i64().expect("JSON-RPC error code"),
                message: error["message"].as_str().expect("error message").to_owned(),
            };
        }
        let result = response["result"]
            .as_object()
            .expect("tools/call result object");
        assert_eq!(
            serde_json::to_value(result.keys().collect::<Vec<_>>()).unwrap(),
            json!(["content", "isError"]),
            "{name} result envelope must carry exactly content and isError"
        );
        let content = result["content"].as_array().expect("content array");
        assert_eq!(
            content.len(),
            1,
            "{name} must return exactly one content item"
        );
        assert_eq!(content[0]["type"], json!("text"));
        let payload: Value = serde_json::from_str(content[0]["text"].as_str().expect("text"))
            .unwrap_or_else(|error| panic!("{name} text content is not JSON: {error}"));
        ToolResponse::Result {
            payload,
            is_error: result["isError"].as_bool().expect("isError"),
        }
    }

    fn write_line(&mut self, line: &str) {
        // The server speaks newline-delimited JSON; keep stdin open (closing it cancels
        // in-flight requests) and only write complete lines.
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

// ---------------------------------------------------------------------------
// Assertion helpers (expectations derived from the corpus above)
// ---------------------------------------------------------------------------

fn default_page() -> Value {
    page(250, 262_144, None)
}

fn page(max_items: usize, max_bytes: usize, cursor: Option<&str>) -> Value {
    json!({"max_items": max_items, "max_bytes": max_bytes, "cursor": cursor})
}

#[allow(clippy::needless_pass_by_value)]
fn records_arguments(detail_level: &str, page: Value) -> Value {
    json!({
        "metrics": {"type": "all_available"},
        "detail_level": detail_level,
        "page": page
    })
}

fn object_keys(value: &Value) -> BTreeSet<String> {
    value
        .as_object()
        .unwrap_or_else(|| panic!("expected an object: {value}"))
        .keys()
        .cloned()
        .collect()
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

/// The complete bulk-grant catalog, in the server's deterministic (metric, source, level)
/// ordering: one common entry per pointer-shaped daily field and one entry per granted metric
/// identity for the lossless layers. Nothing from `notes.txt` or `broken.json` appears.
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

/// Assert one record item against corpus-derived expectations. `record_id` and
/// `artifact.artifact_id` are opaque SHA-256 identities: they are checked for shape only and
/// cross-referenced by callers that reuse discovered identifiers.
#[allow(clippy::needless_pass_by_value)]
#[allow(clippy::too_many_arguments)]
fn assert_record_item(
    item: &Value,
    metric_ids: Value,
    source_id: &str,
    detail_level: &str,
    owner_date: Option<&str>,
    start_time: Option<&str>,
    end_time: Option<&str>,
    capture_status: &str,
    artifact_schema: &str,
    artifact_schema_version: u64,
    locator: Value,
    value: &Value,
) {
    assert_eq!(
        object_keys(item),
        BTreeSet::from([
            "artifact",
            "capture_status",
            "detail_level",
            "end_time",
            "inline",
            "locator",
            "metric_ids",
            "owner_date",
            "record_id",
            "source_id",
            "start_time",
            "type",
            "value",
        ])
        .into_iter()
        .map(str::to_owned)
        .collect(),
        "record item must carry exactly the contract's record fields"
    );
    assert_eq!(item["type"], json!("record"));
    assert_eq!(item["metric_ids"], metric_ids);
    assert_eq!(item["source_id"], json!(source_id));
    assert_eq!(item["detail_level"], json!(detail_level));
    assert_eq!(item["owner_date"], json!(owner_date));
    assert_eq!(item["start_time"], json!(start_time));
    assert_eq!(item["end_time"], json!(end_time));
    assert_eq!(item["capture_status"], json!(capture_status));
    assert_eq!(item["inline"], json!(true));
    assert_eq!(item["value"], *value);
    assert_eq!(item["artifact"]["schema"], json!(artifact_schema));
    assert_eq!(
        item["artifact"]["schema_version"],
        json!(artifact_schema_version)
    );
    assert_eq!(item["locator"], locator);
    let record_id = item["record_id"].as_str().expect("record_id");
    assert_eq!(record_id.len(), 64, "record_id is a hex SHA-256 digest");
    assert!(record_id.bytes().all(|byte| byte.is_ascii_hexdigit()));
}

/// Fetch a whole `healthmd_data_records` listing (single page, default bounds) for one detail
/// level under the endpoint's grant.
fn all_record_items(server: &mut StdioMcpServer, detail_level: &str) -> Vec<Value> {
    let response = server.call(
        "healthmd_data_records",
        records_arguments(detail_level, default_page()),
    );
    response.expect_success("healthmd_data_records")["items"]
        .as_array()
        .expect("records items")
        .clone()
}

fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

#[test]
fn initialize_performs_the_handshake_and_exposes_only_the_five_data_tools() {
    let corpus = Corpus::build();
    for endpoint in corpus.endpoints(&corpus.grant_bulk()) {
        let mut server = endpoint.serve();

        let initialize = server.request_with_id(
            7_777,
            "initialize",
            json!({"protocolVersion": PROTOCOL_VERSION, "capabilities": {}}),
        );
        assert_eq!(initialize["jsonrpc"], json!("2.0"));
        assert_eq!(initialize["id"], json!(7_777));
        let instructions = initialize["result"]["instructions"]
            .as_str()
            .expect("instructions");
        assert!(instructions.contains("healthmd_data_catalog"));
        assert!(!instructions.contains("pair"), "{instructions}");
        assert!(!instructions.contains("healthmd_export"), "{instructions}");

        // The initialized notification produces no response; the next request still answers.
        let tools = server.request("tools/list", json!({}));
        let tools = tools["result"]["tools"].as_array().expect("tools");
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
        for tool in tools {
            assert_eq!(
                tool.pointer("/annotations/readOnlyHint"),
                Some(&json!(true))
            );
            assert!(tool["inputSchema"].is_object(), "fixed tool schemas");
        }

        // Non-data tools are absent by name, including readiness and diagnostics.
        for name in [
            "healthmd_status",
            "healthmd_doctor",
            "healthmd_capabilities",
            "healthmd_query",
            "healthmd_pairing_start",
            "healthmd_export_files",
        ] {
            server
                .call(name, json!({}))
                .expect_rpc_error(-32_602, "Unknown tool");
        }

        // Request identifiers are never reused within one session.
        let ping = server.request_with_id(9_001, "ping", json!({}));
        assert!(ping["result"].as_object().is_some());
        let duplicate = server.request_with_id(9_001, "ping", json!({}));
        assert_eq!(duplicate.pointer("/error/code"), Some(&json!(-32_600)));
        assert_eq!(
            duplicate.pointer("/error/message"),
            Some(&json!("Duplicate request identifier"))
        );

        // Unsupported protocol versions are refused at the handshake.
        let mut rejected = endpoint.serve();
        let response = rejected.request(
            "initialize",
            json!({"protocolVersion": "1999-01-01", "capabilities": {}}),
        );
        assert_eq!(response.pointer("/error/code"), Some(&json!(-32_602)));
        assert_eq!(
            response.pointer("/error/message"),
            Some(&json!("Unsupported MCP protocol version"))
        );
    }
}

#[test]
fn catalog_reports_exact_metric_identities_sources_layers_and_coverage() {
    let corpus = Corpus::build();
    for endpoint in corpus.endpoints(&corpus.grant_bulk()) {
        let mut server = endpoint.serve();

        let catalog = server.call("healthmd_data_catalog", json!({"page": default_page()}));
        let payload = catalog.expect_success("healthmd_data_catalog");
        assert_eq!(payload["schema"], json!("healthmd.agent_query_response"));
        assert_eq!(payload["schema_version"], json!(1));
        assert_eq!(payload["operation"], json!("catalog"));
        assert_eq!(payload["next_cursor"], Value::Null);
        // Receipt hygiene: factual provenance only, exact key sets, no trend/interpretation family.
        assert_eq!(
            object_keys(&payload),
            [
                "items",
                "next_cursor",
                "operation",
                "receipt",
                "schema",
                "schema_version"
            ]
            .into_iter()
            .map(str::to_owned)
            .collect()
        );
        assert_eq!(
            payload["receipt"]["source_kind"],
            json!(endpoint.expected_source_kind())
        );
        assert_eq!(payload["receipt"]["policy_enforced"], json!(true));
        assert_eq!(payload["receipt"]["returned_items"], json!(8));
        assert_eq!(
            object_keys(&payload["receipt"]),
            [
                "index_revision",
                "policy_enforced",
                "returned_items",
                "source_kind"
            ]
            .into_iter()
            .map(str::to_owned)
            .collect()
        );
        let revision = payload["receipt"]["index_revision"]
            .as_str()
            .expect("index revision");
        assert_eq!(revision.len(), 64, "index revision is a hex SHA-256 digest");

        let items = payload["items"].as_array().expect("catalog items");
        assert_eq!(items, &expected_bulk_catalog());
    }
}

#[test]
#[allow(clippy::too_many_lines)]
fn records_are_bounded_paginated_and_detail_level_separated() {
    let corpus = Corpus::build();
    for endpoint in corpus.endpoints(&corpus.grant_bulk()) {
        let mut server = endpoint.serve();

        // Common layer: exactly the three scalar daily fields, in deterministic record order
        // (owner date, then metric identity).
        let common = all_record_items(&mut server, "common");
        assert_eq!(common.len(), 3);
        assert_record_item(
            &common[0],
            json!(["healthmd.health_data#/activity/steps"]),
            "healthmd.health_data",
            "common",
            Some("2026-03-15"),
            None,
            None,
            "complete",
            "healthmd.health_data",
            8,
            json!({"type": "json_pointer", "pointer": "/activity/steps"}),
            &json!(12_345),
        );
        assert_record_item(
            &common[1],
            json!(["healthmd.health_data#/sleep/asleep_minutes"]),
            "healthmd.health_data",
            "common",
            Some("2026-03-15"),
            None,
            None,
            "complete",
            "healthmd.health_data",
            8,
            json!({"type": "json_pointer", "pointer": "/sleep/asleep_minutes"}),
            &json!(480),
        );
        assert_record_item(
            &common[2],
            json!(["healthmd.health_data#/records/0/heart/restingHeartRate"]),
            "healthmd.health_data",
            "common",
            Some("2026-03-16"),
            None,
            None,
            "complete",
            "healthmd.health_data",
            8,
            json!({"type": "json_pointer", "pointer": "/records/0/heart/restingHeartRate"}),
            &json!(58),
        );

        // Lossless layer: five records across three artifacts, paginated with a page bound of two.
        let mut pages = Vec::new();
        let mut cursor: Option<String> = None;
        loop {
            let response = server.call(
                "healthmd_data_records",
                records_arguments("lossless", page(2, 262_144, cursor.as_deref())),
            );
            let payload = response.expect_success("healthmd_data_records");
            let items = payload["items"].as_array().expect("lossless items");
            assert!(items.len() <= 2, "page bounds must be honored: {items:?}");
            assert_eq!(payload["receipt"]["returned_items"], json!(items.len()));
            cursor = payload["next_cursor"].as_str().map(str::to_owned);
            pages.push(payload);
            if cursor.is_none() {
                break;
            }
        }
        assert_eq!(pages.len(), 3, "five lossless records page by two");
        let first = pages[0]["items"].as_array().expect("first page");
        let second = pages[1]["items"].as_array().expect("second page");
        let third = pages[2]["items"].as_array().expect("third page");
        // Deterministic order: the owner-date-less snapshot record sorts first, then 2026-03-15
        // instants (HealthKit before raw snapshot by metric identity), then the 2026-03-16 change.
        assert_eq!(
            first[0]["metric_ids"],
            json!(["healthmd.raw-snapshot#wire:heart_rate_samples"])
        );
        assert_eq!(
            first[0]["locator"],
            json!({"type": "ndjson_line", "line": 3})
        );
        assert_eq!(first[0]["owner_date"], Value::Null);
        assert_eq!(
            first[1]["metric_ids"],
            json!(["healthmd.healthkit_records#metric:heart_rate_avg"])
        );
        assert_eq!(
            first[1]["value"],
            heart_rate_avg_record(),
            "lossless values are the complete source records"
        );
        assert_eq!(
            second[0]["metric_ids"],
            json!(["healthmd.raw-snapshot#wire:steps"])
        );
        assert_eq!(
            second[1]["metric_ids"],
            json!([
                "healthmd.healthkit_records#metric:heart_rate_avg",
                "healthmd.healthkit_records#metric:heart_rate_min"
            ])
        );
        assert_eq!(
            third[0]["metric_ids"],
            json!(["healthmd.raw-changes#wire:steps"])
        );

        let mut record_ids: BTreeSet<&str> = BTreeSet::new();
        for page in &pages {
            for item in page["items"].as_array().expect("items") {
                record_ids.insert(item["record_id"].as_str().expect("record_id"));
            }
        }
        assert_eq!(
            record_ids.len(),
            5,
            "pagination yields each record exactly once"
        );

        // The all_pages traversal wraps identical pages in the bounded aggregate envelope.
        let aggregate = server.call(
            "healthmd_data_records",
            json!({
                "metrics": {"type": "all_available"},
                "detail_level": "lossless",
                "page": page(2, 262_144, None),
                "all_pages": true
            }),
        );
        let aggregate = aggregate.expect_success("healthmd_data_records");
        assert_eq!(aggregate["schema"], json!("healthmd.mcp_query_pages"));
        assert_eq!(
            object_keys(&aggregate),
            ["pages", "receipt", "schema", "schema_version"]
                .into_iter()
                .map(str::to_owned)
                .collect()
        );
        assert_eq!(aggregate["receipt"]["page_count"], json!(3));
        assert_eq!(aggregate["receipt"]["item_count"], json!(5));
        assert_eq!(aggregate["receipt"]["traversal_complete"], json!(true));
        assert_eq!(
            aggregate["pages"].as_array().map(Vec::len),
            Some(3),
            "aggregate carries the same page payloads"
        );
    }
}

#[test]
fn grant_intersection_hides_ungranted_metrics_and_multi_attributed_records() {
    let corpus = Corpus::build();

    // Narrow grant: only the steps pointer is granted; nothing else is catalog- or record-visible.
    for reference in corpus.endpoints(&corpus.grant_steps_only()) {
        let mut narrow = reference.serve();
        let catalog = narrow.call("healthmd_data_catalog", json!({"page": default_page()}));
        let payload = catalog.expect_success("healthmd_data_catalog");
        assert_eq!(
            payload["items"],
            json!([catalog_item(
                "healthmd.health_data#/activity/steps",
                "healthmd.health_data",
                "common",
                1,
                Some("2026-03-15"),
                Some("2026-03-15"),
                None,
                None,
            )]),
            "ungranted metrics are absent from the catalog"
        );
        let records = all_record_items(&mut narrow, "common");
        assert_eq!(records.len(), 1);
        assert_eq!(records[0]["value"], json!(12_345));
        assert_eq!(records[0]["locator"]["pointer"], json!("/activity/steps"));

        // Partial multi-metric attribution: the record carries two metric identities, and the grant
        // permits only one — so the record disappears from BOTH catalog and records.
        let mut partial = reference
            .with_grant(&corpus.grant_one_of_two_attributions())
            .serve();
        let catalog = partial.call("healthmd_data_catalog", json!({"page": default_page()}));
        let payload = catalog.expect_success("healthmd_data_catalog");
        assert_eq!(
            payload["items"],
            json!([catalog_item(
                "healthmd.healthkit_records#metric:heart_rate_avg",
                "healthmd.healthkit_records",
                "lossless",
                1,
                Some("2026-03-15"),
                Some("2026-03-15"),
                Some("2026-03-15T12:00:00Z"),
                Some("2026-03-15T12:00:00Z"),
            )]),
            "the multi-attributed record must not contribute to the heart_rate_avg count"
        );
        let records = all_record_items(&mut partial, "lossless");
        assert_eq!(records.len(), 1);
        assert_eq!(
            records[0]["locator"]["pointer"],
            json!("/healthkit_record_archive/records/0"),
            "only the single-attribution record is visible"
        );

        // Record reads are re-authorized per request against the serving grant.
        let mut bulk = reference.with_grant(&corpus.grant_bulk()).serve();
        let lossless = all_record_items(&mut bulk, "lossless");
        let multi = lossless
            .iter()
            .find(|item| item["metric_ids"].as_array().map(Vec::len) == Some(2))
            .expect("multi-attributed record under the bulk grant");
        let multi_id = multi["record_id"].as_str().expect("record_id").to_owned();
        partial
            .call(
                "healthmd_data_record_read",
                json!({"record_id": multi_id, "page": default_page()}),
            )
            .expect_payload_error(
                "healthmd_data_record_read",
                "healthmd_agent_record_unavailable",
            );

        // Unknown but well-formed identifiers are also unavailable, never an internal error.
        bulk.call(
            "healthmd_data_record_read",
            json!({"record_id": "0".repeat(64), "page": default_page()}),
        )
        .expect_payload_error(
            "healthmd_data_record_read",
            "healthmd_agent_record_unavailable",
        );
    }
}

#[test]
fn instant_and_owner_date_gates_are_independent() {
    let corpus = Corpus::build();

    // Exact instant gate [12:00:00Z, 12:00:02Z): keeps the two overlapping instants, drops the
    // out-of-window records AND every record without a parseable instant (including all three
    // common daily scalars and the timestamp-less raw sample record).
    for reference in corpus.endpoints(&corpus.grant_exact_instant()) {
        let mut instant = reference.serve();
        let catalog = instant.call("healthmd_data_catalog", json!({"page": default_page()}));
        let payload = catalog.expect_success("healthmd_data_catalog");
        assert_eq!(
            payload["items"],
            json!([
                catalog_item(
                    "healthmd.healthkit_records#metric:heart_rate_avg",
                    "healthmd.healthkit_records",
                    "lossless",
                    1,
                    Some("2026-03-15"),
                    Some("2026-03-15"),
                    Some("2026-03-15T12:00:00Z"),
                    Some("2026-03-15T12:00:00Z"),
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
            ]),
            "the instant gate excludes instant-less records from the catalog itself"
        );
        let records = all_record_items(&mut instant, "lossless");
        assert_eq!(records.len(), 2);
        assert_eq!(records[0]["start_time"], json!("2026-03-15T12:00:00Z"));
        assert_eq!(records[1]["start_time"], json!("2026-03-15T12:00:00Z"));
        assert_eq!(
            records[1]["locator"],
            json!({"type": "ndjson_line", "line": 2})
        );

        // Owner-date gate (2026-03-15, times unrestricted): daily scalars carry no instants yet are
        // admitted by their owner date; the 2026-03-16 envelope record is excluded.
        let mut dated = reference.with_grant(&corpus.grant_exact_date()).serve();
        let catalog = dated.call("healthmd_data_catalog", json!({"page": default_page()}));
        let payload = catalog.expect_success("healthmd_data_catalog");
        let metric_ids: Vec<&str> = payload["items"]
            .as_array()
            .expect("catalog items")
            .iter()
            .map(|item| item["metric_id"].as_str().expect("metric_id"))
            .collect();
        assert_eq!(
            metric_ids,
            [
                "healthmd.health_data#/activity/steps",
                "healthmd.health_data#/sleep/asleep_minutes",
            ]
        );
        let records = all_record_items(&mut dated, "common");
        assert_eq!(records.len(), 2);
        assert!(records.iter().all(|item| {
            item["start_time"].is_null() && item["owner_date"] == json!("2026-03-15")
        }));
    }
}

#[test]
fn record_read_chunks_oversized_records_with_exact_reassembly() {
    let corpus = Corpus::build();
    for endpoint in corpus.endpoints(&corpus.grant_bulk()) {
        let mut server = endpoint.serve();

        // Discover the oversized multi-metric record through the records tool.
        let lossless = all_record_items(&mut server, "lossless");
        let multi = lossless
            .iter()
            .find(|item| item["metric_ids"].as_array().map(Vec::len) == Some(2))
            .expect("multi-attributed record");
        let record_id = multi["record_id"].as_str().expect("record_id").to_owned();
        let expected_value = heart_rate_multi_record();
        let expected_bytes = serde_json::to_vec(&expected_value).expect("compact value bytes");
        let sha = sha256_hex(&expected_bytes);

        // max_bytes 8192 leaves ((8192 - 2048) / 4) * 3 = 4608 raw bytes per chunk.
        let first = server.call(
            "healthmd_data_record_read",
            json!({"record_id": record_id, "page": page(1, 8_192, None)}),
        );
        let first = first.expect_success("healthmd_data_record_read");
        assert_eq!(first["operation"], json!("record_read"));
        let item = &first["items"][0];
        assert_eq!(
            object_keys(item),
            [
                "byte_count",
                "complete",
                "data",
                "encoding",
                "media_type",
                "offset",
                "record_id",
                "sha256",
                "total_byte_count",
                "type",
            ]
            .into_iter()
            .map(str::to_owned)
            .collect()
        );
        assert_eq!(item["type"], json!("record_chunk"));
        assert_eq!(item["record_id"], json!(record_id));
        assert_eq!(item["offset"], json!(0));
        assert_eq!(item["byte_count"], json!(4_608));
        assert_eq!(item["total_byte_count"], json!(expected_bytes.len()));
        assert_eq!(item["complete"], json!(false));
        assert_eq!(item["media_type"], json!("application/json"));
        assert_eq!(item["encoding"], json!("base64"));
        assert_eq!(item["sha256"], json!(sha));
        let continuation = first["next_cursor"].as_str().expect("continuation cursor");

        let second = server.call(
            "healthmd_data_record_read",
            json!({"record_id": record_id, "page": page(1, 8_192, Some(continuation))}),
        );
        let second = second.expect_success("healthmd_data_record_read");
        let tail = &second["items"][0];
        assert_eq!(tail["offset"], json!(4_608));
        assert_eq!(tail["byte_count"], json!(expected_bytes.len() - 4_608));
        assert_eq!(tail["complete"], json!(true));
        assert_eq!(second["next_cursor"], Value::Null);

        let head_bytes = URL_SAFE_NO_PAD
            .decode(first["items"][0]["data"].as_str().expect("base64url data"))
            .expect("chunk one decodes");
        let tail_bytes = URL_SAFE_NO_PAD
            .decode(tail["data"].as_str().expect("base64url data"))
            .expect("chunk two decodes");
        let mut reassembled = head_bytes;
        reassembled.extend_from_slice(&tail_bytes);
        assert_eq!(reassembled, expected_bytes, "exact chunk reassembly");

        // Page and cursor misuse is rejected before any bytes are returned.
        server
            .call(
                "healthmd_data_record_read",
                json!({"record_id": record_id, "page": page(1, CHUNK_OVERHEAD_BYTES, None)}),
            )
            .expect_payload_error("healthmd_data_record_read", "healthmd_agent_page_too_small");
        server
            .call(
                "healthmd_data_record_read",
                json!({"record_id": record_id, "page": page(1, 8_192, Some("garbage"))}),
            )
            .expect_payload_error("healthmd_data_record_read", "healthmd_agent_cursor_invalid");
    }
}

#[test]
#[allow(clippy::too_many_lines)]
fn artifacts_listing_and_reads_require_the_bulk_download_grant() {
    let corpus = Corpus::build();

    // Under a record-scoped grant the listing is empty (not an error) and reads are denied.
    for reference in corpus.endpoints(&corpus.grant_steps_only()) {
        let mut narrow = reference.serve();
        let listing = narrow.call("healthmd_data_artifacts", json!({"page": default_page()}));
        let payload = listing.expect_success("healthmd_data_artifacts");
        assert_eq!(payload["operation"], json!("artifacts"));
        assert_eq!(payload["items"], json!([]));
        assert_eq!(payload["receipt"]["returned_items"], json!(0));
        narrow
            .call(
                "healthmd_data_artifact_read",
                json!({"artifact_id": "0".repeat(64), "page": default_page()}),
            )
            .expect_payload_error(
                "healthmd_data_artifact_read",
                "healthmd_agent_bulk_download_denied",
            );

        // Under the unrestricted bulk grant every valid corpus artifact is listed with exact
        // provenance; notes.txt (unsupported) and broken.json (malformed) contribute nothing.
        let mut bulk = reference.with_grant(&corpus.grant_bulk()).serve();
        let listing = bulk.call("healthmd_data_artifacts", json!({"page": default_page()}));
        let payload = listing.expect_success("healthmd_data_artifacts");
        let items = payload["items"].as_array().expect("artifact items");
        assert_eq!(items.len(), 5);
        assert_eq!(
            items
                .iter()
                .map(|item| item["record_count"].as_u64().unwrap())
                .sum::<u64>(),
            8,
            "the eight corpus records are spread across exactly five artifacts"
        );
        assert!(
            items
                .iter()
                .all(|item| item["capture_status"] == json!("complete"))
        );

        let bare_bytes = serde_json::to_vec(&bare_daily()).expect("bare bytes");
        let api_bytes = serde_json::to_vec(&api_export()).expect("api bytes");
        let lossless_bytes = serde_json::to_vec(&lossless_daily()).expect("lossless bytes");
        let snapshot_bytes = snapshot_ndjson_bytes();
        let changes_bytes = serde_json::to_vec(&raw_changes()).expect("changes bytes");

        let artifact_with = |schema: &str| {
            items
                .iter()
                .find(|item| {
                    item["schemas"]
                        .as_array()
                        .is_some_and(|schemas| schemas.iter().any(|s| s["schema"] == json!(schema)))
                })
                .unwrap_or_else(|| panic!("artifact with schema {schema}"))
                .clone()
        };
        let bare = artifact_with("healthmd.health_data");
        let api = artifact_with("healthmd.api_export");
        let lossless = artifact_with("healthmd.healthkit_records");
        let snapshot = artifact_with("healthmd.raw-snapshot");
        let changes = artifact_with("healthmd.raw-changes");

        assert_eq!(bare["media_type"], json!("application/json"));
        assert_eq!(bare["physical_format"], json!("json"));
        assert_eq!(bare["detail_levels"], json!(["common"]));
        assert_eq!(bare["record_count"], json!(1));
        assert_eq!(bare["byte_count"], json!(bare_bytes.len()));
        assert_eq!(
            api["schemas"],
            json!([
                {"schema": "healthmd.api_export", "schema_version": 2},
                {"schema": "healthmd.health_data", "schema_version": 8},
            ])
        );
        assert_eq!(api["record_count"], json!(1));
        assert_eq!(api["byte_count"], json!(api_bytes.len()));
        assert_eq!(lossless["detail_levels"], json!(["common", "lossless"]));
        assert_eq!(lossless["record_count"], json!(3));
        assert_eq!(lossless["byte_count"], json!(lossless_bytes.len()));
        assert_eq!(snapshot["media_type"], json!("application/x-ndjson"));
        assert_eq!(snapshot["physical_format"], json!("ndjson"));
        assert_eq!(snapshot["detail_levels"], json!(["lossless"]));
        assert_eq!(snapshot["record_count"], json!(2));
        assert_eq!(snapshot["byte_count"], json!(snapshot_bytes.len()));
        assert_eq!(changes["record_count"], json!(1));
        assert_eq!(changes["byte_count"], json!(changes_bytes.len()));

        // artifact_id is the SHA-256 of the stored bytes: the directory never rewrites artifacts.
        let snapshot_id = snapshot["artifact_id"].as_str().expect("artifact_id");
        assert_eq!(snapshot_id, sha256_hex(&snapshot_bytes));
        assert_eq!(lossless["artifact_id"], json!(sha256_hex(&lossless_bytes)));

        // Multi-chunk exact-byte read of the largest artifact: max_bytes 4096 bounds each chunk to
        // ((4096 - 2048) / 4) * 3 = 1536 raw bytes.
        let lossless_id = lossless["artifact_id"]
            .as_str()
            .expect("artifact_id")
            .to_owned();
        let mut offset = 0_usize;
        let mut reassembled = Vec::new();
        let mut cursor: Option<String> = None;
        let mut chunk_count = 0_usize;
        loop {
            let response = bulk.call(
                "healthmd_data_artifact_read",
                json!({"artifact_id": lossless_id, "page": page(1, 4_096, cursor.as_deref())}),
            );
            let payload = response.expect_success("healthmd_data_artifact_read");
            assert_eq!(payload["operation"], json!("artifact_read"));
            let item = &payload["items"][0];
            assert_eq!(item["type"], json!("artifact_chunk"));
            assert_eq!(item["artifact_id"], json!(lossless_id));
            assert_eq!(item["offset"], json!(offset));
            assert_eq!(item["total_byte_count"], json!(lossless_bytes.len()));
            assert_eq!(item["media_type"], json!("application/json"));
            assert_eq!(item["encoding"], json!("base64"));
            assert_eq!(
                item["sha256"],
                json!(lossless_id),
                "sha-256 echoes the artifact id"
            );
            let complete = item["complete"].as_bool().expect("complete");
            let chunk = URL_SAFE_NO_PAD
                .decode(item["data"].as_str().expect("base64url data"))
                .expect("chunk decodes");
            assert_eq!(
                chunk.len(),
                usize::try_from(item["byte_count"].as_u64().expect("byte_count"))
                    .expect("byte_count")
            );
            offset += chunk.len();
            reassembled.extend_from_slice(&chunk);
            chunk_count += 1;
            cursor = payload["next_cursor"].as_str().map(str::to_owned);
            if complete {
                assert_eq!(cursor, None, "the final chunk has no continuation");
                break;
            }
            assert!(cursor.is_some(), "incomplete chunks continue");
        }
        assert_eq!(
            chunk_count,
            lossless_bytes.len().div_ceil(1_536),
            "chunk payload bounds derive from max_bytes"
        );
        assert_eq!(
            reassembled, lossless_bytes,
            "exact artifact byte reassembly"
        );

        // A small artifact completes in a single chunk.
        let single = bulk.call(
            "healthmd_data_artifact_read",
            json!({"artifact_id": snapshot_id, "page": page(1, 4_096, None)}),
        );
        let item = &single.expect_success("healthmd_data_artifact_read")["items"][0];
        assert_eq!(item["offset"], json!(0));
        assert_eq!(item["byte_count"], json!(snapshot_bytes.len()));
        assert_eq!(item["complete"], json!(true));
        let decoded = URL_SAFE_NO_PAD
            .decode(item["data"].as_str().expect("base64url data"))
            .expect("chunk decodes");
        assert_eq!(decoded, snapshot_bytes);

        // Unknown but well-formed artifact identifiers are unavailable under a valid bulk grant.
        bulk.call(
            "healthmd_data_artifact_read",
            json!({"artifact_id": "0".repeat(64), "page": default_page()}),
        )
        .expect_payload_error(
            "healthmd_data_artifact_read",
            "healthmd_agent_artifact_unavailable",
        );
    }
}

#[test]
fn cursors_are_query_bound_and_store_instance_bound() {
    let corpus = Corpus::build();
    for endpoint in corpus.endpoints(&corpus.grant_bulk()) {
        let mut first = endpoint.serve();

        let response = first.call(
            "healthmd_data_records",
            records_arguments("lossless", page(1, 262_144, None)),
        );
        let payload = response.expect_success("healthmd_data_records");
        assert_eq!(payload["receipt"]["returned_items"], json!(1));
        let cursor = payload["next_cursor"]
            .as_str()
            .expect("a bounded first page continues")
            .to_owned();

        // The same cursor replayed against a fresh store instance on the same corpus is rejected:
        // cursors are signed with per-instance state.
        let mut second = endpoint.serve();
        second
            .call(
                "healthmd_data_records",
                records_arguments("lossless", page(1, 262_144, Some(&cursor))),
            )
            .expect_payload_error("healthmd_data_records", "healthmd_agent_cursor_invalid");

        // The same cursor under a different query fingerprint is stale, even on its own instance.
        first
            .call(
                "healthmd_data_records",
                records_arguments("lossless", page(2, 262_144, Some(&cursor))),
            )
            .expect_payload_error("healthmd_data_records", "healthmd_agent_cursor_stale");

        // Structurally invalid cursors never reach the store.
        first
            .call(
                "healthmd_data_records",
                records_arguments("lossless", page(1, 262_144, Some("garbage"))),
            )
            .expect_payload_error("healthmd_data_records", "healthmd_agent_cursor_invalid");

        // Invalid page bounds are rejected as invalid tool arguments at the JSON-RPC layer.
        first
            .call(
                "healthmd_data_catalog",
                json!({"page": page(0, 262_144, None)}),
            )
            .expect_rpc_error(-32_602, "Invalid tool arguments");
        first
            .call("healthmd_data_catalog", json!({"page": page(1, 0, None)}))
            .expect_rpc_error(-32_602, "Invalid tool arguments");
        first
            .call(
                "healthmd_data_catalog",
                json!({"metrics": {"type": "all_available"}, "page": default_page()}),
            )
            .expect_rpc_error(-32_602, "Invalid tool arguments");
    }
}

#[test]
fn unsupported_and_malformed_corpus_files_are_never_queryable() {
    let corpus = Corpus::build();
    for endpoint in corpus.endpoints(&corpus.grant_bulk()) {
        let mut server = endpoint.serve();

        // With every selection unrestricted, the catalog still contains exactly the eight identities
        // produced by the five recognized artifacts: notes.txt and broken.json contribute nothing.
        let catalog = server.call("healthmd_data_catalog", json!({"page": default_page()}));
        let payload = catalog.expect_success("healthmd_data_catalog");
        let discovered: BTreeSet<String> = payload["items"]
            .as_array()
            .expect("catalog items")
            .iter()
            .map(|item| item["metric_id"].as_str().expect("metric_id").to_owned())
            .collect();
        let expected: BTreeSet<String> = expected_bulk_catalog()
            .into_iter()
            .map(|item| item["metric_id"].as_str().expect("metric_id").to_owned())
            .collect();
        assert_eq!(discovered, expected);

        // Full traversal of both detail levels yields exactly the eight indexed records.
        let mut record_ids = BTreeSet::new();
        for detail_level in ["common", "lossless"] {
            let aggregate = server.call(
                "healthmd_data_records",
                json!({
                    "metrics": {"type": "all_available"},
                    "detail_level": detail_level,
                    "page": page(3, 262_144, None),
                    "all_pages": true
                }),
            );
            let aggregate = aggregate.expect_success("healthmd_data_records");
            for page in aggregate["pages"].as_array().expect("pages") {
                for item in page["items"].as_array().expect("items") {
                    record_ids.insert(item["record_id"].as_str().expect("record_id").to_owned());
                }
            }
        }
        assert_eq!(record_ids.len(), 8);

        // Malformed-file diagnostics live in `doctor`, which this data-only surface deliberately
        // omits (asserted by the fixed-surface test); the artifacts test asserts the five-artifact,
        // eight-record accounting that excludes the ignored and invalid files.
    }
}

#[test]
fn serve_data_rejects_a_grant_inside_the_store_backing() {
    let corpus = Corpus::build();
    for endpoint in corpus.endpoints(&corpus.grant_bulk()) {
        match endpoint.misplaced_grant() {
            MisplacedGrant::Refused { path, reason } => {
                // Each local store refuses a grant stored inside its own private backing
                // before serving any data: the directory store rejects export-directory
                // grants, the database store a grant that is the database file itself.
                write_json(
                    &path,
                    &grant(
                        all_available(),
                        all_available(),
                        all_available(),
                        all_available(),
                        json!(["common", "lossless"]),
                        true,
                    ),
                );
                let output = Command::new(env!("CARGO_BIN_EXE_healthmd"))
                    .args(endpoint.argv_with_grant(&path))
                    .stdin(Stdio::null())
                    .output()
                    .expect("healthmd should launch");
                assert!(
                    !output.status.success(),
                    "a grant inside the store's private backing must be refused"
                );
                assert!(
                    output.stdout.is_empty(),
                    "no machine-readable payload on refusal"
                );
                let stderr = String::from_utf8_lossy(&output.stderr);
                assert!(
                    stderr.contains(reason),
                    "stderr should explain the boundary: {stderr}"
                );
            }
            MisplacedGrant::IgnoredBucketContent => {
                // The object store is the documented asymmetry: there is no local containment
                // rule against a remote backing. The corpus's grant-shaped bucket object is
                // ignored content — counted, never loaded as a grant — so serving under the
                // local grant succeeds, exposes exactly the indexed corpus, and refuses
                // nothing. The double must meanwhile have observed only verified read-only
                // list/head/get traffic for all of it.
                let mut server = endpoint.serve();
                let catalog = server.call("healthmd_data_catalog", json!({"page": default_page()}));
                let payload = catalog.expect_success("healthmd_data_catalog");
                assert_eq!(
                    payload["receipt"]["source_kind"],
                    json!(endpoint.expected_source_kind())
                );
                assert_eq!(payload["receipt"]["returned_items"], json!(8));
                let discovered: BTreeSet<String> = payload["items"]
                    .as_array()
                    .expect("catalog items")
                    .iter()
                    .map(|item| item["metric_id"].as_str().expect("metric_id").to_owned())
                    .collect();
                let expected: BTreeSet<String> = expected_bulk_catalog()
                    .into_iter()
                    .map(|item| item["metric_id"].as_str().expect("metric_id").to_owned())
                    .collect();
                assert_eq!(
                    discovered, expected,
                    "the grant-shaped bucket object must contribute nothing"
                );
                endpoint.assert_double_clean("misplaced-grant asymmetry");
            }
        }
    }
}
