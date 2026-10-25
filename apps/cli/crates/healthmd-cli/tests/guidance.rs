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
        (&["data"], "healthmd data"),
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
fn data_group_lists_import_and_ingest() {
    let output = run(&["data"]);
    assert!(output.status.success());
    let value = json_output(&output);
    assert_eq!(value["command"], "healthmd data");
    let commands = value["available_commands"]
        .as_array()
        .expect("available commands");
    let names: Vec<&str> = commands
        .iter()
        .map(|command| command["command"].as_str().expect("command"))
        .collect();
    assert!(
        names
            .iter()
            .any(|name| name.starts_with("healthmd data import"))
    );
    assert!(
        names
            .iter()
            .any(|name| name.starts_with("healthmd data ingest"))
    );
    assert!(
        names
            .iter()
            .any(|name| name.starts_with("healthmd data ingest-serve"))
    );
}

#[test]
fn data_ingest_parse_errors_list_accepted_arguments_without_echoing_paths() {
    let output = run(&["data", "ingest"]);
    assert!(!output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.cli_error");
    assert_eq!(value["error"], "invalid_request");
    assert_eq!(value["command"], "healthmd data ingest");
    assert_eq!(value["request_sent"], false);
    let arguments: Vec<&str> = value["accepted_arguments"]
        .as_array()
        .expect("accepted arguments")
        .iter()
        .map(|argument| argument.as_str().expect("argument"))
        .collect();
    assert!(
        arguments
            .iter()
            .any(|argument| argument.contains("--manifest"))
    );
    assert!(
        arguments
            .iter()
            .any(|argument| argument.contains("--artifact"))
    );
}

#[test]
fn data_ingest_serve_parse_errors_list_accepted_arguments_without_echoing_values() {
    // The data group listing includes the gateway command.
    let output = run(&["data"]);
    assert!(output.status.success());
    let value = json_output(&output);
    assert!(
        value["available_commands"]
            .as_array()
            .expect("available commands")
            .iter()
            .any(|command| command["command"]
                .as_str()
                .expect("command")
                .starts_with("healthmd data ingest-serve"))
    );

    let output = run(&["data", "ingest-serve"]);
    assert!(!output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["schema"], "healthmd.cli_error");
    assert_eq!(value["error"], "invalid_request");
    assert_eq!(value["command"], "healthmd data ingest-serve");
    assert_eq!(value["request_sent"], false);
    let arguments: Vec<&str> = value["accepted_arguments"]
        .as_array()
        .expect("accepted arguments")
        .iter()
        .map(|argument| argument.as_str().expect("argument"))
        .collect();
    assert!(
        arguments
            .iter()
            .any(|argument| argument.contains("--database"))
    );
    assert!(arguments.iter().any(|argument| argument.contains("--bind")));
    assert!(
        arguments
            .iter()
            .any(|argument| argument.contains("--allowed-host"))
    );
    assert!(
        arguments
            .iter()
            .any(|argument| argument.contains("--allowed-origin"))
    );
    let encoded = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(encoded.contains("healthmd data ingest-serve --help"));
}

#[test]
fn mcp_serve_data_parse_errors_list_every_backing_argument_without_echoing_values() {
    // The mcp group listing keeps exactly one serve-data entry covering every backing.
    let output = run(&["mcp"]);
    assert!(output.status.success());
    let value = json_output(&output);
    let serve_data_entries: Vec<&str> = value["available_commands"]
        .as_array()
        .expect("available commands")
        .iter()
        .map(|command| command["command"].as_str().expect("command"))
        .filter(|command| command.starts_with("healthmd mcp serve-data"))
        .collect();
    assert_eq!(serve_data_entries.len(), 1);
    assert!(serve_data_entries[0].contains("--directory"));
    assert!(serve_data_entries[0].contains("--database"));
    assert!(serve_data_entries[0].contains("--object-store-url"));
    assert!(serve_data_entries[0].contains("--grant"));

    let private = "synthetic-private-health-value";
    let cases: &[&[&str]] = &[
        // --bucket without --object-store-url leaves the required backing choice unsatisfied.
        &["mcp", "serve-data", "--bucket", private, "--grant", private],
        // Two backings at once conflict.
        &[
            "mcp",
            "serve-data",
            "--database",
            private,
            "--object-store-url",
            private,
            "--grant",
            private,
        ],
        // An unrecognized flag.
        &[
            "mcp",
            "serve-data",
            "--nope",
            "--directory",
            private,
            "--grant",
            private,
        ],
    ];
    for arguments in cases {
        let output = run(arguments);
        assert!(!output.status.success(), "{arguments:?} should fail");
        assert!(output.stderr.is_empty(), "{arguments:?} wrote stderr");
        let value = json_output(&output);
        assert_eq!(value["schema"], "healthmd.cli_error");
        assert_eq!(value["error"], "invalid_request");
        assert_eq!(value["command"], "healthmd mcp serve-data");
        assert_eq!(value["request_sent"], false);
        let text = String::from_utf8_lossy(&output.stdout).into_owned();
        assert!(
            !text.contains(private),
            "{arguments:?} must not echo values"
        );
        let accepted: Vec<&str> = value["accepted_arguments"]
            .as_array()
            .expect("accepted arguments")
            .iter()
            .map(|argument| argument.as_str().expect("argument"))
            .collect();
        for flag in [
            "--directory",
            "--database",
            "--object-store-url",
            "--bucket",
            "--prefix",
            "--grant",
            "--index",
        ] {
            assert!(
                accepted.iter().any(|argument| argument.contains(flag)),
                "{arguments:?} guidance must list {flag}"
            );
        }
        // The embedded reference documents every backing with a value-free example.
        assert_eq!(
            value.pointer("/guidance/command"),
            Some(&Value::String("healthmd mcp serve-data".into()))
        );
        let examples = value
            .pointer("/guidance/examples")
            .and_then(|examples| examples.as_array())
            .expect("serve-data guidance examples");
        assert!(
            examples.len() >= 3,
            "{arguments:?} guidance must example every backing"
        );
        assert!(text.contains("healthmd mcp serve-data --help"));
    }
}

#[test]
fn data_ingest_failures_exit_nonzero_with_health_free_recovery() {
    let output = run(&[
        "data",
        "ingest",
        "--database",
        "relative.sqlite",
        "--manifest",
        "manifest.json",
        "--artifact",
        "day.json",
    ]);
    assert!(!output.status.success());
    assert!(output.stderr.is_empty());
    let value = json_output(&output);
    assert_eq!(value["error"], "data_ingest_failed");
    assert_eq!(
        value["message"],
        "the Agent Data database path must be absolute"
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("healthmd data ingest --help"));
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
