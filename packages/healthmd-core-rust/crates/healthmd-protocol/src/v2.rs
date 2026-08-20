//! Platform-neutral application protocol used by Android direct sources.
//!
//! Version 2 intentionally reuses the deployed v1 packet framing, pairing handshake,
//! encrypted channel, binary chunk frame, and transfer limits. The initial `hello`
//! message remains a v1-shaped message so peers can negotiate an application version.
//! After Android negotiates version 2, control messages use [`Envelope`].

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{encoding::canonical_json, transfer::sha256_hex};

/// Application protocol version required by Android direct sources.
pub const APPLICATION_PROTOCOL_VERSION: u16 = 2;

/// A versioned, explicitly tagged v2 control message.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Envelope {
    pub protocol_version: u16,
    #[serde(flatten)]
    pub message: Message,
}

impl Envelope {
    #[must_use]
    pub const fn new(message: Message) -> Self {
        Self {
            protocol_version: APPLICATION_PROTOCOL_VERSION,
            message,
        }
    }

    /// Verify that this envelope belongs to the supported application protocol.
    ///
    /// # Errors
    ///
    /// Returns [`ProtocolError::UnsupportedVersion`] for any other version.
    pub const fn validate_version(&self) -> Result<(), ProtocolError> {
        if self.protocol_version == APPLICATION_PROTOCOL_VERSION {
            Ok(())
        } else {
            Err(ProtocolError::UnsupportedVersion(self.protocol_version))
        }
    }
}

/// Control messages exchanged after Android negotiates application protocol v2.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", content = "payload", rename_all = "snake_case")]
pub enum Message {
    SourceHello(SourceHello),
    StatusRequest(StatusRequest),
    StatusResponse(SourceStatus),
    ExportRequest(ExportRequest),
    ExportAccepted(ExportAccepted),
    ExportProgress(ExportProgress),
    ExportRejected(ExportFailure),
    ArtifactManifest(ArtifactManifest),
    TransferSession(TransferSession),
    TransferOpen(TransferOpen),
    TransferDisposition(TransferDisposition),
    TransferChunkAcknowledgement(TransferChunkAcknowledgement),
    TransferPartitionComplete(TransferPartitionComplete),
    TransferPartitionAcknowledgement(TransferPartitionAcknowledgement),
    TransferFinalize(TransferFinalize),
    TransferFinalAcknowledgement(TransferFinalAcknowledgement),
    CompletionConfirmed(JobPayload),
    Cancel(JobPayload),
    CancelAcknowledged(JobPayload),
    Ping(Empty),
    Pong(Empty),
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct Empty {}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SourcePlatform {
    Android,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProductId {
    AndroidProviderNativeSnapshotV1,
    GeneratedFilesV1,
    AndroidDailyRecordsV1,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactFormat {
    Json,
    Ndjson,
    Markdown,
    Csv,
    ObsidianBases,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactSchema {
    pub id: String,
    pub major: u16,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SourceIdentity {
    pub installation_id: Uuid,
    pub platform: SourcePlatform,
    pub display_name: String,
    pub app_version: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ProductCapability {
    pub product_id: ProductId,
    pub artifact_schema: ArtifactSchema,
    pub formats: Vec<ArtifactFormat>,
    // Kotlin v2 uses `encodeDefaults = true`; empty default lists are wire-significant.
    #[serde(default)]
    pub providers: Vec<String>,
    #[serde(default)]
    pub settings_policies: Vec<SettingsPolicy>,
    pub supports_resume: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ProtocolLimits {
    pub maximum_control_bytes: u32,
    pub maximum_chunk_bytes: u32,
    pub preferred_partition_bytes: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SourceHello {
    pub source: SourceIdentity,
    pub products: Vec<ProductCapability>,
    pub limits: ProtocolLimits,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct StatusRequest {
    #[serde(with = "crate::time")]
    pub requested_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SourceStatus {
    pub source: SourceIdentity,
    pub app_active: bool,
    pub protected_data_available: bool,
    pub export_in_progress: bool,
    pub available_products: Vec<ProductId>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_job_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum DateSelection {
    Exact {
        start_date: String,
        end_date: String,
    },
    AllAvailable,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SettingsPolicy {
    RequestedScope,
    SavedDeviceSettings,
    /// Resolve settings from a named export profile on the Android source by
    /// stable ID (see [`ProfileReference`]). Additive in the wire contract:
    /// older peers that do not know this variant — or the optional
    /// `profile_reference` field — fail closed with a decode error instead of
    /// misinterpreting the request (export-profiles decision 10).
    Profile,
}

/// Reference to an export profile resolved on the Android source. The stable
/// profile ID is authoritative; `name` is a display convenience captured for
/// errors and logs and is only used for resolution when the ID is absent.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ProfileReference {
    pub profile_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RawSnapshotFormat {
    Json,
    Ndjson,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum RawSnapshotScope {
    SelectedRecordTypes { selected_metric_ids: Vec<String> },
    AllAuthorizedSupportedData,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "product_id", rename_all = "snake_case", deny_unknown_fields)]
pub enum ExportProduct {
    AndroidProviderNativeSnapshotV1 {
        provider_id: String,
        format: RawSnapshotFormat,
        scope: RawSnapshotScope,
        include_exercise_routes: bool,
    },
    GeneratedFilesV1 {
        settings_policy: SettingsPolicy,
        /// Present exactly when `settings_policy` is [`SettingsPolicy::Profile`].
        #[serde(default, skip_serializing_if = "Option::is_none")]
        profile_reference: Option<ProfileReference>,
    },
    AndroidDailyRecordsV1 {
        metric_ids: Vec<String>,
        field_pointers: Vec<String>,
    },
}

impl ExportProduct {
    #[must_use]
    pub const fn product_id(&self) -> ProductId {
        match self {
            Self::AndroidProviderNativeSnapshotV1 { .. } => {
                ProductId::AndroidProviderNativeSnapshotV1
            }
            Self::GeneratedFilesV1 { .. } => ProductId::GeneratedFilesV1,
            Self::AndroidDailyRecordsV1 { .. } => ProductId::AndroidDailyRecordsV1,
        }
    }

    /// The profile reference this product resolves settings from, when any.
    #[must_use]
    pub const fn profile_reference(&self) -> Option<&ProfileReference> {
        match self {
            Self::GeneratedFilesV1 {
                profile_reference: reference,
                ..
            } => reference.as_ref(),
            Self::AndroidProviderNativeSnapshotV1 { .. } | Self::AndroidDailyRecordsV1 { .. } => {
                None
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct DestinationBinding {
    /// Opaque digest binding the request to the CLI-side destination and identity.
    pub binding_sha256: String,
    /// Privacy-safe basename shown to the Android user.
    pub display_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportRequest {
    pub job_id: Uuid,
    #[serde(with = "crate::time")]
    pub created_at: DateTime<Utc>,
    #[serde(with = "crate::time")]
    pub expires_at: DateTime<Utc>,
    pub source_installation_id: Uuid,
    pub date_selection: DateSelection,
    pub product: ExportProduct,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub destination: Option<DestinationBinding>,
}

/// Canonical SHA-256 fingerprint of an immutable v2 export request.
///
/// # Errors
///
/// Returns an encoding error if the request cannot be serialized.
pub fn request_fingerprint(request: &ExportRequest) -> Result<String, serde_json::Error> {
    canonical_json(request).map(|bytes| sha256_hex(&bytes))
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct PeerBinding {
    pub source_installation_id: Uuid,
    pub destination_installation_id: Uuid,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ResolvedRange {
    pub start_date: String,
    pub end_date: String,
    pub time_zone_id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportAccepted {
    pub job_id: Uuid,
    #[serde(with = "crate::time")]
    pub accepted_at: DateTime<Utc>,
    pub peer_binding: PeerBinding,
    pub product_id: ProductId,
    pub resolved_range: ResolvedRange,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub settings_snapshot_sha256: Option<String>,
    pub request_fingerprint: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportProgress {
    pub job_id: Uuid,
    pub phase: ExportPhase,
    pub completed_units: u64,
    pub total_units: u64,
    pub committed_bytes: u64,
    pub message: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ExportPhase {
    Preparing,
    Reading,
    Validating,
    Transferring,
    AwaitingFinalAcknowledgement,
    Completed,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    IncompatibleProtocol,
    AuthenticationFailed,
    TrustMissing,
    UnsupportedProduct,
    UnsupportedSchema,
    UnsupportedProvider,
    InvalidRequest,
    ClockSkew,
    PermissionRequired,
    DeviceLocked,
    SourceUnavailable,
    Busy,
    QuotaExhausted,
    StagingFailed,
    ValidationFailed,
    SpoolMissingRestartRequired,
    TransferFailed,
    DestinationChanged,
    DestinationCommitFailed,
    Cancelled,
    JobExpired,
    InternalFailure,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportFailure {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub job_id: Option<Uuid>,
    pub code: ErrorCode,
    pub phase: ExportPhase,
    pub retryable: bool,
    pub public_message: String,
    // Kotlin v2 uses `encodeDefaults = true`; an empty details map is emitted.
    #[serde(default)]
    pub details: BTreeMap<String, Vec<String>>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactKind {
    RawSnapshot,
    GeneratedFile,
    DailyRecords,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FileWriteMode {
    Overwrite,
    Append,
    MergeMarkdown,
    MergeMarkdownPreservingPreamble,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactManifest {
    pub job_id: Uuid,
    pub artifact_id: Uuid,
    pub kind: ArtifactKind,
    pub schema: ArtifactSchema,
    pub media_type: String,
    pub byte_count: u64,
    pub sha256: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logical_checksum_sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub relative_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub write_mode: Option<FileWriteMode>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub snapshot_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferSession {
    pub session_id: Uuid,
    pub job_id: Uuid,
    pub request_fingerprint: String,
    pub peer_binding: PeerBinding,
    pub partition_target_bytes: u64,
    #[serde(with = "crate::time")]
    pub created_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferPartition {
    pub index: u64,
    pub transfer_id: Uuid,
    pub artifact_id: Uuid,
    pub artifact_offset: u64,
    pub byte_count: u64,
    pub chunk_count: u64,
    pub sha256: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_sha256: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferOpen {
    pub session: TransferSession,
    pub partition: TransferPartition,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferDispositionKind {
    Needed,
    AlreadyCommitted,
    Rejected,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferDisposition {
    pub session_id: Uuid,
    pub job_id: Uuid,
    pub partition_index: u64,
    pub partition_sha256: String,
    pub disposition: TransferDispositionKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferChunkAcknowledgement {
    pub transfer_id: Uuid,
    pub sequence: u32,
    pub accepted: bool,
    pub sha256: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferPartitionComplete {
    pub session_id: Uuid,
    pub job_id: Uuid,
    pub partition_index: u64,
    pub transfer_id: Uuid,
    pub partition_sha256: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferPartitionAcknowledgement {
    pub session_id: Uuid,
    pub job_id: Uuid,
    pub partition_index: u64,
    pub transfer_id: Uuid,
    pub partition_sha256: String,
    pub accepted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferFinalize {
    pub session_id: Uuid,
    pub job_id: Uuid,
    pub request_fingerprint: String,
    pub total_partitions: u64,
    pub total_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub final_partition_sha256: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferFinalAcknowledgement {
    pub session_id: Uuid,
    pub job_id: Uuid,
    pub accepted: bool,
    pub total_partitions: u64,
    pub total_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub final_partition_sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_byte_count: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct JobPayload {
    pub job_id: Uuid,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum ProtocolError {
    #[error("unsupported direct application protocol version {0}")]
    UnsupportedVersion(u16),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture_request() -> ExportRequest {
        ExportRequest {
            job_id: Uuid::parse_str("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee").unwrap(),
            created_at: "2026-07-24T10:11:12Z".parse().unwrap(),
            expires_at: "2026-07-31T10:11:12Z".parse().unwrap(),
            source_installation_id: Uuid::parse_str("11111111-2222-4333-8444-555555555555")
                .unwrap(),
            date_selection: DateSelection::Exact {
                start_date: "2026-07-01".into(),
                end_date: "2026-07-02".into(),
            },
            product: ExportProduct::AndroidProviderNativeSnapshotV1 {
                provider_id: "health_connect".into(),
                format: RawSnapshotFormat::Ndjson,
                scope: RawSnapshotScope::SelectedRecordTypes {
                    selected_metric_ids: vec!["sleep".into(), "steps".into()],
                },
                include_exercise_routes: false,
            },
            destination: None,
        }
    }

    #[test]
    fn envelope_uses_explicit_type_and_payload() {
        let envelope = Envelope::new(Message::StatusRequest(StatusRequest {
            requested_at: "2026-07-24T10:11:12Z".parse().unwrap(),
        }));
        let value = serde_json::to_value(envelope).unwrap();
        assert_eq!(value["protocol_version"], 2);
        assert_eq!(value["type"], "status_request");
        assert_eq!(value["payload"]["requested_at"], "2026-07-24T10:11:12Z");
    }

    #[test]
    fn request_fingerprint_is_deterministic() {
        let request = fixture_request();
        let first = request_fingerprint(&request).unwrap();
        let round_trip: ExportRequest =
            serde_json::from_slice(&canonical_json(&request).unwrap()).unwrap();
        let second = request_fingerprint(&round_trip).unwrap();
        assert_eq!(first, second);
        assert_eq!(first.len(), 64);
    }

    #[test]
    fn envelope_rejects_other_versions() {
        let envelope = Envelope {
            protocol_version: 1,
            message: Message::Ping(Empty {}),
        };
        assert_eq!(
            envelope.validate_version(),
            Err(ProtocolError::UnsupportedVersion(1))
        );
    }
}
