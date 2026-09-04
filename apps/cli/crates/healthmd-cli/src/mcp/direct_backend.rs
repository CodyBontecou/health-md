use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
use chrono::{Local, Utc};
use healthmd_client::{
    ClientError,
    direct::{
        DEFAULT_WAKE_TIMEOUT_SECONDS, DirectClient, MAXIMUM_WAKE_TIMEOUT_SECONDS, SourceStatus,
        StatusResult, WakeWindow,
    },
    file_receiver::FileReceiptPayload,
    job::{JobRecord, JobState},
};
use healthmd_operations::{
    BackendCapabilities, BackendError, CallContext, CallerIdentity, CallerMode, HealthDataBackend,
    PairingStartResult, ProgressUpdate, QueryDetailLevel, QueryPageRequest,
    generated_file_export_from_value, job_id as parse_job_id,
};
use healthmd_protocol::{
    encoding::SwiftUuid,
    models::ResponseMode,
    wire::{DirectQueryDetailLevel, DirectQueryRequest},
};
use serde_json::{Value, json};
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::pairing::{PairingCoordinator, PairingCoordinatorError};

use super::{ServeError, ServeOptions};

pub struct DirectIphoneBackend {
    client: Arc<DirectClient>,
    configuration: DirectBackendConfiguration,
    operation_gate: Arc<Mutex<()>>,
    pairing: PairingCoordinator,
}

#[derive(Clone, Copy, Debug)]
struct DirectBackendConfiguration {
    device_id: Option<Uuid>,
    port: u16,
    timeout: Duration,
    wake_window: WakeWindow,
    wake_requests: bool,
}

impl DirectIphoneBackend {
    pub fn open(options: &ServeOptions) -> Result<Self, ServeError> {
        let wake_window = configured_wake_window(options)?;
        let wake_requests = std::env::var("HEALTHMD_NO_WAKE").ok().as_deref() != Some("1");
        let client = Arc::new(DirectClient::open().map_err(|_| ServeError)?);
        let operation_gate = Arc::new(Mutex::new(()));
        let pairing = PairingCoordinator::new(
            Arc::clone(&client),
            options.device_id,
            options.port,
            Arc::clone(&operation_gate),
        );
        Ok(Self {
            client,
            configuration: DirectBackendConfiguration {
                device_id: options.device_id,
                port: options.port,
                timeout: Duration::from_secs(options.timeout_seconds),
                wake_window,
                wake_requests,
            },
            operation_gate,
            pairing,
        })
    }

    async fn wait_for_active_source(&self, context: &CallContext) -> Result<(), BackendError> {
        self.wait_for_active_source_on(context, self.configuration.device_id)
            .await
    }

    async fn wait_for_active_source_on(
        &self,
        context: &CallContext,
        device_id: Option<Uuid>,
    ) -> Result<(), BackendError> {
        let wake_window = self.configuration.wake_window;
        let wake_request = self.configuration.wake_requests;
        self.client
            .wait_for_active_source(
                device_id,
                self.configuration.port,
                wake_window,
                wake_request,
                &context.cancellation,
                |progress: healthmd_client::direct::WakeProgress| {
                    context.report_progress(ProgressUpdate {
                        progress: progress.elapsed_seconds,
                        total: Some(progress.timeout_seconds),
                        message: progress.message.to_owned(),
                    });
                },
            )
            .await
            .map_err(|error| wake_backend_error(&error, wake_window))
    }

    fn validate_pinned_device(&self, pinned: Uuid) -> Result<(), BackendError> {
        if let Some(requested) = self.configuration.device_id {
            if requested != pinned {
                return Err(backend_error(
                    &ClientError::DeviceNotPaired(requested),
                    None,
                ));
            }
        }
        Ok(())
    }

    /// The shared wake-window object with enrollment reported truthfully for the configured
    /// device selection. Derives from the same client implementation the CLI reports.
    async fn wake_status_value(&self) -> Value {
        self.client
            .wake_status_value(self.configuration.device_id, self.configuration.wake_window)
            .await
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
            instructions: "For an unpaired iPhone, call healthmd_pairing_start. Its negotiated MCP App renders the native image/png QR inline; if the host does not support MCP Apps, render the returned image directly. Tell the user to scan it from Health.md's Sync > Direct CLI Access > Scan Pairing QR screen, and poll healthmd_pairing_status; never run healthmd setup codex, healthmd direct pair, or reconstruct terminal QR glyphs from an MCP client. External custom-URL opens are not pairing consent. Keep Health.md foreground on the paired iPhone. Use fixed typed tools directly: healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Queries use only the authenticated direct iPhone channel; no Health.md Mac app is required.".to_owned(),
        }
    }

    async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let _gate = self.operation_gate.lock().await;
        let wake = self.wake_status_value().await;
        self.client
            .status(
                self.configuration.device_id,
                self.configuration.port,
                self.configuration.timeout,
            )
            .await
            .map(|result| status_value(&result, &wake))
            .map_err(|error| backend_error(&error, None))
    }

    async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
        let devices = self
            .client
            .paired_devices()
            .await
            .map_err(|error| backend_error(&error, None))?;
        if devices.is_empty() {
            let (message, next_tool) =
                unpaired_guidance(self.configuration.device_id.is_some(), &context.caller);
            return Ok(json!({
                "schema": "healthmd.direct_readiness",
                "schema_version": 1,
                "status": "not_paired",
                "ready": false,
                "message": message,
                "next_tool": next_tool,
                "wake": self.wake_status_value().await
            }));
        }
        self.readiness(context).await
    }

    async fn start_pairing(
        &self,
        _context: &CallContext,
        timeout_seconds: u64,
    ) -> Result<PairingStartResult, BackendError> {
        self.pairing
            .start(timeout_seconds)
            .await
            .map_err(pairing_backend_error)
    }

    async fn pairing_status(
        &self,
        _context: &CallContext,
        pairing_session_id: Uuid,
    ) -> Result<Value, BackendError> {
        self.pairing
            .status(pairing_session_id)
            .await
            .map_err(pairing_backend_error)
    }

    async fn query_page(
        &self,
        context: &CallContext,
        request: QueryPageRequest,
    ) -> Result<Value, BackendError> {
        let _gate = self.operation_gate.lock().await;
        self.wait_for_active_source(context).await?;
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
        context: &CallContext,
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
        self.wait_for_active_source(context).await?;
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
        context: &CallContext,
        job_id: Uuid,
        arguments: &Value,
    ) -> Result<Value, BackendError> {
        let (_, timeout) = parse_job_id(arguments, true).map_err(|_| {
            BackendError::new("healthmd_invalid_export", "Invalid export arguments.")
        })?;
        let record = self
            .client
            .job_record(job_id)
            .map_err(|error| backend_error(&error, Some(job_id)))?;
        if record.request.response_mode != ResponseMode::WriteFiles {
            return Err(BackendError::new(
                "healthmd_job_terminal",
                "This durable job is not a generated-file export.",
            )
            .with_job_id(job_id));
        }
        let _gate = self.operation_gate.lock().await;
        if record.state.resume_requires_source() {
            // An unbound job (crash window before its first connection) keeps the configured
            // device selection; a bound job pins the wake preflight to its exact source.
            let wake_device = match record
                .peer_binding
                .as_ref()
                .map(|binding| binding.source_installation_id.0)
            {
                Some(pinned) => {
                    self.validate_pinned_device(pinned)?;
                    Some(pinned)
                }
                None => self.configuration.device_id,
            };
            self.wait_for_active_source_on(context, wake_device).await?;
        }
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
        context: &CallContext,
        job_id: Uuid,
    ) -> Result<Value, BackendError> {
        // Cancellation intentionally bypasses the operation gate. Persist the explicit marker
        // before opening a second listener so an active export that owns the port can deliver it.
        let record = self
            .client
            .job_record(job_id)
            .map_err(|error| backend_error(&error, Some(job_id)))?;
        let delivery_device = if record.state.is_terminal() {
            self.configuration.device_id
        } else {
            let pinned = record
                .peer_binding
                .as_ref()
                .map(|binding| binding.source_installation_id.0)
                .ok_or_else(|| {
                    backend_error(
                        &ClientError::JobNotResumable(job_id, "unbound".into()),
                        Some(job_id),
                    )
                })?;
            self.validate_pinned_device(pinned)?;
            self.client
                .request_job_cancellation(job_id, Some(pinned))
                .map_err(|error| backend_error(&error, Some(job_id)))?;
            if let Err(error) = self.wait_for_active_source_on(context, Some(pinned)).await {
                // The durable marker is already persisted, so local wait expiry or interruption
                // reports the truthful pending state, never terminal phone-side cancellation.
                if matches!(
                    error.code.as_str(),
                    "direct_source_unavailable" | "healthmd_request_cancelled"
                ) {
                    return Err(backend_error(
                        &ClientError::CancellationPending(job_id),
                        Some(job_id),
                    ));
                }
                return Err(error.with_job_id(job_id));
            }
            Some(pinned)
        };
        self.client
            .cancel_job(
                job_id,
                delivery_device,
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

fn configured_wake_window(options: &ServeOptions) -> Result<WakeWindow, ServeError> {
    let timeout_seconds = if let Some(value) = options.wake_timeout_seconds {
        value
    } else {
        match std::env::var("HEALTHMD_WAKE_TIMEOUT") {
            Ok(value) => value.parse::<u64>().map_err(|_| ServeError)?,
            Err(std::env::VarError::NotPresent) => DEFAULT_WAKE_TIMEOUT_SECONDS,
            Err(std::env::VarError::NotUnicode(_)) => return Err(ServeError),
        }
    };
    if timeout_seconds > MAXIMUM_WAKE_TIMEOUT_SECONDS {
        return Err(ServeError);
    }
    Ok(WakeWindow::from_seconds(timeout_seconds))
}

fn wake_backend_error(error: &ClientError, wake_window: WakeWindow) -> BackendError {
    match error {
        ClientError::TimedOut => BackendError::new(
            "direct_source_unavailable",
            "The direct mobile source is unavailable.",
        )
        .retryable(true)
        .with_wake_window_seconds(wake_window.timeout_seconds()),
        ClientError::WaitCancelled => BackendError::new(
            "healthmd_request_cancelled",
            "The local direct mobile wait was cancelled.",
        ),
        other => backend_error(other, None),
    }
}

fn status_value(result: &StatusResult, wake: &Value) -> Value {
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
                "query_capabilities": query,
                "wake": wake.clone()
            })
        }
        SourceStatus::Android(_) => json!({
            "schema": "healthmd.direct_readiness",
            "schema_version": 1,
            "status": "query_unsupported",
            "ready": false,
            "message": "This paired source does not support the direct iPhone query protocol.",
            "application_protocol_version": result.application_protocol_version,
            "port": result.port,
            "wake": wake.clone()
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

fn unpaired_guidance(
    device_is_pinned: bool,
    caller: &CallerIdentity,
) -> (&'static str, Option<&'static str>) {
    if device_is_pinned {
        return (
            "This MCP server is pinned to an unpaired device. Remove the stale device selection before onboarding.",
            None,
        );
    }
    if caller.mode == CallerMode::LocalStdio && caller.has_scope("healthmd:pair") {
        return (
            "Call healthmd_pairing_start, show its QR image, then scan it from Sync > Direct CLI Access > Scan Pairing QR in foreground Health.md.",
            Some("healthmd_pairing_start"),
        );
    }
    (
        "Run `healthmd direct pair` locally, then scan its QR from Sync > Direct CLI Access > Scan Pairing QR in foreground Health.md.",
        None,
    )
}

fn pairing_backend_error(error: PairingCoordinatorError) -> BackendError {
    BackendError::new(error.code(), error.message())
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

#[cfg(test)]
mod tests {
    use super::*;
    use healthmd_client::direct::WakeEnrollment;

    #[test]
    fn explicit_mcp_wake_override_is_bounded_and_can_disable_waiting() {
        let options = ServeOptions {
            device_id: None,
            port: 17_647,
            timeout_seconds: 1_200,
            wake_timeout_seconds: Some(0),
        };
        let disabled = configured_wake_window(&options).unwrap();
        assert!(!disabled.enabled());
        // Enrollment is the per-device credential truth, reported independently of the window:
        // a stored wake credential is enrolled even while the wait itself is disabled.
        let wait_only = disabled.status_value(WakeEnrollment::WaitOnly);
        assert_eq!(wait_only["enabled"], false);
        assert_eq!(wait_only["enrollment"]["state"], "unavailable");
        assert_eq!(wait_only["enrollment"]["mode"], "wait_only");
        let enrolled = disabled.status_value(WakeEnrollment::Enrolled);
        assert_eq!(enrolled["enabled"], false);
        assert_eq!(enrolled["enrollment"]["state"], "available");
        assert_eq!(enrolled["enrollment"]["mode"], "enrolled");

        let invalid = ServeOptions {
            wake_timeout_seconds: Some(MAXIMUM_WAKE_TIMEOUT_SECONDS + 1),
            ..options
        };
        assert!(configured_wake_window(&invalid).is_err());
    }

    #[test]
    fn wake_expiry_and_local_cancellation_remain_distinct() {
        let expired = wake_backend_error(&ClientError::TimedOut, WakeWindow::from_seconds(37));
        assert_eq!(expired.code, "direct_source_unavailable");
        assert!(expired.retryable);
        assert_eq!(expired.wake_window_seconds, Some(37));

        let cancelled =
            wake_backend_error(&ClientError::WaitCancelled, WakeWindow::from_seconds(37));
        assert_eq!(cancelled.code, "healthmd_request_cancelled");
        assert!(!cancelled.retryable);
        assert_eq!(cancelled.wake_window_seconds, None);
    }

    #[test]
    fn read_only_stdio_guidance_never_advertises_hidden_pairing_tools() {
        let (message, next_tool) = unpaired_guidance(false, &CallerIdentity::local_read_only());
        assert!(message.contains("healthmd direct pair"));
        assert!(!message.contains("healthmd_pairing_start"));
        assert_eq!(next_tool, None);

        let (message, next_tool) = unpaired_guidance(false, &CallerIdentity::local());
        assert!(message.contains("healthmd_pairing_start"));
        assert_eq!(next_tool, Some("healthmd_pairing_start"));
    }
}
