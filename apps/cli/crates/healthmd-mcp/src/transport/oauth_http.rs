use std::{
    collections::{BTreeSet, HashMap},
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{Method, Request, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse as _, Response},
    routing::get,
};
use secrecy::SecretString;
use serde_json::json;
use tokio::sync::{Mutex, Semaphore};
use tokio_util::sync::CancellationToken;

use crate::{
    HealthMdApplication,
    auth::{
        AccessTokenVerifier, AuthorizationErrorKind, OAuthPrincipal, OAuthResourceServerConfig,
    },
};

use super::streamable_http::{
    HttpServerError, HttpServerOptions, effective_allowed_hosts, mcp_router,
    request_host_and_origin_allowed,
};

const MAXIMUM_SESSION_OWNERS: usize = 4_096;
const MAXIMUM_CONCURRENT_AUTHORIZED_REQUESTS: usize = 64;
const SESSION_OWNER_TTL: Duration = Duration::from_secs(600);

#[derive(Clone)]
struct AuthorizationState {
    configuration: Arc<OAuthResourceServerConfig>,
    verifier: Arc<dyn AccessTokenVerifier>,
    owners: Arc<SessionOwnerStore>,
    admission: Arc<Semaphore>,
    allowed_hosts: Arc<Vec<String>>,
    allowed_origins: Arc<Vec<String>>,
}

#[derive(Default)]
struct SessionOwnerStore {
    entries: Mutex<HashMap<String, SessionOwner>>,
}

struct SessionOwner {
    binding: PrincipalBinding,
    last_seen: Instant,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct PrincipalBinding {
    subject: String,
    tenant: Option<String>,
    issuer: String,
    audience: String,
}

impl From<&OAuthPrincipal> for PrincipalBinding {
    fn from(principal: &OAuthPrincipal) -> Self {
        Self {
            subject: principal.subject.clone(),
            tenant: principal.tenant.clone(),
            issuer: principal.issuer.clone(),
            audience: principal.audience.clone(),
        }
    }
}

impl SessionOwnerStore {
    async fn bind(&self, session_id: &str, principal: &OAuthPrincipal) -> bool {
        let mut entries = self.entries.lock().await;
        let now = Instant::now();
        entries.retain(|_, owner| now.duration_since(owner.last_seen) <= SESSION_OWNER_TTL);
        let binding = PrincipalBinding::from(principal);
        if let Some(owner) = entries.get_mut(session_id) {
            if owner.binding != binding {
                return false;
            }
            owner.last_seen = now;
            return true;
        }
        if entries.len() >= MAXIMUM_SESSION_OWNERS {
            return false;
        }
        entries.insert(
            session_id.to_owned(),
            SessionOwner {
                binding,
                last_seen: now,
            },
        );
        true
    }

    async fn verify(&self, session_id: &str, principal: &OAuthPrincipal) -> bool {
        let mut entries = self.entries.lock().await;
        let now = Instant::now();
        let Some(owner) = entries.get_mut(session_id) else {
            return false;
        };
        if now.duration_since(owner.last_seen) > SESSION_OWNER_TTL
            || owner.binding != PrincipalBinding::from(principal)
        {
            return false;
        }
        owner.last_seen = now;
        true
    }

    async fn delete(&self, session_id: &str) {
        self.entries.lock().await.remove(session_id);
    }
}

/// Build an OAuth-protected Streamable HTTP resource-server router.
///
/// # Errors
///
/// Returns an error when the host allowlist or listener policy is unsafe.
pub fn router(
    application: Arc<HealthMdApplication>,
    options: &HttpServerOptions,
    oauth: OAuthResourceServerConfig,
    verifier: Arc<dyn AccessTokenVerifier>,
    cancellation: CancellationToken,
) -> Result<Router, HttpServerError> {
    router_with_protected_routes(
        application,
        options,
        oauth,
        verifier,
        cancellation,
        Router::new(),
    )
}

/// Build an OAuth-protected MCP router with additional authenticated data-plane routes.
///
/// Additional routes receive [`crate::CallerIdentity`] as a request extension and must enforce their own
/// least-privilege scopes. MCP's 2 MiB body limit is applied only to `/mcp`; added routes must set
/// an appropriate independent limit.
///
/// # Errors
///
/// Returns an error when the host allowlist or listener policy is unsafe.
pub fn router_with_protected_routes(
    application: Arc<HealthMdApplication>,
    options: &HttpServerOptions,
    oauth: OAuthResourceServerConfig,
    verifier: Arc<dyn AccessTokenVerifier>,
    cancellation: CancellationToken,
    additional_protected_routes: Router,
) -> Result<Router, HttpServerError> {
    if !options.bind.ip().is_loopback() {
        return Err(HttpServerError::NonLoopbackBind);
    }
    if options.allowed_hosts.is_empty() {
        return Err(HttpServerError::AllowedHostsRequired);
    }
    let mcp = mcp_router(application, None, cancellation);

    let state = Arc::new(AuthorizationState {
        configuration: Arc::new(oauth),
        verifier,
        owners: Arc::new(SessionOwnerStore::default()),
        admission: Arc::new(Semaphore::new(MAXIMUM_CONCURRENT_AUTHORIZED_REQUESTS)),
        allowed_hosts: Arc::new(effective_allowed_hosts(options)),
        allowed_origins: Arc::new(options.allowed_origins.clone()),
    });
    let metadata_path = state.configuration.protected_resource_metadata_path();
    let protected = mcp
        .merge(additional_protected_routes)
        .layer(middleware::from_fn_with_state(
            Arc::clone(&state),
            authorize,
        ));
    let mut public = Router::new()
        .route("/healthz", get(|| async { "ok" }))
        .route(&metadata_path, get(protected_resource_metadata));
    if metadata_path != "/.well-known/oauth-protected-resource" {
        public = public.route(
            "/.well-known/oauth-protected-resource",
            get(protected_resource_metadata),
        );
    }
    Ok(public.with_state(state).merge(protected))
}

/// Serve OAuth-protected MCP until shutdown.
///
/// # Errors
///
/// Returns an error for unsafe configuration or listener/server I/O failure.
pub async fn serve(
    application: Arc<HealthMdApplication>,
    options: HttpServerOptions,
    oauth: OAuthResourceServerConfig,
    verifier: Arc<dyn AccessTokenVerifier>,
) -> Result<(), HttpServerError> {
    serve_with_protected_routes(application, options, oauth, verifier, Router::new()).await
}

/// Serve OAuth-protected MCP and additional authenticated data-plane routes until shutdown.
///
/// # Errors
///
/// Returns an error for unsafe configuration or listener/server I/O failure.
pub async fn serve_with_protected_routes(
    application: Arc<HealthMdApplication>,
    options: HttpServerOptions,
    oauth: OAuthResourceServerConfig,
    verifier: Arc<dyn AccessTokenVerifier>,
    additional_protected_routes: Router,
) -> Result<(), HttpServerError> {
    let cancellation = CancellationToken::new();
    let application_router = router_with_protected_routes(
        application,
        &options,
        oauth,
        verifier,
        cancellation.clone(),
        additional_protected_routes,
    )?;
    let listener = tokio::net::TcpListener::bind(options.bind).await?;
    axum::serve(listener, application_router)
        .with_graceful_shutdown(async move {
            let _ = tokio::signal::ctrl_c().await;
            cancellation.cancel();
        })
        .await?;
    Ok(())
}

async fn protected_resource_metadata(State(state): State<Arc<AuthorizationState>>) -> Response {
    let mut response = Json(state.configuration.metadata()).into_response();
    response.headers_mut().insert(
        header::ACCESS_CONTROL_ALLOW_ORIGIN,
        header::HeaderValue::from_static("*"),
    );
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        header::HeaderValue::from_static("no-store"),
    );
    response
}

async fn authorize(
    State(state): State<Arc<AuthorizationState>>,
    request: Request<Body>,
    next: Next,
) -> Response {
    let cors_origin = request
        .headers()
        .get(header::ORIGIN)
        .cloned()
        .filter(|_| request_origin_allowed(&request, &state));
    let admission = Arc::clone(&state.admission).try_acquire_owned();
    let mut response = match admission {
        Ok(_permit) => authorize_request(&state, request, next).await,
        Err(_) => service_unavailable(),
    };
    if let Some(origin) = cors_origin {
        apply_cors_headers(&mut response, origin);
    }
    response
}

#[allow(clippy::too_many_lines)]
async fn authorize_request(
    state: &AuthorizationState,
    mut request: Request<Body>,
    next: Next,
) -> Response {
    let minimum_scopes = minimum_request_scopes(&request, &state.configuration);
    if !request_origin_allowed(&request, state) {
        return authorization_response(
            StatusCode::FORBIDDEN,
            &state
                .configuration
                .challenge_for_scopes(&minimum_scopes, None, None),
            "forbidden",
        );
    }
    if request.method() == Method::OPTIONS {
        return cors_preflight_response(&request);
    }
    let Some(token) = bearer_token(request.headers()) else {
        return unauthorized(&state.configuration, &minimum_scopes, None);
    };
    let principal = match state.verifier.verify(SecretString::from(token)).await {
        Ok(principal) => principal,
        Err(error) if error.kind == AuthorizationErrorKind::InvalidToken => {
            return unauthorized(&state.configuration, &minimum_scopes, Some("invalid_token"));
        }
        Err(_) => return service_unavailable(),
    };
    if principal.audience != state.configuration.resource.as_str() {
        return unauthorized(&state.configuration, &minimum_scopes, Some("invalid_token"));
    }
    if let Some(owner_subject) = &state.configuration.owner_subject {
        if &principal.subject != owner_subject {
            return forbidden(
                &state.configuration,
                "invalid_token",
                "The account is not this server's owner.",
                &minimum_scopes,
            );
        }
    }
    if !state
        .configuration
        .required_scopes
        .iter()
        .all(|scope| principal.scopes.contains(scope))
    {
        return forbidden(
            &state.configuration,
            "insufficient_scope",
            "The access token lacks a required scope.",
            &minimum_scopes,
        );
    }
    if request.uri().path().starts_with("/mcp")
        && !principal.scopes.contains("health.summary.read")
        && !principal.scopes.contains("healthmd:read")
    {
        return forbidden(
            &state.configuration,
            "insufficient_scope",
            "The access token lacks the Health.md summary scope.",
            &BTreeSet::from(["health.summary.read".to_owned()]),
        );
    }
    let request_session = request
        .headers()
        .get("mcp-session-id")
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);
    if let Some(session_id) = &request_session {
        if !state.owners.verify(session_id, &principal).await {
            return forbidden(
                &state.configuration,
                "invalid_token",
                "The MCP session belongs to another authorization grant.",
                &minimum_scopes,
            );
        }
    }
    request.headers_mut().remove(header::AUTHORIZATION);
    request.extensions_mut().insert(principal.caller_identity());
    let delete_session = request.method() == Method::DELETE;
    let mcp_request = request.uri().path().starts_with("/mcp");
    let mut response = next.run(request).await;
    if response.status().is_success() {
        if let Some(session_id) = response
            .headers()
            .get("mcp-session-id")
            .and_then(|value| value.to_str().ok())
        {
            if !state.owners.bind(session_id, &principal).await {
                return service_unavailable();
            }
        }
    }
    if delete_session && response.status().is_success() {
        if let Some(session_id) = request_session {
            state.owners.delete(&session_id).await;
        }
    }
    if mcp_request && response.status() == StatusCode::FORBIDDEN {
        let scopes = BTreeSet::from([
            "health.detail.read".to_owned(),
            "health.summary.read".to_owned(),
        ]);
        if let Ok(challenge) = state
            .configuration
            .challenge_for_scopes(
                &scopes,
                Some("insufficient_scope"),
                Some("The access token lacks the Health.md detail scope."),
            )
            .parse()
        {
            response
                .headers_mut()
                .insert(header::WWW_AUTHENTICATE, challenge);
        }
    }
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        header::HeaderValue::from_static("no-store"),
    );
    response
}

fn cors_preflight_response(request: &Request<Body>) -> Response {
    let method_allowed = request
        .headers()
        .get("access-control-request-method")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|method| matches!(method.trim(), "GET" | "POST" | "PUT" | "DELETE"));
    let headers_allowed = request
        .headers()
        .get("access-control-request-headers")
        .and_then(|value| value.to_str().ok())
        .is_none_or(|headers| {
            headers.split(',').all(|name| {
                matches!(
                    name.trim().to_ascii_lowercase().as_str(),
                    "authorization" | "content-type" | "mcp-protocol-version" | "mcp-session-id"
                )
            })
        });
    if !method_allowed || !headers_allowed {
        return empty_authorization_response(StatusCode::FORBIDDEN);
    }
    Response::builder()
        .status(StatusCode::NO_CONTENT)
        .header(
            header::ACCESS_CONTROL_ALLOW_METHODS,
            "GET, POST, PUT, DELETE, OPTIONS",
        )
        .header(
            header::ACCESS_CONTROL_ALLOW_HEADERS,
            "authorization, content-type, mcp-protocol-version, mcp-session-id",
        )
        .header(header::ACCESS_CONTROL_MAX_AGE, "600")
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::empty())
        .expect("valid CORS preflight response")
}

fn apply_cors_headers(response: &mut Response, origin: header::HeaderValue) {
    response
        .headers_mut()
        .insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, origin);
    response.headers_mut().insert(
        header::ACCESS_CONTROL_EXPOSE_HEADERS,
        header::HeaderValue::from_static("mcp-session-id, www-authenticate"),
    );
    response
        .headers_mut()
        .insert(header::VARY, header::HeaderValue::from_static("Origin"));
}

fn empty_authorization_response(status: StatusCode) -> Response {
    Response::builder()
        .status(status)
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::empty())
        .expect("valid authorization response")
}

fn request_origin_allowed(request: &Request<Body>, state: &AuthorizationState) -> bool {
    request_host_and_origin_allowed(request, &state.allowed_hosts, &state.allowed_origins)
}

fn minimum_request_scopes(
    request: &Request<Body>,
    configuration: &OAuthResourceServerConfig,
) -> BTreeSet<String> {
    match (request.method(), request.uri().path()) {
        (_, path) if path.starts_with("/mcp") => BTreeSet::from(["health.summary.read".to_owned()]),
        (&Method::POST, "/data/v1/days") => BTreeSet::from(["health.sync.write".to_owned()]),
        (&Method::PUT | &Method::DELETE, "/data/v1/consent")
        | (&Method::DELETE, "/data/v1/account") => {
            BTreeSet::from(["health.account.manage".to_owned()])
        }
        (_, "/data/v1/status") => BTreeSet::from(["health.summary.read".to_owned()]),
        (_, "/data/v1/control-status") => BTreeSet::from(["health.account.manage".to_owned()]),
        _ => configuration.required_scopes.clone(),
    }
}

fn bearer_token(headers: &header::HeaderMap) -> Option<String> {
    let value = headers.get(header::AUTHORIZATION)?.to_str().ok()?;
    let (scheme, token) = value.split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("bearer")
        || token.is_empty()
        || token.trim() != token
        || token.contains(char::is_whitespace)
    {
        return None;
    }
    Some(token.to_owned())
}

fn unauthorized(
    configuration: &OAuthResourceServerConfig,
    scopes: &BTreeSet<String>,
    error: Option<&str>,
) -> Response {
    authorization_response(
        StatusCode::UNAUTHORIZED,
        &configuration.challenge_for_scopes(scopes, error, Some("Authentication is required.")),
        "unauthorized",
    )
}

fn forbidden(
    configuration: &OAuthResourceServerConfig,
    error: &str,
    description: &str,
    scopes: &BTreeSet<String>,
) -> Response {
    authorization_response(
        StatusCode::FORBIDDEN,
        &configuration.challenge_for_scopes(scopes, Some(error), Some(description)),
        "forbidden",
    )
}

fn authorization_response(status: StatusCode, challenge: &str, code: &str) -> Response {
    let mut response = (
        status,
        Json(json!({
            "error": code,
            "message": if status == StatusCode::UNAUTHORIZED {
                "Authentication is required."
            } else {
                "The authorization grant cannot access this MCP request."
            }
        })),
    )
        .into_response();
    if let Ok(value) = challenge.parse() {
        response
            .headers_mut()
            .insert(header::WWW_AUTHENTICATE, value);
    }
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        header::HeaderValue::from_static("no-store"),
    );
    response
}

fn service_unavailable() -> Response {
    let mut response = (
        StatusCode::SERVICE_UNAVAILABLE,
        Json(json!({
            "error": "authorization_unavailable",
            "message": "Token verification is temporarily unavailable."
        })),
    )
        .into_response();
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        header::HeaderValue::from_static("no-store"),
    );
    response
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use async_trait::async_trait;
    use axum::{
        Extension,
        body::{Body, to_bytes},
        http::Request,
        routing::get as route_get,
    };
    use secrecy::ExposeSecret as _;
    use serde_json::{Value, json};
    use tower::ServiceExt as _;
    use url::Url;

    use super::*;
    use crate::{
        BackendCapabilities, BackendError, CallContext, HealthDataBackend, QueryPageRequest,
        SurfaceProfile,
        auth::{AuthorizationError, OAuthPrincipal},
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
            Ok(json!({
                "ready": true,
                "authorized": context.caller.mode == crate::CallerMode::OAuth,
                "detail_authorized": context.caller.has_scope("health.detail.read")
            }))
        }

        async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
            self.readiness(context).await
        }

        async fn query_page(
            &self,
            _context: &CallContext,
            _request: QueryPageRequest,
        ) -> Result<Value, BackendError> {
            Ok(
                json!({"schema":"healthmd.query_response","schema_version":1,"items":[],"next_cursor":null}),
            )
        }
    }

    struct FixtureVerifier;

    #[async_trait]
    impl AccessTokenVerifier for FixtureVerifier {
        async fn verify(&self, token: SecretString) -> Result<OAuthPrincipal, AuthorizationError> {
            let token = token.expose_secret();
            let (subject, scopes) = match token {
                "owner" => ("owner", BTreeSet::from(["healthmd:read".to_owned()])),
                "owner-detail" => (
                    "owner",
                    BTreeSet::from(["health.detail.read".to_owned(), "healthmd:read".to_owned()]),
                ),
                "other" => ("other", BTreeSet::from(["healthmd:read".to_owned()])),
                "unscoped" => ("owner", BTreeSet::new()),
                _ => return Err(AuthorizationError::invalid_token()),
            };
            Ok(OAuthPrincipal {
                subject: subject.to_owned(),
                tenant: None,
                issuer: "https://auth.example.com".to_owned(),
                audience: "https://mcp.example.com/mcp".to_owned(),
                scopes,
            })
        }
    }

    #[test]
    fn oauth_listener_requires_loopback_even_with_a_public_resource_url() {
        let application = Arc::new(HealthMdApplication::new(
            Arc::new(FixtureBackend),
            SurfaceProfile::RemoteReadOnly,
        ));
        let options = HttpServerOptions {
            bind: "0.0.0.0:8787".parse().unwrap(),
            allowed_hosts: vec!["mcp.example.com".to_owned()],
            ..HttpServerOptions::default()
        };
        let oauth = OAuthResourceServerConfig::new(
            Url::parse("https://mcp.example.com/mcp").unwrap(),
            vec![Url::parse("https://auth.example.com").unwrap()],
            ["healthmd:read"],
        )
        .unwrap();
        assert!(matches!(
            router(
                application,
                &options,
                oauth,
                Arc::new(FixtureVerifier),
                CancellationToken::new(),
            ),
            Err(HttpServerError::NonLoopbackBind)
        ));
    }

    fn fixture_router() -> Router {
        let application = Arc::new(HealthMdApplication::new(
            Arc::new(FixtureBackend),
            SurfaceProfile::Hosted,
        ));
        let options = HttpServerOptions {
            allowed_hosts: vec!["mcp.example.com".to_owned()],
            allowed_origins: vec!["https://app.example.com".to_owned()],
            ..HttpServerOptions::default()
        };
        let oauth = OAuthResourceServerConfig::new(
            Url::parse("https://mcp.example.com/mcp").unwrap(),
            vec![Url::parse("https://auth.example.com").unwrap()],
            ["healthmd:read"],
        )
        .unwrap()
        .with_owner_subject("owner");
        router(
            application,
            &options,
            oauth,
            Arc::new(FixtureVerifier),
            CancellationToken::new(),
        )
        .unwrap()
    }

    fn post(body: &str, token: Option<&str>) -> Request<Body> {
        let mut request = Request::builder()
            .method("POST")
            .uri("/mcp")
            .header("host", "mcp.example.com")
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .body(Body::from(body.to_owned()))
            .unwrap();
        if let Some(token) = token {
            request.headers_mut().insert(
                header::AUTHORIZATION,
                format!("Bearer {token}").parse().unwrap(),
            );
        }
        request
    }

    #[tokio::test]
    async fn additional_routes_are_authenticated_and_receive_the_resolved_caller() {
        async fn whoami(
            Extension(caller): Extension<crate::CallerIdentity>,
            headers: header::HeaderMap,
        ) -> Json<Value> {
            Json(json!({
                "subject": caller.subject,
                "scopes": caller.scopes,
                "authorization_forwarded": headers.contains_key(header::AUTHORIZATION)
            }))
        }

        let application = Arc::new(HealthMdApplication::new(
            Arc::new(FixtureBackend),
            SurfaceProfile::Hosted,
        ));
        let options = HttpServerOptions {
            allowed_hosts: vec!["mcp.example.com".to_owned()],
            ..HttpServerOptions::default()
        };
        let oauth = OAuthResourceServerConfig::new(
            Url::parse("https://mcp.example.com/mcp").unwrap(),
            vec![Url::parse("https://auth.example.com").unwrap()],
            ["healthmd:read", "health.account.manage"],
        )
        .unwrap()
        .with_required_scopes(std::iter::empty::<&str>());
        let application_router = router_with_protected_routes(
            application,
            &options,
            oauth,
            Arc::new(FixtureVerifier),
            CancellationToken::new(),
            Router::new().route("/data/v1/whoami", route_get(whoami)),
        )
        .unwrap();

        let missing = Request::builder()
            .uri("/data/v1/whoami")
            .header("host", "mcp.example.com")
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            application_router
                .clone()
                .oneshot(missing)
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );

        let authorized = Request::builder()
            .uri("/data/v1/whoami")
            .header("host", "mcp.example.com")
            .header(header::AUTHORIZATION, "Bearer owner")
            .body(Body::empty())
            .unwrap();
        let response = application_router.oneshot(authorized).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), 16_384).await.unwrap();
        let body: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(body["subject"], "owner");
        assert_eq!(body["authorization_forwarded"], false);
    }

    #[tokio::test]
    async fn metadata_is_public_and_missing_tokens_receive_a_discovery_challenge() {
        let application_router = fixture_router();
        let metadata = Request::builder()
            .uri("/.well-known/oauth-protected-resource/mcp")
            .header("host", "mcp.example.com")
            .body(Body::empty())
            .unwrap();
        let response = application_router.clone().oneshot(metadata).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), 16_384).await.unwrap();
        let metadata: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(metadata["resource"], "https://mcp.example.com/mcp");

        let response = application_router
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
                None,
            ))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        let challenge = response
            .headers()
            .get(header::WWW_AUTHENTICATE)
            .unwrap()
            .to_str()
            .unwrap();
        assert!(challenge.contains("oauth-protected-resource/mcp"));
        assert!(challenge.contains("scope=\"health.summary.read\""));
    }

    #[tokio::test]
    async fn allowlisted_browser_origins_receive_preflight_and_actual_cors_headers() {
        let application_router = fixture_router();
        let preflight = Request::builder()
            .method(Method::OPTIONS)
            .uri("/mcp")
            .header("host", "mcp.example.com")
            .header(header::ORIGIN, "https://app.example.com")
            .header("access-control-request-method", "POST")
            .header(
                "access-control-request-headers",
                "authorization, content-type, mcp-session-id, mcp-protocol-version",
            )
            .body(Body::empty())
            .unwrap();
        let response = application_router.clone().oneshot(preflight).await.unwrap();
        assert_eq!(response.status(), StatusCode::NO_CONTENT);
        assert_eq!(
            response.headers().get(header::ACCESS_CONTROL_ALLOW_ORIGIN),
            Some(&header::HeaderValue::from_static("https://app.example.com"))
        );
        assert!(
            response
                .headers()
                .contains_key(header::ACCESS_CONTROL_ALLOW_HEADERS)
        );

        let mut unauthorized = post(
            r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
            None,
        );
        unauthorized
            .headers_mut()
            .insert(header::ORIGIN, "https://app.example.com".parse().unwrap());
        let response = application_router.oneshot(unauthorized).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(
            response.headers().get(header::ACCESS_CONTROL_ALLOW_ORIGIN),
            Some(&header::HeaderValue::from_static("https://app.example.com"))
        );
        assert!(
            response
                .headers()
                .contains_key(header::ACCESS_CONTROL_EXPOSE_HEADERS)
        );
    }

    #[tokio::test]
    async fn lossless_tools_return_a_minimum_scope_step_up_challenge() {
        let application_router = fixture_router();
        let response = application_router
            .clone()
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
                Some("owner"),
            ))
            .await
            .unwrap();
        let session = response.headers()["mcp-session-id"].clone();
        let mut query = post(
            r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"healthmd_query","arguments":{"request":{},"detail_level":"lossless"}}}"#,
            Some("owner"),
        );
        query
            .headers_mut()
            .insert("mcp-session-id", session.clone());
        query
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.clone().oneshot(query).await.unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
        let challenge = response
            .headers()
            .get(header::WWW_AUTHENTICATE)
            .unwrap()
            .to_str()
            .unwrap();
        assert!(challenge.contains("error=\"insufficient_scope\""));
        assert!(challenge.contains("health.summary.read"));
        assert!(challenge.contains("health.detail.read"));
        assert!(!challenge.contains("health.sync.write"));
        assert!(!challenge.contains("health.account.manage"));

        let mut stepped_up = post(
            r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"healthmd_query","arguments":{"request":{},"detail_level":"lossless"}}}"#,
            Some("owner-detail"),
        );
        stepped_up.headers_mut().insert("mcp-session-id", session);
        stepped_up
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.oneshot(stepped_up).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn every_tool_call_uses_the_current_tokens_scopes() {
        let application_router = fixture_router();
        let response = application_router
            .clone()
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#,
                Some("owner-detail"),
            ))
            .await
            .unwrap();
        let session = response.headers()["mcp-session-id"].clone();
        let mut status = post(
            r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"healthmd_status","arguments":{}}}"#,
            Some("owner"),
        );
        status.headers_mut().insert("mcp-session-id", session);
        status
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.oneshot(status).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), 65_536).await.unwrap();
        let body = String::from_utf8_lossy(&body);
        assert!(body.contains("detail_authorized\\\":false"));
        assert!(!body.contains("detail_authorized\\\":true"));
    }

    #[tokio::test]
    async fn sessions_are_bound_to_the_authorized_owner_and_scope() {
        let application_router = fixture_router();
        let initialize = post(
            r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
            Some("owner"),
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

        let mut list = post(
            r#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
            Some("owner"),
        );
        list.headers_mut()
            .insert("mcp-session-id", session.parse().unwrap());
        list.headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.clone().oneshot(list).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let mut status = post(
            r#"{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"healthmd_status","arguments":{}}}"#,
            Some("owner"),
        );
        status
            .headers_mut()
            .insert("mcp-session-id", session.parse().unwrap());
        status
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.clone().oneshot(status).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), 65_536).await.unwrap();
        assert!(String::from_utf8_lossy(&body).contains("authorized\\\":true"));

        let mut stolen = post(
            r#"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}"#,
            Some("other"),
        );
        stolen
            .headers_mut()
            .insert("mcp-session-id", session.parse().unwrap());
        stolen
            .headers_mut()
            .insert("mcp-protocol-version", "2025-11-25".parse().unwrap());
        let response = application_router.clone().oneshot(stolen).await.unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);

        let response = application_router
            .oneshot(post(
                r#"{"jsonrpc":"2.0","id":4,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
                Some("unscoped"),
            ))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
    }
}
