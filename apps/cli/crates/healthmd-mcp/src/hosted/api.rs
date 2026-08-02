use std::sync::Arc;

use axum::{
    Extension, Json, Router,
    extract::{DefaultBodyLimit, State, rejection::JsonRejection},
    http::{StatusCode, header},
    response::{IntoResponse as _, Response},
    routing::{delete, get, post, put},
};
use serde::Serialize;
use serde_json::json;

use crate::CallerIdentity;

use super::{
    HostedConsentRequest, HostedConsentResult, HostedConsentRevocationRequest, HostedDataStore,
    HostedError, HostedSyncRequest, HostedSyncResult, MAX_SYNC_REQUEST_BYTES,
};

/// OAuth-protected synchronization routes. The parent OAuth router supplies the verified
/// [`CallerIdentity`] extension and removes the bearer credential before dispatch.
pub fn router(store: Arc<HostedDataStore>) -> Router {
    let ordinary = Router::new()
        .route("/data/v1/status", get(status))
        .route("/data/v1/control-status", get(control_status))
        .route(
            "/data/v1/consent",
            put(replace_consent).delete(revoke_consent),
        )
        .route("/data/v1/account", delete(delete_account));
    let uploads = Router::new()
        .route("/data/v1/days", post(upload_days))
        .layer(DefaultBodyLimit::max(MAX_SYNC_REQUEST_BYTES));
    ordinary.merge(uploads).with_state(store)
}

async fn status(
    State(store): State<Arc<HostedDataStore>>,
    Extension(caller): Extension<CallerIdentity>,
) -> Response {
    if !has_any_scope(&caller, &["health.summary.read", "healthmd:read"]) {
        return api_error(scope_error()).into_response();
    }
    api_result(store.status(&caller).await)
}

async fn control_status(
    State(store): State<Arc<HostedDataStore>>,
    Extension(caller): Extension<CallerIdentity>,
) -> Response {
    if !caller.has_scope("health.account.manage") {
        return api_error(scope_error()).into_response();
    }
    api_result(store.control_status(&caller).await)
}

async fn replace_consent(
    State(store): State<Arc<HostedDataStore>>,
    Extension(caller): Extension<CallerIdentity>,
    payload: Result<Json<HostedConsentRequest>, JsonRejection>,
) -> Response {
    if !caller.has_scope("health.account.manage") {
        return api_error(scope_error()).into_response();
    }
    let Ok(Json(request)) = payload else {
        return api_error(consent_payload_error());
    };
    api_consent_result(store.replace_consent(&caller, request).await)
}

async fn revoke_consent(
    State(store): State<Arc<HostedDataStore>>,
    Extension(caller): Extension<CallerIdentity>,
    payload: Result<Json<HostedConsentRevocationRequest>, JsonRejection>,
) -> Response {
    if !caller.has_scope("health.account.manage") {
        return api_error(scope_error()).into_response();
    }
    let Ok(Json(request)) = payload else {
        return api_error(consent_payload_error());
    };
    api_consent_result(store.purge_consent(&caller, request).await)
}

async fn upload_days(
    State(store): State<Arc<HostedDataStore>>,
    Extension(caller): Extension<CallerIdentity>,
    payload: Result<Json<HostedSyncRequest>, JsonRejection>,
) -> Response {
    if !caller.has_scope("health.sync.write") {
        return api_error(scope_error()).into_response();
    }
    let Json(request) = match payload {
        Ok(request) => request,
        Err(error) if error.status() == StatusCode::PAYLOAD_TOO_LARGE => {
            return api_error(HostedError::new(
                "healthmd_sync_too_large",
                "The synchronization request exceeds the byte limit.",
            ));
        }
        Err(_) => {
            return api_error(HostedError::new(
                "healthmd_sync_invalid",
                "The synchronization request is invalid.",
            ));
        }
    };
    api_sync_result(store.upload_days(&caller, request).await)
}

async fn delete_account(
    State(store): State<Arc<HostedDataStore>>,
    Extension(caller): Extension<CallerIdentity>,
) -> Response {
    if !caller.has_scope("health.account.manage") {
        return api_error(scope_error()).into_response();
    }
    match store.delete_account(&caller).await {
        Ok(()) => no_store(
            (
                StatusCode::OK,
                Json(json!({
                    "schema": "healthmd.hosted_account_deletion",
                    "schema_version": 1,
                    "status": "deleted"
                })),
            )
                .into_response(),
        ),
        Err(error) => api_error(error),
    }
}

#[derive(Serialize)]
struct HostedConsentAPIResult {
    schema: &'static str,
    schema_version: u8,
    consent_revision: u64,
    consent_state: &'static str,
}

#[derive(Serialize)]
struct HostedSyncAPIResult {
    schema: &'static str,
    schema_version: u8,
    consent_revision: u64,
    changed_day_count: usize,
    unchanged_day_count: usize,
}

fn api_consent_result(result: Result<HostedConsentResult, HostedError>) -> Response {
    api_result(result.map(|value| HostedConsentAPIResult {
        schema: value.schema,
        schema_version: value.schema_version,
        consent_revision: value.consent_revision,
        consent_state: value.consent_state,
    }))
}

fn api_sync_result(result: Result<HostedSyncResult, HostedError>) -> Response {
    api_result(result.map(|value| HostedSyncAPIResult {
        schema: value.schema,
        schema_version: value.schema_version,
        consent_revision: value.consent_revision,
        changed_day_count: value.changed_day_count,
        unchanged_day_count: value.unchanged_day_count,
    }))
}

fn api_result<T: Serialize>(result: Result<T, HostedError>) -> Response {
    match result {
        Ok(value) => no_store((StatusCode::OK, Json(value)).into_response()),
        Err(error) => api_error(error),
    }
}

fn api_error(error: HostedError) -> Response {
    let status = match error.code {
        "healthmd_identity_invalid" | "healthmd_scope_required" => StatusCode::FORBIDDEN,
        "healthmd_consent_violation" | "healthmd_consent_required" | "healthmd_consent_expired" => {
            StatusCode::FORBIDDEN
        }
        "healthmd_consent_revision_stale" | "healthmd_query_cursor_stale" => StatusCode::CONFLICT,
        "healthmd_sync_too_large" | "healthmd_sync_day_too_large" => StatusCode::PAYLOAD_TOO_LARGE,
        "healthmd_storage_unavailable" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::BAD_REQUEST,
    };
    no_store(
        (
            status,
            Json(json!({
                "error": error.code,
                "message": error.message,
                "retryable": error.retryable
            })),
        )
            .into_response(),
    )
}

fn consent_payload_error() -> HostedError {
    HostedError::new(
        "healthmd_consent_invalid",
        "The hosted consent policy is invalid.",
    )
}

fn scope_error() -> HostedError {
    HostedError::new(
        "healthmd_scope_required",
        "The access token lacks the required hosted data scope.",
    )
}

fn has_any_scope(caller: &CallerIdentity, scopes: &[&str]) -> bool {
    scopes.iter().any(|scope| caller.has_scope(scope))
}

fn no_store(mut response: Response) -> Response {
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        header::HeaderValue::from_static("no-store"),
    );
    response
}

#[cfg(test)]
mod tests {
    use axum::{
        body::{Body, to_bytes},
        http::Request,
    };
    use tempfile::TempDir;
    use tower::ServiceExt as _;

    use super::*;
    use crate::CallerMode;

    fn caller(scopes: &[&str]) -> CallerIdentity {
        CallerIdentity {
            subject: "api-owner".to_owned(),
            tenant: Some("api-tenant".to_owned()),
            issuer: Some("https://issuer.example".to_owned()),
            scopes: scopes.iter().map(|scope| (*scope).to_owned()).collect(),
            mode: CallerMode::OAuth,
        }
    }

    #[tokio::test]
    async fn data_routes_require_independent_scopes_and_never_cache() {
        let directory = TempDir::new().unwrap();
        let store = Arc::new(HostedDataStore::new_test(directory.path(), [7; 32]).unwrap());
        let application = router(store);

        let unauthorized = Request::builder()
            .uri("/data/v1/status")
            .extension(caller(&[]))
            .body(Body::empty())
            .unwrap();
        let response = application.clone().oneshot(unauthorized).await.unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
        assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");

        let management_only = Request::builder()
            .uri("/data/v1/status")
            .extension(caller(&["health.account.manage"]))
            .body(Body::empty())
            .unwrap();
        let response = application.clone().oneshot(management_only).await.unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);

        let write_only = Request::builder()
            .uri("/data/v1/status")
            .extension(caller(&["health.sync.write"]))
            .body(Body::empty())
            .unwrap();
        let response = application.clone().oneshot(write_only).await.unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);

        let authorized = Request::builder()
            .uri("/data/v1/control-status")
            .extension(caller(&["health.account.manage"]))
            .body(Body::empty())
            .unwrap();
        let response = application.oneshot(authorized).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
        let body = to_bytes(response.into_body(), 16_384).await.unwrap();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["schema"], "healthmd.hosted_control_status");
        assert_eq!(value["owner_binding"].as_str().unwrap().len(), 64);
        for forbidden in [
            "ready",
            "dataset_revision",
            "synchronized_day_count",
            "first_owner_date",
            "last_owner_date",
        ] {
            assert!(value.get(forbidden).is_none());
        }
    }

    #[tokio::test]
    async fn malformed_consent_is_health_free_and_never_cached() {
        let directory = TempDir::new().unwrap();
        let store = Arc::new(HostedDataStore::new_test(directory.path(), [8; 32]).unwrap());
        let application = router(store);
        let request = Request::builder()
            .method("PUT")
            .uri("/data/v1/consent")
            .header(header::CONTENT_TYPE, "application/json")
            .extension(caller(&["health.account.manage"]))
            .body(Body::from(
                r#"{"revision":1,"allowed_metric_ids":["steps","steps"],"allowed_source_ids":["apple_health","healthmd_summary"],"allowed_provider_ids":[],"maximum_detail":"summary","retention_days":30}"#,
            ))
            .unwrap();
        let response = application.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
        let body = to_bytes(response.into_body(), 16_384).await.unwrap();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["error"], "healthmd_consent_invalid");
    }

    #[tokio::test]
    async fn lifecycle_mutation_responses_disclose_only_required_acknowledgements() {
        let response = api_consent_result(Ok(HostedConsentResult {
            schema: "healthmd.hosted_consent_result",
            schema_version: 1,
            consent_revision: 7,
            dataset_revision: 11,
            consent_state: "active",
            synchronized_day_count: 29,
            purged_day_count: 3,
        }));
        let body = to_bytes(response.into_body(), 16_384).await.unwrap();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["consent_revision"], 7);
        assert_eq!(value["consent_state"], "active");
        for forbidden in [
            "dataset_revision",
            "synchronized_day_count",
            "purged_day_count",
        ] {
            assert!(value.get(forbidden).is_none());
        }

        let response = api_sync_result(Ok(HostedSyncResult {
            schema: "healthmd.hosted_sync_result",
            schema_version: 1,
            consent_revision: 7,
            dataset_revision: 12,
            changed_day_count: 2,
            unchanged_day_count: 1,
            purged_day_count: 4,
        }));
        let body = to_bytes(response.into_body(), 16_384).await.unwrap();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["changed_day_count"], 2);
        assert_eq!(value["unchanged_day_count"], 1);
        for forbidden in ["dataset_revision", "purged_day_count"] {
            assert!(value.get(forbidden).is_none());
        }
    }

    #[tokio::test]
    async fn account_management_does_not_accept_sync_only_scope() {
        let directory = TempDir::new().unwrap();
        let store = Arc::new(HostedDataStore::new_test(directory.path(), [9; 32]).unwrap());
        let application = router(store);
        let request = Request::builder()
            .method("DELETE")
            .uri("/data/v1/account")
            .extension(caller(&["health.sync.write"]))
            .body(Body::empty())
            .unwrap();
        let response = application.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
    }
}
