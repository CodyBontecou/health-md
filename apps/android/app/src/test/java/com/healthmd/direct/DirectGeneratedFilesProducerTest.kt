package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.direct.protocol.ArtifactFormat
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.HealthRepository
import io.mockk.coEvery
import io.mockk.mockk
import java.nio.file.Files
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class DirectGeneratedFilesProducerTest {
    @Test
    fun producesDestinationIndependentFilesWithoutSafConfiguration() = runTest {
        val repository = mockk<HealthRepository>()
        val date = LocalDate.of(2026, 7, 23)
        val healthData = HealthData(date = date, activity = ActivityData(steps = 12_345))
        coEvery { repository.fetchHealthDataRange(any(), any(), any()) } returns listOf(healthData)
        coEvery { repository.fetchHealthData(date) } returns healthData
        val producer = DirectGeneratedFilesProducer(
            healthRepository = repository,
            markdownExporter = MarkdownExporter(),
            jsonExporter = JsonExporter(),
            csvExporter = CsvExporter(),
            obsidianBasesExporter = ObsidianBasesExporter(),
        )
        val settings = ExportSettings.newInstallDefaults().copy(
            exportFormat = ExportFormat.MARKDOWN,
            exportFormats = setOf(ExportFormat.MARKDOWN, ExportFormat.JSON),
        )
        val root = Files.createTempDirectory("direct-generated-test").toFile()
        try {
            val files = producer.produce(root, listOf(date), settings)
            assertThat(files.map(ProducedGeneratedFile::format))
                .containsExactly(ArtifactFormat.MARKDOWN, ArtifactFormat.JSON)
            assertThat(files.all { it.file.isFile && it.file.length() > 0 }).isTrue()
            assertThat(files.all { it.relativePath.contains("2026") }).isTrue()
        } finally {
            root.deleteRecursively()
        }
    }
}
