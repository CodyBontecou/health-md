package com.healthmd.domain.clinicianreport

import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WorkoutType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Internal report configuration. It is intentionally not persisted or part of an export schema. */
data class ReportConfiguration(
    val dateRange: ReportDateRange = ReportDateRange.preset(ReportDateRangePreset.DAYS_30),
    val selectedMetrics: Set<ReportMetric> = ReportMetric.entries.toSet(),
    val detailLevel: ReportDetailLevel = ReportDetailLevel.SUMMARY,
    val unitPreference: UnitPreference = UnitPreference.METRIC,
    val displayName: String = "",
)

enum class ReportDateRangePreset(val dayCount: Long) {
    DAYS_7(7), DAYS_30(30), DAYS_90(90), CUSTOM(0);
}

data class ReportDateRange(val startDate: LocalDate, val endDate: LocalDate) {
    val inclusiveDayCount: Int get() = generateSequence(startDate) { current ->
        current.plusDays(1).takeIf { it <= endDate }
    }.count()

    fun dates(): List<LocalDate> = generateSequence(startDate) { current ->
        current.plusDays(1).takeIf { it <= endDate }
    }.toList()

    fun interval(zoneId: ZoneId): ReportInstantRange = ReportInstantRange(
        startInclusive = startDate.atStartOfDay(zoneId).toInstant(),
        endExclusive = endDate.plusDays(1).atStartOfDay(zoneId).toInstant(),
    )

    companion object {
        fun preset(preset: ReportDateRangePreset, today: LocalDate = LocalDate.now()): ReportDateRange {
            require(preset != ReportDateRangePreset.CUSTOM)
            return ReportDateRange(today.minusDays(preset.dayCount - 1), today)
        }

        fun normalized(start: LocalDate, end: LocalDate, today: LocalDate = LocalDate.now()): ReportDateRange {
            val clampedStart = minOf(start, today)
            val clampedEnd = minOf(end, today)
            return ReportDateRange(minOf(clampedStart, clampedEnd), maxOf(clampedStart, clampedEnd))
        }
    }
}

data class ReportInstantRange(val startInclusive: Instant, val endExclusive: Instant) {
    fun contains(instant: Instant): Boolean = instant >= startInclusive && instant < endExclusive
}

enum class ReportDetailLevel { SUMMARY, SUMMARY_AND_READINGS }

enum class ReportMetric {
    BLOOD_PRESSURE,
    RESTING_HEART_RATE,
    HEART_RATE,
    WEIGHT,
    BLOOD_GLUCOSE,
    OXYGEN_SATURATION,
    RESPIRATORY_RATE,
    BODY_TEMPERATURE,
    SLEEP_DURATION,
    STEPS,
    WORKOUTS,
}

data class ReportSource(val label: String, val isManualEntry: Boolean = false) {
    fun displayLabel(vocabulary: ClinicianReportVocabulary): String {
        if (!isManualEntry) return label
        val manual = vocabulary.text(ClinicianReportText.MANUAL_ENTRY)
        if (label.isBlank()) return manual
        return vocabulary.text(ClinicianReportText.MANUAL_ENTRY_SOURCE, label)
    }
}

data class ScalarReportObservation(
    val metric: ReportMetric,
    val timestamp: Instant,
    val value: Double,
    val stableId: String? = null,
    val source: ReportSource? = null,
)

data class BloodPressureReportObservation(
    val timestamp: Instant,
    val systolic: Double,
    val diastolic: Double,
    val stableId: String? = null,
    val source: ReportSource? = null,
)

data class DailyReportValue(
    val metric: ReportMetric,
    val date: LocalDate,
    val value: Double,
    val stableId: String? = null,
    val source: ReportSource? = null,
)

data class SleepReportObservation(
    val date: LocalDate,
    val durationMinutes: Double,
    val stableId: String? = null,
    val source: ReportSource? = null,
)

data class WorkoutReportObservation(
    val timestamp: Instant,
    val type: WorkoutType,
    val durationMinutes: Double,
    val stableId: String? = null,
    val source: ReportSource? = null,
)

sealed interface ClinicianReportWarning {
    data object ReadFailure : ClinicianReportWarning
    data class SourceFailure(val date: LocalDate) : ClinicianReportWarning
}

data class ClinicianReportInput(
    val configuration: ReportConfiguration,
    val zoneId: ZoneId,
    val generatedAt: Instant,
    val scalarObservations: List<ScalarReportObservation> = emptyList(),
    val bloodPressureObservations: List<BloodPressureReportObservation> = emptyList(),
    val dailyValues: List<DailyReportValue> = emptyList(),
    val sleepObservations: List<SleepReportObservation> = emptyList(),
    val workoutObservations: List<WorkoutReportObservation> = emptyList(),
    val warnings: List<ClinicianReportWarning> = emptyList(),
)

data class ReportFact(val label: String, val value: String)

data class ReportTable(
    val title: String,
    val columns: List<String>,
    val rows: List<List<String>>,
)

data class MetricReportSummary(
    val metric: ReportMetric,
    val facts: List<ReportFact>,
    val sources: List<String>,
    val coverageDisclosure: String?,
    val noDataMessage: String?,
    val table: ReportTable?,
    val localizedTitle: String,
    val sourcesDisclosure: String? = null,
    val detailReadingsDescription: String? = null,
)

enum class ReportCompleteness { COMPLETE, PARTIAL }

data class ClinicianReportData(
    val title: String,
    val displayName: String?,
    val dateRangeLabel: String,
    val generatedLabel: String,
    val timeZoneLabel: String,
    val sections: List<MetricReportSummary>,
    val warnings: List<String>,
    val completeness: ReportCompleteness,
    val disclaimer: String,
    val attribution: String,
    val practiceLine: String?,
    val languageTag: String,
    val paperRegionCode: String?,
    val isRtl: Boolean,
    val pdfSubject: String,
    val pdfKeywords: List<String>,
    val metadataPeriodLabel: String,
    val metadataGeneratedLabel: String,
    val metadataTimeZoneLabel: String,
    val metadataPatientLabel: String,
    val availabilityNoteTitle: String,
    val aboutTitle: String,
    val pageFooterTemplate: String,
)
