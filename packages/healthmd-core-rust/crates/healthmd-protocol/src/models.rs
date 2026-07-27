//! Direct export, transfer, and durable-job wire models.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::{
    encoding::{SwiftUuid, data},
    time,
    wire::{Empty, RawProfile},
};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DateSelection {
    #[serde(rename = "exact")]
    Exact(ExactDateSelection),
    #[serde(rename = "allAvailable")]
    AllAvailable(Empty),
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ExactDateSelection {
    pub start: String,
    pub end: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum SettingsPolicy {
    #[serde(rename = "requested_dates_only")]
    RequestedDatesOnly,
    #[serde(rename = "current_iphone_settings")]
    CurrentIphoneSettings,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ResponseMode {
    #[serde(rename = "raw_json")]
    RawJson,
    #[serde(rename = "write_files")]
    WriteFiles,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DetailLevel {
    Summary,
    Lossless,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CanonicalSelection {
    #[serde(rename = "metricIDs")]
    pub metric_ids: Vec<String>,
    pub categories: Vec<String>,
    #[serde(rename = "sourceIDs")]
    pub source_ids: Vec<String>,
    #[serde(rename = "objectPaths")]
    pub object_paths: Vec<String>,
    #[serde(rename = "fieldPointers")]
    pub field_pointers: Vec<String>,
    #[serde(rename = "allMetrics")]
    pub all_metrics: bool,
    #[serde(rename = "detailLevel")]
    pub detail_level: DetailLevel,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ExportDestination {
    #[serde(rename = "rootPath")]
    pub root_path: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ExportRequest {
    #[serde(rename = "protocolVersion")]
    pub protocol_version: i32,
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "createdAt", with = "time")]
    pub created_at: DateTime<Utc>,
    #[serde(rename = "dateSelection")]
    pub date_selection: DateSelection,
    #[serde(rename = "settingsPolicy")]
    pub settings_policy: SettingsPolicy,
    #[serde(rename = "responseMode")]
    pub response_mode: ResponseMode,
    #[serde(rename = "rawProfile", skip_serializing_if = "Option::is_none")]
    pub raw_profile: Option<RawProfile>,
    #[serde(rename = "canonicalSelection", skip_serializing_if = "Option::is_none")]
    pub canonical_selection: Option<CanonicalSelection>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub destination: Option<ExportDestination>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct PeerBinding {
    #[serde(rename = "sourceInstallationID")]
    pub source_installation_id: SwiftUuid,
    #[serde(rename = "destinationInstallationID")]
    pub destination_installation_id: SwiftUuid,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ExportAccepted {
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "acceptedAt", with = "time")]
    pub accepted_at: DateTime<Utc>,
    #[serde(rename = "peerBinding")]
    pub peer_binding: PeerBinding,
    #[serde(rename = "resolvedDateIdentifiers")]
    pub resolved_date_identifiers: Vec<String>,
    #[serde(rename = "sourceDeviceName")]
    pub source_device_name: String,
    #[serde(rename = "sourceTimeZoneIdentifier")]
    pub source_time_zone_identifier: String,
    #[serde(
        rename = "resolvedCanonicalSelection",
        skip_serializing_if = "Option::is_none"
    )]
    pub resolved_canonical_selection: Option<CanonicalSelection>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RawDayManifest {
    #[serde(rename = "job_id")]
    pub job_id: SwiftUuid,
    pub date: String,
    pub status: String,
    #[serde(rename = "capture_status", skip_serializing_if = "Option::is_none")]
    pub capture_status: Option<String>,
    #[serde(rename = "sample_count")]
    pub sample_count: i64,
    #[serde(rename = "record_count")]
    pub record_count: i64,
    #[serde(rename = "query_status_counts")]
    pub query_status_counts: std::collections::BTreeMap<String, i64>,
    #[serde(rename = "integrity_warning_count")]
    pub integrity_warning_count: i64,
    #[serde(rename = "integrity_warning_codes")]
    pub integrity_warning_codes: Vec<String>,
    #[serde(rename = "partial_failure_count")]
    pub partial_failure_count: i64,
    #[serde(rename = "partial_failure_types")]
    pub partial_failure_types: Vec<String>,
    #[serde(rename = "failure_code", skip_serializing_if = "Option::is_none")]
    pub failure_code: Option<String>,
    #[serde(rename = "health_data_byte_count")]
    pub health_data_byte_count: i64,
    #[serde(rename = "health_data_sha256", skip_serializing_if = "Option::is_none")]
    pub health_data_sha256: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum FileWriteMode {
    #[serde(rename = "overwrite")]
    Overwrite,
    #[serde(rename = "append")]
    Append,
    #[serde(rename = "merge_markdown")]
    MergeMarkdown,
    #[serde(rename = "merge_markdown_preserving_preamble")]
    MergeMarkdownPreservingPreamble,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct FileManifest {
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "fileID")]
    pub file_id: SwiftUuid,
    #[serde(rename = "relativePath")]
    pub relative_path: String,
    #[serde(rename = "byteCount")]
    pub byte_count: i64,
    pub sha256: String,
    #[serde(rename = "writeMode")]
    pub write_mode: FileWriteMode,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ExportProgress {
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "processedDays")]
    pub processed_days: i64,
    #[serde(rename = "totalDays")]
    pub total_days: i64,
    #[serde(rename = "currentDate", skip_serializing_if = "Option::is_none")]
    pub current_date: Option<String>,
    #[serde(rename = "committedPartitions")]
    pub committed_partitions: i64,
    #[serde(rename = "committedBytes")]
    pub committed_bytes: i64,
    pub message: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportFailureReason {
    #[serde(rename = "unsupported_peer")]
    UnsupportedPeer,
    #[serde(rename = "invalid_request")]
    InvalidRequest,
    #[serde(rename = "healthkit_unavailable")]
    HealthKitUnavailable,
    #[serde(rename = "healthkit_not_authorized")]
    HealthKitNotAuthorized,
    #[serde(rename = "protected_data_unavailable")]
    ProtectedDataUnavailable,
    #[serde(rename = "export_limit_reached")]
    ExportLimitReached,
    #[serde(rename = "request_in_progress")]
    RequestInProgress,
    #[serde(rename = "cancelled")]
    Cancelled,
    #[serde(rename = "internal_failure")]
    InternalFailure,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ExportFailure {
    #[serde(rename = "jobID", skip_serializing_if = "Option::is_none")]
    pub job_id: Option<SwiftUuid>,
    pub reason: ExportFailureReason,
    pub message: String,
}

#[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
pub struct RequestFingerprint {
    pub version: i32,
    pub sha256: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferSession {
    #[serde(rename = "protocolVersion")]
    pub protocol_version: i32,
    #[serde(rename = "sessionID")]
    pub session_id: SwiftUuid,
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "requestFingerprint")]
    pub request_fingerprint: RequestFingerprint,
    #[serde(rename = "peerBinding")]
    pub peer_binding: PeerBinding,
    #[serde(rename = "partitionTargetBytes")]
    pub partition_target_bytes: i64,
    #[serde(rename = "createdAt", with = "time")]
    pub created_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
pub struct TransferItemSegment {
    #[serde(rename = "itemID")]
    pub item_id: String,
    pub offset: i64,
    #[serde(rename = "itemByteCount")]
    pub item_byte_count: i64,
    #[serde(rename = "isFinalSegment")]
    pub is_final_segment: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
pub struct TransferPartition {
    pub index: i64,
    #[serde(rename = "transferID")]
    pub transfer_id: SwiftUuid,
    #[serde(rename = "sourceDates")]
    pub source_dates: Vec<String>,
    #[serde(rename = "byteCount")]
    pub byte_count: i64,
    #[serde(rename = "chunkCount")]
    pub chunk_count: i64,
    pub sha256: String,
    #[serde(rename = "previousSHA256", skip_serializing_if = "Option::is_none")]
    pub previous_sha256: Option<String>,
    #[serde(rename = "itemSegment", skip_serializing_if = "Option::is_none")]
    pub item_segment: Option<TransferItemSegment>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferOpen {
    pub session: TransferSession,
    pub partition: TransferPartition,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum TransferDispositionKind {
    #[serde(rename = "needed")]
    Needed,
    #[serde(rename = "already_committed")]
    AlreadyCommitted,
    #[serde(rename = "rejected")]
    Rejected,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferDisposition {
    #[serde(rename = "sessionID")]
    pub session_id: SwiftUuid,
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "partitionIndex")]
    pub partition_index: i64,
    #[serde(rename = "partitionSHA256")]
    pub partition_sha256: String,
    pub disposition: TransferDispositionKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferChunk {
    #[serde(rename = "transferID")]
    pub transfer_id: SwiftUuid,
    pub sequence: i64,
    #[serde(with = "data")]
    pub data: Vec<u8>,
    pub sha256: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferChunkAcknowledgement {
    #[serde(rename = "transferID")]
    pub transfer_id: SwiftUuid,
    pub sequence: i64,
    pub accepted: bool,
    pub sha256: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferPartitionComplete {
    #[serde(rename = "sessionID")]
    pub session_id: SwiftUuid,
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "partitionIndex")]
    pub partition_index: i64,
    #[serde(rename = "transferID")]
    pub transfer_id: SwiftUuid,
    #[serde(rename = "partitionSHA256")]
    pub partition_sha256: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferPartitionAcknowledgement {
    #[serde(rename = "sessionID")]
    pub session_id: SwiftUuid,
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "partitionIndex")]
    pub partition_index: i64,
    #[serde(rename = "transferID")]
    pub transfer_id: SwiftUuid,
    #[serde(rename = "partitionSHA256")]
    pub partition_sha256: String,
    pub accepted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ExportOutcome {
    pub status: String,
    #[serde(rename = "successCount")]
    pub success_count: i64,
    #[serde(rename = "totalCount")]
    pub total_count: i64,
    #[serde(rename = "failedDateIdentifiers")]
    pub failed_date_identifiers: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferFinalize {
    #[serde(rename = "sessionID")]
    pub session_id: SwiftUuid,
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    #[serde(rename = "requestFingerprint")]
    pub request_fingerprint: RequestFingerprint,
    #[serde(rename = "totalPartitions")]
    pub total_partitions: i64,
    #[serde(rename = "totalBytes")]
    pub total_bytes: i64,
    #[serde(
        rename = "finalPartitionSHA256",
        skip_serializing_if = "Option::is_none"
    )]
    pub final_partition_sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub outcome: Option<ExportOutcome>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TransferFinalAcknowledgement {
    #[serde(rename = "sessionID")]
    pub session_id: SwiftUuid,
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
    pub accepted: bool,
    #[serde(rename = "totalPartitions")]
    pub total_partitions: i64,
    #[serde(rename = "totalBytes")]
    pub total_bytes: i64,
    #[serde(
        rename = "finalPartitionSHA256",
        skip_serializing_if = "Option::is_none"
    )]
    pub final_partition_sha256: Option<String>,
    #[serde(rename = "responseByteCount", skip_serializing_if = "Option::is_none")]
    pub response_byte_count: Option<i64>,
    #[serde(rename = "responseSHA256", skip_serializing_if = "Option::is_none")]
    pub response_sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct JobIdPayload {
    #[serde(rename = "jobID")]
    pub job_id: SwiftUuid,
}
