use std::process::{Command, Output, Stdio};

use serde_json::Value;

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

#[test]
fn incomplete_public_commands_return_successful_non_network_guidance() {
    let cases: &[(&[&str], &str)] = &[
        (&["export"], "healthmd export"),
        (&["extract"], "healthmd extract"),
        (&["query"], "healthmd query"),
        (
            &["query", "healthmd_sleep_sessions"],
            "healthmd query healthmd_sleep_sessions",
        ),
        (&["resume"], "healthmd resume"),
        (&["cancel"], "healthmd cancel"),
        (&["direct"], "healthmd direct"),
        (&["direct", "unpair"], "healthmd direct unpair"),
        (&["direct", "reset-trust"], "healthmd direct reset-trust"),
        (&["mcp"], "healthmd mcp"),
        (&["setup"], "healthmd setup"),
    ];

    for (arguments, expected_command) in cases {
        let output = run(arguments);
        assert!(
            output.status.success(),
            "{arguments:?} should be successful discovery"
        );
        assert!(output.stderr.is_empty(), "{arguments:?} wrote stderr");
        let value = json_output(&output);
        assert_eq!(value["schema"], "healthmd.cli_guidance");
        assert_eq!(value["status"], "guidance");
        assert_eq!(value["command"], *expected_command);
        assert_eq!(value["request_sent"], false);
    }
}

#[test]
fn discovery_does_not_initialize_private_cli_state() {
    let temporary = tempfile::tempdir().expect("temporary root should exist");
    for (index, arguments) in [
        &["export"][..],
        &["query", "healthmd_sleep_sessions"][..],
        &["mcp", "schema", "healthmd_sleep_sessions"][..],
        &["direct", "reset-trust"][..],
    ]
    .into_iter()
    .enumerate()
    {
        let state = temporary.path().join(format!("state-{index}"));
        let output = Command::new(env!("CARGO_BIN_EXE_healthmd"))
            .args(arguments)
            .env("HEALTHMD_CLI_DATA_DIR", &state)
            .stdin(Stdio::null())
            .output()
            .expect("healthmd should launch");
        assert!(output.status.success());
        assert!(
            !state.exists(),
            "discovery must not initialize private state for {arguments:?}"
        );
    }
}

#[test]
fn selected_query_operation_returns_its_complete_argument_schema() {
    let output = run(&["query", "healthmd_sleep_sessions"]);
    assert!(output.status.success());
    let value = json_output(&output);
    assert_eq!(
        value.pointer("/input_schema/required/0"),
        Some(&Value::String("dates".into()))
    );
    assert_eq!(
        value.pointer("/examples/0/argv/2"),
        Some(&Value::String("healthmd_sleep_sessions".into()))
    );
}

#[test]
fn human_mode_renders_every_discovery_command_without_json_syntax() {
    for arguments in [
        &["export", "--human"][..],
        &["extract", "--human"][..],
        &["query", "--human"][..],
        &["resume", "--human"][..],
        &["cancel", "--human"][..],
        &["direct", "--human"][..],
        &["mcp", "--human"][..],
        &["setup", "--human"][..],
    ] {
        let output = run(arguments);
        assert!(output.status.success(), "{arguments:?} should succeed");
        let text = String::from_utf8(output.stdout).expect("human output should be UTF-8");
        assert!(!text.trim_start().starts_with('{'), "{arguments:?}");
        assert!(text.contains("Machine-readable"), "{arguments:?}");
    }
}

#[test]
fn explicit_json_preserves_the_machine_contract() {
    let output = run(&["query", "--json"]);
    assert!(output.status.success());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.cli_guidance");
    assert_eq!(value["command"], "healthmd query");
}

#[test]
fn parse_failures_are_structured_actionable_and_do_not_echo_values() {
    let private = "synthetic-private-health-value";
    let output = run(&["export", "--timeout", private]);
    assert!(!output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.cli_error");
    assert_eq!(value["error"], "invalid_request");
    assert_eq!(value["request_sent"], false);
    assert_eq!(value["help_command"], "healthmd export --help");
    assert!(!String::from_utf8_lossy(&output.stdout).contains(private));

    let human = run(&["export", "--timeout", private, "--human"]);
    assert!(!human.status.success());
    let text = String::from_utf8_lossy(&human.stdout);
    assert!(text.starts_with("Error: Invalid request"));
    assert!(!text.contains(private));
}

#[test]
fn invalid_typed_arguments_explain_the_exact_operation_without_contacting_iphone() {
    let temporary = tempfile::tempdir().expect("temporary root should exist");
    let state = temporary.path().join("must-not-exist");
    let output = Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .args(["query", "healthmd_sleep_sessions", "--arguments", "{}"])
        .env("HEALTHMD_CLI_DATA_DIR", &state)
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch");
    assert!(!output.status.success());
    assert!(output.stderr.is_empty());
    assert!(
        !state.exists(),
        "argument validation must precede private state"
    );
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.cli_error");
    assert_eq!(value["message"], "dates are required");
    assert_eq!(value["request_sent"], false);
    assert_eq!(
        value.pointer("/guidance/input_schema/required/0"),
        Some(&Value::String("dates".into()))
    );
}
