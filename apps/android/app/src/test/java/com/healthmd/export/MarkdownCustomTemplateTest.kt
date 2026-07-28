package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.MarkdownTemplateConfig
import com.healthmd.domain.model.MarkdownTemplateStyle
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.LocalDate

class MarkdownCustomTemplateTest {
    private val exporter = MarkdownExporter()

    @Test
    fun settingsRepository_persistsCustomTemplateConfig() = runTest {
        val repository = FakeSettingsRepository()
        val customization = FormatCustomization(
            markdownTemplate = MarkdownTemplateConfig(
                style = MarkdownTemplateStyle.CUSTOM,
                customTemplate = "# Custom {{date}}\n{{metrics}}",
            ),
        )

        repository.updateExportSettings(
            repository.getExportSettings().copy(formatCustomization = customization),
        )

        val stored = repository.getExportSettings().formatCustomization.markdownTemplate
        assertThat(stored.style).isEqualTo(MarkdownTemplateStyle.CUSTOM)
        assertThat(stored.customTemplate).isEqualTo("# Custom {{date}}\n{{metrics}}")
    }

    @Test
    fun customTemplate_rendersPlaceholdersAndConditionalBlocks() {
        val customization = FormatCustomization(
            markdownTemplate = MarkdownTemplateConfig(
                style = MarkdownTemplateStyle.CUSTOM,
                customTemplate = """
                    # Daily {{date}}
                    {{#activity}}
                    Activity:
                    {{activity_metrics}}
                    {{/activity}}
                    {{#sleep}}Sleep should disappear{{/sleep}}
                """.trimIndent(),
            ),
        )
        val data = HealthData(
            date = LocalDate.of(2026, 3, 15),
            activity = ActivityData(steps = 8500),
        )

        val output = exporter.export(data, customization = customization)

        assertThat(output).contains("# Daily 2026-03-15")
        assertThat(output).contains("**Steps:** 8,500")
        assertThat(output).doesNotContain("Sleep should disappear")
    }
}
