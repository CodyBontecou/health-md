package com.healthmd.direct.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

const val DIRECT_PORT: Int = 17_647
const val TRANSPORT_PROTOCOL_VERSION: Int = 1
const val ANDROID_PAIRING_PROTOCOL_VERSION: Int = 2
const val ANDROID_APPLICATION_PROTOCOL_VERSION: Int = 2
const val MAXIMUM_PACKET_BYTES: Int = 2 * 1024 * 1024
const val MAXIMUM_CHUNK_BYTES: Int = 512 * 1024
const val MINIMUM_PARTITION_BYTES: Long = 32L * 1024 * 1024
const val PREFERRED_PARTITION_BYTES: Long = 48L * 1024 * 1024
const val MAXIMUM_PARTITION_BYTES: Long = 64L * 1024 * 1024
const val JOB_LIFETIME_SECONDS: Long = 7L * 24 * 60 * 60

@Serializable
data class EncryptedFrame(
    val nonce: String,
    val ciphertext: String,
    val tag: String,
)

data class TrustedListener(
    val installationId: String,
    val displayName: String,
    val reconnectSecret: ByteArray,
    val host: String,
    val port: Int,
)

data class AuthenticatedListener(
    val installationId: String,
    val displayName: String,
    val reconnectSecret: ByteArray,
)

@Serializable
data class TransferCapabilities(
    @SerialName("protocolVersions") val protocolVersions: List<Int> = listOf(1),
    @SerialName("binaryFrameVersions") val binaryFrameVersions: List<Int> = listOf(1),
    @SerialName("minimumPartitionBytes") val minimumPartitionBytes: Long = MINIMUM_PARTITION_BYTES,
    @SerialName("preferredPartitionBytes") val preferredPartitionBytes: Long = PREFERRED_PARTITION_BYTES,
    @SerialName("maximumPartitionBytes") val maximumPartitionBytes: Long = MAXIMUM_PARTITION_BYTES,
    @SerialName("maximumInFlightChunks") val maximumInFlightChunks: Int = 4,
)

@Serializable
data class NegotiationHello(
    @SerialName("protocolVersions") val protocolVersions: List<Int>,
    val platform: String,
    @SerialName("installationID") val installationId: String,
    @SerialName("supportedRawProfiles") val supportedRawProfiles: List<String>,
    @SerialName("supportsDurableJobs") val supportsDurableJobs: Boolean,
    @SerialName("supportsCanonicalExtraction") val supportsCanonicalExtraction: Boolean,
    val transfer: TransferCapabilities,
)

@Serializable
enum class ProductId {
    @SerialName("android_provider_native_snapshot_v1")
    ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1,

    @SerialName("generated_files_v1")
    GENERATED_FILES_V1,

    @SerialName("android_daily_records_v1")
    ANDROID_DAILY_RECORDS_V1,
}

@Serializable
enum class ArtifactFormat {
    @SerialName("json") JSON,
    @SerialName("ndjson") NDJSON,
    @SerialName("markdown") MARKDOWN,
    @SerialName("csv") CSV,
    @SerialName("obsidian_bases") OBSIDIAN_BASES,
}

@Serializable
enum class SettingsPolicy {
    @SerialName("requested_scope") REQUESTED_SCOPE,
    @SerialName("saved_device_settings") SAVED_DEVICE_SETTINGS,
}

@Serializable
data class ArtifactSchema(
    val id: String,
    val major: Int,
)

@Serializable
data class SourceIdentity(
    @SerialName("installation_id") val installationId: String,
    val platform: String = "android",
    @SerialName("display_name") val displayName: String,
    @SerialName("app_version") val appVersion: String,
)

@Serializable
data class ProductCapability(
    @SerialName("product_id") val productId: ProductId,
    @SerialName("artifact_schema") val artifactSchema: ArtifactSchema,
    val formats: List<ArtifactFormat>,
    val providers: List<String> = emptyList(),
    @SerialName("settings_policies") val settingsPolicies: List<SettingsPolicy> = emptyList(),
    @SerialName("supports_resume") val supportsResume: Boolean = true,
)

@Serializable
data class ProtocolLimits(
    @SerialName("maximum_control_bytes") val maximumControlBytes: Int = 256 * 1024,
    @SerialName("maximum_chunk_bytes") val maximumChunkBytes: Int = MAXIMUM_CHUNK_BYTES,
    @SerialName("preferred_partition_bytes") val preferredPartitionBytes: Long = PREFERRED_PARTITION_BYTES,
)

@Serializable
data class SourceHello(
    val source: SourceIdentity,
    val products: List<ProductCapability>,
    val limits: ProtocolLimits = ProtocolLimits(),
)

@Serializable
data class StatusRequest(
    @SerialName("requested_at") val requestedAt: String,
)

@Serializable
data class SourceStatus(
    val source: SourceIdentity,
    @SerialName("app_active") val appActive: Boolean,
    @SerialName("protected_data_available") val protectedDataAvailable: Boolean,
    @SerialName("export_in_progress") val exportInProgress: Boolean,
    @SerialName("available_products") val availableProducts: List<ProductId>,
    @SerialName("active_job_id") val activeJobId: String? = null,
    val message: String? = null,
)

@Serializable
data class ExportRequest(
    @SerialName("job_id") val jobId: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("source_installation_id") val sourceInstallationId: String,
    @SerialName("date_selection") val dateSelection: JsonObject,
    val product: JsonObject,
    val destination: DestinationBinding? = null,
)

@Serializable
data class DestinationBinding(
    @SerialName("binding_sha256") val bindingSha256: String,
    @SerialName("display_name") val displayName: String,
)

@Serializable
data class PeerBinding(
    @SerialName("source_installation_id") val sourceInstallationId: String,
    @SerialName("destination_installation_id") val destinationInstallationId: String,
)

@Serializable
data class ResolvedRange(
    @SerialName("start_date") val startDate: String,
    @SerialName("end_date") val endDate: String,
    @SerialName("time_zone_id") val timeZoneId: String,
)

@Serializable
data class ExportAccepted(
    @SerialName("job_id") val jobId: String,
    @SerialName("accepted_at") val acceptedAt: String,
    @SerialName("peer_binding") val peerBinding: PeerBinding,
    @SerialName("product_id") val productId: ProductId,
    @SerialName("resolved_range") val resolvedRange: ResolvedRange,
    @SerialName("provider_id") val providerId: String? = null,
    @SerialName("settings_snapshot_sha256") val settingsSnapshotSha256: String? = null,
    @SerialName("request_fingerprint") val requestFingerprint: String,
)

@Serializable
enum class ExportPhase {
    @SerialName("preparing") PREPARING,
    @SerialName("reading") READING,
    @SerialName("validating") VALIDATING,
    @SerialName("transferring") TRANSFERRING,
    @SerialName("awaiting_final_acknowledgement") AWAITING_FINAL_ACKNOWLEDGEMENT,
    @SerialName("completed") COMPLETED,
}

@Serializable
data class ExportProgress(
    @SerialName("job_id") val jobId: String,
    val phase: ExportPhase,
    @SerialName("completed_units") val completedUnits: Long,
    @SerialName("total_units") val totalUnits: Long,
    @SerialName("committed_bytes") val committedBytes: Long,
    val message: String,
)

@Serializable
enum class ErrorCode {
    @SerialName("incompatible_protocol") INCOMPATIBLE_PROTOCOL,
    @SerialName("authentication_failed") AUTHENTICATION_FAILED,
    @SerialName("trust_missing") TRUST_MISSING,
    @SerialName("unsupported_product") UNSUPPORTED_PRODUCT,
    @SerialName("unsupported_schema") UNSUPPORTED_SCHEMA,
    @SerialName("unsupported_provider") UNSUPPORTED_PROVIDER,
    @SerialName("invalid_request") INVALID_REQUEST,
    @SerialName("clock_skew") CLOCK_SKEW,
    @SerialName("permission_required") PERMISSION_REQUIRED,
    @SerialName("device_locked") DEVICE_LOCKED,
    @SerialName("source_unavailable") SOURCE_UNAVAILABLE,
    @SerialName("busy") BUSY,
    @SerialName("quota_exhausted") QUOTA_EXHAUSTED,
    @SerialName("staging_failed") STAGING_FAILED,
    @SerialName("validation_failed") VALIDATION_FAILED,
    @SerialName("spool_missing_restart_required") SPOOL_MISSING_RESTART_REQUIRED,
    @SerialName("transfer_failed") TRANSFER_FAILED,
    @SerialName("destination_changed") DESTINATION_CHANGED,
    @SerialName("destination_commit_failed") DESTINATION_COMMIT_FAILED,
    @SerialName("cancelled") CANCELLED,
    @SerialName("job_expired") JOB_EXPIRED,
    @SerialName("internal_failure") INTERNAL_FAILURE,
}

@Serializable
data class ExportFailure(
    @SerialName("job_id") val jobId: String? = null,
    val code: ErrorCode,
    val phase: ExportPhase,
    val retryable: Boolean,
    @SerialName("public_message") val publicMessage: String,
    val details: Map<String, List<String>> = emptyMap(),
)

@Serializable
enum class ArtifactKind {
    @SerialName("raw_snapshot") RAW_SNAPSHOT,
    @SerialName("generated_file") GENERATED_FILE,
    @SerialName("daily_records") DAILY_RECORDS,
}

@Serializable
enum class FileWriteMode {
    @SerialName("overwrite") OVERWRITE,
    @SerialName("append") APPEND,
    @SerialName("merge_markdown") MERGE_MARKDOWN,
    @SerialName("merge_markdown_preserving_preamble") MERGE_MARKDOWN_PRESERVING_PREAMBLE,
}

@Serializable
data class ArtifactManifest(
    @SerialName("job_id") val jobId: String,
    @SerialName("artifact_id") val artifactId: String,
    val kind: ArtifactKind,
    val schema: ArtifactSchema,
    @SerialName("media_type") val mediaType: String,
    @SerialName("byte_count") val byteCount: Long,
    val sha256: String,
    @SerialName("logical_checksum_sha256") val logicalChecksumSha256: String? = null,
    @SerialName("relative_path") val relativePath: String? = null,
    @SerialName("write_mode") val writeMode: FileWriteMode? = null,
    @SerialName("snapshot_status") val snapshotStatus: String? = null,
    @SerialName("provider_id") val providerId: String? = null,
)

@Serializable
data class TransferSession(
    @SerialName("session_id") val sessionId: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("request_fingerprint") val requestFingerprint: String,
    @SerialName("peer_binding") val peerBinding: PeerBinding,
    @SerialName("partition_target_bytes") val partitionTargetBytes: Long,
    @SerialName("created_at") val createdAt: String,
)

@Serializable
data class TransferPartition(
    val index: Long,
    @SerialName("transfer_id") val transferId: String,
    @SerialName("artifact_id") val artifactId: String,
    @SerialName("artifact_offset") val artifactOffset: Long,
    @SerialName("byte_count") val byteCount: Long,
    @SerialName("chunk_count") val chunkCount: Long,
    val sha256: String,
    @SerialName("previous_sha256") val previousSha256: String? = null,
)

@Serializable
data class TransferOpen(
    val session: TransferSession,
    val partition: TransferPartition,
)

@Serializable
enum class TransferDispositionKind {
    @SerialName("needed") NEEDED,
    @SerialName("already_committed") ALREADY_COMMITTED,
    @SerialName("rejected") REJECTED,
}

@Serializable
data class TransferDisposition(
    @SerialName("session_id") val sessionId: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("partition_index") val partitionIndex: Long,
    @SerialName("partition_sha256") val partitionSha256: String,
    val disposition: TransferDispositionKind,
    val message: String? = null,
)

@Serializable
data class TransferChunkAcknowledgement(
    @SerialName("transfer_id") val transferId: String,
    val sequence: Int,
    val accepted: Boolean,
    val sha256: String,
    val message: String? = null,
)

@Serializable
data class TransferPartitionComplete(
    @SerialName("session_id") val sessionId: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("partition_index") val partitionIndex: Long,
    @SerialName("transfer_id") val transferId: String,
    @SerialName("partition_sha256") val partitionSha256: String,
)

@Serializable
data class TransferPartitionAcknowledgement(
    @SerialName("session_id") val sessionId: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("partition_index") val partitionIndex: Long,
    @SerialName("transfer_id") val transferId: String,
    @SerialName("partition_sha256") val partitionSha256: String,
    val accepted: Boolean,
    val message: String? = null,
)

@Serializable
data class TransferFinalize(
    @SerialName("session_id") val sessionId: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("request_fingerprint") val requestFingerprint: String,
    @SerialName("total_partitions") val totalPartitions: Long,
    @SerialName("total_bytes") val totalBytes: Long,
    @SerialName("final_partition_sha256") val finalPartitionSha256: String? = null,
)

@Serializable
data class TransferFinalAcknowledgement(
    @SerialName("session_id") val sessionId: String,
    @SerialName("job_id") val jobId: String,
    val accepted: Boolean,
    @SerialName("total_partitions") val totalPartitions: Long,
    @SerialName("total_bytes") val totalBytes: Long,
    @SerialName("final_partition_sha256") val finalPartitionSha256: String? = null,
    @SerialName("response_byte_count") val responseByteCount: Long? = null,
    @SerialName("response_sha256") val responseSha256: String? = null,
    val message: String? = null,
)

@Serializable
data class JobPayload(
    @SerialName("job_id") val jobId: String,
)
