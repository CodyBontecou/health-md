//! Shipped-binary regression gate for MCP surface separation.
//!
//! The direct-device MCP surface (`healthmd mcp serve`, inspected offline via
//! `healthmd mcp schema`) and the data-only Agent Data surface
//! (`healthmd mcp serve-data`, inspected via `healthmd mcp schema --data`)
//! must remain separate, fixed catalogs. These assertions freeze the observed
//! catalogs as the baseline: any tool addition, removal, or cross-surface leak
//! in the shipped binary must be a conscious change that updates this gate.

use std::process::{Command, Output, Stdio};

use serde_json::{Value, json};

/// The fixed direct-operation catalog served by `healthmd mcp serve`.
const DIRECT_TOOLS: &[&str] = &[
    // Readiness family.
    "healthmd_status",
    "healthmd_doctor",
    // Catalog family.
    "healthmd_capabilities",
    "healthmd_metrics",
    // Typed-query family.
    "healthmd_metric_chart",
    "healthmd_sleep_sessions",
    "healthmd_training_alignment",
    "healthmd_workouts",
    "healthmd_coverage",
    "healthmd_compare_periods",
    "healthmd_training_evidence",
    "healthmd_query",
    "healthmd_evidence_packet",
    // Pairing family.
    "healthmd_pairing_start",
    "healthmd_pairing_status",
    // Durable export family.
    "healthmd_export_files",
    "healthmd_export_job_status",
    "healthmd_export_job_resume",
    "healthmd_export_job_cancel",
];

/// The fixed five-tool Agent Data catalog served by `healthmd mcp serve-data`.
const DATA_TOOLS: &[&str] = &[
    "healthmd_data_catalog",
    "healthmd_data_records",
    "healthmd_data_record_read",
    "healthmd_data_artifacts",
    "healthmd_data_artifact_read",
];

/// The documented unavailable-tool error for `mcp schema` lookups.
const UNAVAILABLE_TOOL_MESSAGE: &str = "The requested fixed MCP tool is unavailable. Run `healthmd mcp schema` (or `healthmd mcp schema --data`) to list the supported tools.";

fn run(arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(arguments)
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch")
}

fn json_output(output: &Output) -> Value {
    serde_json::from_slice(&output.stdout).expect("stdout should contain one JSON document")
}

fn sorted_tool_names(value: &Value) -> Vec<String> {
    let mut names: Vec<String> = value["tools"]
        .as_array()
        .expect("catalog should contain a tools array")
        .iter()
        .map(|tool| {
            tool["name"]
                .as_str()
                .expect("every tool should have a name")
                .to_owned()
        })
        .collect();
    names.sort();
    names
}

fn sorted(strings: &[&str]) -> Vec<String> {
    let mut names: Vec<String> = strings.iter().map(|name| (*name).to_owned()).collect();
    names.sort();
    names
}

#[test]
fn direct_catalog_lists_exactly_the_fixed_direct_operations_and_no_data_tools() {
    let output = run(&["mcp", "schema"]);
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.mcp_tool_catalog");
    assert_eq!(value["schema_version"], 1);

    // Exact frozen baseline: additions to the direct surface are conscious.
    assert_eq!(sorted_tool_names(&value), sorted(DIRECT_TOOLS));
    for name in sorted_tool_names(&value) {
        assert!(
            !name.starts_with("healthmd_data_"),
            "direct catalog must not contain {name}"
        );
    }

    // No data-store advertising anywhere in the direct surface.
    let text = String::from_utf8(output.stdout).expect("catalog should be UTF-8");
    assert!(!text.contains("healthmd_data_"));
    assert!(!text.contains("Agent Data"));

    // Direct guidance stays direct-tool guidance.
    let guidance = &value["guidance"];
    assert_eq!(guidance["typed_tools_are_preferred"], true);
    assert_eq!(guidance["sleep_tool"], "healthmd_sleep_sessions");
    assert_eq!(guidance["workout_tool"], "healthmd_workouts");
    assert_eq!(guidance["metric_series_tool"], "healthmd_metric_chart");
    assert!(
        guidance.get("data_only").is_none(),
        "direct guidance must not carry the data_only marker"
    );
}

#[test]
fn data_catalog_lists_exactly_the_five_agent_data_tools() {
    let output = run(&["mcp", "schema", "--data"]);
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.mcp_tool_catalog");
    assert_eq!(value["schema_version"], 1);

    // Exact set equality: no additions, and no direct, status, pairing,
    // export, filesystem, SQL, or shell tools.
    assert_eq!(sorted_tool_names(&value), sorted(DATA_TOOLS));

    // Every Agent Data tool is read-only: no mutating tool ships on the
    // data surface.
    for tool in value["tools"].as_array().expect("tools array") {
        assert_eq!(
            tool.pointer("/annotations/readOnlyHint"),
            Some(&Value::Bool(true)),
            "{} must stay read-only",
            tool["name"]
        );
    }

    let guidance = &value["guidance"];
    assert_eq!(guidance["data_only"], true);
    assert_eq!(guidance["discovery_tool"], "healthmd_data_catalog");
    assert_eq!(guidance["records_tool"], "healthmd_data_records");

    // No direct tool name leaks into the data surface.
    let text = String::from_utf8(output.stdout).expect("catalog should be UTF-8");
    for name in DIRECT_TOOLS {
        assert!(
            !text.contains(name),
            "{name} must not appear on the data surface"
        );
    }
}

#[test]
fn data_records_schema_documents_the_bounded_page_object() {
    let output = run(&["mcp", "schema", "--data", "healthmd_data_records"]);
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.mcp_tool_schema");
    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["tool"]["name"], "healthmd_data_records");
    assert_eq!(value["guidance"]["data_only"], true);

    let input_schema = &value["tool"]["inputSchema"];
    assert_eq!(input_schema["required"], json!(["metrics", "detail_level"]));
    assert_eq!(
        input_schema.pointer("/properties/detail_level/enum"),
        Some(&json!(["common", "lossless"]))
    );

    // The bounded page object: fixed wire bounds and opaque cursor defaults.
    assert_eq!(
        input_schema.pointer("/properties/page"),
        Some(&json!({
            "type": "object",
            "additionalProperties": false,
            "required": ["max_items", "max_bytes"],
            "properties": {
                "max_items": {"type": "integer", "minimum": 1, "maximum": 1000, "default": 250},
                "max_bytes": {"type": "integer", "minimum": 1, "maximum": 1_048_576, "default": 262_144},
                "cursor": {"type": ["string", "null"], "default": null}
            },
            "default": {"max_items": 250, "max_bytes": 262_144, "cursor": null}
        }))
    );
}

#[test]
fn unavailable_tools_fail_with_the_documented_error_surface_without_echoing_the_name() {
    let cases = [
        (
            "data",
            &["mcp", "schema", "--data", "healthmd_data_unknown"][..],
            "healthmd_data_unknown",
        ),
        (
            "direct",
            &["mcp", "schema", "healthmd_data_records"][..],
            "healthmd_data_records",
        ),
        (
            "direct",
            &["mcp", "schema", "healthmd_unknown_direct"][..],
            "healthmd_unknown_direct",
        ),
    ];
    for (backend, arguments, requested_name) in cases {
        let output = run(arguments);
        assert!(!output.status.success(), "{arguments:?} should fail");
        assert!(output.stderr.is_empty(), "{arguments:?} wrote stderr");
        let value = json_output(&output);
        assert_eq!(value["schema"], "healthmd.cli_error");
        assert_eq!(value["status"], "failure");
        assert_eq!(value["error"], "invalid_request");
        assert_eq!(value["backend"], backend);
        assert_eq!(value["request_sent"], false);
        assert_eq!(value["help_command"], "healthmd mcp schema --help");
        assert_eq!(value["message"], UNAVAILABLE_TOOL_MESSAGE);
        assert_eq!(
            value.pointer("/next_actions/0/command"),
            Some(&Value::String("healthmd mcp schema --help".into()))
        );
        let text = String::from_utf8_lossy(&output.stdout);
        assert!(
            !text.contains(requested_name),
            "{arguments:?} must not echo the requested tool name"
        );
    }
}

#[test]
fn bare_mcp_lists_discovery_subcommands_without_starting_a_listener() {
    let output = run(&["mcp"]);
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.cli_guidance");
    assert_eq!(value["status"], "guidance");
    assert_eq!(value["command"], "healthmd mcp");
    assert_eq!(value["request_sent"], false);

    let commands: Vec<&str> = value["available_commands"]
        .as_array()
        .expect("available_commands array")
        .iter()
        .map(|entry| entry["command"].as_str().expect("command string"))
        .collect();
    for documented in [
        "healthmd mcp serve",
        "healthmd mcp serve-read-only",
        "healthmd mcp schema",
        "healthmd mcp schema --data",
    ] {
        assert!(
            commands.contains(&documented),
            "discovery must list {documented}"
        );
    }
    let serve_data: Vec<&&str> = commands
        .iter()
        .filter(|command| command.starts_with("healthmd mcp serve-data"))
        .collect();
    assert_eq!(serve_data.len(), 1, "exactly one serve-data entry");
    let serve_data = serve_data[0];
    assert!(serve_data.contains("--directory"));
    assert!(serve_data.contains("--grant"));
    // Every documented subcommand stays under `healthmd mcp` (the
    // streamable-http build adds `serve-http`; default builds do not).
    for command in &commands {
        assert!(
            command.starts_with("healthmd mcp "),
            "unexpected MCP subcommand {command}"
        );
    }
}

#[test]
fn serve_data_help_documents_store_options_without_direct_serve_options() {
    let output = run(&["mcp", "serve-data", "--help"]);
    assert!(output.status.success());
    let text = String::from_utf8(output.stdout).expect("help should be UTF-8");
    assert!(text.contains("--directory <DIRECTORY>"));
    assert!(text.contains("--grant <GRANT>"));
    assert!(text.contains("Agent Data grant"));
    // `mcp serve-data` shares no surface-specific option with `mcp serve`.
    assert!(!text.contains("--timeout-seconds"));
}
