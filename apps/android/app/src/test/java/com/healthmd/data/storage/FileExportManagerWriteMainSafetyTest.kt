package com.healthmd.data.storage

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.util.Collections
import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Play ANR (issue #441, version code 41): the main thread blocked in the SAF binder call that
 * opens the destination stream, `FileExportManager.writeContent` <- `writeFile` <-
 * `writeFileAtRelativePath` <- `ExportRepositoryImpl.exportLegacy` (the daily-note side-effect
 * write), with the export launched from `viewModelScope`.
 *
 * Unlike [ExportRepositoryMainSafetyTest], this drives the real [FileExportManager] over a fake
 * SAF [ContentResolver], so the asserted thread is the one that actually opens each output
 * stream, the exact frame in the trace.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class FileExportManagerWriteMainSafetyTest {

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
    fun legacyDailyNoteWriteOpensItsSafStreamOffTheCallingThread() = runBlocking {
        val saf = FakeSaf()
        val repository = repository(FileExportManager(saf.context))
        val settings = ExportSettings(
            exportFormat = ExportFormat.MARKDOWN,
            exportFormats = setOf(ExportFormat.MARKDOWN),
            writeMode = WriteMode.OVERWRITE,
            dailyNoteInjection = DailyNoteInjectionSettings(enabled = true, folderPath = "Daily/2026"),
        )

        val success = withContext(callerDispatcher) { repository.exportHealthData(day, settings) }

        assertThat(success).isTrue()
        assertThat(callerThread[0]).isNotNull()
        // The aggregate note and the daily note were both written through writeContent.
        assertThat(saf.created).contains("2026-03-15.md")
        assertThat(saf.writes.map { it.first }).hasSize(2)
        assertThat(saf.writes.map { it.second }).doesNotContain(callerThread[0])
        assertThat(saf.created).containsAtLeast("Daily", "2026").inOrder()
    }

    /** A SAF tree with no existing children: every folder and file is created, then written. */
    private class FakeSaf {
        val created: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val writes: MutableList<Pair<Uri, Thread>> = Collections.synchronizedList(mutableListOf())
        private val resolver = mockk<ContentResolver>()
        val context = mockk<Context>().also { every { it.contentResolver } returns resolver }

        init {
            every { resolver.query(any(), any(), any<String>(), any(), any<String>()) } returns null
            every { resolver.call(any<String>(), METHOD_CREATE_DOCUMENT, any(), any()) } answers {
                val parent = (arg<Bundle>(3)).getParcelable<Uri>(EXTRA_URI)!!
                val name = arg<Bundle>(3).getString(DocumentsContract.Document.COLUMN_DISPLAY_NAME)!!
                created += name
                val parentId = DocumentsContract.getDocumentId(parent)
                val child = DocumentsContract.buildDocumentUriUsingTree(TREE_URI, "$parentId/$name")
                Bundle().apply { putParcelable(EXTRA_URI, child) }
            }
            every { resolver.openOutputStream(any<Uri>(), "wt") } answers {
                writes += firstArg<Uri>() to Thread.currentThread()
                ByteArrayOutputStream()
            }
        }
    }

    private fun repository(manager: FileExportManager): ExportRepositoryImpl {
        val settingsRepository = mockk<SettingsRepository>()
        coEvery { settingsRepository.getExportFolderUri() } returns TREE_URI.toString()
        return ExportRepositoryImpl(
            fileExportManager = manager,
            markdownExporter = MarkdownExporter(),
            jsonExporter = JsonExporter(),
            csvExporter = CsvExporter(),
            obsidianBasesExporter = ObsidianBasesExporter(),
            settingsRepository = settingsRepository,
            dailyAggregatePlanner = LocalDailyAggregateExportPlanner { _, _ -> LocalDailyAggregatePlanningResult.Legacy },
        )
    }

    private val day = HealthData(date = LocalDate.of(2026, 3, 15), activity = ActivityData(steps = 1234))

    private companion object {
        // Hidden DocumentsContract constants that DocumentsContract.createDocument sends.
        const val METHOD_CREATE_DOCUMENT = "android:createDocument"
        const val EXTRA_URI = "uri"
        val TREE_URI: Uri = DocumentsContract.buildTreeDocumentUri(
            "com.android.externalstorage.documents",
            "primary:Vault",
        )
    }
}
