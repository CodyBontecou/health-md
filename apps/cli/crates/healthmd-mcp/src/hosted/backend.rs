use std::sync::Arc;

use async_trait::async_trait;
use serde_json::{Value, json};

use crate::backend::{
    BackendCapabilities, BackendError, CallContext, HealthDataBackend, QueryDetailLevel,
    QueryPageRequest,
};

use super::{HostedDataStore, HostedError};

/// Read-only MCP backend over an authenticated caller's synchronized hosted corpus.
pub struct HostedDataBackend {
    store: Arc<HostedDataStore>,
}

impl HostedDataBackend {
    pub fn new(store: Arc<HostedDataStore>) -> Self {
        Self { store }
    }

    pub fn store(&self) -> &Arc<HostedDataStore> {
        &self.store
    }

    fn require_summary(context: &CallContext) -> Result<(), BackendError> {
        if context.caller.subject.trim().is_empty() {
            return Err(BackendError::new(
                "healthmd_identity_invalid",
                "The authenticated caller identity is invalid.",
            ));
        }
        if context.caller.has_scope("health.summary.read")
            || context.caller.has_scope("healthmd:read")
        {
            Ok(())
        } else {
            Err(BackendError::new(
                "healthmd_scope_required",
                "The caller lacks hosted health summary read scope.",
            ))
        }
    }

    fn require_detail(context: &CallContext) -> Result<(), BackendError> {
        if context.caller.has_scope("health.detail.read") {
            Ok(())
        } else {
            Err(BackendError::new(
                "healthmd_detail_scope_required",
                "The caller lacks hosted health detail read scope.",
            ))
        }
    }
}

#[async_trait]
impl HealthDataBackend for HostedDataBackend {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            source_kind: "hosted_encrypted_snapshots".to_owned(),
            transport: "hosted_sync".to_owned(),
            supports_queries: true,
            supports_local_file_exports: false,
            requires_foreground_source: false,
            instructions:
                "Query only consented, encrypted snapshots synchronized to this hosted account."
                    .to_owned(),
        }
    }

    async fn readiness(&self, context: &CallContext) -> Result<Value, BackendError> {
        Self::require_summary(context)?;
        let status = self
            .store
            .status(&context.caller)
            .await
            .map_err(BackendError::from)?;
        serde_json::to_value(status).map_err(|_| {
            BackendError::new(
                "healthmd_encoding_failed",
                "Hosted readiness could not be encoded.",
            )
        })
    }

    async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
        Self::require_summary(context)?;
        let status = self
            .store
            .status(&context.caller)
            .await
            .map_err(BackendError::from)?;
        Ok(json!({
            "schema":"healthmd.hosted_doctor",
            "schema_version":1,
            "ready":status.ready,
            "storage":"encrypted",
            "source":"synchronized_snapshots",
            "dataset_revision":status.dataset_revision,
            "consent_revision":status.consent_revision,
            "consent_state":status.consent_state,
            "synchronized_day_count":status.synchronized_day_count,
            "first_owner_date":status.first_owner_date,
            "last_owner_date":status.last_owner_date
        }))
    }

    async fn query_page(
        &self,
        context: &CallContext,
        request: QueryPageRequest,
    ) -> Result<Value, BackendError> {
        Self::require_summary(context)?;
        if request.detail_level == QueryDetailLevel::Lossless {
            Self::require_detail(context)?;
        }
        self.store
            .evaluate_query(context, request)
            .await
            .map_err(BackendError::from)
    }
}

impl From<HostedError> for BackendError {
    fn from(error: HostedError) -> Self {
        BackendError {
            code: error.code.to_owned(),
            message: error.message.to_owned(),
            retryable: error.retryable,
            job_id: None,
        }
    }
}
