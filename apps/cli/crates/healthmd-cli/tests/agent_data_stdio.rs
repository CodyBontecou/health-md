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
//! Store-parity kit: the corpus builder and every scenario helper are parameterized by
//! [`StoreEndpoint`], which currently emits the directory store's `--directory/--grant/--index`
//! argv. When the `SQLite` store lands, add its argv (`--database ...`) to [`StoreEndpoint`] and
//! re-run these scenarios unchanged against it; the planned Cloudflare store follows the same
//! seam. Keep new scenarios parameterized by endpoint, never by global state.
//!
//! Harness facts (observed, frozen): the server speaks one JSON document per `\n`-terminated
//! line, echoes the negotiated MCP protocol version, ignores notifications, rejects duplicate
//! request identifiers with `-32600`, and cancels in-flight requests when stdin closes, so the
//! child's stdin stays open for the life of each server handle.

use std::{
    collections::BTreeSet,
    io::{BufRead as _, Write as _},
    path::PathBuf,
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{Receiver, channel},
    },
    thread,
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
        Self { root }
    }

    fn exports(&self) -> PathBuf {
        self.root.path().join("exports")
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

    /// One store endpoint configuration for the parity kit. Today this is the directory store;
    /// later stores add their own argv here and reuse the same scenarios.
    fn endpoint(&self, grant: &std::path::Path) -> StoreEndpoint {
        let sequence = INDEX_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        StoreEndpoint {
            directory: self.exports(),
            grant: grant.to_path_buf(),
            index: self
                .root
                .path()
                .join("indexes")
                .join(format!("index-{sequence}.json")),
        }
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
// Store endpoint and stdio JSON-RPC client
// ---------------------------------------------------------------------------

/// Configuration for one Agent Data store under test. The directory store is the v1 shape; later
/// stores (`SQLite` `--database`, Cloudflare) extend this with their own connection arguments so the
/// same scenario functions re-run unchanged.
#[derive(Clone, Debug)]
struct StoreEndpoint {
    directory: PathBuf,
    grant: PathBuf,
    index: PathBuf,
}

impl StoreEndpoint {
    fn argv(&self) -> Vec<String> {
        vec![
            "mcp".to_owned(),
            "serve-data".to_owned(),
            "--directory".to_owned(),
            self.directory.to_string_lossy().into_owned(),
            "--grant".to_owned(),
            self.grant.to_string_lossy().into_owned(),
            "--index".to_owned(),
            self.index.to_string_lossy().into_owned(),
        ]
    }

    /// Spawn the shipped binary with piped stdio and perform the initialize handshake.
    fn serve(&self) -> StdioMcpServer {
        StdioMcpServer::spawn(&self.argv())
    }
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
    fn spawn(argv: &[String]) -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
            .args(argv)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
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
    let digest = Sha256::digest(bytes);
    let mut value = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write as _;
        let _ = write!(value, "{byte:02x}");
    }
    value
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

#[test]
fn initialize_performs_the_handshake_and_exposes_only_the_five_data_tools() {
    let corpus = Corpus::build();
    let endpoint = corpus.endpoint(&corpus.grant_bulk());
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

#[test]
fn catalog_reports_exact_metric_identities_sources_layers_and_coverage() {
    let corpus = Corpus::build();
    let mut server = corpus.endpoint(&corpus.grant_bulk()).serve();

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
    assert_eq!(payload["receipt"]["source_kind"], json!("directory"));
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

#[test]
#[allow(clippy::too_many_lines)]
fn records_are_bounded_paginated_and_detail_level_separated() {
    let corpus = Corpus::build();
    let mut server = corpus.endpoint(&corpus.grant_bulk()).serve();

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

#[test]
fn grant_intersection_hides_ungranted_metrics_and_multi_attributed_records() {
    let corpus = Corpus::build();

    // Narrow grant: only the steps pointer is granted; nothing else is catalog- or record-visible.
    let mut narrow = corpus.endpoint(&corpus.grant_steps_only()).serve();
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
    let mut partial = corpus
        .endpoint(&corpus.grant_one_of_two_attributions())
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
    let mut bulk = corpus.endpoint(&corpus.grant_bulk()).serve();
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

#[test]
fn instant_and_owner_date_gates_are_independent() {
    let corpus = Corpus::build();

    // Exact instant gate [12:00:00Z, 12:00:02Z): keeps the two overlapping instants, drops the
    // out-of-window records AND every record without a parseable instant (including all three
    // common daily scalars and the timestamp-less raw sample record).
    let mut instant = corpus.endpoint(&corpus.grant_exact_instant()).serve();
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
    let mut dated = corpus.endpoint(&corpus.grant_exact_date()).serve();
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
    assert!(
        records.iter().all(|item| {
            item["start_time"].is_null() && item["owner_date"] == json!("2026-03-15")
        })
    );
}

#[test]
fn record_read_chunks_oversized_records_with_exact_reassembly() {
    let corpus = Corpus::build();
    let mut server = corpus.endpoint(&corpus.grant_bulk()).serve();

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

#[test]
#[allow(clippy::too_many_lines)]
fn artifacts_listing_and_reads_require_the_bulk_download_grant() {
    let corpus = Corpus::build();

    // Under a record-scoped grant the listing is empty (not an error) and reads are denied.
    let mut narrow = corpus.endpoint(&corpus.grant_steps_only()).serve();
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
    let mut bulk = corpus.endpoint(&corpus.grant_bulk()).serve();
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
            usize::try_from(item["byte_count"].as_u64().expect("byte_count")).expect("byte_count")
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

#[test]
fn cursors_are_query_bound_and_store_instance_bound() {
    let corpus = Corpus::build();
    let endpoint = corpus.endpoint(&corpus.grant_bulk());
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

#[test]
fn unsupported_and_malformed_corpus_files_are_never_queryable() {
    let corpus = Corpus::build();
    let mut server = corpus.endpoint(&corpus.grant_bulk()).serve();

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

#[test]
fn serve_data_rejects_a_grant_inside_the_export_directory() {
    let corpus = Corpus::build();
    let inside = corpus.exports().join("inside-grant.json");
    write_json(
        &inside,
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
        .args(["mcp", "serve-data", "--directory"])
        .arg(corpus.exports())
        .arg("--grant")
        .arg(&inside)
        .arg("--index")
        .arg(corpus.root.path().join("indexes").join("rejected.json"))
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch");
    assert!(
        !output.status.success(),
        "a grant inside the export directory must be refused"
    );
    assert!(
        output.stdout.is_empty(),
        "no machine-readable payload on refusal"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("outside the export directory"),
        "stderr should explain the boundary: {stderr}"
    );
}
