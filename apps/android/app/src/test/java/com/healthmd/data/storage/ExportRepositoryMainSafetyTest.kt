package com.healthmd.data.storage

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.data.storage.FileExportManager.Companion.writeUtf8
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.spyk
import io.mockk.verify
import java.io.OutputStream
import com.healthmd.export.ExportFixtures
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Test

/**
 * Manual exports are launched from `viewModelScope` (the main thread). Play vitals showed SAF
 * lookups/writes and JSON encoding running there (ANRs and main-thread OOMs). The repository
 * must move that work off its caller's thread by itself.
 */
class ExportRepositoryMainSafetyTest {

    private val callerThread = arrayOfNulls<Thread>(1)
    private val callerExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "fake-main").also { callerThread[0] = it }
    }
    private val callerDispatcher = callerExecutor.asCoroutineDispatcher()

    @After
    fun tearDown() {
        callerDispatcher.close()
    }

    @Test
    fun legacyExportWritesAndRendersOffTheCallingThread() = runBlocking {
        val writeThreads = mutableListOf<Thread>()
        val manager = mockk<FileExportManager>(relaxed = true)
        every { manager.writeStreamedFile(any(), any(), any(), any(), any(), any()) } answers {
            writeThreads += Thread.currentThread()
            true
        }
        every { manager.writeFile(any(), any(), any(), any(), any(), any()) } answers {
            writeThreads += Thread.currentThread()
            true
        }
        val repository = repository(manager)

        val success = withContext(callerDispatcher) {
            repository.exportHealthData(day, settings(ExportFormat.JSON, ExportFormat.MARKDOWN))
        }

        assertThat(success).isTrue()
        assertThat(writeThreads).hasSize(2)
        assertThat(callerThread[0]).isNotNull()
        assertThat(writeThreads).doesNotContain(callerThread[0])
    }

    /**
     * Play vitals #421: `JsonExporter.render` grew one pretty-printed String for a whole granular
     * day (`JsonToStringWriter.ensureTotalCapacity` -> OutOfMemoryError) when the folder export
     * called `export(...)` from `contentForFormat`. The folder JSON must reach the destination
     * only through the streamed writer, never as one String, with the historical bytes.
     */
    @Test
    fun legacyFolderJsonIsStreamedInsteadOfRenderedAsOneString() = runBlocking {
        val manager = mockk<FileExportManager>(relaxed = true)
        val body = slot<(OutputStream) -> Unit>()
        every { manager.writeStreamedFile(any(), any(), any(), any(), any(), capture(body)) } returns true
        val jsonExporter = spyk(JsonExporter())
        val repository = repository(manager, jsonExporter = jsonExporter)
        val granular = settings(ExportFormat.JSON).copy(includeGranularData = true)
        val data = ExportFixtures.fullDayGranular

        val success = withContext(callerDispatcher) { repository.exportHealthData(data, granular) }

        assertThat(success).isTrue()
        verify(exactly = 0) { jsonExporter.export(any(), any(), any(), any(), any()) }
        verify(exactly = 0) { manager.writeFile(any(), any(), any(), any(), any(), any()) }
        val streamed = ByteArrayOutputStream().also { body.captured(it) }.toByteArray()
        val historical = JsonExporter().export(
            data = data,
            customization = granular.formatCustomization,
            includeGranularData = true,
            detail = granular.exportDetailSelection(),
        )
        assertThat(streamed).isEqualTo(historical.toByteArray(Charsets.UTF_8))
    }

    @Test
    fun previewReadsDestinationOffTheCallingThread() = runBlocking {
        val readThreads = mutableListOf<Thread>()
        val manager = mockk<FileExportManager>(relaxed = true)
        every { manager.readFileAtRelativePath(any(), any()) } answers {
            readThreads += Thread.currentThread()
            null
        }
        val repository = repository(manager)

        withContext(callerDispatcher) {
            repository.previewHealthData(day, settings(ExportFormat.MARKDOWN).copy(writeMode = WriteMode.UPDATE))
        }

        assertThat(readThreads).isNotEmpty()
        assertThat(callerThread[0]).isNotNull()
        assertThat(readThreads).doesNotContain(callerThread[0])
    }

    @Test
    fun ordinaryRenderingFailureFailsTheDayInsteadOfEscapingToTheCaller() = runBlocking {
        val manager = mockk<FileExportManager>(relaxed = true)
        val markdown = mockk<MarkdownExporter>()
        every { markdown.export(any(), any(), any(), any(), any(), any()) } throws IllegalStateException("render failed")
        val repository = repository(manager, markdownExporter = markdown)

        val success = withContext(callerDispatcher) {
            repository.exportHealthData(day, settings(ExportFormat.MARKDOWN))
        }

        assertThat(success).isFalse()
    }

    @Test
    fun chunkedUtf8WriterIsByteIdenticalToWholeStringEncoding() {
        val pair = "🏃"
        val samples = listOf(
            "",
            "plain ascii",
            // Surrogate pairs and lone surrogates straddling every early chunk boundary.
            "a".repeat(16 * 1024 - 1) + pair + "b".repeat(16 * 1024) + "\uD83C" + "c" + "\uDC00",
            "x".repeat(16 * 1024 - 1) + "\uD83C",
            (pair + "é日").repeat(40_000),
        )
        for (text in samples) {
            val streamed = ByteArrayOutputStream().also { it.writeUtf8(text) }.toByteArray()
            assertThat(streamed).isEqualTo(text.toByteArray(Charsets.UTF_8))
        }
    }

    private fun repository(
        manager: FileExportManager,
        markdownExporter: MarkdownExporter = MarkdownExporter(),
        jsonExporter: JsonExporter = JsonExporter(),
    ): ExportRepositoryImpl {
        val settingsRepository = mockk<SettingsRepository>()
        coEvery { settingsRepository.getExportFolderUri() } returns folderUri
        return ExportRepositoryImpl(
            fileExportManager = manager,
            markdownExporter = markdownExporter,
            jsonExporter = jsonExporter,
            csvExporter = CsvExporter(),
            obsidianBasesExporter = ObsidianBasesExporter(),
            settingsRepository = settingsRepository,
            dailyAggregatePlanner = LocalDailyAggregateExportPlanner { _, _ -> LocalDailyAggregatePlanningResult.Legacy },
        )
    }

    private fun settings(vararg formats: ExportFormat) = ExportSettings(
        exportFormat = formats.first(),
        exportFormats = formats.toSet(),
        writeMode = WriteMode.OVERWRITE,
    )

    private val day = HealthData(date = LocalDate.of(2026, 3, 15), activity = ActivityData(steps = 1234))
    private val folderUri = "content://exports"
}
