//! Deployed Swift v1 JSON wire shapes.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::{
    encoding::{SwiftUuid, data, optional_data},
    models::{
        ExportAccepted, ExportFailure, ExportProgress, ExportRequest, FileManifest, JobIdPayload,
        RawDayManifest, TransferChunk, TransferChunkAcknowledgement, TransferDisposition,
        TransferFinalAcknowledgement, TransferFinalize, TransferOpen,
        TransferPartitionAcknowledgement, TransferPartitionComplete, TransferSession,
    },
    time,
};

/// Swift synthesized associated-value box (`{"_0": value}`).
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Unlabeled<T> {
    #[serde(rename = "_0")]
    pub value: T,
}

impl<T> From<T> for Unlabeled<T> {
    fn from(value: T) -> Self {
        Self { value }
    }
}

/// Swift synthesized no-payload associated-value box (`{}`).
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct Empty {}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedFrame {
    #[serde(with = "data")]
    pub nonce: Vec<u8>,
    #[serde(with = "data")]
    pub ciphertext: Vec<u8>,
    #[serde(with = "data")]
    pub tag: Vec<u8>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct PairingRequest {
    #[serde(rename = "protocolVersion")]
    pub protocol_version: i32,
    #[serde(rename = "deviceName")]
    pub device_name: String,
    #[serde(rename = "clientPublicKey", with = "data")]
    pub client_public_key: Vec<u8>,
    #[serde(rename = "clientNonce", with = "data")]
    pub client_nonce: Vec<u8>,
    #[serde(rename = "codeVerifier", with = "data")]
    pub code_verifier: Vec<u8>,
    #[serde(
        rename = "clientInstallationID",
        skip_serializing_if = "Option::is_none"
    )]
    pub client_installation_id: Option<SwiftUuid>,
    #[serde(
        rename = "trustedVerifier",
        default,
        skip_serializing_if = "Option::is_none",
        with = "optional_data"
    )]
    pub trusted_verifier: Option<Vec<u8>>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct PairingResponse {
    #[serde(rename = "protocolVersion")]
    pub protocol_version: i32,
    #[serde(rename = "macName")]
    pub mac_name: String,
    #[serde(rename = "serverPublicKey", with = "data")]
    pub server_public_key: Vec<u8>,
    #[serde(rename = "serverNonce", with = "data")]
    pub server_nonce: Vec<u8>,
    #[serde(rename = "macInstallationID", skip_serializing_if = "Option::is_none")]
    pub mac_installation_id: Option<SwiftUuid>,
    #[serde(
        rename = "authenticationVerifier",
        default,
        skip_serializing_if = "Option::is_none",
        with = "optional_data"
    )]
    pub authentication_verifier: Option<Vec<u8>>,
    #[serde(
        rename = "sealedReconnectSecret",
        skip_serializing_if = "Option::is_none"
    )]
    pub sealed_reconnect_secret: Option<EncryptedFrame>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct PairingRejected {
    pub reason: String,
}

/// The outer pre-authenticated packet. Every payload keeps Swift's `_0` box.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum SyncPacket {
    #[serde(rename = "pairingRequest")]
    PairingRequest(Unlabeled<PairingRequest>),
    #[serde(rename = "pairingResponse")]
    PairingResponse(Unlabeled<PairingResponse>),
    #[serde(rename = "pairingRejected")]
    PairingRejected(Unlabeled<PairingRejected>),
    #[serde(rename = "encrypted")]
    Encrypted(Unlabeled<EncryptedFrame>),
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
pub enum PeerPlatform {
    #[serde(rename = "ios")]
    Ios,
    #[serde(rename = "android")]
    Android,
    /// Legacy v1 wire value used by every direct CLI operating system.
    #[serde(rename = "macos_cli")]
    Cli,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
pub enum RawProfile {
    #[serde(rename = "canonical_source_records_v1")]
    CanonicalSourceRecordsV1,
    #[serde(rename = "health_data_projection")]
    HealthDataProjection,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferCapabilities {
    #[serde(rename = "protocolVersions")]
    pub protocol_versions: Vec<i32>,
    #[serde(rename = "binaryFrameVersions")]
    pub binary_frame_versions: Vec<i32>,
    #[serde(rename = "minimumPartitionBytes")]
    pub minimum_partition_bytes: i64,
    #[serde(rename = "preferredPartitionBytes")]
    pub preferred_partition_bytes: i64,
    #[serde(rename = "maximumPartitionBytes")]
    pub maximum_partition_bytes: i64,
    #[serde(rename = "maximumInFlightChunks")]
    pub maximum_in_flight_chunks: i32,
}

impl Default for TransferCapabilities {
    fn default() -> Self {
        Self {
            protocol_versions: vec![1],
            binary_frame_versions: vec![1],
            minimum_partition_bytes: 32 * 1_024 * 1_024,
            preferred_partition_bytes: 48 * 1_024 * 1_024,
            maximum_partition_bytes: 64 * 1_024 * 1_024,
            maximum_in_flight_chunks: 4,
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct WakeCapabilities {
    pub supported: bool,
}

/// RFC-0005 P2 wake enrollment delivered by the phone immediately after its hello when both
/// sides advertised wake support. `wake_key` is base64 of exactly 32 random bytes generated
/// solely for wake HMAC verification; it is never derived from or reused for pairing, channel,
/// or session secrets.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct WakeEnrollment {
    #[serde(rename = "wakeID")]
    pub wake_id: String,
    #[serde(rename = "wakeKey")]
    pub wake_key: String,
}

impl WakeEnrollment {
    /// Validate the enrollment shape before anything is persisted. The identifier stays opaque;
    /// the key must decode to exactly 32 bytes.
    #[must_use]
    pub fn is_valid(&self) -> bool {
        !self.wake_id.is_empty()
            && self.wake_id.len() <= 128
            && !self
                .wake_id
                .bytes()
                .any(|byte| !(0x20..=0x7e).contains(&byte))
            && base64::Engine::decode(&base64::engine::general_purpose::STANDARD, &self.wake_key)
                .is_ok_and(|bytes| bytes.len() == 32)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct PeerCapabilities {
    #[serde(rename = "protocolVersions")]
    pub protocol_versions: Vec<i32>,
    pub platform: PeerPlatform,
    #[serde(rename = "installationID")]
    pub installation_id: SwiftUuid,
    #[serde(rename = "supportedRawProfiles")]
    pub supported_raw_profiles: Vec<RawProfile>,
    #[serde(rename = "supportsDurableJobs")]
    pub supports_durable_jobs: bool,
    #[serde(rename = "supportsCanonicalExtraction")]
    pub supports_canonical_extraction: bool,
    pub transfer: TransferCapabilities,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub query: Option<DirectQueryCapabilities>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wake: Option<WakeCapabilities>,
}

impl PeerCapabilities {
    #[must_use]
    pub fn portable_cli(installation_id: SwiftUuid) -> Self {
        Self {
            protocol_versions: vec![crate::IOS_APPLICATION_PROTOCOL_VERSION],
            platform: PeerPlatform::Cli,
            installation_id,
            supported_raw_profiles: vec![
                RawProfile::CanonicalSourceRecordsV1,
                RawProfile::HealthDataProjection,
            ],
            supports_durable_jobs: true,
            supports_canonical_extraction: true,
            transfer: TransferCapabilities::default(),
            query: None,
            wake: Some(WakeCapabilities { supported: true }),
        }
    }

    /// CLI capabilities advertised during source-neutral application negotiation.
    #[must_use]
    pub fn portable_cli_all_versions(installation_id: SwiftUuid) -> Self {
        let mut capabilities = Self::portable_cli(installation_id);
        capabilities.protocol_versions = vec![
            crate::IOS_APPLICATION_PROTOCOL_VERSION,
            crate::ANDROID_APPLICATION_PROTOCOL_VERSION,
            crate::IOS_QUERY_APPLICATION_PROTOCOL_VERSION,
        ];
        capabilities.query = Some(DirectQueryCapabilities::current());
        capabilities
    }

    #[must_use]
    pub fn negotiated_protocol_version(&self, peer: &Self) -> Option<i32> {
        self.protocol_versions
            .iter()
            .filter(|version| peer.protocol_versions.contains(version))
            .max()
            .copied()
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DirectQueryCapabilities {
    #[serde(rename = "schemaVersions")]
    pub schema_versions: Vec<i32>,
    pub operations: Vec<String>,
    #[serde(rename = "detailLevels")]
    pub detail_levels: Vec<DirectQueryDetailLevel>,
    #[serde(rename = "maximumPageItems")]
    pub maximum_page_items: i32,
    #[serde(rename = "maximumPageBytes")]
    pub maximum_page_bytes: i32,
    #[serde(rename = "supportsEvidenceValues")]
    pub supports_evidence_values: bool,
}

impl DirectQueryCapabilities {
    #[must_use]
    pub fn current() -> Self {
        Self {
            schema_versions: vec![1],
            operations: [
                "coverage",
                "derive_packet",
                "metric_series",
                "period_comparison",
                "sleep_session_listing",
                "source_record_listing",
                "workout_listing",
                "workout_sleep_alignment",
            ]
            .into_iter()
            .map(str::to_owned)
            .collect(),
            detail_levels: vec![
                DirectQueryDetailLevel::Lossless,
                DirectQueryDetailLevel::Summary,
            ],
            maximum_page_items: 1_000,
            maximum_page_bytes: 1_024 * 1_024,
            supports_evidence_values: true,
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DirectQueryDetailLevel {
    Summary,
    Lossless,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DirectQueryRequest {
    #[serde(rename = "protocolVersion")]
    pub protocol_version: i32,
    #[serde(rename = "requestID")]
    pub request_id: SwiftUuid,
    #[serde(rename = "createdAt", with = "time")]
    pub created_at: DateTime<Utc>,
    #[serde(rename = "detailLevel")]
    pub detail_level: DirectQueryDetailLevel,
    pub query: serde_json::Value,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DirectQueryResponse {
    #[serde(rename = "requestID")]
    pub request_id: SwiftUuid,
    pub response: serde_json::Value,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DirectQueryFailure {
    #[serde(rename = "requestID")]
    pub request_id: SwiftUuid,
    pub code: String,
    pub message: String,
    pub retryable: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct StatusRequest {
    #[serde(rename = "requestedAt", with = "time")]
    pub requested_at: DateTime<Utc>,
}

#[allow(clippy::struct_excessive_bools)]
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct IphoneStatus {
    pub name: String,
    #[serde(rename = "appActive")]
    pub app_active: bool,
    #[serde(rename = "protectedDataAvailable")]
    pub protected_data_available: bool,
    #[serde(rename = "exportInProgress")]
    pub export_in_progress: bool,
    #[serde(rename = "canTriggerRawExports")]
    pub can_trigger_raw_exports: bool,
    #[serde(rename = "canTriggerFileExports")]
    pub can_trigger_file_exports: bool,
    #[serde(
        rename = "queryInProgress",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub query_in_progress: Option<bool>,
    #[serde(
        rename = "canTriggerQueries",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub can_trigger_queries: Option<bool>,
    #[serde(rename = "activeJobID", skip_serializing_if = "Option::is_none")]
    pub active_job_id: Option<SwiftUuid>,
    #[serde(
        rename = "activeQueryRequestID",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub active_query_request_id: Option<SwiftUuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DirectMessage {
    #[serde(rename = "hello")]
    Hello(Unlabeled<PeerCapabilities>),
    #[serde(rename = "statusRequest")]
    StatusRequest(Unlabeled<StatusRequest>),
    #[serde(rename = "statusResponse")]
    StatusResponse(Unlabeled<IphoneStatus>),
    #[serde(rename = "exportRequest")]
    ExportRequest(Unlabeled<ExportRequest>),
    #[serde(rename = "queryRequest")]
    QueryRequest(Unlabeled<DirectQueryRequest>),
    #[serde(rename = "queryResponse")]
    QueryResponse(Unlabeled<DirectQueryResponse>),
    #[serde(rename = "queryRejected")]
    QueryRejected(Unlabeled<DirectQueryFailure>),
    #[serde(rename = "wakeEnrollment")]
    WakeEnrollment(Unlabeled<WakeEnrollment>),
    #[serde(rename = "exportAccepted")]
    ExportAccepted(Unlabeled<ExportAccepted>),
    #[serde(rename = "exportProgress")]
    ExportProgress(Unlabeled<ExportProgress>),
    #[serde(rename = "exportRejected")]
    ExportRejected(Unlabeled<ExportFailure>),
    #[serde(rename = "transferSession")]
    TransferSession(Unlabeled<TransferSession>),
    #[serde(rename = "rawDayManifest")]
    RawDayManifest(Unlabeled<RawDayManifest>),
    #[serde(rename = "fileManifest")]
    FileManifest(Unlabeled<FileManifest>),
    #[serde(rename = "transferOpen")]
    TransferOpen(Unlabeled<TransferOpen>),
    #[serde(rename = "transferDisposition")]
    TransferDisposition(Unlabeled<TransferDisposition>),
    #[serde(rename = "transferChunk")]
    TransferChunk(Unlabeled<TransferChunk>),
    #[serde(rename = "transferChunkAcknowledgement")]
    TransferChunkAcknowledgement(Unlabeled<TransferChunkAcknowledgement>),
    #[serde(rename = "transferPartitionComplete")]
    TransferPartitionComplete(Unlabeled<TransferPartitionComplete>),
    #[serde(rename = "transferPartitionAcknowledgement")]
    TransferPartitionAcknowledgement(Unlabeled<TransferPartitionAcknowledgement>),
    #[serde(rename = "transferFinalize")]
    TransferFinalize(Unlabeled<TransferFinalize>),
    #[serde(rename = "transferFinalAcknowledgement")]
    TransferFinalAcknowledgement(Unlabeled<TransferFinalAcknowledgement>),
    #[serde(rename = "completionConfirmed")]
    CompletionConfirmed(JobIdPayload),
    #[serde(rename = "cancel")]
    Cancel(JobIdPayload),
    #[serde(rename = "cancelAcknowledged")]
    CancelAcknowledged(JobIdPayload),
    #[serde(rename = "ping")]
    Ping(Empty),
    #[serde(rename = "pong")]
    Pong(Empty),
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn sync_packet_uses_swift_unlabelled_box() {
        let request = PairingRequest {
            protocol_version: 1,
            device_name: "iPhone".into(),
            client_public_key: vec![1; 32],
            client_nonce: vec![2; 32],
            code_verifier: vec![3; 32],
            client_installation_id: Some(SwiftUuid(Uuid::nil())),
            trusted_verifier: None,
        };
        let value = serde_json::to_value(SyncPacket::PairingRequest(request.into())).unwrap();
        assert_eq!(value["pairingRequest"]["_0"]["protocolVersion"], 1);
        assert!(
            value["pairingRequest"]["_0"]
                .get("trustedVerifier")
                .is_none()
        );
    }

    #[test]
    fn direct_no_payload_case_is_empty_object() {
        assert_eq!(
            serde_json::to_string(&DirectMessage::Ping(Empty {})).unwrap(),
            r#"{"ping":{}}"#
        );
    }

    #[test]
    fn capabilities_keep_id_acronym() {
        let value =
            serde_json::to_value(PeerCapabilities::portable_cli(SwiftUuid(Uuid::nil()))).unwrap();
        assert!(value.get("installationID").is_some());
        assert!(value.get("installationId").is_none());
        assert!(value.get("query").is_none());
    }

    #[test]
    fn direct_query_v3_uses_swift_box_and_bounded_capabilities() {
        let request = DirectQueryRequest {
            protocol_version: crate::IOS_QUERY_APPLICATION_PROTOCOL_VERSION,
            request_id: SwiftUuid(Uuid::nil()),
            created_at: DateTime::from_timestamp(1_700_000_000, 0).unwrap(),
            detail_level: DirectQueryDetailLevel::Summary,
            query: serde_json::json!({
                "schema": "healthmd.query_request",
                "schema_version": 1,
                "operation": { "type": "coverage" }
            }),
        };
        let message = DirectMessage::QueryRequest(request.into());
        let value = serde_json::to_value(&message).unwrap();
        assert_eq!(value["queryRequest"]["_0"]["protocolVersion"], 3);
        assert_eq!(
            value["queryRequest"]["_0"]["requestID"],
            Uuid::nil().to_string().to_uppercase()
        );
        assert_eq!(value["queryRequest"]["_0"]["detailLevel"], "summary");
        assert_eq!(
            serde_json::from_value::<DirectMessage>(value).unwrap(),
            message
        );

        let capabilities = DirectQueryCapabilities::current();
        assert_eq!(capabilities.maximum_page_items, 1_000);
        assert_eq!(capabilities.maximum_page_bytes, 1_024 * 1_024);
        assert!(
            capabilities
                .operations
                .contains(&"metric_series".to_owned())
        );
    }
}
