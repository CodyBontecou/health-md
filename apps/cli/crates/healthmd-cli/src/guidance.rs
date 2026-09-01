use std::ffi::OsString;

use clap::error::ErrorKind;
use healthmd_operations::{OperationDefinition, OperationKind, definition, definitions};
use serde_json::{Value, json};

use super::{Cli, Command, CommandError, QueryArgs, command_name};

const GUIDANCE_SCHEMA: &str = "healthmd.cli_guidance";
const ERROR_SCHEMA: &str = "healthmd.cli_error";
const SCHEMA_VERSION: u8 = 1;
const CANONICAL_OBJECT_ALIASES: &[&str] = &[
    "sleep",
    "activity",
    "heart",
    "vitals",
    "body",
    "nutrition",
    "mindfulness",
    "mobility",
    "hearing",
    "reproductive-health",
    "cycling",
    "vitamins",
    "minerals",
    "symptoms",
    "medications",
    "other",
    "workouts",
    "archive",
    "records",
    "external-records",
    "query-results",
    "warnings",
];

#[derive(Clone, Debug)]
pub(super) struct ErrorContext {
    backend: &'static str,
    command: &'static str,
    query_operation: Option<&'static str>,
}

impl ErrorContext {
    pub(super) fn from_cli(cli: &Cli) -> Self {
        let query_operation = match &cli.command {
            Command::Query(QueryArgs {
                operation: Some(operation),
                ..
            }) => definition(operation)
                .filter(|candidate| candidate.kind == OperationKind::Query)
                .map(|candidate| candidate.name),
            _ => None,
        };
        Self {
            backend: cli.backend.wire_name(),
            command: command_name(&cli.command),
            query_operation,
        }
    }
}

pub(super) fn export(backend: &'static str, missing_dates: bool, missing_mode: bool) -> Value {
    let mut missing = Vec::new();
    if missing_dates {
        missing.push(json!({
            "name": "date_selection",
            "description": "Choose exactly one of --yesterday, --last DAYS, --from DATE with --to DATE, or --all."
        }));
    }
    if missing_mode {
        missing.push(json!({
            "name": "export_mode",
            "description": "Choose --raw for a validated platform-native artifact, or --destination DIR for production-generated files."
        }));
    }
    let message = if missing.is_empty() {
        "Review the two export modes and their accepted argument combinations."
    } else {
        "The export request is incomplete. Choose the missing values below; no device was contacted."
    };
    json!({
        "schema": GUIDANCE_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "guidance",
        "backend": backend,
        "command": "healthmd export",
        "message": message,
        "request_sent": false,
        "missing": missing,
        "required_choices": [
            {
                "name": "date_selection",
                "exactly_one_of": [
                    "--yesterday",
                    "--last <DAYS>",
                    "--from <YYYY-MM-DD> --to <YYYY-MM-DD>",
                    "--all"
                ]
            },
            {
                "name": "export_mode",
                "exactly_one_of": [
                    "--raw",
                    "--destination <EXISTING_ABSOLUTE_DIRECTORY>"
                ]
            }
        ],
        "modes": [
            {
                "name": "generated_files",
                "description": "Ask the mobile app's production exporters to write files into an existing absolute directory on this computer.",
                "required": ["one date selection", "--destination <DIR>"],
                "settings_options": [
                    "--use-device-settings",
                    "--profile <PROFILE_ID>",
                    "--metric <METRIC_ID>",
                    "--category <CATEGORY>",
                    "--all-metrics",
                    "--detail <summary|lossless>"
                ],
                "platform_note": "Android generated files use saved device settings or a profile and do not accept CLI metric/category selectors."
            },
            {
                "name": "raw",
                "description": "Return the source platform's validated native raw artifact. Omit --output to stream it to stdout.",
                "required": ["one date selection", "--raw"],
                "options": [
                    "--output <FILE>",
                    "--allow-partial",
                    "--provider <PROVIDER_ID> (Android)",
                    "--raw-format <json|ndjson> (Android)",
                    "--metric <METRIC_ID> (Android)",
                    "--all-metrics (Android)"
                ]
            }
        ],
        "common_options": [
            {"argument": "--timeout <SECONDS>", "default": 300, "minimum": 5, "maximum": 900},
            {"argument": "--device <UUID>", "description": "Global option used when more than one source is paired."}
        ],
        "examples": [
            {
                "description": "Generated files for yesterday",
                "argv_template": ["healthmd", "export", "--yesterday", "--destination", "<EXISTING_ABSOLUTE_DIRECTORY>"]
            },
            {
                "description": "Seven-day raw artifact committed atomically to a file",
                "argv_template": ["healthmd", "export", "--last", "7", "--raw", "--output", "week.json"]
            },
            {
                "description": "Stream all validated raw data to stdout",
                "argv_template": ["healthmd", "export", "--all", "--raw"]
            }
        ],
        "next_actions": [
            {
                "command": "healthmd export --help",
                "description": "Read every export flag, platform constraint, and example."
            }
        ]
    })
}

pub(super) fn extract(backend: &'static str, missing_dates: bool, missing_scope: bool) -> Value {
    let mut missing = Vec::new();
    if missing_dates {
        missing.push(json!({
            "name": "date_selection",
            "description": "Choose exactly one of --yesterday, --last DAYS, --from DATE with --to DATE, or --all."
        }));
    }
    if missing_scope {
        missing.push(json!({
            "name": "selection",
            "description": "Choose --metric, --category, a category --object alias, or --all-metrics."
        }));
    }
    let message = if missing.is_empty() {
        "Review the canonical extraction scope and accepted argument combinations."
    } else {
        "The extraction request is incomplete. Choose the missing values below; no device was contacted."
    };
    json!({
        "schema": GUIDANCE_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "guidance",
        "backend": backend,
        "command": "healthmd extract",
        "message": message,
        "request_sent": false,
        "missing": missing,
        "required_choices": [
            {
                "name": "date_selection",
                "exactly_one_of": ["--yesterday", "--last <DAYS>", "--from <YYYY-MM-DD> --to <YYYY-MM-DD>", "--all"]
            },
            {
                "name": "selection",
                "one_or_more_of": ["--metric <METRIC_ID>", "--category <CATEGORY>", "--object <ALIAS>", "--all-metrics"]
            }
        ],
        "selection_options": [
            "--metric <METRIC_ID>",
            "--category <CATEGORY>",
            "--all-metrics",
            "--detail <summary|lossless>",
            "--object <ALIAS_OR_JSON_POINTER>",
            "--field <JSON_POINTER>",
            "--source <SOURCE_ID>"
        ],
        "object_aliases": CANONICAL_OBJECT_ALIASES,
        "output_options": [
            "--format <json|jsonl>",
            "--output <FILE>",
            "--allow-partial",
            "--timeout <SECONDS>"
        ],
        "platform_note": "Canonical extraction is currently available for paired iOS sources only. Typed sleep/workout questions should use `healthmd query` instead.",
        "examples": [
            {
                "description": "Seven days of canonical sleep data",
                "argv": ["healthmd", "extract", "--category", "Sleep", "--last", "7", "--output", "sleep.json"]
            },
            {
                "description": "Lossless workout records",
                "argv": ["healthmd", "extract", "--metric", "workouts", "--last", "14", "--object", "workouts", "--detail", "lossless"]
            }
        ],
        "next_actions": [
            {
                "command": "healthmd extract --help",
                "description": "Read every selector, output format, and example."
            },
            {
                "command": "healthmd query",
                "description": "List fixed typed query operations when the goal is analysis rather than canonical extraction."
            }
        ]
    })
}

pub(super) fn query(backend: &'static str, requested_operation: Option<&str>) -> Value {
    requested_operation
        .and_then(|name| {
            definition(name).filter(|candidate| candidate.kind == OperationKind::Query)
        })
        .map_or_else(
            || query_catalog(backend),
            |operation| query_operation(backend, operation),
        )
}

fn query_catalog(backend: &'static str) -> Value {
    json!({
        "schema": GUIDANCE_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "guidance",
        "backend": backend,
        "command": "healthmd query",
        "recognized_operation": false,
        "message": "Choose one fixed typed query operation. No device was contacted.",
        "request_sent": false,
        "platform_note": "Typed query execution currently requires a compatible foreground iPhone; operation discovery is local and works without pairing.",
        "required": [
            {
                "argument": "<OPERATION>",
                "description": "One fixed operation name from available_operations."
            },
            {
                "argument": "--arguments <JSON>",
                "description": "One JSON object satisfying that operation's input schema. Omit it after selecting an operation to inspect the exact schema and examples."
            }
        ],
        "available_operations": query_operations(),
        "next_actions": [
            {
                "command": "healthmd query healthmd_sleep_sessions",
                "description": "Inspect the sleep operation's required arguments, full schema, and examples."
            },
            {
                "command": "healthmd mcp schema",
                "description": "Print the complete fixed operation catalog."
            },
            {
                "command": "healthmd query --help",
                "description": "Read CLI quoting and timeout guidance."
            }
        ]
    })
}

fn query_operation(backend: &'static str, operation: &OperationDefinition) -> Value {
    let tool = healthmd_cli::mcp::tool_catalog(Some(operation.name))
        .ok()
        .and_then(|catalog| catalog.get("tool").cloned())
        .unwrap_or_else(|| {
            json!({
                "name": operation.name,
                "title": operation.title,
                "description": operation.description,
                "inputSchema": {"type": "object"}
            })
        });
    let examples = tool
        .pointer("/inputSchema/examples")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .map(|arguments| {
                    let encoded = serde_json::to_string(arguments).unwrap_or_else(|_| "{}".into());
                    json!({
                        "arguments": arguments,
                        "argv": ["healthmd", "query", operation.name, "--arguments", encoded]
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    json!({
        "schema": GUIDANCE_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "guidance",
        "backend": backend,
        "command": format!("healthmd query {}", operation.name),
        "recognized_operation": true,
        "message": "Supply --arguments with one JSON object matching input_schema. No device was contacted.",
        "request_sent": false,
        "platform_note": "Typed query execution currently requires a compatible foreground iPhone; this schema inspection is local and works without pairing.",
        "operation": {
            "name": operation.name,
            "title": operation.title,
            "description": operation.description
        },
        "required": [
            {
                "argument": "--arguments <JSON>",
                "description": "One JSON object matching input_schema."
            }
        ],
        "optional": [
            {
                "argument": "--timeout <SECONDS>",
                "default": 1200,
                "minimum": 1,
                "maximum": 3600
            }
        ],
        "input_schema": tool.get("inputSchema").cloned().unwrap_or(Value::Null),
        "examples": examples,
        "next_actions": [
            {
                "command": format!("healthmd mcp schema {}", operation.name),
                "description": "Print the same full operation declaration independently."
            },
            {
                "command": "healthmd query",
                "description": "Return to the fixed typed query operation catalog."
            }
        ]
    })
}

pub(super) fn group(backend: &'static str, group: &'static str) -> Value {
    let (description, commands) = match group {
        "direct" => (
            "Pair and manage direct mobile trust.",
            vec![
                json!({"command": "healthmd direct pair", "description": "Pair this CLI installation with an open iOS or Android app."}),
                json!({"command": "healthmd direct devices", "description": "List local trusted devices without network access."}),
                json!({"command": "healthmd direct unpair", "description": "Inspect the required device ID before removing one pairing."}),
                json!({"command": "healthmd direct reset-trust", "description": "Review the destructive all-trust reset and its required confirmation."}),
            ],
        ),
        "mcp" => {
            #[allow(unused_mut)]
            let mut commands = vec![
                json!({"command": "healthmd mcp serve", "description": "Serve the complete local MCP surface over stdio."}),
                json!({"command": "healthmd mcp serve-read-only", "description": "Serve only readiness and query tools over stdio."}),
                json!({"command": "healthmd mcp schema", "description": "Print the fixed operation catalog without contacting a device."}),
            ];
            #[cfg(feature = "streamable-http")]
            commands.push(json!({"command": "healthmd mcp serve-http", "description": "Serve the experimental read-only loopback Streamable HTTP profile."}));
            (
                "Serve or inspect Health.md's fixed Model Context Protocol surface.",
                commands,
            )
        }
        "setup" => (
            "Configure a supported local AI host.",
            vec![json!({
                "command": "healthmd setup codex",
                "description": "Configure Codex to launch this executable and pair an iPhone when needed."
            })],
        ),
        _ => ("Choose one documented Health.md command.", root_commands()),
    };
    json!({
        "schema": GUIDANCE_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "guidance",
        "backend": backend,
        "command": format!("healthmd {group}"),
        "message": "Choose one of the available commands below; no operation was started.",
        "description": description,
        "request_sent": false,
        "available_commands": commands,
        "next_actions": [{
            "command": format!("healthmd {group} --help"),
            "description": "Read the complete command help."
        }]
    })
}

pub(super) fn resume(backend: &'static str) -> Value {
    positional(
        backend,
        "healthmd resume",
        "JOB_ID",
        "The UUID from an interrupted durable export receipt or `healthmd status --job JOB_ID`.",
        &[
            json!({"argv_template": ["healthmd", "resume", "<JOB_UUID>"]}),
            json!({"argv_template": ["healthmd", "resume", "<JOB_UUID>", "--output", "resumed.json"]}),
        ],
    )
}

pub(super) fn cancel(backend: &'static str) -> Value {
    positional(
        backend,
        "healthmd cancel",
        "JOB_ID",
        "The UUID of the exact durable job to cancel. Cancellation is explicit and cannot be undone after the mobile source acknowledges it.",
        &[json!({"argv_template": ["healthmd", "cancel", "<JOB_UUID>"]})],
    )
}

pub(super) fn unpair(backend: &'static str) -> Value {
    positional(
        backend,
        "healthmd direct unpair",
        "DEVICE_ID",
        "A trusted mobile installation UUID from `healthmd direct devices`.",
        &[json!({"argv_template": ["healthmd", "direct", "unpair", "<DEVICE_UUID>"]})],
    )
}

pub(super) fn reset_trust(backend: &'static str) -> Value {
    json!({
        "schema": GUIDANCE_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "guidance",
        "backend": backend,
        "command": "healthmd direct reset-trust",
        "message": "No trust was removed. This destructive recovery command requires explicit confirmation.",
        "request_sent": false,
        "required": [{
            "argument": "--confirm",
            "description": "Acknowledge that every local mobile pairing will be removed."
        }],
        "before_continuing": [
            "Finish or intentionally cancel durable jobs.",
            "Record any device IDs needed for support or re-pairing.",
            "Be prepared to forget this CLI in each mobile app and pair again."
        ],
        "examples": [{"argv": ["healthmd", "direct", "reset-trust", "--confirm"]}],
        "next_actions": [
            {"command": "healthmd direct devices", "description": "Inspect current local trust first."},
            {"command": "healthmd direct reset-trust --help", "description": "Read the recovery contract."}
        ]
    })
}

fn positional(
    backend: &'static str,
    command: &'static str,
    argument: &'static str,
    description: &'static str,
    examples: &[Value],
) -> Value {
    json!({
        "schema": GUIDANCE_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "guidance",
        "backend": backend,
        "command": command,
        "message": "The command is incomplete. Supply the required identifier below; no device was contacted.",
        "request_sent": false,
        "required": [{"argument": argument, "description": description}],
        "examples": examples,
        "next_actions": [{
            "command": format!("{command} --help"),
            "description": "Read every accepted option and recovery constraint."
        }]
    })
}

pub(super) fn command_error(error: &CommandError, context: &ErrorContext) -> Value {
    let mut payload = json!({
        "schema": ERROR_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "failure",
        "backend": error.backend,
        "error": error.code,
        "message": error.message,
        "command": format!("healthmd {}", context.command),
        "help_command": format!("healthmd {} --help", context.command),
        "next_actions": recovery_actions(error.code, context.command)
    });
    if matches!(error.code, "invalid_request" | "runtime_unavailable") {
        if let Some(object) = payload.as_object_mut() {
            object.insert("request_sent".into(), Value::Bool(false));
        }
    }
    if error.code == "invalid_request" {
        let reference = match context.command {
            "export" => Some(export(context.backend, false, false)),
            "extract" => Some(extract(context.backend, false, false)),
            "query" => Some(query(context.backend, context.query_operation)),
            "resume" => Some(resume(context.backend)),
            "cancel" => Some(cancel(context.backend)),
            "direct unpair" => Some(unpair(context.backend)),
            "direct reset-trust" => Some(reset_trust(context.backend)),
            "direct" | "mcp" | "setup" => Some(group(context.backend, context.command)),
            _ => None,
        };
        if let (Some(object), Some(reference)) = (payload.as_object_mut(), reference) {
            object.insert("guidance".into(), reference);
        }
    }
    payload
}

pub(super) fn parser_error(error: &clap::Error, arguments: &[OsString]) -> Value {
    let path = command_path(arguments);
    let backend = requested_backend(arguments);
    let help_command = if path.is_empty() {
        "healthmd --help".to_owned()
    } else {
        format!("healthmd {path} --help")
    };
    let reference = if path == "query" {
        query(backend, recognized_query_operation(arguments))
    } else {
        command_reference(backend, path)
    };
    let available = available_commands(path);
    let mut payload = json!({
        "schema": ERROR_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "status": "failure",
        "backend": backend,
        "error": "invalid_request",
        "error_kind": error_kind_name(error.kind()),
        "message": parser_message(error.kind()),
        "command": if path.is_empty() { "healthmd".to_owned() } else { format!("healthmd {path}") },
        "request_sent": false,
        "help_command": help_command,
        "accepted_arguments": accepted_arguments(path),
        "next_actions": [{
            "command": help_command,
            "description": "Review the accepted syntax, constraints, and examples, then retry with only documented arguments."
        }]
    });
    if let Some(object) = payload.as_object_mut() {
        if !available.is_null() {
            object.insert("available_commands".into(), available);
        }
        if !reference.is_null() {
            object.insert("guidance".into(), reference);
        }
    }
    payload
}

fn command_reference(backend: &'static str, path: &'static str) -> Value {
    match path {
        "export" => export(backend, false, false),
        "extract" => extract(backend, false, false),
        "query" => query(backend, None),
        "resume" => resume(backend),
        "cancel" => cancel(backend),
        "direct unpair" => unpair(backend),
        "direct reset-trust" => reset_trust(backend),
        "direct" | "mcp" | "setup" => group(backend, path),
        _ => Value::Null,
    }
}

fn recovery_actions(code: &str, command: &str) -> Vec<Value> {
    let help = || {
        json!({
            "command": format!("healthmd {command} --help"),
            "description": "Review accepted arguments and examples."
        })
    };
    match code {
        "invalid_request" => vec![help()],
        "transport_unsupported" => vec![
            json!({"command_template": "healthmd --transport manual-ip <COMMAND> [OPTIONS]", "description": "Use the portable Manual IP/Tailscale transport."}),
            help(),
        ],
        "not_implemented" => vec![
            json!({"command_template": "healthmd --backend direct <COMMAND> [OPTIONS]", "description": "Use the implemented portable direct backend."}),
            help(),
        ],
        "direct_device_selection_required" => vec![
            json!({"command": "healthmd direct devices", "description": "List trusted installation UUIDs without contacting a device."}),
            json!({"command_template": "healthmd --device <DEVICE_UUID> <COMMAND> [OPTIONS]", "description": "Retry while pinning exactly one trusted source."}),
        ],
        "direct_not_paired" | "direct_device_not_paired" | "direct_device_not_found" => vec![
            json!({"command": "healthmd direct devices", "description": "Check which mobile sources are trusted locally and copy an exact installation UUID."}),
            json!({"command": "healthmd direct pair", "description": "Pair an open mobile app when no usable trust exists."}),
        ],
        "direct_trust_invalid" => vec![
            json!({"command": "healthmd direct devices", "description": "Inspect local trust before destructive recovery."}),
            json!({"command": "healthmd direct reset-trust", "description": "Review the explicit reset requirements; this invocation does not remove trust."}),
        ],
        "direct_storage_unavailable"
        | "direct_storage_outcome_unknown"
        | "direct_initialization_failed" => vec![
            json!({"command": "healthmd direct devices", "description": "Recheck the native credential store and current trust state before retrying a mutation."}),
            json!({"command": "healthmd --help", "description": "See the platform credential-store recovery guidance."}),
        ],
        "direct_pairing_failed" => vec![
            json!({"command": "healthmd direct devices", "description": "Check whether pairing completed despite an interrupted response."}),
            json!({"command": "healthmd direct pair", "description": "Retry with Health.md open and the exact one-time platform code."}),
        ],
        "direct_job_busy" => vec![
            json!({"action": "Wait for the other Health.md CLI process using this durable job to finish."}),
            json!({"command_template": "healthmd status --job <JOB_UUID>", "description": "Inspect durable state after the other process releases the job."}),
        ],
        "direct_export_paused" => vec![
            json!({"command_template": "healthmd status --job <JOB_UUID>", "description": "Inspect the durable job without changing it."}),
            json!({"command_template": "healthmd resume <JOB_UUID>", "description": "Resume the exact immutable job."}),
        ],
        "direct_cancellation_pending" => vec![
            json!({"command_template": "healthmd status --job <JOB_UUID>", "description": "Keep the source app foreground and inspect acknowledgement state."}),
        ],
        "job_not_found" | "job_expired" | "direct_job_not_resumable" => vec![
            json!({"command_template": "healthmd status --job <JOB_UUID>", "description": "Verify the exact durable job ID and current state."}),
            help(),
        ],
        "healthmd_query_failed" | "direct_source_unavailable" | "direct_source_unsupported" => {
            vec![
                json!({"action": "Keep Health.md open in the foreground on the paired mobile source."}),
                json!({"command": "healthmd status", "description": "Check pairing, transport, protected-data, and source readiness."}),
                json!({"command": "healthmd direct devices", "description": "Inspect local pairing and select a device explicitly when needed."}),
            ]
        }
        "partial_canonical_extraction" => vec![
            json!({"command_template": "healthmd extract [SAME SCOPE] --allow-partial", "description": "Emit only the explicitly retained partial data when that is acceptable."}),
            help(),
        ],
        "invalid_direct_file_receipt" | "invalid_direct_response" => vec![
            json!({"action": "Do not consume, append, merge, or manually repair the rejected result."}),
            json!({"command_template": "healthmd status --job <JOB_UUID>", "description": "Inspect durable state and resume only when the exact job remains resumable."}),
        ],
        "secure_random_unavailable" => vec![
            json!({"action": "Restore operating-system secure randomness and retry pairing; never provide a predictable replacement code."}),
            help(),
        ],
        "output_write_failed" => vec![
            json!({"action": "Verify that stdout or the requested output destination is writable and has sufficient free space."}),
            help(),
        ],
        "runtime_unavailable" => vec![
            json!({"command": "healthmd --version", "description": "Verify that the installed executable can start without running a live command."}),
            json!({"action": "Release local process/thread resources or reinstall the exact supported Health.md CLI build before retrying."}),
        ],
        _ => vec![
            json!({"command": "healthmd status", "description": "Check direct mobile readiness before retrying."}),
            help(),
        ],
    }
}

fn query_operations() -> Vec<Value> {
    definitions()
        .iter()
        .filter(|operation| operation.kind == OperationKind::Query)
        .map(|operation| {
            json!({
                "name": operation.name,
                "title": operation.title,
                "description": operation.description,
                "inspect_command": format!("healthmd query {}", operation.name),
                "schema_command": format!("healthmd mcp schema {}", operation.name)
            })
        })
        .collect()
}

fn root_commands() -> Vec<Value> {
    vec![
        json!({"command": "healthmd status", "description": "Check direct mobile readiness or a durable job."}),
        json!({"command": "healthmd export", "description": "Inspect raw and generated-file export modes."}),
        json!({"command": "healthmd extract", "description": "Inspect canonical extraction scope."}),
        json!({"command": "healthmd query", "description": "List fixed typed query operations."}),
        json!({"command": "healthmd resume", "description": "Inspect durable resume arguments."}),
        json!({"command": "healthmd cancel", "description": "Inspect explicit cancellation arguments."}),
        json!({"command": "healthmd direct", "description": "List pairing and trust commands."}),
        json!({"command": "healthmd mcp", "description": "List MCP serve and schema commands."}),
        json!({"command": "healthmd setup", "description": "List supported AI-host setup commands."}),
    ]
}

fn available_commands(path: &'static str) -> Value {
    match path {
        "" => Value::Array(root_commands()),
        "direct" | "mcp" | "setup" => group("direct", path)
            .get("available_commands")
            .cloned()
            .unwrap_or(Value::Null),
        "query" => Value::Array(query_operations()),
        _ => Value::Null,
    }
}

fn accepted_arguments(path: &str) -> Value {
    let arguments: &[&str] = match path {
        "status" => &["--job <JOB_UUID>"],
        "export" => &[
            "--yesterday | --last <DAYS> | --from <DATE> --to <DATE> | --all",
            "--raw | --destination <DIR>",
            "--output <FILE>",
            "--profile <PROFILE_ID>",
            "--use-device-settings",
            "--metric <ID>",
            "--category <NAME>",
            "--all-metrics",
            "--detail <summary|lossless>",
            "--provider <ID>",
            "--raw-format <json|ndjson>",
            "--allow-partial",
            "--timeout <SECONDS>",
        ],
        "extract" => &[
            "--yesterday | --last <DAYS> | --from <DATE> --to <DATE> | --all",
            "--metric <ID> | --category <NAME> | --object <ALIAS> | --all-metrics",
            "--field <JSON_POINTER>",
            "--source <ID>",
            "--detail <summary|lossless>",
            "--format <json|jsonl>",
            "--output <FILE>",
            "--allow-partial",
            "--timeout <SECONDS>",
        ],
        "query" => &["[OPERATION]", "--arguments <JSON>", "--timeout <SECONDS>"],
        "resume" => &[
            "[JOB_UUID]",
            "--output <FILE>",
            "--format <json|jsonl>",
            "--allow-partial",
            "--timeout <SECONDS>",
        ],
        "cancel" => &["[JOB_UUID]"],
        "direct pair" => &[
            "--pairing-code <6 DIGITS>",
            "--android-pairing-code <20 DIGITS>",
            "--timeout <SECONDS>",
        ],
        "direct unpair" => &["[DEVICE_UUID]"],
        "direct reset-trust" => &["--confirm"],
        "mcp schema" => &["[TOOL]"],
        "mcp serve" | "mcp serve-read-only" => &["--timeout-seconds <SECONDS>"],
        "setup codex" => &["--skip-pairing", "--pairing-timeout <SECONDS>"],
        _ => &[],
    };
    json!(arguments)
}

fn parser_message(kind: ErrorKind) -> &'static str {
    match kind {
        ErrorKind::InvalidSubcommand => {
            "That subcommand is not available. Choose one of the documented commands below."
        }
        ErrorKind::UnknownArgument => {
            "One argument is not recognized for this command. Review the accepted arguments below."
        }
        ErrorKind::InvalidValue | ErrorKind::ValueValidation => {
            "One argument has an invalid value. Review its documented format and allowed values."
        }
        ErrorKind::ArgumentConflict => {
            "Two supplied arguments cannot be used together. Choose one documented request shape."
        }
        ErrorKind::MissingRequiredArgument | ErrorKind::MissingSubcommand => {
            "The command is incomplete. Add one of the required arguments or subcommands shown below."
        }
        ErrorKind::TooManyValues
        | ErrorKind::TooFewValues
        | ErrorKind::WrongNumberOfValues
        | ErrorKind::NoEquals => {
            "One argument has the wrong number or form of values. Review the accepted syntax below."
        }
        _ => "The command could not be parsed safely. Review the documented syntax below.",
    }
}

const fn error_kind_name(kind: ErrorKind) -> &'static str {
    match kind {
        ErrorKind::InvalidValue => "invalid_value",
        ErrorKind::UnknownArgument => "unknown_argument",
        ErrorKind::InvalidSubcommand => "invalid_subcommand",
        ErrorKind::NoEquals => "missing_equals",
        ErrorKind::ValueValidation => "value_validation",
        ErrorKind::TooManyValues => "too_many_values",
        ErrorKind::TooFewValues => "too_few_values",
        ErrorKind::WrongNumberOfValues => "wrong_number_of_values",
        ErrorKind::ArgumentConflict => "argument_conflict",
        ErrorKind::MissingRequiredArgument => "missing_required_argument",
        ErrorKind::MissingSubcommand => "missing_subcommand",
        ErrorKind::DisplayHelp => "display_help",
        ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand => "display_help_on_missing",
        ErrorKind::DisplayVersion => "display_version",
        ErrorKind::Io => "io",
        ErrorKind::Format => "format",
        _ => "unknown",
    }
}

fn recognized_query_operation(arguments: &[OsString]) -> Option<&'static str> {
    arguments
        .iter()
        .filter_map(|argument| argument.to_str())
        .find_map(|argument| {
            definition(argument)
                .filter(|candidate| candidate.kind == OperationKind::Query)
                .map(|candidate| candidate.name)
        })
}

fn requested_backend(arguments: &[OsString]) -> &'static str {
    let mut values = arguments.iter().filter_map(|argument| argument.to_str());
    while let Some(value) = values.next() {
        if value == "--backend" {
            return match values.next() {
                Some("mac-app") => "mac-app",
                _ => "direct",
            };
        }
        if value == "--backend=mac-app" {
            return "mac-app";
        }
    }
    "direct"
}

fn command_path(arguments: &[OsString]) -> &'static str {
    let values = arguments
        .iter()
        .filter_map(|argument| argument.to_str())
        .collect::<Vec<_>>();
    let Some((index, command)) = values.iter().enumerate().find_map(|(index, value)| {
        matches!(
            *value,
            "status"
                | "export"
                | "extract"
                | "query"
                | "resume"
                | "cancel"
                | "direct"
                | "mcp"
                | "setup"
        )
        .then_some((index, *value))
    }) else {
        return "";
    };
    match command {
        "direct" => values[index + 1..]
            .iter()
            .find_map(|value| match *value {
                "pair" => Some("direct pair"),
                "devices" => Some("direct devices"),
                "unpair" => Some("direct unpair"),
                "reset-trust" => Some("direct reset-trust"),
                _ => None,
            })
            .unwrap_or("direct"),
        "mcp" => values[index + 1..]
            .iter()
            .find_map(|value| match *value {
                "serve" => Some("mcp serve"),
                "serve-read-only" => Some("mcp serve-read-only"),
                #[cfg(feature = "streamable-http")]
                "serve-http" => Some("mcp serve-http"),
                "schema" => Some("mcp schema"),
                _ => None,
            })
            .unwrap_or("mcp"),
        "setup" => values[index + 1..]
            .iter()
            .find_map(|value| (*value == "codex").then_some("setup codex"))
            .unwrap_or("setup"),
        "status" => "status",
        "export" => "export",
        "extract" => "extract",
        "query" => "query",
        "resume" => "resume",
        "cancel" => "cancel",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser as _;

    #[test]
    fn query_guidance_embeds_schema_and_executable_argv() {
        let value = query("direct", Some("healthmd_sleep_sessions"));
        assert_eq!(value["status"], "guidance");
        assert_eq!(value["request_sent"], false);
        assert_eq!(
            value.pointer("/input_schema/required/0"),
            Some(&json!("dates"))
        );
        assert_eq!(
            value.pointer("/examples/0/argv/2"),
            Some(&json!("healthmd_sleep_sessions"))
        );
    }

    #[test]
    fn unknown_query_operation_is_not_echoed_and_lists_fixed_choices() {
        let private = "synthetic-private-health-value";
        let encoded = serde_json::to_string(&query("direct", Some(private))).unwrap();
        assert!(!encoded.contains(private));
        assert!(encoded.contains("healthmd_sleep_sessions"));
    }

    #[test]
    fn parser_errors_never_echo_user_values() {
        let private = "synthetic-private-health-value";
        let error = Cli::try_parse_from(["healthmd", "export", "--timeout", private])
            .expect_err("timeout must reject private invalid input");
        let payload = parser_error(
            &error,
            &[
                OsString::from("export"),
                OsString::from("--timeout"),
                OsString::from(private),
            ],
        );
        let encoded = serde_json::to_string(&payload).unwrap();
        assert!(!encoded.contains(private));
        assert!(encoded.contains("healthmd export --help"));
        assert!(encoded.contains("accepted_arguments"));
    }

    #[test]
    fn incomplete_export_guidance_explains_both_safe_modes() {
        let value = export("direct", true, true);
        assert_eq!(value["status"], "guidance");
        assert_eq!(value["missing"].as_array().map(Vec::len), Some(2));
        let encoded = serde_json::to_string(&value).unwrap();
        assert!(encoded.contains("--destination"));
        assert!(encoded.contains("--raw"));
        assert!(encoded.contains("--yesterday"));
    }

    #[test]
    fn command_error_adds_bounded_recovery_actions() {
        let context = ErrorContext {
            backend: "direct",
            command: "query",
            query_operation: Some("healthmd_sleep_sessions"),
        };
        let error = CommandError {
            backend: "direct",
            code: "invalid_request",
            message: "dates is required".into(),
        };
        let value = command_error(&error, &context);
        assert_eq!(value["schema"], ERROR_SCHEMA);
        assert_eq!(value["help_command"], "healthmd query --help");
        assert_eq!(
            value.pointer("/guidance/input_schema/required/0"),
            Some(&json!("dates"))
        );
    }

    #[test]
    fn direct_command_path_is_inferred_without_retaining_other_arguments() {
        let path = command_path(&[
            OsString::from("--backend"),
            OsString::from("direct"),
            OsString::from("direct"),
            OsString::from("unpair"),
            OsString::from("not-a-uuid"),
        ]);
        assert_eq!(path, "direct unpair");
    }

    #[test]
    fn error_context_recognizes_only_fixed_query_names() {
        let parsed = Cli::try_parse_from([
            "healthmd",
            "query",
            "healthmd_sleep_sessions",
            "--arguments",
            "{}",
        ])
        .unwrap();
        let context = ErrorContext::from_cli(&parsed);
        assert_eq!(context.query_operation, Some("healthmd_sleep_sessions"));

        let unknown = Cli::try_parse_from([
            "healthmd",
            "query",
            "synthetic-private-health-value",
            "--arguments",
            "{}",
        ])
        .unwrap();
        let context = ErrorContext::from_cli(&unknown);
        assert_eq!(context.query_operation, None);
    }

    #[test]
    fn direct_group_contains_pairing_and_trust_choices() {
        let value = group("direct", "direct");
        let commands = value["available_commands"].as_array().unwrap();
        assert_eq!(commands.len(), 4);
        assert!(
            commands.iter().any(|command| {
                command["command"] == Value::String("healthmd direct pair".into())
            })
        );
    }

    #[test]
    fn documented_extract_object_aliases_are_all_accepted() {
        for alias in CANONICAL_OBJECT_ALIASES {
            assert!(
                healthmd_operations::canonical_object_path(alias).is_ok(),
                "documented alias should resolve: {alias}"
            );
        }
    }

    #[test]
    fn reset_trust_guidance_is_non_mutating() {
        let value = reset_trust("direct");
        assert_eq!(value["request_sent"], false);
        assert_eq!(
            value.pointer("/required/0/argument"),
            Some(&json!("--confirm"))
        );
    }

    #[test]
    fn command_path_defaults_to_root_for_unknown_input() {
        assert_eq!(command_path(&[OsString::from("unknown")]), "");
    }
}
