//! End-to-end coverage for the Health.md-owned `SQLite` Agent Data store: the public
//! `healthmd data import` command and the `healthmd mcp serve-data --database`
//! stdio surface, using only synthetic export artifacts.

use std::{
    io::{BufRead as _, BufReader, Write as _},
    process::{Child, Command, Output, Stdio},
};

use base64::Engine as _;
use serde_json::{Value, json};

const DAY_ONE: &str = r#"{
  "schema":"healthmd.health_data","schema_version":8,"date":"2026-03-15",
  "type":"health-data","raw_capture_status":"complete","unit_system":"metric","units":{},
  "activity":{"steps":12345},"heart":{"restingHeartRate":58}
}"#;
const DAY_TWO: &str = r#"{
  "schema":"healthmd.health_data","schema_version":8,"date":"2026-03-16",
  "type":"health-data","raw_capture_status":"complete","unit_system":"metric","units":{},
  "activity":{"steps":999}
}"#;

struct Layout {
    root: tempfile::TempDir,
}

impl Layout {
    fn new() -> Self {
        let root = tempfile::tempdir().expect("temporary root");
        let exports = root.path().join("exports");
        std::fs::create_dir(&exports).expect("exports directory");
        write(&exports.join("day1.json"), DAY_ONE);
        write(&exports.join("day2.json"), DAY_TWO);
        write(
            &root.path().join("grant.json"),
            &serde_json::to_string(&grant(false)).expect("grant JSON"),
        );
        Self { root }
    }

    fn exports(&self) -> std::path::PathBuf {
        self.root.path().join("exports")
    }

    fn database(&self) -> std::path::PathBuf {
        self.root.path().join("agent-data.sqlite")
    }

    fn grant(&self) -> std::path::PathBuf {
        self.root.path().join("grant.json")
    }

    fn bulk_grant(&self) -> std::path::PathBuf {
        let path = self.root.path().join("grant-bulk.json");
        write(
            &path,
            &serde_json::to_string(&grant(true)).expect("grant JSON"),
        );
        path
    }
}

fn grant(bulk: bool) -> Value {
    json!({
        "schema": "healthmd.agent_data_grant",
        "schema_version": 1,
        "metrics": {"type": "all_available"},
        "sources": {"type": "all_available"},
        "dates": {"type": "all_available"},
        "times": {"type": "all_available"},
        "detail_levels": ["common", "lossless"],
        "bulk_download": bulk
    })
}

fn write(path: &std::path::Path, contents: &str) {
    let mut file = std::fs::File::create(path).expect("file create");
    file.write_all(contents.as_bytes()).expect("file write");
}

fn run(arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(arguments)
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch")
}

fn json_output(output: &Output) -> Value {
    assert!(
        output.status.success(),
        "command should succeed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("stdout should contain one JSON document")
}

/// One newline-delimited JSON-RPC exchange with a `serve-data` stdio server.
struct StdioSession {
    child: Child,
}

impl StdioSession {
    fn start(arguments: &[String]) -> Self {
        let child = Command::new(env!("CARGO_BIN_EXE_healthmd"))
            .args(["mcp", "serve-data"])
            .args(arguments)
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

    #[allow(clippy::needless_pass_by_value)]
    fn call_tool(&mut self, id: i64, name: &str, arguments: Value) -> Value {
        self.request(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments}
        }))
    }
}

impl Drop for StdioSession {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn tool_payload(response: &Value) -> Value {
    let text = response
        .pointer("/result/content/0/text")
        .and_then(Value::as_str)
        .expect("tool text payload");
    serde_json::from_str(text).expect("tool payload JSON")
}

#[test]
fn data_import_is_idempotent_and_reports_honest_counts() {
    let layout = Layout::new();
    let database = layout.database();
    let exports = layout.exports();
    let database_arg = database.to_str().expect("utf-8 database path");
    let exports_arg = exports.to_str().expect("utf-8 exports path");

    let first = json_output(&run(&[
        "data",
        "import",
        "--database",
        database_arg,
        "--directory",
        exports_arg,
    ]));
    assert_eq!(first["schema"], "healthmd.agent_data_import");
    assert_eq!(first["status"], "success");
    assert_eq!(first["scanned_file_count"], 2);
    assert_eq!(first["imported_artifact_count"], 2);
    assert_eq!(first["duplicate_artifact_count"], 0);
    assert_eq!(first["artifact_count"], 2);
    assert_eq!(first["record_count"], 3);
    assert_eq!(first["non_destructive"], true);

    let second = json_output(&run(&[
        "data",
        "import",
        "--database",
        database_arg,
        "--directory",
        exports_arg,
    ]));
    assert_eq!(second["imported_artifact_count"], 0);
    assert_eq!(second["duplicate_artifact_count"], 2);
    assert_eq!(second["artifact_count"], 2);
    assert_eq!(second["record_count"], 3);
    assert_eq!(
        second["index_revision"], first["index_revision"],
        "identical bytes must not change the store revision"
    );
}

#[test]
fn data_import_rejects_databases_inside_the_exports_directory() {
    let layout = Layout::new();
    let inside = layout.exports().join("inside.sqlite");
    let inside_arg = inside.to_str().expect("utf-8 database path").to_owned();
    let exports = layout.exports();
    let exports_arg = exports.to_str().expect("utf-8 exports path").to_owned();
    let output = run(&[
        "data",
        "import",
        "--database",
        &inside_arg,
        "--directory",
        &exports_arg,
    ]);
    assert!(!output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).expect("error JSON");
    assert_eq!(value["schema"], "healthmd.cli_error");
    assert_eq!(value["status"], "failure");
    assert_eq!(value["error"], "data_import_failed");
    let encoded = serde_json::to_string(&value).expect("encoded error");
    assert!(
        !encoded.contains(&inside_arg.to_string()),
        "the private database path must not be echoed"
    );
}

#[test]
fn serve_data_database_serves_the_agent_data_contract_over_stdio() {
    let layout = Layout::new();
    let database_arg = layout.database().to_str().expect("utf-8 path").to_owned();
    let exports_arg = layout.exports().to_str().expect("utf-8 path").to_owned();
    let grant_arg = layout.grant().to_str().expect("utf-8 path").to_owned();
    json_output(&run(&[
        "data",
        "import",
        "--database",
        &database_arg,
        "--directory",
        &exports_arg,
    ]));

    let arguments = vec![
        "--database".to_owned(),
        database_arg,
        "--grant".to_owned(),
        grant_arg,
    ];
    let mut session = StdioSession::start(&arguments);
    let initialize = session.request(&json!({
        "jsonrpc": "2.0",
        "id": 0,
        "method": "initialize",
        "params": {"protocolVersion": "2025-11-25", "capabilities": {}}
    }));
    assert!(
        initialize["result"]["instructions"]
            .as_str()
            .expect("instructions")
            .contains("healthmd_data_catalog")
    );

    let catalog = tool_payload(&session.call_tool(1, "healthmd_data_catalog", json!({})));
    assert_eq!(catalog["schema"], "healthmd.agent_query_response");
    assert_eq!(catalog["receipt"]["source_kind"], "database");
    assert_eq!(catalog["receipt"]["policy_enforced"], true);
    assert!(
        catalog["items"]
            .as_array()
            .expect("catalog items")
            .iter()
            .any(|item| item["metric_id"] == "healthmd.health_data#/activity/steps")
    );

    let records = tool_payload(&session.call_tool(
        2,
        "healthmd_data_records",
        json!({
            "metrics": {"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]},
            "sources": {"type": "all_available"},
            "dates": {"type": "all_available"},
            "times": {"type": "all_available"},
            "detail_level": "common"
        }),
    ));
    let items = records["items"].as_array().expect("record items");
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["value"], 12345);
    let encoded = serde_json::to_string(&records).expect("encoded records");
    assert!(
        !encoded.contains("restingHeartRate"),
        "an all-available grant still only exposes indexed metric records"
    );

    let denied = session.call_tool(3, "healthmd_data_artifacts", json!({}));
    let artifacts = tool_payload(&denied);
    assert!(
        artifacts["items"]
            .as_array()
            .expect("artifact items")
            .is_empty(),
        "bulk download must stay gated without an unrestricted grant"
    );
}

#[test]
fn serve_data_database_serves_exact_bulk_artifact_bytes() {
    let layout = Layout::new();
    let database_arg = layout.database().to_str().expect("utf-8 path").to_owned();
    let exports_arg = layout.exports().to_str().expect("utf-8 path").to_owned();
    let grant_arg = layout.bulk_grant().to_str().expect("utf-8 path").to_owned();
    json_output(&run(&[
        "data",
        "import",
        "--database",
        &database_arg,
        "--directory",
        &exports_arg,
    ]));

    let mut session = StdioSession::start(&[
        "--database".to_owned(),
        database_arg,
        "--grant".to_owned(),
        grant_arg,
    ]);
    session.request(&json!({
        "jsonrpc": "2.0",
        "id": 0,
        "method": "initialize",
        "params": {"protocolVersion": "2025-11-25", "capabilities": {}}
    }));
    let artifacts = tool_payload(&session.call_tool(1, "healthmd_data_artifacts", json!({})));
    let items = artifacts["items"].as_array().expect("artifact items");
    assert_eq!(items.len(), 2);
    let target = items
        .iter()
        .find(|item| item["byte_count"].as_u64() == Some(DAY_ONE.len() as u64))
        .expect("day one artifact");
    let artifact_id = target["artifact_id"].as_str().expect("artifact id");

    let chunk = tool_payload(&session.call_tool(
        2,
        "healthmd_data_artifact_read",
        json!({"artifact_id": artifact_id}),
    ));
    let item = &chunk["items"][0];
    assert_eq!(item["complete"], true);
    assert_eq!(item["sha256"], artifact_id);
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(item["data"].as_str().expect("base64 data"))
        .expect("base64 payload");
    assert_eq!(decoded, DAY_ONE.as_bytes());
}

#[test]
fn serve_data_rejects_conflicting_and_missing_backing_arguments() {
    let layout = Layout::new();
    let database_arg = layout.database().to_str().expect("utf-8 path").to_owned();
    let exports_arg = layout.exports().to_str().expect("utf-8 path").to_owned();
    let grant_arg = layout.grant().to_str().expect("utf-8 path").to_owned();

    let conflicting = run(&[
        "mcp",
        "serve-data",
        "--database",
        &database_arg,
        "--directory",
        &exports_arg,
        "--grant",
        &grant_arg,
    ]);
    assert!(!conflicting.status.success());

    let missing = run(&["mcp", "serve-data", "--grant", &grant_arg]);
    assert!(!missing.status.success());

    let index_with_database = run(&[
        "mcp",
        "serve-data",
        "--database",
        &database_arg,
        "--grant",
        &grant_arg,
        "--index",
        "/tmp/should-not-be-accepted.json",
    ]);
    assert!(!index_with_database.status.success());
    assert!(
        String::from_utf8_lossy(&index_with_database.stderr).contains("--index"),
        "the database store owns its index internally"
    );
}
