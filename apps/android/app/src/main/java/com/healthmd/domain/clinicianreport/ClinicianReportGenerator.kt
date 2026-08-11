package com.healthmd.domain.clinicianreport

import com.healthmd.domain.model.UnitConverter
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs

class ClinicianReportGenerator(
    private val vocabulary: ClinicianReportVocabulary,
) {
    private val locale get() = vocabulary.locale

    fun generate(input: ClinicianReportInput): ClinicianReportData {
        val config = input.configuration
        val range = config.dateRange
        val interval = range.interval(input.zoneId)
        val sections = ReportMetric.entries
            .filter { it in config.selectedMetrics }
            .map { metric -> section(metric, input, interval) }
        val warnings = input.warnings.distinct().map { warning ->
            when (warning) {
                ClinicianReportWarning.ReadFailure -> vocabulary.text(ClinicianReportText.WARNING_READ_FAILURE)
                is ClinicianReportWarning.SourceFailure -> vocabulary.text(
                    ClinicianReportText.WARNING_SOURCE_FAILURE_DATE,
                    date(warning.date),
                )
            }
        }
        return ClinicianReportData(
            title = vocabulary.text(ClinicianReportText.DOCUMENT_TITLE),
            displayName = config.displayName.trim().takeIf(String::isNotEmpty),
            dateRangeLabel = "${date(range.startDate)} – ${date(range.endDate)}",
            generatedLabel = dateTime(input.generatedAt, input.zoneId),
            timeZoneLabel = input.zoneId.id,
            sections = sections,
            warnings = warnings,
            completeness = if (warnings.isEmpty()) ReportCompleteness.COMPLETE else ReportCompleteness.PARTIAL,
            disclaimer = vocabulary.text(ClinicianReportText.DISCLAIMER),
            attribution = vocabulary.text(ClinicianReportText.ATTRIBUTION),
            practiceLine = vocabulary.text(ClinicianReportText.PRACTICE_LINE, ClinicianReportCopy.practiceUrl),
            languageTag = vocabulary.languageTag,
            paperRegionCode = vocabulary.paperRegionCode,
            isRtl = vocabulary.isRtl,
            pdfSubject = vocabulary.text(ClinicianReportText.ENTRY_SUBTITLE),
            pdfKeywords = listOf(
                vocabulary.text(ClinicianReportText.TITLE),
                vocabulary.text(ClinicianReportText.DOCUMENT_TITLE),
                "Health.md",
            ),
            metadataPeriodLabel = vocabulary.text(ClinicianReportText.METADATA_PERIOD),
            metadataGeneratedLabel = vocabulary.text(ClinicianReportText.METADATA_GENERATED),
            metadataTimeZoneLabel = vocabulary.text(ClinicianReportText.METADATA_TIMEZONE),
            metadataPatientLabel = vocabulary.text(ClinicianReportText.METADATA_PATIENT),
            availabilityNoteTitle = vocabulary.text(ClinicianReportText.AVAILABILITY_NOTE),
            aboutTitle = vocabulary.text(ClinicianReportText.ABOUT),
            pageFooterTemplate = vocabulary.text(ClinicianReportText.PAGE_FOOTER),
        )
    }

    private fun section(metric: ReportMetric, input: ClinicianReportInput, interval: ReportInstantRange): MetricReportSummary = when (metric) {
        ReportMetric.BLOOD_PRESSURE -> bloodPressure(input, interval)
        ReportMetric.RESTING_HEART_RATE, ReportMetric.WEIGHT, ReportMetric.STEPS -> daily(metric, input)
        ReportMetric.HEART_RATE, ReportMetric.BLOOD_GLUCOSE, ReportMetric.OXYGEN_SATURATION,
        ReportMetric.RESPIRATORY_RATE, ReportMetric.BODY_TEMPERATURE -> scalar(metric, input, interval)
        ReportMetric.SLEEP_DURATION -> sleep(input)
        ReportMetric.WORKOUTS -> workouts(input, interval)
    }

    private fun bloodPressure(input: ClinicianReportInput, interval: ReportInstantRange): MetricReportSummary {
        val values = dedupe(input.bloodPressureObservations.filter { interval.contains(it.timestamp) }) { it.stableId }
            .sortedBy { it.timestamp }
        if (values.isEmpty()) return empty(ReportMetric.BLOOD_PRESSURE)
        val days = values.map { localDate(it.timestamp, input.zoneId) }.toSet().size
        val latest = values.last()
        val facts = listOf(
            ReportFact(vocabulary.text(ClinicianReportText.FACT_READINGS), values.size.toString()),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_DAYS_WITH_DATA), days.toString()),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_AVERAGE), "${whole(values.map { it.systolic }.average())}/${whole(values.map { it.diastolic }.average())} mmHg"),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_RANGE), "${whole(values.minOf { it.systolic })}–${whole(values.maxOf { it.systolic })} / ${whole(values.minOf { it.diastolic })}–${whole(values.maxOf { it.diastolic })} mmHg"),
            ReportFact(
                vocabulary.text(ClinicianReportText.FACT_MOST_RECENT),
                vocabulary.text(
                    ClinicianReportText.VALUE_ON_DATE,
                    "${whole(latest.systolic)}/${whole(latest.diastolic)} mmHg",
                    dateTime(latest.timestamp, input.zoneId),
                ),
            ),
        )
        val table = if (input.configuration.detailLevel == ReportDetailLevel.SUMMARY_AND_READINGS) ReportTable(
            vocabulary.text(ClinicianReportText.TABLE_BLOOD_PRESSURE),
            listOf(
                vocabulary.text(ClinicianReportText.COLUMN_DATE),
                vocabulary.text(ClinicianReportText.COLUMN_TIME),
                vocabulary.text(ClinicianReportText.COLUMN_SYSTOLIC),
                vocabulary.text(ClinicianReportText.COLUMN_DIASTOLIC),
                vocabulary.text(ClinicianReportText.COLUMN_SOURCE),
            ),
            values.map {
                listOf(
                    date(localDate(it.timestamp, input.zoneId)),
                    time(it.timestamp, input.zoneId),
                    whole(it.systolic) + " mmHg",
                    whole(it.diastolic) + " mmHg",
                    it.source?.displayLabel(vocabulary).orEmpty(),
                )
            },
        ) else null
        return summary(ReportMetric.BLOOD_PRESSURE, facts, values.map { it.source }, days, input, table)
    }

    private fun scalar(metric: ReportMetric, input: ClinicianReportInput, interval: ReportInstantRange): MetricReportSummary {
        val exact = input.scalarObservations.filter { it.metric == metric && interval.contains(it.timestamp) }.map {
            ScalarValue(localDate(it.timestamp, input.zoneId), it.timestamp, it.value, it.stableId, it.source)
        }
        val range = input.configuration.dateRange
        val dailyAggregates = input.dailyValues.filter { it.metric == metric && it.date in range.startDate..range.endDate }.map {
            ScalarValue(it.date, null, it.value, it.stableId, it.source)
        }
        val values = dedupe(exact + dailyAggregates) { it.stableId }.sortedWith(compareBy<ScalarValue> { it.date }.thenBy { it.timestamp })
        if (values.isEmpty()) return empty(metric)
        val days = values.map { it.date }.toSet().size
        val unit = unit(metric, input)
        fun formatted(value: Double): String = "${formatValue(metric, value, input)} $unit".trim()
        val latest = values.last()
        val latestWhen = latest.timestamp?.let { dateTime(it, input.zoneId) } ?: date(latest.date)
        val facts = listOf(
            ReportFact(vocabulary.text(if (dailyAggregates.isEmpty()) ClinicianReportText.FACT_READINGS else ClinicianReportText.FACT_AVAILABLE_VALUES), values.size.toString()),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_DAYS_WITH_DATA), days.toString()),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_MEDIAN), formatted(median(values.map { it.value }))),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_RANGE), "${formatted(values.minOf { it.value })}–${formatted(values.maxOf { it.value })}"),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_MOST_RECENT), vocabulary.text(ClinicianReportText.VALUE_ON_DATE, formatted(latest.value), latestWhen)),
        )
        val table = if (input.configuration.detailLevel == ReportDetailLevel.SUMMARY_AND_READINGS) ReportTable(
            vocabulary.text(ClinicianReportText.TABLE_METRIC_READINGS, vocabulary.metricName(metric)),
            listOf(
                vocabulary.text(ClinicianReportText.COLUMN_DATE),
                vocabulary.text(ClinicianReportText.COLUMN_TIME),
                vocabulary.text(ClinicianReportText.COLUMN_VALUE),
                vocabulary.text(ClinicianReportText.COLUMN_SOURCE),
            ),
            values.map {
                listOf(
                    date(it.date),
                    it.timestamp?.let { timestamp -> time(timestamp, input.zoneId) }.orEmpty(),
                    formatted(it.value),
                    it.source?.displayLabel(vocabulary).orEmpty(),
                )
            },
        ) else null
        return summary(metric, facts, values.map { it.source }, days, input, table)
    }

    private fun daily(metric: ReportMetric, input: ClinicianReportInput): MetricReportSummary {
        val range = input.configuration.dateRange
        val values = dedupe(input.dailyValues.filter { it.metric == metric && it.date in range.startDate..range.endDate }) { it.stableId }
            .sortedWith(compareBy<DailyReportValue> { it.date })
        if (values.isEmpty()) return empty(metric)
        val days = values.map { it.date }.toSet().size
        val converter = UnitConverter(input.configuration.unitPreference)
        val facts = when (metric) {
            ReportMetric.RESTING_HEART_RATE -> listOf(
                ReportFact(vocabulary.text(ClinicianReportText.FACT_DAYS_WITH_DATA), days.toString()),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_MEDIAN), "${one(median(values.map { it.value }))} bpm"),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_RANGE), "${one(values.minOf { it.value })}–${one(values.maxOf { it.value })} bpm"),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_MOST_RECENT), vocabulary.text(ClinicianReportText.VALUE_ON_DATE, "${one(values.last().value)} bpm", date(values.last().date))),
            )
            ReportMetric.WEIGHT -> listOf(
                ReportFact(vocabulary.text(ClinicianReportText.FACT_DAILY_VALUES), values.size.toString()),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_DAYS_WITH_DATA), days.toString()),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_FIRST), vocabulary.text(ClinicianReportText.VALUE_ON_DATE, formatWeight(values.first().value, converter), date(values.first().date))),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_MOST_RECENT), vocabulary.text(ClinicianReportText.VALUE_ON_DATE, formatWeight(values.last().value, converter), date(values.last().date))),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_CHANGE), signed(converter.convertWeight(values.last().value - values.first().value), converter.weightUnit())),
            )
            ReportMetric.STEPS -> listOf(
                ReportFact(vocabulary.text(ClinicianReportText.FACT_DAYS_WITH_DATA), days.toString()),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_TOTAL), vocabulary.text(ClinicianReportText.STEP_TOTAL, whole(values.sumOf { it.value }))),
                ReportFact(vocabulary.text(ClinicianReportText.FACT_AVERAGE_DATA_DAYS), vocabulary.text(ClinicianReportText.STEP_AVERAGE, whole(values.map { it.value }.average()))),
            )
            else -> emptyList()
        }
        val table = if (input.configuration.detailLevel == ReportDetailLevel.SUMMARY_AND_READINGS) {
            val valueLabel = when (metric) {
                ReportMetric.WEIGHT -> vocabulary.text(ClinicianReportText.COLUMN_WEIGHT)
                ReportMetric.STEPS -> vocabulary.text(ClinicianReportText.COLUMN_STEPS)
                else -> vocabulary.text(ClinicianReportText.COLUMN_VALUE)
            }
            val columns = if (metric == ReportMetric.STEPS) {
                listOf(vocabulary.text(ClinicianReportText.COLUMN_DATE), valueLabel)
            } else {
                listOf(vocabulary.text(ClinicianReportText.COLUMN_DATE), valueLabel, vocabulary.text(ClinicianReportText.COLUMN_SOURCE))
            }
            ReportTable(
                vocabulary.text(ClinicianReportText.TABLE_METRIC_READINGS, vocabulary.metricName(metric)),
                columns,
                values.map {
                    val value = when (metric) {
                        ReportMetric.WEIGHT -> formatWeight(it.value, converter)
                        ReportMetric.STEPS -> vocabulary.text(ClinicianReportText.STEP_TOTAL, whole(it.value))
                        else -> one(it.value)
                    }
                    if (metric == ReportMetric.STEPS) listOf(date(it.date), value) else listOf(date(it.date), value, it.source?.displayLabel(vocabulary).orEmpty())
                },
            )
        } else null
        return summary(metric, facts, values.map { it.source }, days, input, table)
    }

    private fun sleep(input: ClinicianReportInput): MetricReportSummary {
        val range = input.configuration.dateRange
        val values = dedupe(input.sleepObservations.filter { it.date in range.startDate..range.endDate }) { it.stableId }.sortedBy { it.date }
        if (values.isEmpty()) return empty(ReportMetric.SLEEP_DURATION)
        val days = values.map { it.date }.toSet().size
        val facts = listOf(
            ReportFact(vocabulary.text(ClinicianReportText.FACT_NIGHTS_WITH_DATA), days.toString()),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_MEDIAN_SLEEP), duration(median(values.map { it.durationMinutes }))),
        )
        val table = if (input.configuration.detailLevel == ReportDetailLevel.SUMMARY_AND_READINGS) ReportTable(
            vocabulary.text(ClinicianReportText.TABLE_SLEEP),
            listOf(
                vocabulary.text(ClinicianReportText.COLUMN_NIGHT),
                vocabulary.text(ClinicianReportText.COLUMN_DURATION),
                vocabulary.text(ClinicianReportText.COLUMN_SOURCE),
            ),
            values.map { listOf(date(it.date), duration(it.durationMinutes), it.source?.displayLabel(vocabulary).orEmpty()) },
        ) else null
        return summary(ReportMetric.SLEEP_DURATION, facts, values.map { it.source }, days, input, table)
    }

    private fun workouts(input: ClinicianReportInput, interval: ReportInstantRange): MetricReportSummary {
        val values = dedupe(input.workoutObservations.filter { interval.contains(it.timestamp) }) { it.stableId }.sortedBy { it.timestamp }
        if (values.isEmpty()) return empty(ReportMetric.WORKOUTS)
        val days = values.map { localDate(it.timestamp, input.zoneId) }.toSet().size
        val breakdown = values.groupingBy { it.type }.eachCount().entries
            .map { Triple(it.key, vocabulary.workoutName(it.key), it.value) }
            .sortedBy { it.second }
            .joinToString(", ") { vocabulary.text(ClinicianReportText.WORKOUT_BREAKDOWN_ITEM, it.second, it.third.toString()) }
        val facts = listOf(
            ReportFact(vocabulary.text(ClinicianReportText.FACT_SESSIONS), values.size.toString()),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_TOTAL_DURATION), duration(values.sumOf { it.durationMinutes })),
            ReportFact(vocabulary.text(ClinicianReportText.FACT_WORKOUT_TYPE), breakdown),
        )
        val table = if (input.configuration.detailLevel == ReportDetailLevel.SUMMARY_AND_READINGS) ReportTable(
            vocabulary.text(ClinicianReportText.TABLE_WORKOUTS),
            listOf(
                vocabulary.text(ClinicianReportText.COLUMN_DATE),
                vocabulary.text(ClinicianReportText.COLUMN_TIME),
                vocabulary.text(ClinicianReportText.COLUMN_TYPE),
                vocabulary.text(ClinicianReportText.COLUMN_DURATION),
                vocabulary.text(ClinicianReportText.COLUMN_SOURCE),
            ),
            values.map {
                listOf(
                    date(localDate(it.timestamp, input.zoneId)),
                    time(it.timestamp, input.zoneId),
                    vocabulary.workoutName(it.type),
                    duration(it.durationMinutes),
                    it.source?.displayLabel(vocabulary).orEmpty(),
                )
            },
        ) else null
        return summary(ReportMetric.WORKOUTS, facts, values.map { it.source }, days, input, table)
    }

    private data class ScalarValue(
        val date: LocalDate,
        val timestamp: Instant?,
        val value: Double,
        val stableId: String?,
        val source: ReportSource?,
    )

    private fun summary(
        metric: ReportMetric,
        facts: List<ReportFact>,
        rawSources: List<ReportSource?>,
        days: Int,
        input: ClinicianReportInput,
        table: ReportTable?,
    ): MetricReportSummary {
        val sourceLabels = rawSources.mapNotNull {
            it?.displayLabel(vocabulary)?.trim()?.takeIf(String::isNotEmpty)
        }.distinct().sorted()
        return MetricReportSummary(
            metric = metric,
            facts = facts,
            sources = sourceLabels,
            coverageDisclosure = coverage(days, input.configuration.dateRange.inclusiveDayCount),
            noDataMessage = null,
            table = table,
            localizedTitle = vocabulary.metricName(metric),
            sourcesDisclosure = sourceLabels.takeIf(List<String>::isNotEmpty)?.let {
                vocabulary.text(ClinicianReportText.SOURCES, it.joinToString(", "))
            },
            detailReadingsDescription = table?.let {
                vocabulary.text(ClinicianReportText.DETAIL_READINGS_COUNT, it.rows.size.toString())
            },
        )
    }

    private fun empty(metric: ReportMetric) = MetricReportSummary(
        metric = metric,
        facts = emptyList(),
        sources = emptyList(),
        coverageDisclosure = null,
        noDataMessage = vocabulary.text(ClinicianReportText.NO_DATA),
        table = null,
        localizedTitle = vocabulary.metricName(metric),
    )

    private fun coverage(days: Int, expected: Int): String {
        val missing = (expected - days).coerceAtLeast(0)
        return vocabulary.text(ClinicianReportText.COVERAGE, days.toString(), expected.toString(), missing.toString())
    }

    private fun <T> dedupe(values: List<T>, id: (T) -> String?): List<T> {
        val seen = mutableSetOf<String>()
        return values.filter { value -> id(value)?.let(seen::add) ?: true }
    }

    private fun localDate(instant: Instant, zoneId: ZoneId) = instant.atZone(zoneId).toLocalDate()
    private fun date(value: LocalDate): String = value.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale))
    private fun dateTime(value: Instant, zoneId: ZoneId): String = value.atZone(zoneId).format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM).withLocale(locale))
    private fun time(value: Instant, zoneId: ZoneId): String = value.atZone(zoneId).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
    private fun one(value: Double) = String.format(locale, "%.1f", value)
    private fun whole(value: Double) = String.format(locale, "%.0f", value)
    private fun median(values: List<Double>): Double {
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2 else sorted[middle]
    }
    private fun duration(minutes: Double): String {
        val rounded = minutes.toInt().coerceAtLeast(0)
        val hours = rounded / 60
        val remainder = rounded % 60
        if (hours == 0) return vocabulary.text(ClinicianReportText.DURATION_MINUTES, remainder.toString())
        val hourText = vocabulary.text(ClinicianReportText.DURATION_HOURS, hours.toString())
        return if (remainder == 0) hourText else vocabulary.text(
            ClinicianReportText.DURATION_HOURS_MINUTES,
            hourText,
            vocabulary.text(ClinicianReportText.DURATION_MINUTES, remainder.toString()),
        )
    }
    private fun signed(value: Double, unit: String): String = (if (value > 0) "+" else if (abs(value) < 0.05) "" else "") + one(value) + " " + unit
    private fun unit(metric: ReportMetric, input: ClinicianReportInput): String = when (metric) {
        ReportMetric.HEART_RATE, ReportMetric.RESTING_HEART_RATE -> "bpm"
        ReportMetric.BLOOD_GLUCOSE -> "mg/dL"
        ReportMetric.OXYGEN_SATURATION -> "%"
        ReportMetric.RESPIRATORY_RATE -> vocabulary.text(ClinicianReportText.UNIT_RESPIRATORY_RATE)
        ReportMetric.BODY_TEMPERATURE -> UnitConverter(input.configuration.unitPreference).temperatureUnit()
        else -> ""
    }
    private fun formatWeight(kilograms: Double, converter: UnitConverter): String = "${one(converter.convertWeight(kilograms))} ${converter.weightUnit()}"
    private fun formatValue(metric: ReportMetric, value: Double, input: ClinicianReportInput): String = when (metric) {
        ReportMetric.OXYGEN_SATURATION -> one(value * 100)
        ReportMetric.BODY_TEMPERATURE -> one(UnitConverter(input.configuration.unitPreference).convertTemperature(value))
        else -> one(value)
    }
}
