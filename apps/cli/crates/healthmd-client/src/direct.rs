use std::{env, fs, io, time::Duration};

use chrono::{NaiveDate, Utc};
use healthmd_protocol::{
    ANDROID_APPLICATION_PROTOCOL_VERSION, IOS_APPLICATION_PROTOCOL_VERSION,
    IOS_QUERY_APPLICATION_PROTOCOL_VERSION, JOB_LIFETIME_SECONDS,
    encoding::SwiftUuid,
    models::{
        DateSelection, ExportFailure, ExportFailureReason, ExportRequest, JobIdPayload,
        PeerBinding, ResponseMode,
    },
    transfer::{decode_binary_chunk, negotiate_transfer},
    v2,
    wire::{
        DirectMessage, DirectQueryCapabilities, DirectQueryDetailLevel, DirectQueryRequest, Empty,
        IphoneStatus, PeerCapabilities, PeerPlatform, StatusRequest, Unlabeled,
    },
};
use tokio::{net::TcpListener, time::Instant};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    ClientError,
    credentials::OsCredentialStore,
    file_receiver::{FileExportReceipt, FileReceiver, GeneratedDestination},
    handshake::{AuthenticatedConnection, NewPairingPolicy, authenticate_with_policy},
    job::{JobRecord, JobState, JobStore},
    limits::{MAXIMUM_DATES_PER_JOB, MAXIMUM_JOB_BYTES, MAXIMUM_PARTITIONS_PER_JOB},
    packet::PacketConnection,
    raw_receiver::{JsonlExtractionArtifact, RawReceiveArtifact, RawReceiver},
    secure_channel::{SecureChannel, SecurePayload, V2SecurePayload},
    storage::{ClientIdentity, IdentityStore, StorageLayout},
    trust::{TrustState, TrustStore, TrustedClient},
    v2_job::{V2JobRecord, V2JobStore},
    v2_receiver::{V2ArtifactReceipt, V2ArtifactReceiver},
};

const MAXIMUM_AUTHENTICATION_ATTEMPTS: usize = 8;
const MAXIMUM_REQUEST_CLOCK_SKEW: chrono::Duration = chrono::Duration::minutes(5);
const WAKE_INITIAL_BACKOFF: Duration = Duration::from_millis(250);
const WAKE_MAXIMUM_BACKOFF: Duration = Duration::from_secs(2);
const WAKE_PROGRESS_INTERVAL: Duration = Duration::from_secs(10);

pub const DEFAULT_WAKE_TIMEOUT_SECONDS: u64 = 120;
pub const MAXIMUM_WAKE_TIMEOUT_SECONDS: u64 = 3_600;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct WakeWindow {
    timeout: Duration,
}

/// The RFC-0005 wake enrollment truth for one selected paired device.
///
/// [`WakeEnrollment::Enrolled`] means a stored wake credential exists for the selected device, so
/// a wait can fire the best-effort push nudge. [`WakeEnrollment::WaitOnly`] is the honest report
/// when no credential exists (or no single device is selected): waits degrade to P1 wait-only.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WakeEnrollment {
    /// A stored wake credential exists for the selected device (P2 push wake can fire).
    Enrolled,
    /// No stored credential exists for the selected device; waits stay wait-only (P1).
    WaitOnly,
}

impl WakeEnrollment {
    #[must_use]
    pub const fn state(self) -> &'static str {
        match self {
            Self::Enrolled => "available",
            Self::WaitOnly => "unavailable",
        }
    }

    #[must_use]
    pub const fn mode(self) -> &'static str {
        match self {
            Self::Enrolled => "enrolled",
            Self::WaitOnly => "wait_only",
        }
    }
}

impl WakeWindow {
    #[must_use]
    pub const fn from_seconds(timeout_seconds: u64) -> Self {
        Self {
            timeout: Duration::from_secs(timeout_seconds),
        }
    }

    #[must_use]
    pub const fn timeout(self) -> Duration {
        self.timeout
    }

    #[must_use]
    pub const fn timeout_seconds(self) -> u64 {
        self.timeout.as_secs()
    }

    #[must_use]
    pub const fn enabled(self) -> bool {
        !self.timeout.is_zero()
    }

    /// Serialize the shared wake-window status object with the enrollment truth for the
    /// selected device. This is the single implementation behind both the CLI `wake_window`
    /// object and the MCP `wake` object (RFC-0005 decision 2).
    #[must_use]
    pub fn status_value(self, enrollment: WakeEnrollment) -> serde_json::Value {
        serde_json::json!({
            "enabled": self.enabled(),
            "timeout_seconds": self.timeout_seconds(),
            "enrollment": {
                "state": enrollment.state(),
                "mode": enrollment.mode()
            }
        })
    }
}

impl Default for WakeWindow {
    fn default() -> Self {
        Self::from_seconds(DEFAULT_WAKE_TIMEOUT_SECONDS)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WakeProgress {
    pub elapsed_seconds: u64,
    pub timeout_seconds: u64,
    pub message: &'static str,
}

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

pub struct DirectClient<C = OsCredentialStore> {
    pub identity: ClientIdentity,
    pub layout: StorageLayout,
    display_name: String,
    trust_store: TrustStore<C>,
}

impl DirectClient<OsCredentialStore> {
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
}

impl<C: crate::credentials::CredentialStore> DirectClient<C> {
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
        legacy_apple_pairing_code: &str,
        shared_pairing_code: &str,
        port: u16,
        timeout: Duration,
        on_listening: F,
    ) -> Result<PairingResult, ClientError>
    where
        F: FnOnce(u16),
    {
        self.pair_expected_source(
            legacy_apple_pairing_code,
            shared_pairing_code,
            port,
            timeout,
            None,
            NewPairingPolicy::AllowAny,
            on_listening,
        )
        .await
    }

    /// Listen for and pair one foreground Health.md iPhone.
    ///
    /// A non-iOS peer is rejected and any newly written trust is removed before this returns.
    ///
    /// # Errors
    ///
    /// Returns the same bounded listener, authentication, compatibility, and storage errors as
    /// [`Self::pair`], plus an authentication error when the peer is not an iPhone.
    pub async fn pair_ios<F>(
        &self,
        legacy_apple_pairing_code: &str,
        shared_pairing_code: &str,
        port: u16,
        timeout: Duration,
        on_listening: F,
    ) -> Result<PairingResult, ClientError>
    where
        F: FnOnce(u16),
    {
        self.pair_expected_source(
            legacy_apple_pairing_code,
            shared_pairing_code,
            port,
            timeout,
            Some(SourceKind::Ios),
            NewPairingPolicy::AllowAny,
            on_listening,
        )
        .await
    }

    /// Listen for and onboard the first foreground Health.md iPhone.
    ///
    /// The cross-process trust lease atomically rejects a different new device if another process
    /// added trust after the caller's onboarding preflight.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::PairingConflict`] when code pairing would add a second trusted device,
    /// plus the bounded errors documented by [`Self::pair_ios`].
    pub async fn pair_first_ios<F>(
        &self,
        legacy_apple_pairing_code: &str,
        shared_pairing_code: &str,
        port: u16,
        timeout: Duration,
        on_listening: F,
    ) -> Result<PairingResult, ClientError>
    where
        F: FnOnce(u16),
    {
        self.pair_expected_source(
            legacy_apple_pairing_code,
            shared_pairing_code,
            port,
            timeout,
            Some(SourceKind::Ios),
            NewPairingPolicy::RequireNoOtherTrust,
            on_listening,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    async fn pair_expected_source<F>(
        &self,
        legacy_apple_pairing_code: &str,
        shared_pairing_code: &str,
        port: u16,
        timeout: Duration,
        expected_source: Option<SourceKind>,
        new_pairing_policy: NewPairingPolicy,
        on_listening: F,
    ) -> Result<PairingResult, ClientError>
    where
        F: FnOnce(u16),
    {
        let legacy_apple_code = crate::handshake::normalize_pairing_code(legacy_apple_pairing_code);
        let shared_code = crate::handshake::normalize_pairing_code(shared_pairing_code);
        if legacy_apple_code.len() != 6 || shared_code.len() != 20 {
            return Err(ClientError::Authentication(
                "shared pairing requires 20 digits; legacy Apple v1 requires 6 digits".into(),
            ));
        }
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        on_listening(bound_port);
        let mut connection = self
            .accept_compatible_with_policy(
                &listener,
                Some((&legacy_apple_code, &shared_code)),
                None,
                timeout,
                new_pairing_policy,
            )
            .await?;
        let device_id = connection.device.installation_id.0;
        let was_new_pairing = connection.was_new_pairing;
        let result = async {
            let (peer, wake_enrollment) =
                exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
            let (source, _) = validate_source_peer(&connection.channel, &peer)?;
            if expected_source.is_some_and(|expected| expected != source) {
                return Err(ClientError::Authentication(
                    "the paired source platform is not allowed by this operation".into(),
                ));
            }
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
            if let Some(enrollment) = wake_enrollment {
                self.store_wake_enrollment(device_id, enrollment).await?;
            }
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
        self.status_on_listener(&listener, selected, bound_port, timeout)
            .await
    }

    /// Wait for the selected authenticated mobile app to report that it is active.
    ///
    /// The listener remains bound for the complete bounded wake window. Unreachable peers and
    /// authenticated inactive statuses are retried with a 250 ms to 2 s backoff. A local waiter
    /// cancellation is distinct from phone-side durable-job cancellation.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::WaitCancelled`] on local cancellation, [`ClientError::TimedOut`] on
    /// wake-window expiry, or a non-retryable trust/authentication/protocol error.
    pub async fn wait_for_active_source<F>(
        &self,
        device_id: Option<Uuid>,
        port: u16,
        wake_window: WakeWindow,
        wake_request: bool,
        cancellation: &CancellationToken,
        mut on_progress: F,
    ) -> Result<(), ClientError>
    where
        F: FnMut(WakeProgress),
    {
        if !wake_window.enabled() {
            return Ok(());
        }
        let selected = self.selected_device_id(device_id).await?;
        if wake_request {
            // RFC-0005 P2: one best-effort nudge at wait start. Missing configuration, an
            // unreachable worker, or a rejected request degrades silently to the wait-only
            // window; the data path never depends on the worker.
            if let (Some(base_url), Ok(Some(credential))) = (
                crate::wake::worker_base_url(),
                self.wake_credential(selected).await,
            ) {
                let label = self.display_name.clone();
                let _ = crate::wake::request_wake(
                    &base_url,
                    &credential.wake_id,
                    &credential.wake_key,
                    &label,
                )
                .await;
            }
        }
        let source = self.selected_source(Some(selected)).await?;
        let waiting_message = match source.platform {
            Some(PeerPlatform::Android) => {
                "Waiting for Android; open Health.md or tap the wake notification."
            }
            _ => "Waiting for iPhone; open Health.md or tap the wake notification.",
        };
        let listener = bind_listener(port).await?;
        let bound_port = listener.local_addr().map_err(connection_error)?.port();
        let started = Instant::now();
        let deadline = started + wake_window.timeout();
        let mut backoff = WAKE_INITIAL_BACKOFF;
        let mut waiting_reported = false;
        let mut next_progress = WAKE_PROGRESS_INTERVAL;

        loop {
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            let attempt_timeout = remaining.min(backoff);
            let attempt_started = Instant::now();
            let attempt = tokio::select! {
                result = self.status_on_listener(
                    &listener,
                    selected,
                    bound_port,
                    attempt_timeout,
                ) => result,
                () = tokio::time::sleep(remaining) => return Err(ClientError::TimedOut),
                () = cancellation.cancelled() => return Err(ClientError::WaitCancelled),
            };
            match attempt {
                Ok(result) if source_status_is_active(&result.status) => return Ok(()),
                Ok(_) | Err(ClientError::TimedOut | ClientError::Connection(_)) => {}
                Err(error) => return Err(error),
            }

            let elapsed = started.elapsed();
            if waiting_reported {
                while elapsed >= next_progress {
                    on_progress(WakeProgress {
                        elapsed_seconds: elapsed.as_secs(),
                        timeout_seconds: wake_window.timeout_seconds(),
                        message: waiting_message,
                    });
                    next_progress += WAKE_PROGRESS_INTERVAL;
                }
            } else {
                waiting_reported = true;
                on_progress(WakeProgress {
                    elapsed_seconds: elapsed.as_secs(),
                    timeout_seconds: wake_window.timeout_seconds(),
                    message: waiting_message,
                });
                while elapsed >= next_progress {
                    next_progress += WAKE_PROGRESS_INTERVAL;
                }
            }

            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            let delay = attempt_timeout
                .saturating_sub(attempt_started.elapsed())
                .min(remaining);
            if !delay.is_zero() {
                tokio::select! {
                    () = tokio::time::sleep(delay) => {}
                    () = cancellation.cancelled() => return Err(ClientError::WaitCancelled),
                }
            }
            backoff = backoff.saturating_mul(2).min(WAKE_MAXIMUM_BACKOFF);
        }
    }

    async fn status_on_listener(
        &self,
        listener: &TcpListener,
        selected: Uuid,
        bound_port: u16,
        timeout: Duration,
    ) -> Result<StatusResult, ClientError> {
        let mut connection = self
            .accept_compatible(listener, None, Some(selected), timeout)
            .await?;
        let (peer, wake_enrollment) =
            exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
        let (source, application_protocol_version) =
            validate_source_peer(&connection.channel, &peer)?;
        self.remember_platform(selected, peer.platform).await?;
        if let Some(enrollment) = wake_enrollment {
            self.store_wake_enrollment(selected, enrollment).await?;
        }

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
                let DirectMessage::StatusResponse(Unlabeled { value: mut status }) =
                    receive_message(&mut connection.channel, Duration::from_secs(10)).await?
                else {
                    return Err(ClientError::UnexpectedMessage);
                };
                if status.name != connection.device.display_name
                    || !is_safe_peer_metadata(&status.name, 128)
                    || status
                        .message
                        .as_deref()
                        .is_some_and(|message| !is_safe_peer_message(message))
                {
                    return Err(ClientError::UnexpectedMessage);
                }
                status.message = Some("Authenticated iPhone readiness received.".into());
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
                let v2::Message::StatusResponse(mut status) = envelope.message else {
                    return Err(ClientError::UnexpectedMessage);
                };
                if status.source != capabilities.source
                    || status.available_products.len() > 32
                    || status
                        .message
                        .as_deref()
                        .is_some_and(|message| !is_safe_peer_message(message))
                {
                    return Err(ClientError::Authentication(
                        "the Android status source identity does not match the paired device"
                            .into(),
                    ));
                }
                status.message = Some("Authenticated Android readiness received.".into());
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
        mut request: DirectQueryRequest,
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
        let (peer, _wake_enrollment) =
            exchange_hello(&mut connection.channel, self.identity.installation_id).await?;
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
            || (operation == "source_record_listing"
                && (request.detail_level != DirectQueryDetailLevel::Lossless
                    || !capabilities.supports_evidence_values))
        {
            return Err(ClientError::QueryUnsupported);
        }
        let (max_items, max_bytes) = clamp_query_page(&mut request.query, capabilities)?;

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
                        || serde_json::to_vec(&value.response)
                            .map_err(|_| ClientError::MalformedPacket)?
                            .len()
                            > max_bytes
                        || !query_response_is_well_formed_and_bounded(&value.response, max_items)
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
                        || !is_safe_peer_code(&value.code)
                        || value.message.is_empty()
                        || value.message.len() > 512
                    {
                        return Err(ClientError::MalformedPacket);
                    }
                    return Err(ClientError::QueryRejected {
                        code: value.code,
                        message: "the iPhone rejected the bounded query".into(),
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
        validate_v2_job_time(request.created_at, request.expires_at)?;
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
        if overall_remaining.is_zero() {
            return Err(ClientError::TimedOut);
        }
        let result = async {
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), overall_remaining)
                .await?;
            let (peer, _wake_enrollment) =
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
        }
        .await;

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
                        paused.message = Some("Direct export paused before completion.".into());
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
        validate_v1_job_time(request.created_at)?;
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
            let (peer, _wake_enrollment) =
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
                        paused.message = Some("Direct export paused before completion.".into());
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
        validate_v1_job_time(request.created_at)?;
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
            let (peer, _wake_enrollment) =
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
                        paused.message = Some("Direct export paused before completion.".into());
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

    /// Durably record an explicit cancellation request for an Android job without opening a
    /// network listener. An already-running export process can observe and deliver this marker.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent, corrupt, pinned to another device, or terminal in
    /// a state other than already cancelled.
    pub fn request_android_job_cancellation(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
    ) -> Result<(), ClientError> {
        self.prepare_android_job_cancellation(job_id, device_id)
            .map(|_| ())
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
        let Some((jobs, selected)) = self.prepare_android_job_cancellation(job_id, device_id)?
        else {
            return Ok(());
        };
        let deadline = Instant::now() + timeout;
        let result = async {
            let listener = bind_listener(port).await?;
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), remaining)
                .await?;
            let (peer, _wake_enrollment) =
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
        }
        .await;
        result.map_err(|_| ClientError::CancellationPending(job_id))
    }

    /// Durably record an explicit cancellation request for an iPhone job without opening a
    /// network listener. An already-running export process can observe and deliver this marker.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent, corrupt, unbound, pinned to another device, or
    /// terminal in a state other than already cancelled.
    pub fn request_job_cancellation(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
    ) -> Result<(), ClientError> {
        self.prepare_job_cancellation(job_id, device_id).map(|_| ())
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
        let Some((jobs, selected)) = self.prepare_job_cancellation(job_id, device_id)? else {
            return Ok(());
        };
        let result = async {
            let listener = bind_listener(port).await?;
            let mut connection = self
                .accept_compatible(&listener, None, Some(selected), timeout)
                .await?;
            let (peer, _wake_enrollment) =
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

    fn prepare_android_job_cancellation(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
    ) -> Result<Option<(V2JobStore, Uuid)>, ClientError> {
        let jobs = V2JobStore::new(self.layout.clone())?;
        let mut record = jobs.load(job_id)?;
        if record.state == JobState::Cancelled {
            return Ok(None);
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
        Ok(Some((jobs, selected)))
    }

    fn prepare_job_cancellation(
        &self,
        job_id: Uuid,
        device_id: Option<Uuid>,
    ) -> Result<Option<(JobStore, Uuid)>, ClientError> {
        let jobs = JobStore::new(self.layout.clone())?;
        let mut record = jobs.load(job_id)?;
        if record.state == JobState::Cancelled {
            return Ok(None);
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
        Ok(Some((jobs, selected)))
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
                        if value.job_id != request.job_id || !valid_ios_progress(&value) {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        apply_ios_progress(&mut record, &value)?;
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
                        if value.job_id.is_some_and(|job_id| job_id != request.job_id)
                            || !is_safe_peer_message(&value.message)
                        {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = if value.reason == ExportFailureReason::Cancelled {
                            JobState::Cancelled
                        } else {
                            JobState::Failed
                        };
                        record.updated_at = Utc::now();
                        record.failure = Some(ExportFailure {
                            job_id: value.job_id,
                            reason: value.reason,
                            message: "The iPhone rejected the direct export.".into(),
                        });
                        record.message = Some("The iPhone rejected the direct export.".into());
                        jobs.save(&record)?;
                        return Err(ClientError::InvalidTransfer(
                            "the iPhone rejected the direct export".into(),
                        ));
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
                        if value.job_id != request.job_id || !valid_ios_progress(&value) {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        apply_ios_progress(&mut record, &value)?;
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
                        if value.job_id.is_some_and(|job_id| job_id != request.job_id)
                            || !is_safe_peer_message(&value.message)
                        {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id.0)?;
                        record.state = if value.reason == ExportFailureReason::Cancelled {
                            JobState::Cancelled
                        } else {
                            JobState::Failed
                        };
                        record.updated_at = Utc::now();
                        record.failure = Some(ExportFailure {
                            job_id: value.job_id,
                            reason: value.reason,
                            message: "The iPhone rejected the direct export.".into(),
                        });
                        record.message = Some("The iPhone rejected the direct export.".into());
                        jobs.save(&record)?;
                        return Err(ClientError::InvalidTransfer(
                            "the iPhone rejected the direct export".into(),
                        ));
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
                    v2::Message::ExportProgress(value) => {
                        if value.job_id != request.job_id || !valid_android_progress(&value) {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        let mut record = jobs.load(request.job_id)?;
                        record.updated_at = Utc::now();
                        record.message = Some("Android direct export is progressing.".into());
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
                        if !is_safe_peer_message(&value.public_message)
                            || value.details.len() > 64
                            || value.details.values().any(|values| values.len() > 64)
                        {
                            return Err(ClientError::UnexpectedMessage);
                        }
                        record.updated_at = Utc::now();
                        record.message = Some("Android rejected the direct export.".into());
                        record.failure = Some(v2::ExportFailure {
                            job_id: value.job_id,
                            code: value.code,
                            phase: value.phase,
                            retryable: value.retryable,
                            public_message: "Android rejected the direct export.".into(),
                            details: std::collections::BTreeMap::new(),
                        });
                        jobs.save(&record)?;
                        return if value.code == v2::ErrorCode::Cancelled {
                            Err(ClientError::Cancelled)
                        } else {
                            Err(ClientError::InvalidTransfer(
                                "Android rejected the direct export".into(),
                            ))
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
                    v2::Message::ExportRejected(_)
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

    /// The persisted RFC-0005 P2 wake credential for a paired device, if any. `None` means
    /// wait-only P1 behavior.
    ///
    /// # Errors
    ///
    /// Returns an error when native trust state cannot be read.
    pub async fn wake_credential(
        &self,
        device_id: Uuid,
    ) -> Result<Option<crate::trust::TrustedWakeCredential>, ClientError> {
        Ok(self
            .load_trust()
            .await?
            .client(device_id)
            .and_then(|client| client.wake.clone()))
    }

    /// The shared wake-window status object with enrollment reported truthfully per device.
    ///
    /// The selected device is resolved exactly as the wake wait resolves it, and a stored wake
    /// credential for that device reports [`WakeEnrollment::Enrolled`]. Without a resolvable
    /// selection or a stored credential — including nothing paired at all — the honest report is
    /// [`WakeEnrollment::WaitOnly`], matching what the wake wait would actually do.
    pub async fn wake_status_value(
        &self,
        requested: Option<Uuid>,
        window: WakeWindow,
    ) -> serde_json::Value {
        let enrolled = match self.selected_device_id(requested).await {
            Ok(device) => matches!(self.wake_credential(device).await, Ok(Some(_))),
            Err(_) => false,
        };
        window.status_value(if enrolled {
            WakeEnrollment::Enrolled
        } else {
            WakeEnrollment::WaitOnly
        })
    }

    /// Persist a wake enrollment from a paired phone under its existing trust binding. A later
    /// enrollment replaces the stored material (rotation); unpairing removes it with the trust
    /// entry.
    async fn store_wake_enrollment(
        &self,
        device_id: Uuid,
        enrollment: healthmd_protocol::wire::WakeEnrollment,
    ) -> Result<(), ClientError> {
        if !enrollment.is_valid() {
            return Err(ClientError::UnexpectedMessage);
        }
        let wake_key = crate::wake::decode_wake_key(&enrollment.wake_key)
            .ok_or(ClientError::UnexpectedMessage)?;
        let _lease = acquire_trust_lease(self.layout.clone()).await?;
        let mut state = self.load_trust().await?;
        let now = Utc::now();
        let client = state
            .trusted_clients
            .iter_mut()
            .find(|client| client.installation_id.0 == device_id)
            .ok_or(ClientError::DeviceNotPaired(device_id))?;
        client.wake = Some(crate::trust::TrustedWakeCredential {
            wake_id: enrollment.wake_id,
            wake_key,
            enrolled_at: now,
        });
        self.trust_store.save(&state).await
    }

    async fn remember_platform(
        &self,
        device_id: Uuid,
        platform: PeerPlatform,
    ) -> Result<(), ClientError> {
        let _lease = acquire_trust_lease(self.layout.clone()).await?;
        let mut state = self.load_trust().await?;
        if state.client(device_id).and_then(|client| client.platform) == Some(platform) {
            return Ok(());
        }
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
        self.accept_compatible_with_policy(
            listener,
            pairing_codes,
            selected_device,
            timeout,
            NewPairingPolicy::AllowAny,
        )
        .await
    }

    async fn accept_compatible_with_policy(
        &self,
        listener: &TcpListener,
        pairing_codes: Option<(&str, &str)>,
        selected_device: Option<Uuid>,
        timeout: Duration,
        new_pairing_policy: NewPairingPolicy,
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
            let lease = acquire_trust_lease_until(self.layout.clone(), deadline).await?;
            let authentication_remaining = deadline.saturating_duration_since(Instant::now());
            if authentication_remaining.is_zero() {
                return Err(ClientError::TimedOut);
            }
            let attempt = authenticate_with_policy(
                PacketConnection::new(stream),
                self.identity.installation_id,
                &self.display_name,
                pairing_codes,
                &self.trust_store,
                authentication_remaining.min(Duration::from_secs(10)),
                new_pairing_policy,
            )
            .await;
            drop(lease);
            match attempt {
                Ok(connection)
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
                Ok(connection)
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
                Ok(connection) => {
                    last_error = ClientError::Authentication(format!(
                        "a different paired source connected: {}",
                        connection.channel.peer_installation_id
                    ));
                }
                Err(ClientError::CredentialMutationOutcomeUnknown) => {
                    return Err(ClientError::CredentialMutationOutcomeUnknown);
                }
                Err(ClientError::PairingConflict) => return Err(ClientError::PairingConflict),
                Err(error) => last_error = error,
            }
        }
        Err(last_error)
    }
}

const fn source_status_is_active(status: &SourceStatus) -> bool {
    match status {
        SourceStatus::Ios(status) => status.app_active,
        SourceStatus::Android(status) => status.app_active,
    }
}

async fn acquire_trust_lease(layout: StorageLayout) -> Result<TrustLease, ClientError> {
    acquire_trust_lease_until(layout, Instant::now() + Duration::from_secs(10)).await
}

async fn acquire_trust_lease_until(
    layout: StorageLayout,
    deadline: Instant,
) -> Result<TrustLease, ClientError> {
    let deadline = deadline.into_std();
    tokio::task::spawn_blocking(move || {
        use fs2::FileExt as _;

        const TRUST_LEASE_RETRY_DELAY: Duration = Duration::from_millis(25);

        layout.prepare()?;
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(layout.root.join("trust.lock"))
            .map_err(connection_error)?;
        loop {
            match file.try_lock_exclusive() {
                Ok(()) => return Ok(TrustLease { _file: file }),
                Err(error)
                    if error.kind() == io::ErrorKind::WouldBlock
                        && std::time::Instant::now() < deadline =>
                {
                    let remaining = deadline.saturating_duration_since(std::time::Instant::now());
                    std::thread::sleep(TRUST_LEASE_RETRY_DELAY.min(remaining));
                }
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    return Err(ClientError::TimedOut);
                }
                Err(error) => return Err(connection_error(error)),
            }
        }
    })
    .await
    .map_err(|_| ClientError::CredentialStore("the direct trust lease failed".into()))?
}

async fn bind_listener(port: u16) -> Result<TcpListener, ClientError> {
    TcpListener::bind(("0.0.0.0", port))
        .await
        .map_err(connection_error)
}

async fn exchange_hello(
    channel: &mut SecureChannel,
    installation_id: SwiftUuid,
) -> Result<
    (
        PeerCapabilities,
        Option<healthmd_protocol::wire::WakeEnrollment>,
    ),
    ClientError,
> {
    let local = PeerCapabilities::portable_cli_all_versions(installation_id);
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(local)))
        .await?;
    let DirectMessage::Hello(Unlabeled { value: peer }) =
        receive_message(channel, Duration::from_secs(10)).await?
    else {
        return Err(ClientError::UnexpectedMessage);
    };
    // RFC-0005 P2: a phone that advertised wake support sends exactly one enrollment as the very
    // next message; a phone that did not advertise must never send one, so any stray enrollment
    // later in a stream fails closed as an unexpected message.
    let enrollment =
        if peer.wake == Some(healthmd_protocol::wire::WakeCapabilities { supported: true }) {
            match receive_message(channel, Duration::from_secs(10)).await? {
                DirectMessage::WakeEnrollment(Unlabeled { value }) => Some(value),
                _ => return Err(ClientError::UnexpectedMessage),
            }
        } else {
            None
        };
    Ok((peer, enrollment))
}

async fn receive_message(
    channel: &mut SecureChannel,
    timeout: Duration,
) -> Result<DirectMessage, ClientError> {
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Err(ClientError::TimedOut);
        }
        match tokio::time::timeout(remaining, channel.receive())
            .await
            .map_err(|_| ClientError::TimedOut)??
        {
            SecurePayload::Message(message) => match *message {
                DirectMessage::Ping(Empty {}) => {
                    let remaining = deadline.saturating_duration_since(Instant::now());
                    if remaining.is_zero() {
                        return Err(ClientError::TimedOut);
                    }
                    tokio::time::timeout(remaining, channel.send(&DirectMessage::Pong(Empty {})))
                        .await
                        .map_err(|_| ClientError::TimedOut)??;
                }
                message => return Ok(message),
            },
            SecurePayload::BinaryTransferFrame(_) => {
                return Err(ClientError::UnexpectedMessage);
            }
        }
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
        || !is_safe_peer_metadata(&hello.source.display_name, 128)
        || !is_safe_peer_metadata(&hello.source.app_version, 64)
        || hello.products.is_empty()
        || hello.products.len() > 32
        || !hello.products.iter().all(|product| {
            product.supports_resume
                && is_safe_peer_metadata(&product.artifact_schema.id, 128)
                && product.formats.len() <= 16
                && product.providers.len() <= 64
                && product
                    .providers
                    .iter()
                    .all(|provider| is_safe_peer_code(provider))
                && product.settings_policies.len() <= 16
        })
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
        (1, PeerPlatform::Ios)
            | (2, PeerPlatform::Android)
            | (3, PeerPlatform::Ios | PeerPlatform::Android)
    )
}

const fn pairing_protocol_matches_source(version: i32, source: SourceKind) -> bool {
    matches!(
        (version, source),
        (1, SourceKind::Ios)
            | (2, SourceKind::Android)
            | (3, SourceKind::Ios | SourceKind::Android)
    )
}

fn clamp_query_page(
    query: &mut serde_json::Value,
    peer: &DirectQueryCapabilities,
) -> Result<(usize, usize), ClientError> {
    let requested_items = query
        .pointer("/page/max_items")
        .and_then(serde_json::Value::as_u64)
        .ok_or(ClientError::QueryUnsupported)?;
    let requested_bytes = query
        .pointer("/page/max_bytes")
        .and_then(serde_json::Value::as_u64)
        .ok_or(ClientError::QueryUnsupported)?;
    if requested_items == 0 || requested_bytes == 0 {
        return Err(ClientError::QueryUnsupported);
    }
    let local = DirectQueryCapabilities::current();
    let peer_items =
        u64::try_from(peer.maximum_page_items).map_err(|_| ClientError::QueryUnsupported)?;
    let peer_bytes =
        u64::try_from(peer.maximum_page_bytes).map_err(|_| ClientError::QueryUnsupported)?;
    let local_items =
        u64::try_from(local.maximum_page_items).map_err(|_| ClientError::QueryUnsupported)?;
    let local_bytes =
        u64::try_from(local.maximum_page_bytes).map_err(|_| ClientError::QueryUnsupported)?;
    let effective_items = requested_items.min(peer_items).min(local_items);
    let effective_bytes = requested_bytes.min(peer_bytes).min(local_bytes);
    if effective_items == 0 || effective_bytes == 0 {
        return Err(ClientError::QueryUnsupported);
    }
    let page = query
        .pointer_mut("/page")
        .and_then(serde_json::Value::as_object_mut)
        .ok_or(ClientError::QueryUnsupported)?;
    page.insert("max_items".into(), serde_json::json!(effective_items));
    page.insert("max_bytes".into(), serde_json::json!(effective_bytes));
    Ok((
        usize::try_from(effective_items).map_err(|_| ClientError::QueryUnsupported)?,
        usize::try_from(effective_bytes).map_err(|_| ClientError::QueryUnsupported)?,
    ))
}

fn query_response_is_well_formed_and_bounded(response: &serde_json::Value, maximum: usize) -> bool {
    let Some(object) = response.as_object() else {
        return false;
    };
    let allowed = [
        "schema",
        "schema_version",
        "items",
        "packet",
        "coverage",
        "sources",
        "evidence",
        "next_cursor",
        "limitations",
        "metadata",
    ];
    if object.keys().any(|key| !allowed.contains(&key.as_str()))
        || object.get("schema").and_then(serde_json::Value::as_str)
            != Some("healthmd.query_response")
        || object
            .get("schema_version")
            .and_then(serde_json::Value::as_i64)
            != Some(1)
    {
        return false;
    }
    let Some(items) = object.get("items").and_then(serde_json::Value::as_array) else {
        return false;
    };
    if !items.iter().all(query_item_is_well_formed)
        || !query_coverage_is_well_formed(object.get("coverage"))
        || !query_array_is_well_formed(object.get("sources"), Some(64), query_source_is_well_formed)
        || !query_array_is_well_formed(
            object.get("evidence"),
            None,
            query_evidence_reference_is_well_formed,
        )
        || !query_array_is_well_formed(
            object.get("limitations"),
            Some(64),
            query_limitation_is_well_formed,
        )
        || object
            .get("next_cursor")
            .is_some_and(|value| !value.is_null() && !value.is_string())
        || object
            .get("metadata")
            .is_some_and(|value| !value.is_null() && !value.is_object())
    {
        return false;
    }
    let packet_facts = match object.get("packet") {
        None | Some(serde_json::Value::Null) => 0,
        Some(packet) => {
            let Some(count) = query_packet_fact_count(packet, items.is_empty()) else {
                return false;
            };
            count
        }
    };
    items
        .len()
        .checked_add(packet_facts)
        .is_some_and(|count| count <= maximum)
}

fn query_packet_fact_count(packet: &serde_json::Value, items_are_empty: bool) -> Option<usize> {
    let packet = packet.as_object()?;
    let allowed = [
        "schema",
        "schema_version",
        "packet_id",
        "kind",
        "range",
        "facts",
        "coverage",
        "sources",
        "limitations",
        "metadata",
    ];
    if !items_are_empty
        || packet.keys().any(|key| !allowed.contains(&key.as_str()))
        || packet.get("schema").and_then(serde_json::Value::as_str)
            != Some("healthmd.evidence_packet")
        || packet
            .get("schema_version")
            .and_then(serde_json::Value::as_i64)
            != Some(1)
        || packet
            .get("packet_id")
            .and_then(serde_json::Value::as_str)
            .is_none_or(str::is_empty)
        || packet
            .get("kind")
            .and_then(serde_json::Value::as_str)
            .is_none_or(|value| !matches!(value, "daily_wellness" | "training" | "doctor_visit"))
        || packet
            .get("range")
            .is_some_and(|value| !value.is_null() && !query_date_range_is_well_formed(value))
        || !query_coverage_is_well_formed(packet.get("coverage"))
        || !query_array_is_well_formed(packet.get("sources"), Some(64), query_source_is_well_formed)
        || !query_array_is_well_formed(
            packet.get("limitations"),
            Some(64),
            query_limitation_is_well_formed,
        )
        || !packet
            .get("metadata")
            .is_some_and(query_packet_metadata_is_well_formed)
    {
        return None;
    }
    let facts = packet.get("facts").and_then(serde_json::Value::as_array)?;
    facts
        .iter()
        .all(query_packet_fact_is_well_formed)
        .then_some(facts.len())
}

fn query_array_is_well_formed(
    value: Option<&serde_json::Value>,
    maximum: Option<usize>,
    validator: fn(&serde_json::Value) -> bool,
) -> bool {
    let Some(values) = value.and_then(serde_json::Value::as_array) else {
        return false;
    };
    maximum.is_none_or(|maximum| values.len() <= maximum) && values.iter().all(validator)
}

fn query_object_with_keys<'a>(
    value: &'a serde_json::Value,
    allowed: &[&str],
    required: &[&str],
) -> Option<&'a serde_json::Map<String, serde_json::Value>> {
    let object = value.as_object()?;
    (object.keys().all(|key| allowed.contains(&key.as_str()))
        && required.iter().all(|key| object.contains_key(*key)))
    .then_some(object)
}

fn query_nonempty_string(object: &serde_json::Map<String, serde_json::Value>, key: &str) -> bool {
    object
        .get(key)
        .and_then(serde_json::Value::as_str)
        .is_some_and(|value| !value.is_empty())
}

fn query_string_array(value: Option<&serde_json::Value>) -> bool {
    value
        .and_then(serde_json::Value::as_array)
        .is_some_and(|values| {
            values
                .iter()
                .all(|value| value.as_str().is_some_and(|value| !value.is_empty()))
        })
}

fn query_status_is_well_formed(value: Option<&serde_json::Value>) -> bool {
    value
        .and_then(serde_json::Value::as_str)
        .is_some_and(|value| {
            matches!(
                value,
                "available"
                    | "complete_empty"
                    | "partial"
                    | "failed"
                    | "unsupported"
                    | "skipped"
                    | "cancelled"
                    | "not_requested"
                    | "legacy_unavailable"
                    | "redacted"
                    | "not_synchronized"
            )
        })
}

fn query_date_range_is_well_formed(value: &serde_json::Value) -> bool {
    query_object_with_keys(
        value,
        &["start_date", "end_date"],
        &["start_date", "end_date"],
    )
    .is_some_and(|object| {
        query_nonempty_string(object, "start_date") && query_nonempty_string(object, "end_date")
    })
}

fn query_source_is_well_formed(value: &serde_json::Value) -> bool {
    query_object_with_keys(
        value,
        &["schema", "schema_version", "digest"],
        &["schema", "schema_version", "digest"],
    )
    .is_some_and(|object| {
        query_nonempty_string(object, "schema")
            && object
                .get("schema_version")
                .and_then(serde_json::Value::as_u64)
                .is_some()
            && object
                .get("digest")
                .and_then(serde_json::Value::as_str)
                .is_some_and(|digest| {
                    digest.len() == 64 && digest.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
    })
}

fn query_limitation_is_well_formed(value: &serde_json::Value) -> bool {
    query_object_with_keys(value, &["code", "message"], &["code", "message"]).is_some_and(
        |object| {
            query_nonempty_string(object, "code")
                && query_nonempty_string(object, "message")
                && object["code"]
                    .as_str()
                    .is_some_and(|value| value.len() <= 128)
                && object["message"]
                    .as_str()
                    .is_some_and(|value| value.len() <= 512)
        },
    )
}

fn query_evidence_locator_is_well_formed(value: &serde_json::Value) -> bool {
    let Some(object) = value.as_object() else {
        return false;
    };
    let Some(kind) = object.get("type").and_then(serde_json::Value::as_str) else {
        return false;
    };
    let detail = match kind {
        "summary_key" => "key",
        "canonical_uuid" => "uuid",
        "external_identity" | "query_manifest" | "partial_failure" => "identifier",
        "warning" => "code",
        _ => return false,
    };
    let allowed = ["type", "owner_date", detail];
    object.keys().all(|key| allowed.contains(&key.as_str()))
        && query_nonempty_string(object, "owner_date")
        && query_nonempty_string(object, detail)
}

fn query_evidence_reference_is_well_formed(value: &serde_json::Value) -> bool {
    let Some(object) = query_object_with_keys(
        value,
        &[
            "evidence_id",
            "locator",
            "source",
            "source_id",
            "provider_id",
        ],
        &["evidence_id", "locator", "source", "source_id"],
    ) else {
        return false;
    };
    query_nonempty_string(object, "evidence_id")
        && query_nonempty_string(object, "source_id")
        && object
            .get("provider_id")
            .is_none_or(|value| value.as_str().is_some_and(|value| !value.is_empty()))
        && object
            .get("locator")
            .is_some_and(query_evidence_locator_is_well_formed)
        && object
            .get("source")
            .is_some_and(query_source_is_well_formed)
}

fn query_missing_interval_is_well_formed(value: &serde_json::Value) -> bool {
    let Some(object) =
        query_object_with_keys(value, &["range", "status", "reason"], &["range", "status"])
    else {
        return false;
    };
    object
        .get("range")
        .is_some_and(query_date_range_is_well_formed)
        && query_status_is_well_formed(object.get("status"))
        && object
            .get("reason")
            .is_none_or(|value| value.as_str().is_some())
}

fn query_coverage_is_well_formed(value: Option<&serde_json::Value>) -> bool {
    let Some(value) = value else { return false };
    let allowed = [
        "requested_range",
        "available_range",
        "status",
        "days_considered",
        "days_with_values",
        "missing",
        "missing_interval_count",
        "missing_truncated",
    ];
    let Some(coverage) = query_object_with_keys(
        value,
        &allowed,
        &["status", "days_considered", "days_with_values", "missing"],
    ) else {
        return false;
    };
    let Some(days_considered) = coverage
        .get("days_considered")
        .and_then(serde_json::Value::as_u64)
    else {
        return false;
    };
    let Some(days_with_values) = coverage
        .get("days_with_values")
        .and_then(serde_json::Value::as_u64)
    else {
        return false;
    };
    query_status_is_well_formed(coverage.get("status"))
        && days_with_values <= days_considered
        && query_array_is_well_formed(
            coverage.get("missing"),
            Some(64),
            query_missing_interval_is_well_formed,
        )
        && coverage
            .get("requested_range")
            .is_none_or(|value| value.is_null() || query_date_range_is_well_formed(value))
        && coverage
            .get("available_range")
            .is_none_or(|value| value.is_null() || query_date_range_is_well_formed(value))
        && coverage
            .get("missing_interval_count")
            .is_none_or(|value| value.as_u64().is_some())
        && coverage
            .get("missing_truncated")
            .is_none_or(serde_json::Value::is_boolean)
}

fn query_value_is_well_formed(value: &serde_json::Value) -> bool {
    query_value_is_well_formed_at_depth(value, 0)
}

fn query_value_is_well_formed_at_depth(value: &serde_json::Value, depth: usize) -> bool {
    if depth > 64 {
        return false;
    }
    let Some(object) = value.as_object() else {
        return false;
    };
    let Some(kind) = object.get("type").and_then(serde_json::Value::as_str) else {
        return false;
    };
    let valid = match kind {
        "quantity" => {
            object
                .get("value")
                .and_then(serde_json::Value::as_f64)
                .is_some()
                && query_nonempty_string(object, "unit")
        }
        "duration" => object
            .get("seconds")
            .and_then(serde_json::Value::as_f64)
            .is_some(),
        "count" => object
            .get("value")
            .and_then(serde_json::Value::as_i64)
            .is_some(),
        "string" | "timestamp" | "date" => object
            .get("value")
            .and_then(serde_json::Value::as_str)
            .is_some(),
        "boolean" => object
            .get("value")
            .and_then(serde_json::Value::as_bool)
            .is_some(),
        "category" => {
            query_nonempty_string(object, "identifier")
                && object
                    .get("display")
                    .is_none_or(|value| value.as_str().is_some())
                && object
                    .get("raw_value")
                    .is_none_or(|value| value.as_i64().is_some())
        }
        "array" => object
            .get("value")
            .and_then(serde_json::Value::as_array)
            .is_some_and(|values| {
                values
                    .iter()
                    .all(|value| query_value_is_well_formed_at_depth(value, depth + 1))
            }),
        _ => !kind.is_empty(),
    };
    if !valid {
        return false;
    }
    let allowed: &[&str] = match kind {
        "quantity" => &["type", "value", "unit"],
        "duration" => &["type", "seconds"],
        "category" => &["type", "identifier", "display", "raw_value"],
        _ => &["type", "value"],
    };
    object.keys().all(|key| allowed.contains(&key.as_str()))
}

fn query_metric_item_is_well_formed(value: &serde_json::Value) -> bool {
    let allowed = [
        "metric_id",
        "display_name",
        "owner_date",
        "value",
        "status",
        "evidence",
        "limitations",
    ];
    let required = [
        "metric_id",
        "display_name",
        "owner_date",
        "status",
        "evidence",
        "limitations",
    ];
    let Some(object) = query_object_with_keys(value, &allowed, &required) else {
        return false;
    };
    query_nonempty_string(object, "metric_id")
        && query_nonempty_string(object, "display_name")
        && query_nonempty_string(object, "owner_date")
        && query_status_is_well_formed(object.get("status"))
        && object
            .get("value")
            .is_none_or(|value| value.is_null() || query_value_is_well_formed(value))
        && query_array_is_well_formed(
            object.get("evidence"),
            None,
            query_evidence_reference_is_well_formed,
        )
        && query_array_is_well_formed(
            object.get("limitations"),
            Some(64),
            query_limitation_is_well_formed,
        )
}

fn query_aggregation_is_well_formed(value: &serde_json::Value) -> bool {
    query_object_with_keys(
        value,
        &["metric_id", "kind", "expected_unit"],
        &["metric_id", "kind"],
    )
    .is_some_and(|object| {
        query_nonempty_string(object, "metric_id")
            && object
                .get("kind")
                .and_then(serde_json::Value::as_str)
                .is_some_and(|kind| {
                    matches!(
                        kind,
                        "sum"
                            | "average"
                            | "minimum"
                            | "maximum"
                            | "latest"
                            | "count"
                            | "duration_sum"
                    )
                })
            && object
                .get("expected_unit")
                .is_none_or(|value| value.as_str().is_some())
    })
}

fn query_comparison_item_is_well_formed(value: &serde_json::Value) -> bool {
    let allowed = [
        "metric_id",
        "aggregation",
        "first_range",
        "second_range",
        "first_value",
        "second_value",
        "absolute_change",
        "percent_change",
        "direction",
        "coverage",
        "evidence",
        "limitations",
    ];
    let required = [
        "metric_id",
        "aggregation",
        "first_range",
        "second_range",
        "direction",
        "coverage",
        "evidence",
        "limitations",
    ];
    let Some(object) = query_object_with_keys(value, &allowed, &required) else {
        return false;
    };
    query_nonempty_string(object, "metric_id")
        && object
            .get("aggregation")
            .is_some_and(query_aggregation_is_well_formed)
        && object
            .get("first_range")
            .is_some_and(query_date_range_is_well_formed)
        && object
            .get("second_range")
            .is_some_and(query_date_range_is_well_formed)
        && object
            .get("direction")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|value| {
                matches!(
                    value,
                    "increased" | "decreased" | "unchanged" | "not_comparable"
                )
            })
        && query_coverage_is_well_formed(object.get("coverage"))
        && ["first_value", "second_value", "absolute_change"]
            .iter()
            .all(|key| {
                object
                    .get(*key)
                    .is_none_or(|value| value.is_null() || query_value_is_well_formed(value))
            })
        && object
            .get("percent_change")
            .is_none_or(|value| value.is_null() || value.as_f64().is_some())
        && query_array_is_well_formed(
            object.get("evidence"),
            None,
            query_evidence_reference_is_well_formed,
        )
        && query_array_is_well_formed(
            object.get("limitations"),
            Some(64),
            query_limitation_is_well_formed,
        )
}

fn query_workout_is_well_formed(value: &serde_json::Value) -> bool {
    let allowed = [
        "workout_id",
        "activity",
        "start",
        "end",
        "details",
        "evidence_ids",
    ];
    let Some(object) = query_object_with_keys(value, &allowed, &allowed) else {
        return false;
    };
    query_nonempty_string(object, "workout_id")
        && query_nonempty_string(object, "activity")
        && query_nonempty_string(object, "start")
        && query_nonempty_string(object, "end")
        && object
            .get("details")
            .and_then(serde_json::Value::as_object)
            .is_some_and(|details| details.values().all(query_value_is_well_formed))
        && query_string_array(object.get("evidence_ids"))
}

fn query_sleep_physiology_is_well_formed(value: &serde_json::Value) -> bool {
    let allowed = [
        "metric_id",
        "status",
        "sample_count",
        "first_sample_at",
        "last_sample_at",
        "observed_owner_dates",
        "evidence",
    ];
    let required = [
        "metric_id",
        "status",
        "sample_count",
        "observed_owner_dates",
        "evidence",
    ];
    let Some(object) = query_object_with_keys(value, &allowed, &required) else {
        return false;
    };
    query_nonempty_string(object, "metric_id")
        && query_status_is_well_formed(object.get("status"))
        && object
            .get("sample_count")
            .and_then(serde_json::Value::as_u64)
            .is_some()
        && ["first_sample_at", "last_sample_at"].iter().all(|key| {
            object
                .get(*key)
                .is_none_or(|value| value.is_null() || value.is_string())
        })
        && query_string_array(object.get("observed_owner_dates"))
        && query_array_is_well_formed(
            object.get("evidence"),
            None,
            query_evidence_reference_is_well_formed,
        )
}

fn query_sleep_window_is_well_formed(value: &serde_json::Value) -> bool {
    query_object_with_keys(
        value,
        &["start_offset_seconds", "duration_seconds"],
        &["duration_seconds"],
    )
    .is_some_and(|window| {
        window
            .get("start_offset_seconds")
            .is_none_or(|value| value.as_f64().is_some())
            && window
                .get("duration_seconds")
                .and_then(serde_json::Value::as_f64)
                .is_some()
    })
}

#[allow(clippy::too_many_lines)]
fn query_sleep_session_is_well_formed(value: &serde_json::Value) -> bool {
    let allowed = [
        "session_id",
        "owner_date",
        "calendar_dates",
        "classification",
        "completeness",
        "start",
        "end",
        "local_start",
        "local_end",
        "calendar_timezone",
        "analysis_start",
        "analysis_end",
        "requested_window",
        "elapsed_duration_seconds",
        "observed_duration_seconds",
        "untracked_duration_seconds",
        "asleep_duration_seconds",
        "awake_duration_seconds",
        "stage_durations_seconds",
        "physiology",
        "evidence",
        "limitations",
    ];
    let required: Vec<&str> = allowed
        .iter()
        .copied()
        .filter(|key| *key != "requested_window")
        .collect();
    let Some(object) = query_object_with_keys(value, &allowed, &required) else {
        return false;
    };
    let required_strings = [
        "session_id",
        "owner_date",
        "start",
        "end",
        "local_start",
        "local_end",
        "calendar_timezone",
        "analysis_start",
        "analysis_end",
    ];
    required_strings
        .iter()
        .all(|key| query_nonempty_string(object, key))
        && object
            .get("classification")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|value| matches!(value, "overnight" | "nap" | "sleep"))
        && object
            .get("completeness")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|value| {
                matches!(
                    value,
                    "complete"
                        | "partial"
                        | "truncated_at_start"
                        | "truncated_at_end"
                        | "truncated_at_both"
                        | "aggregated"
                        | "outside_session"
                )
            })
        && query_string_array(object.get("calendar_dates"))
        && [
            "elapsed_duration_seconds",
            "observed_duration_seconds",
            "untracked_duration_seconds",
            "asleep_duration_seconds",
            "awake_duration_seconds",
        ]
        .iter()
        .all(|key| {
            object
                .get(*key)
                .and_then(serde_json::Value::as_f64)
                .is_some()
        })
        && object
            .get("stage_durations_seconds")
            .and_then(serde_json::Value::as_object)
            .is_some_and(|durations| durations.values().all(|value| value.as_f64().is_some()))
        && object
            .get("requested_window")
            .is_none_or(|window| window.is_null() || query_sleep_window_is_well_formed(window))
        && query_array_is_well_formed(
            object.get("physiology"),
            None,
            query_sleep_physiology_is_well_formed,
        )
        && query_array_is_well_formed(
            object.get("evidence"),
            None,
            query_evidence_reference_is_well_formed,
        )
        && query_array_is_well_formed(
            object.get("limitations"),
            Some(64),
            query_limitation_is_well_formed,
        )
}

fn query_alignment_item_is_well_formed(value: &serde_json::Value) -> bool {
    let allowed = [
        "alignment_id",
        "workout",
        "preceding_sleep",
        "following_sleep",
        "seconds_from_preceding_sleep",
        "seconds_until_following_sleep",
        "physiology_sample_count",
        "status",
        "evidence",
        "limitations",
    ];
    let required = [
        "alignment_id",
        "workout",
        "physiology_sample_count",
        "status",
        "evidence",
        "limitations",
    ];
    let Some(object) = query_object_with_keys(value, &allowed, &required) else {
        return false;
    };
    query_nonempty_string(object, "alignment_id")
        && object
            .get("workout")
            .is_some_and(query_workout_is_well_formed)
        && object
            .get("physiology_sample_count")
            .and_then(serde_json::Value::as_u64)
            .is_some()
        && object
            .get("status")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|value| matches!(value, "complete" | "partial" | "unavailable"))
        && ["preceding_sleep", "following_sleep"].iter().all(|key| {
            object
                .get(*key)
                .is_none_or(|value| value.is_null() || query_sleep_session_is_well_formed(value))
        })
        && [
            "seconds_from_preceding_sleep",
            "seconds_until_following_sleep",
        ]
        .iter()
        .all(|key| {
            object
                .get(*key)
                .is_none_or(|value| value.is_null() || value.as_f64().is_some())
        })
        && query_array_is_well_formed(
            object.get("evidence"),
            None,
            query_evidence_reference_is_well_formed,
        )
        && query_array_is_well_formed(
            object.get("limitations"),
            Some(64),
            query_limitation_is_well_formed,
        )
}

fn query_context_evidence_is_well_formed(value: &serde_json::Value) -> bool {
    let Some(object) = query_object_with_keys(
        value,
        &["reference", "value", "note", "metric_ids"],
        &["reference", "metric_ids"],
    ) else {
        return false;
    };
    object
        .get("reference")
        .is_some_and(query_evidence_reference_is_well_formed)
        && query_string_array(object.get("metric_ids"))
        && object
            .get("value")
            .is_none_or(|value| value.is_null() || query_value_is_well_formed(value))
        && object
            .get("note")
            .is_none_or(|value| value.as_str().is_some())
}

fn query_item_is_well_formed(value: &serde_json::Value) -> bool {
    let Some(object) = value.as_object() else {
        return false;
    };
    let Some(kind) = object.get("type").and_then(serde_json::Value::as_str) else {
        return false;
    };
    let (payload, validator): (&str, fn(&serde_json::Value) -> bool) = match kind {
        "metric" => ("metric", query_metric_item_is_well_formed),
        "comparison" => ("comparison", query_comparison_item_is_well_formed),
        "workout" => ("workout", query_workout_is_well_formed),
        "sleep_session" => ("sleep_session", query_sleep_session_is_well_formed),
        "workout_sleep_alignment" => (
            "workout_sleep_alignment",
            query_alignment_item_is_well_formed,
        ),
        "evidence" => ("evidence", query_context_evidence_is_well_formed),
        _ => return false,
    };
    object.len() == 2 && object.get(payload).is_some_and(validator)
}

fn query_packet_metadata_is_well_formed(value: &serde_json::Value) -> bool {
    query_object_with_keys(
        value,
        &["generated_at", "producer"],
        &["generated_at", "producer"],
    )
    .is_some_and(|object| {
        query_nonempty_string(object, "generated_at") && query_nonempty_string(object, "producer")
    })
}

fn query_packet_fact_is_well_formed(value: &serde_json::Value) -> bool {
    let Some(object) = query_object_with_keys(
        value,
        &["fact_id", "label", "owner_date", "value", "evidence"],
        &["fact_id", "label", "value", "evidence"],
    ) else {
        return false;
    };
    query_nonempty_string(object, "fact_id")
        && query_nonempty_string(object, "label")
        && object
            .get("owner_date")
            .is_none_or(|value| value.as_str().is_some())
        && object.get("value").is_some_and(query_value_is_well_formed)
        && query_array_is_well_formed(
            object.get("evidence"),
            None,
            query_evidence_reference_is_well_formed,
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
        && accepted.resolved_range.time_zone_id.len() <= 64
        && accepted
            .resolved_range
            .time_zone_id
            .parse::<chrono_tz::Tz>()
            .is_ok()
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

fn validate_v2_job_time(
    created_at: chrono::DateTime<Utc>,
    expires_at: chrono::DateTime<Utc>,
) -> Result<(), ClientError> {
    let now = Utc::now();
    if created_at.checked_add_signed(chrono::Duration::seconds(JOB_LIFETIME_SECONDS))
        != Some(expires_at)
        || created_at > now + MAXIMUM_REQUEST_CLOCK_SKEW
    {
        return Err(ClientError::InvalidTransfer(
            "Android direct job lifetime is invalid".into(),
        ));
    }
    if expires_at <= now {
        return Err(ClientError::JobExpired);
    }
    Ok(())
}

fn validate_v1_job_time(created_at: chrono::DateTime<Utc>) -> Result<(), ClientError> {
    let now = Utc::now();
    if created_at > now + MAXIMUM_REQUEST_CLOCK_SKEW {
        return Err(ClientError::InvalidTransfer(
            "direct job creation time is invalid".into(),
        ));
    }
    let expires_at = created_at
        .checked_add_signed(chrono::Duration::seconds(JOB_LIFETIME_SECONDS))
        .ok_or_else(|| ClientError::InvalidTransfer("direct job lifetime is invalid".into()))?;
    if expires_at <= now {
        return Err(ClientError::JobExpired);
    }
    Ok(())
}

fn ensure_job_execution_window(record: &JobRecord, timeout: Duration) -> Result<(), ClientError> {
    let timeout = chrono::Duration::from_std(timeout).map_err(|_| ClientError::JobExpired)?;
    let deadline = Utc::now()
        .checked_add_signed(timeout)
        .ok_or(ClientError::JobExpired)?;
    if record.expires_at <= deadline {
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

fn apply_ios_progress(
    record: &mut JobRecord,
    value: &healthmd_protocol::models::ExportProgress,
) -> Result<(), ClientError> {
    if record
        .total_days
        .is_some_and(|total_days| total_days != value.total_days)
    {
        return Err(ClientError::UnexpectedMessage);
    }
    record.state = if record.committed_partitions > 0 || value.committed_partitions > 0 {
        JobState::Transferring
    } else {
        JobState::Preparing
    };
    record.updated_at = Utc::now();
    record.processed_days = record.processed_days.max(value.processed_days);
    record.total_days = Some(value.total_days);
    // The receiver updates committed counters only after local durable partition commit. Peer
    // progress may lag on resume or lead local persistence and must never redefine that frontier.
    record.message = Some("iPhone direct export is progressing.".into());
    Ok(())
}

fn valid_ios_progress(value: &healthmd_protocol::models::ExportProgress) -> bool {
    value.processed_days >= 0
        && value.processed_days <= value.total_days
        && usize::try_from(value.total_days).is_ok_and(|days| days <= MAXIMUM_DATES_PER_JOB)
        && value.committed_partitions >= 0
        && u64::try_from(value.committed_partitions)
            .is_ok_and(|partitions| partitions <= MAXIMUM_PARTITIONS_PER_JOB)
        && value.committed_bytes >= 0
        && u64::try_from(value.committed_bytes).is_ok_and(|bytes| bytes <= MAXIMUM_JOB_BYTES)
        && is_safe_peer_message(&value.message)
}

fn valid_android_progress(value: &v2::ExportProgress) -> bool {
    const MAXIMUM_PROGRESS_UNITS: u64 = 1_000_000;

    value.completed_units <= value.total_units
        && value.total_units <= MAXIMUM_PROGRESS_UNITS
        && value.committed_bytes <= MAXIMUM_JOB_BYTES
        && is_safe_peer_message(&value.message)
}

fn is_safe_peer_metadata(value: &str, maximum_bytes: usize) -> bool {
    !value.trim().is_empty() && value.len() <= maximum_bytes && !value.chars().any(char::is_control)
}

fn is_safe_peer_message(value: &str) -> bool {
    !value.is_empty() && value.len() <= 512 && !value.chars().any(char::is_control)
}

fn is_safe_peer_code(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'_' | b'-')
        })
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
#[path = "direct_fake_peer_tests.rs"]
mod fake_peer_tests;

#[cfg(test)]
mod tests {
    use super::*;

    fn progress_test_record() -> JobRecord {
        JobRecord::new(ExportRequest {
            protocol_version: IOS_APPLICATION_PROTOCOL_VERSION,
            job_id: SwiftUuid(Uuid::new_v4()),
            created_at: Utc::now(),
            date_selection: DateSelection::Exact(healthmd_protocol::models::ExactDateSelection {
                start: "2026-07-01".into(),
                end: "2026-07-02".into(),
            }),
            settings_policy: healthmd_protocol::models::SettingsPolicy::RequestedDatesOnly,
            profile_reference: None,
            response_mode: ResponseMode::RawJson,
            raw_profile: Some(healthmd_protocol::wire::RawProfile::HealthDataProjection),
            canonical_selection: None,
            destination: None,
        })
    }

    fn query_test_coverage() -> serde_json::Value {
        serde_json::json!({
            "status": "available",
            "days_considered": 1,
            "days_with_values": 1,
            "missing": []
        })
    }

    fn query_test_reference() -> serde_json::Value {
        serde_json::json!({
            "evidence_id": "evidence",
            "locator": {
                "type": "summary_key",
                "owner_date": "2026-01-01",
                "key": "steps"
            },
            "source": {
                "schema": "healthmd.health_data",
                "schema_version": 7,
                "digest": "0".repeat(64)
            },
            "source_id": "healthmd_summary"
        })
    }

    fn query_test_workout() -> serde_json::Value {
        serde_json::json!({
            "workout_id": "workout",
            "activity": "walking",
            "start": "2026-01-01T00:00:00Z",
            "end": "2026-01-01T00:30:00Z",
            "details": {},
            "evidence_ids": []
        })
    }

    fn query_test_sleep() -> serde_json::Value {
        serde_json::json!({
            "session_id": "sleep",
            "owner_date": "2026-01-01",
            "calendar_dates": ["2026-01-01"],
            "classification": "sleep",
            "completeness": "complete",
            "start": "2026-01-01T00:00:00Z",
            "end": "2026-01-01T08:00:00Z",
            "local_start": "2026-01-01T00:00:00",
            "local_end": "2026-01-01T08:00:00",
            "calendar_timezone": "UTC",
            "analysis_start": "2026-01-01T00:00:00Z",
            "analysis_end": "2026-01-01T08:00:00Z",
            "elapsed_duration_seconds": 28_800,
            "observed_duration_seconds": 28_800,
            "untracked_duration_seconds": 0,
            "asleep_duration_seconds": 28_800,
            "awake_duration_seconds": 0,
            "stage_durations_seconds": {},
            "physiology": [],
            "evidence": [],
            "limitations": []
        })
    }

    #[test]
    fn pairing_protocols_preserve_legacy_platform_binding_and_share_v3() {
        assert!(pairing_protocol_matches_source(1, SourceKind::Ios));
        assert!(pairing_protocol_matches_source(2, SourceKind::Android));
        assert!(pairing_protocol_matches_source(3, SourceKind::Ios));
        assert!(pairing_protocol_matches_source(3, SourceKind::Android));
        assert!(pairing_protocol_matches_platform(3, PeerPlatform::Ios));
        assert!(pairing_protocol_matches_platform(3, PeerPlatform::Android));
        assert!(!pairing_protocol_matches_source(1, SourceKind::Android));
        assert!(!pairing_protocol_matches_source(2, SourceKind::Ios));
        assert!(!pairing_protocol_matches_platform(1, PeerPlatform::Android));
    }

    #[tokio::test]
    async fn receive_message_answers_heartbeat_before_returning_control_message() {
        use tokio::net::{TcpListener, TcpStream};

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = tokio::spawn(TcpStream::connect(address));
        let (server, _) = listener.accept().await.unwrap();
        let client = client.await.unwrap().unwrap();
        let peer_id = Uuid::new_v4();
        let mut source = SecureChannel::new(
            PacketConnection::new(client),
            [9; 32],
            peer_id,
            "source".into(),
        );
        let mut destination = SecureChannel::new(
            PacketConnection::new(server),
            [9; 32],
            peer_id,
            "destination".into(),
        );
        let expected = DirectMessage::Hello(Unlabeled::from(
            PeerCapabilities::portable_cli_all_versions(SwiftUuid(peer_id)),
        ));
        let source_expected = expected.clone();
        let source_task = tokio::spawn(async move {
            source.send(&DirectMessage::Ping(Empty {})).await.unwrap();
            source.send(&source_expected).await.unwrap();
            assert_eq!(
                source.receive().await.unwrap(),
                SecurePayload::Message(Box::new(DirectMessage::Pong(Empty {})))
            );
        });

        assert_eq!(
            receive_message(&mut destination, Duration::from_secs(1))
                .await
                .unwrap(),
            expected
        );
        source_task.await.unwrap();
    }

    #[tokio::test]
    async fn repeated_heartbeats_do_not_extend_receive_deadline() {
        use tokio::net::{TcpListener, TcpStream};

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = tokio::spawn(TcpStream::connect(address));
        let (server, _) = listener.accept().await.unwrap();
        let client = client.await.unwrap().unwrap();
        let peer_id = Uuid::new_v4();
        let mut source = SecureChannel::new(
            PacketConnection::new(client),
            [11; 32],
            peer_id,
            "source".into(),
        );
        let mut destination = SecureChannel::new(
            PacketConnection::new(server),
            [11; 32],
            peer_id,
            "destination".into(),
        );
        let source_task = tokio::spawn(async move {
            loop {
                source.send(&DirectMessage::Ping(Empty {})).await.unwrap();
                assert_eq!(
                    source.receive().await.unwrap(),
                    SecurePayload::Message(Box::new(DirectMessage::Pong(Empty {})))
                );
                tokio::time::sleep(Duration::from_millis(1)).await;
            }
        });

        assert!(matches!(
            receive_message(&mut destination, Duration::from_millis(25)).await,
            Err(ClientError::TimedOut)
        ));
        source_task.abort();
        let _ = source_task.await;
    }

    #[test]
    fn durable_job_times_are_exact_and_not_future_dated() {
        let now = Utc::now();
        assert!(validate_v1_job_time(now).is_ok());
        assert!(
            validate_v1_job_time(now + MAXIMUM_REQUEST_CLOCK_SKEW + chrono::Duration::seconds(1))
                .is_err()
        );
        assert!(
            validate_v2_job_time(now, now + chrono::Duration::seconds(JOB_LIFETIME_SECONDS))
                .is_ok()
        );
        assert!(
            validate_v2_job_time(
                now,
                now + chrono::Duration::seconds(JOB_LIFETIME_SECONDS + 1)
            )
            .is_err()
        );
        assert!(
            validate_v2_job_time(
                now + MAXIMUM_REQUEST_CLOCK_SKEW + chrono::Duration::seconds(1),
                now + MAXIMUM_REQUEST_CLOCK_SKEW
                    + chrono::Duration::seconds(JOB_LIFETIME_SECONDS + 1)
            )
            .is_err()
        );
    }

    #[test]
    fn ios_peer_progress_never_redefines_the_local_durable_frontier() {
        let mut record = progress_test_record();
        record.committed_partitions = 4;
        record.committed_bytes = 4_096;
        record.processed_days = 2;
        record.total_days = Some(2);
        let progress = healthmd_protocol::models::ExportProgress {
            job_id: record.request.job_id,
            processed_days: 1,
            total_days: 2,
            current_date: Some("2026-07-01".into()),
            committed_partitions: 9,
            committed_bytes: 9_999,
            message: "Peer progress".into(),
        };
        apply_ios_progress(&mut record, &progress).unwrap();
        assert_eq!(record.committed_partitions, 4);
        assert_eq!(record.committed_bytes, 4_096);
        assert_eq!(record.processed_days, 2);
        assert_eq!(record.state, JobState::Transferring);

        let mut empty_local = progress_test_record();
        let mut peer_ahead_of_empty_local = progress.clone();
        peer_ahead_of_empty_local.job_id = empty_local.request.job_id;
        peer_ahead_of_empty_local.processed_days = 1;
        apply_ios_progress(&mut empty_local, &peer_ahead_of_empty_local).unwrap();
        assert_eq!(empty_local.committed_partitions, 0);
        assert_eq!(empty_local.committed_bytes, 0);
        assert_eq!(empty_local.processed_days, 1);
        assert_eq!(empty_local.state, JobState::Transferring);

        let mut mismatched = progress;
        mismatched.total_days = 3;
        assert!(apply_ios_progress(&mut record, &mismatched).is_err());
        assert_eq!(record.total_days, Some(2));
        assert_eq!(record.committed_partitions, 4);
        assert_eq!(record.committed_bytes, 4_096);
        assert_eq!(record.processed_days, 2);
    }

    #[test]
    fn query_page_controls_and_complete_response_shapes_are_bounded() {
        let mut query = serde_json::json!({
            "page": {"max_items": 1_000, "max_bytes": 1_048_576, "cursor": null}
        });
        let mut peer = DirectQueryCapabilities::current();
        peer.maximum_page_items = 10;
        peer.maximum_page_bytes = 32_768;
        assert_eq!(clamp_query_page(&mut query, &peer).unwrap(), (10, 32_768));
        assert_eq!(query["page"]["max_items"], 10);
        assert_eq!(query["page"]["max_bytes"], 32_768);

        let coverage = serde_json::json!({
            "status": "available",
            "days_considered": 1,
            "days_with_values": 1,
            "missing": []
        });
        let metric_item = serde_json::json!({
            "type": "metric",
            "metric": {
                "metric_id": "steps",
                "display_name": "Steps",
                "owner_date": "2026-01-01",
                "status": "available",
                "evidence": [],
                "limitations": []
            }
        });
        let bounded = serde_json::json!({
            "schema": "healthmd.query_response",
            "schema_version": 1,
            "items": [metric_item.clone(), metric_item.clone(), metric_item],
            "coverage": coverage.clone(),
            "sources": [],
            "evidence": [],
            "limitations": []
        });
        assert!(query_response_is_well_formed_and_bounded(&bounded, 3));

        let fact = serde_json::json!({
            "fact_id": "fact",
            "label": "Fact",
            "value": {"type": "count", "value": 1},
            "evidence": []
        });
        let mut packet = serde_json::json!({
            "schema": "healthmd.evidence_packet",
            "schema_version": 1,
            "packet_id": "packet",
            "kind": "training",
            "facts": [fact.clone(), fact.clone(), fact.clone()],
            "coverage": coverage.clone(),
            "sources": [],
            "limitations": [],
            "metadata": {"generated_at": "2026-01-01T00:00:00Z", "producer": "Health.md"}
        });
        let packet_response = serde_json::json!({
            "schema": "healthmd.query_response",
            "schema_version": 1,
            "items": [],
            "packet": packet.clone(),
            "coverage": coverage.clone(),
            "sources": [],
            "evidence": [],
            "limitations": []
        });
        assert!(query_response_is_well_formed_and_bounded(
            &packet_response,
            3
        ));
        packet["facts"] = serde_json::json!([fact.clone(), fact.clone(), fact.clone(), fact]);
        let oversized = serde_json::json!({
            "schema": "healthmd.query_response",
            "schema_version": 1,
            "items": [],
            "packet": packet,
            "coverage": coverage,
            "sources": [],
            "evidence": [],
            "limitations": []
        });
        assert!(!query_response_is_well_formed_and_bounded(&oversized, 3));

        let mut incomplete = bounded.clone();
        incomplete.as_object_mut().unwrap().remove("sources");
        assert!(!query_response_is_well_formed_and_bounded(&incomplete, 3));
        let mut unknown = bounded.clone();
        unknown["unexpected"] = serde_json::json!(true);
        assert!(!query_response_is_well_formed_and_bounded(&unknown, 3));
        let mut mixed = bounded;
        mixed["packet"] = packet_response["packet"].clone();
        assert!(!query_response_is_well_formed_and_bounded(&mixed, 3));
    }

    #[test]
    fn every_query_item_variant_has_a_strict_nested_shape() {
        let reference = query_test_reference();
        let workout = query_test_workout();
        let sleep = query_test_sleep();
        let items = [
            serde_json::json!({
                "type": "metric",
                "metric": {
                    "metric_id": "steps", "display_name": "Steps",
                    "owner_date": "2026-01-01", "status": "available",
                    "value": {"type": "count", "value": 1},
                    "evidence": [reference.clone()], "limitations": []
                }
            }),
            serde_json::json!({
                "type": "comparison",
                "comparison": {
                    "metric_id": "steps",
                    "aggregation": {"metric_id": "steps", "kind": "sum"},
                    "first_range": {"start_date": "2026-01-01", "end_date": "2026-01-02"},
                    "second_range": {"start_date": "2026-01-03", "end_date": "2026-01-04"},
                    "direction": "increased", "coverage": query_test_coverage(),
                    "evidence": [], "limitations": []
                }
            }),
            serde_json::json!({"type": "workout", "workout": workout.clone()}),
            serde_json::json!({"type": "sleep_session", "sleep_session": sleep.clone()}),
            serde_json::json!({
                "type": "workout_sleep_alignment",
                "workout_sleep_alignment": {
                    "alignment_id": "alignment", "workout": workout,
                    "preceding_sleep": sleep, "physiology_sample_count": 0,
                    "status": "complete", "evidence": [], "limitations": []
                }
            }),
            serde_json::json!({
                "type": "evidence",
                "evidence": {"reference": reference, "metric_ids": ["steps"]}
            }),
        ];
        assert!(items.iter().all(query_item_is_well_formed));

        let mut malformed_category = items[0].clone();
        malformed_category["metric"]["value"] = serde_json::json!({
            "type": "category", "identifier": "value", "raw_value": "not-an-integer"
        });
        assert!(!query_item_is_well_formed(&malformed_category));
        let mut outside_session = items[3].clone();
        outside_session["sleep_session"]["completeness"] = serde_json::json!("outside_session");
        assert!(query_item_is_well_formed(&outside_session));
        let mut malformed_sleep = items[3].clone();
        malformed_sleep["sleep_session"]["classification"] = serde_json::json!("future_case");
        assert!(!query_item_is_well_formed(&malformed_sleep));
        let mut unknown_nested = items[2].clone();
        unknown_nested["workout"]["private"] = serde_json::json!(true);
        assert!(!query_item_is_well_formed(&unknown_nested));
    }

    #[test]
    fn peer_diagnostics_are_bounded_and_machine_shaped() {
        assert!(is_safe_peer_code("permission_required"));
        assert!(!is_safe_peer_code("permission required"));
        assert!(!is_safe_peer_code("HEALTH_VALUE"));
        assert!(is_safe_peer_metadata("Pixel 7", 128));
        assert!(!is_safe_peer_metadata("private\nvalue", 128));
        assert!(is_safe_peer_message("Preparing export"));
        assert!(!is_safe_peer_message("line one\nline two"));
        assert!(!is_safe_peer_message(&"x".repeat(513)));
    }
}
