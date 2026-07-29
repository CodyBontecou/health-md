use std::{env, fs, time::Duration};

use chrono::{NaiveDate, Utc};
use healthmd_protocol::{
    ANDROID_APPLICATION_PROTOCOL_VERSION, IOS_APPLICATION_PROTOCOL_VERSION,
    IOS_QUERY_APPLICATION_PROTOCOL_VERSION, JOB_LIFETIME_SECONDS,
    encoding::SwiftUuid,
    models::{
        DateSelection, ExportFailureReason, ExportRequest, JobIdPayload, PeerBinding, ResponseMode,
    },
    transfer::{decode_binary_chunk, negotiate_transfer},
    v2,
    wire::{
        DirectMessage, DirectQueryRequest, Empty, IphoneStatus, PeerCapabilities, PeerPlatform,
        StatusRequest, Unlabeled,
    },
};
use tokio::{net::TcpListener, time::Instant};
use uuid::Uuid;

use crate::{
    ClientError,
    credentials::OsCredentialStore,
    file_receiver::{FileExportReceipt, FileReceiver, GeneratedDestination},
    handshake::{AuthenticatedConnection, authenticate},
    job::{JobRecord, JobState, JobStore},
    packet::PacketConnection,
    raw_receiver::{JsonlExtractionArtifact, RawReceiveArtifact, RawReceiver},
    secure_channel::{SecureChannel, SecurePayload, V2SecurePayload},
    storage::{ClientIdentity, IdentityStore, StorageLayout},
    trust::{TrustState, TrustStore, TrustedClient},
    v2_job::{V2JobRecord, V2JobStore},
    v2_receiver::{V2ArtifactReceipt, V2ArtifactReceiver},
};

const MAXIMUM_AUTHENTICATION_ATTEMPTS: usize = 8;

struct TrustLease {
    _file: fs::File,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceKind {
    Ios,
    Android,
}

impl SourceKind {
    #[must_use]
    pub const fn wire_name(self) -> &'static str {
        match self {
            Self::Ios => "ios",
            Self::Android => "android",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PairingResult {
    pub device: TrustedClient,
    pub source: SourceKind,
    pub port: u16,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SourceStatus {
    Ios(IphoneStatus),
    Android(v2::SourceStatus),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StatusResult {
    pub status: SourceStatus,
    pub peer_capabilities: PeerCapabilities,
    pub android_capabilities: Option<v2::SourceHello>,
    pub application_protocol_version: i32,
    pub port: u16,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RawExportResult {
    pub artifact: RawReceiveArtifact,
    pub port: u16,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FileExportResult {
    pub receipt: FileExportReceipt,
    pub port: u16,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AndroidExportResult {
    pub receipt: V2ArtifactReceipt,
    pub port: u16,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QueryResult {
    pub response: serde_json::Value,
    pub port: u16,
}

pub struct DirectClient {
    pub identity: ClientIdentity,
    pub layout: StorageLayout,
    display_name: String,
    trust_store: TrustStore<OsCredentialStore>,
}

impl DirectClient {
    /// Open the durable portable direct-client context.
    ///
    /// # Errors
    ///
    /// Returns an error when private storage or the installation identity is unavailable.
    pub fn open() -> Result<Self, ClientError> {
        let layout = StorageLayout::discover()?;
        let identity = IdentityStore::new(layout.clone()).load_or_create(Utc::now())?;
        Ok(Self {
            identity,
            layout,
            display_name: local_display_name(),
            trust_store: TrustStore::new(OsCredentialStore),
        })
    }

    /// List locally trusted mobile sources without making a network connection.
    ///
    /// # Errors
    ///
    /// Returns an error when the operating system credential store is unavailable.
    pub async fn paired_devices(&self) -> Result<Vec<TrustedClient>, ClientError> {
        let mut devices = self.load_trust().await?.trusted_clients;
        devices.sort_by_cached_key(|device| device.display_name.to_lowercase());
        Ok(devices)
    }

    /// Resolve the selected paired source platform without making a network connection.
    ///
    /// Existing v1 trust records predate platform metadata and are treated as iOS until their next
    /// authenticated hello updates the record.
    ///
    /// # Errors
    ///
    /// Returns a device-selection or trust-store error.
    pub async fn selected_source_kind(
        &self,
        requested: Option<Uuid>,
    ) -> Result<SourceKind, ClientError> {
        let device = self.selected_source(requested).await?;
        Ok(if device.platform == Some(PeerPlatform::Android) {
            SourceKind::Android
        } else {
            SourceKind::Ios
        })
    }

    /// Resolve the selected paired source record without a network connection.
    ///
    /// # Errors
    ///
    /// Returns a device-selection or trust-store error.
    pub async fn selected_source(
        &self,
        requested: Option<Uuid>,
    ) -> Result<TrustedClient, ClientError> {
        let selected = self.selected_device_id(requested).await?;
        self.paired_devices()
            .await?
            .into_iter()
            .find(|device| device.installation_id.0 == selected)
            .ok_or(ClientError::DeviceNotPaired(selected))
    }

    /// Remove local trust for one mobile source.
    ///
    /// # Errors
    ///
    /// Returns an error when the operating system credential store cannot be updated.
    pub async fn unpair(&self, device_id: Uuid) -> Result<bool, ClientError> {
        let _lease = acquire_trust_lease(self.layout.clone()).await?;
        let mut state = self.load_trust().await?;
        let removed = state.forget_client(device_id);
        self.trust_store.save(&state).await?;
        Ok(removed)
    }

    /// Explicitly replace unusable or unwanted local direct trust with an empty state.
    ///
    /// # Errors
    ///
    /// Returns an error when the native credential store cannot be updated.
    pub async fn reset_trust(&self) -> Result<(), ClientError> {
        let _lease = acquire_trust_lease(self.layout.clone()).await?;
        self.trust_store
            .save(&TrustState::empty(self.identity.installation_id))
            .await
    }

    /// Listen for and pair one foreground Health.md mobile source using platform-specific codes.
    ///
    /// `on_listening` runs only after the port is bound, so callers can safely print connection
    /// instructions before waiting for the source.
    ///
    /// # Errors
    ///
    /// Returns an error for an invalid code/timeout, listener failure, authentication failure,
    /// incompatible source, or unavailable secure storage.
    pub async fn pair<F>(
        &self,
        ios_pairing_code: &str,
        android_pairing_code: &str,
        port: u16,
        timeout: Duration,
        on_listening: F,
    ) -> Result<PairingResult, ClientError>
    where
        F: FnOnce(u16),
    {
        let ios_code = crate::handshake::normalize_pairing_code(ios_pairing_code);
        let android_code = crate::handshake::normalize_pairing_code(android_pairing_code);
        if ios_code.len() != 6 || android_code.len() != 20 {
            return Err(ClientError::Authentication(
                "iOS pairing requires 6 digits and Android pairing requires 20 digits".into(),
            ));
        }
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        on_listening(bound_port);
        let mut connection = self
            .accept_compatible(&listener, Some((&ios_code, &android_code)), None, timeout)
            .await?;
        let device_id = connection.device.installation_id.0;
        let was_new_pairing = connection.was_new_pairing;
        let result = async {
            let peer =
                exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
            let (source, _) = validate_source_peer(&connection.channel, &peer)?;
            if !pairing_protocol_matches_source(connection.pairing_protocol_version, source) {
                return Err(ClientError::Authentication(
                    "the source platform does not match its pairing protocol".into(),
                ));
            }
            if source == SourceKind::Android {
                let hello =
                    receive_android_source_hello(&mut connection.channel, device_id).await?;
                if hello.source.display_name != connection.device.display_name {
                    return Err(ClientError::Authentication(
                        "the Android source identity changed during negotiation".into(),
                    ));
                }
            }
            self.remember_platform(device_id, peer.platform).await?;
            connection.device.platform = Some(peer.platform);
            Ok(PairingResult {
                device: connection.device,
                source,
                port: bound_port,
            })
        }
        .await;
        if result.is_err() && was_new_pairing {
            let _ = self.unpair(device_id).await;
        }
        result
    }

    /// Connect to the selected paired foreground source and request readiness.
    ///
    /// # Errors
    ///
    /// Returns an error for device selection, listener/timeout/authentication failure, or an
    /// incompatible/unexpected source response.
    pub async fn status(
        &self,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<StatusResult, ClientError> {
        let selected = self.selected_device_id(device_id).await?;
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        let mut connection = self
            .accept_compatible(&listener, None, Some(selected), timeout)
            .await?;
        let peer = exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
        let (source, application_protocol_version) =
            validate_source_peer(&connection.channel, &peer)?;
        self.remember_platform(selected, peer.platform).await?;

        let (status, android_capabilities) = match source {
            SourceKind::Ios => {
                connection
                    .channel
                    .send(&DirectMessage::StatusRequest(Unlabeled::from(
                        StatusRequest {
                            requested_at: Utc::now(),
                        },
                    )))
                    .await?;
                let DirectMessage::StatusResponse(Unlabeled { value: status }) =
                    receive_message(&mut connection.channel, Duration::from_secs(10)).await?
                else {
                    return Err(ClientError::UnexpectedMessage);
                };
                (SourceStatus::Ios(status), None)
            }
            SourceKind::Android => {
                let capabilities =
                    receive_android_source_hello(&mut connection.channel, selected).await?;
                connection
                    .channel
                    .send_v2(&v2::Envelope::new(v2::Message::StatusRequest(
                        v2::StatusRequest {
                            requested_at: Utc::now(),
                        },
                    )))
                    .await?;
                let envelope =
                    receive_v2_message(&mut connection.channel, Duration::from_secs(10)).await?;
                let v2::Message::StatusResponse(status) = envelope.message else {
                    return Err(ClientError::UnexpectedMessage);
                };
                if status.source.installation_id != selected {
                    return Err(ClientError::Authentication(
                        "the Android status source identity does not match the paired device"
                            .into(),
                    ));
                }
                (SourceStatus::Android(status), Some(capabilities))
            }
        };
        Ok(StatusResult {
            status,
            peer_capabilities: peer,
            android_capabilities,
            application_protocol_version,
            port: bound_port,
        })
    }

    /// Execute one bounded query page on a foreground paired iPhone.
    ///
    /// Query protocol v3 is capability-gated and reuses the deployed iOS pairing and encrypted
    /// transport. No Health.md macOS app or localhost service is involved.
    ///
    /// # Errors
    ///
    /// Returns an error for device selection, listener/authentication failure, missing v3 query
    /// capability, timeout, malformed response, or a stable health-free iPhone rejection.
    #[allow(clippy::too_many_lines)]
    pub async fn query(
        &self,
        request: DirectQueryRequest,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<QueryResult, ClientError> {
        if request.protocol_version != IOS_QUERY_APPLICATION_PROTOCOL_VERSION
            || request
                .query
                .get("schema")
                .and_then(serde_json::Value::as_str)
                != Some("healthmd.query_request")
            || request
                .query
                .get("schema_version")
                .and_then(serde_json::Value::as_i64)
                != Some(1)
        {
            return Err(ClientError::QueryUnsupported);
        }
        let selected = self.selected_device_id(device_id).await?;
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        let mut connection = self
            .accept_compatible(&listener, None, Some(selected), timeout)
            .await?;
        let peer = exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
        let (source, _) = validate_source_peer(&connection.channel, &peer)?;
        self.remember_platform(selected, peer.platform).await?;
        if source != SourceKind::Ios
            || !peer
                .protocol_versions
                .contains(&IOS_QUERY_APPLICATION_PROTOCOL_VERSION)
        {
            return Err(ClientError::QueryUnsupported);
        }
        let capabilities = peer.query.as_ref().ok_or(ClientError::QueryUnsupported)?;
        if !capabilities.schema_versions.contains(&1)
            || !capabilities.detail_levels.contains(&request.detail_level)
            || capabilities.maximum_page_items <= 0
            || capabilities.maximum_page_bytes <= 0
        {
            return Err(ClientError::QueryUnsupported);
        }
        let operation = request
            .query
            .pointer("/operation/type")
            .and_then(serde_json::Value::as_str)
            .ok_or(ClientError::QueryUnsupported)?;
        if !capabilities
            .operations
            .iter()
            .any(|value| value == operation)
        {
            return Err(ClientError::QueryUnsupported);
        }
        let max_items = request
            .query
            .pointer("/page/max_items")
            .and_then(serde_json::Value::as_i64)
            .ok_or(ClientError::QueryUnsupported)?;
        let max_bytes = request
            .query
            .pointer("/page/max_bytes")
            .and_then(serde_json::Value::as_i64)
            .ok_or(ClientError::QueryUnsupported)?;
        if max_items <= 0
            || max_items > i64::from(capabilities.maximum_page_items)
            || max_bytes <= 0
            || max_bytes > i64::from(capabilities.maximum_page_bytes)
        {
            return Err(ClientError::QueryUnsupported);
        }

        let request_id = request.request_id;
        connection
            .channel
            .send(&DirectMessage::QueryRequest(Unlabeled::from(request)))
            .await?;
        let deadline = Instant::now() + timeout;
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            match receive_message(&mut connection.channel, remaining).await? {
                DirectMessage::QueryResponse(Unlabeled { value }) => {
                    if value.request_id != request_id
                        || value
                            .response
                            .get("schema")
                            .and_then(serde_json::Value::as_str)
                            != Some("healthmd.query_response")
                        || value
                            .response
                            .get("schema_version")
                            .and_then(serde_json::Value::as_i64)
                            != Some(1)
                        || serde_json::to_vec(&value.response)
                            .map_err(|_| ClientError::MalformedPacket)?
                            .len()
                            > usize::try_from(max_bytes)
                                .map_err(|_| ClientError::MalformedPacket)?
                    {
                        return Err(ClientError::MalformedPacket);
                    }
                    return Ok(QueryResult {
                        response: value.response,
                        port: bound_port,
                    });
                }
                DirectMessage::QueryRejected(Unlabeled { value }) => {
                    if value.request_id != request_id
                        || value.code.is_empty()
                        || value.code.len() > 128
                        || value.message.is_empty()
                        || value.message.len() > 512
                    {
                        return Err(ClientError::MalformedPacket);
                    }
                    return Err(ClientError::QueryRejected {
                        code: value.code,
                        message: value.message,
                        retryable: value.retryable,
                    });
                }
                DirectMessage::Ping(Empty {}) => {
                    connection
                        .channel
                        .send(&DirectMessage::Pong(Empty {}))
                        .await?;
                }
                _ => return Err(ClientError::UnexpectedMessage),
            }
        }
    }

    /// Start or resume a durable Android v2 export.
    ///
    /// # Errors
    ///
    /// Returns an error for incompatible source/product, changed request/destination, transfer
    /// protocol violations, interruption, cancellation, validation, or destination commit failure.
    #[allow(clippy::too_many_lines)]
    pub async fn export_android(
        &self,
        request: v2::ExportRequest,
        destination_root: Option<std::path::PathBuf>,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<AndroidExportResult, ClientError> {
        if request.created_at >= request.expires_at || request.expires_at <= Utc::now() {
            return Err(ClientError::JobExpired);
        }
        let selected = self.selected_device_id(device_id).await?;
        if request.source_installation_id != selected {
            return Err(ClientError::DeviceNotPaired(request.source_installation_id));
        }
        let generated = matches!(request.product, v2::ExportProduct::GeneratedFilesV1 { .. });
        if generated != destination_root.is_some() || generated != request.destination.is_some() {
            return Err(ClientError::InvalidTransfer(
                "Android destination does not match the requested product".into(),
            ));
        }
        let destination_root = destination_root
            .map(|path| {
                path.to_str().map(ToOwned::to_owned).ok_or_else(|| {
                    ClientError::InvalidTransfer(
                        "Android generated-file destination must be valid UTF-8".into(),
                    )
                })
            })
            .transpose()?;
        let jobs = V2JobStore::new(self.layout.clone())?;
        let _ = jobs.remove_expired(Utc::now())?;
        match jobs.load(request.job_id) {
            Ok(existing) => {
                if existing.request != request || existing.destination_root != destination_root {
                    return Err(ClientError::InvalidTransfer(
                        "durable Android export request or destination changed".into(),
                    ));
                }
                if existing.state == JobState::Completed {
                    return Ok(AndroidExportResult {
                        receipt: V2ArtifactReceiver::new(self.layout.clone(), jobs)
                            .receipt(request.job_id)?,
                        port,
                    });
                }
            }
            Err(ClientError::JobNotFound) => {
                jobs.save(&V2JobRecord::new(request.clone(), destination_root.clone()))?;
            }
            Err(error) => return Err(error),
        }
        let _execution = jobs.acquire_execution(request.job_id)?;
        let mut record = jobs.load(request.job_id)?;
        let remaining_lifetime = request.expires_at - Utc::now();
        if remaining_lifetime
            <= chrono::Duration::from_std(timeout).map_err(|_| ClientError::JobExpired)?
        {
            return Err(ClientError::JobExpired);
        }
        if matches!(
            record.state,
            JobState::Cancelled | JobState::CancellationPending | JobState::Failed
        ) {
            return Err(ClientError::JobNotResumable(
                request.job_id,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let binding = v2::PeerBinding {
            source_installation_id: selected,
            destination_installation_id: self.identity.installation_id.0,
        };
        if record
            .peer_binding
            .as_ref()
            .is_some_and(|saved| saved != &binding)
        {
            return Err(ClientError::DeviceNotPaired(selected));
        }
        record.peer_binding = Some(binding);
        if record.state != JobState::AwaitingPeerAcknowledgement {
            record.state = JobState::Connecting;
            record.updated_at = Utc::now();
            record.message = Some("Waiting for the paired Android source to connect.".into());
        }
        jobs.save(&record)?;

        let operation_deadline = Instant::now() + timeout;
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        let overall_remaining = operation_deadline.saturating_duration_since(Instant::now());
        let result = tokio::time::timeout(overall_remaining, async {
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), timeout)
                .await?;
            let peer =
                exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
            let (source, version) = validate_source_peer(&connection.channel, &peer)?;
            if source != SourceKind::Android || version != ANDROID_APPLICATION_PROTOCOL_VERSION {
                return Err(ClientError::Authentication(
                    "the selected source is not a compatible Health.md Android app".into(),
                ));
            }
            self.remember_platform(selected, PeerPlatform::Android)
                .await?;
            let capabilities =
                receive_android_source_hello(&mut connection.channel, selected).await?;
            let requested_product = request.product.product_id();
            let capability = capabilities
                .products
                .iter()
                .find(|product| product.product_id == requested_product)
                .ok_or_else(|| {
                    ClientError::InvalidTransfer(
                        "the Android app does not advertise the requested export product".into(),
                    )
                })?;
            if let v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
                provider_id,
                format,
                ..
            } = &request.product
            {
                let artifact_format = match format {
                    v2::RawSnapshotFormat::Json => v2::ArtifactFormat::Json,
                    v2::RawSnapshotFormat::Ndjson => v2::ArtifactFormat::Ndjson,
                };
                if !capability.providers.contains(provider_id)
                    || !capability.formats.contains(&artifact_format)
                {
                    return Err(ClientError::InvalidTransfer(
                        "the Android app does not advertise the requested provider or raw format"
                            .into(),
                    ));
                }
            }
            connection
                .channel
                .send_v2(&v2::Envelope::new(v2::Message::ExportRequest(
                    request.clone(),
                )))
                .await?;
            let remaining = operation_deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            self.process_android_export(&mut connection.channel, &request, &jobs, remaining)
                .await
        })
        .await
        .unwrap_or(Err(ClientError::TimedOut));

        match result {
            Ok(receipt) => Ok(AndroidExportResult {
                receipt,
                port: bound_port,
            }),
            Err(error) => {
                if let Ok(mut paused) = jobs.load(request.job_id) {
                    if !paused.state.is_terminal()
                        && paused.state != JobState::AwaitingPeerAcknowledgement
                    {
                        paused.state = JobState::Paused;
                        paused.updated_at = Utc::now();
                        paused.message = Some(error.to_string());
                        let _ = jobs.save(&paused);
                    }
                }
                if matches!(
                    error,
                    ClientError::InvalidTransfer(_)
                        | ClientError::Cancelled
                        | ClientError::JobNotResumable(_, _)
                ) {
                    Err(error)
                } else {
                    Err(ClientError::ExportPaused(request.job_id))
                }
            }
        }
    }

    /// Resume a durable Android export without changing its request or destination.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent/non-resumable or transfer fails.
    pub async fn resume_android(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<AndroidExportResult, ClientError> {
        let jobs = V2JobStore::new(self.layout.clone())?;
        let record = jobs.load(job_id)?;
        let selected = record.request.source_installation_id;
        if let Some(requested) = device_id {
            if requested != selected {
                return Err(ClientError::DeviceNotPaired(requested));
            }
        }
        self.export_android(
            record.request,
            record.destination_root.map(Into::into),
            Some(selected),
            port,
            timeout,
        )
        .await
    }

    /// Read a durable Android v2 job without contacting the source.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent, expired, or corrupt.
    pub fn v2_job_record(&self, job_id: Uuid) -> Result<V2JobRecord, ClientError> {
        V2JobStore::new(self.layout.clone())?.load(job_id)
    }

    /// Start or resume a durable strict-raw export over Manual IP/Tailscale.
    ///
    /// # Errors
    ///
    /// Returns an error for invalid requests/jobs, peer selection or authentication failure,
    /// protocol violations, interrupted transfer, cancellation, or durable storage failure.
    #[allow(clippy::too_many_lines)]
    pub async fn export_raw(
        &self,
        request: ExportRequest,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<RawExportResult, ClientError> {
        if request.response_mode != ResponseMode::RawJson || request.raw_profile.is_none() {
            return Err(ClientError::InvalidTransfer(
                "raw export request has incompatible response settings".into(),
            ));
        }
        if request.created_at + chrono::Duration::seconds(JOB_LIFETIME_SECONDS) <= Utc::now() {
            return Err(ClientError::JobExpired);
        }
        let selected = self.selected_device_id(device_id).await?;
        let jobs = JobStore::new(self.layout.clone())?;
        let _ = jobs.remove_expired(Utc::now())?;
        match jobs.load(request.job_id.0) {
            Ok(existing) => {
                if existing.request != request {
                    return Err(ClientError::InvalidTransfer(
                        "durable export request changed".into(),
                    ));
                }
                if existing.state == JobState::Completed {
                    let receiver = RawReceiver::new(self.layout.clone(), jobs);
                    return Ok(RawExportResult {
                        artifact: receiver.artifact(request.job_id.0)?,
                        port,
                    });
                }
            }
            Err(ClientError::JobNotFound) => jobs.save(&JobRecord::new(request.clone()))?,
            Err(error) => return Err(error),
        }
        let _execution = jobs.acquire_execution(request.job_id.0)?;

        let mut record = jobs.load(request.job_id.0)?;
        ensure_job_execution_window(&record, timeout)?;
        if matches!(
            record.state,
            JobState::Cancelled | JobState::CancellationPending | JobState::Failed
        ) || jobs.cancellation_requested(request.job_id.0)
        {
            return Err(ClientError::JobNotResumable(
                request.job_id.0,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let intended_binding = PeerBinding {
            source_installation_id: SwiftUuid(selected),
            destination_installation_id: self.identity.installation_id,
        };
        if record
            .peer_binding
            .as_ref()
            .is_some_and(|binding| binding != &intended_binding)
        {
            return Err(ClientError::DeviceNotPaired(selected));
        }
        record.peer_binding = Some(intended_binding);
        record.state = JobState::Connecting;
        record.updated_at = Utc::now();
        record.message = Some("Waiting for the paired iPhone to connect.".into());
        jobs.save(&record)?;

        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        let result = async {
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), timeout)
                .await?;
            let peer =
                exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
            validate_iphone_peer(&connection.channel, &peer)?;
            let negotiation = negotiate_transfer(
                &PeerCapabilities::portable_cli(self.identity.installation_id).transfer,
                &peer.transfer,
            )
            .ok_or_else(|| {
                ClientError::Authentication(
                    "the iPhone cannot negotiate bounded direct transfer".into(),
                )
            })?;
            connection
                .channel
                .send(&DirectMessage::ExportRequest(Unlabeled::from(
                    request.clone(),
                )))
                .await?;
            self.process_raw_export(
                &mut connection.channel,
                &peer,
                &request,
                &jobs,
                negotiation.partition_target_bytes,
                timeout,
            )
            .await
        }
        .await;

        match result {
            Ok(artifact) => Ok(RawExportResult {
                artifact,
                port: bound_port,
            }),
            Err(error) => {
                if let Ok(mut paused) = jobs.load(request.job_id.0) {
                    if !paused.state.is_terminal()
                        && paused.state != JobState::AwaitingPeerAcknowledgement
                    {
                        paused.state = JobState::Paused;
                        paused.updated_at = Utc::now();
                        paused.message = Some(error.to_string());
                        let _ = jobs.save(&paused);
                    }
                }
                if matches!(
                    error,
                    ClientError::InvalidTransfer(_)
                        | ClientError::Cancelled
                        | ClientError::JobNotResumable(_, _)
                ) {
                    Err(error)
                } else {
                    Err(ClientError::ExportPaused(request.job_id.0))
                }
            }
        }
    }

    /// Start or resume a durable production-generated file export.
    ///
    /// # Errors
    ///
    /// Returns an error for invalid destination/request, peer or protocol failure, interrupted
    /// transfer, destination conflict, or durable storage failure.
    #[allow(clippy::too_many_lines)]
    pub async fn export_files(
        &self,
        request: ExportRequest,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<FileExportResult, ClientError> {
        if request.response_mode != ResponseMode::WriteFiles || request.raw_profile.is_some() {
            return Err(ClientError::InvalidTransfer(
                "generated-file request has incompatible response settings".into(),
            ));
        }
        let destination = request.destination.as_ref().ok_or_else(|| {
            ClientError::InvalidTransfer("generated-file destination is missing".into())
        })?;
        let _validated_destination =
            GeneratedDestination::open(std::path::Path::new(&destination.root_path))?;
        if request.created_at + chrono::Duration::seconds(JOB_LIFETIME_SECONDS) <= Utc::now() {
            return Err(ClientError::JobExpired);
        }
        let selected = self.selected_device_id(device_id).await?;
        let jobs = JobStore::new(self.layout.clone())?;
        let _ = jobs.remove_expired(Utc::now())?;
        match jobs.load(request.job_id.0) {
            Ok(existing) => {
                if existing.request != request {
                    return Err(ClientError::InvalidTransfer(
                        "durable file export request changed".into(),
                    ));
                }
                if existing.state == JobState::Completed {
                    return Ok(FileExportResult {
                        receipt: FileReceiver::new(self.layout.clone(), jobs)
                            .receipt(request.job_id.0)?,
                        port,
                    });
                }
            }
            Err(ClientError::JobNotFound) => jobs.save(&JobRecord::new(request.clone()))?,
            Err(error) => return Err(error),
        }
        let _execution = jobs.acquire_execution(request.job_id.0)?;
        let mut record = jobs.load(request.job_id.0)?;
        ensure_job_execution_window(&record, timeout)?;
        if matches!(
            record.state,
            JobState::Cancelled | JobState::CancellationPending | JobState::Failed
        ) || jobs.cancellation_requested(request.job_id.0)
        {
            return Err(ClientError::JobNotResumable(
                request.job_id.0,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let binding = PeerBinding {
            source_installation_id: SwiftUuid(selected),
            destination_installation_id: self.identity.installation_id,
        };
        if record
            .peer_binding
            .as_ref()
            .is_some_and(|saved| saved != &binding)
        {
            return Err(ClientError::DeviceNotPaired(selected));
        }
        record.peer_binding = Some(binding);
        record.state = JobState::Connecting;
        record.updated_at = Utc::now();
        record.message = Some("Waiting for the paired iPhone to connect.".into());
        jobs.save(&record)?;
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        let result = async {
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), timeout)
                .await?;
            let peer =
                exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
            validate_iphone_peer(&connection.channel, &peer)?;
            let negotiation = negotiate_transfer(
                &PeerCapabilities::portable_cli(self.identity.installation_id).transfer,
                &peer.transfer,
            )
            .ok_or_else(|| {
                ClientError::Authentication(
                    "the iPhone cannot negotiate bounded direct transfer".into(),
                )
            })?;
            connection
                .channel
                .send(&DirectMessage::ExportRequest(Unlabeled::from(
                    request.clone(),
                )))
                .await?;
            self.process_file_export(
                &mut connection.channel,
                &peer,
                &request,
                &jobs,
                negotiation.partition_target_bytes,
                timeout,
            )
            .await
        }
        .await;
        match result {
            Ok(receipt) => Ok(FileExportResult {
                receipt,
                port: bound_port,
            }),
            Err(error) => {
                if let Ok(mut paused) = jobs.load(request.job_id.0) {
                    if !paused.state.is_terminal()
                        && paused.state != JobState::AwaitingPeerAcknowledgement
                    {
                        paused.state = JobState::Paused;
                        paused.updated_at = Utc::now();
                        paused.message = Some(error.to_string());
                        let _ = jobs.save(&paused);
                    }
                }
                if matches!(
                    error,
                    ClientError::InvalidTransfer(_)
                        | ClientError::Cancelled
                        | ClientError::JobNotResumable(_, _)
                ) {
                    Err(error)
                } else {
                    Err(ClientError::ExportPaused(request.job_id.0))
                }
            }
        }
    }

    /// Resume a durable raw job without allowing its immutable request to change.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent/non-resumable or the export fails.
    pub async fn resume_raw(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<RawExportResult, ClientError> {
        let jobs = JobStore::new(self.layout.clone())?;
        let record = jobs.load(job_id)?;
        if matches!(
            record.state,
            JobState::Cancelled | JobState::CancellationPending | JobState::Failed
        ) || jobs.cancellation_requested(job_id)
        {
            return Err(ClientError::JobNotResumable(
                job_id,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let pinned = record
            .peer_binding
            .as_ref()
            .map(|binding| binding.source_installation_id.0);
        if let Some(requested) = device_id {
            if Some(requested) != pinned {
                return Err(ClientError::DeviceNotPaired(requested));
            }
        }
        self.export_raw(record.request, pinned.or(device_id), port, timeout)
            .await
    }

    /// Read a durable iOS v1 direct job without contacting the source.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent, expired, or corrupt.
    pub fn job_record(&self, job_id: Uuid) -> Result<JobRecord, ClientError> {
        let jobs = JobStore::new(self.layout.clone())?;
        let mut record = jobs.load(job_id)?;
        if jobs.cancellation_requested(job_id) && !record.state.is_terminal() {
            record.state = JobState::CancellationPending;
            record.message = Some("Cancellation is pending delivery to the paired iPhone.".into());
        }
        Ok(record)
    }

    /// Materialize a completed canonical projection into the public extraction envelope.
    ///
    /// # Errors
    ///
    /// Returns an error when the durable projection corpus is absent, incomplete, or invalid.
    pub fn extraction(
        &self,
        job_id: Uuid,
        pointers: &[String],
    ) -> Result<RawReceiveArtifact, ClientError> {
        let jobs = JobStore::new(self.layout.clone())?;
        RawReceiver::new(self.layout.clone(), jobs).extraction(job_id, pointers)
    }

    /// Materialize a completed projection as bounded JSONL plus its receipt sidecar.
    ///
    /// # Errors
    ///
    /// Returns an error when the durable projection is absent, invalid, or has an item over 64 MiB.
    pub fn extraction_jsonl(
        &self,
        job_id: Uuid,
        pointers: &[String],
    ) -> Result<JsonlExtractionArtifact, ClientError> {
        let jobs = JobStore::new(self.layout.clone())?;
        RawReceiver::new(self.layout.clone(), jobs).extraction_jsonl(job_id, pointers)
    }

    /// Deliver a durable cancellation request to the Android source.
    ///
    /// # Errors
    ///
    /// Returns `CancellationPending` if Android does not acknowledge before timeout.
    pub async fn cancel_android_job(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<(), ClientError> {
        let jobs = V2JobStore::new(self.layout.clone())?;
        let mut record = jobs.load(job_id)?;
        if record.state == JobState::Cancelled {
            return Ok(());
        }
        if record.state.is_terminal() {
            return Err(ClientError::JobNotResumable(
                job_id,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let selected = record.request.source_installation_id;
        if let Some(requested) = device_id {
            if requested != selected {
                return Err(ClientError::DeviceNotPaired(requested));
            }
        }
        jobs.request_cancellation(job_id)?;
        record.state = JobState::CancellationPending;
        record.updated_at = Utc::now();
        record.message = Some("Cancellation is pending delivery to Android.".into());
        jobs.save(&record)?;

        let deadline = Instant::now() + timeout;
        let result = tokio::time::timeout(timeout, async {
            let listener = bind_listener(port).await?;
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), timeout)
                .await?;
            let peer =
                exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
            if validate_source_peer(&connection.channel, &peer)?.0 != SourceKind::Android {
                return Err(ClientError::Authentication(
                    "the selected cancellation source is not Android".into(),
                ));
            }
            let _ = receive_android_source_hello(&mut connection.channel, selected).await?;
            connection
                .channel
                .send_v2(&v2::Envelope::new(v2::Message::Cancel(v2::JobPayload {
                    job_id,
                })))
                .await?;
            loop {
                let remaining = deadline.saturating_duration_since(Instant::now());
                if remaining.is_zero() {
                    return Err(ClientError::TimedOut);
                }
                let envelope = receive_v2_message(&mut connection.channel, remaining).await?;
                match envelope.message {
                    v2::Message::CancelAcknowledged(payload) if payload.job_id == job_id => {
                        jobs.mark_cancelled(job_id)?;
                        return Ok(());
                    }
                    v2::Message::Ping(v2::Empty {}) => {
                        connection
                            .channel
                            .send_v2(&v2::Envelope::new(v2::Message::Pong(v2::Empty {})))
                            .await?;
                    }
                    _ => return Err(ClientError::UnexpectedMessage),
                }
            }
        })
        .await
        .unwrap_or(Err(ClientError::TimedOut));
        result.map_err(|_| ClientError::CancellationPending(job_id))
    }

    /// Deliver a durable cancellation request to the job's pinned iPhone.
    ///
    /// # Errors
    ///
    /// Returns `CancellationPending` if iPhone does not acknowledge before the timeout.
    pub async fn cancel_job(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<(), ClientError> {
        let jobs = JobStore::new(self.layout.clone())?;
        let mut record = jobs.load(job_id)?;
        if record.state == JobState::Cancelled {
            return Ok(());
        }
        if record.state.is_terminal() {
            return Err(ClientError::JobNotResumable(
                job_id,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let selected = record
            .peer_binding
            .as_ref()
            .map(|binding| binding.source_installation_id.0)
            .ok_or_else(|| ClientError::JobNotResumable(job_id, "unbound".into()))?;
        if let Some(requested) = device_id {
            if requested != selected {
                return Err(ClientError::DeviceNotPaired(requested));
            }
        }
        jobs.request_cancellation(job_id)?;
        record.state = JobState::CancellationPending;
        record.updated_at = Utc::now();
        record.message = Some("Cancellation is pending delivery to the paired iPhone.".into());
        jobs.save(&record)?;

        let result = async {
            let listener = bind_listener(port).await?;
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), timeout)
                .await?;
            let peer =
                exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
            validate_iphone_peer(&connection.channel, &peer)?;
            connection
                .channel
                .send(&DirectMessage::Cancel(JobIdPayload {
                    job_id: SwiftUuid(job_id),
                }))
                .await?;
            let DirectMessage::CancelAcknowledged(payload) =
                receive_message(&mut connection.channel, timeout).await?
            else {
                return Err(ClientError::UnexpectedMessage);
            };
            if payload.job_id.0 != job_id {
                return Err(ClientError::UnexpectedMessage);
            }
            let mut receiver = RawReceiver::new(self.layout.clone(), jobs.clone());
            receiver.cancel(job_id)?;
            jobs.clear_cancellation_request(job_id);
            Ok(())
        }
        .await;
        result.map_err(|_| ClientError::CancellationPending(job_id))
    }

    /// Resume a durable generated-file job without changing its request or destination.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent/non-resumable or transfer/commit fails.
    pub async fn resume_files(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<FileExportResult, ClientError> {
        let jobs = JobStore::new(self.layout.clone())?;
        let record = jobs.load(job_id)?;
        if matches!(
            record.state,
            JobState::Cancelled | JobState::CancellationPending | JobState::Failed
        ) || jobs.cancellation_requested(job_id)
        {
            return Err(ClientError::JobNotResumable(
                job_id,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let pinned = record
            .peer_binding
            .as_ref()
            .map(|binding| binding.source_installation_id.0);
        if let Some(requested) = device_id {
            if Some(requested) != pinned {
                return Err(ClientError::DeviceNotPaired(requested));
            }
        }
        self.export_files(record.request, pinned.or(device_id), port, timeout)
            .await
    }

    #[allow(clippy::too_many_lines)]
    #[cfg_attr(windows, allow(dead_code))]
    async fn process_file_export(
        &self,
        channel: &mut SecureChannel,
        peer: &PeerCapabilities,
        request: &ExportRequest,
        jobs: &JobStore,
        partition_target_bytes: i64,
        timeout: Duration,
    ) -> Result<FileExportReceipt, ClientError> {
        let deadline = Instant::now() + timeout;
        let mut receiver = FileReceiver::new(self.layout.clone(), jobs.clone());
        let mut accepted = None;
        let mut finalized: Option<FileExportReceipt> = None;
        let mut cancellation_sent = false;
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            if jobs.cancellation_requested(request.job_id.0) && !cancellation_sent {
                channel
                    .send(&DirectMessage::Cancel(JobIdPayload {
                        job_id: request.job_id,
                    }))
                    .await?;
                cancellation_sent = true;
            }
            let payload = tokio::time::timeout(remaining, channel.receive())
                .await
                .map_err(|_| ClientError::TimedOut)??;
            match payload {
                SecurePayload::BinaryTransferFrame(_) if finalized.is_some() => {
                    return Err(ClientError::UnexpectedMessage);
                }
                SecurePayload::BinaryTransferFrame(frame) => {
                    let chunk = decode_binary_chunk(&frame)
                        .map_err(|error| ClientError::InvalidTransfer(error.to_string()))?;
                    let acknowledgement = receiver.receive_chunk(chunk)?;
                    channel
                        .send(&DirectMessage::TransferChunkAcknowledgement(
                            Unlabeled::from(acknowledgement),
                        ))
                        .await?;
                }
                SecurePayload::Message(message)
                    if finalized.is_some()
                        && !allowed_after_finalize(message.as_ref(), request.job_id) =>
                {
                    return Err(ClientError::UnexpectedMessage);
                }
                SecurePayload::Message(message) => match *message {
                    DirectMessage::ExportAccepted(Unlabeled { value }) => {
                        let expected = PeerBinding {
                            source_installation_id: peer.installation_id,
                            destination_installation_id: self.identity.installation_id,
                        };
                        if value.job_id != request.job_id
                            || value.peer_binding != expected
                            || value.resolved_date_identifiers.is_empty()
                            || !accepted_dates_match(request, &value.resolved_date_identifiers)
                        {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = JobState::Accepted;
                        record.updated_at = Utc::now();
                        record.peer_binding = Some(value.peer_binding.clone());
                        record.total_days = Some(
                            i64::try_from(value.resolved_date_identifiers.len()).map_err(|_| {
                                ClientError::InvalidTransfer("too many dates".into())
                            })?,
                        );
                        record.message = Some("iPhone accepted the direct file export.".into());
                        jobs.save(&record)?;
                        accepted = Some(value);
                    }
                    DirectMessage::TransferSession(Unlabeled { value }) => {
                        if value.partition_target_bytes != partition_target_bytes {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        receiver.prepare(
                            request.clone(),
                            accepted.clone().ok_or(ClientError::UnexpectedMessage)?,
                            value,
                        )?;
                    }
                    DirectMessage::FileManifest(Unlabeled { value }) => {
                        receiver.store_manifest(value)?;
                    }
                    DirectMessage::RawDayManifest(_) => {
                        return Err(ClientError::UnexpectedMessage);
                    }
                    DirectMessage::ExportProgress(Unlabeled { value }) => {
                        if value.job_id != request.job_id {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = if value.committed_partitions > 0 {
                            JobState::Transferring
                        } else {
                            JobState::Preparing
                        };
                        record.updated_at = Utc::now();
                        record.processed_days = value.processed_days;
                        record.total_days = Some(value.total_days);
                        record.committed_partitions = value.committed_partitions;
                        record.committed_bytes = value.committed_bytes;
                        record.message = Some(value.message);
                        jobs.save(&record)?;
                    }
                    DirectMessage::TransferOpen(Unlabeled { value }) => {
                        let disposition = receiver.disposition(value)?;
                        channel
                            .send(&DirectMessage::TransferDisposition(Unlabeled::from(
                                disposition,
                            )))
                            .await?;
                    }
                    DirectMessage::TransferPartitionComplete(Unlabeled { value }) => {
                        let acknowledgement = receiver.commit_partition(value)?;
                        channel
                            .send(&DirectMessage::TransferPartitionAcknowledgement(
                                Unlabeled::from(acknowledgement),
                            ))
                            .await?;
                    }
                    DirectMessage::TransferFinalize(Unlabeled { value }) => {
                        let receipt = receiver.finalize(&value)?;
                        let acknowledgement = FileReceiver::final_acknowledgement(&value, &receipt);
                        channel
                            .send(&DirectMessage::TransferFinalAcknowledgement(
                                Unlabeled::from(acknowledgement),
                            ))
                            .await?;
                        finalized = Some(receipt);
                    }
                    DirectMessage::CompletionConfirmed(payload)
                        if payload.job_id == request.job_id && finalized.is_some() =>
                    {
                        receiver.acknowledge_peer_completion(request.job_id.0)?;
                        return finalized.ok_or(ClientError::UnexpectedMessage);
                    }
                    DirectMessage::ExportRejected(Unlabeled { value }) => {
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = if value.reason == ExportFailureReason::Cancelled {
                            JobState::Cancelled
                        } else {
                            JobState::Failed
                        };
                        record.updated_at = Utc::now();
                        record.failure = Some(value.clone());
                        record.message = Some(value.message.clone());
                        jobs.save(&record)?;
                        return Err(ClientError::InvalidTransfer(value.message));
                    }
                    DirectMessage::Ping(Empty {}) => {
                        channel.send(&DirectMessage::Pong(Empty {})).await?;
                    }
                    DirectMessage::CancelAcknowledged(payload)
                        if payload.job_id == request.job_id =>
                    {
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = JobState::Cancelled;
                        record.updated_at = Utc::now();
                        jobs.save(&record)?;
                        jobs.clear_cancellation_request(request.job_id.0);
                        return Err(ClientError::Cancelled);
                    }
                    _ => {}
                },
            }
        }
    }

    #[allow(clippy::too_many_lines)]
    async fn process_raw_export(
        &self,
        channel: &mut SecureChannel,
        peer: &PeerCapabilities,
        request: &ExportRequest,
        jobs: &JobStore,
        partition_target_bytes: i64,
        timeout: Duration,
    ) -> Result<RawReceiveArtifact, ClientError> {
        let deadline = Instant::now() + timeout;
        let mut receiver = RawReceiver::new(self.layout.clone(), jobs.clone());
        let mut accepted = None;
        let mut finalized: Option<RawReceiveArtifact> = None;
        let mut cancellation_sent = false;

        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            if jobs.cancellation_requested(request.job_id.0) && !cancellation_sent {
                channel
                    .send(&DirectMessage::Cancel(JobIdPayload {
                        job_id: request.job_id,
                    }))
                    .await?;
                cancellation_sent = true;
            }
            let payload = tokio::time::timeout(remaining, channel.receive())
                .await
                .map_err(|_| ClientError::TimedOut)??;
            match payload {
                SecurePayload::BinaryTransferFrame(_) if finalized.is_some() => {
                    return Err(ClientError::UnexpectedMessage);
                }
                SecurePayload::BinaryTransferFrame(frame) => {
                    let chunk = decode_binary_chunk(&frame)
                        .map_err(|error| ClientError::InvalidTransfer(error.to_string()))?;
                    let acknowledgement = receiver.receive_chunk(chunk)?;
                    channel
                        .send(&DirectMessage::TransferChunkAcknowledgement(
                            Unlabeled::from(acknowledgement),
                        ))
                        .await?;
                }
                SecurePayload::Message(message)
                    if finalized.is_some()
                        && !allowed_after_finalize(message.as_ref(), request.job_id) =>
                {
                    return Err(ClientError::UnexpectedMessage);
                }
                SecurePayload::Message(message) => match *message {
                    DirectMessage::ExportAccepted(Unlabeled { value }) => {
                        let expected_binding = PeerBinding {
                            source_installation_id: peer.installation_id,
                            destination_installation_id: self.identity.installation_id,
                        };
                        if value.job_id != request.job_id
                            || value.peer_binding != expected_binding
                            || value.resolved_date_identifiers.is_empty()
                            || !accepted_dates_match(request, &value.resolved_date_identifiers)
                        {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = JobState::Accepted;
                        record.updated_at = Utc::now();
                        record.peer_binding = Some(value.peer_binding.clone());
                        record.total_days = Some(
                            i64::try_from(value.resolved_date_identifiers.len()).map_err(|_| {
                                ClientError::InvalidTransfer("too many dates".into())
                            })?,
                        );
                        record.message = Some("iPhone accepted the direct export.".into());
                        jobs.save(&record)?;
                        accepted = Some(value);
                    }
                    DirectMessage::TransferSession(Unlabeled { value }) => {
                        if value.partition_target_bytes != partition_target_bytes {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        receiver.prepare(
                            request.clone(),
                            accepted.clone().ok_or(ClientError::UnexpectedMessage)?,
                            value,
                        )?;
                    }
                    DirectMessage::RawDayManifest(Unlabeled { value }) => {
                        receiver.store_manifest(value)?;
                    }
                    DirectMessage::FileManifest(_) => {
                        return Err(ClientError::UnexpectedMessage);
                    }
                    DirectMessage::ExportProgress(Unlabeled { value }) => {
                        if value.job_id != request.job_id {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = if value.committed_partitions > 0 {
                            JobState::Transferring
                        } else {
                            JobState::Preparing
                        };
                        record.updated_at = Utc::now();
                        record.processed_days = value.processed_days;
                        record.total_days = Some(value.total_days);
                        record.committed_partitions = value.committed_partitions;
                        record.committed_bytes = value.committed_bytes;
                        record.message = Some(value.message);
                        jobs.save(&record)?;
                    }
                    DirectMessage::TransferOpen(Unlabeled { value }) => {
                        let disposition = receiver.disposition(value)?;
                        channel
                            .send(&DirectMessage::TransferDisposition(Unlabeled::from(
                                disposition,
                            )))
                            .await?;
                    }
                    DirectMessage::TransferPartitionComplete(Unlabeled { value }) => {
                        let acknowledgement = receiver.commit_partition(value)?;
                        channel
                            .send(&DirectMessage::TransferPartitionAcknowledgement(
                                Unlabeled::from(acknowledgement),
                            ))
                            .await?;
                    }
                    DirectMessage::TransferFinalize(Unlabeled { value }) => {
                        let artifact = receiver.finalize(&value)?;
                        let acknowledgement = RawReceiver::final_acknowledgement(&value, &artifact);
                        channel
                            .send(&DirectMessage::TransferFinalAcknowledgement(
                                Unlabeled::from(acknowledgement),
                            ))
                            .await?;
                        finalized = Some(artifact);
                    }
                    DirectMessage::CompletionConfirmed(payload)
                        if payload.job_id == request.job_id && finalized.is_some() =>
                    {
                        receiver.acknowledge_peer_completion(request.job_id.0)?;
                        return finalized.ok_or(ClientError::UnexpectedMessage);
                    }
                    DirectMessage::ExportRejected(Unlabeled { value }) => {
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = if value.reason == ExportFailureReason::Cancelled {
                            JobState::Cancelled
                        } else {
                            JobState::Failed
                        };
                        record.updated_at = Utc::now();
                        record.failure = Some(value.clone());
                        record.message = Some(value.message.clone());
                        jobs.save(&record)?;
                        return Err(ClientError::InvalidTransfer(value.message));
                    }
                    DirectMessage::Ping(Empty {}) => {
                        channel.send(&DirectMessage::Pong(Empty {})).await?;
                    }
                    DirectMessage::CancelAcknowledged(payload)
                        if payload.job_id == request.job_id =>
                    {
                        receiver.cancel(request.job_id.0)?;
                        jobs.clear_cancellation_request(request.job_id.0);
                        return Err(ClientError::Cancelled);
                    }
                    _ => {}
                },
            }
        }
    }

    #[allow(clippy::too_many_lines)]
    async fn process_android_export(
        &self,
        channel: &mut SecureChannel,
        request: &v2::ExportRequest,
        jobs: &V2JobStore,
        timeout: Duration,
    ) -> Result<V2ArtifactReceipt, ClientError> {
        let deadline = Instant::now() + timeout;
        let mut accepted: Option<v2::ExportAccepted> = None;
        let mut receiver = V2ArtifactReceiver::new(self.layout.clone(), jobs.clone());
        receiver.set_deadline(deadline.into_std());
        let mut cancellation_sent = false;
        let mut final_acknowledged =
            jobs.load(request.job_id)?.state == JobState::AwaitingPeerAcknowledgement;

        loop {
            if jobs.cancellation_requested(request.job_id) && !cancellation_sent {
                channel
                    .send_v2(&v2::Envelope::new(v2::Message::Cancel(v2::JobPayload {
                        job_id: request.job_id,
                    })))
                    .await?;
                cancellation_sent = true;
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            let receive_window = remaining.min(Duration::from_millis(250));
            let payload =
                match tokio::time::timeout(receive_window, channel.receive_v2_payload()).await {
                    Ok(result) => result?,
                    Err(_) => continue,
                };
            match payload {
                V2SecurePayload::BinaryTransferFrame(frame) => {
                    if final_acknowledged {
                        return Err(ClientError::UnexpectedMessage);
                    }
                    let acknowledgement = receiver.receive_binary_frame(&frame)?;
                    channel
                        .send_v2(&v2::Envelope::new(
                            v2::Message::TransferChunkAcknowledgement(acknowledgement),
                        ))
                        .await?;
                }
                V2SecurePayload::Message(envelope) => match envelope.message {
                    v2::Message::ExportAccepted(value) => {
                        if value.job_id != request.job_id
                            || value.product_id != request.product.product_id()
                            || !android_acceptance_matches(request, &value)
                            || value.peer_binding.source_installation_id
                                != request.source_installation_id
                            || value.peer_binding.destination_installation_id
                                != self.identity.installation_id.0
                            || value.request_fingerprint
                                != v2::request_fingerprint(request).map_err(|_| {
                                    ClientError::InvalidTransfer(
                                        "Android request fingerprint failed".into(),
                                    )
                                })?
                            || accepted.as_ref().is_some_and(|saved| saved != &value)
                        {
                            return Err(ClientError::InvalidTransfer(
                                "Android export acceptance changed".into(),
                            ));
                        }
                        accepted = Some(value);
                        let mut record = jobs.load(request.job_id)?;
                        if record.state != JobState::AwaitingPeerAcknowledgement {
                            record.state = JobState::Accepted;
                            record.updated_at = Utc::now();
                            record.message = Some("Android accepted the direct export.".into());
                            jobs.save(&record)?;
                        }
                    }
                    v2::Message::ExportProgress(value) if value.job_id == request.job_id => {
                        let mut record = jobs.load(request.job_id)?;
                        record.updated_at = Utc::now();
                        record.message = Some(value.message);
                        record.committed_bytes = record.committed_bytes.max(value.committed_bytes);
                        jobs.save(&record)?;
                    }
                    v2::Message::ExportRejected(value)
                        if value.job_id.is_none() || value.job_id == Some(request.job_id) =>
                    {
                        if final_acknowledged {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id)?;
                        record.state = if value.code == v2::ErrorCode::Cancelled {
                            JobState::Cancelled
                        } else {
                            JobState::Failed
                        };
                        record.updated_at = Utc::now();
                        record.message = Some(value.public_message.clone());
                        record.failure = Some(value.clone());
                        jobs.save(&record)?;
                        return if value.code == v2::ErrorCode::Cancelled {
                            Err(ClientError::Cancelled)
                        } else {
                            Err(ClientError::InvalidTransfer(value.public_message))
                        };
                    }
                    v2::Message::TransferSession(session) => {
                        let accepted = accepted.clone().ok_or(ClientError::UnexpectedMessage)?;
                        receiver.prepare(request.clone(), accepted, session)?;
                    }
                    v2::Message::ArtifactManifest(manifest) => {
                        receiver.store_manifest(manifest)?;
                    }
                    v2::Message::TransferOpen(open) => {
                        let disposition = receiver.disposition(open)?;
                        channel
                            .send_v2(&v2::Envelope::new(v2::Message::TransferDisposition(
                                disposition,
                            )))
                            .await?;
                    }
                    v2::Message::TransferPartitionComplete(complete) => {
                        if final_acknowledged {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let acknowledgement = receiver.commit_partition(&complete)?;
                        channel
                            .send_v2(&v2::Envelope::new(
                                v2::Message::TransferPartitionAcknowledgement(acknowledgement),
                            ))
                            .await?;
                    }
                    v2::Message::TransferFinalize(finalize) => {
                        let acknowledgement = receiver.finalize(&finalize)?;
                        channel
                            .send_v2(&v2::Envelope::new(
                                v2::Message::TransferFinalAcknowledgement(acknowledgement),
                            ))
                            .await?;
                        final_acknowledged = true;
                    }
                    v2::Message::CompletionConfirmed(payload)
                        if payload.job_id == request.job_id && final_acknowledged =>
                    {
                        receiver.acknowledge_completion(request.job_id)?;
                        jobs.clear_cancellation_request(request.job_id);
                        return receiver.receipt(request.job_id);
                    }
                    v2::Message::CancelAcknowledged(payload)
                        if payload.job_id == request.job_id && cancellation_sent =>
                    {
                        jobs.mark_cancelled(request.job_id)?;
                        return Err(ClientError::Cancelled);
                    }
                    v2::Message::Ping(v2::Empty {}) => {
                        channel
                            .send_v2(&v2::Envelope::new(v2::Message::Pong(v2::Empty {})))
                            .await?;
                    }
                    v2::Message::ExportProgress(_)
                    | v2::Message::ExportRejected(_)
                    | v2::Message::CompletionConfirmed(_)
                    | v2::Message::CancelAcknowledged(_)
                    | v2::Message::SourceHello(_)
                    | v2::Message::StatusRequest(_)
                    | v2::Message::StatusResponse(_)
                    | v2::Message::ExportRequest(_)
                    | v2::Message::TransferDisposition(_)
                    | v2::Message::TransferChunkAcknowledgement(_)
                    | v2::Message::TransferPartitionAcknowledgement(_)
                    | v2::Message::TransferFinalAcknowledgement(_)
                    | v2::Message::Cancel(_)
                    | v2::Message::Pong(v2::Empty {}) => {
                        return Err(ClientError::UnexpectedMessage);
                    }
                },
            }
        }
    }

    async fn load_trust(&self) -> Result<TrustState, ClientError> {
        self.trust_store.load(self.identity.installation_id).await
    }

    async fn remember_platform(
        &self,
        device_id: Uuid,
        platform: PeerPlatform,
    ) -> Result<(), ClientError> {
        let _lease = acquire_trust_lease(self.layout.clone()).await?;
        let mut state = self.load_trust().await?;
        if !state.set_client_platform(device_id, platform) {
            return Err(ClientError::DeviceNotPaired(device_id));
        }
        self.trust_store.save(&state).await
    }

    async fn selected_device_id(&self, requested: Option<Uuid>) -> Result<Uuid, ClientError> {
        let devices = self.paired_devices().await?;
        if let Some(id) = requested {
            return devices
                .iter()
                .any(|device| device.installation_id.0 == id)
                .then_some(id)
                .ok_or(ClientError::DeviceNotPaired(id));
        }
        match devices.as_slice() {
            [device] => Ok(device.installation_id.0),
            _ => Err(ClientError::DeviceSelectionRequired(
                devices
                    .iter()
                    .map(|device| device.installation_id.0)
                    .collect(),
            )),
        }
    }

    async fn accept_compatible(
        &self,
        listener: &TcpListener,
        pairing_codes: Option<(&str, &str)>,
        selected_device: Option<Uuid>,
        timeout: Duration,
    ) -> Result<AuthenticatedConnection, ClientError> {
        let deadline = Instant::now() + timeout;
        let mut last_error = ClientError::TimedOut;
        for _ in 0..MAXIMUM_AUTHENTICATION_ATTEMPTS {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            let (stream, _) = tokio::time::timeout(remaining, listener.accept())
                .await
                .map_err(|_| ClientError::TimedOut)?
                .map_err(connection_error)?;
            let authentication_remaining = deadline.saturating_duration_since(Instant::now());
            if authentication_remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            let lease = acquire_trust_lease(self.layout.clone()).await?;
            let attempt = tokio::time::timeout(
                authentication_remaining.min(Duration::from_secs(10)),
                authenticate(
                    PacketConnection::new(stream),
                    self.identity.installation_id,
                    &self.display_name,
                    pairing_codes,
                    &self.trust_store,
                ),
            )
            .await;
            drop(lease);
            match attempt {
                Ok(Ok(connection))
                    if (selected_device.is_none()
                        || selected_device == Some(connection.channel.peer_installation_id))
                        && connection.device.platform.is_none_or(|platform| {
                            pairing_protocol_matches_platform(
                                connection.pairing_protocol_version,
                                platform,
                            )
                        }) =>
                {
                    return Ok(connection);
                }
                Ok(Ok(connection))
                    if connection.device.platform.is_some_and(|platform| {
                        !pairing_protocol_matches_platform(
                            connection.pairing_protocol_version,
                            platform,
                        )
                    }) =>
                {
                    last_error = ClientError::Authentication(
                        "the source platform does not match its pairing protocol".into(),
                    );
                }
                Ok(Ok(connection)) => {
                    last_error = ClientError::Authentication(format!(
                        "a different paired source connected: {}",
                        connection.channel.peer_installation_id
                    ));
                }
                Ok(Err(error)) => last_error = error,
                Err(_) => last_error = ClientError::TimedOut,
            }
        }
        Err(last_error)
    }
}

async fn acquire_trust_lease(layout: StorageLayout) -> Result<TrustLease, ClientError> {
    tokio::task::spawn_blocking(move || {
        use fs2::FileExt as _;

        layout.prepare()?;
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(layout.root.join("trust.lock"))
            .map_err(connection_error)?;
        file.lock_exclusive().map_err(connection_error)?;
        Ok(TrustLease { _file: file })
    })
    .await
    .map_err(|error| ClientError::Connection(error.to_string()))?
}

async fn bind_listener(port: u16) -> Result<TcpListener, ClientError> {
    TcpListener::bind(("0.0.0.0", port))
        .await
        .map_err(connection_error)
}

async fn exchange_hello(
    channel: &mut SecureChannel,
    installation_id: SwiftUuid,
) -> Result<PeerCapabilities, ClientError> {
    let local = PeerCapabilities::portable_cli_all_versions(installation_id);
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(local)))
        .await?;
    match receive_message(channel, Duration::from_secs(10)).await? {
        DirectMessage::Hello(Unlabeled { value }) => Ok(value),
        _ => Err(ClientError::UnexpectedMessage),
    }
}

async fn receive_message(
    channel: &mut SecureChannel,
    timeout: Duration,
) -> Result<DirectMessage, ClientError> {
    match tokio::time::timeout(timeout, channel.receive())
        .await
        .map_err(|_| ClientError::TimedOut)??
    {
        SecurePayload::Message(message) => Ok(*message),
        SecurePayload::BinaryTransferFrame(_) => Err(ClientError::UnexpectedMessage),
    }
}

async fn receive_v2_message(
    channel: &mut SecureChannel,
    timeout: Duration,
) -> Result<v2::Envelope, ClientError> {
    tokio::time::timeout(timeout, channel.receive_v2())
        .await
        .map_err(|_| ClientError::TimedOut)?
}

async fn receive_android_source_hello(
    channel: &mut SecureChannel,
    expected_installation_id: Uuid,
) -> Result<v2::SourceHello, ClientError> {
    let envelope = receive_v2_message(channel, Duration::from_secs(10)).await?;
    let v2::Message::SourceHello(hello) = envelope.message else {
        return Err(ClientError::UnexpectedMessage);
    };
    if hello.source.platform != v2::SourcePlatform::Android
        || hello.source.installation_id != expected_installation_id
        || hello.products.is_empty()
        || !hello.products.iter().all(|product| product.supports_resume)
        || hello.limits.maximum_control_bytes == 0
        || hello.limits.maximum_control_bytes as usize > healthmd_protocol::MAXIMUM_PACKET_BYTES
        || hello.limits.maximum_chunk_bytes == 0
        || hello.limits.maximum_chunk_bytes as usize > healthmd_protocol::TRANSFER_FRAME_BYTES
    {
        return Err(ClientError::Authentication(
            "the connected Android source advertised invalid capabilities".into(),
        ));
    }
    Ok(hello)
}

const fn pairing_protocol_matches_platform(version: i32, platform: PeerPlatform) -> bool {
    matches!(
        (version, platform),
        (1, PeerPlatform::Ios) | (2, PeerPlatform::Android)
    )
}

const fn pairing_protocol_matches_source(version: i32, source: SourceKind) -> bool {
    matches!(
        (version, source),
        (1, SourceKind::Ios) | (2, SourceKind::Android)
    )
}

fn validate_source_peer(
    channel: &SecureChannel,
    peer: &PeerCapabilities,
) -> Result<(SourceKind, i32), ClientError> {
    if peer.installation_id.0 != channel.peer_installation_id {
        return Err(ClientError::Authentication(
            "the connected source identity changed during negotiation".into(),
        ));
    }
    match peer.platform {
        PeerPlatform::Ios
            if peer
                .protocol_versions
                .contains(&IOS_APPLICATION_PROTOCOL_VERSION) =>
        {
            Ok((SourceKind::Ios, IOS_APPLICATION_PROTOCOL_VERSION))
        }
        PeerPlatform::Android
            if peer
                .protocol_versions
                .contains(&ANDROID_APPLICATION_PROTOCOL_VERSION) =>
        {
            Ok((SourceKind::Android, ANDROID_APPLICATION_PROTOCOL_VERSION))
        }
        PeerPlatform::Ios | PeerPlatform::Android => Err(ClientError::Authentication(
            "the connected Health.md source has no compatible application protocol".into(),
        )),
        PeerPlatform::Cli => Err(ClientError::Authentication(
            "another CLI cannot act as a Health.md export source".into(),
        )),
    }
}

fn android_acceptance_matches(request: &v2::ExportRequest, accepted: &v2::ExportAccepted) -> bool {
    let dates_match = match &request.date_selection {
        v2::DateSelection::Exact {
            start_date,
            end_date,
        } => {
            accepted.resolved_range.start_date == *start_date
                && accepted.resolved_range.end_date == *end_date
        }
        v2::DateSelection::AllAvailable => {
            let start = NaiveDate::parse_from_str(&accepted.resolved_range.start_date, "%Y-%m-%d");
            let end = NaiveDate::parse_from_str(&accepted.resolved_range.end_date, "%Y-%m-%d");
            matches!((start, end), (Ok(start), Ok(end)) if start <= end)
        }
    };
    let product_metadata_matches = match &request.product {
        v2::ExportProduct::AndroidProviderNativeSnapshotV1 { provider_id, .. } => {
            accepted.provider_id.as_deref() == Some(provider_id)
                && accepted.settings_snapshot_sha256.is_none()
        }
        v2::ExportProduct::GeneratedFilesV1 { .. } => {
            accepted.provider_id.is_none()
                && accepted
                    .settings_snapshot_sha256
                    .as_deref()
                    .is_some_and(healthmd_protocol::transfer::is_sha256)
        }
        v2::ExportProduct::AndroidDailyRecordsV1 { .. } => false,
    };
    dates_match
        && product_metadata_matches
        && !accepted.resolved_range.time_zone_id.trim().is_empty()
}

fn validate_iphone_peer(
    channel: &SecureChannel,
    peer: &PeerCapabilities,
) -> Result<(), ClientError> {
    if validate_source_peer(channel, peer)? != (SourceKind::Ios, IOS_APPLICATION_PROTOCOL_VERSION) {
        return Err(ClientError::Authentication(
            "the selected source is not a compatible Health.md iPhone".into(),
        ));
    }
    Ok(())
}

fn ensure_job_execution_window(record: &JobRecord, timeout: Duration) -> Result<(), ClientError> {
    let timeout = chrono::Duration::from_std(timeout).map_err(|_| ClientError::JobExpired)?;
    if record.expires_at <= Utc::now() + timeout {
        return Err(ClientError::JobExpired);
    }
    Ok(())
}

fn allowed_after_finalize(message: &DirectMessage, job_id: SwiftUuid) -> bool {
    matches!(message, DirectMessage::Ping(Empty {}))
        || matches!(
            message,
            DirectMessage::CompletionConfirmed(payload) if payload.job_id == job_id
        )
        || matches!(
            message,
            DirectMessage::TransferFinalize(Unlabeled { value }) if value.job_id == job_id
        )
}

fn accepted_dates_match(request: &ExportRequest, accepted: &[String]) -> bool {
    let DateSelection::Exact(exact) = &request.date_selection else {
        return true;
    };
    let Ok(mut current) = NaiveDate::parse_from_str(&exact.start, "%Y-%m-%d") else {
        return false;
    };
    let Ok(end) = NaiveDate::parse_from_str(&exact.end, "%Y-%m-%d") else {
        return false;
    };
    if current > end {
        return false;
    }
    for identifier in accepted {
        if current > end || identifier != &current.format("%Y-%m-%d").to_string() {
            return false;
        }
        let Some(next) = current.succ_opt() else {
            return false;
        };
        current = next;
    }
    current > end
}

fn local_display_name() -> String {
    env::var("HOSTNAME")
        .or_else(|_| env::var("COMPUTERNAME"))
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "healthmd CLI".into())
}

#[allow(clippy::needless_pass_by_value)]
fn connection_error(error: std::io::Error) -> ClientError {
    ClientError::Connection(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pairing_protocol_cannot_downgrade_android_to_the_ios_code_path() {
        assert!(pairing_protocol_matches_source(1, SourceKind::Ios));
        assert!(pairing_protocol_matches_source(2, SourceKind::Android));
        assert!(!pairing_protocol_matches_source(1, SourceKind::Android));
        assert!(!pairing_protocol_matches_platform(1, PeerPlatform::Android));
    }
}
