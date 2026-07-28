mod app;
mod chart;
mod server;
mod tools;

use std::{collections::HashMap, fmt, io::BufRead as _, sync::Arc, time::Duration};

use clap::Args;
use healthmd_client::direct::DirectClient;
use serde_json::{Value, json};
use tokio::{
    io::{AsyncWriteExt as _, BufWriter},
    sync::{mpsc, watch},
    task::JoinSet,
};
use uuid::Uuid;

use server::{Configuration, Server};

const MAXIMUM_INPUT_BYTES: usize = 2 * 1_024 * 1_024;
const MAXIMUM_IN_FLIGHT_REQUESTS: usize = 64;

#[derive(Clone, Debug, Args)]
pub struct ServeOptions {
    /// A paired iPhone device UUID. Required only when multiple devices are paired.
    #[arg(long)]
    pub device_id: Option<Uuid>,
    /// Direct iPhone listener port.
    #[arg(long, default_value_t = 17_647)]
    pub port: u16,
    /// Default timeout for readiness and query operations.
    #[arg(long, default_value_t = 1_200)]
    pub timeout_seconds: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ServeError;

impl fmt::Display for ServeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("direct client initialization failed")
    }
}

impl std::error::Error for ServeError {}

/// Return the complete supported MCP tool catalog or one named tool without opening credentials or a
/// network listener.
///
/// # Errors
///
/// Returns a stable message when `tool_name` is not part of Health.md's fixed surface.
pub fn tool_catalog(tool_name: Option<&str>) -> Result<Value, String> {
    let tools = tools::list(false);
    let guidance = json!({
        "typed_tools_are_preferred": true,
        "sleep_tool": "healthmd_sleep_sessions",
        "workout_tool": "healthmd_workouts",
        "metric_series_tool": "healthmd_metric_chart",
        "note": "Call typed MCP tools directly. The shell `healthmd extract` command returns a different canonical projection and is not the typed query API."
    });
    if let Some(name) = tool_name {
        let tool = tools
            .into_iter()
            .find(|tool| tool.get("name").and_then(Value::as_str) == Some(name))
            .ok_or_else(|| format!("unknown fixed MCP tool: {name}"))?;
        return Ok(json!({
            "schema": "healthmd.mcp_tool_schema",
            "schema_version": 1,
            "guidance": guidance,
            "tool": tool
        }));
    }
    Ok(json!({
        "schema": "healthmd.mcp_tool_catalog",
        "schema_version": 1,
        "guidance": guidance,
        "tools": tools
    }))
}

/// Serve the fixed Health.md MCP surface over newline-delimited JSON-RPC stdio.
///
/// The normal entry point is `healthmd mcp serve`, which deliberately uses the same installed,
/// signed executable identity that owns pairing trust. `healthmd-mcp` remains a compatibility
/// launcher that delegates to that command.
///
/// # Errors
///
/// Returns [`ServeError`] when native direct-client state cannot be initialized.
#[allow(clippy::too_many_lines)]
pub async fn serve(options: ServeOptions) -> Result<(), ServeError> {
    let client = DirectClient::open().map_err(|_| ServeError)?;
    let server = Arc::new(Server::new(
        client,
        Configuration {
            device_id: options.device_id,
            port: options.port,
            timeout: Duration::from_secs(options.timeout_seconds),
        },
    ));

    let (line_sender, mut line_receiver) = mpsc::channel::<Vec<u8>>(32);
    std::thread::spawn(move || {
        let stdin = std::io::stdin();
        let mut reader = stdin.lock();
        let mut line = Vec::new();
        let mut overflow = false;
        loop {
            let Ok(available) = reader.fill_buf() else {
                break;
            };
            if available.is_empty() {
                if !line.is_empty() || overflow {
                    let value = if overflow { b"{".to_vec() } else { line };
                    let _ = line_sender.blocking_send(value);
                }
                break;
            }
            let newline = available.iter().position(|byte| *byte == b'\n');
            let consumed = newline.map_or(available.len(), |index| index + 1);
            let content = &available[..newline.unwrap_or(available.len())];
            if !overflow {
                if line.len().saturating_add(content.len()) > MAXIMUM_INPUT_BYTES {
                    overflow = true;
                    line.clear();
                } else {
                    line.extend_from_slice(content);
                }
            }
            reader.consume(consumed);
            if newline.is_some() {
                let value = if overflow {
                    b"{".to_vec()
                } else {
                    std::mem::take(&mut line)
                };
                overflow = false;
                if line_sender.blocking_send(value).is_err() {
                    break;
                }
            }
        }
    });

    let mut output = BufWriter::new(tokio::io::stdout());
    let mut tasks: JoinSet<(Option<String>, Option<String>)> = JoinSet::new();
    let mut in_flight: HashMap<String, watch::Sender<bool>> = HashMap::new();
    let mut input_open = true;

    while input_open || !tasks.is_empty() {
        tokio::select! {
            line = line_receiver.recv(), if input_open => {
                let Some(line) = line else {
                    input_open = false;
                    for sender in in_flight.values() {
                        let _ = sender.send(true);
                    }
                    continue
                };
                let line = String::from_utf8_lossy(&line).trim().to_owned();
                if line.is_empty() { continue; }
                let parsed: Option<Value> = serde_json::from_str(&line).ok();
                if parsed.as_ref().and_then(|value| value.get("method")).and_then(Value::as_str)
                    == Some("notifications/cancelled")
                {
                    if let Some(key) = parsed.as_ref().and_then(|value| value.pointer("/params/requestId")).map(request_key) {
                        if let Some(sender) = in_flight.get(&key) {
                            let _ = sender.send(true);
                        }
                    }
                    continue;
                }
                if parsed.as_ref().and_then(|value| value.get("id")).is_none()
                    && parsed.as_ref().and_then(|value| value.get("method")).is_some()
                {
                    continue;
                }
                let id = parsed.as_ref().and_then(|value| value.get("id")).cloned();
                let key = id.as_ref().map(request_key);
                if key.is_none() {
                    if let Some(response) = server.handle(&line, watch::channel(false).1).await {
                        write_line(&mut output, &response).await;
                    }
                    continue;
                }
                if key.as_ref().is_some_and(|key| in_flight.contains_key(key)) {
                    write_line(&mut output, &rpc_error_response(
                        id.as_ref(),
                        -32600,
                        "Duplicate request identifier",
                    )).await;
                    continue;
                }
                if at_capacity(in_flight.len()) {
                    write_line(&mut output, &rpc_error_response(
                        id.as_ref(),
                        -32001,
                        "Server overloaded",
                    )).await;
                    continue;
                }
                let is_initialize = parsed.as_ref().and_then(|value| value.get("method")).and_then(Value::as_str) == Some("initialize");
                let (sender, receiver) = watch::channel(false);
                if let Some(key) = key.as_ref() { in_flight.insert(key.clone(), sender); }
                if is_initialize {
                    let response = server.handle(&line, receiver).await;
                    if let Some(key) = key.as_ref() { in_flight.remove(key); }
                    if let Some(response) = response { write_line(&mut output, &response).await; }
                } else {
                    let server = Arc::clone(&server);
                    tasks.spawn(async move { (key, server.handle(&line, receiver).await) });
                }
            }
            completion = tasks.join_next(), if !tasks.is_empty() => {
                if let Some(Ok((key, response))) = completion {
                    if let Some(key) = key { in_flight.remove(&key); }
                    if let Some(response) = response { write_line(&mut output, &response).await; }
                }
            }
        }
    }
    Ok(())
}

async fn write_line(output: &mut BufWriter<tokio::io::Stdout>, value: &str) {
    if output.write_all(value.as_bytes()).await.is_err() {
        return;
    }
    if output.write_all(b"\n").await.is_err() {
        return;
    }
    let _ = output.flush().await;
}

fn request_key(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "null".to_owned())
}

fn rpc_error_response(id: Option<&Value>, code: i64, message: &str) -> String {
    serde_json::to_string(&json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": {"code": code, "message": message}
    }))
    .unwrap_or_else(|_| {
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}".to_owned()
    })
}

const fn at_capacity(in_flight: usize) -> bool {
    in_flight >= MAXIMUM_IN_FLIGHT_REQUESTS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stdio_admission_is_bounded() {
        assert!(!at_capacity(MAXIMUM_IN_FLIGHT_REQUESTS - 1));
        assert!(at_capacity(MAXIMUM_IN_FLIGHT_REQUESTS));
        assert!(at_capacity(usize::MAX));
    }

    #[test]
    fn schema_catalog_is_local_exact_and_tool_scoped() {
        let sleep = tool_catalog(Some("healthmd_sleep_sessions")).expect("sleep schema");
        assert_eq!(sleep["schema"], "healthmd.mcp_tool_schema");
        assert_eq!(
            sleep.pointer("/tool/name"),
            Some(&json!("healthmd_sleep_sessions"))
        );
        assert_eq!(
            sleep
                .pointer("/tool/inputSchema/properties/dates/oneOf")
                .and_then(Value::as_array)
                .map(Vec::len),
            Some(2)
        );
        assert!(tool_catalog(Some("healthmd_not_a_tool")).is_err());
    }
}
