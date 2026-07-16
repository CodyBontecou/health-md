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
enum class RawTypeStatus {
    @SerialName("exported") EXPORTED,
    @SerialName("not_selected") NOT_SELECTED,
    @SerialName("permission_not_granted") PERMISSION_NOT_GRANTED,
    @SerialName("feature_unavailable") FEATURE_UNAVAILABLE,
    @SerialName("history_permission_missing") HISTORY_PERMISSION_MISSING,
    @SerialName("read_error") READ_ERROR,
    @SerialName("unsupported_by_provider") UNSUPPORTED_BY_PROVIDER,
}

@Serializable
enum class RawRangeBehavior {
    @SerialName("instant") INSTANT,
    @SerialName("overlap") OVERLAP,
    @SerialName("unbounded_non_temporal") UNBOUNDED_NON_TEMPORAL,
}

@Serializable
enum class RawRecordKind {
    @SerialName("health_connect_record") HEALTH_CONNECT_RECORD,
    @SerialName("provider_payload") PROVIDER_PAYLOAD,
}

@Serializable
enum class RawProviderFidelity {
    @SerialName("native_api_payload") NATIVE_API_PAYLOAD,
    @SerialName("normalized_only") NORMALIZED_ONLY,
    @SerialName("unsupported") UNSUPPORTED,
    @SerialName("health_connect_api_projected") HEALTH_CONNECT_API_PROJECTED,
}

@Serializable
enum class RawPaginationSupport {
    @SerialName("none") NONE,
    @SerialName("next_token") NEXT_TOKEN,
    @SerialName("fan_out") FAN_OUT,
}

@Serializable
data class RawInstant(
    val epochSecond: Long,
    val nano: Int,
    /** Additive exact representation for clients whose number type cannot safely hold Int64. */
    val epochSecondExact: String = epochSecond.toString(),
) {
    init {
        require(nano in 0..999_999_999) { "nano must be between 0 and 999999999" }
        require(epochSecondExact == epochSecond.toString()) { "epochSecondExact must match epochSecond" }
    }
}

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
) {
    init {
        require(number.isFinite()) { "quantity number must be finite" }
        val parsed = decimal.toDoubleOrNull()
        require(parsed != null && parsed.isFinite() && parsed.toRawBits() == number.toRawBits()) {
            "quantity decimal must round-trip to number"
        }
    }
}

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
    /** Additive exact representation for clients whose number type cannot safely hold Int64. */
    val clientRecordVersionExact: String = clientRecordVersion.toString(),
    val lastModifiedTime: RawInstant,
    val dataOriginPackageName: String,
    val recordingMethod: RawEnumValue,
    val device: RawDevice? = null,
) {
    init {
        require(clientRecordVersionExact == clientRecordVersion.toString()) {
            "clientRecordVersionExact must match clientRecordVersion"
        }
    }
}

@Serializable
data class RawSnapshotRequest(
    val format: RawExportFormat,
    val scope: RawSnapshotScope,
    val startTime: RawInstant,
    val endTime: RawInstant,
    val selectedMetricIds: Set<String> = emptySet(),
    val pageSize: Int = 500,
    val includeExerciseRoutes: Boolean = true,
    /** IANA zone captured once when calendar-day boundaries were converted to instants. */
    val calendarZoneId: String? = null,
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
    /** Additive source declaration. Defaults retain v1 Health Connect compatibility. */
    val providerId: String = "health_connect",
    val fidelityLevel: RawProviderFidelity = RawProviderFidelity.HEALTH_CONNECT_API_PROJECTED,
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
data class RawSourceDescriptor(
    val providerId: String = "health_connect",
    val fidelityLevel: RawProviderFidelity = RawProviderFidelity.HEALTH_CONNECT_API_PROJECTED,
    /** Logical adapter capability key, never a URL. */
    val endpointKey: String? = null,
)

@Serializable
data class RawProviderPayload(
    val providerId: String,
    val endpointKey: String,
    /** Opaque provider-scoped digest. It is never a URL or provider path. */
    val endpointIdentifier: String,
    val queryMetadata: Map<String, String> = emptyMap(),
    val fetchedAt: RawInstant,
    val httpStatus: Int,
    val contentType: String? = null,
    val charset: String,
    val responseHeaders: Map<String, String> = emptyMap(),
    val pageOrdinal: Int,
    /** Exact successful response bytes. This is the authoritative representation. */
    val responseBytesBase64: String,
    /** Exact decoded text when the declared charset decoded strictly and the JSON was valid. */
    val responseText: String? = null,
    /** SHA-256 of the decoded bytes in responseBytesBase64. */
    val responseSha256: String,
    /** True when the provider endpoint documents a server-produced summary/aggregate. */
    val serverAggregation: Boolean = false,
)

@Serializable
data class RawRecord(
    val wireType: String,
    val nativeIdentity: String,
    /** Additive discriminator; omitted callers decode as the original Health Connect shape. */
    val recordKind: RawRecordKind = RawRecordKind.HEALTH_CONNECT_RECORD,
    val source: RawSourceDescriptor = RawSourceDescriptor(),
    /** Medical resources have no temporal field and therefore use null, never a fabricated time. */
    val startTime: RawInstant? = null,
    val endTime: RawInstant? = null,
    /** Null means the source explicitly omitted its original zone offset. */
    val startZoneOffsetSeconds: Int? = null,
    /** Null means the source explicitly omitted its original zone offset. */
    val endZoneOffsetSeconds: Int? = null,
    /** Medical resources and provider pages have no Health Connect Record metadata. */
    val metadata: RawMetadata? = null,
    val fields: JsonObject,
    val providerPayload: RawProviderPayload? = null,
    /** Provider payload records use the exact native response-byte SHA-256. */
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
data class RawTypeReport(
    val typeKey: String,
    val wireType: String,
    val status: RawTypeStatus,
    val recordCount: Long = 0,
    val issueCount: Long = 0,
    val permission: String? = null,
    val feature: String? = null,
    val rangeBehavior: RawRangeBehavior,
    val message: String? = null,
    val providerId: String = "health_connect",
    val pagination: RawPaginationSupport = RawPaginationSupport.NONE,
    val serverAggregation: Boolean = false,
)

@Serializable
data class RawSnapshotManifest(
    val schema: String = "healthmd.raw-snapshot.manifest",
    val version: Int = 1,
    val snapshotId: String,
    val status: RawSnapshotStatus,
    /** Time final provider processing and artifact accounting completed, immediately before manifest emission. */
    val completedAt: RawInstant,
    val recordCount: Long,
    val issueCount: Long,
    val duplicateCount: Long,
    val identityCollisionCount: Long,
    val typeCounts: List<RawTypeCount>,
    val typeReports: List<RawTypeReport>,
    val logicalChecksumSha256: String,
    /** Hash of this manifest with this field and artifactChecksumSha256 omitted. */
    val manifestChecksumSha256: String,
    /** Filled in the returned result after the completed artifact has been closed. */
    val artifactChecksumSha256: String? = null,
) {
    init {
        require(status == RawSnapshotStatus.COMPLETE || status == RawSnapshotStatus.PARTIAL || status == RawSnapshotStatus.FAILED) {
            "A final manifest cannot carry a transient or cancelled status"
        }
    }
}

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

    @Serializable
    @SerialName("type_report")
    data class TypeReport(val report: RawTypeReport) : RawExportItem()
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
