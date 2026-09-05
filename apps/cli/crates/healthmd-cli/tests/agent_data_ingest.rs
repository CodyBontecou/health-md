//! End-to-end coverage for the local Agent Data ingestion protocol v1 half:
//! the public `healthmd data ingest` command driving the real binary against
//! the SQLite store, using only synthetic artifacts. Receipts are asserted
//! against the grammar of the versioned contract fixtures in
//! `packages/contracts/agent-data/v1/fixtures/`.

use std::{
    io::{BufRead as _, BufReader, Write as _},
    path::PathBuf,
    process::{Child, Command, Output, Stdio},
};

use serde_json::{Value, json};

/// Synthetic complete daily export for owner date 2026-03-15.
const COMPLETE_DAY: &str = r#"{"schema":"healthmd.health_data","schema_version":8,"date":"2026-03-15","type":"health-data","raw_capture_status":"complete","unit_system":"metric","units":{},"activity":{"steps":12345},"heart":{"restingHeartRate":58}}"#;
/// SHA-256 of [`COMPLETE_DAY`] (exact bytes, no trailing newline).
const COMPLETE_DAY_SHA256: &str =
    "ec7589e331d296726fc4380133db7cf7469a0f5979fca947c59e41dd9f20fe83";
/// Synthetic finalized partial daily export for the same owner date.
const PARTIAL_DAY: &str = r#"{"schema":"healthmd.health_data","schema_version":8,"date":"2026-03-15","type":"health-data","raw_capture_status":"partial","unit_system":"metric","units":{},"activity":{"steps":9999}}"#;
/// SHA-256 of [`PARTIAL_DAY`].
const PARTIAL_DAY_SHA256: &str =
    "755f2eaea025776e4239a28c802de28f2db13b2c9d27a2494b9ad562eba4cfe3";

struct Layout {
    root: tempfile::TempDir,
}

impl Layout {
    fn new() -> Self {
        let root = tempfile::tempdir().expect("temporary root");
        std::fs::create_dir(root.path().join("uploads")).expect("uploads directory");
        Self { root }
    }

    fn database(&self) -> PathBuf {
        self.root.path().join("agent-data.sqlite")
    }

    fn uploads(&self) -> PathBuf {
        self.root.path().join("uploads")
    }

    fn upload(&self, name: &str, contents: &str) -> PathBuf {
        let path = self.uploads().join(name);
        std::fs::write(&path, contents).expect("upload write");
        path
    }

    fn grant(&self) -> PathBuf {
        let path = self.root.path().join("grant.json");
        std::fs::write(
            &path,
            &serde_json::to_string(&grant()).expect("grant JSON"),
        )
        .expect("grant write");
        path
    }
}

fn grant() -> Value {
    json!({
        "schema": "healthmd.agent_data_grant",
        "schema_version": 1,
        "metrics": {"type": "all_available"},
        "sources": {"type": "all_available"},
        "dates": {"type": "all_available"},
        "times": {"type": "all_available"},
        "detail_levels": ["common", "lossless"],
        "bulk_download": true
    })
}

fn manifest(contents_sha256: &str, byte_count: usize, completeness: Value) -> String {
    serde_json::to_string(&json!({
        "schema": "healthmd.agent_data_ingest",
        "schema_version": 1,
        "artifact_kind": "health_data_daily",
        "platform": "apple",
        "artifact_schema": "healthmd.health_data",
        "artifact_schema_version": 8,
        "owner_date": "2026-03-15",
        "physical_format": "json",
        "media_type": "application/json",
        "byte_count": byte_count,
        "sha256": contents_sha256,
        "completeness": completeness
    }))
    .expect("manifest JSON")
}

fn complete_manifest_for(contents: &str) -> String {
    manifest(&digest(contents), contents.len(), json!({"type": "complete"}))
}

fn partial_manifest_for(contents: &str) -> String {
    manifest(
        &digest(contents),
        contents.len(),
        json!({"type": "partial", "finalized": true, "covered_owner_dates": ["2026-03-15"]}),
    )
}

/// Digests are fixed constants for the two artifacts above; any other content
/// only needs a syntactically valid digest for the negative paths.
fn digest(contents: &str) -> String {
    match contents {
        COMPLETE_DAY => COMPLETE_DAY_SHA256.to_owned(),
        PARTIAL_DAY => PARTIAL_DAY_SHA256.to_owned(),
        _ => "0".repeat(64),
    }
}

fn run(arguments: &[String]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(arguments)
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch")
}

fn ingest(layout: &Layout, manifest: &str, artifact: &std::path::Path) -> Output {
    let manifest_path = layout.uploads().join("manifest.json");
    std::fs::write(&manifest_path, manifest).expect("manifest write");
    run(&[
        "data".into(),
        "ingest".into(),
        "--database".into(),
        layout.database().to_string_lossy().into_owned(),
        "--manifest".into(),
        manifest_path.to_string_lossy().into_owned(),
        "--artifact".into(),
        artifact.to_string_lossy().into_owned(),
    ])
}

fn json_output(output: &Output) -> Value {
    assert!(
        output.status.success(),
        "command should exit 0 with a receipt, got {:?}: {}",
        output.status.code(),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty(), "no stderr expected");
    serde_json::from_slice(&output.stdout).expect("stdout should contain one JSON document")
}

fn sorted_keys(value: &Value) -> Vec<String> {
    let mut keys: Vec<String> = value
        .as_object()
        .expect("object")
        .keys()
        .cloned()
        .collect();
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

/// One newline-delimited JSON-RPC exchange with a `serve-data` stdio server.
struct StdioSession {
    child: Child,
}

impl StdioSession {
    fn start(layout: &Layout) -> Self {
        let child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
            .args([
                "mcp",
                "serve-data",
                "--database",
            ])
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

    fn call(&mut self, id: i64, tool: &str, arguments: Value) -> Value {
        self.request(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": {"name": tool, "arguments": arguments}
        }))
    }
}

impl Drop for StdioSession {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn listed_artifact_count(session: &mut StdioSession, id: i64) -> usize {
    let response = session.call(id, "healthmd_data_artifacts", json!({}));
    let text = response
        .pointer("/result/content/0/text")
        .and_then(Value::as_str)
        .expect("tool text payload");
    let payload: Value = serde_json::from_str(text).expect("tool payload JSON");
    payload["items"].as_array().expect("items").len()
}

#[test]
fn accepted_complete_upload_matches_the_receipt_fixture_grammar() {
    let layout = Layout::new();
    let artifact = layout.upload("day.json", COMPLETE_DAY);
    let output = ingest(&layout, &complete_manifest_for(COMPLETE_DAY), &artifact);
    let receipt = json_output(&output);

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
    assert_eq!(receipt["stored"]["revision_id"], COMPLETE_DAY_SHA256);
    assert_eq!(receipt["stored"]["byte_count"], COMPLETE_DAY.len() as u64);
    assert_eq!(receipt["stored"]["completeness"], json!({"type": "complete"}));
    let partition = &receipt["partition"];
    assert_partition_grammar(partition);
    assert_eq!(partition["owner_date"], "2026-03-15");
    assert_eq!(partition["complete_revision_present"], true);
    assert_eq!(partition["partial_revision_present"], false);
    assert_eq!(
        partition["authoritative"],
        json!({
            "revision_id": COMPLETE_DAY_SHA256,
            "completeness": {"type": "complete"}
        })
    );

    // The ingested artifact is immediately servable through the data surface.
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(listed_artifact_count(&mut session, 1), 1);
}

#[test]
fn accepted_partial_is_authoritative_until_shadowed_by_a_complete_revision() {
    let layout = Layout::new();

    // The finalized partial arrives first and is authoritative with explicit
    // partial status and covered owner dates.
    let partial_artifact = layout.upload("partial.json", PARTIAL_DAY);
    let receipt = json_output(&ingest(
        &layout,
        &partial_manifest_for(PARTIAL_DAY),
        &partial_artifact,
    ));
    assert_eq!(receipt["outcome"], "accepted");
    assert_eq!(
        receipt["stored"]["completeness"],
        json!({"type": "partial", "finalized": true, "covered_owner_dates": ["2026-03-15"]})
    );
    assert_eq!(receipt["partition"]["complete_revision_present"], false);
    assert_eq!(receipt["partition"]["partial_revision_present"], true);
    assert_eq!(receipt["partition"]["authoritative"]["revision_id"], PARTIAL_DAY_SHA256);
    assert_eq!(
        receipt["partition"]["authoritative"]["completeness"],
        json!({"type": "partial", "finalized": true, "covered_owner_dates": ["2026-03-15"]})
    );

    // A complete revision for the same partition flips authority and the old
    // partial stays stored.
    let complete_artifact = layout.upload("complete.json", COMPLETE_DAY);
    let receipt = json_output(&ingest(
        &layout,
        &complete_manifest_for(COMPLETE_DAY),
        &complete_artifact,
    ));
    assert_eq!(receipt["outcome"], "accepted");
    assert_eq!(receipt["stored"]["revision_id"], COMPLETE_DAY_SHA256);
    assert_partition_grammar(&receipt["partition"]);
    assert_eq!(receipt["partition"]["complete_revision_present"], true);
    assert_eq!(receipt["partition"]["partial_revision_present"], true);
    assert_eq!(
        receipt["partition"]["authoritative"],
        json!({
            "revision_id": COMPLETE_DAY_SHA256,
            "completeness": {"type": "complete"}
        }),
        "the complete revision must be authoritative"
    );

    // Non-destructive: both revisions remain stored and servable.
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(
        listed_artifact_count(&mut session, 1),
        2,
        "nothing was deleted; the shadowed partial stays stored"
    );

    // A later partial for the same partition never displaces the complete one.
    let later_partial = COMPLETE_DAY.replacen("12345", "77777", 1);
    let later_artifact = layout.upload("later-partial.json", &later_partial);
    let later_manifest = manifest(
        &digest_of(&later_partial),
        later_partial.len(),
        json!({"type": "partial", "finalized": true, "covered_owner_dates": ["2026-03-15"]}),
    );
    let receipt = json_output(&ingest(&layout, &later_manifest, &later_artifact));
    assert_eq!(receipt["outcome"], "accepted");
    assert_eq!(
        receipt["partition"]["authoritative"]["completeness"],
        json!({"type": "complete"}),
        "a partial never displaces a complete revision"
    );
}

fn digest_of(contents: &str) -> String {
    use sha2::{Digest as _, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(contents.as_bytes());
    let digest = hasher.finalize();
    let mut text = String::with_capacity(64);
    for byte in digest {
        use std::fmt::Write as _;
        let _ = write!(text, "{byte:02x}");
    }
    text
}

#[test]
fn rejected_uploads_return_the_four_stable_codes_with_grammar_receipts() {
    let layout = Layout::new();
    let artifact = layout.upload("day.json", COMPLETE_DAY);

    // Seed the partition so rejections can carry its current view.
    json_output(&ingest(
        &layout,
        &complete_manifest_for(COMPLETE_DAY),
        &artifact,
    ));

    // truncated: the declared byte count disagrees with the artifact file.
    let mut truncated = serde_json::from_str::<Value>(&complete_manifest_for(COMPLETE_DAY))
        .expect("manifest");
    truncated
        .as_object_mut()
        .unwrap()
        .insert("byte_count".into(), json!(COMPLETE_DAY.len() + 1));
    let receipt = json_output(&ingest(
        &layout,
        &serde_json::to_string(&truncated).unwrap(),
        &artifact,
    ));
    assert_eq!(receipt["outcome"], "rejected");
    assert_eq!(receipt["rejection"], json!({"code": "truncated"}));
    assert_eq!(
        sorted_keys(&receipt),
        ["outcome", "partition", "rejection", "schema", "schema_version"]
    );
    assert_partition_grammar(&receipt["partition"]);
    assert_eq!(
        receipt["partition"]["authoritative"]["revision_id"],
        COMPLETE_DAY_SHA256
    );

    // checksum_invalid: correct length, wrong digest.
    let mut checksum = serde_json::from_str::<Value>(&complete_manifest_for(COMPLETE_DAY))
        .expect("manifest");
    checksum
        .as_object_mut()
        .unwrap()
        .insert("sha256".into(), json!("1".repeat(64)));
    let receipt = json_output(&ingest(
        &layout,
        &serde_json::to_string(&checksum).unwrap(),
        &artifact,
    ));
    assert_eq!(receipt["rejection"], json!({"code": "checksum_invalid"}));

    // manifest_incomplete: the manifest file is missing entirely.
    let manifest_path = layout.uploads().join("missing.json");
    let output = run(&[
        "data".into(),
        "ingest".into(),
        "--database".into(),
        layout.database().to_string_lossy().into_owned(),
        "--manifest".into(),
        manifest_path.to_string_lossy().into_owned(),
        "--artifact".into(),
        artifact.to_string_lossy().into_owned(),
    ]);
    let receipt = json_output(&output);
    assert_eq!(receipt["rejection"], json!({"code": "manifest_incomplete"}));
    assert_eq!(
        sorted_keys(&receipt),
        ["outcome", "rejection", "schema", "schema_version"]
    );

    // manifest_incomplete: schema-invalid manifest document.
    let invalid = layout.upload("invalid.json", "{\"schema\":\"healthmd.agent_data_ingest\"}");
    let receipt = json_output(&ingest(&layout, "{\"not\":\"a manifest\"}", &invalid));
    assert_eq!(receipt["rejection"], json!({"code": "manifest_incomplete"}));

    // transient: the artifact path is not readable bytes (a directory).
    let directory = layout.uploads().join("artifact-directory");
    std::fs::create_dir(&directory).expect("directory");
    let receipt = json_output(&ingest(
        &layout,
        &complete_manifest_for(COMPLETE_DAY),
        &directory,
    ));
    assert_eq!(receipt["rejection"], json!({"code": "transient"}));

    // Rejections never mutate the store.
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(listed_artifact_count(&mut session, 1), 1);
}

#[test]
fn reingest_is_idempotent_with_a_stable_receipt_and_no_duplicate_rows() {
    let layout = Layout::new();
    let artifact = layout.upload("day.json", COMPLETE_DAY);
    let first = json_output(&ingest(
        &layout,
        &complete_manifest_for(COMPLETE_DAY),
        &artifact,
    ));
    let second = json_output(&ingest(
        &layout,
        &complete_manifest_for(COMPLETE_DAY),
        &artifact,
    ));
    assert_eq!(
        serde_json::to_string(&first).unwrap(),
        serde_json::to_string(&second).unwrap(),
        "identical bytes must produce a byte-identical receipt"
    );
    let mut session = StdioSession::start(&layout);
    session.initialize();
    assert_eq!(listed_artifact_count(&mut session, 1), 1);
}

#[test]
fn cli_level_failures_exit_nonzero_without_receipts() {
    let layout = Layout::new();
    let artifact = layout.upload("day.json", COMPLETE_DAY);
    let manifest_path = layout.uploads().join("manifest.json");
    std::fs::write(&manifest_path, complete_manifest_for(COMPLETE_DAY)).expect("manifest");
    let output = run(&[
        "data".into(),
        "ingest".into(),
        "--database".into(),
        "relative.sqlite".into(),
        "--manifest".into(),
        manifest_path.to_string_lossy().into_owned(),
        "--artifact".into(),
        artifact.to_string_lossy().into_owned(),
    ]);
    assert!(!output.status.success());
    assert!(output.stderr.is_empty());
    let value: Value = serde_json::from_slice(&output.stdout).expect("cli error JSON");
    assert_eq!(value["schema"], "healthmd.cli_error");
    assert_eq!(value["error"], "data_ingest_failed");
    assert_eq!(
        value["message"],
        "the Agent Data database path must be absolute"
    );

    // The database may not be one of the upload files.
    let output = run(&[
        "data".into(),
        "ingest".into(),
        "--database".into(),
        manifest_path.to_string_lossy().into_owned(),
        "--manifest".into(),
        manifest_path.to_string_lossy().into_owned(),
        "--artifact".into(),
        artifact.to_string_lossy().into_owned(),
    ]);
    assert!(!output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).expect("cli error JSON");
    assert_eq!(
        value["message"],
        "the Agent Data database must be stored outside the upload files"
    );
}
