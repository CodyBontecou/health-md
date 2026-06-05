package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Calendar
import java.util.Locale

@Serializable
data class FormatCustomization(
    val dateFormat: DateFormatPreference = DateFormatPreference.ISO8601,
    val timeFormat: TimeFormatPreference = TimeFormatPreference.HOUR_24,
    val unitPreference: UnitPreference = UnitPreference.METRIC,
    val frontmatterConfig: FrontmatterConfiguration = FrontmatterConfiguration(),
    val markdownTemplate: MarkdownTemplateConfig = MarkdownTemplateConfig(),
) {
    val unitConverter: UnitConverter
        get() = UnitConverter(unitPreference)
}

@Serializable
data class ExportSettings(
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
    val subfolder: String = "health",
    val folderOrganization: FolderOrganization = FolderOrganization.FLAT,
    val scheduleEnabled: Boolean = false,
    val scheduleCadenceValue: Int = 1,
    val scheduleCadenceUnit: ScheduleCadenceUnit = ScheduleCadenceUnit.DAYS,
    val scheduleHour: Int = 6,
    val scheduleMinute: Int = 0,
    val scheduleLookbackDays: Int = 1,
    val pendingScheduledRetryDates: List<String> = emptyList(),
) {
    val selectedExportFormats: Set<ExportFormat>
        get() = exportFormats

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
