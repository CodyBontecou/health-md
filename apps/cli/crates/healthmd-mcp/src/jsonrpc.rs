use std::{
    collections::HashSet,
    sync::{Arc, Mutex},
};

use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use crate::{CallerIdentity, HealthMdSession, apps};

const MAXIMUM_REQUEST_ID_BYTES: usize = 128;
const MAXIMUM_USED_REQUEST_IDS: usize = 16_384;
const PROTOCOLS: &[&str] = &["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"];

/// Transport-neutral JSON-RPC dispatcher shared by the bounded stdio and Streamable HTTP
/// adapters. Both transports dispatch into the same [`HealthMdSession`] application contract.
pub struct JsonRpcSession {
    session: Arc<HealthMdSession>,
    used_request_ids: Mutex<HashSet<String>>,
}

impl JsonRpcSession {
    pub fn new(session: HealthMdSession) -> Self {
        Self {
            session: Arc::new(session),
            used_request_ids: Mutex::new(HashSet::new()),
        }
    }

    pub async fn handle(&self, input: &str, cancellation: CancellationToken) -> Option<String> {
        self.handle_with_caller(input, cancellation, None, None, None)
            .await
    }

    pub async fn handle_with_notifications(
        &self,
        input: &str,
        cancellation: CancellationToken,
        notifications: tokio::sync::mpsc::Sender<String>,
    ) -> Option<String> {
        self.handle_with_caller(input, cancellation, None, None, Some(notifications))
            .await
    }

    /// Dispatch with the caller resolved from the current authenticated transport request.
    ///
    /// OAuth transports must call this for every request so a session cannot retain grants from
    /// the token that initialized it.
    pub async fn handle_as(
        &self,
        input: &str,
        cancellation: CancellationToken,
        caller: CallerIdentity,
        session_id: Option<String>,
    ) -> Option<String> {
        self.handle_with_caller(input, cancellation, Some(caller), session_id, None)
            .await
    }

    async fn handle_with_caller(
        &self,
        input: &str,
        cancellation: CancellationToken,
        caller: Option<CallerIdentity>,
        session_id: Option<String>,
        notifications: Option<tokio::sync::mpsc::Sender<String>>,
    ) -> Option<String> {
        let request: Value = match serde_json::from_str(input) {
            Ok(value) => value,
            Err(_) => return Some(response_error(Value::Null, -32_700, "Parse error")),
        };
        let Some(object) = request.as_object() else {
            return Some(response_error(Value::Null, -32_600, "Invalid request"));
        };
        if object.get("jsonrpc").and_then(Value::as_str) != Some("2.0") {
            return Some(response_error(Value::Null, -32_600, "Invalid request"));
        }
        let id = object.get("id").cloned();
        let Some(method) = object.get("method").and_then(Value::as_str) else {
            return Some(response_error(
                id.unwrap_or(Value::Null),
                -32_600,
                "Invalid request",
            ));
        };
        let Some(id) = id else {
            // MCP notifications currently require no application-side dispatch. In particular,
            // initialization acknowledgement and cancellation are handled by their transports.
            return None;
        };
        let Ok(key) = request_id_key(&id) else {
            return Some(response_error(id, -32_600, "Invalid request"));
        };
        {
            let mut used = self
                .used_request_ids
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if used.contains(&key) {
                return Some(response_error(id, -32_600, "Duplicate request identifier"));
            }
            if used.len() >= MAXIMUM_USED_REQUEST_IDS {
                return Some(response_error(
                    id,
                    -32_001,
                    "Session request limit exceeded",
                ));
            }
            used.insert(key);
        }
        let params = object.get("params").cloned().unwrap_or_else(|| json!({}));
        let result = match method {
            "initialize" => self.initialize(&params),
            "ping" => Ok(json!({})),
            "tools/list" => Ok(json!({"tools": self.session.list_tools()})),
            "resources/list" if self.session.ui_enabled() => {
                Ok(json!({"resources": self.session.list_resources()}))
            }
            "resources/read" if self.session.ui_enabled() => {
                let uri = params
                    .get("uri")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                self.session
                    .read_resource(uri)
                    .map(|content| json!({"contents": [content]}))
            }
            "tools/call" => {
                self.call_tool_request(caller, &params, cancellation, session_id, notifications)
                    .await
            }
            _ => Err(crate::application::ApplicationError {
                code: -32_601,
                message: "Method not found",
            }),
        };
        Some(match result {
            Ok(result) => response_success(id, result),
            Err(error) => response_error(id, error.code, error.message),
        })
    }

    async fn call_tool_request(
        &self,
        caller: Option<CallerIdentity>,
        params: &Value,
        cancellation: CancellationToken,
        session_id: Option<String>,
        notifications: Option<tokio::sync::mpsc::Sender<String>>,
    ) -> Result<Value, crate::application::ApplicationError> {
        let name = params
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let arguments = params
            .get("arguments")
            .cloned()
            .unwrap_or_else(|| json!({}));
        let progress_token = params
            .pointer("/_meta/progressToken")
            .filter(|token| valid_progress_token(token))
            .cloned();
        let (progress, forwarder) = match (progress_token, notifications) {
            (Some(token), Some(notifications)) => {
                let (sender, mut receiver) = tokio::sync::mpsc::channel(16);
                let forwarder = tokio::spawn(async move {
                    while let Some(update) = receiver.recv().await {
                        let _ = notifications
                            .send(progress_notification(&token, &update))
                            .await;
                    }
                });
                (Some(sender), Some(forwarder))
            }
            _ => (None, None),
        };
        let result = if let Some(caller) = caller {
            self.session
                .call_tool_as_with_progress(
                    caller,
                    name,
                    arguments,
                    cancellation,
                    session_id,
                    progress,
                )
                .await
        } else {
            self.session
                .call_tool_with_progress(name, arguments, cancellation, session_id, progress)
                .await
        };
        if let Some(forwarder) = forwarder {
            let _ = forwarder.await;
        }
        result
    }

    fn initialize(&self, params: &Value) -> Result<Value, crate::application::ApplicationError> {
        let version = params
            .get("protocolVersion")
            .and_then(Value::as_str)
            .filter(|version| PROTOCOLS.contains(version))
            .ok_or(crate::application::ApplicationError {
                code: -32_602,
                message: "Unsupported MCP protocol version",
            })?;
        let ui = params
            .get("capabilities")
            .and_then(|value| value.get("extensions"))
            .and_then(|value| value.get(apps::EXTENSION_ID))
            .and_then(|value| value.get("mimeTypes"))
            .and_then(Value::as_array)
            .is_some_and(|values| {
                values
                    .iter()
                    .any(|value| value.as_str() == Some(apps::MIME_TYPE))
            });
        self.session.set_ui_enabled(ui);
        let mut capabilities = json!({"tools": {"listChanged": false}});
        if ui {
            capabilities["resources"] = json!({"subscribe": false, "listChanged": false});
            capabilities["extensions"] =
                json!({apps::EXTENSION_ID: {"mimeTypes": [apps::MIME_TYPE]}});
        }
        Ok(json!({
            "protocolVersion": version,
            "capabilities": capabilities,
            "serverInfo": {
                "name": "healthmd-mcp",
                "version": env!("CARGO_PKG_VERSION")
            },
            "instructions": self.session.instructions()
        }))
    }
}

fn valid_progress_token(value: &Value) -> bool {
    match value {
        Value::String(value) => value.len() <= MAXIMUM_REQUEST_ID_BYTES,
        Value::Number(value) => value.as_i64().is_some(),
        _ => false,
    }
}

fn progress_notification(token: &Value, update: &healthmd_operations::ProgressUpdate) -> String {
    let mut params = json!({
        "progressToken": token,
        "progress": update.progress,
        "message": update.message
    });
    if let Some(total) = update.total {
        params["total"] = Value::from(total);
    }
    serde_json::to_string(&json!({
        "jsonrpc": "2.0",
        "method": "notifications/progress",
        "params": params
    }))
    .expect("progress notification")
}

pub(crate) fn request_id_key(value: &Value) -> Result<String, ()> {
    let valid = match value {
        Value::String(value) => value.len() <= MAXIMUM_REQUEST_ID_BYTES,
        Value::Number(value) => value.as_i64().is_some(),
        _ => false,
    };
    if !valid {
        return Err(());
    }
    let key = serde_json::to_string(value).map_err(|_| ())?;
    if key.len() > MAXIMUM_REQUEST_ID_BYTES {
        return Err(());
    }
    Ok(key)
}

#[allow(clippy::needless_pass_by_value)]
fn response_success(id: Value, result: Value) -> String {
    serde_json::to_string(&json!({"jsonrpc": "2.0", "id": id, "result": result}))
        .expect("JSON response")
}

#[allow(clippy::needless_pass_by_value)]
fn response_error(id: Value, code: i64, message: &str) -> String {
    serde_json::to_string(&json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": {"code": code, "message": message}
    }))
    .expect("JSON response")
}

#[cfg(test)]
mod tests {
    use async_trait::async_trait;

    use super::*;
    use crate::{
        BackendCapabilities, BackendError, CallContext, CallerIdentity, HealthDataBackend,
        HealthMdApplication, QueryPageRequest, SurfaceProfile,
    };

    struct FixtureBackend;

    #[async_trait]
    impl HealthDataBackend for FixtureBackend {
        fn capabilities(&self) -> BackendCapabilities {
            BackendCapabilities {
                source_kind: "fixture".to_owned(),
                transport: "fixture".to_owned(),
                supports_queries: true,
                supports_local_file_exports: false,
                requires_foreground_source: false,
                instructions: "Use the fixture.".to_owned(),
            }
        }

        async fn readiness(&self, context: &CallContext) -> Result<Value, BackendError> {
            context.report_progress(healthmd_operations::ProgressUpdate {
                progress: 10,
                total: Some(120),
                message: "Waiting for the paired source.".to_owned(),
            });
            Ok(json!({"ready": true}))
        }

        async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
            self.readiness(context).await
        }

        async fn query_page(
            &self,
            _context: &CallContext,
            _request: QueryPageRequest,
        ) -> Result<Value, BackendError> {
            Ok(json!({
                "schema": "healthmd.query_response",
                "schema_version": 1,
                "items": [],
                "next_cursor": null
            }))
        }
    }

    fn dispatcher() -> JsonRpcSession {
        let application = Arc::new(HealthMdApplication::new(
            Arc::new(FixtureBackend),
            SurfaceProfile::RemoteReadOnly,
        ));
        JsonRpcSession::new(application.session(CallerIdentity::loopback()))
    }

    #[tokio::test]
    async fn initializes_and_returns_the_shared_catalog() {
        let dispatcher = dispatcher();
        let initialize = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let initialize: Value = serde_json::from_str(&initialize).unwrap();
        assert_eq!(
            initialize.pointer("/result/protocolVersion"),
            Some(&json!("2025-11-25"))
        );
        let tools = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let tools: Value = serde_json::from_str(&tools).unwrap();
        assert_eq!(
            tools
                .pointer("/result/tools")
                .and_then(Value::as_array)
                .map(Vec::len),
            Some(13)
        );
    }

    #[tokio::test]
    async fn forwards_bounded_mcp_progress_notifications() {
        let dispatcher = dispatcher();
        let (sender, mut receiver) = tokio::sync::mpsc::channel(4);
        let response = dispatcher
            .handle_with_notifications(
                r#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"healthmd_status","arguments":{},"_meta":{"progressToken":"wake-7"}}}"#,
                CancellationToken::new(),
                sender,
            )
            .await
            .unwrap();
        assert!(serde_json::from_str::<Value>(&response).unwrap()["result"].is_object());
        let notification: Value = serde_json::from_str(&receiver.recv().await.unwrap()).unwrap();
        assert_eq!(notification["method"], json!("notifications/progress"));
        assert_eq!(notification["params"]["progressToken"], json!("wake-7"));
        assert_eq!(notification["params"]["progress"], json!(10));
        assert_eq!(notification["params"]["total"], json!(120));
    }

    #[tokio::test]
    async fn ignores_progress_updates_without_a_valid_caller_token() {
        let dispatcher = dispatcher();
        let (sender, mut receiver) = tokio::sync::mpsc::channel(4);
        let response = dispatcher
            .handle_with_notifications(
                r#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"healthmd_status","arguments":{},"_meta":{"progressToken":{"invalid":true}}}}"#,
                CancellationToken::new(),
                sender,
            )
            .await
            .unwrap();
        assert!(serde_json::from_str::<Value>(&response).unwrap()["result"].is_object());
        assert!(receiver.try_recv().is_err());
    }

    #[tokio::test]
    async fn request_identifiers_are_scalar_bounded_and_never_reused() {
        let dispatcher = dispatcher();
        let first = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":"request-1","method":"tools/list"}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        assert!(
            serde_json::from_str::<Value>(&first)
                .unwrap()
                .get("result")
                .is_some()
        );

        let duplicate = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":"request-1","method":"tools/list"}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&duplicate)
                .unwrap()
                .pointer("/error/code"),
            Some(&json!(-32_600))
        );

        for invalid in [
            r#"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#.to_owned(),
            r#"{"jsonrpc":"2.0","id":1.5,"method":"tools/list"}"#.to_owned(),
            r#"{"jsonrpc":"2.0","id":{},"method":"tools/list"}"#.to_owned(),
            format!(
                "{{\"jsonrpc\":\"2.0\",\"id\":\"{}\",\"method\":\"tools/list\"}}",
                "x".repeat(MAXIMUM_REQUEST_ID_BYTES + 1)
            ),
        ] {
            let response = dispatcher
                .handle(&invalid, CancellationToken::new())
                .await
                .unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(&response)
                    .unwrap()
                    .pointer("/error/code"),
                Some(&json!(-32_600))
            );
        }
    }
}
