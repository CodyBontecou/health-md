mod direct_backend;

#[cfg(feature = "streamable-http")]
pub use healthmd_mcp::transport::streamable_http::{HttpServerError, HttpServerOptions};

use std::{collections::HashMap, fmt, io::BufRead as _, sync::Arc};

use clap::Args;
use serde_json::{Value, json};
use tokio::{
    io::{AsyncWriteExt as _, BufWriter},
    sync::mpsc,
    task::JoinSet,
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

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

#[cfg(feature = "oauth-resource-server")]
#[derive(Clone, Debug)]
pub struct HttpOAuthOptions {
    pub resource: url::Url,
    pub issuer: url::Url,
    pub jwks_uri: url::Url,
    pub owner_subject: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ServeError;

impl fmt::Display for ServeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("direct client initialization failed")
    }
}

impl std::error::Error for ServeError {}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum QueryError {
    DirectInitialization,
    InvalidArguments,
    Backend(healthmd_operations::BackendError),
}

impl fmt::Display for QueryError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DirectInitialization => {
                formatter.write_str("direct client initialization failed")
            }
            Self::InvalidArguments => formatter.write_str("invalid typed query arguments"),
            Self::Backend(error) => formatter.write_str(&error.message),
        }
    }
}

impl std::error::Error for QueryError {}

#[cfg(feature = "streamable-http")]
#[derive(Debug)]
pub enum HttpServeError {
    Direct(ServeError),
    Http(HttpServerError),
    #[cfg(feature = "oauth-resource-server")]
    OAuthConfiguration(healthmd_mcp::auth::OAuthConfigurationError),
    #[cfg(feature = "oauth-resource-server")]
    OAuthVerifier(healthmd_mcp::auth::AuthorizationError),
}

#[cfg(feature = "streamable-http")]
impl fmt::Display for HttpServeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Direct(error) => error.fmt(formatter),
            Self::Http(error) => error.fmt(formatter),
            #[cfg(feature = "oauth-resource-server")]
            Self::OAuthConfiguration(error) => error.fmt(formatter),
            #[cfg(feature = "oauth-resource-server")]
            Self::OAuthVerifier(error) => error.fmt(formatter),
        }
    }
}

#[cfg(feature = "streamable-http")]
impl std::error::Error for HttpServeError {}

/// Return the complete supported MCP tool catalog or one named tool without opening credentials or a
/// network listener.
///
/// # Errors
///
/// Returns a stable message when `tool_name` is not part of Health.md's fixed surface.
pub fn tool_catalog(tool_name: Option<&str>) -> Result<Value, String> {
    healthmd_mcp::tool_catalog(healthmd_mcp::SurfaceProfile::LocalDirect, tool_name)
}

/// Execute one canonical typed query without an MCP transport envelope.
///
/// CLI and MCP adapters both normalize through the shared operation registry and traverse pages
/// through [`healthmd_operations::HealthOperations`].
///
/// # Errors
///
/// Returns a stable error when direct state is unavailable, arguments are invalid, or iPhone query
/// execution fails.
pub async fn query(
    options: ServeOptions,
    operation: &str,
    arguments: Value,
    cancellation: CancellationToken,
) -> Result<Value, QueryError> {
    let invocation = healthmd_operations::query_invocation(operation, &arguments)
        .map_err(|_| QueryError::InvalidArguments)?;
    let backend = direct_backend::DirectIphoneBackend::open(&options)
        .map_err(|_| QueryError::DirectInitialization)?;
    execute_query_invocation(Arc::new(backend), invocation, cancellation).await
}

/// Execute the CLI query adapter against an injected transport-neutral backend.
///
/// This is also the parity seam used to prove that CLI and MCP normalize and execute identical
/// operation inputs.
///
/// # Errors
///
/// Returns a stable error for invalid arguments or backend failure.
pub async fn execute_query_operation(
    backend: Arc<dyn healthmd_operations::HealthDataBackend>,
    operation: &str,
    arguments: &Value,
    cancellation: CancellationToken,
) -> Result<Value, QueryError> {
    let invocation = healthmd_operations::query_invocation(operation, arguments)
        .map_err(|_| QueryError::InvalidArguments)?;
    execute_query_invocation(backend, invocation, cancellation).await
}

async fn execute_query_invocation(
    backend: Arc<dyn healthmd_operations::HealthDataBackend>,
    invocation: healthmd_operations::QueryInvocation,
    cancellation: CancellationToken,
) -> Result<Value, QueryError> {
    let operations = healthmd_operations::HealthOperations::new(
        backend,
        healthmd_operations::SurfaceProfile::LocalDirect,
    );
    operations
        .query(
            &healthmd_operations::CallContext {
                caller: healthmd_operations::CallerIdentity::local(),
                cancellation,
                session_id: None,
            },
            invocation,
        )
        .await
        .map_err(QueryError::Backend)
}

/// Serve the fixed Health.md MCP surface over newline-delimited JSON-RPC stdio.
///
/// The normal entry point is `healthmd mcp serve`, which deliberately uses the same installed,
/// signed executable identity that owns pairing trust. On Unix, `healthmd-mcp` replaces itself with
/// that sibling executable. On Windows, where there is no `exec(2)`, the compatibility binary runs
/// this same server in-process and supervises its own same-file credential helper.
///
/// # Errors
///
/// Returns [`ServeError`] when native direct-client state cannot be initialized.
#[allow(clippy::too_many_lines)]
pub async fn serve(options: ServeOptions) -> Result<(), ServeError> {
    let backend = direct_backend::DirectIphoneBackend::open(&options)?;
    let application = Arc::new(healthmd_mcp::HealthMdApplication::new(
        Arc::new(backend),
        healthmd_mcp::SurfaceProfile::LocalDirect,
    ));
    let dispatcher = Arc::new(healthmd_mcp::JsonRpcSession::new(
        application.session(healthmd_mcp::CallerIdentity::local()),
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
    let mut in_flight: HashMap<String, CancellationToken> = HashMap::new();
    let mut input_open = true;

    while input_open || !tasks.is_empty() {
        tokio::select! {
            line = line_receiver.recv(), if input_open => {
                let Some(line) = line else {
                    input_open = false;
                    for cancellation in in_flight.values() {
                        cancellation.cancel();
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
                        if let Some(cancellation) = in_flight.get(&key) {
                            cancellation.cancel();
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
                    if let Some(response) = dispatcher.handle(&line, CancellationToken::new()).await {
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
                let cancellation = CancellationToken::new();
                if let Some(key) = key.as_ref() {
                    in_flight.insert(key.clone(), cancellation.clone());
                }
                if is_initialize {
                    let response = dispatcher.handle(&line, cancellation).await;
                    if let Some(key) = key.as_ref() { in_flight.remove(key); }
                    if let Some(response) = response { write_line(&mut output, &response).await; }
                } else {
                    let dispatcher = Arc::clone(&dispatcher);
                    tasks.spawn(async move { (key, dispatcher.handle(&line, cancellation).await) });
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

/// Serve the read-only vendor-neutral MCP surface over Streamable HTTP on loopback.
///
/// Both development and OAuth modes reject non-loopback binds. A remote deployment terminates TLS
/// in a co-resident reverse proxy that forwards only to this loopback listener; it never exposes
/// one installation's native pairing credentials over plaintext HTTP.
///
/// # Errors
///
/// Returns an error when direct-client state is unavailable or the HTTP listener cannot start.
#[cfg(feature = "oauth-resource-server")]
pub async fn serve_http(
    options: ServeOptions,
    http_options: HttpServerOptions,
    oauth_options: Option<HttpOAuthOptions>,
) -> Result<(), HttpServeError> {
    if oauth_options.is_none() {
        http_options
            .validate_unauthenticated()
            .map_err(HttpServeError::Http)?;
    }
    let backend =
        direct_backend::DirectIphoneBackend::open(&options).map_err(HttpServeError::Direct)?;
    let application = Arc::new(healthmd_mcp::HealthMdApplication::new(
        Arc::new(backend),
        healthmd_mcp::SurfaceProfile::RemoteReadOnly,
    ));
    if let Some(oauth) = oauth_options {
        let resource_server = healthmd_mcp::auth::OAuthResourceServerConfig::new(
            oauth.resource.clone(),
            vec![oauth.issuer.clone()],
            ["healthmd:read"],
        )
        .map_err(HttpServeError::OAuthConfiguration)?
        .with_owner_subject(oauth.owner_subject);
        let verifier_configuration = healthmd_mcp::auth::JwtJwksVerifierConfig::new(
            oauth.issuer,
            oauth.resource,
            oauth.jwks_uri,
        )
        .map_err(HttpServeError::OAuthConfiguration)?;
        let verifier = healthmd_mcp::auth::JwtJwksVerifier::new(verifier_configuration)
            .map_err(HttpServeError::OAuthVerifier)?;
        healthmd_mcp::transport::oauth_http::serve(
            application,
            http_options,
            resource_server,
            Arc::new(verifier),
        )
        .await
        .map_err(HttpServeError::Http)
    } else {
        healthmd_mcp::transport::streamable_http::serve(
            application,
            healthmd_mcp::CallerIdentity::loopback(),
            http_options,
        )
        .await
        .map_err(HttpServeError::Http)
    }
}

/// Serve unauthenticated read-only MCP over loopback HTTP when OAuth support is not compiled.
///
/// # Errors
///
/// Returns an error when direct-client state is unavailable or the HTTP listener cannot start.
#[cfg(all(feature = "streamable-http", not(feature = "oauth-resource-server")))]
pub async fn serve_http(
    options: ServeOptions,
    http_options: HttpServerOptions,
) -> Result<(), HttpServeError> {
    http_options
        .validate_unauthenticated()
        .map_err(HttpServeError::Http)?;
    let backend =
        direct_backend::DirectIphoneBackend::open(&options).map_err(HttpServeError::Direct)?;
    let application = Arc::new(healthmd_mcp::HealthMdApplication::new(
        Arc::new(backend),
        healthmd_mcp::SurfaceProfile::RemoteReadOnly,
    ));
    healthmd_mcp::transport::streamable_http::serve(
        application,
        healthmd_mcp::CallerIdentity::loopback(),
        http_options,
    )
    .await
    .map_err(HttpServeError::Http)
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
    use std::sync::Mutex;

    use async_trait::async_trait;
    use healthmd_operations::{
        BackendCapabilities, BackendError, CallContext, HealthDataBackend, QueryPageRequest,
    };

    use super::*;

    #[derive(Default)]
    struct FixtureBackend {
        requests: Mutex<Vec<QueryPageRequest>>,
    }

    #[async_trait]
    impl HealthDataBackend for FixtureBackend {
        fn capabilities(&self) -> BackendCapabilities {
            BackendCapabilities {
                source_kind: "fixture".to_owned(),
                transport: "fixture".to_owned(),
                supports_queries: true,
                supports_local_file_exports: false,
                requires_foreground_source: false,
                instructions: "fixture".to_owned(),
            }
        }

        async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
            Ok(json!({"ready": true}))
        }

        async fn doctor(&self, _context: &CallContext) -> Result<Value, BackendError> {
            Ok(json!({"ready": true}))
        }

        async fn query_page(
            &self,
            _context: &CallContext,
            request: QueryPageRequest,
        ) -> Result<Value, BackendError> {
            self.requests.lock().unwrap().push(request);
            Ok(json!({
                "schema": "healthmd.query_response",
                "schema_version": 1,
                "items": [],
                "next_cursor": null
            }))
        }
    }

    #[test]
    fn stdio_admission_is_bounded() {
        assert!(!at_capacity(MAXIMUM_IN_FLIGHT_REQUESTS - 1));
        assert!(at_capacity(MAXIMUM_IN_FLIGHT_REQUESTS));
        assert!(at_capacity(usize::MAX));
    }

    #[tokio::test]
    async fn every_query_operation_has_cli_and_mcp_canonical_parity() {
        let backend = Arc::new(FixtureBackend::default());
        let dates = json!({"type": "all_available"});
        let metrics = json!({"type": "explicit", "metric_ids": ["sleep_total"]});
        let request = json!({
            "schema": "healthmd.query_request",
            "schema_version": 1,
            "metrics": metrics,
            "sources": {"type": "all_available"},
            "dates": dates,
            "operation": {"type": "metric_series"},
            "page": {"max_items": 250, "max_bytes": 262_144, "cursor": null}
        });
        let cases = vec![
            (
                "healthmd_metric_chart",
                json!({"dates": dates, "metrics": metrics}),
            ),
            ("healthmd_sleep_sessions", json!({"dates": dates})),
            ("healthmd_training_alignment", json!({"dates": dates})),
            ("healthmd_workouts", json!({"dates": dates})),
            (
                "healthmd_coverage",
                json!({"dates": dates, "metrics": metrics}),
            ),
            (
                "healthmd_compare_periods",
                json!({
                    "dates": dates,
                    "metrics": metrics,
                    "first": {"start_date": "2026-07-01", "end_date": "2026-07-07"},
                    "second": {"start_date": "2026-07-08", "end_date": "2026-07-14"},
                    "aggregations": [{"metric_id": "sleep_total", "kind": "average"}]
                }),
            ),
            ("healthmd_training_evidence", json!({"dates": dates})),
            ("healthmd_query", json!({"request": request})),
            ("healthmd_evidence_packet", json!({"request": request})),
        ];
        let application = Arc::new(healthmd_mcp::HealthMdApplication::new(
            backend.clone(),
            healthmd_operations::SurfaceProfile::LocalDirect,
        ));

        for (operation, arguments) in cases {
            let before = backend.requests.lock().unwrap().len();
            let cli_payload = execute_query_operation(
                backend.clone(),
                operation,
                &arguments,
                CancellationToken::new(),
            )
            .await
            .unwrap();
            let mcp_result = application
                .session(healthmd_operations::CallerIdentity::local())
                .call_tool(operation, arguments, CancellationToken::new(), None)
                .await
                .unwrap();
            let mcp_payload: Value = serde_json::from_str(
                mcp_result["content"][0]["text"]
                    .as_str()
                    .expect("MCP text payload"),
            )
            .unwrap();
            assert_eq!(cli_payload, mcp_payload, "payload parity for {operation}");
            let requests = backend.requests.lock().unwrap();
            assert_eq!(
                requests[before],
                requests[before + 1],
                "request parity for {operation}"
            );
        }
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
