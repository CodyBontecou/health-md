use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
use chrono::{Local, Utc};
use healthmd_client::{
    ClientError,
    direct::{DirectClient, SourceStatus, StatusResult},
    file_receiver::FileReceiptPayload,
    job::{JobRecord, JobState},
};
use healthmd_operations::{
    BackendCapabilities, BackendError, CallContext, HealthDataBackend, QueryDetailLevel,
    QueryPageRequest, generated_file_export_from_value, job_id as parse_job_id,
};
use healthmd_protocol::{
    encoding::SwiftUuid,
    models::ResponseMode,
    wire::{DirectQueryDetailLevel, DirectQueryRequest},
};
use serde_json::{Value, json};
use tokio::sync::Mutex;
use uuid::Uuid;

use super::{ServeError, ServeOptions};

pub struct DirectIphoneBackend {
    client: Arc<DirectClient>,
    configuration: DirectBackendConfiguration,
    operation_gate: Mutex<()>,
}

#[derive(Clone, Copy, Debug)]
struct DirectBackendConfiguration {
    device_id: Option<Uuid>,
    port: u16,
    timeout: Duration,
}

impl DirectIphoneBackend {
    pub fn open(options: &ServeOptions) -> Result<Self, ServeError> {
        let client = DirectClient::open().map_err(|_| ServeError)?;
        Ok(Self {
            client: Arc::new(client),
            configuration: DirectBackendConfiguration {
                device_id: options.device_id,
                port: options.port,
                timeout: Duration::from_secs(options.timeout_seconds),
            },
            operation_gate: Mutex::new(()),
        })
    }
}

#[async_trait]
impl HealthDataBackend for DirectIphoneBackend {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            source_kind: "paired_iphone".to_owned(),
            transport: "authenticated_encrypted_iphone_direct".to_owned(),
            supports_queries: true,
            supports_local_file_exports: true,
            requires_foreground_source: true,
            instructions: "Keep Health.md foreground on the paired iPhone. Use fixed typed tools directly: healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Queries use only the authenticated direct iPhone channel; no Health.md Mac app is required.".to_owned(),
        }
    }

    async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let _gate = self.operation_gate.lock().await;
        self.client
            .status(
                self.configuration.device_id,
                self.configuration.port,
                self.configuration.timeout,
            )
            .await
            .map(|result| status_value(&result))
            .map_err(|error| backend_error(&error, None))
    }

    async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
        let devices = self
            .client
            .paired_devices()
            .await
            .map_err(|error| backend_error(&error, None))?;
        if devices.is_empty() {
            return Ok(json!({
                "schema": "healthmd.direct_readiness",
                "schema_version": 1,
                "status": "not_paired",
                "ready": false,
                "message": "Run `healthmd direct pair`, then approve pairing in the foreground Health.md iPhone app."
            }));
        }
        self.readiness(context).await
    }

    async fn query_page(
        &self,
        _context: &CallContext,
        request: QueryPageRequest,
    ) -> Result<Value, BackendError> {
        let _gate = self.operation_gate.lock().await;
        let detail_level = match request.detail_level {
            QueryDetailLevel::Summary => DirectQueryDetailLevel::Summary,
            QueryDetailLevel::Lossless => DirectQueryDetailLevel::Lossless,
        };
        self.client
            .query(
                DirectQueryRequest {
                    protocol_version: healthmd_protocol::IOS_QUERY_APPLICATION_PROTOCOL_VERSION,
                    request_id: SwiftUuid(Uuid::new_v4()),
                    created_at: Utc::now(),
                    detail_level,
                    query: request.query,
                },
                self.configuration.device_id,
                self.configuration.port,
                self.configuration.timeout,
            )
            .await
            .map(|result| result.response)
            .map_err(|error| backend_error(&error, None))
    }

    async fn start_export(
        &self,
        _context: &CallContext,
        job_id: Uuid,
        arguments: &Value,
    ) -> Result<Value, BackendError> {
        let invocation = generated_file_export_from_value(
            arguments,
            job_id,
            Utc::now(),
            Local::now().date_naive(),
        )
        .map_err(|_| BackendError::new("healthmd_invalid_export", "Invalid export arguments."))?;
        let _gate = self.operation_gate.lock().await;
        self.client
            .export_files(
                invocation.request,
                self.configuration.device_id,
                self.configuration.port,
                invocation.timeout,
            )
            .await
            .map(|result| export_success(&result.receipt.payload))
            .map_err(|error| backend_error(&error, Some(job_id)))
    }

    async fn export_status(
        &self,
        _context: &CallContext,
        job_id: Uuid,
    ) -> Result<Value, BackendError> {
        self.client
            .job_record(job_id)
            .map(|record| job_receipt(&record))
            .map_err(|error| backend_error(&error, Some(job_id)))
    }

    async fn resume_export(
        &self,
        _context: &CallContext,
        job_id: Uuid,
        arguments: &Value,
    ) -> Result<Value, BackendError> {
        let (_, timeout) = parse_job_id(arguments, true).map_err(|_| {
            BackendError::new("healthmd_invalid_export", "Invalid export arguments.")
        })?;
        if self
            .client
            .job_record(job_id)
            .is_ok_and(|record| record.request.response_mode != ResponseMode::WriteFiles)
        {
            return Err(BackendError::new(
                "healthmd_job_terminal",
                "This durable job is not a generated-file export.",
            )
            .with_job_id(job_id));
        }
        let _gate = self.operation_gate.lock().await;
        self.client
            .resume_files(
                job_id,
                self.configuration.device_id,
                self.configuration.port,
                timeout,
            )
            .await
            .map(|result| export_success(&result.receipt.payload))
            .map_err(|error| backend_error(&error, Some(job_id)))
    }

    async fn cancel_export(
        &self,
        _context: &CallContext,
        job_id: Uuid,
    ) -> Result<Value, BackendError> {
        // Cancellation intentionally bypasses the operation gate. The direct client durably stores
        // the marker before delivering it on the authenticated channel.
        self.client
            .cancel_job(
                job_id,
                self.configuration.device_id,
                self.configuration.port,
                self.configuration.timeout,
            )
            .await
            .map(|()| {
                json!({
                    "job_id": job_id,
                    "status": "cancelled",
                    "message": "The durable direct iPhone export was cancelled."
                })
            })
            .map_err(|error| backend_error(&error, Some(job_id)))
    }
}

fn status_value(result: &StatusResult) -> Value {
    let query = result.peer_capabilities.query.as_ref();
    match &result.status {
        SourceStatus::Ios(source) => {
            let ready = source.app_active
                && source.protected_data_available
                && source.can_trigger_queries.unwrap_or(false);
            json!({
                "schema": "healthmd.direct_readiness",
                "schema_version": 1,
                "status": if ready { "ready" } else { "unavailable" },
                "ready": ready,
                "message": if ready {
                    "The authenticated direct iPhone query service is ready."
                } else {
                    "The iPhone direct service is not ready. Keep Health.md foreground with Direct CLI Access enabled."
                },
                "device_name": source.name,
                "application_protocol_version": result.application_protocol_version,
                "port": result.port,
                "app_active": source.app_active,
                "protected_data_available": source.protected_data_available,
                "export_in_progress": source.export_in_progress,
                "query_in_progress": source.query_in_progress,
                "can_trigger_file_exports": source.can_trigger_file_exports,
                "can_trigger_queries": source.can_trigger_queries,
                "active_job_id": source.active_job_id,
                "active_query_request_id": source.active_query_request_id,
                "query_capabilities": query
            })
        }
        SourceStatus::Android(_) => json!({
            "schema": "healthmd.direct_readiness",
            "schema_version": 1,
            "status": "query_unsupported",
            "ready": false,
            "message": "This paired source does not support the direct iPhone query protocol.",
            "application_protocol_version": result.application_protocol_version,
            "port": result.port
        }),
    }
}

fn export_success(payload: &FileReceiptPayload) -> Value {
    const MAXIMUM_RECEIPT_PATHS: usize = 256;
    let paths: Vec<&String> = payload
        .relative_paths
        .iter()
        .take(MAXIMUM_RECEIPT_PATHS)
        .collect();
    let failed_dates: Vec<&String> = payload
        .failed_date_identifiers
        .iter()
        .take(MAXIMUM_RECEIPT_PATHS)
        .collect();
    json!({
        "job_id": payload.job_id,
        "status": payload.status,
        "message": "Health.md generated and verified the requested files from the iPhone.",
        "destination_path": payload.destination_path,
        "files_written": payload.files_written,
        "total_bytes": payload.total_bytes,
        "relative_paths": paths,
        "relative_path_count": payload.relative_paths.len(),
        "relative_paths_truncated": payload.relative_paths.len() > MAXIMUM_RECEIPT_PATHS,
        "success_count": payload.success_count,
        "total_count": payload.total_count,
        "failed_date_identifiers": failed_dates,
        "failed_date_identifier_count": payload.failed_date_identifiers.len(),
        "failed_date_identifiers_truncated": payload.failed_date_identifiers.len() > MAXIMUM_RECEIPT_PATHS
    })
}

fn job_receipt(record: &JobRecord) -> Value {
    let status = match record.state {
        JobState::Queued
        | JobState::Connecting
        | JobState::Sent
        | JobState::Accepted
        | JobState::Preparing
        | JobState::Transferring
        | JobState::AwaitingPeerAcknowledgement => "preparing",
        JobState::Paused => "timed_out",
        JobState::CancellationPending => "accepted",
        JobState::Completed => "success",
        JobState::Failed => "failure",
        JobState::Cancelled => "cancelled",
    };
    let message = match record.state {
        JobState::Paused => "The direct transfer paused and can be resumed.",
        JobState::Completed => "The durable direct iPhone export completed.",
        JobState::Failed => "The durable direct iPhone export failed.",
        JobState::Cancelled => "The durable direct iPhone export was cancelled.",
        _ => "The durable direct iPhone export has not reached a terminal state.",
    };
    let mut value = json!({
        "job_id": record.request.job_id,
        "status": status,
        "message": message,
        "state": record.state,
        "created_at": record.created_at,
        "updated_at": record.updated_at,
        "expires_at": record.expires_at,
        "processed_days": record.processed_days,
        "total_days": record.total_days,
        "committed_partitions": record.committed_partitions,
        "committed_bytes": record.committed_bytes
    });
    if let Some(destination) = &record.request.destination {
        value["destination_path"] = Value::String(destination.root_path.clone());
    }
    value
}

fn backend_error(error: &ClientError, job_id: Option<Uuid>) -> BackendError {
    let (code, message, retryable) = match error {
        ClientError::DeviceSelectionRequired(devices) if devices.is_empty() => (
            "healthmd_not_paired",
            "No iPhone is paired. Run `healthmd direct pair`.",
            false,
        ),
        ClientError::DeviceSelectionRequired(_) => (
            "healthmd_device_ambiguous",
            "More than one iPhone is paired. Configure a device ID.",
            false,
        ),
        ClientError::DeviceNotPaired(_) => (
            "healthmd_not_paired",
            "The requested iPhone is not paired. Pair it again or select a trusted device.",
            false,
        ),
        ClientError::QueryUnsupported => (
            "healthmd_query_unsupported",
            "The paired iPhone does not advertise direct query support.",
            false,
        ),
        ClientError::QueryRejected { retryable, .. } => (
            "healthmd_query_rejected",
            "The iPhone rejected the bounded query. Check dates, metrics, and readiness.",
            *retryable,
        ),
        ClientError::ExportPaused(_) => (
            "healthmd_export_paused",
            "The durable export paused and may be resumed.",
            true,
        ),
        ClientError::CancellationPending(_) => (
            "healthmd_cancellation_pending",
            "Cancellation is durably pending delivery to the paired iPhone.",
            true,
        ),
        ClientError::JobNotFound => (
            "healthmd_job_not_found",
            "The durable job was not found.",
            false,
        ),
        ClientError::JobExpired => ("healthmd_job_expired", "The durable job expired.", false),
        ClientError::JobNotResumable(_, _) => (
            "healthmd_job_terminal",
            "The durable job cannot be resumed from its current state.",
            false,
        ),
        ClientError::TimedOut => (
            "healthmd_timeout",
            "The direct iPhone operation timed out.",
            true,
        ),
        ClientError::CredentialMutationOutcomeUnknown => (
            "healthmd_credential_outcome_unknown",
            "The native credential mutation may have completed. Inspect pairing state before retrying.",
            false,
        ),
        ClientError::FrameTooLarge => (
            "healthmd_response_too_large",
            "The direct response exceeded a bounded MCP or protocol limit.",
            false,
        ),
        ClientError::MalformedPacket
        | ClientError::UnexpectedMessage
        | ClientError::ReplayedPacket => (
            "healthmd_protocol_error",
            "The authenticated peer returned an invalid protocol response.",
            false,
        ),
        ClientError::InvalidTransfer(_) | ClientError::InvalidJob => (
            "healthmd_integrity_error",
            "The durable transfer failed protocol or artifact integrity validation.",
            false,
        ),
        ClientError::Authentication(_) | ClientError::InvalidTrustState => (
            "healthmd_pairing_required",
            "The authenticated direct channel failed. Pair again if this persists.",
            false,
        ),
        _ => (
            "healthmd_unavailable",
            "The direct iPhone service is unavailable. Keep Health.md foreground and verify Direct CLI Access.",
            true,
        ),
    };
    let mut mapped = BackendError::new(code, message).retryable(retryable);
    if let Some(job_id) = job_id {
        mapped = mapped.with_job_id(job_id);
    }
    mapped
}
