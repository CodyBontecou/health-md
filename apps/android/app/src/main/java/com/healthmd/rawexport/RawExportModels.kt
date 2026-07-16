package com.healthmd.rawexport

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
enum class ExportMode { COMPATIBILITY, RAW_SNAPSHOT }

@Serializable
enum class RawExportFormat { JSON, NDJSON }

@Serializable
enum class RawSnapshotScope { SELECTED_RECORD_TYPES, ALL_AUTHORIZED_SUPPORTED_DATA }

@Serializable
enum class RawSnapshotStatus { PENDING, RUNNING, COMPLETE, PARTIAL, CANCELLED, FAILED }

@Serializable
enum class RawIssueSeverity { INFO, WARNING, ERROR }

@Serializable
enum class RawRouteState { CONSENT_REQUIRED, NO_DATA, DATA }

@Serializable
data class RawInstant(
    val epochSecond: Long,
    val nano: Int,
)

@Serializable
data class RawEnumValue(
    val raw: Int,
    val label: String,
)

@Serializable
data class RawQuantity(
    /** The SDK value in the documented canonical unit. */
    val number: Double,
    /** Locale-independent round-trippable decimal form of [number]. */
    val decimal: String,
    val type: String,
    val unit: String,
)

@Serializable
data class RawDevice(
    val type: RawEnumValue,
    val manufacturer: String? = null,
    val model: String? = null,
)

@Serializable
data class RawMetadata(
    val id: String,
    val clientRecordId: String? = null,
    val clientRecordVersion: Long,
    val lastModifiedTime: RawInstant,
    val dataOriginPackageName: String,
    val recordingMethod: RawEnumValue,
    val device: RawDevice? = null,
)

@Serializable
data class RawSnapshotRequest(
    val format: RawExportFormat,
    val scope: RawSnapshotScope,
    val startTime: RawInstant,
    val endTime: RawInstant,
    val selectedMetricIds: Set<String> = emptySet(),
    val pageSize: Int = 500,
    val includeExerciseRoutes: Boolean = true,
) {
    init {
        require(pageSize in 1..5_000) { "pageSize must be between 1 and 5000" }
        require(
            startTime.epochSecond < endTime.epochSecond ||
                startTime.epochSecond == endTime.epochSecond && startTime.nano < endTime.nano,
        ) { "startTime must be before endTime" }
    }
}

@Serializable
data class RawProviderCapabilities(
    val sdkVersion: String = "androidx.health.connect:connect-client:1.2.0-alpha02",
    val available: Boolean,
    val grantedPermissions: Set<String> = emptySet(),
    val availableFeatures: Set<String> = emptySet(),
    val historicalReadGranted: Boolean = false,
    val nonTransactional: Boolean = true,
    val preservesSourceUnits: Boolean = false,
    val preservesUnknownSdkFields: Boolean = false,
)

@Serializable
data class RawIssue(
    val code: String,
    val message: String,
    val severity: RawIssueSeverity = RawIssueSeverity.WARNING,
    val recordType: String? = null,
    val retryable: Boolean = false,
)

@Serializable
data class RawRecord(
    val wireType: String,
    val nativeIdentity: String,
    /** Medical resources have no temporal field and therefore use null, never a fabricated time. */
    val startTime: RawInstant? = null,
    val endTime: RawInstant? = null,
    /** Null means the source explicitly omitted its original zone offset. */
    val startZoneOffsetSeconds: Int? = null,
    /** Null means the source explicitly omitted its original zone offset. */
    val endZoneOffsetSeconds: Int? = null,
    /** Medical resources have no Record metadata and therefore use null. */
    val metadata: RawMetadata? = null,
    val fields: JsonObject,
    val hash: String,
)

@Serializable
data class RawSnapshotHeader(
    val schema: String = "healthmd.raw-snapshot",
    val version: Int = 1,
    val snapshotId: String,
    val createdAt: RawInstant,
    val request: RawSnapshotRequest,
    val capabilities: RawProviderCapabilities,
)

@Serializable
data class RawTypeCount(val wireType: String, val count: Long)

@Serializable
data class RawSnapshotManifest(
    val schema: String = "healthmd.raw-snapshot.manifest",
    val version: Int = 1,
    val snapshotId: String,
    val status: RawSnapshotStatus,
    val recordCount: Long,
    val issueCount: Long,
    val duplicateCount: Long,
    val typeCounts: List<RawTypeCount>,
    val logicalChecksumSha256: String,
    /** Hash of this manifest with this field and artifactChecksumSha256 omitted. */
    val manifestChecksumSha256: String,
    /** Filled in the returned result after the completed artifact has been closed. */
    val artifactChecksumSha256: String? = null,
)

@Serializable
data class RawSnapshotDocument(
    val header: RawSnapshotHeader,
    val records: List<RawRecord>,
    val issues: List<RawIssue>,
    val manifest: RawSnapshotManifest,
)

@Serializable
sealed class RawExportItem {
    @Serializable
    @SerialName("status")
    data class Status(val status: RawSnapshotStatus, val message: String? = null) : RawExportItem()

    @Serializable
    @SerialName("record")
    data class Record(val record: RawRecord) : RawExportItem()

    @Serializable
    @SerialName("issue")
    data class Issue(val issue: RawIssue) : RawExportItem()
}

@Serializable
data class RawExportResult(
    val snapshotId: String,
    val finalLocation: String,
    val format: RawExportFormat,
    val manifest: RawSnapshotManifest,
    val artifactChecksumSha256: String,
    val bytesWritten: Long,
)
