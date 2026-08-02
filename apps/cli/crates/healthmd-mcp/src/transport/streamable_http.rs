use std::{
    collections::HashMap,
    fmt, io,
    net::{IpAddr, SocketAddr},
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    Router,
    body::{Body, to_bytes},
    extract::State,
    http::{Method, Request, StatusCode, header},
    middleware::{self, Next},
    response::Response,
    routing::{any, get},
};
use serde_json::{Value, json};
use tokio::sync::{Mutex, Semaphore};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{CallerIdentity, HealthMdApplication, JsonRpcSession};

pub const MAXIMUM_HTTP_BODY_BYTES: usize = 2 * 1_024 * 1_024;
const LATEST_HTTP_PROTOCOL: &str = "2025-11-25";
const HTTP_PROTOCOLS: &[&str] = &["2025-06-18", LATEST_HTTP_PROTOCOL];
const MAXIMUM_HTTP_SESSIONS: usize = 4_096;
const MAXIMUM_HTTP_SESSIONS_PER_CALLER: usize = 64;
const MAXIMUM_CONCURRENT_HTTP_REQUESTS: usize = 32;
const MAXIMUM_ACTIVE_REQUESTS_PER_SESSION: usize = 128;
const HTTP_SESSION_TTL: Duration = Duration::from_secs(600);
const HTTP_REQUEST_TIMEOUT: Duration = Duration::from_secs(300);

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HttpServerOptions {
    pub bind: SocketAddr,
    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,
}

impl Default for HttpServerOptions {
    fn default() -> Self {
        Self {
            bind: SocketAddr::from(([127, 0, 0, 1], 8_787)),
            allowed_hosts: Vec::new(),
            allowed_origins: Vec::new(),
        }
    }
}

impl HttpServerOptions {
    /// Validate the complete unauthenticated development-listener policy.
    ///
    /// # Errors
    ///
    /// Returns an error if the listener, accepted Hosts, or accepted Origins are not loopback-only.
    pub fn validate_unauthenticated(&self) -> Result<(), HttpServerError> {
        validate_bind(self.bind.ip())?;
        validate_unauthenticated_policy(self)
    }
}

#[derive(Debug)]
pub enum HttpServerError {
    NonLoopbackBind,
    AllowedHostsRequired,
    UnauthenticatedRemotePolicy,
    Io(std::io::Error),
}

impl fmt::Display for HttpServerError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NonLoopbackBind => formatter.write_str(
                "Streamable HTTP must bind to loopback; terminate TLS in a co-resident reverse proxy",
            ),
            Self::AllowedHostsRequired => formatter.write_str(
                "an OAuth-protected public MCP server requires an explicit Host allowlist",
            ),
            Self::UnauthenticatedRemotePolicy => formatter.write_str(
                "unauthenticated Streamable HTTP accepts only loopback Host and Origin values",
            ),
            Self::Io(error) => write!(formatter, "Streamable HTTP server failed: {error}"),
        }
    }
}

impl std::error::Error for HttpServerError {}

impl From<std::io::Error> for HttpServerError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

#[derive(Clone)]
struct OriginPolicy {
    allowed_hosts: Arc<Vec<String>>,
    allowed_origins: Arc<Vec<String>>,
}

#[derive(Clone)]
struct McpHttpState {
    application: Arc<HealthMdApplication>,
    default_caller: Option<CallerIdentity>,
    sessions: Arc<SessionStore>,
    admission: Arc<Semaphore>,
    cancellation: CancellationToken,
}

#[derive(Default)]
struct SessionStore {
    entries: Mutex<HashMap<String, SessionEntry>>,
}

struct SessionEntry {
    session: Arc<HttpSession>,
    last_seen: Instant,
}

struct HttpSession {
    rpc: JsonRpcSession,
    owner: SessionOwnerKey,
    protocol_version: String,
    cancellation: CancellationToken,
    active: Mutex<HashMap<String, CancellationToken>>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct SessionOwnerKey {
    subject: String,
    tenant: Option<String>,
    mode: crate::CallerMode,
}

impl From<&CallerIdentity> for SessionOwnerKey {
    fn from(caller: &CallerIdentity) -> Self {
        Self {
            subject: caller.subject.clone(),
            tenant: caller.tenant.clone(),
            mode: caller.mode,
        }
    }
}

impl HttpSession {
    fn new(
        application: &Arc<HealthMdApplication>,
        caller: CallerIdentity,
        protocol_version: &str,
        cancellation: &CancellationToken,
    ) -> Self {
        let owner = SessionOwnerKey::from(&caller);
        Self {
            rpc: JsonRpcSession::new(application.session(caller)),
            owner,
            protocol_version: protocol_version.to_owned(),
            cancellation: cancellation.child_token(),
            active: Mutex::new(HashMap::new()),
        }
    }

    async fn begin_request(&self, id: &Value) -> Option<(String, CancellationToken)> {
        let key = crate::jsonrpc::request_id_key(id).ok()?;
        let mut active = self.active.lock().await;
        if active.len() >= MAXIMUM_ACTIVE_REQUESTS_PER_SESSION || active.contains_key(&key) {
            return None;
        }
        let cancellation = self.cancellation.child_token();
        active.insert(key.clone(), cancellation.clone());
        Some((key, cancellation))
    }

    async fn finish_request(&self, key: &str) {
        self.active.lock().await.remove(key);
    }

    async fn cancel_request(&self, id: &Value) {
        let Ok(key) = crate::jsonrpc::request_id_key(id) else {
            return;
        };
        if let Some(cancellation) = self.active.lock().await.get(&key) {
            cancellation.cancel();
        }
    }
}

impl SessionStore {
    async fn insert(&self, id: String, session: Arc<HttpSession>) -> bool {
        let mut entries = self.entries.lock().await;
        expire_sessions(&mut entries);
        if entries.len() >= MAXIMUM_HTTP_SESSIONS
            || entries
                .values()
                .filter(|entry| entry.session.owner == session.owner)
                .count()
                >= MAXIMUM_HTTP_SESSIONS_PER_CALLER
        {
            return false;
        }
        entries.insert(
            id,
            SessionEntry {
                session,
                last_seen: Instant::now(),
            },
        );
        true
    }

    async fn get(&self, id: &str) -> Option<Arc<HttpSession>> {
        let mut entries = self.entries.lock().await;
        expire_sessions(&mut entries);
        let entry = entries.get_mut(id)?;
        entry.last_seen = Instant::now();
        Some(Arc::clone(&entry.session))
    }

    async fn remove(&self, id: &str) -> bool {
        self.entries.lock().await.remove(id).is_some_and(|entry| {
            entry.session.cancellation.cancel();
            true
        })
    }
}

fn expire_sessions(entries: &mut HashMap<String, SessionEntry>) {
    let now = Instant::now();
    entries.retain(|_, entry| {
        let live = now.duration_since(entry.last_seen) <= HTTP_SESSION_TTL;
        if !live {
            entry.session.cancellation.cancel();
        }
        live
    });
}

/// Build the bounded Streamable HTTP router for an explicitly scoped caller.
///
/// # Errors
///
/// Returns an error when the configured bind address is not permitted.
pub fn router(
    application: Arc<HealthMdApplication>,
    caller: CallerIdentity,
    options: &HttpServerOptions,
    cancellation: CancellationToken,
) -> Result<Router, HttpServerError> {
    options.validate_unauthenticated()?;
    let policy = Arc::new(OriginPolicy {
        allowed_hosts: Arc::new(effective_allowed_hosts(options)),
        allowed_origins: Arc::new(options.allowed_origins.clone()),
    });
    Ok(Router::new()
        .route("/healthz", get(|| async { "ok" }))
        .merge(mcp_router(application, Some(caller), cancellation))
        .layer(middleware::from_fn_with_state(
            policy,
            enforce_host_and_origin,
        )))
}

/// Serve MCP Streamable HTTP until shutdown on the configured listener.
///
/// # Errors
///
/// Returns an error for an unsafe bind address or listener/server I/O failure.
pub async fn serve(
    application: Arc<HealthMdApplication>,
    caller: CallerIdentity,
    options: HttpServerOptions,
) -> Result<(), HttpServerError> {
    options.validate_unauthenticated()?;
    let cancellation = CancellationToken::new();
    let application_router = router(application, caller, &options, cancellation.clone())?;
    let listener = tokio::net::TcpListener::bind(options.bind).await?;
    axum::serve(listener, application_router)
        .with_graceful_shutdown(async move {
            let _ = tokio::signal::ctrl_c().await;
            cancellation.cancel();
        })
        .await?;
    Ok(())
}

pub(super) fn mcp_router(
    application: Arc<HealthMdApplication>,
    default_caller: Option<CallerIdentity>,
    cancellation: CancellationToken,
) -> Router {
    let state = Arc::new(McpHttpState {
        application,
        default_caller,
        sessions: Arc::new(SessionStore::default()),
        admission: Arc::new(Semaphore::new(MAXIMUM_CONCURRENT_HTTP_REQUESTS)),
        cancellation,
    });
    Router::new()
        .route("/mcp", any(handle_mcp))
        .layer(middleware::from_fn(enforce_request_body_limit))
        .with_state(state)
}

async fn handle_mcp(State(state): State<Arc<McpHttpState>>, request: Request<Body>) -> Response {
    match *request.method() {
        Method::POST => handle_post(state, request).await,
        Method::DELETE => handle_delete(state, request).await,
        _ => method_not_allowed_response(),
    }
}

#[allow(clippy::too_many_lines)]
async fn handle_post(state: Arc<McpHttpState>, request: Request<Body>) -> Response {
    let Ok(_request_permit) = Arc::clone(&state.admission).try_acquire_owned() else {
        return empty_response(StatusCode::SERVICE_UNAVAILABLE);
    };
    if !accepts_streamable_http(request.headers()) {
        return empty_response(StatusCode::NOT_ACCEPTABLE);
    }
    if !has_json_content_type(request.headers()) {
        return empty_response(StatusCode::UNSUPPORTED_MEDIA_TYPE);
    }
    let has_session_header = request.headers().contains_key("mcp-session-id");
    let request_session_id = session_id(&request);
    if has_session_header && request_session_id.is_none() {
        return empty_response(StatusCode::BAD_REQUEST);
    }
    let existing_session = if let Some(session_id) = &request_session_id {
        let Some(session) = state.sessions.get(session_id).await else {
            return empty_response(StatusCode::NOT_FOUND);
        };
        Some(session)
    } else {
        None
    };
    let caller = state
        .default_caller
        .clone()
        .or_else(|| request.extensions().get::<CallerIdentity>().cloned());
    let request_protocol_version = request
        .headers()
        .get("mcp-protocol-version")
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);
    let Ok(body) = to_bytes(request.into_body(), MAXIMUM_HTTP_BODY_BYTES).await else {
        return empty_response(StatusCode::PAYLOAD_TOO_LARGE);
    };
    let parsed: Value = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(_) => {
            return json_rpc_response(
                StatusCode::OK,
                json_rpc_error(Value::Null, -32_700, "Parse error"),
                None,
            );
        }
    };
    let Some(object) = parsed.as_object() else {
        return json_rpc_response(
            StatusCode::OK,
            json_rpc_error(Value::Null, -32_600, "Invalid request"),
            None,
        );
    };
    if object.get("jsonrpc").and_then(Value::as_str) != Some("2.0") {
        return json_rpc_response(
            StatusCode::OK,
            json_rpc_error(
                object.get("id").cloned().unwrap_or(Value::Null),
                -32_600,
                "Invalid request",
            ),
            None,
        );
    }
    let id = object.get("id").cloned();
    let Some(method) = object.get("method").and_then(Value::as_str) else {
        let is_response = id.is_some()
            && object.contains_key("result") != object.contains_key("error")
            && object
                .keys()
                .all(|key| matches!(key.as_str(), "jsonrpc" | "id" | "result" | "error"));
        if is_response {
            return empty_response(StatusCode::ACCEPTED);
        }
        return json_rpc_response(
            StatusCode::OK,
            json_rpc_error(id.unwrap_or(Value::Null), -32_600, "Invalid request"),
            None,
        );
    };

    let Some(current_session_id) = request_session_id else {
        if method != "initialize" || id.is_none() {
            return empty_response(StatusCode::BAD_REQUEST);
        }
        let Some(requested_protocol) = parsed
            .pointer("/params/protocolVersion")
            .and_then(Value::as_str)
        else {
            return json_rpc_response(
                StatusCode::OK,
                json_rpc_error(id.unwrap_or(Value::Null), -32_602, "Invalid parameters"),
                None,
            );
        };
        let protocol_version = if HTTP_PROTOCOLS.contains(&requested_protocol) {
            requested_protocol
        } else {
            LATEST_HTTP_PROTOCOL
        };
        if request_protocol_version
            .as_deref()
            .is_some_and(|header| header != protocol_version)
        {
            return protocol_version_error();
        }
        let Some(caller) = caller else {
            return empty_response(StatusCode::INTERNAL_SERVER_ERROR);
        };
        let session = Arc::new(HttpSession::new(
            &state.application,
            caller,
            protocol_version,
            &state.cancellation,
        ));
        let mut normalized = parsed.clone();
        normalized["params"]["protocolVersion"] = Value::String(protocol_version.to_owned());
        let cancellation = session.cancellation.child_token();
        let normalized = normalized.to_string();
        let response =
            match dispatch_http_request(&session, &normalized, cancellation, None, None).await {
                Ok(Some(response)) => response,
                Ok(None) => return empty_response(StatusCode::BAD_REQUEST),
                Err(DispatchError::TimedOut) => {
                    return json_rpc_response(
                        StatusCode::OK,
                        json_rpc_error(id.unwrap_or(Value::Null), -32_000, "Request timed out"),
                        None,
                    );
                }
            };
        let response_value: Value = serde_json::from_str(&response)
            .unwrap_or_else(|_| json_rpc_error(Value::Null, -32_603, "Internal error"));
        if response_value.get("result").is_none() {
            return json_rpc_response(StatusCode::OK, response_value, None);
        }
        let session_id = Uuid::new_v4().to_string();
        if !state.sessions.insert(session_id.clone(), session).await {
            return empty_response(StatusCode::SERVICE_UNAVAILABLE);
        }
        return json_rpc_response(StatusCode::OK, response_value, Some(&session_id));
    };

    let session = existing_session.expect("looked up for a present session ID");
    if request_protocol_version.as_deref() != Some(session.protocol_version.as_str()) {
        return protocol_version_error();
    }
    let Some(caller) = caller else {
        return empty_response(StatusCode::INTERNAL_SERVER_ERROR);
    };
    if method == "initialize" {
        return json_rpc_response(
            StatusCode::OK,
            json_rpc_error(id.unwrap_or(Value::Null), -32_600, "Invalid request"),
            None,
        );
    }
    if id.is_none() {
        if method == "notifications/cancelled" {
            if let Some(request_id) = parsed.pointer("/params/requestId") {
                session.cancel_request(request_id).await;
            }
        }
        return empty_response(StatusCode::ACCEPTED);
    }
    let id = id.expect("checked");
    if crate::jsonrpc::request_id_key(&id).is_err() {
        return json_rpc_response(
            StatusCode::OK,
            json_rpc_error(id, -32_600, "Invalid request"),
            None,
        );
    }
    let Some((key, cancellation)) = session.begin_request(&id).await else {
        return json_rpc_response(
            StatusCode::OK,
            json_rpc_error(id, -32_000, "Request limit exceeded"),
            None,
        );
    };
    let response = dispatch_http_request(
        &session,
        std::str::from_utf8(&body).unwrap_or_default(),
        cancellation,
        Some(caller),
        Some(current_session_id),
    )
    .await;
    session.finish_request(&key).await;
    let response = match response {
        Ok(Some(response)) => response,
        Ok(None) => return empty_response(StatusCode::ACCEPTED),
        Err(DispatchError::TimedOut) => {
            return json_rpc_response(
                StatusCode::OK,
                json_rpc_error(id, -32_000, "Request timed out"),
                None,
            );
        }
    };
    let response: Value = serde_json::from_str(&response)
        .unwrap_or_else(|_| json_rpc_error(Value::Null, -32_603, "Internal error"));
    let status = if response.pointer("/error/code") == Some(&json!(-32_003)) {
        StatusCode::FORBIDDEN
    } else {
        StatusCode::OK
    };
    json_rpc_response(status, response, None)
}

enum DispatchError {
    TimedOut,
}

async fn dispatch_http_request(
    session: &HttpSession,
    input: &str,
    cancellation: CancellationToken,
    caller: Option<CallerIdentity>,
    session_id: Option<String>,
) -> Result<Option<String>, DispatchError> {
    let timeout_cancellation = cancellation.clone();
    let response = tokio::time::timeout(HTTP_REQUEST_TIMEOUT, async {
        if let Some(caller) = caller {
            session
                .rpc
                .handle_as(input, cancellation, caller, session_id)
                .await
        } else {
            session.rpc.handle(input, cancellation).await
        }
    })
    .await;
    if let Ok(response) = response {
        Ok(response)
    } else {
        timeout_cancellation.cancel();
        Err(DispatchError::TimedOut)
    }
}

async fn handle_delete(state: Arc<McpHttpState>, request: Request<Body>) -> Response {
    let Some(session_id) = session_id(&request) else {
        return empty_response(StatusCode::BAD_REQUEST);
    };
    let protocol_version = request
        .headers()
        .get("mcp-protocol-version")
        .and_then(|value| value.to_str().ok());
    let Some(session) = state.sessions.get(&session_id).await else {
        return empty_response(StatusCode::NOT_FOUND);
    };
    if protocol_version != Some(session.protocol_version.as_str()) {
        return protocol_version_error();
    }
    drop(request);
    if state.sessions.remove(&session_id).await {
        empty_response(StatusCode::OK)
    } else {
        empty_response(StatusCode::NOT_FOUND)
    }
}

fn session_id(request: &Request<Body>) -> Option<String> {
    let value = request.headers().get("mcp-session-id")?.to_str().ok()?;
    if value.is_empty() || value.len() > 128 || !value.bytes().all(|byte| byte.is_ascii_graphic()) {
        return None;
    }
    Some(value.to_owned())
}

fn accepts_streamable_http(headers: &header::HeaderMap) -> bool {
    let Some(accept) = headers
        .get(header::ACCEPT)
        .and_then(|value| value.to_str().ok())
    else {
        return false;
    };
    let mut json = false;
    let mut events = false;
    for media_type in accept.split(',').filter_map(|part| part.split(';').next()) {
        match media_type.trim() {
            "application/json" => json = true,
            "text/event-stream" => events = true,
            "*/*" => {
                json = true;
                events = true;
            }
            _ => {}
        }
    }
    json && events
}

fn has_json_content_type(headers: &header::HeaderMap) -> bool {
    headers
        .get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(';').next())
        .is_some_and(|value| value.trim().eq_ignore_ascii_case("application/json"))
}

#[allow(clippy::needless_pass_by_value)]
fn json_rpc_error(id: Value, code: i64, message: &str) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": {"code": code, "message": message}
    })
}

struct BoundedBodyBuffer {
    bytes: Vec<u8>,
}

impl io::Write for BoundedBodyBuffer {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > MAXIMUM_HTTP_BODY_BYTES.saturating_sub(self.bytes.len()) {
            return Err(io::Error::other("response exceeds transport limit"));
        }
        self.bytes.extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[allow(clippy::needless_pass_by_value)]
fn json_rpc_response(status: StatusCode, value: Value, session_id: Option<&str>) -> Response {
    let mut output = BoundedBodyBuffer {
        bytes: Vec::with_capacity(16_384),
    };
    if serde_json::to_writer(&mut output, &value).is_err() {
        let id = value.get("id").cloned().unwrap_or(Value::Null);
        output.bytes = serde_json::to_vec(&json_rpc_error(
            id,
            -32_000,
            "Response exceeds transport limit",
        ))
        .expect("fixed JSON-RPC error serializes");
    }
    let mut builder = Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::CACHE_CONTROL, "no-store");
    if let Some(session_id) = session_id {
        builder = builder.header("mcp-session-id", session_id);
    }
    builder
        .body(Body::from(output.bytes))
        .expect("valid JSON-RPC response")
}

fn method_not_allowed_response() -> Response {
    Response::builder()
        .status(StatusCode::METHOD_NOT_ALLOWED)
        .header(header::ALLOW, "POST, DELETE")
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::empty())
        .expect("valid method-not-allowed response")
}

fn empty_response(status: StatusCode) -> Response {
    Response::builder()
        .status(status)
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::empty())
        .expect("valid empty response")
}

pub(super) async fn enforce_request_body_limit(request: Request<Body>, next: Next) -> Response {
    let has_session = request.headers().contains_key("mcp-session-id");
    let protocol_version = request.headers().get("mcp-protocol-version");
    if has_session && protocol_version.is_none() {
        return protocol_version_error();
    }
    if let Some(version) = protocol_version {
        let supported = version
            .to_str()
            .is_ok_and(|version| HTTP_PROTOCOLS.contains(&version));
        if !supported {
            return protocol_version_error();
        }
    }
    if request.method() != Method::POST {
        return next.run(request).await;
    }
    let (parts, body) = request.into_parts();
    match to_bytes(body, MAXIMUM_HTTP_BODY_BYTES).await {
        Ok(bytes) => {
            next.run(Request::from_parts(parts, Body::from(bytes)))
                .await
        }
        Err(_) => empty_response(StatusCode::PAYLOAD_TOO_LARGE),
    }
}

fn protocol_version_error() -> Response {
    json_rpc_response(
        StatusCode::BAD_REQUEST,
        json!({
            "jsonrpc": "2.0",
            "id": null,
            "error": {
                "code": -32600,
                "message": "Unsupported MCP protocol version",
                "data": {"supported": HTTP_PROTOCOLS}
            }
        }),
        None,
    )
}

async fn enforce_host_and_origin(
    State(policy): State<Arc<OriginPolicy>>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if request_host_and_origin_allowed(&request, &policy.allowed_hosts, &policy.allowed_origins) {
        next.run(request).await
    } else {
        empty_response(StatusCode::FORBIDDEN)
    }
}

pub(super) fn request_host_and_origin_allowed(
    request: &Request<Body>,
    allowed_hosts: &[String],
    allowed_origins: &[String],
) -> bool {
    let host_allowed = request
        .headers()
        .get(header::HOST)
        .and_then(|value| value.to_str().ok())
        .and_then(|host| host.parse::<axum::http::uri::Authority>().ok())
        .is_some_and(|host| {
            allowed_hosts.iter().any(|allowed| {
                let Ok(allowed) = allowed.parse::<axum::http::uri::Authority>() else {
                    return false;
                };
                host.host().eq_ignore_ascii_case(allowed.host())
                    && allowed
                        .port_u16()
                        .is_none_or(|port| host.port_u16() == Some(port))
            })
        });
    if !host_allowed {
        return false;
    }
    let Some(origin) = request
        .headers()
        .get(header::ORIGIN)
        .and_then(|value| value.to_str().ok())
    else {
        return true;
    };
    allowed_origins.iter().any(|allowed| origin == allowed)
}

fn validate_bind(ip: IpAddr) -> Result<(), HttpServerError> {
    if ip.is_loopback() {
        Ok(())
    } else {
        Err(HttpServerError::NonLoopbackBind)
    }
}

fn validate_unauthenticated_policy(options: &HttpServerOptions) -> Result<(), HttpServerError> {
    let hosts_are_loopback = effective_allowed_hosts(options)
        .iter()
        .all(|value| authority_host(value).is_some_and(|host| host_is_loopback(&host)));
    let origins_are_loopback = options.allowed_origins.iter().all(|value| {
        value
            .parse::<axum::http::Uri>()
            .ok()
            .and_then(|origin| origin.host().map(str::to_owned))
            .is_some_and(|host| host_is_loopback(&host))
    });
    if hosts_are_loopback && origins_are_loopback {
        Ok(())
    } else {
        Err(HttpServerError::UnauthenticatedRemotePolicy)
    }
}

fn authority_host(value: &str) -> Option<String> {
    value
        .parse::<axum::http::uri::Authority>()
        .ok()
        .map(|authority| authority.host().trim_matches(['[', ']']).to_owned())
}

fn host_is_loopback(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<IpAddr>()
            .is_ok_and(|address| address.is_loopback())
}

pub(super) fn effective_allowed_hosts(options: &HttpServerOptions) -> Vec<String> {
    if !options.allowed_hosts.is_empty() {
        return options.allowed_hosts.clone();
    }
    let mut hosts = vec![
        "localhost".to_owned(),
        "127.0.0.1".to_owned(),
        "[::1]".to_owned(),
    ];
    let bind_host = options.bind.ip().to_string();
    if !hosts.contains(&bind_host) {
        hosts.push(bind_host);
    }
    hosts
}

#[cfg(test)]
mod tests {
    use async_trait::async_trait;
    use axum::{
        body::{Body, to_bytes},
        http::{Request, StatusCode},
    };
    use serde_json::{Value, json};
    use tokio::sync::Notify;
    use tower::ServiceExt as _;

    use super::*;
    use crate::{
        BackendCapabilities, BackendError, CallContext, HealthDataBackend, QueryPageRequest,
        SurfaceProfile,
    };

    struct FixtureBackend;

    struct BlockingBackend {
        started: Arc<Notify>,
    }

    #[async_trait]
    impl HealthDataBackend for BlockingBackend {
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

        async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
            self.started.notify_one();
            std::future::pending().await
        }

        async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
            self.readiness(context).await
        }

        async fn query_page(
            &self,
            _context: &CallContext,
            _request: QueryPageRequest,
        ) -> Result<Value, BackendError> {
            std::future::pending().await
        }
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
                instructions: "Use the fixture.".to_owned(),
            }
        }

        async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
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

    fn fixture_router(options: &HttpServerOptions) -> Router {
        let application = Arc::new(HealthMdApplication::new(
            Arc::new(FixtureBackend),
            SurfaceProfile::RemoteReadOnly,
        ));
        router(
            application,
            CallerIdentity::loopback(),
            options,
            CancellationToken::new(),
        )
        .unwrap()
    }

    fn post(body: &str) -> Request<Body> {
        Request::builder()
            .method("POST")
            .uri("/mcp")
            .header("host", "127.0.0.1:8787")
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .body(Body::from(body.to_owned()))
            .unwrap()
    }

    #[test]
    fn direct_backed_http_rejects_non_loopback_bind() {
        assert!(matches!(
            validate_bind(IpAddr::from([0, 0, 0, 0])),
            Err(HttpServerError::NonLoopbackBind)
        ));
        assert!(validate_bind(IpAddr::from([127, 0, 0, 1])).is_ok());
        assert!(validate_bind(IpAddr::V6(std::net::Ipv6Addr::LOCALHOST)).is_ok());
    }

    #[test]
    fn unauthenticated_http_rejects_reverse_proxy_hosts_and_origins() {
        for options in [
            HttpServerOptions {
                allowed_hosts: vec!["mcp.example.com".to_owned()],
                ..HttpServerOptions::default()
            },
            HttpServerOptions {
                allowed_origins: vec!["https://mcp.example.com".to_owned()],
                ..HttpServerOptions::default()
            },
        ] {
            assert!(matches!(
                validate_unauthenticated_policy(&options),
                Err(HttpServerError::UnauthenticatedRemotePolicy)
            ));
        }
        assert!(
            validate_unauthenticated_policy(&HttpServerOptions {
                allowed_hosts: vec!["localhost:8787".to_owned(), "[::1]:8787".to_owned()],
                allowed_origins: vec!["http://127.0.0.1:3000".to_owned()],
                ..HttpServerOptions::default()
            })
            .is_ok()
        );
    }

    #[tokio::test]
    async fn streamable_http_initializes_and_lists_only_remote_tools() {
        let application_router = fixture_router(&HttpServerOptions::default());
        let initialize = post(
            r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test-client","version":"1"}}}"#,
        );
        let response = application_router
            .clone()
            .oneshot(initialize)
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let session = response
            .headers()
            .get("mcp-session-id")
            .unwrap()
            .to_str()
            .unwrap()
            .to_owned();
        let body = to_bytes(response.into_body(), MAXIMUM_HTTP_BODY_BYTES)
            .await
            .unwrap();
        let body = String::from_utf8(body.to_vec()).unwrap();
        assert!(body.contains("healthmd-mcp"));
        assert!(body.contains("2025-11-25"));

        let mut request = post(r#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#);
        request
            .headers_mut()
            .insert("mcp-session-id", session.parse().unwrap());
        request
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.clone().oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), MAXIMUM_HTTP_BODY_BYTES)
            .await
            .unwrap();
        let body = String::from_utf8(body.to_vec()).unwrap();
        assert!(body.contains("healthmd_sleep_sessions"));
        assert!(body.contains("healthmd_metric_chart"));
        assert!(!body.contains("healthmd_export_files"));

        let mut notification =
            post(r#"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#);
        notification
            .headers_mut()
            .insert("mcp-session-id", session.parse().unwrap());
        notification
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.oneshot(notification).await.unwrap();
        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }

    #[tokio::test]
    async fn stdio_and_streamable_http_return_equivalent_tool_results() {
        let application = Arc::new(HealthMdApplication::new(
            Arc::new(FixtureBackend),
            SurfaceProfile::RemoteReadOnly,
        ));
        let stdio = JsonRpcSession::new(application.session(CallerIdentity::loopback()));
        let _ = stdio
            .handle(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let stdio_response = stdio
            .handle(
                r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"healthmd_status","arguments":{}}}"#,
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let stdio_response: Value = serde_json::from_str(&stdio_response).unwrap();

        let application_router = router(
            application,
            CallerIdentity::loopback(),
            &HttpServerOptions::default(),
            CancellationToken::new(),
        )
        .unwrap();
        let initialized = application_router
            .clone()
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
            ))
            .await
            .unwrap();
        let session = initialized.headers()["mcp-session-id"].clone();
        let mut request = post(
            r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"healthmd_status","arguments":{}}}"#,
        );
        request.headers_mut().insert("mcp-session-id", session);
        request
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.oneshot(request).await.unwrap();
        let body = to_bytes(response.into_body(), 65_536).await.unwrap();
        let http_response: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(http_response["result"], stdio_response["result"]);
    }

    #[tokio::test]
    async fn cancellation_notifications_cancel_the_matching_active_request() {
        let started = Arc::new(Notify::new());
        let application = Arc::new(HealthMdApplication::new(
            Arc::new(BlockingBackend {
                started: Arc::clone(&started),
            }),
            SurfaceProfile::RemoteReadOnly,
        ));
        let application_router = router(
            application,
            CallerIdentity::loopback(),
            &HttpServerOptions::default(),
            CancellationToken::new(),
        )
        .unwrap();
        let response = application_router
            .clone()
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
            ))
            .await
            .unwrap();
        let session = response.headers()["mcp-session-id"].clone();

        let mut call = post(
            r#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"healthmd_status","arguments":{}}}"#,
        );
        call.headers_mut().insert("mcp-session-id", session.clone());
        call.headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let calling_router = application_router.clone();
        let pending = tokio::spawn(async move { calling_router.oneshot(call).await.unwrap() });
        started.notified().await;

        let mut cancellation = post(
            r#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":9,"reason":"test"}}"#,
        );
        cancellation.headers_mut().insert("mcp-session-id", session);
        cancellation
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.oneshot(cancellation).await.unwrap();
        assert_eq!(response.status(), StatusCode::ACCEPTED);

        let response = tokio::time::timeout(Duration::from_secs(1), pending)
            .await
            .expect("cancelled request must finish")
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), 65_536).await.unwrap();
        assert!(String::from_utf8_lossy(&body).contains("healthmd_request_cancelled"));
    }

    #[tokio::test]
    async fn streamable_http_rejects_unconfigured_browser_origins() {
        let application_router = fixture_router(&HttpServerOptions::default());
        let mut request = post(
            r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test-client","version":"1"}}}"#,
        );
        request
            .headers_mut()
            .insert("origin", "https://untrusted.example".parse().unwrap());
        let response = application_router.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn streamable_http_rejects_oversized_bodies_and_unknown_versions() {
        let application_router = fixture_router(&HttpServerOptions::default());
        let oversized = Request::builder()
            .method("POST")
            .uri("/mcp")
            .header("host", "127.0.0.1:8787")
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .body(Body::from("x".repeat(MAXIMUM_HTTP_BODY_BYTES + 1)))
            .unwrap();
        let response = application_router.clone().oneshot(oversized).await.unwrap();
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);

        let mut unknown_version = post(
            r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01","capabilities":{},"clientInfo":{"name":"test-client","version":"1"}}}"#,
        );
        unknown_version
            .headers_mut()
            .insert("mcp-protocol-version", "2099-01-01".parse().unwrap());
        let response = application_router.oneshot(unknown_version).await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn streamable_http_requires_the_negotiated_protocol_for_existing_sessions() {
        let application_router = fixture_router(&HttpServerOptions::default());
        let response = application_router
            .clone()
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
            ))
            .await
            .unwrap();
        let session = response.headers()["mcp-session-id"].clone();

        let mut missing = post(r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#);
        missing
            .headers_mut()
            .insert("mcp-session-id", session.clone());
        let response = application_router.clone().oneshot(missing).await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);

        let mut changed = post(r#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#);
        changed.headers_mut().insert("mcp-session-id", session);
        changed
            .headers_mut()
            .insert("mcp-protocol-version", "2025-06-18".parse().unwrap());
        let response = application_router.oneshot(changed).await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn client_response_messages_are_accepted_without_application_dispatch() {
        let application_router = fixture_router(&HttpServerOptions::default());
        let response = application_router
            .clone()
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
            ))
            .await
            .unwrap();
        let session = response.headers()["mcp-session-id"].clone();
        let mut client_response = post(r#"{"jsonrpc":"2.0","id":99,"result":{}}"#);
        client_response
            .headers_mut()
            .insert("mcp-session-id", session);
        client_response
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.oneshot(client_response).await.unwrap();
        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }

    #[tokio::test]
    async fn response_serialization_stops_at_the_transport_limit() {
        let response = json_rpc_response(
            StatusCode::OK,
            json!({
                "jsonrpc": "2.0",
                "id": 42,
                "result": "x".repeat(MAXIMUM_HTTP_BODY_BYTES + 1)
            }),
            None,
        );
        let body = to_bytes(response.into_body(), MAXIMUM_HTTP_BODY_BYTES)
            .await
            .unwrap();
        let body: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(body.pointer("/error/code"), Some(&json!(-32_000)));
        assert_eq!(body["id"], 42);
    }

    #[tokio::test]
    async fn streamable_http_negotiates_unsupported_versions_to_the_latest_protocol() {
        let application_router = fixture_router(&HttpServerOptions::default());
        let response = application_router
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}"#,
            ))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert!(response.headers().get("mcp-session-id").is_some());
        let body = to_bytes(response.into_body(), 16_384).await.unwrap();
        let body: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(
            body.pointer("/result/protocolVersion"),
            Some(&json!(LATEST_HTTP_PROTOCOL))
        );
    }
}
