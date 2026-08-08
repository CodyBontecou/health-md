package com.healthmd.clinicianreport

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.clinicianreport.*
import com.healthmd.domain.model.WorkoutType
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class ClinicianReportLocalizationTest {
    @Test fun representativeSupportedLocalesResolveExplicitDocumentVocabulary() {
        val expected = mapOf(
            "ar-SA" to "الملخص الصحي",
            "bn-BD" to "স্বাস্থ্য সারাংশ",
            "hi-IN" to "स्वास्थ्य सारांश",
            "pa-Guru-IN" to "ਸਿਹਤ ਸਾਰ",
            "zh-Hans-CN" to "健康摘要",
            "ja-JP" to "健康サマリー",
            "kk-KZ" to "Денсаулық туралы жиынтық",
            "ru-RU" to "Сводка о здоровье",
            "uk-UA" to "Зведення про здоров’я",
            "ro-RO" to "Rezumat al datelor de sănătate",
            "de-DE" to "Gesundheitsübersicht",
            "pt-BR" to "Resumo de saúde",
        )
        expected.forEach { (requested, title) ->
            val vocabulary = reportVocabulary(Locale.forLanguageTag(requested))
            assertThat(vocabulary.text(ClinicianReportText.DOCUMENT_TITLE)).isEqualTo(title)
            assertThat(vocabulary.text(ClinicianReportText.COVERAGE, "1", "3", "2")).doesNotContain("%")
            assertThat(vocabulary.text(ClinicianReportText.PRACTICE_LINE, "healthmd.app/practice")).contains("healthmd.app/practice")
        }
    }

    @Test fun unsupportedLocaleUsesEnglishContentAndTagButPreservesPaperRegion() {
        val vocabulary = reportVocabulary(Locale.forLanguageTag("it-IT"))
        assertThat(vocabulary.languageTag).isEqualTo("en")
        assertThat(vocabulary.paperRegionCode).isEqualTo("IT")
        assertThat(vocabulary.isRtl).isFalse()
        assertThat(vocabulary.text(ClinicianReportText.DOCUMENT_TITLE)).isEqualTo("Health Summary")
        val report = generator(vocabulary, setOf(ReportMetric.STEPS))
        assertThat(report.languageTag).isEqualTo("en")
        assertThat(report.paperRegionCode).isEqualTo("IT")
    }

    @Test fun allNormalizedWorkoutTypesAndRespiratoryUnitsAreLocalized() {
        val locales = listOf("ar-SA", "bn-BD", "de-DE", "hi-IN", "ja-JP", "kk-KZ", "pa-Guru-IN", "pt-BR", "ro-RO", "ru-RU", "uk-UA", "zh-Hans-CN")
        locales.forEach { requested ->
            val vocabulary = reportVocabulary(Locale.forLanguageTag(requested))
            assertThat(WorkoutType.entries).hasSize(42)
            WorkoutType.entries.forEach { type ->
                val label = vocabulary.workoutName(type)
                assertThat(label).isNotEmpty()
                assertThat(label).doesNotContain("clinician_report_")
            }
            assertThat(vocabulary.text(ClinicianReportText.UNIT_RESPIRATORY_RATE)).isNotEmpty()
        }
        assertThat(reportVocabulary(Locale.GERMANY).workoutName(WorkoutType.RUNNING)).isEqualTo("Laufen")
        assertThat(reportVocabulary(Locale.GERMANY).text(ClinicianReportText.UNIT_RESPIRATORY_RATE)).isEqualTo("Atemzüge/min")
    }

    @Test fun localePinsWarningsManualProvenanceNumbersDatesAndModelCopy() {
        val vocabulary = reportVocabulary(Locale.GERMANY)
        val range = ReportDateRange(LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 3))
        val report = ClinicianReportGenerator(vocabulary).generate(
            ClinicianReportInput(
                configuration = ReportConfiguration(range, setOf(ReportMetric.RESPIRATORY_RATE, ReportMetric.WEIGHT, ReportMetric.WORKOUTS), ReportDetailLevel.SUMMARY_AND_READINGS),
                zoneId = ZoneId.of("Europe/Berlin"),
                generatedAt = Instant.parse("2026-03-04T12:00:00Z"),
                scalarObservations = listOf(ScalarReportObservation(ReportMetric.RESPIRATORY_RATE, Instant.parse("2026-03-01T08:00:00Z"), 15.25, source = ReportSource("", true))),
                dailyValues = listOf(DailyReportValue(ReportMetric.WEIGHT, range.startDate, 80.25)),
                workoutObservations = listOf(WorkoutReportObservation(Instant.parse("2026-03-01T09:00:00Z"), WorkoutType.RUNNING, 30.0)),
                warnings = listOf(ClinicianReportWarning.SourceFailure(range.startDate)),
            ),
        )
        assertThat(report.dateRangeLabel).contains("01.03.2026")
        assertThat(report.warnings.single()).doesNotContain("connected health sources")
        assertThat(report.sections.single { it.metric == ReportMetric.RESPIRATORY_RATE }.facts.any { it.value.contains("15,3 Atemzüge/min") }).isTrue()
        assertThat(report.sections.single { it.metric == ReportMetric.RESPIRATORY_RATE }.sources.single()).isEqualTo("Manuelle Eingabe")
        assertThat(report.sections.single { it.metric == ReportMetric.WEIGHT }.facts.any { it.value.contains("80,3 kg") }).isTrue()
        assertThat(report.sections.single { it.metric == ReportMetric.WORKOUTS }.table!!.rows.single()[2]).isEqualTo("Laufen")
        assertThat(report.sections.all { it.localizedTitle.isNotBlank() }).isTrue()
        assertThat(report.sections.none { it.sourcesDisclosure?.startsWith("Sources:") == true }).isTrue()
    }

    @Test fun arabicIsRtlAndUsesPinnedA4Region() {
        val vocabulary = reportVocabulary(Locale.forLanguageTag("ar-SA"))
        assertThat(vocabulary.languageTag).isEqualTo("ar")
        assertThat(vocabulary.paperRegionCode).isEqualTo("SA")
        assertThat(vocabulary.isRtl).isTrue()
    }

    private fun generator(vocabulary: ClinicianReportVocabulary, metrics: Set<ReportMetric>): ClinicianReportData {
        val date = LocalDate.of(2026, 1, 1)
        return ClinicianReportGenerator(vocabulary).generate(
            ClinicianReportInput(ReportConfiguration(ReportDateRange(date, date), metrics), ZoneId.of("UTC"), Instant.parse("2026-01-02T00:00:00Z")),
        )
    }
}
