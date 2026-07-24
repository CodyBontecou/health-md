use std::{env, fs, time::Duration};

use chrono::{NaiveDate, Utc};
use healthmd_protocol::{
    JOB_LIFETIME_SECONDS,
    encoding::SwiftUuid,
    models::{
        DateSelection, ExportFailureReason, ExportRequest, JobIdPayload, PeerBinding, ResponseMode,
    },
    transfer::{decode_binary_chunk, negotiate_transfer},
    wire::{
        DirectMessage, Empty, IphoneStatus, PeerCapabilities, PeerPlatform, StatusRequest,
        Unlabeled,
    },
};
use tokio::{net::TcpListener, time::Instant};
use uuid::Uuid;

use crate::{
    ClientError,
    credentials::OsCredentialStore,
    file_receiver::{FileExportReceipt, FileReceiver},
    handshake::{AuthenticatedConnection, authenticate},
    job::{JobRecord, JobState, JobStore},
    packet::PacketConnection,
    raw_receiver::{JsonlExtractionArtifact, RawReceiveArtifact, RawReceiver},
    secure_channel::{SecureChannel, SecurePayload},
    storage::{ClientIdentity, IdentityStore, StorageLayout},
    trust::{TrustState, TrustStore, TrustedClient},
};

const MAXIMUM_AUTHENTICATION_ATTEMPTS: usize = 8;

struct TrustLease {
    _file: fs::File,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PairingResult {
    pub device: TrustedClient,
    pub port: u16,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StatusResult {
    pub status: IphoneStatus,
    pub peer_capabilities: PeerCapabilities,
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

    /// List locally trusted iPhones without making a network connection.
    ///
    /// # Errors
    ///
    /// Returns an error when the operating system credential store is unavailable.
    pub async fn paired_devices(&self) -> Result<Vec<TrustedClient>, ClientError> {
        let mut devices = self.load_trust().await?.trusted_clients;
        devices.sort_by_cached_key(|device| device.display_name.to_lowercase());
        Ok(devices)
    }

    /// Remove local trust for one iPhone.
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

    /// Listen for and pair one foreground iPhone using a six-digit code.
    ///
    /// `on_listening` runs only after the port is bound, so callers can safely print connection
    /// instructions before waiting for iPhone.
    ///
    /// # Errors
    ///
    /// Returns an error for an invalid code/timeout, listener failure, timeout, authentication
    /// failure, incompatible iPhone, or unavailable secure storage.
    pub async fn pair<F>(
        &self,
        pairing_code: &str,
        port: u16,
        timeout: Duration,
        on_listening: F,
    ) -> Result<PairingResult, ClientError>
    where
        F: FnOnce(u16),
    {
        let normalized = crate::handshake::normalize_pairing_code(pairing_code);
        if normalized.len() != 6 {
            return Err(ClientError::Authentication(
                "the direct pairing code must contain six ASCII digits".into(),
            ));
        }
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        on_listening(bound_port);
        let mut connection = self
            .accept_compatible(&listener, Some(&normalized), None, timeout)
            .await?;
        let peer = exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
        validate_iphone_peer(&connection.channel, &peer)?;
        Ok(PairingResult {
            device: connection.device,
            port: bound_port,
        })
    }

    /// Connect to the selected paired foreground iPhone and request readiness.
    ///
    /// # Errors
    ///
    /// Returns an error for device selection, listener/timeout/authentication failure, or an
    /// incompatible/unexpected iPhone response.
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
        validate_iphone_peer(&connection.channel, &peer)?;
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
        Ok(StatusResult {
            status,
            peer_capabilities: peer,
            port: bound_port,
        })
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
    #[cfg_attr(windows, allow(unused_variables))]
    pub async fn export_files(
        &self,
        request: ExportRequest,
        device_id: Option<Uuid>,
        port: u16,
        timeout: Duration,
    ) -> Result<FileExportResult, ClientError> {
        if request.response_mode != ResponseMode::WriteFiles
            || request.raw_profile.is_some()
            || request.destination.is_none()
        {
            return Err(ClientError::InvalidTransfer(
                "generated-file request has incompatible response settings".into(),
            ));
        }
        #[cfg(windows)]
        return Err(ClientError::InvalidTransfer(
            "generated-file export requires the v2 logical destination contract on Windows; raw and extract are supported"
                .into(),
        ));
        #[cfg(not(windows))]
        {
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

    /// Read a durable direct job without contacting iPhone.
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
        if record.state.is_terminal() {
            return Ok(());
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

    async fn load_trust(&self) -> Result<TrustState, ClientError> {
        self.trust_store.load(self.identity.installation_id).await
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
        pairing_code: Option<&str>,
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
            let lease = acquire_trust_lease(self.layout.clone()).await?;
            let attempt = tokio::time::timeout(
                remaining.min(Duration::from_secs(10)),
                authenticate(
                    PacketConnection::new(stream),
                    self.identity.installation_id,
                    &self.display_name,
                    pairing_code,
                    &self.trust_store,
                ),
            )
            .await;
            drop(lease);
            match attempt {
                Ok(Ok(connection))
                    if selected_device.is_none()
                        || selected_device == Some(connection.channel.peer_installation_id) =>
                {
                    return Ok(connection);
                }
                Ok(Ok(connection)) => {
                    last_error = ClientError::Authentication(format!(
                        "a different paired iPhone connected: {}",
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
    let local = PeerCapabilities::portable_cli(installation_id);
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

fn validate_iphone_peer(
    channel: &SecureChannel,
    peer: &PeerCapabilities,
) -> Result<(), ClientError> {
    let local = PeerCapabilities::portable_cli(SwiftUuid(Uuid::nil()));
    if peer.platform != PeerPlatform::Ios
        || peer.installation_id.0 != channel.peer_installation_id
        || local.negotiated_protocol_version(peer).is_none()
    {
        return Err(ClientError::Authentication(
            "the connected peer is not a compatible Health.md iPhone".into(),
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
