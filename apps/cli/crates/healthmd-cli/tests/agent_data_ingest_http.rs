//! End-to-end coverage for the self-hosted reference ingestion gateway:
//! the public `healthmd data ingest-serve` command driving the real binary
//! with a std-only HTTP/1.1 client over real loopback TCP sockets.
//!
//! The scenarios mirror the frozen gateway transport mapping documented in
//! `apps/cli/docs/agent-data.md` (and, normatively, the Agent Data v1
//! contract): one `POST /v1/ingest` request carries one `\n`-terminated
//! `healthmd.agent_data_ingest` v1 manifest line followed immediately by the
//! exact artifact bytes; every validated outcome answers HTTP 200 with the
//! same `healthmd.agent_ingest_response` v1 receipt `healthmd data ingest`
//! prints; transport-level failures answer health-free code+message JSON;
//! a connection that closes before the full declared body arrives observes
//! a connection close with NO receipt.
//!
//! Harness facts (observed, frozen): the listener binds only after the
//! listener policy validates and the store opens and migrates, the gateway
//! serves plain HTTP/1.1 with `Connection: close` per request, and the
//! Host/Origin gate rejects unconfigured values with `403 Forbidden` before
//! any request logic runs — mirroring the loopback Streamable HTTP data
//! surface. Each scenario probes fixed high-numbered loopback port
//! candidates with a std listener before claiming one, and every spawned
//! child is killed deterministically on drop.

use std::{
    fmt::Write as _,
    io::{BufRead as _, BufReader, Read as _, Write as _},
    net::{Shutdown, TcpListener, TcpStream},
    path::PathBuf,
    process::{Child, Command, Output, Stdio},
    thread,
    time::Duration,
};

use serde_json::{Value, json};
use tempfile::TempDir;

const RESPONSE_TIMEOUT: Duration = Duration::from_secs(30);
const STARTUP_TIMEOUT: Duration = Duration::from_secs(30);
const INGEST_MEDIA_TYPE: &str = "application/x-healthmd-agent-data-ingest";

/// Synthetic complete daily export for owner date 2026-03-15 (mirrors the
/// local `data ingest` e2e corpus).
const COMPLETE_DAY: &str = r#"{"schema":"healthmd.health_data","schema_version":8,"date":"2026-03-15","type":"health-data","raw_capture_status":"complete","unit_system":"metric","units":{},"activity":{"steps":12345},"heart":{"restingHeartRate":58}}"#;

// ---------------------------------------------------------------------------
// Layout, manifest construction, digests
// ---------------------------------------------------------------------------

struct Layout {
    root: TempDir,
}

impl Layout {
    fn new() -> Self {
        Self {
            root: tempfile::tempdir().expect("temporary root"),
        }
    }

    fn database(&self) -> PathBuf {
        self.root.path().join("agent-data.sqlite")
    }

    fn grant(&self) -> PathBuf {
        let path = self.root.path().join("grant.json");
        std::fs::write(
            &path,
            serde_json::to_string(&json!({
                "schema": "healthmd.agent_data_grant",
                "schema_version": 1,
                "metrics": {"type": "all_available"},
                "sources": {"type": "all_available"},
                "dates": {"type": "all_available"},
                "times": {"type": "all_available"},
                "detail_levels": ["common", "lossless"],
                "bulk_download": true
            }))
            .expect("grant JSON"),
        )
        .expect("grant write");
        path
    }
}

fn digest_of(contents: &[u8]) -> String {
    use sha2::{Digest as _, Sha256};
    let digest = Sha256::digest(contents);
    let mut text = String::with_capacity(64);
    for byte in digest {
        use std::fmt::Write as _;
        let _ = write!(text, "{byte:02x}");
    }
    text
}

/// One inline synthetic `healthmd.agent_data_ingest` v1 manifest.
fn manifest_for(contents: &[u8], completeness: &Value, overrides: &[(&str, Value)]) -> Vec<u8> {
    let mut value = json!({
        "schema": "healthmd.agent_data_ingest",
        "schema_version": 1,
        "artifact_kind": "health_data_daily",
        "platform": "apple",
        "artifact_schema": "healthmd.health_data",
        "artifact_schema_version": 8,
        "owner_date": "2026-03-15",
        "physical_format": "json",
        "media_type": "application/json",
        "byte_count": contents.len(),
        "sha256": digest_of(contents),
        "completeness": completeness.clone()
    });
    for (key, replacement) in overrides {
        value
            .as_object_mut()
            .expect("manifest object")
            .insert((*key).to_owned(), replacement.clone());
    }
    let mut line = serde_json::to_vec(&value).expect("manifest JSON");
    line.push(b'\n');
    line
}

fn complete() -> Value {
    json!({"type": "complete"})
}

/// Frame one gateway request body: the manifest line plus the artifact bytes.
fn frame(manifest_line: &[u8], artifact: &[u8]) -> Vec<u8> {
    let mut body = manifest_line.to_vec();
    body.extend_from_slice(artifact);
    body
}

// ---------------------------------------------------------------------------
// Std-only loopback HTTP/1.1 client (fresh `Connection: close` per request)
// ---------------------------------------------------------------------------

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

    fn transport_error_code(&self) -> String {
        self.json()["code"]
            .as_str()
            .unwrap_or_else(|| panic!("transport error body carries a code: {:?}", self.body))
            .to_owned()
    }
}

/// Issue one request on a fresh connection with an exact `Content-Length`
/// body. `host` overrides the `Host` header value and `headers` appends
/// extra headers for validation checks.
#[allow(clippy::too_many_arguments)]
fn send(
    port: u16,
    method: &str,
    path: &str,
    host: &str,
    content_type: Option<&str>,
    extra_headers: &[(&str, &str)],
    body: &[u8],
    declared_length: Option<usize>,
) -> HttpResponse {
    let mut stream = connect(port);
    stream
        .set_read_timeout(Some(RESPONSE_TIMEOUT))
        .expect("read timeout");
    stream
        .set_write_timeout(Some(RESPONSE_TIMEOUT))
        .expect("write timeout");
    let mut request = format!("{method} {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n");
    if let Some(content_type) = content_type {
        request.push_str("Content-Type: ");
        request.push_str(content_type);
        request.push_str("\r\n");
    }
    let length = declared_length.unwrap_or(body.len());
    let _ = write!(request, "Content-Length: {length}\r\n");
    for (name, value) in extra_headers {
        let _ = write!(request, "{name}: {value}\r\n");
    }
    request.push_str("\r\n");
    stream
        .write_all(request.as_bytes())
        .expect("write HTTP request");
    stream.write_all(body).expect("write HTTP body");
    stream.flush().expect("flush HTTP request");
    read_response(&mut stream)
}

fn connect(port: u16) -> TcpStream {
    TcpStream::connect(("127.0.0.1", port)).expect("connect to the ingestion gateway")
}

/// Read and parse one complete `Content-Length`-framed HTTP/1.1 response.
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
    let text = String::from_utf8_lossy(&raw[..header_end]).into_owned();
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
    let length = headers
        .iter()
        .find(|(name, _)| name == "content-length")
        .map(|(_, value)| {
            value
                .parse::<usize>()
                .unwrap_or_else(|_| panic!("invalid content length: {value}"))
        })
        .unwrap_or_default();
    while body.len() < length {
        let read = stream.read(&mut chunk).expect("read body");
        assert!(read > 0, "connection closed inside the body");
        body.extend_from_slice(&chunk[..read]);
    }
    body.truncate(length);
    HttpResponse {
        status,
        headers,
        body,
    }
}

fn find_header_end(raw: &[u8]) -> Option<usize> {
    raw.windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|position| position + 4)
}

/// One framed ingestion POST with the documented media type.
fn post_ingest(port: u16, manifest_line: &[u8], artifact: &[u8]) -> HttpResponse {
    let body = frame(manifest_line, artifact);
    send(
        port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{port}"),
        Some(INGEST_MEDIA_TYPE),
        &[],
        &body,
        None,
    )
}

fn sorted_keys(value: &Value) -> Vec<String> {
    let mut keys: Vec<String> = value.as_object().expect("object").keys().cloned().collect();
    keys.sort();
    keys
}

fn assert_partition_grammar(partition: &Value) {
    assert_eq!(
        sorted_keys(partition),
        [
            "authoritative",
            "complete_revision_present",
            "owner_date",
            "partial_revision_present"
        ]
    );
    assert_eq!(
        sorted_keys(&partition["authoritative"]),
        ["completeness", "revision_id"]
    );
}

// ---------------------------------------------------------------------------
// Server supervision
// ---------------------------------------------------------------------------

struct GatewayServer {
    child: Child,
    port: u16,
}

impl GatewayServer {
    /// Spawn the shipped binary, claiming one of the fixed candidate ports.
    ///
    /// The gateway takes a fixed bind address, so each scenario probes its own
    /// pair of high-numbered loopback ports with a std listener; a candidate
    /// is claimed only after its listener answers, and a candidate held by a
    /// sibling run falls through to the alternate.
    fn spawn(layout: &Layout, ports: [u16; 2], extra_args: &[&str]) -> Self {
        let mut arguments: Vec<String> = vec![
            "data".into(),
            "ingest-serve".into(),
            "--database".into(),
            layout.database().to_string_lossy().into_owned(),
            "--bind".into(),
            format!("127.0.0.1:{}", ports[0]),
        ];
        for argument in extra_args {
            arguments.push((*argument).to_owned());
        }
        for port in ports {
            if TcpListener::bind(("127.0.0.1", port)).is_err() {
                continue;
            }
            // Replace the --bind value with this candidate.
            if let Some(position) = arguments.iter().position(|value| value == "--bind") {
                arguments[position + 1] = format!("127.0.0.1:{port}");
            }
            let mut child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
                .args(&arguments)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .expect("healthmd data ingest-serve should launch");
            if wait_for_listener(&mut child, port) {
                return Self { child, port };
            }
            let _ = child.kill();
            let _ = child.wait();
        }
        panic!("no loopback candidate port answered; attempted {ports:?}");
    }

    /// Spawn on the documented default bind (127.0.0.1:8791).
    fn spawn_default_bind(layout: &Layout) -> Self {
        const DEFAULT_PORT: u16 = 8_791;
        let claim = TcpListener::bind(("127.0.0.1", DEFAULT_PORT))
            .expect("the default gateway port must be claimable for this scenario");
        drop(claim);
        let mut child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
            .args(["data", "ingest-serve", "--database"])
            .arg(layout.database())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("healthmd data ingest-serve should launch");
        assert!(
            wait_for_listener(&mut child, DEFAULT_PORT),
            "the gateway must bind its documented default 127.0.0.1:8791"
        );
        Self {
            child,
            port: DEFAULT_PORT,
        }
    }
}

impl Drop for GatewayServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Wait until the port accepts a connection or the child exits. The listener
/// binds only after the listener policy validates and the store opens, so an
/// accepting socket means a ready gateway.
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

/// One newline-delimited JSON-RPC exchange with a `serve-data` stdio server
/// (promotion proof, mirroring the cycle-2 e2e).
struct StdioSession {
    child: Child,
}

impl StdioSession {
    fn start(layout: &Layout) -> Self {
        let child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
            .args(["mcp", "serve-data", "--database"])
            .arg(layout.database())
            .arg("--grant")
            .arg(layout.grant())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("serve-data should launch");
        Self { child }
    }

    fn request(&mut self, request: &Value) -> Value {
        let payload = serde_json::to_string(request).expect("request JSON");
        let stdin = self.child.stdin.as_mut().expect("stdin");
        stdin.write_all(payload.as_bytes()).expect("stdin write");
        stdin.write_all(b"\n").expect("stdin newline");
        stdin.flush().expect("stdin flush");
        let stdout = self.child.stdout.as_mut().expect("stdout");
        let mut line = String::new();
        let mut reader = BufReader::new(stdout);
        loop {
            line.clear();
            let count = reader.read_line(&mut line).expect("stdout read");
            assert!(count > 0, "server closed before responding to {payload}");
            if let Ok(response) = serde_json::from_str::<Value>(line.trim()) {
                if response.get("id") == request.get("id") {
                    return response;
                }
            }
        }
    }

    fn initialize(&mut self) {
        let response = self.request(&json!({
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": {"protocolVersion": "2025-11-25", "capabilities": {}}
        }));
        assert_eq!(response["jsonrpc"], "2.0", "initialize should succeed");
    }

    fn listed_artifact_count(&mut self, id: i64) -> usize {
        let response = self.request(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": {"name": "healthmd_data_artifacts", "arguments": {}}
        }));
        let text = response
            .pointer("/result/content/0/text")
            .and_then(Value::as_str)
            .expect("tool text payload");
        let payload: Value = serde_json::from_str(text).expect("tool payload JSON");
        payload["items"].as_array().expect("items").len()
    }
}

impl Drop for StdioSession {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn run(arguments: &[String]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(arguments)
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch")
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

#[test]
fn accepted_upload_matches_the_receipt_fixture_grammar_and_is_servable() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_311, 48_313], &[]);

    // A declared record count that disagrees with the artifact bytes is
    // still accepted: record_count is strictly informational in v1.
    let manifest = manifest_for(
        COMPLETE_DAY.as_bytes(),
        &complete(),
        &[("record_count", json!(999))],
    );
    let response = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200, "accepted outcome is HTTP 200");
    assert_eq!(
        response.header("content-type").unwrap_or_default(),
        "application/json"
    );
    let receipt = response.json();
    assert_eq!(receipt["schema"], "healthmd.agent_ingest_response");
    assert_eq!(receipt["schema_version"], 1);
    assert_eq!(receipt["outcome"], "accepted");
    assert_eq!(
        sorted_keys(&receipt),
        ["outcome", "partition", "schema", "schema_version", "stored"]
    );
    assert_eq!(
        sorted_keys(&receipt["stored"]),
        ["byte_count", "completeness", "revision_id"]
    );
    assert_eq!(
        receipt["stored"]["revision_id"],
        digest_of(COMPLETE_DAY.as_bytes())
    );
    assert_eq!(receipt["stored"]["byte_count"], COMPLETE_DAY.len() as u64);
    assert_eq!(
        receipt["stored"]["completeness"],
        json!({"type": "complete"})
    );
    assert_partition_grammar(&receipt["partition"]);
    assert_eq!(receipt["partition"]["owner_date"], "2026-03-15");
    assert_eq!(receipt["partition"]["complete_revision_present"], true);
    assert_eq!(receipt["partition"]["partial_revision_present"], false);

    // Promotion proof: the ingested artifact is immediately servable through
    // the data surface, exactly like a local `data ingest` promotion.
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(session.listed_artifact_count(1), 1);
}

#[test]
fn identical_reupload_returns_a_byte_identical_receipt_without_duplicates() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_321, 48_323], &[]);
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]);

    let first = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(first.status, 200);
    let second = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(second.status, 200);
    assert_eq!(
        first.body, second.body,
        "identical manifest+bytes must produce a byte-identical receipt"
    );

    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(
        session.listed_artifact_count(1),
        1,
        "no duplicate rows from the idempotent re-upload"
    );
}

#[test]
fn integrity_rejections_are_protocol_outcomes_over_http_200() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_331, 48_333], &[]);
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]);

    // Seed the partition so rejections can carry its current view.
    let seeded = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(seeded.status, 200);

    // truncated: the artifact bytes are shorter than the declared byte_count.
    let mut truncated_value: Value =
        serde_json::from_slice(&manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]))
            .expect("manifest");
    truncated_value
        .as_object_mut()
        .unwrap()
        .insert("byte_count".into(), json!(COMPLETE_DAY.len() + 5));
    let mut truncated_line = serde_json::to_vec(&truncated_value).expect("manifest JSON");
    truncated_line.push(b'\n');
    let response = post_ingest(server.port, &truncated_line, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200, "rejections are never HTTP errors");
    let receipt = response.json();
    assert_eq!(receipt["outcome"], "rejected");
    assert_eq!(receipt["rejection"], json!({"code": "truncated"}));
    assert_eq!(
        sorted_keys(&receipt),
        [
            "outcome",
            "partition",
            "rejection",
            "schema",
            "schema_version"
        ]
    );
    assert_eq!(
        receipt["partition"]["authoritative"]["revision_id"],
        digest_of(COMPLETE_DAY.as_bytes())
    );

    // checksum_invalid: correct length, wrong digest.
    let mut checksum_value = truncated_value.clone();
    checksum_value
        .as_object_mut()
        .unwrap()
        .insert("byte_count".into(), json!(COMPLETE_DAY.len()));
    checksum_value
        .as_object_mut()
        .unwrap()
        .insert("sha256".into(), json!("1".repeat(64)));
    let mut checksum_line = serde_json::to_vec(&checksum_value).expect("manifest JSON");
    checksum_line.push(b'\n');
    let response = post_ingest(server.port, &checksum_line, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200);
    assert_eq!(
        response.json()["rejection"],
        json!({"code": "checksum_invalid"})
    );

    // Rejections never mutate the store.
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(session.listed_artifact_count(1), 1);
}

#[test]
fn manifest_incomplete_covers_malformed_json_and_unknown_fields() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_341, 48_343], &[]);

    // Malformed JSON manifest line.
    let response = post_ingest(server.port, b"{not json\n", COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200);
    let receipt = response.json();
    assert_eq!(receipt["outcome"], "rejected");
    assert_eq!(receipt["rejection"], json!({"code": "manifest_incomplete"}));
    assert_eq!(
        sorted_keys(&receipt),
        ["outcome", "rejection", "schema", "schema_version"]
    );

    // Unknown field (schema-invalid manifest document).
    let manifest = manifest_for(
        COMPLETE_DAY.as_bytes(),
        &complete(),
        &[("extra", json!(null))],
    );
    let response = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200);
    assert_eq!(
        response.json()["rejection"],
        json!({"code": "manifest_incomplete"})
    );

    // An unterminated manifest line (no newline within the bound) is also an
    // unidentifiable manifest.
    let mut unterminated = manifest.clone();
    unterminated.pop();
    let body = frame(&unterminated, COMPLETE_DAY.as_bytes());
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        Some(INGEST_MEDIA_TYPE),
        &[],
        &body,
        None,
    );
    assert_eq!(response.status, 200);
    assert_eq!(
        response.json()["rejection"],
        json!({"code": "manifest_incomplete"})
    );
}

#[test]
fn unfinalized_partial_is_transient_over_http_and_manifest_incomplete_locally() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_351, 48_353], &[]);
    let unfinalized = json!({
        "type": "partial", "finalized": false,
        "covered_owner_dates": ["2026-03-15"]
    });
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &unfinalized, &[]);

    // Gateway reading: unfinalized = retryable transient, HTTP 200 receipt.
    let response = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200);
    let receipt = response.json();
    assert_eq!(receipt["outcome"], "rejected");
    assert_eq!(receipt["rejection"], json!({"code": "transient"}));

    // Local reading stays byte-identical to cycle 2: the same manifest file
    // is manifest_incomplete under `healthmd data ingest`.
    let manifest_path = layout.root.path().join("manifest.json");
    let artifact_path = layout.root.path().join("day.json");
    std::fs::write(&manifest_path, &manifest).expect("manifest write");
    std::fs::write(&artifact_path, COMPLETE_DAY).expect("artifact write");
    let output = run(&[
        "data".into(),
        "ingest".into(),
        "--database".into(),
        layout.database().to_string_lossy().into_owned(),
        "--manifest".into(),
        manifest_path.to_string_lossy().into_owned(),
        "--artifact".into(),
        artifact_path.to_string_lossy().into_owned(),
    ]);
    assert!(output.status.success(), "local ingest still exits 0");
    let local: Value = serde_json::from_slice(&output.stdout).expect("local receipt");
    assert_eq!(
        local["rejection"],
        json!({"code": "manifest_incomplete"}),
        "the documented surface divergence: local class stays cycle-2"
    );

    // Neither surface stored anything.
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(session.listed_artifact_count(1), 0);
}

#[test]
fn premature_body_close_is_a_client_connection_error_without_a_receipt() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_361, 48_363], &[]);
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]);
    let body = frame(&manifest, COMPLETE_DAY.as_bytes());

    // Send the head plus only part of the declared body, then close the
    // writing side: the server must simply close with NO receipt.
    let mut stream = connect(server.port);
    stream
        .set_read_timeout(Some(RESPONSE_TIMEOUT))
        .expect("read timeout");
    let head = format!(
        "POST /v1/ingest HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nContent-Type: {INGEST_MEDIA_TYPE}\r\n\
         Connection: close\r\nContent-Length: {}\r\n\r\n",
        server.port,
        body.len()
    );
    stream.write_all(head.as_bytes()).expect("write head");
    stream
        .write_all(&body[..body.len() / 2])
        .expect("write partial body");
    stream.flush().expect("flush partial upload");
    stream.shutdown(Shutdown::Write).expect("close write side");
    let mut received = Vec::new();
    let read = stream.read_to_end(&mut received).expect("read to close");
    assert_eq!(
        read, 0,
        "the client observes a connection close, not a receipt"
    );
    assert!(
        received.is_empty(),
        "no bytes of any receipt or error may arrive: {received:?}"
    );

    // The store holds nothing from the abandoned upload.
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(session.listed_artifact_count(1), 0);
}

#[test]
fn transport_errors_are_health_free_code_message_json() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_371, 48_373], &[]);

    // 413: the declared body exceeds the 64 MiB + 64 KiB bound. The bound is
    // checked before the body is read, so no oversized payload is sent.
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        Some(INGEST_MEDIA_TYPE),
        &[],
        b"",
        Some(67_174_401),
    );
    assert_eq!(response.status, 413);
    assert_eq!(response.transport_error_code(), "payload_too_large");

    // 404: unknown path.
    let response = send(
        server.port,
        "POST",
        "/v1/other",
        &format!("127.0.0.1:{}", server.port),
        Some(INGEST_MEDIA_TYPE),
        &[],
        b"",
        None,
    );
    assert_eq!(response.status, 404);
    assert_eq!(response.transport_error_code(), "not_found");

    // 405: wrong method.
    let response = send(
        server.port,
        "GET",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        None,
        &[],
        b"",
        None,
    );
    assert_eq!(response.status, 405);
    assert_eq!(response.transport_error_code(), "method_not_allowed");

    // 415: wrong media type, and a missing media type.
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        Some("application/json"),
        &[],
        b"{}\n",
        None,
    );
    assert_eq!(response.status, 415);
    assert_eq!(response.transport_error_code(), "unsupported_media_type");
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        None,
        &[],
        b"{}\n",
        None,
    );
    assert_eq!(response.status, 415);
    assert_eq!(response.transport_error_code(), "unsupported_media_type");

    // 400: chunked transfer encoding is rejected in v1.
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        Some(INGEST_MEDIA_TYPE),
        &[("Transfer-Encoding", "chunked")],
        b"",
        None,
    );
    assert_eq!(response.status, 400);
    assert_eq!(
        response.transport_error_code(),
        "chunked_encoding_unsupported"
    );

    // 400: malformed request line.
    let mut stream = connect(server.port);
    stream
        .set_read_timeout(Some(RESPONSE_TIMEOUT))
        .expect("read timeout");
    stream
        .write_all(b"GARBAGE\r\n\r\n")
        .expect("write malformed request");
    let response = read_response(&mut stream);
    assert_eq!(response.status, 400);
    assert_eq!(response.transport_error_code(), "bad_request");

    // Every transport error body is health-free and path-free.
    let encoded = String::from_utf8_lossy(&response.body).into_owned();
    assert!(encoded.contains("\"code\"") && encoded.contains("\"message\""));

    // The server keeps serving after transport errors.
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]);
    let response = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200);
    assert_eq!(response.json()["outcome"], "accepted");
}

#[test]
fn host_and_origin_validation_is_enforced_before_request_logic() {
    let layout = Layout::new();
    let server = GatewayServer::spawn(&layout, [48_381, 48_383], &[]);
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]);
    let body = frame(&manifest, COMPLETE_DAY.as_bytes());

    // An unconfigured Host is refused with 403 and no body.
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        "untrusted.example",
        Some(INGEST_MEDIA_TYPE),
        &[],
        &body,
        None,
    );
    assert_eq!(response.status, 403, "unconfigured Host must be rejected");
    assert!(response.body.is_empty(), "no body leaks past validation");

    // An unconfigured browser Origin is refused the same way.
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        Some(INGEST_MEDIA_TYPE),
        &[("Origin", "https://untrusted.example")],
        &body,
        None,
    );
    assert_eq!(response.status, 403, "unconfigured Origin must be rejected");
    assert!(response.body.is_empty());

    // The gateway survives and the next well-formed request still answers.
    let response = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200);
    assert_eq!(response.json()["outcome"], "accepted");
}

#[test]
fn allowlisted_origin_is_accepted() {
    let layout = Layout::new();
    // Explicit --bind plus an allowlisted loopback Origin.
    let origin = "http://127.0.0.1:48393";
    let server = GatewayServer::spawn(&layout, [48_391, 48_393], &["--allowed-origin", origin]);
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]);
    let body = frame(&manifest, COMPLETE_DAY.as_bytes());
    let response = send(
        server.port,
        "POST",
        "/v1/ingest",
        &format!("127.0.0.1:{}", server.port),
        Some(INGEST_MEDIA_TYPE),
        &[("Origin", origin)],
        &body,
        None,
    );
    assert_eq!(response.status, 200, "the allowlisted Origin is accepted");
    assert_eq!(response.json()["outcome"], "accepted");
}

#[test]
fn the_default_bind_is_loopback_8791() {
    let layout = Layout::new();
    let server = GatewayServer::spawn_default_bind(&layout);
    let manifest = manifest_for(COMPLETE_DAY.as_bytes(), &complete(), &[]);
    let response = post_ingest(server.port, &manifest, COMPLETE_DAY.as_bytes());
    assert_eq!(response.status, 200);
    assert_eq!(response.json()["outcome"], "accepted");
}

#[test]
fn absolute_database_paths_are_enforced_with_health_free_errors() {
    let output = run(&[
        "data".into(),
        "ingest-serve".into(),
        "--database".into(),
        "relative.sqlite".into(),
    ]);
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("the Agent Data database path must be absolute"),
        "health-free stable error, got: {stderr}"
    );
    assert!(!stderr.contains("relative.sqlite"));
}
