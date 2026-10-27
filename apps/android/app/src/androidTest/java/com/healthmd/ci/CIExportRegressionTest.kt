package com.healthmd.ci

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.R
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.data.history.ExportHistoryDatabase
import com.healthmd.data.history.ExportHistoryRepositoryImpl
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.data.storage.ExportRepositoryImpl
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.review.ReviewPromptResult
import com.healthmd.domain.review.ReviewPrompter
import com.healthmd.presentation.export.ExportScreen
import com.healthmd.presentation.export.ExportViewModel
import com.healthmd.presentation.theme.HealthMdTheme
import java.io.File
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Single native journey: SDK fixture -> real screen/view model -> SAF file -> durable settings. */
@RunWith(AndroidJUnit4::class)
class CIExportRegressionTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun productionExportWritesSdkValuesAndSettingsSurviveReopen() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        check(context.packageName.endsWith(".e2e")) { "CI must use the isolated .e2e application" }
        val date = LocalDate.now()
        val rootId = "ci-${UUID.randomUUID()}"
        val provider = context.packageManager.getProviderInfo(
            ComponentName(context.packageName, "com.healthmd.ci.CIExportDocumentsProvider"), 0,
        )
        val tree = DocumentsContract.buildTreeDocumentUri(provider.authority, rootId)
        val storeFile = File(context.cacheDir, "$rootId.preferences_pb")
        val storeJob = SupervisorJob()
        val dataStore = PreferenceDataStoreFactory.create(
            scope = CoroutineScope(storeJob + Dispatchers.IO), produceFile = { storeFile },
        )
        val settings = SettingsRepositoryImpl(dataStore, context)
        val history = Room.inMemoryDatabaseBuilder(context, ExportHistoryDatabase::class.java).build()
        val models = ViewModelStore()
        var reopenedJob: kotlinx.coroutines.Job? = null
        try {
            val selection = MetricSelectionState(setOf("steps"))
            runBlocking {
                settings.updateExportSettings(ExportSettings(
                    dataTypes = DataTypeSelection().deselectAll().copy(activity = true),
                    metricSelection = selection, subfolder = "",
                ))
                settings.saveExportFolderUri(tree.toString())
                settings.setPurchased(true)
                settings.setSelectedHealthProviderId("health_connect")
            }
            val files = FileExportManager(context)
            val health = HealthRepositoryImpl(
                HealthProviderRegistry(HealthConnectDataProvider(HealthConnectManager(context, ciHealthConnectClient()))),
                settings,
            )
            val exports = ExportRepositoryImpl(files, MarkdownExporter(), JsonExporter(), CsvExporter(), ObsidianBasesExporter(), settings)
            lateinit var model: ExportViewModel
            compose.runOnUiThread {
                model = ExportViewModel(health, exports, settings, ExportProfileRepository(dataStore, context),
                    object : EntitlementRepository {
                        override val isUnlocked = MutableStateFlow(true)
                        override fun refresh() = Unit
                        override fun debugSetUnlocked(unlocked: Boolean) = Unit
                        override fun debugReset() = Unit
                    }, DistributionPolicy.play(),
                    object : ReviewPrompter {
                        override val isAvailable = false
                        override suspend fun prompt(activity: Activity) = ReviewPromptResult.Unavailable
                    }, ExportHistoryRepositoryImpl(history.exportHistoryDao()), files)
                models.put("ci-export", model)
                model.setDateRange(date, date)
            }
            compose.setContent { HealthMdTheme { ExportScreen(viewModel = model) } }
            compose.waitUntil(10_000) {
                model.uiState.value.hasPermissions && model.uiState.value.folderName != null && model.uiState.value.isPurchased
            }
            compose.onNodeWithText(context.getString(R.string.export_button))
                .assertIsDisplayed().assertIsEnabled().performClick()
            compose.waitUntil(10_000) { model.uiState.value.lastResult != null }
            val result = requireNotNull(model.uiState.value.lastResult)
            assertEquals(1, result.successCount)
            assertFalse(result.wasCancelled)
            assertTrue(result.failedDateDetails.isEmpty())

            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId)
            val exportedId = context.contentResolver.query(children,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null)!!.use { cursor ->
                var id: String? = null
                while (cursor.moveToNext()) if (cursor.getString(1) == "$date.md") id = cursor.getString(0)
                requireNotNull(id) { "Production exporter must write the expected daily file" }
            }
            val fileUri = DocumentsContract.buildDocumentUriUsingTree(tree, exportedId)
            val content = context.contentResolver.openInputStream(fileUri)!!.bufferedReader().use { it.readText() }
            assertTrue(content.contains("steps: 1234"))
            assertFalse(content.contains("CIHealthConnectClient"))

            runBlocking { settings.setPreventAccidentalChanges(true) }
            compose.runOnUiThread { models.clear() }
            runBlocking { storeJob.cancelAndJoin() }
            val reopenScope = SupervisorJob().also { reopenedJob = it }
            val reopened = SettingsRepositoryImpl(PreferenceDataStoreFactory.create(
                scope = CoroutineScope(reopenScope + Dispatchers.IO), produceFile = { storeFile },
            ), context)
            runBlocking {
                assertEquals(selection, reopened.getExportSettings().metricSelection)
                assertEquals(tree.toString(), reopened.getExportFolderUri())
                assertTrue(reopened.preventAccidentalChanges.first())
            }
        } finally {
            compose.runOnUiThread { models.clear() }
            runBlocking { storeJob.cancelAndJoin(); reopenedJob?.cancelAndJoin() }
            history.close()
            storeFile.delete()
            DocumentsContract.deleteDocument(context.contentResolver, DocumentsContract.buildDocumentUriUsingTree(tree, rootId))
        }
    }
}
