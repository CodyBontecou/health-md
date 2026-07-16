package com.healthmd.rawchanges

import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawIssue
import com.healthmd.rawexport.RawProviderCapabilities
import com.healthmd.rawexport.RawRecord
import com.healthmd.rawexport.RawSnapshotStatus
import com.healthmd.rawexport.RawTypeCount
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Independent incremental archive contract. This is not a raw snapshot or compatibility export. */
@Serializable
data class RawChangesScope(
    val recordTypeKeys: Set<String>,
    val dataOriginPackageNames: Set<String> = emptySet(),
) {
    init {
        require(recordTypeKeys.isNotEmpty()) { "At least one changes-eligible record type is required." }
        require(recordTypeKeys.none(String::isBlank))
        require(dataOriginPackageNames.none(String::isBlank))
    }

    fun canonical(): RawChangesScope = copy(
        recordTypeKeys = recordTypeKeys.toSortedSet(),
        dataOriginPackageNames = dataOriginPackageNames.toSortedSet(),
    )
}

@Serializable
data class RawChangesTokenSemantics(
    val generatedAt: RawInstant,
    val generatedBeforeBaseSnapshot: Boolean,
    val validityDays: Int = 30,
    val opaqueTokenExported: Boolean = false,
    val advancesOnlyAfterDurability: Boolean = true,
)

@Serializable
data class RawChangesHeader(
    val schema: String = "healthmd.raw-changes",
    val version: Int = 1,
    val archiveId: String,
    val chainId: String,
    val sequence: Long,
    val previousArchiveLogicalHash: String?,
    val scopeHash: String,
    val recordTypeKeys: List<String>,
    val dataOriginPackageNames: List<String>,
    val provider: String = "Android Health Connect",
    val providerSdk: String = "androidx.health.connect:connect-client:1.2.0-alpha02",
    val createdAt: RawInstant,
    val capabilities: RawProviderCapabilities,
    val tokenSemantics: RawChangesTokenSemantics,
    val consistency: String = "non_transactional_at_least_once",
)

@Serializable
sealed class RawChangeEvent {
    abstract val ordinal: Long
    abstract val eventHash: String

    @Serializable
    @SerialName("upsertion")
    data class Upsertion(
        override val ordinal: Long,
        val record: RawRecord,
        override val eventHash: String,
    ) : RawChangeEvent()

    @Serializable
    @SerialName("deletion")
    data class Deletion(
        override val ordinal: Long,
        val nativeRecordId: String,
        val wireType: String?,
        val typeKey: String?,
        val dataOriginPackageName: String?,
        val lastKnownRecordHash: String?,
        val observedAt: RawInstant,
        override val eventHash: String,
    ) : RawChangeEvent()
}

@Serializable
enum class RawChangesTypeStatus {
    @SerialName("exported") EXPORTED,
    @SerialName("not_selected") NOT_SELECTED,
    @SerialName("permission_not_granted") PERMISSION_NOT_GRANTED,
    @SerialName("feature_unavailable") FEATURE_UNAVAILABLE,
    @SerialName("unsupported_changes_api") UNSUPPORTED_CHANGES_API,
}

@Serializable
data class RawChangesTypeReport(
    val typeKey: String,
    val wireType: String,
    val status: RawChangesTypeStatus,
    val upsertionCount: Long = 0,
    val deletionCount: Long = 0,
    val unknownDeletionCount: Long = 0,
    val permission: String? = null,
    val feature: String? = null,
    val message: String? = null,
)

@Serializable
data class RawChangesManifest(
    val schema: String = "healthmd.raw-changes.manifest",
    val version: Int = 1,
    val archiveId: String,
    val chainId: String,
    val sequence: Long,
    val status: String = "COMPLETE",
    val completedAt: RawInstant,
    val eventCount: Long,
    val upsertionCount: Long,
    val deletionCount: Long,
    val unknownDeletionCount: Long,
    val issueCount: Long,
    val pageCount: Long,
    val typeCounts: List<RawTypeCount>,
    val typeReports: List<RawChangesTypeReport>,
    val unsupportedCategories: List<String> = listOf("cloud_providers", "personal_health_record"),
    val logicalChecksumSha256: String,
    val manifestChecksumSha256: String,
    val artifactChecksumSha256: String? = null,
)

@Serializable
data class RawChangesDocument(
    val header: RawChangesHeader,
    val events: List<RawChangeEvent>,
    val issues: List<RawIssue>,
    val manifest: RawChangesManifest,
)

data class RawChangesArchiveResult(
    val archiveId: String,
    val chainId: String,
    val sequence: Long,
    val location: String,
    val logicalChecksumSha256: String,
    val artifactChecksumSha256: String,
    val bytesWritten: Long,
)

sealed interface RawChangesResult {
    data class Complete(val archive: RawChangesArchiveResult) : RawChangesResult
    /** No archive was created and no coverage is claimed for this unavailable scope. */
    data class UnavailableScope(
        val recordTypeKeys: List<String>,
        val requiredFeatures: List<String>,
        val providerUnavailable: Boolean = false,
    ) : RawChangesResult
    data class RebaseRequired(val chainId: String?, val scopeHash: String, val reason: String = "changes_token_expired_or_invalid") : RawChangesResult
    data class BootstrapRequired(val scopeHash: String) : RawChangesResult
    data class ScopeMismatch(val expectedScopeHash: String, val actualScopeHash: String) : RawChangesResult
    /** Another recover/read/commit operation owns this scope or its durable state changed. */
    data class Conflict(val scopeHash: String, val reason: String = "raw_changes_scope_busy_or_changed") : RawChangesResult
}

enum class RawBaseHistoricalCoverage {
    /** Every record readable at bootstrap time, without a lower or upper date bound, within the exact receipt scope. */
    UNBOUNDED_ALL_READABLE_WITHIN_SCOPE,
    BOUNDED_DATE_RANGE,
    INCOMPLETE,
}

/** Verifiable proof for the exact raw snapshot used as an incremental chain's base. */
data class RawBaseSnapshotReceipt(
    val snapshotId: String,
    val schema: String,
    val version: Int,
    val status: RawSnapshotStatus,
    val recordTypeKeys: Set<String>,
    val dataOriginPackageNames: Set<String>,
    val historicalCoverage: RawBaseHistoricalCoverage,
    val format: RawExportFormat,
    val artifactPath: String,
    val sidecarPath: String,
    val logicalChecksumSha256: String,
    val artifactChecksumSha256: String,
) {
    init {
        require(snapshotId.isNotBlank())
        require(recordTypeKeys.isNotEmpty() && recordTypeKeys.none(String::isBlank))
        require(dataOriginPackageNames.none(String::isBlank))
        require(artifactPath.isNotBlank() && sidecarPath.isNotBlank())
        require(logicalChecksumSha256.matches(Regex("[0-9a-f]{64}")))
        require(artifactChecksumSha256.matches(Regex("[0-9a-f]{64}")))
    }
}

interface RawBaseSnapshotIndex {
    /** Must be called for each durable base-snapshot RawRecord; records use the snapshot mapper unchanged. */
    fun record(record: RawRecord)
}

fun interface RawBaseSnapshotStep {
    suspend fun create(index: RawBaseSnapshotIndex): RawBaseSnapshotReceipt
}
