package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.InjectionResult
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import org.junit.Test

class DailyNoteInjectorTest {

    private val injector = DailyNoteInjector()

    @Test
    fun frontmatterOnlyAddsYamlToNoteWithoutExistingFrontmatter() {
        val existing = """
            Morning pages.

            ## Journal

            Kept my own note.
        """.trimIndent()

        val (result, content) = injector.inject(
            existingContent = existing,
            data = ExportFixtures.partialDay,
            settings = DailyNoteInjectionSettings(enabled = true),
        )

        assertThat(result).isEqualTo(InjectionResult.UPDATED)
        assertThat(content).startsWith("---\ndate: 2026-03-15")
        assertThat(content).contains("sleep_total_hours: 7.50")
        assertThat(content).contains("steps: 8500")
        assertThat(content).contains("Morning pages.")
        assertThat(content).contains("## Journal\n\nKept my own note.")
        assertThat(content).doesNotContain("## Activity")
    }

    @Test
    fun frontmatterOnlyPreservesExistingFrontmatterAndCustomBody() {
        val existing = """
            ---
            date: 2026-03-15
            mood: focused
            steps: 100
            ---

            Personal note before exported sections.

            ## Journal

            I wrote this myself.
        """.trimIndent()

        val (result, content) = injector.inject(
            existingContent = existing,
            data = ExportFixtures.partialDay,
            settings = DailyNoteInjectionSettings(enabled = true),
        )

        assertThat(result).isEqualTo(InjectionResult.UPDATED)
        assertThat(content).contains("mood: focused")
        assertThat(content).contains("steps: 8500")
        assertThat(content).contains("Personal note before exported sections.")
        assertThat(content).contains("## Journal\n\nI wrote this myself.")
        assertThat(content).doesNotContain("## Sleep")
    }

    @Test
    fun markdownSectionInjectionReplacesManagedSectionsAndPreservesUserSections() {
        val existing = """
            ---
            date: 2026-03-15
            mood: focused
            ---

            Personal note before exported sections.

            ## Sleep

            - old sleep value

            ## Journal

            I wrote this myself.
        """.trimIndent()

        val (result, content) = injector.inject(
            existingContent = existing,
            data = ExportFixtures.partialDay,
            settings = DailyNoteInjectionSettings(
                enabled = true,
                injectMarkdownSections = true,
            ),
        )

        assertThat(result).isEqualTo(InjectionResult.UPDATED)
        assertThat(content).contains("mood: focused")
        assertThat(content).contains("Personal note before exported sections.")
        assertThat(content).contains("## Journal\n\nI wrote this myself.")
        assertThat(content).contains("## Sleep")
        assertThat(content).contains("**Total:** 7h 30m")
        assertThat(content).contains("## Activity")
        assertThat(content).contains("**Steps:** 8,500")
        assertThat(content).doesNotContain("- old sleep value")
    }

    @Test
    fun missingNoteCreatesDailyNoteWithDateTitleAndSectionsWhenEnabled() {
        val (result, content) = injector.inject(
            existingContent = null,
            data = ExportFixtures.partialDay,
            settings = DailyNoteInjectionSettings(
                enabled = true,
                createIfMissing = true,
                injectMarkdownSections = true,
            ),
        )

        assertThat(result).isEqualTo(InjectionResult.CREATED)
        assertThat(content).startsWith("---\ndate: 2026-03-15")
        assertThat(content).contains("# 2026-03-15")
        assertThat(content).contains("# Health Data — 2026-03-15")
        assertThat(content).contains("## Activity")
    }

    @Test
    fun missingNoteSkipsWhenCreateIfMissingIsFalse() {
        val (result, content) = injector.inject(
            existingContent = null,
            data = ExportFixtures.partialDay,
            settings = DailyNoteInjectionSettings(
                enabled = true,
                createIfMissing = false,
                injectMarkdownSections = true,
            ),
        )

        assertThat(result).isEqualTo(InjectionResult.SKIPPED)
        assertThat(content).isNull()
    }

    @Test
    fun customFrontmatterKeysAndDisabledFieldsAreRespected() {
        val fields = FrontmatterConfiguration.defaultFields.map { field ->
            when (field.originalKey) {
                "steps" -> field.copy(customKey = "daily_steps")
                "active_calories" -> field.copy(isEnabled = false)
                else -> field
            }
        }
        val customization = FormatCustomization(
            frontmatterConfig = FrontmatterConfiguration(
                fields = fields,
                includeDate = true,
                customDateKey = "day",
            ),
        )

        val (_, content) = injector.inject(
            existingContent = "Today was good.",
            data = ExportFixtures.partialDay,
            settings = DailyNoteInjectionSettings(enabled = true),
            customization = customization,
        )

        assertThat(content).contains("day: 2026-03-15")
        assertThat(content).contains("daily_steps: 8500")
        assertThat(content).doesNotContain("\nsteps: 8500")
        assertThat(content).doesNotContain("active_calories:")
        assertThat(content).contains("Today was good.")
    }
}
