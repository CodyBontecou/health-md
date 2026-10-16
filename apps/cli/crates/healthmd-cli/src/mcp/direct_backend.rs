use std::{
    fs::File,
    io::{Read as _, Seek as _, SeekFrom},
    sync::Arc,
    time::Duration,
};

use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use chrono::{Duration as ChronoDuration, Local, Utc};
use healthmd_client::{
    ClientError,
    direct::{
        DEFAULT_WAKE_TIMEOUT_SECONDS, DirectClient, MAXIMUM_WAKE_TIMEOUT_SECONDS,
        RawArtifactPlatform, SourceKind, SourceStatus, StatusResult, WakeWindow,
    },
    file_receiver::FileReceiptPayload,
    job::{JobRecord, JobState},
    v2_job::V2JobRecord,
    v2_receiver::V2ArtifactReceipt,
};
use healthmd_operations::{
    BackendCapabilities, BackendError, CallContext, CallerIdentity, CallerMode, HealthDataBackend,
    PairingStartResult, ProgressUpdate, QueryDetailLevel, QueryPageRequest, RawCorpusExportInput,
    RawCorpusFormat, generated_file_export_from_value, job_id as parse_job_id,
    raw_artifact_read_from_value, raw_corpus_export_from_value,
};
use healthmd_protocol::{
    JOB_LIFETIME_SECONDS,
    encoding::SwiftUuid,
    models::{CanonicalSelection, DetailLevel, ExportRequest, ResponseMode, SettingsPolicy},
    v2,
    wire::{DirectQueryDetailLevel, DirectQueryRequest, RawProfile},
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

    async fn start_ios_raw_export(
        &self,
        job_id: Uuid,
        input: RawCorpusExportInput,
    ) -> Result<Value, BackendError> {
        if input.format == RawCorpusFormat::Ndjson
            || input
                .provider_id
                .as_deref()
                .is_some_and(|provider| provider != "apple_health")
        {
            return Err(BackendError::new(
                "healthmd_invalid_export",
                "iPhone full-corpus export uses Apple Health JSON.",
            )
            .with_job_id(job_id));
        }
        let request = ExportRequest {
            protocol_version: 1,
            job_id: SwiftUuid(job_id),
            created_at: Utc::now(),
            date_selection: input
                .dates
                .resolve(Local::now().date_naive())
                .map_err(|_| {
                    BackendError::new("healthmd_invalid_export", "Invalid raw export dates.")
                })?,
            settings_policy: SettingsPolicy::RequestedDatesOnly,
            profile_reference: None,
            response_mode: ResponseMode::RawJson,
            raw_profile: Some(RawProfile::HealthDataProjection),
            canonical_selection: Some(CanonicalSelection {
                metric_ids: Vec::new(),
                categories: Vec::new(),
                source_ids: vec!["apple_health".to_owned()],
                object_paths: vec!["/healthkit_record_archive".to_owned()],
                field_pointers: Vec::new(),
                all_metrics: true,
                detail_level: DetailLevel::Lossless,
            }),
            destination: None,
        };
        let result = self
            .client
            .export_raw(
                request,
                self.configuration.device_id,
                self.configuration.port,
                input.timeout,
            )
            .await
            .map_err(|error| backend_error(&error, Some(job_id)))?;
        Ok(raw_export_success(
            job_id,
            "ios",
            "apple_health",
            "json",
            &result.artifact.status,
            u64::try_from(result.artifact.byte_count).map_err(|_| {
                BackendError::new("healthmd_integrity_error", "Invalid raw artifact size.")
            })?,
            &result.artifact.sha256,
        ))
    }

    async fn start_android_raw_export(
        &self,
        job_id: Uuid,
        input: RawCorpusExportInput,
        installation_id: Uuid,
    ) -> Result<Value, BackendError> {
        let provider_id = input
            .provider_id
            .unwrap_or_else(|| "health_connect".to_owned());
        let date_selection = match input
            .dates
            .resolve(Local::now().date_naive())
            .map_err(|_| {
                BackendError::new("healthmd_invalid_export", "Invalid raw export dates.")
            })? {
            healthmd_protocol::models::DateSelection::Exact(range) => v2::DateSelection::Exact {
                start_date: range.start,
                end_date: range.end,
            },
            healthmd_protocol::models::DateSelection::AllAvailable(_) => {
                v2::DateSelection::AllAvailable
            }
        };
        let created_at = Utc::now();
        let request = v2::ExportRequest {
            job_id,
            created_at,
            expires_at: created_at + ChronoDuration::seconds(JOB_LIFETIME_SECONDS),
            source_installation_id: installation_id,
            date_selection,
            product: v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
                provider_id: provider_id.clone(),
                format: match input.format {
                    RawCorpusFormat::Json => v2::RawSnapshotFormat::Json,
                    RawCorpusFormat::Auto | RawCorpusFormat::Ndjson => {
                        v2::RawSnapshotFormat::Ndjson
                    }
                },
                scope: v2::RawSnapshotScope::AllAuthorizedSupportedData,
                include_exercise_routes: input.include_exercise_routes,
            },
            destination: None,
        };
        let result = self
            .client
            .export_android(
                request,
                None,
                Some(installation_id),
                self.configuration.port,
                input.timeout,
            )
            .await
            .map_err(|error| backend_error(&error, Some(job_id)))?;
        Ok(raw_export_success(
            job_id,
            "android",
            &provider_id,
            match input.format {
                RawCorpusFormat::Json => "json",
                RawCorpusFormat::Auto | RawCorpusFormat::Ndjson => "ndjson",
            },
            &result.receipt.status,
            result.receipt.byte_count,
            &result.receipt.sha256,
        ))
    }
}

#[async_trait]
impl HealthDataBackend for DirectIphoneBackend {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            source_kind: "paired_mobile".to_owned(),
            transport: "authenticated_encrypted_mobile_direct".to_owned(),
            supports_queries: true,
            supports_local_file_exports: true,
            requires_foreground_source: true,
            instructions: "For an unpaired iPhone, call healthmd_pairing_start. Its negotiated MCP App renders the native image/png QR inline; if the host does not support MCP Apps, render the returned image directly. Tell the user to scan it from Health.md's Direct CLI Access screen, and poll healthmd_pairing_status; never run healthmd setup codex, healthmd direct pair, or reconstruct terminal QR glyphs from an MCP client. External custom-URL opens are not pairing consent. Android pairing remains an explicit out-of-MCP `healthmd direct pair` workflow. Keep Health.md foreground on the paired phone. On iPhone, use fixed typed tools directly: healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. On iPhone or Android, healthmd_export_raw captures the complete supported public and user-authorized corpus into a private job-bound artifact; traverse it only with healthmd_raw_artifact_read. No Health.md Mac app or health-data cloud is required.".to_owned(),
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

    async fn start_raw_export(
        &self,
        context: &CallContext,
        job_id: Uuid,
        arguments: &Value,
    ) -> Result<Value, BackendError> {
        let input =
            raw_corpus_export_from_value(arguments, Local::now().date_naive()).map_err(|_| {
                BackendError::new("healthmd_invalid_export", "Invalid raw export arguments.")
            })?;
        let source_kind = self
            .client
            .selected_source_kind(self.configuration.device_id)
            .await
            .map_err(|error| backend_error(&error, Some(job_id)))?;
        let selected = self
            .client
            .selected_source(self.configuration.device_id)
            .await
            .map_err(|error| backend_error(&error, Some(job_id)))?;
        let _gate = self.operation_gate.lock().await;
        self.wait_for_active_source(context).await?;
        match source_kind {
            SourceKind::Ios => self.start_ios_raw_export(job_id, input).await,
            SourceKind::Android => {
                self.start_android_raw_export(job_id, input, selected.installation_id.0)
                    .await
            }
        }
    }

    async fn read_raw_artifact(
        &self,
        _context: &CallContext,
        arguments: &Value,
    ) -> Result<Value, BackendError> {
        let input = raw_artifact_read_from_value(arguments).map_err(|_| {
            BackendError::new(
                "healthmd_invalid_export",
                "Invalid raw artifact read arguments.",
            )
        })?;
        let artifact = self
            .client
            .raw_artifact(input.job_id)
            .map_err(|error| backend_error(&error, Some(input.job_id)))?;
        if input.offset > artifact.byte_count {
            return Err(BackendError::new(
                "healthmd_invalid_export",
                "The raw artifact offset is outside the validated artifact.",
            )
            .with_job_id(input.job_id));
        }
        let remaining = artifact.byte_count - input.offset;
        let requested = remaining.min(u64::try_from(input.maximum_bytes).unwrap_or(u64::MAX));
        let requested = usize::try_from(requested).map_err(|_| {
            BackendError::new("healthmd_integrity_error", "Invalid raw artifact bounds.")
                .with_job_id(input.job_id)
        })?;
        let mut file = File::open(&artifact.path).map_err(|_| {
            BackendError::new("healthmd_unavailable", "The raw artifact is unavailable.")
        })?;
        file.seek(SeekFrom::Start(input.offset)).map_err(|_| {
            BackendError::new("healthmd_unavailable", "The raw artifact is unavailable.")
        })?;
        let mut bytes = vec![0_u8; requested];
        file.read_exact(&mut bytes).map_err(|_| {
            BackendError::new(
                "healthmd_integrity_error",
                "The raw artifact changed during reading.",
            )
        })?;
        let next_offset = input
            .offset
            .checked_add(u64::try_from(bytes.len()).unwrap_or(u64::MAX))
            .ok_or_else(|| {
                BackendError::new("healthmd_integrity_error", "Invalid raw artifact bounds.")
            })?;
        Ok(json!({
            "schema": "healthmd.raw_artifact_chunk",
            "schema_version": 1,
            "job_id": input.job_id,
            "artifact": {
                "platform": match artifact.platform {
                    RawArtifactPlatform::Ios => "ios",
                    RawArtifactPlatform::Android => "android",
                },
                "profile": artifact.profile,
                "provider_id": artifact.provider_id,
                "format": artifact.format,
                "status": artifact.status,
                "byte_count": artifact.byte_count,
                "sha256": artifact.sha256
            },
            "chunk": {
                "offset": input.offset,
                "byte_count": bytes.len(),
                "next_offset": next_offset,
                "eof": next_offset == artifact.byte_count,
                "encoding": "base64",
                "data": BASE64_STANDARD.encode(bytes)
            }
        }))
    }

    async fn export_status(
        &self,
        _context: &CallContext,
        job_id: Uuid,
    ) -> Result<Value, BackendError> {
        match self.client.job_record(job_id) {
            Ok(record) => {
                let mut receipt = ios_job_receipt(&record);
                if record.request.response_mode == ResponseMode::RawJson
                    && record.state == JobState::Completed
                    && record.response_artifact.is_some()
                {
                    let artifact = self
                        .client
                        .raw_artifact(job_id)
                        .map_err(|error| backend_error(&error, Some(job_id)))?;
                    attach_raw_artifact_metadata(&mut receipt, &artifact);
                }
                Ok(receipt)
            }
            Err(ClientError::JobNotFound) => {
                let record = self
                    .client
                    .v2_job_record(job_id)
                    .map_err(|error| backend_error(&error, Some(job_id)))?;
                let mut receipt = android_job_receipt(&record);
                if matches!(
                    record.request.product,
                    v2::ExportProduct::AndroidProviderNativeSnapshotV1 { .. }
                ) && record.state == JobState::Completed
                    && record.response_artifact.is_some()
                {
                    let artifact = self
                        .client
                        .raw_artifact(job_id)
                        .map_err(|error| backend_error(&error, Some(job_id)))?;
                    attach_raw_artifact_metadata(&mut receipt, &artifact);
                }
                Ok(receipt)
            }
            Err(error) => Err(backend_error(&error, Some(job_id))),
        }
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
        let _gate = self.operation_gate.lock().await;
        match self.client.job_record(job_id) {
            Ok(record) => {
                if record.state.resume_requires_source() {
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
                match record.request.response_mode {
                    ResponseMode::WriteFiles => self
                        .client
                        .resume_files(
                            job_id,
                            self.configuration.device_id,
                            self.configuration.port,
                            timeout,
                        )
                        .await
                        .map(|result| export_success(&result.receipt.payload))
                        .map_err(|error| backend_error(&error, Some(job_id))),
                    ResponseMode::RawJson => self
                        .client
                        .resume_raw(
                            job_id,
                            self.configuration.device_id,
                            self.configuration.port,
                            timeout,
                        )
                        .await
                        .and_then(|_| self.client.raw_artifact(job_id))
                        .map(|artifact| durable_raw_export_success(job_id, &artifact))
                        .map_err(|error| backend_error(&error, Some(job_id))),
                }
            }
            Err(ClientError::JobNotFound) => {
                let record = self
                    .client
                    .v2_job_record(job_id)
                    .map_err(|error| backend_error(&error, Some(job_id)))?;
                let pinned = record.request.source_installation_id;
                self.validate_pinned_device(pinned)?;
                if record.state.resume_requires_source() {
                    self.wait_for_active_source_on(context, Some(pinned))
                        .await?;
                }
                let result = self
                    .client
                    .resume_android(job_id, Some(pinned), self.configuration.port, timeout)
                    .await
                    .map_err(|error| backend_error(&error, Some(job_id)))?;
                if matches!(
                    record.request.product,
                    v2::ExportProduct::AndroidProviderNativeSnapshotV1 { .. }
                ) {
                    let artifact = self
                        .client
                        .raw_artifact(job_id)
                        .map_err(|error| backend_error(&error, Some(job_id)))?;
                    Ok(durable_raw_export_success(job_id, &artifact))
                } else {
                    Ok(android_artifact_success(job_id, &result.receipt))
                }
            }
            Err(error) => Err(backend_error(&error, Some(job_id))),
        }
    }

    async fn cancel_export(
        &self,
        context: &CallContext,
        job_id: Uuid,
    ) -> Result<Value, BackendError> {
        // Cancellation intentionally bypasses the operation gate. Persist the explicit marker
        // before opening a second listener so an active export that owns the port can deliver it.
        match self.client.job_record(job_id) {
            Ok(record) => {
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
                    if let Err(error) = self.wait_for_active_source_on(context, Some(pinned)).await
                    {
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
                    .map(|()| cancelled_job_value(job_id, "ios"))
                    .map_err(|error| backend_error(&error, Some(job_id)))
            }
            Err(ClientError::JobNotFound) => {
                let record = self
                    .client
                    .v2_job_record(job_id)
                    .map_err(|error| backend_error(&error, Some(job_id)))?;
                let pinned = record.request.source_installation_id;
                self.validate_pinned_device(pinned)?;
                if !record.state.is_terminal() {
                    self.client
                        .request_android_job_cancellation(job_id, Some(pinned))
                        .map_err(|error| backend_error(&error, Some(job_id)))?;
                    if let Err(error) = self.wait_for_active_source_on(context, Some(pinned)).await
                    {
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
                }
                self.client
                    .cancel_android_job(
                        job_id,
                        Some(pinned),
                        self.configuration.port,
                        self.configuration.timeout,
                    )
                    .await
                    .map(|()| cancelled_job_value(job_id, "android"))
                    .map_err(|error| backend_error(&error, Some(job_id)))
            }
            Err(error) => Err(backend_error(&error, Some(job_id))),
        }
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
            let source_available = source.app_active && source.protected_data_available;
            let query_ready = source_available && source.can_trigger_queries.unwrap_or(false);
            let raw_export_ready = source_available && source.can_trigger_raw_exports;
            let ready = query_ready || raw_export_ready;
            json!({
                "schema": "healthmd.direct_readiness",
                "schema_version": 1,
                "status": if ready { "ready" } else { "unavailable" },
                "ready": ready,
                "query_ready": query_ready,
                "raw_export_ready": raw_export_ready,
                "message": if query_ready {
                    "The authenticated direct iPhone query and export service is ready."
                } else if raw_export_ready {
                    "The authenticated direct iPhone raw-export service is ready; typed queries are unavailable."
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
                "can_trigger_raw_exports": source.can_trigger_raw_exports,
                "can_trigger_file_exports": source.can_trigger_file_exports,
                "can_trigger_queries": source.can_trigger_queries,
                "active_job_id": source.active_job_id,
                "active_query_request_id": source.active_query_request_id,
                "query_capabilities": query,
                "wake": wake.clone()
            })
        }
        SourceStatus::Android(source) => {
            let raw_export_supported = source
                .available_products
                .contains(&v2::ProductId::AndroidProviderNativeSnapshotV1);
            let raw_export_ready =
                source.app_active && source.protected_data_available && raw_export_supported;
            json!({
                "schema": "healthmd.direct_readiness",
                "schema_version": 1,
                "status": if raw_export_ready { "ready" } else { "unavailable" },
                "ready": raw_export_ready,
                "query_ready": false,
                "raw_export_ready": raw_export_ready,
                "message": if raw_export_ready {
                    "The authenticated direct Android raw-export service is ready; typed queries are unsupported."
                } else {
                    "The Android direct raw-export service is not ready. Keep Health.md foreground with Direct CLI Access enabled."
                },
                "device_name": source.source.display_name,
                "application_protocol_version": result.application_protocol_version,
                "port": result.port,
                "app_active": source.app_active,
                "protected_data_available": source.protected_data_available,
                "export_in_progress": source.export_in_progress,
                "available_products": source.available_products,
                "active_job_id": source.active_job_id,
                "wake": wake.clone()
            })
        }
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

fn raw_export_success(
    job_id: Uuid,
    platform: &str,
    provider_id: &str,
    format: &str,
    source_status: &str,
    byte_count: u64,
    sha256: &str,
) -> Value {
    let status = normalized_raw_status(source_status);
    json!({
        "schema": "healthmd.raw_export_receipt",
        "schema_version": 1,
        "job_id": job_id,
        "status": status,
        "platform": platform,
        "provider_id": provider_id,
        "scope": "all_public_authorized",
        "format": format,
        "byte_count": byte_count,
        "sha256": sha256,
        "artifact_access": {
            "tool": "healthmd_raw_artifact_read",
            "job_bound": true,
            "encoding": "base64"
        },
        "message": "Health.md completed the requested public-and-authorized corpus job. Inspect the artifact manifest for exported, permission, unsupported, empty, skipped, partial, and read-error states; this receipt does not imply every type contained readable records."
    })
}

fn durable_raw_export_success(
    job_id: Uuid,
    artifact: &healthmd_client::direct::DurableRawArtifact,
) -> Value {
    raw_export_success(
        job_id,
        match artifact.platform {
            RawArtifactPlatform::Ios => "ios",
            RawArtifactPlatform::Android => "android",
        },
        artifact.provider_id.as_deref().unwrap_or("unknown"),
        artifact.format,
        &artifact.status,
        artifact.byte_count,
        &artifact.sha256,
    )
}

fn normalized_raw_status(status: &str) -> &str {
    match status {
        "complete" | "success" => "success",
        "partial" | "partial_success" => "partial_success",
        "failed" | "failure" => "failure",
        other => other,
    }
}

fn attach_raw_artifact_metadata(
    receipt: &mut Value,
    artifact: &healthmd_client::direct::DurableRawArtifact,
) {
    receipt["status"] = json!(normalized_raw_status(&artifact.status));
    receipt["scope"] = json!("all_public_authorized");
    receipt["artifact"] = json!({
        "platform": match artifact.platform {
            RawArtifactPlatform::Ios => "ios",
            RawArtifactPlatform::Android => "android",
        },
        "profile": artifact.profile,
        "provider_id": artifact.provider_id,
        "format": artifact.format,
        "status": artifact.status,
        "byte_count": artifact.byte_count,
        "sha256": artifact.sha256,
        "access": {
            "tool": "healthmd_raw_artifact_read",
            "job_bound": true,
            "encoding": "base64"
        }
    });
}

fn android_artifact_success(job_id: Uuid, receipt: &V2ArtifactReceipt) -> Value {
    json!({
        "job_id": job_id,
        "status": normalized_raw_status(&receipt.status),
        "platform": "android",
        "product": format!("{:?}", receipt.product_id).to_lowercase(),
        "byte_count": receipt.byte_count,
        "sha256": receipt.sha256,
        "message": "Health.md completed and validated the Android direct export."
    })
}

fn cancelled_job_value(job_id: Uuid, platform: &str) -> Value {
    json!({
        "job_id": job_id,
        "status": "cancelled",
        "platform": platform,
        "message": "The durable direct mobile export was cancelled."
    })
}

fn ios_job_receipt(record: &JobRecord) -> Value {
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
    value["platform"] = json!("ios");
    value["product"] = json!(if record.request.response_mode == ResponseMode::RawJson {
        "raw_corpus"
    } else {
        "generated_files"
    });
    if record.request.response_mode == ResponseMode::RawJson && record.response_artifact.is_some() {
        value["artifact_access"] = json!({
            "tool": "healthmd_raw_artifact_read",
            "job_bound": true,
            "encoding": "base64"
        });
    }
    value
}

fn android_job_receipt(record: &V2JobRecord) -> Value {
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
    let raw = matches!(
        record.request.product,
        v2::ExportProduct::AndroidProviderNativeSnapshotV1 { .. }
    );
    let mut value = json!({
        "job_id": record.request.job_id,
        "status": status,
        "platform": "android",
        "product": if raw { "raw_corpus" } else { "generated_files" },
        "state": record.state,
        "created_at": record.request.created_at,
        "updated_at": record.updated_at,
        "expires_at": record.request.expires_at,
        "committed_partitions": record.committed_partitions,
        "committed_bytes": record.committed_bytes,
        "artifact_ready": record.response_artifact.is_some(),
        "message": match record.state {
            JobState::Paused => "The direct transfer paused and can be resumed.",
            JobState::Completed => "The durable direct Android export completed.",
            JobState::Failed => "The durable direct Android export failed.",
            JobState::Cancelled => "The durable direct Android export was cancelled.",
            _ => "The durable direct Android export has not reached a terminal state.",
        }
    });
    if raw && record.response_artifact.is_some() {
        value["artifact_access"] = json!({
            "tool": "healthmd_raw_artifact_read",
            "job_bound": true,
            "encoding": "base64"
        });
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
            "No mobile source is paired. Pair a supported device first.",
            false,
        ),
        ClientError::DeviceSelectionRequired(_) => (
            "healthmd_device_ambiguous",
            "More than one mobile source is paired. Configure a device ID.",
            false,
        ),
        ClientError::DeviceNotPaired(_) => (
            "healthmd_not_paired",
            "The requested mobile source is not paired. Pair it again or select a trusted device.",
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
            "Cancellation is durably pending delivery to the paired mobile source.",
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
            "The direct mobile operation timed out.",
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
            "The direct mobile service is unavailable. Keep Health.md foreground and verify Direct CLI Access.",
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
    fn android_readiness_advertises_raw_without_claiming_typed_queries() {
        let result = StatusResult {
            status: SourceStatus::Android(v2::SourceStatus {
                source: v2::SourceIdentity {
                    installation_id: Uuid::new_v4(),
                    platform: v2::SourcePlatform::Android,
                    display_name: "Android fixture".to_owned(),
                    app_version: "1".to_owned(),
                },
                app_active: true,
                protected_data_available: true,
                export_in_progress: false,
                available_products: vec![v2::ProductId::AndroidProviderNativeSnapshotV1],
                active_job_id: None,
                message: None,
            }),
            peer_capabilities: healthmd_protocol::wire::PeerCapabilities::portable_cli(SwiftUuid(
                Uuid::new_v4(),
            )),
            android_capabilities: None,
            application_protocol_version: 2,
            port: 17_647,
        };
        let readiness = status_value(&result, &json!({"enabled": false}));
        assert_eq!(readiness["ready"], true);
        assert_eq!(readiness["query_ready"], false);
        assert_eq!(readiness["raw_export_ready"], true);
        assert_eq!(readiness["device_name"], "Android fixture");
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
