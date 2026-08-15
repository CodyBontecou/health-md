package com.healthmd.sharedsetup

import com.healthmd.domain.model.ExportSettings
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

const val SHARED_SETUP_SCHEMA = "healthmd.shared_setup"
const val SHARED_SETUP_VERSION = 1
const val SHARED_SETUP_MIME_TYPE = "application/vnd.healthmd.configuration+json"
const val SHARED_SETUP_EXTENSION = "healthmdconfig"
const val SHARED_SETUP_MAX_BYTES = 262_144

@Serializable
data class SharedSetupV1(
    val schema: String,
    @SerialName("schema_version") val schemaVersion: Int,
    @SerialName("created_by") val createdBy: SharedSetupCreatedBy,
    @SerialName("metric_registry") val metricRegistry: SharedSetupMetricRegistryIdentity,
    val profile: SharedSetupProfile,
    @SerialName("metric_aliases") val metricAliases: List<SharedSetupMetricAlias>,
    @SerialName("platform_extensions") val platformExtensions: SharedSetupPlatformExtensions,
)

@Serializable
data class SharedSetupCreatedBy(
    val platform: String,
    @SerialName("app_version") val appVersion: String,
)

@Serializable
data class SharedSetupMetricRegistryIdentity(
    val schema: String,
    @SerialName("registry_version") val registryVersion: Int,
    @SerialName("registry_sha256") val registrySha256: String,
)

@Serializable
data class SharedSetupMetricAlias(
    @SerialName("semantic_id") val semanticId: String,
    val equivalence: String,
    @SerialName("apple_selection_id") val appleSelectionId: String?,
    @SerialName("android_selection_id") val androidSelectionId: String?,
)

@Serializable
data class SharedSetupProfile(
    val export: SharedSetupExport,
    val metrics: SharedSetupMetrics,
    val presentation: SharedSetupPresentation,
    @SerialName("individual_entries") val individualEntries: SharedSetupIndividualEntries,
    @SerialName("daily_notes") val dailyNotes: SharedSetupDailyNotes,
    val schedule: SharedSetupSchedule,
    @SerialName("api_endpoint") val apiEndpoint: SharedSetupApiEndpoint?,
)

@Serializable
data class SharedSetupExport(
    val formats: List<String>,
    @SerialName("include_metadata") val includeMetadata: Boolean,
    @SerialName("group_by_category") val groupByCategory: Boolean,
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("folder_template") val folderTemplate: String,
    @SerialName("write_mode") val writeMode: String,
    @SerialName("include_granular_data") val includeGranularData: Boolean,
)

@Serializable
data class SharedSetupMetrics(@SerialName("enabled_ids") val enabledIds: List<String>)

@Serializable
data class SharedSetupPresentation(
    @SerialName("date_format") val dateFormat: String,
    @SerialName("time_format") val timeFormat: String,
    val units: String,
    val frontmatter: SharedSetupFrontmatter,
    val markdown: SharedSetupMarkdown,
)

@Serializable
data class SharedSetupFrontmatter(
    val fields: List<SharedSetupFrontmatterField>,
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
data class SharedSetupFrontmatterField(
    @SerialName("source_key") val sourceKey: String,
    @SerialName("output_key") val outputKey: String,
    val enabled: Boolean,
)

@Serializable
data class SharedSetupMarkdown(
    val style: String,
    @SerialName("custom_text") val customText: String,
    @SerialName("header_level") val headerLevel: Int,
    @SerialName("use_emoji") val useEmoji: Boolean,
    @SerialName("include_summary") val includeSummary: Boolean,
    @SerialName("bullet_style") val bulletStyle: String,
    @SerialName("origin_dialect") val originDialect: String,
)

@Serializable
data class SharedSetupIndividualEntries(
    val enabled: Boolean,
    val metrics: Map<String, SharedSetupIndividualMetric>,
    @SerialName("entries_folder") val entriesFolder: String,
    @SerialName("organize_by_category") val organizeByCategory: Boolean,
    @SerialName("filename_template") val filenameTemplate: String,
)

@Serializable
data class SharedSetupIndividualMetric(
    val enabled: Boolean,
    @SerialName("custom_folder") val customFolder: String?,
)

@Serializable
data class SharedSetupDailyNotes(
    val enabled: Boolean,
    val folder: String,
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("create_if_missing") val createIfMissing: Boolean,
    @SerialName("inject_sections") val injectSections: Boolean,
)

@Serializable
data class SharedSetupSchedule(
    @SerialName("activation_requested") val activationRequested: Boolean,
    val cadence: SharedSetupCadence,
    @SerialName("local_time") val localTime: SharedSetupLocalTime,
    @SerialName("lookback_days") val lookbackDays: Int,
    @SerialName("date_window") val dateWindow: String,
    @SerialName("desired_target") val desiredTarget: String,
)

@Serializable data class SharedSetupCadence(val value: Int, val unit: String)
@Serializable data class SharedSetupLocalTime(val hour: Int, val minute: Int)

@Serializable
data class SharedSetupApiEndpoint(
    val scheme: String,
    val host: String,
    val port: Int?,
    val path: String,
    @SerialName("query_omitted") val queryOmitted: Boolean,
    @SerialName("credentials_required") val credentialsRequired: Boolean,
)

@Serializable
data class SharedSetupPlatformExtensions(
    val apple: SharedSetupAppleExtension?,
    val android: SharedSetupAndroidExtension?,
)

@Serializable
data class SharedSetupAppleExtension(
    @SerialName("extension_version") val extensionVersion: Int,
    val export: SharedSetupAppleExport,
    @SerialName("daily_notes") val dailyNotes: SharedSetupAppleDailyNotes,
    val schedule: SharedSetupAppleSchedule,
)

@Serializable
data class SharedSetupAppleExport(
    @SerialName("organize_formats_into_folders") val organizeFormatsIntoFolders: Boolean,
    @SerialName("archive_files") val archiveFiles: Boolean,
    @SerialName("include_data_dictionary") val includeDataDictionary: Boolean,
    @SerialName("summary_only") val summaryOnly: Boolean,
    val rollups: List<String>,
)

@Serializable data class SharedSetupAppleDailyNotes(val only: Boolean)

@Serializable
data class SharedSetupAppleSchedule(
    val frequency: String,
    @SerialName("custom_unit") val customUnit: String,
    val weekday: Int,
    @SerialName("today_refresh_requested") val todayRefreshRequested: Boolean,
    @SerialName("today_refresh_interval_hours") val todayRefreshIntervalHours: Int,
    @SerialName("desired_target") val desiredTarget: String,
)

@Serializable
data class SharedSetupAndroidExtension(
    @SerialName("extension_version") val extensionVersion: Int,
    val export: SharedSetupAndroidExport,
)

@Serializable
data class SharedSetupAndroidExport(
    @SerialName("compatibility_profile") val compatibilityProfile: String,
    @SerialName("include_legacy_aliases") val includeLegacyAliases: Boolean,
    @SerialName("include_android_native_fields") val includeAndroidNativeFields: Boolean,
    val subfolder: String,
    @SerialName("folder_organization") val folderOrganization: String,
)

enum class SharedSetupCompatibilityStatus { APPLIED, REQUIRES_ACTION, UNSUPPORTED, INVALID }

data class SharedSetupCompatibilityItem(
    val status: SharedSetupCompatibilityStatus,
    val title: String,
    val detail: String,
)

data class SharedSetupReviewSummary(
    val formats: List<String>,
    val metricCount: Int,
    val filenameTemplate: String,
    val units: String,
    val dailyNotesEnabled: Boolean,
    val individualEntriesEnabled: Boolean,
    val hasCustomContent: Boolean,
    val scheduleRequested: Boolean,
    val endpointDescription: String?,
    val items: List<SharedSetupCompatibilityItem>,
) {
    val appliedCount: Int get() = items.count { it.status == SharedSetupCompatibilityStatus.APPLIED }
    val requiresActionCount: Int get() = items.count { it.status == SharedSetupCompatibilityStatus.REQUIRES_ACTION }
    val unsupportedCount: Int get() = items.count { it.status == SharedSetupCompatibilityStatus.UNSUPPORTED }
}

data class SharedSetupPreview(
    val document: SharedSetupV1,
    val expectedCurrent: ExportSettings,
    val candidate: ExportSettings,
    val pendingEndpoint: String?,
    val review: SharedSetupReviewSummary,
)

data class SharedSetupApplyResult(val review: SharedSetupReviewSummary, val canUndo: Boolean)

sealed interface SharedSetupDecodeResult {
    data class Valid(val document: SharedSetupV1) : SharedSetupDecodeResult
    data class Invalid(val message: String) : SharedSetupDecodeResult
}
