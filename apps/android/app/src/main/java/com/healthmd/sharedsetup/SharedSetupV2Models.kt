package com.healthmd.sharedsetup

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

const val SHARED_SETUP_V2_VERSION: Int = 2
const val SHARED_SETUP_V2_MAX_BYTES: Int = 4 * 1024 * 1024
const val SHARED_SETUP_V2_MAX_PROFILES: Int = 100

/**
 * Closed Shared Setup v2 writer DTOs.
 *
 * These intentionally do not extend or reuse the serializable v1 DTO graph. A decoded unknown
 * field can therefore be inspected under the bounded generic preflight, but can never be copied
 * back out by the typed v2 writer.
 */
@Serializable
data class SharedSetupV2(
    val schema: String,
    @SerialName("schema_version") val schemaVersion: Int,
    @SerialName("created_by") val createdBy: SharedSetupV2CreatedBy,
    @SerialName("metric_registry") val metricRegistry: SharedSetupV2MetricRegistryIdentity,
    val profiles: List<SharedSetupV2Profile>,
    @SerialName("active_profile") val activeProfile: String,
    @SerialName("metric_aliases") val metricAliases: List<SharedSetupV2MetricAlias>,
)

@Serializable
data class SharedSetupV2CreatedBy(
    val platform: String,
    @SerialName("app_version") val appVersion: String,
)

@Serializable
data class SharedSetupV2MetricRegistryIdentity(
    val schema: String,
    @SerialName("registry_version") val registryVersion: Int,
    @SerialName("registry_sha256") val registrySha256: String,
)

@Serializable
data class SharedSetupV2MetricAlias(
    @SerialName("semantic_id") val semanticId: String,
    val equivalence: String,
    @SerialName("apple_selection_id") val appleSelectionId: String?,
    @SerialName("android_selection_id") val androidSelectionId: String?,
)

@Serializable
data class SharedSetupV2Profile(
    @SerialName("bundle_id") val bundleId: String,
    val name: String,
    val export: SharedSetupV2Export,
    val metrics: SharedSetupV2Metrics,
    val presentation: SharedSetupV2Presentation,
    @SerialName("individual_entries") val individualEntries: SharedSetupV2IndividualEntries,
    @SerialName("daily_notes") val dailyNotes: SharedSetupV2DailyNotes,
    val destination: SharedSetupV2Destination,
    val schedule: SharedSetupV2Schedule?,
    @SerialName("platform_extensions") val platformExtensions: SharedSetupV2PlatformExtensions,
)

@Serializable
data class SharedSetupV2Export(
    val formats: List<String>,
    @SerialName("include_metadata") val includeMetadata: Boolean,
    @SerialName("group_by_category") val groupByCategory: Boolean,
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("folder_template") val folderTemplate: String,
    @SerialName("write_mode") val writeMode: String,
    @SerialName("compatibility_detail") val compatibilityDetail: String,
)

@Serializable
data class SharedSetupV2Metrics(
    @SerialName("enabled_ids") val enabledIds: List<String>,
)

@Serializable
data class SharedSetupV2Presentation(
    @SerialName("date_format") val dateFormat: String,
    @SerialName("time_format") val timeFormat: String,
    val units: String,
    val frontmatter: SharedSetupV2Frontmatter,
    val markdown: SharedSetupV2Markdown,
)

@Serializable
data class SharedSetupV2Frontmatter(
    val fields: List<SharedSetupV2FrontmatterField>,
    @SerialName("custom_values") val customValues: Map<String, String>,
    val placeholders: List<String>,
    @SerialName("include_date") val includeDate: Boolean,
    @SerialName("include_type") val includeType: Boolean,
    @SerialName("date_key") val dateKey: String,
    @SerialName("type_key") val typeKey: String,
    @SerialName("type_value") val typeValue: String,
    @SerialName("key_style") val keyStyle: String,
)

@Serializable
data class SharedSetupV2FrontmatterField(
    @SerialName("source_key") val sourceKey: String,
    @SerialName("output_key") val outputKey: String,
    val enabled: Boolean,
)

@Serializable
data class SharedSetupV2Markdown(
    val style: String,
    @SerialName("custom_text") val customText: String,
    @SerialName("header_level") val headerLevel: Int,
    @SerialName("use_emoji") val useEmoji: Boolean,
    @SerialName("include_summary") val includeSummary: Boolean,
    @SerialName("bullet_style") val bulletStyle: String,
    @SerialName("origin_dialect") val originDialect: String,
)

@Serializable
data class SharedSetupV2IndividualEntries(
    val enabled: Boolean,
    val metrics: Map<String, SharedSetupV2IndividualMetric>,
    @SerialName("entries_folder") val entriesFolder: String,
    @SerialName("organize_by_category") val organizeByCategory: Boolean,
    @SerialName("filename_template") val filenameTemplate: String,
)

@Serializable
data class SharedSetupV2IndividualMetric(
    val enabled: Boolean,
    @SerialName("custom_folder") val customFolder: String?,
)

@Serializable
data class SharedSetupV2DailyNotes(
    val enabled: Boolean,
    val folder: String,
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("create_if_missing") val createIfMissing: Boolean,
    @SerialName("inject_sections") val injectSections: Boolean,
)

@Serializable
data class SharedSetupV2Destination(
    val kind: String,
    @SerialName("api_endpoint") val apiEndpoint: SharedSetupV2ApiEndpoint?,
)

@Serializable
data class SharedSetupV2ApiEndpoint(
    val scheme: String,
    val host: String,
    val port: Int?,
    val path: String,
    @SerialName("query_omitted") val queryOmitted: Boolean,
    @SerialName("credentials_required") val credentialsRequired: Boolean,
)

@Serializable
data class SharedSetupV2Schedule(
    @SerialName("activation_requested") val activationRequested: Boolean,
    val cadence: SharedSetupV2Cadence,
    @SerialName("local_time") val localTime: SharedSetupV2LocalTime,
    val weekday: Int,
    @SerialName("lookback_days") val lookbackDays: Int,
    @SerialName("date_window") val dateWindow: String,
)

@Serializable
data class SharedSetupV2Cadence(
    val value: Int,
    val unit: String,
    @SerialName("anchor_date") val anchorDate: String,
)

@Serializable
data class SharedSetupV2LocalTime(
    val hour: Int,
    val minute: Int,
)

@Serializable
data class SharedSetupV2PlatformExtensions(
    val apple: SharedSetupV2AppleExtension?,
    val android: SharedSetupV2AndroidExtension?,
)

@Serializable
data class SharedSetupV2AppleExtension(
    @SerialName("extension_version") val extensionVersion: Int,
    val export: SharedSetupV2AppleExport,
    @SerialName("daily_notes") val dailyNotes: SharedSetupV2AppleDailyNotes,
    val schedule: SharedSetupV2AppleSchedule?,
)

@Serializable
data class SharedSetupV2AppleExport(
    @SerialName("organize_formats_into_folders") val organizeFormatsIntoFolders: Boolean,
    @SerialName("archive_files") val archiveFiles: Boolean,
    @SerialName("include_data_dictionary") val includeDataDictionary: Boolean,
    @SerialName("summary_only") val summaryOnly: Boolean,
    @SerialName("healthkit_source_archive") val healthkitSourceArchive: String,
    @SerialName("generate_range_summary") val generateRangeSummary: Boolean,
)

@Serializable
data class SharedSetupV2AppleDailyNotes(
    val only: Boolean,
)

@Serializable
data class SharedSetupV2AppleSchedule(
    val frequency: String,
    @SerialName("custom_unit") val customUnit: String,
    @SerialName("today_refresh_requested") val todayRefreshRequested: Boolean,
    @SerialName("today_refresh_interval_hours") val todayRefreshIntervalHours: Int,
)

@Serializable
data class SharedSetupV2AndroidExtension(
    @SerialName("extension_version") val extensionVersion: Int,
    val export: SharedSetupV2AndroidExport,
)

@Serializable
data class SharedSetupV2AndroidExport(
    val mode: String,
    @SerialName("legacy_primary_format") val legacyPrimaryFormat: String,
    @SerialName("compatibility_profile") val compatibilityProfile: String,
    @SerialName("include_legacy_aliases") val includeLegacyAliases: Boolean,
    @SerialName("include_android_native_fields") val includeAndroidNativeFields: Boolean,
    @SerialName("legacy_data_types") val legacyDataTypes: SharedSetupV2AndroidLegacyDataTypes,
    val subfolder: String,
    @SerialName("folder_organization") val folderOrganization: String,
    @SerialName("raw_snapshot") val rawSnapshot: SharedSetupV2AndroidRawSnapshot,
)

@Serializable
data class SharedSetupV2AndroidLegacyDataTypes(
    val sleep: Boolean,
    val activity: Boolean,
    val heart: Boolean,
    val vitals: Boolean,
    val body: Boolean,
    val nutrition: Boolean,
    val mobility: Boolean,
    @SerialName("reproductive_health") val reproductiveHealth: Boolean,
    val mindfulness: Boolean,
    val workouts: Boolean,
    @SerialName("planned_workouts") val plannedWorkouts: Boolean,
    @SerialName("medical_resources") val medicalResources: Boolean,
)

@Serializable
data class SharedSetupV2AndroidRawSnapshot(
    val format: String,
    val scope: String,
    @SerialName("include_exercise_routes") val includeExerciseRoutes: Boolean,
    @SerialName("page_size") val pageSize: Int,
)

/** Strict dispatch result. The v1 and v2 typed graphs remain intentionally separate. */
sealed interface SharedSetupDecodedDocument {
    data class V1(val document: SharedSetupV1) : SharedSetupDecodedDocument
    data class V2(val document: SharedSetupV2) : SharedSetupDecodedDocument
}

sealed interface SharedSetupVersionedDecodeResult {
    data class Valid(val document: SharedSetupDecodedDocument) : SharedSetupVersionedDecodeResult
    data class Invalid(val message: String) : SharedSetupVersionedDecodeResult
}

enum class SharedSetupV2CompatibilityStatus {
    APPLIED,
    REQUIRES_ACTION,
    UNSUPPORTED,
    INVALID,
}

data class SharedSetupV2CompatibilityItem(
    val status: SharedSetupV2CompatibilityStatus,
    val field: String,
    val title: String,
    val detail: String,
)

/** Destination data remains descriptive until a recipient explicitly rebinds it locally. */
data class SharedSetupV2DestinationImportIntent(
    val source: SharedSetupV2Destination,
    val requiresLocalRebinding: Boolean = true,
)

/** A schedule is preserved as configuration intent, but cycle-2 import must keep it disabled. */
data class SharedSetupV2ScheduleImportIntent(
    val source: SharedSetupV2Schedule,
    val importedEnabled: Boolean = false,
)

/** Pure, zero-write plan for one profile. It deliberately contains no native profile identity. */
data class SharedSetupV2ProfileImportPlan(
    val bundleId: String,
    val name: String,
    val source: SharedSetupV2Profile,
    val supportedMetricIds: List<String>,
    val unavailableMetricIds: List<String>,
    val destinationIntent: SharedSetupV2DestinationImportIntent,
    val scheduleIntent: SharedSetupV2ScheduleImportIntent?,
    /** Exact foreign meaning retained for later round trip; Android never approximates it. */
    val preservedAppleExtension: SharedSetupV2AppleExtension?,
    val compatibility: List<SharedSetupV2CompatibilityItem>,
)

/**
 * Read-only cycle-2 handoff. Building this value performs validation and compatibility analysis,
 * but no repository, scheduler, destination, credential, or profile-store write.
 */
data class SharedSetupV2ImportPlan(
    val source: SharedSetupV2,
    val profiles: List<SharedSetupV2ProfileImportPlan>,
    val activeProfile: String,
) {
    val compatibility: List<SharedSetupV2CompatibilityItem>
        get() = profiles.flatMap { it.compatibility }
}
