package com.healthmd.clinicianreport

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.AndroidClinicianReportPdfRenderer
import com.healthmd.domain.clinicianreport.BloodPressureReportObservation
import com.healthmd.domain.clinicianreport.ClinicianReportData
import com.healthmd.domain.clinicianreport.ClinicianReportGenerator
import com.healthmd.domain.clinicianreport.ClinicianReportInput
import com.healthmd.domain.clinicianreport.DailyReportValue
import com.healthmd.domain.clinicianreport.ReportConfiguration
import com.healthmd.domain.clinicianreport.ReportDateRange
import com.healthmd.domain.clinicianreport.ReportDetailLevel
import com.healthmd.domain.clinicianreport.ReportMetric
import com.healthmd.domain.clinicianreport.ReportSource
import com.healthmd.domain.clinicianreport.ScalarReportObservation
import com.healthmd.domain.clinicianreport.SleepReportObservation
import com.healthmd.domain.clinicianreport.WorkoutReportObservation
import com.healthmd.domain.model.WorkoutType
import com.tom_roush.pdfbox.pdmodel.PDDocument
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.system.measureNanoTime

/** Deterministic Linux benchmarks with structural assertions and no flaky time threshold. */
@RunWith(RobolectricTestRunner::class)
class ClinicianReportDense90DayBenchmarkTest {
    @Test
    fun denseNinetyDayGeneratorBenchmark() {
        val input = denseInput()
        val generator = ClinicianReportGenerator(reportVocabulary(Locale.US))

        repeat(WARMUP_ITERATIONS) { generator.generate(input) }

        lateinit var report: ClinicianReportData
        val elapsedNanos = LongArray(MEASURED_ITERATIONS) { index ->
            measureNanoTime {
                report = generator.generate(input)
                // Consume deterministic structure so the measured result cannot be discarded.
                check(report.sections.sumOf { it.table?.rows?.size ?: 0 } == EXPECTED_TABLE_ROWS)
            }.also { elapsed ->
                check(elapsed > 0) { "Benchmark clock did not advance at iteration $index" }
            }
        }.sorted()

        val heart = report.sections.single { it.metric == ReportMetric.HEART_RATE }
        assertThat(report.sections).hasSize(ReportMetric.entries.size)
        assertThat(heart.table!!.rows).hasSize(HEART_READING_COUNT)
        assertThat(report.sections.sumOf { it.table?.rows?.size ?: 0 }).isEqualTo(EXPECTED_TABLE_ROWS)
        assertThat(report.dateRangeLabel).contains("Jan 1, 2026")
        assertThat(report.dateRangeLabel).contains("Mar 31, 2026")

        val medianNanos = elapsedNanos[elapsedNanos.size / 2]
        println(
            "CLINICIAN_REPORT_DENSE_90_DAY_BENCHMARK " +
                "warmups=$WARMUP_ITERATIONS iterations=$MEASURED_ITERATIONS " +
                "days=90 heartReadings=$HEART_READING_COUNT tableRows=$EXPECTED_TABLE_ROWS " +
                "minMs=${millis(elapsedNanos.first())} medianMs=${millis(medianNanos)} " +
                "maxMs=${millis(elapsedNanos.last())} sections=${report.sections.size}",
        )
    }

    @Test
    fun denseNinetyDayTaggedPdfBenchmark() {
        assumeTrue(System.getenv("HEALTHMD_CLINICIAN_REPORT_DENSE_PDF_BENCHMARK") == "1")
        val report = ClinicianReportGenerator(reportVocabulary(Locale.US)).generate(denseInput())
        assertThat(report.sections.sumOf { it.table?.rows?.size ?: 0 }).isEqualTo(EXPECTED_TABLE_ROWS)
        val renderer = AndroidClinicianReportPdfRenderer(ApplicationProvider.getApplicationContext<Context>())
        var pageCount = 0
        var byteCount = 0
        val pageCounts = mutableSetOf<Int>()
        val byteCounts = mutableSetOf<Int>()
        val elapsed = LongArray(TAGGED_PDF_ITERATIONS) {
            measureNanoTime {
                val bytes = ByteArrayOutputStream().use { output ->
                    pageCount = renderer.render(report, output)
                    output.toByteArray()
                }
                byteCount = bytes.size
                pageCounts += pageCount
                byteCounts += byteCount
                PDDocument.load(bytes).use { document ->
                    check(document.numberOfPages == pageCount)
                    check(document.documentCatalog.structureTreeRoot != null)
                    check(document.documentCatalog.markInfo.isMarked)
                }
            }
        }.sorted()
        assertThat(pageCount).isGreaterThan(1)
        assertThat(byteCount).isGreaterThan(0)
        assertThat(pageCounts).containsExactly(pageCount)
        assertThat(byteCounts).containsExactly(byteCount)
        println(
            "CLINICIAN_REPORT_DENSE_90_DAY_TAGGED_PDF_BENCHMARK " +
                "iterations=$TAGGED_PDF_ITERATIONS days=90 heartReadings=$HEART_READING_COUNT " +
                "tableRows=$EXPECTED_TABLE_ROWS pages=$pageCount bytes=$byteCount " +
                "minMs=${millis(elapsed.first())} medianMs=${millis(elapsed[elapsed.size / 2])} " +
                "maxMs=${millis(elapsed.last())}",
        )
    }

    private fun denseInput(): ClinicianReportInput {
        val zoneId = ZoneId.of("America/New_York")
        val range = ReportDateRange(LocalDate.of(2026, 1, 1), LocalDate.of(2026, 3, 31))
        val dates = range.dates()
        check(dates.size == 90)
        val source = ReportSource("Synthetic Benchmark Source")

        val scalars = ArrayList<ScalarReportObservation>(HEART_READING_COUNT + dates.size * 4)
        dates.forEachIndexed { dayIndex, date ->
            repeat(HEART_READINGS_PER_DAY) { readingIndex ->
                val minuteOfDay = readingIndex * (24 * 60 / HEART_READINGS_PER_DAY)
                scalars += ScalarReportObservation(
                    metric = ReportMetric.HEART_RATE,
                    timestamp = date.atStartOfDay().plusMinutes(minuteOfDay.toLong()).atZone(zoneId).toInstant(),
                    value = 55.0 + ((dayIndex + readingIndex) % 85),
                    stableId = "heart-$dayIndex-$readingIndex",
                    source = source,
                )
            }
            val timestamp = date.atTime(12, 0).atZone(zoneId).toInstant()
            scalars += ScalarReportObservation(ReportMetric.BLOOD_GLUCOSE, timestamp, 85.0 + dayIndex % 30, "glucose-$dayIndex", source)
            scalars += ScalarReportObservation(ReportMetric.OXYGEN_SATURATION, timestamp, .94 + (dayIndex % 5) * .005, "oxygen-$dayIndex", source)
            scalars += ScalarReportObservation(ReportMetric.RESPIRATORY_RATE, timestamp, 12.0 + dayIndex % 8, "respiratory-$dayIndex", source)
            scalars += ScalarReportObservation(ReportMetric.BODY_TEMPERATURE, timestamp, 36.2 + (dayIndex % 8) * .1, "temperature-$dayIndex", source)
        }

        val bloodPressure = dates.flatMapIndexed { dayIndex, date ->
            listOf(8, 20).mapIndexed { readingIndex, hour ->
                BloodPressureReportObservation(
                    timestamp = date.atTime(hour, 0).atZone(zoneId).toInstant(),
                    systolic = 110.0 + (dayIndex + readingIndex) % 25,
                    diastolic = 70.0 + (dayIndex + readingIndex) % 15,
                    stableId = "bp-$dayIndex-$readingIndex",
                    source = source,
                )
            }
        }
        val daily = dates.flatMapIndexed { dayIndex, date ->
            listOf(
                DailyReportValue(ReportMetric.RESTING_HEART_RATE, date, 55.0 + dayIndex % 15, "resting-$dayIndex", source),
                DailyReportValue(ReportMetric.WEIGHT, date, 78.0 + dayIndex * .01, "weight-$dayIndex", source),
                DailyReportValue(ReportMetric.STEPS, date, 5_000.0 + dayIndex * 37, "steps-$dayIndex", null),
            )
        }
        val sleep = dates.mapIndexed { dayIndex, date ->
            SleepReportObservation(date, 390.0 + dayIndex % 90, "sleep-$dayIndex", source)
        }
        val workouts = dates.mapIndexed { dayIndex, date ->
            WorkoutReportObservation(
                timestamp = date.atTime(17, 30).atZone(zoneId).toInstant(),
                type = if (dayIndex % 2 == 0) WorkoutType.WALKING else WorkoutType.CYCLING,
                durationMinutes = 30.0 + dayIndex % 45,
                stableId = "workout-$dayIndex",
                source = source,
            )
        }

        return ClinicianReportInput(
            configuration = ReportConfiguration(
                dateRange = range,
                selectedMetrics = ReportMetric.entries.toSet(),
                detailLevel = ReportDetailLevel.SUMMARY_AND_READINGS,
            ),
            zoneId = zoneId,
            generatedAt = Instant.parse("2026-04-01T12:00:00Z"),
            scalarObservations = scalars,
            bloodPressureObservations = bloodPressure,
            dailyValues = daily,
            sleepObservations = sleep,
            workoutObservations = workouts,
        )
    }

    private fun millis(nanos: Long): String = String.format(Locale.US, "%.3f", nanos / 1_000_000.0)

    companion object {
        private const val HEART_READINGS_PER_DAY = 144
        private const val HEART_READING_COUNT = 90 * HEART_READINGS_PER_DAY
        private const val EXPECTED_TABLE_ROWS = HEART_READING_COUNT + (90 * 4) + (90 * 2) + (90 * 3) + 90 + 90
        private const val WARMUP_ITERATIONS = 3
        private const val MEASURED_ITERATIONS = 9
        private const val TAGGED_PDF_ITERATIONS = 3
    }
}
