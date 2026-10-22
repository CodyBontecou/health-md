//! Fixed agent backend used by both portable MCP and CLI. This path never calls the
//! deployed status/wake/export/query/receiver preparers or creates installation state.
use async_trait::async_trait;
use healthmd_client::{
    ClientError,
    agent_host::{HostAuthorityStore, ProtectedHostKey},
    agent_planning::{HostPlanInput, HostPlanner, PlanningClock, SystemPlanningClock},
    credentials::CredentialStore,
    direct::DirectClient,
};
use healthmd_operations::{
    AgentPlanInput, BackendCapabilities, BackendError, CallContext, HealthDataBackend,
    QueryPageRequest,
};
use healthmd_protocol::v4::{Approval, ApprovalRequest, ExportPlan};
use serde_json::Value;
use std::{sync::Arc, time::Duration};
use tokio::sync::Mutex;
use uuid::Uuid;

pub struct DirectAgentBackend<C: CredentialStore> {
    client: Arc<DirectClient<C>>,
    key: Arc<dyn ProtectedHostKey>,
    device: Option<Uuid>,
    port: u16,
    timeout: Duration,
    gate: Arc<Mutex<()>>,
}
impl<C: CredentialStore> DirectAgentBackend<C> {
    pub fn new(
        client: Arc<DirectClient<C>>,
        key: Arc<dyn ProtectedHostKey>,
        device: Option<Uuid>,
        port: u16,
        timeout: Duration,
        gate: Arc<Mutex<()>>,
    ) -> Self {
        Self {
            client,
            key,
            device,
            port,
            timeout: timeout.min(Duration::from_secs(600)),
            gate,
        }
    }
    async fn planner(&self) -> Result<HostPlanner, BackendError> {
        let peer = self
            .client
            .planning_peer(self.device)
            .await
            .map_err(agent_backend_error)?;
        let store = HostAuthorityStore::open_existing(
            self.client.layout.root.join("agent-host-v1"),
            peer.host_installation_id,
            Arc::clone(&self.key),
        )
        .await
        .map_err(agent_backend_error)?;
        Ok(HostPlanner::new(store))
    }
}
#[async_trait]
impl<C: CredentialStore> HealthDataBackend for DirectAgentBackend<C> {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities { source_kind: "paired_mobile".into(), transport: "authenticated_encrypted_mobile_direct".into(),
            supports_queries: false, supports_local_file_exports: false, requires_foreground_source: true,
            instructions: "Planning requires independently stored native/host consent, protected issuer key, and a registered host destination. No execution adapter is provided.".into() }
    }
    async fn readiness(&self, _: &CallContext) -> Result<Value, BackendError> {
        Err(unsupported())
    }
    async fn doctor(&self, _: &CallContext) -> Result<Value, BackendError> {
        Err(unsupported())
    }
    async fn query_page(
        &self,
        _: &CallContext,
        _: QueryPageRequest,
    ) -> Result<Value, BackendError> {
        Err(unsupported())
    }

    async fn plan_export(
        &self,
        context: &CallContext,
        input: AgentPlanInput,
    ) -> Result<ExportPlan, BackendError> {
        let _gate = self.gate.lock().await;
        let planner = self.planner().await?;
        let peer = self
            .client
            .planning_peer(self.device)
            .await
            .map_err(agent_backend_error)?;
        let settings = input
            .settings()
            .map_err(|e| agent_backend_error(e.into()))?;
        let input = HostPlanInput {
            dates: input.dates,
            calendar_timezone: input.calendar_timezone,
            metric_ids: input.metric_ids,
            settings,
            destination_binding_id: input.destination_binding_id,
            native_authority_reference: input.native_authority_reference,
            host_authority_reference: input.host_authority_reference,
        };
        planner
            .preflight(&peer, &input, &SystemPlanningClock.now())
            .await
            .map_err(agent_backend_error)?;
        let mut source = self
            .client
            .connect_bridge(
                self.device,
                self.port,
                self.timeout,
                context.cancellation.clone(),
            )
            .await
            .map_err(agent_backend_error)?;
        planner
            .plan(&mut source, input, &SystemPlanningClock)
            .await
            .map_err(agent_backend_error)
    }

    async fn relay_export_approval(
        &self,
        context: &CallContext,
        request: ApprovalRequest,
    ) -> Result<Approval, BackendError> {
        let _gate = self.gate.lock().await;
        let planner = self.planner().await?;
        let peer = planner
            .preflight_approval(&request, &SystemPlanningClock.now())
            .await
            .map_err(agent_backend_error)?;
        if self
            .client
            .planning_peer(self.device)
            .await
            .map_err(agent_backend_error)?
            != peer
        {
            return Err(BackendError::new(
                "binding_changed",
                "The selected peer differs from the issued plan.",
            ));
        }
        let mut source = self
            .client
            .connect_bridge(
                self.device,
                self.port,
                self.timeout,
                context.cancellation.clone(),
            )
            .await
            .map_err(agent_backend_error)?;
        planner
            .relay_approval(&mut source, request, &SystemPlanningClock)
            .await
            .map_err(agent_backend_error)
    }
}
#[cfg(test)]
#[path = "agent_direct_tests.rs"]
mod tests;

fn unsupported() -> BackendError {
    BackendError::new(
        "unsupported_capability",
        "This backend provides only configuration planning and stored-decision relay.",
    )
}

pub fn agent_backend_error(error: ClientError) -> BackendError {
    let code = match error {
        ClientError::Agent(error) => error.to_string(),
        ClientError::AgentRejected(code) => serde_json::to_value(code)
            .ok()
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_else(|| "invalid_request".into()),
        ClientError::AgentStoreBusy => "revision_conflict".into(),
        ClientError::AgentStoreFull => "query_budget_exceeded".into(),
        ClientError::AgentAuthorityUnavailable | ClientError::CredentialStore(_) => {
            "permission_required".into()
        }
        ClientError::WaitCancelled => "healthmd_request_cancelled".into(),
        ClientError::TimedOut | ClientError::Connection(_) => "direct_source_unavailable".into(),
        _ => "binding_changed".into(),
    };
    BackendError::new(
        code,
        "The configuration-only agent operation is unavailable, invalid, or unauthorized.",
    )
}
