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
    fun workoutCountOnlyDoesNotWriteOtherWorkoutProperties() {
        val customization = FormatCustomization(frontmatterConfig = FrontmatterConfiguration(
            includeDate = false,
            fields = FrontmatterConfiguration.defaultFields.map { field ->
                field.copy(isEnabled = field.originalKey == "workout_count")
            },
        ))
        val (result, content) = injector.inject(null, ExportFixtures.fullDay,
            DailyNoteInjectionSettings(enabled = true, createIfMissing = true), customization)
        assertThat(result).isEqualTo(InjectionResult.CREATED)
        val header = requireNotNull(content).lineSequence().drop(1).takeWhile { it != "---" }.toList()
        assertThat(header).containsExactly("workout_count: 1")
    }

    @Test
    fun editorValidationFlagsOnlyEnabledDuplicatesAndReservedNames() {
        assertThat(FrontmatterConfiguration().conflictingOutputKeys).isEmpty()
        val fields = listOf(
            com.healthmd.domain.model.CustomFrontmatterField("workout_count", "same"),
            com.healthmd.domain.model.CustomFrontmatterField("workout_minutes", "same"),
        )
        val config = FrontmatterConfiguration(fields = fields)
        assertThat(config.conflictingOutputKeys).containsExactly("same")
        val legacy = config.copy(fields = listOf(fields.first().copy(customKey = "workout_minutes")))
        assertThat(legacy.conflictingOutputKeys).containsExactly("workout_minutes")
        assertThat(config.copy(fields = fields.map { it.copy(isEnabled = it.originalKey == "workout_count") })
            .conflictingOutputKeys).isEmpty()
        assertThat(config.copy(fields = listOf(fields.first().copy(customKey = "date"))).conflictingOutputKeys)
            .containsExactly("date")
        assertThat(config.copy(fields = listOf(fields.first().copy(customKey = "healthmd_injection_kind"))).conflictingOutputKeys)
            .containsExactly("healthmd_injection_kind")
    }

    @Test
    fun conflictDetailsKeepSourcesAndRouteOnlyCanonicalEditorTags() {
        val fields = listOf(
            com.healthmd.domain.model.CustomFrontmatterField("steps", "local_private_key"),
            com.healthmd.domain.model.CustomFrontmatterField("workout_count", "local_private_key"),
        )
        val config = FrontmatterConfiguration(fields = fields,
            customFields = mapOf("local_private_key" to "value"), placeholderFields = listOf("local_private_key"))
        val conflict = config.keyConflicts.single()
        assertThat(conflict.outputKey).isEqualTo("local_private_key")
        assertThat(conflict.sources.map { it.originalKey }).containsExactly("steps", "workout_count", "local_private_key", "local_private_key").inOrder()
        val targets = conflict.sources.map { com.healthmd.presentation.settings.FrontmatterCustomizationTags.conflictTarget(it) }
        assertThat(targets).containsExactly("frontmatter.output.steps", "frontmatter.output.workout_count",
            "frontmatter.custom.key", "frontmatter.placeholder.key").inOrder()
        assertThat(targets.joinToString()).doesNotContain("local_private_key")
        val reserved = config.copy(fields = listOf(fields.first().copy(customKey = "healthmd_injection_kind")),
            customFields = emptyMap(), placeholderFields = emptyList()).keyConflicts.single()
        assertThat(reserved.isReserved).isTrue()
        assertThat(reserved.sources).hasSize(1)
        val date = config.copy(fields = listOf(fields.first().copy(customKey = "date")),
            customFields = emptyMap(), placeholderFields = emptyList()).keyConflicts.single()
        assertThat(com.healthmd.presentation.settings.FrontmatterCustomizationTags.conflictTarget(date.sources.last()))
            .isEqualTo("frontmatter.date.key")
    }

    @Test
    fun collidingKeysFailWithoutReturningPartialNote() {
        val fields = FrontmatterConfiguration.defaultFields.map { field -> field.copy(
            isEnabled = field.originalKey in setOf("workout_count", "workout_minutes"), customKey = "same",
        ) }
        for (base in listOf(null, "", "My journal", "---\ntitle: keep\n---\nMy journal")) {
            val (result, note) = injector.inject(base, ExportFixtures.fullDay,
                DailyNoteInjectionSettings(enabled = true, createIfMissing = true),
                FormatCustomization(frontmatterConfig = FrontmatterConfiguration(fields = fields)))
            assertThat(result).isEqualTo(InjectionResult.FAILED)
            assertThat(note).isNull()
        }
    }

    @Test
    fun dateAndReservedKeyCollisionsAreRejected() {
        for (key in listOf("date", "healthmd_injection_kind", "healthmd_daily_injection_v1", "healthmd_daily_injection_v2")) {
            val fields = FrontmatterConfiguration.defaultFields.map { field -> field.copy(
                isEnabled = field.originalKey == "workout_count", customKey = key,
            ) }
            val (result, note) = injector.inject(null, ExportFixtures.fullDay,
                DailyNoteInjectionSettings(enabled = true, createIfMissing = true),
                FormatCustomization(frontmatterConfig = FrontmatterConfiguration(fields = fields)))
            assertThat(result).isEqualTo(InjectionResult.FAILED)
            assertThat(note).isNull()
        }
    }

    @Test
    fun disabledFieldWithCollidingAliasDoesNotBlockSelectedField() {
        val fields = FrontmatterConfiguration.defaultFields.map { field -> field.copy(
            isEnabled = field.originalKey == "workout_count", customKey = "same",
        ) }
        val (result, note) = injector.inject(null, ExportFixtures.fullDay,
            DailyNoteInjectionSettings(enabled = true, createIfMissing = true),
            FormatCustomization(frontmatterConfig = FrontmatterConfiguration(fields = fields, includeDate = false)))
        assertThat(result).isEqualTo(InjectionResult.CREATED)
        assertThat(note).contains("same: 1")
        assertThat(note).doesNotContain("same: 30")
    }

    @Test
    fun allMetricFieldsDisabledKeepUserPropertiesAndBodyUntouched() {
        val config = FormatCustomization(frontmatterConfig = FrontmatterConfiguration(includeDate = false,
            fields = FrontmatterConfiguration.defaultFields.map { it.copy(isEnabled = false) }))
        val existing = "---\r\nworkout_count: 9 # user property\r\n---\r\nMy journal"
        val (result, note) = injector.inject(existing, ExportFixtures.fullDay,
            DailyNoteInjectionSettings(enabled = true), config)
        assertThat(result).isEqualTo(InjectionResult.SKIPPED)
        assertThat(note).isNull()
    }

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
