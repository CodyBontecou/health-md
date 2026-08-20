package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.direct.protocol.ArtifactFormat
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportArtifactPlan
import com.healthmd.domain.exportengine.ExportArtifactPlanItem
import com.healthmd.domain.exportengine.ExportArtifactWriteMode
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.exportengine.artifactIdHex
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.repository.HealthRepository
import io.mockk.coEvery
import io.mockk.mockk
import java.io.File
import java.nio.file.Files
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Test

class DirectGeneratedFilesProducerTest {
    @Test
    fun producesDestinationIndependentFilesWithoutSafConfiguration() = runTest {
        val repository = mockk<HealthRepository>()
        val date = LocalDate.of(2026, 7, 23)
        val healthData = HealthData(date = date, activity = ActivityData(steps = 12_345))
        coEvery { repository.resolveCaptureContext(any(), any()) } returns
            AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.NIGHT_BEGINS)
        coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } returns listOf(healthData)
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
            val files = producer.produce(root, listOf(date), settings, captureContext())
            assertThat(files.map(ProducedGeneratedFile::format))
                .containsExactly(ArtifactFormat.MARKDOWN, ArtifactFormat.JSON)
            assertThat(files.all { it.file.isFile && it.file.length() > 0 }).isTrue()
            assertThat(files.all { it.relativePath.contains("2026") }).isTrue()
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun preservesExactAuthoritativePlanBytesDuringDirectStaging() = runTest {
        val bytes = "# Café 🫀\n".encodeToByteArray()
        val fixture = fixtureProducer(bytes)
        try {
            val files = fixture.producer.produce(fixture.root, listOf(fixture.date), fixture.settings, captureContext())

            assertThat(files).hasSize(1)
            assertThat(files.single().file.readBytes()).isEqualTo(bytes)
        } finally {
            fixture.root.deleteRecursively()
        }
    }

    @Test
    fun rejectsNonUtf8AuthoritativePlanBeforeDirectStaging() = runTest {
        val fixture = fixtureProducer(byteArrayOf(0xff.toByte()))
        try {
            var failure: Throwable? = null
            try {
                fixture.producer.produce(fixture.root, listOf(fixture.date), fixture.settings, captureContext())
            } catch (error: Throwable) {
                failure = error
            }
            assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
            assertThat(File(fixture.root, "generated").walkTopDown().filter(File::isFile).toList())
                .isEmpty()
        } finally {
            fixture.root.deleteRecursively()
        }
    }

    private fun captureContext() = AndroidCaptureContext(
        ZoneId.of("UTC"),
        SleepDayAttribution.NIGHT_BEGINS,
    )

    private fun fixtureProducer(bytes: ByteArray): Fixture {
        val repository = mockk<HealthRepository>()
        val date = LocalDate.of(2026, 7, 23)
        val healthData = HealthData(date = date, activity = ActivityData(steps = 12_345))
        coEvery { repository.resolveCaptureContext(any(), any()) } returns
            AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.NIGHT_BEGINS)
        coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } returns listOf(healthData)
        val relativePath = "Health/2026-07-23.md"
        val mediaType = "text/markdown; charset=utf-8"
        val item = ExportArtifactPlanItem(
            artifactId = artifactIdHex(
                requestId = "request",
                sessionId = "session",
                profile = AndroidExportProfile.android_frozen_v4,
                relativePath = relativePath,
                mediaType = mediaType,
                writeMode = ExportArtifactWriteMode.overwrite,
                contentSha256 = sha256Hex(bytes),
            ),
            relativePath = relativePath,
            mediaType = mediaType,
            writeMode = ExportArtifactWriteMode.overwrite,
            content = bytes,
        )
        val planner = LocalDailyAggregateExportPlanner { _, _ ->
            LocalDailyAggregatePlanningResult.Planned(
                mode = ExportEngineMode.rust,
                plan = ExportArtifactPlan(
                    schema = ExportArtifactPlan.SCHEMA,
                    artifactPlanVersion = ExportArtifactPlan.VERSION,
                    requestId = "request",
                    sessionId = "session",
                    profile = AndroidExportProfile.android_frozen_v4,
                    items = listOf(item),
                ),
                formats = listOf(ExportFormat.MARKDOWN),
            )
        }
        return Fixture(
            producer = DirectGeneratedFilesProducer(
                healthRepository = repository,
                markdownExporter = MarkdownExporter(),
                jsonExporter = JsonExporter(),
                csvExporter = CsvExporter(),
                obsidianBasesExporter = ObsidianBasesExporter(),
                dailyAggregatePlanner = planner,
            ),
            root = Files.createTempDirectory("direct-generated-plan-test").toFile(),
            date = date,
            settings = ExportSettings.newInstallDefaults().copy(
                exportFormat = ExportFormat.MARKDOWN,
                exportFormats = setOf(ExportFormat.MARKDOWN),
            ),
        )
    }

    private data class Fixture(
        val producer: DirectGeneratedFilesProducer,
        val root: File,
        val date: LocalDate,
        val settings: ExportSettings,
    )
}
