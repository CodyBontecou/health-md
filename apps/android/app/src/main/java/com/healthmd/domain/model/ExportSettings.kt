package com.healthmd.domain.model

import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawSnapshotScope
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Calendar
import java.util.Locale

@Serializable
enum class CompatibilitySchemaProfile {
    /** Frozen wire shape used by persisted settings and API/plugin v4 consumers. */
    IOS_V4_FROZEN,
    /** Additive local analytical shape with Android-native values and exact source details. */
    ANDROID_ANALYTICAL_V5,
}

@Serializable
data class FormatCustomization(
    val dateFormat: DateFormatPreference = DateFormatPreference.ISO8601,
    val timeFormat: TimeFormatPreference = TimeFormatPreference.HOUR_24,
    val unitPreference: UnitPreference = UnitPreference.METRIC,
    /**
     * Deprecated serialized migration field. Exporters intentionally do not read this value;
     * persisted settings are migrated to the two explicit switches below.
     */
    @Deprecated("Use includeLegacyAndroidAliases and includeAndroidNativeFields")
    val includeAndroidCompatibilityKeys: Boolean = false,
    /** Duplicate pre-parity Android keys and labels only. */
    val includeLegacyAndroidAliases: Boolean = false,
    /** Emit real Android-native values that do not have an equivalent frozen iOS-v4 field. */
    val includeAndroidNativeFields: Boolean = false,
    /** Declares whether this customization is frozen v4 or additive analytical v5. */
    val compatibilitySchemaProfile: CompatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
    val frontmatterConfig: FrontmatterConfiguration = FrontmatterConfiguration(),
    val markdownTemplate: MarkdownTemplateConfig = MarkdownTemplateConfig(),
) {
    val unitConverter: UnitConverter
        get() = UnitConverter(unitPreference)

    /** API v1 embeds frozen daily-record schema v4 regardless of local analytical settings. */
    fun forFrozenApiV4(): FormatCustomization = when (compatibilitySchemaProfile) {
        CompatibilitySchemaProfile.IOS_V4_FROZEN -> this
        CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> copy(
            includeLegacyAndroidAliases = false,
            includeAndroidNativeFields = false,
            compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
        )
    }

    companion object {
        /** Default for newly-created local settings. Persisted settings use explicit migration. */
        fun analyticalDefault(): FormatCustomization = FormatCustomization(
            includeAndroidNativeFields = true,
            compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
        )
    }
}

@Serializable
data class PendingScheduledExportRequest(
    @Serializable(with = LocalDateSerializer::class)
    val date: LocalDate,
    /** Captures the destination at failure time so retries cannot silently switch targets. */
    val exportTarget: ExportTarget = ExportTarget.DEVICE_FOLDER,
    /** SHA-256 of the normalized API URL; blocks automatic delivery after an endpoint change. */
    val destinationFingerprint: String? = null,
    val firstFailedAtMillis: Long = 0L,
    val lastAttemptAtMillis: Long = firstFailedAtMillis,
    val lastFailureReason: ExportFailureReason? = null,
    val attemptCount: Int = 0,
)

@Serializable
data class RawSnapshotSettings(
    /** One action creates exactly one artifact and performs exactly one Health Connect source read. */
    val format: RawExportFormat = RawExportFormat.NDJSON,
    val scope: RawSnapshotScope = RawSnapshotScope.SELECTED_RECORD_TYPES,
    val includeExerciseRoutes: Boolean = true,
    val pageSize: Int = DEFAULT_PAGE_SIZE,
) {
    fun normalized(): RawSnapshotSettings = copy(pageSize = pageSize.coerceIn(MIN_PAGE_SIZE, MAX_PAGE_SIZE))

    companion object {
        const val DEFAULT_PAGE_SIZE = 500
        const val MIN_PAGE_SIZE = 1
        const val MAX_PAGE_SIZE = 5_000
    }
}

@Serializable
data class ExportSettings(
    /** Missing on all pre-raw persisted settings, so compatibility remains the migration default. */
    val exportMode: ExportMode = ExportMode.COMPATIBILITY,
    val rawSnapshot: RawSnapshotSettings = RawSnapshotSettings(),
    val dataTypes: DataTypeSelection = DataTypeSelection(),
    /**
     * Legacy single-format preference kept for backwards compatibility with previously saved
     * settings. New export code should read [selectedExportFormats].
     */
    val exportFormat: ExportFormat = ExportFormat.MARKDOWN,
    /**
     * Formats written during one export action. Empty is allowed while the user is editing; export
     * and preview actions validate and block with a clear UI state.
     */
    val exportFormats: Set<ExportFormat> = setOf(ExportFormat.MARKDOWN),
    val includeMetadata: Boolean = true,
    val groupByCategory: Boolean = true,
    val filenameFormat: String = DEFAULT_FILENAME_FORMAT,
    val folderStructure: String = "", // empty = flat
    val writeMode: WriteMode = WriteMode.OVERWRITE,
    val formatCustomization: FormatCustomization = FormatCustomization(),
    val metricSelection: MetricSelectionState = MetricSelectionState(),
    val dailyNoteInjection: DailyNoteInjectionSettings = DailyNoteInjectionSettings(),
    val individualTracking: IndividualTrackingSettings = IndividualTrackingSettings(),
    val includeGranularData: Boolean = false,
    /** Destination for exports started from the Export screen. */
    val exportTarget: ExportTarget = ExportTarget.DEVICE_FOLDER,
    /** Destination captured when WorkManager creates a scheduled export run. */
    val scheduledExportTarget: ExportTarget = ExportTarget.DEVICE_FOLDER,
    /** Non-secret endpoint configuration. Authorization credentials are encrypted separately. */
    val apiEndpointUrl: String = "",
    val subfolder: String = "health",
    val folderOrganization: FolderOrganization = FolderOrganization.FLAT,
    val scheduleEnabled: Boolean = false,
    val scheduleCadenceValue: Int = 1,
    val scheduleCadenceUnit: ScheduleCadenceUnit = ScheduleCadenceUnit.DAYS,
    val scheduleHour: Int = 6,
    val scheduleMinute: Int = 0,
    val scheduleLookbackDays: Int = 1,
    val scheduleDateWindow: ScheduleDateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
    /**
     * Legacy date-only retry list kept for backwards compatibility with v1.3 settings. New code
     * should use [pendingScheduledExportRequests], while writing both fields until v2.0.
     */
    val pendingScheduledRetryDates: List<String> = emptyList(),
    val pendingScheduledExportRequests: List<PendingScheduledExportRequest> = emptyList(),
) {
    val selectedExportFormats: Set<ExportFormat>
        get() = exportFormats

    fun normalized(): ExportSettings = copy(rawSnapshot = rawSnapshot.normalized())

    fun effectiveDataTypeSelection(): DataTypeSelection =
        metricSelection.toDataTypeSelection().intersect(dataTypes)

    fun shouldFetchGranularData(): Boolean =
        includeGranularData || individualTracking.requiresGranularData

    fun formatFilename(date: LocalDate): String =
        applyDatePlaceholders(filenameFormat, date)

    fun formatFolderPath(date: LocalDate): String? {
        val template = folderStructure.ifBlank {
            when (folderOrganization) {
                FolderOrganization.FLAT -> ""
                FolderOrganization.BY_YEAR -> "{year}"
                FolderOrganization.BY_MONTH -> "{month}"
                FolderOrganization.BY_YEAR_MONTH -> "{year}/{month}"
            }
        }
        if (template.isEmpty()) return null
        return applyDatePlaceholders(template, date)
    }

    fun aggregateSubfolderPath(date: LocalDate): String? = listOfNotNull(
        subfolder.trim('/').takeIf { it.isNotBlank() },
        formatFolderPath(date)?.trim('/')?.takeIf { it.isNotBlank() },
    ).joinToString("/").takeIf { it.isNotBlank() }

    fun aggregateRelativePath(date: LocalDate, format: ExportFormat): String {
        val selectedFormats = selectedExportFormats.ifEmpty { setOf(format) }
        val baseName = formatFilename(date)
        val fileName = if (format == ExportFormat.OBSIDIAN_BASES && ExportFormat.MARKDOWN in selectedFormats) {
            "$baseName-bases.${format.fileExtension}"
        } else {
            "$baseName.${format.fileExtension}"
        }
        return listOfNotNull(aggregateSubfolderPath(date), fileName).joinToString("/")
    }

    companion object {
        const val DEFAULT_FILENAME_FORMAT = "{date}"

        fun applyDatePlaceholders(template: String, date: LocalDate): String {
            var result = template

            // {date} -> yyyy-MM-dd
            result = result.replace("{date}", date.format(DateTimeFormatter.ofPattern("yyyy-MM-dd")))
            // {year} -> yyyy
            result = result.replace("{year}", date.format(DateTimeFormatter.ofPattern("yyyy")))
            // {month} -> MM
            result = result.replace("{month}", date.format(DateTimeFormatter.ofPattern("MM")))
            // {day} -> dd
            result = result.replace("{day}", date.format(DateTimeFormatter.ofPattern("dd")))
            // {weekday} -> Monday, Tuesday, etc.
            result = result.replace("{weekday}", date.format(DateTimeFormatter.ofPattern("EEEE", Locale.getDefault())))
            // {monthName} -> January, February, etc.
            result = result.replace("{monthName}", date.format(DateTimeFormatter.ofPattern("MMMM", Locale.getDefault())))
            // {quarter} -> Q1, Q2, Q3, Q4
            val quarter = "Q${(date.monthValue - 1) / 3 + 1}"
            result = result.replace("{quarter}", quarter)

            return result
        }
    }
}

@Serializable
enum class FolderOrganization {
    FLAT,
    BY_YEAR,
    BY_MONTH,
    BY_YEAR_MONTH,
}

@Serializable
enum class ScheduleCadenceUnit {
    MINUTES,
    HOURS,
    DAYS,
    WEEKS,
}

@Serializable
enum class ScheduleDateWindow {
    PAST_COMPLETE_DAYS,
    TODAY,
}
