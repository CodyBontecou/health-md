use std::collections::BTreeSet;

use async_trait::async_trait;
use serde_json::Value;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

/// Stable identity and grants resolved by the transport before application dispatch.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CallerIdentity {
    pub subject: String,
    pub tenant: Option<String>,
    pub issuer: Option<String>,
    pub scopes: BTreeSet<String>,
    pub mode: CallerMode,
}

impl CallerIdentity {
    pub fn local() -> Self {
        Self {
            subject: "local-user".to_owned(),
            tenant: None,
            issuer: None,
            scopes: BTreeSet::from([
                "healthmd:read".to_owned(),
                "healthmd:export".to_owned(),
                "healthmd:pair".to_owned(),
            ]),
            mode: CallerMode::LocalStdio,
        }
    }

    pub fn local_read_only() -> Self {
        Self {
            subject: "local-user".to_owned(),
            tenant: None,
            issuer: None,
            scopes: BTreeSet::from(["healthmd:read".to_owned()]),
            mode: CallerMode::LocalStdio,
        }
    }

    pub fn loopback() -> Self {
        Self {
            subject: "local-user".to_owned(),
            tenant: None,
            issuer: None,
            scopes: BTreeSet::from(["healthmd:read".to_owned()]),
            mode: CallerMode::LocalHttp,
        }
    }

    pub fn remote_owner(subject: impl Into<String>) -> Self {
        Self {
            subject: subject.into(),
            tenant: None,
            issuer: None,
            scopes: BTreeSet::from(["healthmd:read".to_owned()]),
            mode: CallerMode::OAuth,
        }
    }

    pub fn has_scope(&self, scope: &str) -> bool {
        self.scopes.contains(scope)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CallerMode {
    LocalStdio,
    LocalHttp,
    OAuth,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProgressUpdate {
    pub progress: u64,
    pub total: Option<u64>,
    pub message: String,
}

/// Per-call state that is safe to pass through application and backend layers.
#[derive(Clone, Debug)]
pub struct CallContext {
    pub caller: CallerIdentity,
    pub cancellation: CancellationToken,
    pub session_id: Option<String>,
    pub progress: Option<mpsc::Sender<ProgressUpdate>>,
}

impl CallContext {
    pub fn report_progress(&self, update: ProgressUpdate) {
        if let Some(progress) = &self.progress {
            let _ = progress.try_send(update);
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BackendCapabilities {
    pub source_kind: String,
    pub transport: String,
    pub supports_queries: bool,
    pub supports_local_file_exports: bool,
    pub requires_foreground_source: bool,
    pub instructions: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QueryDetailLevel {
    Summary,
    Lossless,
}

/// One transport-independent request to the source's typed query evaluator.
#[derive(Clone, Debug, PartialEq)]
pub struct QueryPageRequest {
    pub query: Value,
    pub detail_level: QueryDetailLevel,
}

/// A local pairing listener that is ready for the returned QR code to be scanned.
#[derive(Clone, Debug, PartialEq)]
pub struct PairingStartResult {
    pub receipt: Value,
    pub qr_png: Vec<u8>,
}

/// Stable, health-free backend failure. Arbitrary upstream error text must never be copied here.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BackendError {
    pub code: String,
    pub message: String,
    pub retryable: bool,
    pub job_id: Option<Uuid>,
    pub wake_window_seconds: Option<u64>,
}

impl BackendError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            retryable: false,
            job_id: None,
            wake_window_seconds: None,
        }
    }

    #[must_use]
    pub fn retryable(mut self, retryable: bool) -> Self {
        self.retryable = retryable;
        self
    }

    #[must_use]
    pub fn with_job_id(mut self, job_id: Uuid) -> Self {
        self.job_id = Some(job_id);
        self
    }

    #[must_use]
    pub const fn with_wake_window_seconds(mut self, seconds: u64) -> Self {
        self.wake_window_seconds = Some(seconds);
        self
    }
}

#[async_trait]
pub trait HealthDataBackend: Send + Sync {
    fn capabilities(&self) -> BackendCapabilities;

    async fn readiness(&self, context: &CallContext) -> Result<Value, BackendError>;

    async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError>;

    async fn query_page(
        &self,
        context: &CallContext,
        request: QueryPageRequest,
    ) -> Result<Value, BackendError>;

    async fn start_pairing(
        &self,
        _context: &CallContext,
        _timeout_seconds: u64,
    ) -> Result<PairingStartResult, BackendError> {
        Err(BackendError::new(
            "healthmd_pairing_unsupported",
            "This Health.md data source does not support local device pairing.",
        ))
    }

    async fn pairing_status(
        &self,
        _context: &CallContext,
        _pairing_session_id: Uuid,
    ) -> Result<Value, BackendError> {
        Err(BackendError::new(
            "healthmd_pairing_unsupported",
            "This Health.md data source does not support local device pairing.",
        ))
    }

    async fn start_export(
        &self,
        _context: &CallContext,
        _job_id: Uuid,
        _arguments: &Value,
    ) -> Result<Value, BackendError> {
        Err(BackendError::new(
            "healthmd_export_unsupported",
            "This Health.md data source does not support local file exports.",
        ))
    }

    async fn export_status(
        &self,
        _context: &CallContext,
        job_id: Uuid,
    ) -> Result<Value, BackendError> {
        Err(BackendError::new(
            "healthmd_export_unsupported",
            "This Health.md data source does not support local export jobs.",
        )
        .with_job_id(job_id))
    }

    async fn resume_export(
        &self,
        _context: &CallContext,
        job_id: Uuid,
        _arguments: &Value,
    ) -> Result<Value, BackendError> {
        Err(BackendError::new(
            "healthmd_export_unsupported",
            "This Health.md data source does not support local export jobs.",
        )
        .with_job_id(job_id))
    }

    async fn cancel_export(
        &self,
        _context: &CallContext,
        job_id: Uuid,
    ) -> Result<Value, BackendError> {
        Err(BackendError::new(
            "healthmd_export_unsupported",
            "This Health.md data source does not support local export jobs.",
        )
        .with_job_id(job_id))
    }
}

/// A read-only store of immutable Health.md export artifacts.
///
/// Implementations may use a local directory, a Health.md-owned database, or hosted object
/// storage. The public query and grant contracts remain transport- and storage-neutral.
#[async_trait]
pub trait ArtifactStore: Send + Sync {
    fn capabilities(&self) -> BackendCapabilities;

    async fn readiness(&self, context: &CallContext) -> Result<Value, BackendError>;

    async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError>;

    async fn query_page(
        &self,
        context: &CallContext,
        request: crate::AgentDataQueryRequest,
    ) -> Result<Value, BackendError>;
}

/// Adapts an [`ArtifactStore`] to the existing CLI/MCP backend seam.
pub struct ArtifactStoreBackend {
    store: std::sync::Arc<dyn ArtifactStore>,
}

impl ArtifactStoreBackend {
    #[must_use]
    pub fn new(store: std::sync::Arc<dyn ArtifactStore>) -> Self {
        Self { store }
    }
}

#[async_trait]
impl HealthDataBackend for ArtifactStoreBackend {
    fn capabilities(&self) -> BackendCapabilities {
        self.store.capabilities()
    }

    async fn readiness(&self, context: &CallContext) -> Result<Value, BackendError> {
        self.store.readiness(context).await
    }

    async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
        self.store.doctor(context).await
    }

    async fn query_page(
        &self,
        context: &CallContext,
        request: QueryPageRequest,
    ) -> Result<Value, BackendError> {
        let query = crate::AgentDataQueryRequest::from_value(request.query).map_err(|_| {
            BackendError::new(
                "healthmd_agent_query_invalid",
                "The Agent Data query did not match the supported contract.",
            )
        })?;
        let expected_detail = match &query.operation {
            crate::AgentDataOperation::Records { detail_level, .. } => Some(match detail_level {
                crate::AgentDataDetailLevel::Common => QueryDetailLevel::Summary,
                crate::AgentDataDetailLevel::Lossless => QueryDetailLevel::Lossless,
            }),
            _ => None,
        };
        if expected_detail.is_some_and(|value| value != request.detail_level) {
            return Err(BackendError::new(
                "healthmd_agent_query_invalid",
                "The Agent Data query detail level was inconsistent.",
            ));
        }
        self.store.query_page(context, query).await
    }
}

#[cfg(test)]
mod artifact_store_tests {
    use std::sync::Arc;

    use serde_json::json;

    use super::*;

    struct RejectingStore;

    #[async_trait]
    impl ArtifactStore for RejectingStore {
        fn capabilities(&self) -> BackendCapabilities {
            BackendCapabilities {
                source_kind: "artifact_store".to_owned(),
                transport: "test".to_owned(),
                supports_queries: true,
                supports_local_file_exports: false,
                requires_foreground_source: false,
                instructions: String::new(),
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
            _request: crate::AgentDataQueryRequest,
        ) -> Result<Value, BackendError> {
            Err(BackendError::new("test", "test"))
        }
    }

    #[tokio::test]
    async fn adapter_rejects_non_agent_queries_before_store_dispatch() {
        let backend = ArtifactStoreBackend::new(Arc::new(RejectingStore));
        let context = CallContext {
            caller: CallerIdentity::local_read_only(),
            cancellation: CancellationToken::new(),
            session_id: None,
            progress: None,
        };
        let error = backend
            .query_page(
                &context,
                QueryPageRequest {
                    query: json!({"schema": "healthmd.query_request"}),
                    detail_level: QueryDetailLevel::Summary,
                },
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, "healthmd_agent_query_invalid");
    }
}
