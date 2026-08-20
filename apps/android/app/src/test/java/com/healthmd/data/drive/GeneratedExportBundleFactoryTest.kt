package com.healthmd.data.drive

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.MarkdownMerger
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.WriteMode
import com.healthmd.export.ExportFixtures
import org.junit.Test

class GeneratedExportBundleFactoryTest {
    private val markdown = MarkdownExporter()
    private val factory = GeneratedExportBundleFactory(
        markdownExporter = markdown,
        jsonExporter = JsonExporter(),
        csvExporter = CsvExporter(),
        obsidianBasesExporter = ObsidianBasesExporter(),
    )

    @Test
    fun `overwrite bundle preserves authoritative renderer bytes and profile identity`() {
        val settings = ExportSettings(
            exportFormats = setOf(ExportFormat.MARKDOWN),
            writeMode = WriteMode.OVERWRITE,
            exportTarget = ExportTarget.GOOGLE_DRIVE,
        )

        val bundle = factory.daily(
            operationId = "operation-1",
            profileId = "profile-1",
            source = "scheduled",
            data = listOf(ExportFixtures.partialDay),
            settings = settings,
        )

        val artifact = bundle.artifacts.single()
        val expected = markdown.export(
            ExportFixtures.partialDay,
            settings.includeMetadata,
            settings.groupByCategory,
            settings.formatCustomization,
            settings.includeGranularData,
        ).encodeToByteArray()
        assertThat(bundle.profileId).isEqualTo("profile-1")
        assertThat(artifact.writeIntent).isEqualTo(GeneratedArtifactWriteIntent.OVERWRITE)
        assertThat(artifact.bytes).isEqualTo(expected)
        assertThat(generateDriveFinalBytes(artifact.writeIntent, "ignored".encodeToByteArray(), artifact.bytes))
            .isEqualTo(expected)
    }

    @Test
    fun `append and markdown update generate the same complete final bytes as existing writers`() {
        val baseline = "# Existing\n\nUser content".encodeToByteArray()
        val fragment = "# New\n\n## Activity\n\nSteps: 10".encodeToByteArray()

        assertThat(generateDriveFinalBytes(GeneratedArtifactWriteIntent.APPEND, baseline, fragment))
            .isEqualTo("# Existing\n\nUser content\n# New\n\n## Activity\n\nSteps: 10".encodeToByteArray())
        assertThat(generateDriveFinalBytes(GeneratedArtifactWriteIntent.MARKDOWN_UPDATE, baseline, fragment))
            .isEqualTo(
                MarkdownMerger().merge(baseline.decodeToString(), fragment.decodeToString()).encodeToByteArray(),
            )
    }

    @Test
    fun `daily note artifact retains preamble prefix and merges fragment exactly once`() {
        val settings = ExportSettings(
            exportFormats = emptySet(),
            dailyNoteInjection = DailyNoteInjectionSettings(
                enabled = true,
                createIfMissing = true,
                injectMarkdownSections = true,
            ),
            exportTarget = ExportTarget.GOOGLE_DRIVE,
        )

        val artifact = factory.daily(
            operationId = "operation-daily-note",
            profileId = null,
            source = "manual",
            data = listOf(ExportFixtures.partialDay),
            settings = settings,
        ).artifacts.single()

        assertThat(artifact.writeIntent).isEqualTo(GeneratedArtifactWriteIntent.DAILY_NOTE_MERGE)
        val prefix = requireNotNull(artifact.missingPrefix)
        assertThat(prefix.decodeToString()).isEqualTo("# 2026-03-15\n")
        assertThat(generateDriveFinalBytes(artifact.writeIntent, prefix, artifact.bytes))
            .isEqualTo(
                MarkdownMerger().merge(prefix.decodeToString(), artifact.bytes.decodeToString()).encodeToByteArray(),
            )
    }
}
