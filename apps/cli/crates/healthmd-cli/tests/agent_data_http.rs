//! End-to-end loopback Streamable HTTP harness for the Health.md Agent Data MCP surface.
//!
//! These tests spawn the *shipped* `healthmd` binary
//! (`mcp serve-data --transport streamable-http`) and drive it with a std-only HTTP/1.1 client
//! over a real loopback TCP socket. The synthetic corpus and every expectation are derived from
//! the normative v1 contract (`packages/contracts/agent-data/v1/contract.md`,
//! `apps/cli/docs/agent-data.md`) and deliberately mirror `tests/agent_data_stdio.rs`: the
//! five-tool catalog, bounded queries, grant denials, and chunk reassembly must be identical
//! over both transports, because the surface reuses the transport the direct `serve-http`
//! command already serves on.
//!
//! Harness facts (observed, frozen): the listener binds only after the store and grant validate,
//! initialize returns the session in an `mcp-session-id` response header, subsequent requests
//! must echo the negotiated protocol version in `mcp-protocol-version`, notifications are
//! answered with `202 Accepted`, and the Host/Origin middleware rejects unconfigured values
//! with `403 Forbidden` before any session logic runs. The transport takes a fixed bind
//! address, so each scenario uses a fixed high-numbered loopback port with one alternate
//! candidate to tolerate sibling-parallel runs.

#![cfg(feature = "streamable-http")]

use std::{
    fmt::Write as _,
    io::{Read as _, Write as _},
    net::TcpStream,
    path::PathBuf,
    process::{Child, Command, Stdio},
    thread,
    time::Duration,
};

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use serde_json::{Value, json};
use tempfile::TempDir;

const PROTOCOL_VERSION: &str = "2025-11-25";
const RESPONSE_TIMEOUT: Duration = Duration::from_secs(30);
const STARTUP_TIMEOUT: Duration = Duration::from_secs(30);
/// `CURSOR_RESPONSE_OVERHEAD_BYTES`: pages at or below this bound cannot carry a data chunk.
const CHUNK_OVERHEAD_BYTES: usize = 2_048;

// ---------------------------------------------------------------------------
// Corpus (mirrors tests/agent_data_stdio.rs; expectations derive from it)
// ---------------------------------------------------------------------------

struct Corpus {
    root: TempDir,
}

impl Corpus {
    fn build() -> Self {
        let root = TempDir::new().expect("temporary corpus root");
        let exports = root.path().join("exports");
        std::fs::create_dir(&exports).expect("export directory");
        write_json(&exports.join("bare.json"), &bare_daily());
        write_json(&exports.join("api-export.json"), &api_export());
        write_json(&exports.join("lossless.json"), &lossless_daily());
        std::fs::write(exports.join("raw-snapshot.ndjson"), snapshot_ndjson_bytes())
            .expect("raw snapshot artifact");
        write_json(&exports.join("raw-changes.json"), &raw_changes());
        std::fs::create_dir(root.path().join("grants")).expect("grant directory");
        std::fs::create_dir(root.path().join("indexes")).expect("index directory");
        Self { root }
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
                &all_available(),
                &all_available(),
                &all_available(),
                &all_available(),
                &json!(["common", "lossless"]),
                true,
            ),
        )
    }

    /// Narrow record-level grant: only the bare daily's steps pointer, common level, no bulk.
    fn grant_steps_only(&self) -> PathBuf {
        self.write_grant(
            "steps-only.json",
            &grant(
                &json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
                &all_available(),
                &all_available(),
                &all_available(),
                &json!(["common"]),
                false,
            ),
        )
    }
}

fn all_available() -> Value {
    json!({"type": "all_available"})
}

#[allow(clippy::too_many_arguments)]
fn grant(
    metrics: &Value,
    sources: &Value,
    dates: &Value,
    times: &Value,
    detail_levels: &Value,
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

/// `HealthKit` archive record attributed to TWO metrics, with a payload large enough to force
/// chunked `healthmd_data_record_read` reassembly.
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
/// ordering; identical to the stdio harness expectation for the same corpus.
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
// Std-only loopback HTTP/1.1 client
// ---------------------------------------------------------------------------

/// One parsed HTTP/1.1 response. Only the small profile the MCP transport emits is supported:
/// `Content-Length`-framed bodies, optional chunked transfer decoding, and connection close.
struct HttpResponse {
    status: u16,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

impl HttpResponse {
    fn header(&self, name: &str) -> Option<&str> {
        let lower = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(key, _)| *key == lower)
            .map(|(_, value)| value.as_str())
    }

    fn json(&self) -> Value {
        serde_json::from_slice(&self.body)
            .unwrap_or_else(|error| panic!("body is not JSON ({error}): {:?}", self.body))
    }
}

struct RawHttp {
    port: u16,
}

impl RawHttp {
    /// Issue one request on a fresh connection (`Connection: close`), framed by an exact
    /// `Content-Length` body. `host` overrides the `Host` header value for validation checks.
    fn post(
        &self,
        host: &str,
        path: &str,
        body: &str,
        extra_headers: &[(&str, &str)],
    ) -> HttpResponse {
        let mut stream = connect(self.port);
        stream
            .set_read_timeout(Some(RESPONSE_TIMEOUT))
            .expect("read timeout");
        stream
            .set_write_timeout(Some(RESPONSE_TIMEOUT))
            .expect("write timeout");
        let mut request = format!(
            "POST {path} HTTP/1.1\r\nHost: {host}\r\nContent-Type: application/json\r\n\
             Accept: application/json, text/event-stream\r\nConnection: close\r\n\
             Content-Length: {}\r\n",
            body.len()
        );
        for (name, value) in extra_headers {
            let _ = write!(request, "{name}: {value}\r\n");
        }
        request.push_str("\r\n");
        request.push_str(body);
        stream
            .write_all(request.as_bytes())
            .expect("write HTTP request");
        stream.flush().expect("flush HTTP request");
        read_response(&mut stream)
    }
}

fn connect(port: u16) -> TcpStream {
    TcpStream::connect(("127.0.0.1", port)).expect("connect to the loopback MCP listener")
}

/// Read and parse one complete HTTP/1.1 response from the socket.
fn read_response(stream: &mut TcpStream) -> HttpResponse {
    let mut raw = Vec::new();
    let mut chunk = [0_u8; 8_192];
    let header_end = loop {
        if let Some(position) = find_header_end(&raw) {
            break position;
        }
        let read = stream.read(&mut chunk).expect("read HTTP response");
        assert!(read > 0, "connection closed before a complete response");
        raw.extend_from_slice(&chunk[..read]);
    };
    let header_bytes = raw[..header_end].to_vec();
    let text = String::from_utf8_lossy(&header_bytes);
    let mut lines = text.split("\r\n");
    let status_line = lines.next().expect("status line");
    let status = status_line
        .split_ascii_whitespace()
        .nth(1)
        .and_then(|code| code.parse::<u16>().ok())
        .unwrap_or_else(|| panic!("malformed status line: {status_line}"));
    let headers: Vec<(String, String)> = lines
        .filter(|line| !line.is_empty())
        .map(|line| {
            let (name, value) = line.split_once(':').expect("header line");
            (name.trim().to_ascii_lowercase(), value.trim().to_owned())
        })
        .collect();
    let mut body = raw[header_end..].to_vec();
    let header = |name: &str| {
        headers
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.clone())
    };
    if header("transfer-encoding")
        .is_some_and(|value| value.to_ascii_lowercase().contains("chunked"))
    {
        while !chunked_body_complete(&body) {
            let read = stream.read(&mut chunk).expect("read chunked body");
            assert!(read > 0, "connection closed inside a chunked body");
            body.extend_from_slice(&chunk[..read]);
        }
        body = decode_chunked_body(&body);
    } else if let Some(length) = header("content-length").map(|value| {
        value
            .parse::<usize>()
            .unwrap_or_else(|_| panic!("invalid content length: {value}"))
    }) {
        while body.len() < length {
            let read = stream.read(&mut chunk).expect("read body");
            assert!(read > 0, "connection closed inside the body");
            body.extend_from_slice(&chunk[..read]);
        }
        body.truncate(length);
    } else {
        loop {
            let read = match stream.read(&mut chunk) {
                Ok(0) | Err(_) => break,
                Ok(read) => read,
            };
            body.extend_from_slice(&chunk[..read]);
        }
    }
    HttpResponse {
        status,
        headers,
        body,
    }
}

/// Locate the end of the header block (the blank line after the headers).
fn find_header_end(raw: &[u8]) -> Option<usize> {
    raw.windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|position| position + 4)
}

fn chunked_body_complete(body: &[u8]) -> bool {
    try_decode_chunked(body).is_ok()
}

fn decode_chunked_body(body: &[u8]) -> Vec<u8> {
    match try_decode_chunked(body) {
        Ok(bytes) => bytes,
        Err(()) => panic!("chunked body terminated mid-chunk: {body:?}"),
    }
}

fn try_decode_chunked(body: &[u8]) -> Result<Vec<u8>, ()> {
    let mut decoded = Vec::new();
    let mut cursor = 0_usize;
    loop {
        let line_end = body[cursor..]
            .windows(2)
            .position(|window| window == b"\r\n")
            .map(|position| cursor + position)
            .ok_or(())?;
        let size_text = std::str::from_utf8(&body[cursor..line_end]).map_err(|_| ())?;
        let size_text = size_text.split(';').next().unwrap_or_default().trim();
        let size = usize::from_str_radix(size_text, 16).map_err(|_| ())?;
        cursor = line_end + 2;
        if size == 0 {
            return Ok(decoded);
        }
        let end = cursor.checked_add(size).ok_or(())?;
        if body.len() < end + 2 {
            return Err(());
        }
        decoded.extend_from_slice(&body[cursor..end]);
        cursor = end + 2;
    }
}

// ---------------------------------------------------------------------------
// MCP-over-HTTP session and server supervision
// ---------------------------------------------------------------------------

struct HttpMcpServer {
    child: Child,
    port: u16,
    session: Option<String>,
    next_id: u64,
}

impl HttpMcpServer {
    /// Spawn the shipped binary over `streamable-http` on one of the fixed candidate ports.
    ///
    /// The shared transport takes a fixed bind address and does not surface the bound port, so
    /// each caller probes its own pair of high-numbered loopback ports; a candidate is claimed
    /// only after its listener answers, and a candidate held by a sibling run falls through to
    /// the alternate. The index lands outside the corpus so both candidates may be attempted.
    fn spawn(corpus: &Corpus, grant: &std::path::Path, ports: [u16; 2]) -> Self {
        let mut attempts = Vec::new();
        for (attempt, port) in ports.iter().enumerate() {
            if std::net::TcpListener::bind(("127.0.0.1", *port)).is_err() {
                continue;
            }
            let index = corpus
                .root
                .path()
                .join("indexes")
                .join(format!("http-index-{port}-{attempt}.json"));
            let mut child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
                .args([
                    "mcp",
                    "serve-data",
                    "--serve-transport",
                    "streamable-http",
                    "--bind",
                    &format!("127.0.0.1:{port}"),
                    "--directory",
                ])
                .arg(corpus.root.path().join("exports"))
                .arg("--grant")
                .arg(grant)
                .arg("--index")
                .arg(&index)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .expect("healthmd mcp serve-data should launch");
            if wait_for_listener(&mut child, *port) {
                return Self {
                    child,
                    port: *port,
                    session: None,
                    next_id: 0,
                };
            }
            let _ = child.kill();
            let _ = child.wait();
            attempts.push(*port);
        }
        panic!(
            "no loopback candidate port answered; attempted {attempts:?} of {ports:?}"
        );
    }

    fn raw(&self) -> RawHttp {
        RawHttp { port: self.port }
    }

    /// Perform the initialize handshake the transport requires, capturing the session header.
    fn initialize(&mut self) -> Value {
        let response = self.raw().post(
            &format!("127.0.0.1:{}", self.port),
            "/mcp",
            &json!({
                "jsonrpc": "2.0",
                "id": self.allocate_id(),
                "method": "initialize",
                "params": {"protocolVersion": PROTOCOL_VERSION, "capabilities": {}}
            })
            .to_string(),
            &[],
        );
        assert_eq!(response.status, 200, "initialize must succeed: {:?}", response.body);
        let session = response
            .header("mcp-session-id")
            .expect("initialize returns mcp-session-id")
            .to_owned();
        let result = response.json();
        self.session = Some(session);
        self.notify("notifications/initialized");
        result
    }

    /// Send a notification; the transport answers `202 Accepted` with no body.
    fn notify(&mut self, method: &str) {
        let mut extra = Vec::new();
        if let Some(session) = &self.session {
            extra.push(("mcp-session-id", session.as_str()));
            extra.push(("mcp-protocol-version", PROTOCOL_VERSION));
        }
        let response = self.raw().post(
            &format!("127.0.0.1:{}", self.port),
            "/mcp",
            &json!({"jsonrpc": "2.0", "method": method}).to_string(),
            &extra,
        );
        assert_eq!(response.status, 202, "notification must be accepted");
        assert!(response.body.is_empty(), "notifications carry no body");
    }

    fn request(&mut self, method: &str, params: &Value) -> HttpResponse {
        self.next_id += 1;
        let id = self.next_id;
        self.request_body(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        }))
    }

    fn request_body(&mut self, body: &Value) -> HttpResponse {
        let mut extra = Vec::new();
        if let Some(session) = &self.session {
            extra.push(("mcp-session-id", session.as_str()));
            extra.push(("mcp-protocol-version", PROTOCOL_VERSION));
        }
        let response = self.raw().post(
            &format!("127.0.0.1:{}", self.port),
            "/mcp",
            &body.to_string(),
            &extra,
        );
        assert_eq!(response.status, 200, "request must succeed: {:?}", response.body);
        response
    }

    /// Post an arbitrary JSON-RPC document with a custom `Host` (validation checks).
    fn post_with_host(&self, host: &str, body: &Value) -> HttpResponse {
        let mut extra = Vec::new();
        if let Some(session) = &self.session {
            extra.push(("mcp-session-id", session.as_str()));
        }
        self.raw()
            .post(host, "/mcp", &body.to_string(), &extra)
    }

    /// Call one fixed MCP tool and return its text payload plus `isError`.
    fn call(&mut self, name: &str, arguments: &Value) -> (Value, bool) {
        let response = self.request(
            "tools/call",
            &json!({"name": name, "arguments": arguments}),
        );
        let value = response.json();
        assert_eq!(value["jsonrpc"], json!("2.0"), "JSON-RPC 2.0 envelope");
        let result = value["result"].as_object().expect("tools/call result");
        assert_eq!(
            serde_json::to_value(result.keys().collect::<Vec<_>>()).unwrap(),
            json!(["content", "isError"]),
            "{name} result envelope must carry exactly content and isError"
        );
        let content = result["content"].as_array().expect("content array");
        assert_eq!(content.len(), 1, "{name} returns exactly one content item");
        assert_eq!(content[0]["type"], json!("text"));
        let payload: Value = serde_json::from_str(content[0]["text"].as_str().expect("text"))
            .unwrap_or_else(|error| panic!("{name} text content is not JSON: {error}"));
        (payload, result["isError"].as_bool().expect("isError"))
    }

    fn allocate_id(&mut self) -> u64 {
        self.next_id += 1;
        self.next_id
    }
}

impl Drop for HttpMcpServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Wait until the port accepts a connection or the child exits. The transport binds only after
/// the store, grant, and listener policy validate, so an accepting socket means a ready server.
fn wait_for_listener(child: &mut Child, port: u16) -> bool {
    let deadline = std::time::Instant::now() + STARTUP_TIMEOUT;
    loop {
        if let Ok(Some(_)) = child.try_wait() {
            return false;
        }
        if TcpStream::connect_timeout(
            &std::net::SocketAddr::from(([127, 0, 0, 1], port)),
            Duration::from_millis(500),
        )
        .is_ok()
        {
            return true;
        }
        if std::time::Instant::now() >= deadline {
            return false;
        }
        thread::sleep(Duration::from_millis(100));
    }
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

#[test]
fn http_initialize_performs_the_handshake_and_exposes_only_the_five_data_tools() {
    let corpus = Corpus::build();
    let mut server = HttpMcpServer::spawn(&corpus, &corpus.grant_bulk(), [48_191, 48_193]);

    let initialize = server.initialize();
    let result = initialize["result"].as_object().expect("initialize result");
    assert_eq!(result["protocolVersion"], json!(PROTOCOL_VERSION));
    assert_eq!(result["capabilities"], json!({"tools": {"listChanged": false}}));
    assert_eq!(result["serverInfo"]["name"], json!("healthmd-mcp"));
    let instructions = result["instructions"].as_str().expect("instructions");
    assert!(instructions.contains("healthmd_data_catalog"));
    assert!(!instructions.contains("pair"), "{instructions}");

    // Exact frozen five-tool catalog, in the server's fixed order.
    let tools = server.request("tools/list", &json!({}));
    let tools = tools.json()["result"]["tools"]
        .as_array()
        .expect("tools")
        .clone();
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
    assert!(tools.iter().all(|tool| {
        tool.pointer("/annotations/readOnlyHint") == Some(&json!(true))
            && tool["inputSchema"].is_object()
    }));

    // No fallback between the direct and data surfaces over HTTP either.
    let unknown = server.request(
        "tools/call",
        &json!({"name": "healthmd_status", "arguments": {}}),
    );
    let unknown = unknown.json();
    assert_eq!(unknown.pointer("/error/code"), Some(&json!(-32_602)));
    assert_eq!(unknown.pointer("/error/message"), Some(&json!("Unknown tool")));

    // One bounded query against the synthetic corpus: the exact bulk catalog, identical to the
    // stdio expectation for the same corpus and grant.
    let (catalog, is_error) = server.call("healthmd_data_catalog", &json!({"page": default_page()}));
    assert!(!is_error, "catalog query: {catalog}");
    assert_eq!(catalog["schema"], json!("healthmd.agent_query_response"));
    assert_eq!(catalog["schema_version"], json!(1));
    assert_eq!(catalog["operation"], json!("catalog"));
    assert_eq!(catalog["next_cursor"], Value::Null);
    assert_eq!(catalog["receipt"]["source_kind"], json!("directory"));
    assert_eq!(catalog["receipt"]["policy_enforced"], json!(true));
    assert_eq!(catalog["receipt"]["returned_items"], json!(8));
    assert_eq!(
        catalog["items"].as_array().expect("catalog items"),
        &expected_bulk_catalog(),
        "the HTTP catalog must equal the stdio catalog byte-for-byte in meaning"
    );
}

#[test]
fn http_record_read_chunks_oversized_records_with_exact_reassembly() {
    let corpus = Corpus::build();
    let mut server = HttpMcpServer::spawn(&corpus, &corpus.grant_bulk(), [48_221, 48_223]);
    server.initialize();

    // Discover the oversized multi-metric record through the records tool.
    let (records, is_error) = server.call(
        "healthmd_data_records",
        &json!({
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

    // max_bytes 8192 leaves ((8192 - 2048) / 4) * 3 = 4608 raw bytes per chunk.
    let (first, is_error) = server.call(
        "healthmd_data_record_read",
        &json!({"record_id": record_id, "page": page(1, 8_192, None)}),
    );
    assert!(!is_error, "record read: {first}");
    assert_eq!(first["operation"], json!("record_read"));
    let item = &first["items"][0];
    assert_eq!(item["type"], json!("record_chunk"));
    assert_eq!(item["record_id"], json!(record_id));
    assert_eq!(item["offset"], json!(0));
    assert_eq!(item["byte_count"], json!(4_608));
    assert_eq!(item["encoding"], json!("base64"));
    assert_eq!(item["complete"], json!(false));
    let continuation = first["next_cursor"].as_str().expect("continuation cursor");

    let expected_bytes =
        serde_json::to_vec(&heart_rate_multi_record()).expect("compact value bytes");

    let (tail, is_error) = server.call(
        "healthmd_data_record_read",
        &json!({"record_id": record_id, "page": page(1, 8_192, Some(continuation))}),
    );
    assert!(!is_error, "tail read: {tail}");
    let tail_item = &tail["items"][0];
    assert_eq!(tail_item["offset"], json!(4_608));
    assert_eq!(
        tail_item["byte_count"],
        json!(expected_bytes.len() - 4_608)
    );
    assert_eq!(tail_item["complete"], json!(true));
    assert_eq!(tail["next_cursor"], Value::Null);

    let head_bytes = URL_SAFE_NO_PAD
        .decode(first["items"][0]["data"].as_str().expect("base64url data"))
        .expect("chunk one decodes");
    let tail_bytes = URL_SAFE_NO_PAD
        .decode(tail_item["data"].as_str().expect("base64url data"))
        .expect("chunk two decodes");
    let mut reassembled = head_bytes;
    reassembled.extend_from_slice(&tail_bytes);
    assert_eq!(reassembled, expected_bytes, "exact chunk reassembly");

    // Page misuse is rejected before any bytes are returned, identical to stdio.
    let (rejected, is_error) = server.call(
        "healthmd_data_record_read",
        &json!({"record_id": record_id, "page": page(1, CHUNK_OVERHEAD_BYTES, None)}),
    );
    assert!(is_error, "undersized page: {rejected}");
    assert_eq!(
        rejected["error"],
        json!("healthmd_agent_page_too_small")
    );
}

#[test]
fn http_grant_denial_and_host_origin_validation_are_enforced() {
    let corpus = Corpus::build();
    let mut server = HttpMcpServer::spawn(&corpus, &corpus.grant_steps_only(), [48_251, 48_253]);
    server.initialize();

    // Under a record-scoped grant the artifact listing is empty and reads are denied.
    let (listing, is_error) = server.call("healthmd_data_artifacts", &json!({"page": default_page()}));
    assert!(!is_error, "artifact listing: {listing}");
    assert_eq!(listing["operation"], json!("artifacts"));
    assert_eq!(listing["items"], json!([]));
    assert_eq!(listing["receipt"]["returned_items"], json!(0));
    let (denied, is_error) = server.call(
        "healthmd_data_artifact_read",
        &json!({"artifact_id": "0".repeat(64), "page": default_page()}),
    );
    assert!(is_error, "artifact read must be denied: {denied}");
    assert_eq!(
        denied["error"],
        json!("healthmd_agent_bulk_download_denied"),
        "grant-denied tool result over HTTP"
    );

    // Host/Origin validation runs before any session logic: an unconfigured Host or browser
    // Origin is refused with 403 and no JSON-RPC body.
    let body = json!({
        "jsonrpc": "2.0",
        "id": 401,
        "method": "tools/list",
        "params": {}
    });
    let bad_host = server.post_with_host("untrusted.example", &body);
    assert_eq!(bad_host.status, 403, "unconfigured Host must be rejected");
    assert!(bad_host.body.is_empty(), "no body leaks past validation");
    let bad_origin = server.raw().post(
        &format!("127.0.0.1:{}", server.port),
        "/mcp",
        &body.to_string(),
        &[("origin", "https://untrusted.example")],
    );
    assert_eq!(bad_origin.status, 403, "unconfigured Origin must be rejected");
    assert!(bad_origin.body.is_empty());
    // The session survives; the next well-formed request still answers.
    let after = server.request("tools/list", &json!({}));
    assert_eq!(after.json()["result"]["tools"].as_array().map(Vec::len), Some(5));
}
