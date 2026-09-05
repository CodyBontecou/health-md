mod data_backend;
mod direct_backend;

pub use data_backend::{DataServeOptions, DataStoreOpenError, DirectoryArtifactStore};

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
    /// Programmatic wake-window override. MCP users configure this with `HEALTHMD_WAKE_TIMEOUT`.
    #[arg(skip)]
    pub wake_timeout_seconds: Option<u64>,
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

/// Return the fixed read-only Agent Data tool catalog without opening a data store.
///
/// # Errors
///
/// Returns a stable message when `tool_name` is not part of the Agent Data surface.
pub fn data_tool_catalog(tool_name: Option<&str>) -> Result<Value, String> {
    healthmd_mcp::tool_catalog(healthmd_mcp::SurfaceProfile::DataReadOnly, tool_name)
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
                progress: None,
            },
            invocation,
        )
        .await
        .map_err(QueryError::Backend)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum StdioSurface {
    LocalDirect,
    ReadOnly,
    Data,
}

impl StdioSurface {
    const fn profile(self) -> healthmd_mcp::SurfaceProfile {
        match self {
            Self::LocalDirect => healthmd_mcp::SurfaceProfile::LocalDirect,
            Self::ReadOnly => healthmd_mcp::SurfaceProfile::LocalReadOnly,
            Self::Data => healthmd_mcp::SurfaceProfile::DataReadOnly,
        }
    }

    fn caller(self) -> healthmd_mcp::CallerIdentity {
        match self {
            Self::LocalDirect => healthmd_mcp::CallerIdentity::local(),
            Self::ReadOnly | Self::Data => healthmd_mcp::CallerIdentity::local_read_only(),
        }
    }
}

fn stdio_dispatcher(
    backend: Arc<dyn healthmd_operations::HealthDataBackend>,
    surface: StdioSurface,
) -> Arc<healthmd_mcp::JsonRpcSession> {
    let application = Arc::new(healthmd_mcp::HealthMdApplication::new(
        backend,
        surface.profile(),
    ));
    Arc::new(healthmd_mcp::JsonRpcSession::new(
        application.session(surface.caller()),
    ))
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
pub async fn serve(options: ServeOptions) -> Result<(), ServeError> {
    serve_stdio(options, StdioSurface::LocalDirect).await
}

/// Serve the 13-tool read-only Health.md MCP surface over local newline-delimited JSON-RPC stdio.
///
/// Pairing and every generated-file export operation are absent and rejected even when called by
/// name. Pair the iPhone separately with `healthmd direct pair`. This profile starts no MCP HTTP
/// listener and requires no Health.md or third-party cloud service.
///
/// # Errors
///
/// Returns [`ServeError`] when native direct-client state cannot be initialized.
pub async fn serve_read_only(options: ServeOptions) -> Result<(), ServeError> {
    serve_stdio(options, StdioSurface::ReadOnly).await
}

/// Serve a data-only MCP surface over stdio from an explicitly configured export directory.
///
/// This server never opens mobile pairing state and never modifies source artifacts. Its grant is
/// enforced inside the artifact-store backend before records are returned.
///
/// # Errors
///
/// Returns [`DataStoreOpenError`] when the directory, grant, or external index is invalid.
pub async fn serve_data(options: DataServeOptions) -> Result<(), DataStoreOpenError> {
    let store = DirectoryArtifactStore::open(options)?;
    let backend = healthmd_operations::ArtifactStoreBackend::new(Arc::new(store));
    let dispatcher = stdio_dispatcher(Arc::new(backend), StdioSurface::Data);
    serve_dispatcher(dispatcher).await;
    Ok(())
}

async fn serve_stdio(options: ServeOptions, surface: StdioSurface) -> Result<(), ServeError> {
    let backend = direct_backend::DirectIphoneBackend::open(&options)?;
    let dispatcher = stdio_dispatcher(Arc::new(backend), surface);
    serve_dispatcher(dispatcher).await;
    Ok(())
}

#[allow(clippy::too_many_lines)]
async fn serve_dispatcher(dispatcher: Arc<healthmd_mcp::JsonRpcSession>) {
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
    let (notification_sender, mut notification_receiver) = mpsc::channel::<String>(64);
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
                    if let Some(response) = dispatcher
                        .handle_with_notifications(
                            &line,
                            CancellationToken::new(),
                            notification_sender.clone(),
                        )
                        .await
                    {
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
                    let response = dispatcher
                        .handle_with_notifications(
                            &line,
                            cancellation,
                            notification_sender.clone(),
                        )
                        .await;
                    if let Some(key) = key.as_ref() { in_flight.remove(key); }
                    if let Some(response) = response { write_line(&mut output, &response).await; }
                } else {
                    let dispatcher = Arc::clone(&dispatcher);
                    let notifications = notification_sender.clone();
                    tasks.spawn(async move {
                        (
                            key,
                            dispatcher
                                .handle_with_notifications(&line, cancellation, notifications)
                                .await,
                        )
                    });
                }
            }
            notification = notification_receiver.recv() => {
                if let Some(notification) = notification {
                    write_line(&mut output, &notification).await;
                }
            }
            completion = tasks.join_next(), if !tasks.is_empty() => {
                if let Some(Ok((key, response))) = completion {
                    if let Some(key) = key { in_flight.remove(&key); }
                    while let Ok(notification) = notification_receiver.try_recv() {
                        write_line(&mut output, &notification).await;
                    }
                    if let Some(response) = response { write_line(&mut output, &response).await; }
                }
            }
        }
    }
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
    async fn read_only_stdio_dispatcher_is_fail_closed_and_cloud_free() {
        let dispatcher =
            stdio_dispatcher(Arc::new(FixtureBackend::default()), StdioSurface::ReadOnly);
        let initialize = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let initialize: Value = serde_json::from_str(&initialize).unwrap();
        let instructions = initialize["result"]["instructions"].as_str().unwrap();
        assert!(instructions.contains("read-only"));
        assert!(instructions.contains("healthmd direct pair"));
        assert!(instructions.contains("no Health.md cloud"));
        assert!(!instructions.contains("healthmd_pairing_start"));

        let tools = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let tools: Value = serde_json::from_str(&tools).unwrap();
        let tools = tools["result"]["tools"].as_array().unwrap();
        assert_eq!(tools.len(), 13);
        assert!(tools.iter().all(|tool| {
            tool.pointer("/annotations/readOnlyHint") == Some(&json!(true))
                && !tool["name"].as_str().is_some_and(|name| {
                    name.starts_with("healthmd_pairing_") || name.starts_with("healthmd_export_")
                })
        }));
        let doctor = tools
            .iter()
            .find(|tool| tool["name"] == "healthmd_doctor")
            .and_then(|tool| tool["description"].as_str())
            .unwrap();
        assert!(doctor.contains("healthmd direct pair"));
        assert!(!doctor.contains("healthmd_pairing_start"));
        assert!(!doctor.contains("export readiness"));

        let hidden = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"healthmd_export_files","arguments":{}}}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let hidden: Value = serde_json::from_str(&hidden).unwrap();
        assert_eq!(hidden.pointer("/error/code"), Some(&json!(-32_602)));
        assert_eq!(
            hidden.pointer("/error/message"),
            Some(&json!("Unknown tool"))
        );
    }

    #[tokio::test]
    async fn data_stdio_dispatcher_exposes_only_the_data_contract() {
        let dispatcher = stdio_dispatcher(Arc::new(FixtureBackend::default()), StdioSurface::Data);
        let initialize = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let initialize: Value = serde_json::from_str(&initialize).unwrap();
        let instructions = initialize["result"]["instructions"].as_str().unwrap();
        assert!(instructions.contains("healthmd_data_catalog"));
        assert!(instructions.contains("does not interpret"));
        assert!(!instructions.contains("pair"));

        let tools = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let tools: Value = serde_json::from_str(&tools).unwrap();
        let tools = tools["result"]["tools"].as_array().unwrap();
        assert_eq!(tools.len(), 5);
        assert!(tools.iter().all(|tool| {
            tool["name"]
                .as_str()
                .is_some_and(|name| name.starts_with("healthmd_data_"))
                && tool.pointer("/annotations/readOnlyHint") == Some(&json!(true))
        }));

        let hidden = dispatcher
            .handle(
                r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"healthmd_status","arguments":{}}}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let hidden: Value = serde_json::from_str(&hidden).unwrap();
        assert_eq!(hidden.pointer("/error/code"), Some(&json!(-32_602)));
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

        let data = data_tool_catalog(None).expect("Agent Data schema");
        assert_eq!(data["tools"].as_array().map(Vec::len), Some(5));
        assert!(data_tool_catalog(Some("healthmd_status")).is_err());
    }
}
