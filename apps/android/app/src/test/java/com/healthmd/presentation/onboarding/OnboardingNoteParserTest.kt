package com.healthmd.presentation.onboarding

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.onboarding.HealthPack
import java.time.LocalDate
import org.junit.Test

class OnboardingNoteParserTest {
    private val markdown = """
        ---
        date: 2026-11-12
        type: health-data
        sleep_total_hours: 7.70
        ---

        # Health Data — 2026-11-12

        ## 😴 Sleep

        - **Total:** 7h 42m
        - **Deep:** 1h 18m

        | Start | End | Stage |
        |-------|-----|-------|

        ## Activity

        - **Steps:** 8,432
        - **Active Calories:** 624 kcal

        ## Heart

        - **HRV (RMSSD):** 48.0 ms
    """.trimIndent()

    @Test
    fun parsesDefaultTemplateSectionsAndRows() {
        val sections = OnboardingNoteParser.parse(markdown)

        assertThat(sections.map { it.title }).containsExactly("Sleep", "Activity", "Heart").inOrder()
        assertThat(sections.map { it.pack }).containsExactly(HealthPack.SLEEP, HealthPack.ACTIVITY, HealthPack.HEART).inOrder()
        assertThat(sections[0].rows).containsExactly(NoteRow("Total", "7h 42m"), NoteRow("Deep", "1h 18m")).inOrder()
        assertThat(sections[2].rows.single()).isEqualTo(NoteRow("HRV (RMSSD)", "48.0 ms"))
        // Frontmatter keys never become rendered rows.
        assertThat(sections.flatMap { it.rows }.map { it.label }).doesNotContain("sleep_total_hours")
    }

    @Test
    fun buildsSevenDaysKeepingDaysWithoutNotes() {
        val dates = OnboardingFlow.firstNoteDates(LocalDate.of(2026, 11, 12))
        val preview = ExportPreview(
            requestedDateCount = 7,
            previewedDateCount = 1,
            isTruncated = false,
            days = listOf(
                ExportPreviewDay(
                    date = LocalDate.of(2026, 11, 12),
                    files = listOf(
                        ExportPreviewFile(ExportFormat.JSON, "health/2026-11-12.json", 2, "{}"),
                        ExportPreviewFile(ExportFormat.MARKDOWN, "health/2026-11-12.md", markdown.length, markdown),
                    ),
                ),
            ),
        )

        val days = OnboardingNoteParser.days(dates, preview)

        assertThat(days.map { it.date }).isEqualTo(dates)
        assertThat(days.count { it.hasNote }).isEqualTo(1)
        val last = days.last()
        assertThat(last.fileName).isEqualTo("2026-11-12.md")
        assertThat(last.raw).isEqualTo(markdown)
        assertThat(OnboardingNoteParser.chartValue(last)).isEqualTo(462.0)
        assertThat(OnboardingNoteParser.chartIsSleep(days)).isTrue()
        assertThat(OnboardingNoteParser.highlights(last.sections).map { it.second.label })
            .containsExactly("Total", "Steps", "HRV (RMSSD)").inOrder()
    }

    @Test
    fun durationParsingIgnoresMilliseconds() {
        assertThat(OnboardingNoteParser.durationMinutes("7h 42m")).isEqualTo(462.0)
        assertThat(OnboardingNoteParser.durationMinutes("45m")).isEqualTo(45.0)
        assertThat(OnboardingNoteParser.durationMinutes("48 ms")).isNull()
    }

    @Test
    fun sampleNoteCoversOnlyThePickedPacksAndIsNotRealData() {
        val dates = OnboardingFlow.firstNoteDates(LocalDate.of(2026, 11, 12))
        val days = OnboardingSampleNote.days(dates, setOf(HealthPack.SLEEP, HealthPack.BODY))

        assertThat(days).hasSize(7)
        assertThat(days.first().sections.map { it.pack }).containsExactly(HealthPack.SLEEP, HealthPack.BODY).inOrder()
        // The sample's raw file round-trips through the same renderer as real notes.
        assertThat(OnboardingNoteParser.parse(days.first().raw!!)).isEqualTo(days.first().sections)
    }
}
