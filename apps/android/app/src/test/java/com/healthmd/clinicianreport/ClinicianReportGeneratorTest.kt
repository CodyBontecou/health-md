package com.healthmd.clinicianreport

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.clinicianreport.*
import com.healthmd.domain.model.UnitPreference
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class ClinicianReportGeneratorTest {
    private val zone = ZoneId.of("America/New_York")
    private val range = ReportDateRange(LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 30))
    private val generator = ClinicianReportGenerator(reportVocabulary(Locale.US))

    @Test fun presetsAndCustomRangesAreInclusiveNormalizedAndFutureClamped() {
        val today = LocalDate.of(2026, 8, 8)
        assertThat(ReportDateRange.preset(ReportDateRangePreset.DAYS_30, today).inclusiveDayCount).isEqualTo(30)
        assertThat(ReportDateRange.normalized(today.plusDays(3), today.minusDays(4), today))
            .isEqualTo(ReportDateRange(today.minusDays(4), today))
    }

    @Test fun calendarIntervalsHonorDstAndHalfOpenBoundaries() {
        val spring = ReportDateRange(LocalDate.of(2026, 3, 8), LocalDate.of(2026, 3, 8)).interval(zone)
        val fall = ReportDateRange(LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 1)).interval(zone)
        assertThat(spring.endExclusive.epochSecond - spring.startInclusive.epochSecond).isEqualTo(23 * 3600)
        assertThat(fall.endExclusive.epochSecond - fall.startInclusive.epochSecond).isEqualTo(25 * 3600)
        assertThat(spring.contains(spring.startInclusive)).isTrue()
        assertThat(spring.contains(spring.endExclusive)).isFalse()
    }

    @Test fun emptySelectionProducesNoDataSection() {
        val report = generate(metrics = setOf(ReportMetric.BLOOD_GLUCOSE))
        assertThat(report.sections.single().noDataMessage).isEqualTo(reportVocabulary(Locale.US).text(ClinicianReportText.NO_DATA))
    }

    @Test fun scalarMedianCoverageSourcesAndStableDedupeAreCorrect() {
        val observations = listOf(
            scalar(60.0, "2026-03-01T15:00:00Z", "same", ReportSource("z.app")),
            scalar(60.0, "2026-03-01T15:00:00Z", "same", ReportSource("z.app")),
            scalar(64.0, "2026-03-01T16:00:00Z", null, ReportSource("Alpha", true)),
            scalar(66.0, "2026-03-02T16:00:00Z", null, null),
        )
        val report = generate(setOf(ReportMetric.HEART_RATE), scalars = observations)
        val section = report.sections.single()
        assertThat(section.facts.first { it.label == "Readings" }.value).isEqualTo("3")
        assertThat(section.facts.first { it.label == "Median" }.value).isEqualTo("64.0 bpm")
        assertThat(section.coverageDisclosure).contains("2 of 30 days")
        assertThat(section.sources).containsExactly("Alpha (manual entry)", "z.app").inOrder()
    }

    @Test fun evenMedianAndOxygenFractionFormattingAreCorrect() {
        val report = generate(
            setOf(ReportMetric.OXYGEN_SATURATION),
            scalars = listOf(
                ScalarReportObservation(ReportMetric.OXYGEN_SATURATION, Instant.parse("2026-03-02T12:00:00Z"), .95),
                ScalarReportObservation(ReportMetric.OXYGEN_SATURATION, Instant.parse("2026-03-03T12:00:00Z"), .97),
            ),
        )
        assertThat(report.sections.single().facts.first { it.label == "Median" }.value).isEqualTo("96.0 %")
    }

    @Test fun bloodPressureUsesPairedObservationsForMeansAndNoPulseColumn() {
        val input = baseInput(setOf(ReportMetric.BLOOD_PRESSURE)).copy(
            bloodPressureObservations = listOf(
                BloodPressureReportObservation(Instant.parse("2026-03-03T12:00:00Z"), 120.0, 80.0),
                BloodPressureReportObservation(Instant.parse("2026-03-04T12:00:00Z"), 140.0, 90.0),
            ),
            configuration = config(setOf(ReportMetric.BLOOD_PRESSURE)).copy(detailLevel = ReportDetailLevel.SUMMARY_AND_READINGS),
        )
        val section = generator.generate(input).sections.single()
        assertThat(section.facts.first { it.label == "Average" }.value).isEqualTo("130/85 mmHg")
        assertThat(section.table!!.columns).doesNotContain("Pulse")
        assertThat(section.table!!.rows).hasSize(2)
    }

    @Test fun weightUsesExistingImperialConversionAndChange() {
        val input = baseInput(setOf(ReportMetric.WEIGHT)).copy(
            configuration = config(setOf(ReportMetric.WEIGHT)).copy(unitPreference = UnitPreference.IMPERIAL),
            dailyValues = listOf(
                DailyReportValue(ReportMetric.WEIGHT, range.startDate, 80.0),
                DailyReportValue(ReportMetric.WEIGHT, range.endDate, 78.0),
            ),
        )
        val facts = generator.generate(input).sections.single().facts
        assertThat(facts.first { it.label == "First" }.value).contains("176.4 lbs")
        assertThat(facts.first { it.label == "Change over period" }.value).contains("-4.4 lbs")
    }

    @Test fun stepsDoNotTreatMissingDaysAsZero() {
        val input = baseInput(setOf(ReportMetric.STEPS)).copy(dailyValues = listOf(
            DailyReportValue(ReportMetric.STEPS, range.startDate, 1000.0),
            DailyReportValue(ReportMetric.STEPS, range.startDate.plusDays(1), 3000.0),
        ))
        val facts = generator.generate(input).sections.single().facts
        assertThat(facts.first { it.label == "Average on days with data" }.value).isEqualTo("2000 steps/day")
    }

    @Test fun stepsReadingsTableOmitsUnsupportedSourceColumn() {
        val input = baseInput(setOf(ReportMetric.STEPS)).copy(
            configuration = config(setOf(ReportMetric.STEPS)).copy(detailLevel = ReportDetailLevel.SUMMARY_AND_READINGS),
            dailyValues = listOf(DailyReportValue(ReportMetric.STEPS, range.startDate, 1234.0)),
        )
        assertThat(generator.generate(input).sections.single().table!!.columns).containsExactly("Date", "Steps").inOrder()
    }

    @Test fun largeReadingCountProducesCompleteTableWithoutFailure() {
        val start = range.startDate.atStartOfDay(zone).toInstant()
        val values = (0 until 10_001).map { index -> ScalarReportObservation(ReportMetric.HEART_RATE, start.plusSeconds(index.toLong()), 50.0 + index % 100) }
        val input = baseInput(setOf(ReportMetric.HEART_RATE)).copy(
            configuration = config(setOf(ReportMetric.HEART_RATE)).copy(detailLevel = ReportDetailLevel.SUMMARY_AND_READINGS),
            scalarObservations = values,
        )
        assertThat(generator.generate(input).sections.single().table!!.rows).hasSize(10_001)
    }

    private fun scalar(value: Double, time: String, id: String?, source: ReportSource?) = ScalarReportObservation(ReportMetric.HEART_RATE, Instant.parse(time), value, id, source)
    private fun generate(metrics: Set<ReportMetric>, scalars: List<ScalarReportObservation> = emptyList()) = generator.generate(baseInput(metrics).copy(scalarObservations = scalars))
    private fun config(metrics: Set<ReportMetric>) = ReportConfiguration(range, metrics)
    private fun baseInput(metrics: Set<ReportMetric>) = ClinicianReportInput(config(metrics), zone, Instant.parse("2026-03-31T12:00:00Z"))
}
