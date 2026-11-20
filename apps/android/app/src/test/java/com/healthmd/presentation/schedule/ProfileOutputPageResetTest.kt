package com.healthmd.presentation.schedule

import android.app.Application
import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ApplicationProvider
import com.healthmd.R
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.model.resettingExportConfiguration
import com.healthmd.presentation.common.ConfigurationProtectionUi
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.export.ExportProfileEditorDraft
import com.healthmd.presentation.theme.HealthMdTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-EXP-34: 3.5 offered Reset to Defaults for export configuration; 4.0 release builds lost it.
 * An automation's Output page must offer it behind a confirmation, save through the page's
 * autosave path, keep name/destination/subfolder, and respect configuration protection.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w400dp-h2000dp", application = Application::class)
class ProfileOutputPageResetTest {
    @get:Rule val compose = createComposeRule()
    private val context = ApplicationProvider.getApplicationContext<Context>()

    private val customized = ExportProfileEditorDraft(
        name = "Evening vault",
        target = ExportTarget.DEVICE_FOLDER,
        folderUri = "content://tree/primary%3AVault",
        folderDisplayName = "Vault",
        settings = ExportSettings(
            exportFormats = setOf(ExportFormat.JSON, ExportFormat.CSV),
            includeMetadata = false,
            filenameFormat = "{year}-{month}-{day} health",
            folderStructure = "{year}",
            folderOrganization = FolderOrganization.BY_YEAR,
            writeMode = WriteMode.APPEND,
            subfolder = "vault/health-data",
            scheduleEnabled = true,
            scheduleHour = 21,
        ),
    )

    private fun setPage(saved: () -> ExportProfileEditorDraft, onSave: (ExportProfileEditorDraft) -> Unit, protection: ConfigurationProtectionUi = ConfigurationProtectionUi()) {
        compose.setContent {
            CompositionLocalProvider(LocalConfigurationProtection provides protection) {
                HealthMdTheme {
                    ProfileOutputPage(
                        key = "profile/output",
                        stored = customized,
                        onSave = { change -> onSave(change(saved())) },
                        overlap = { emptyList() },
                        onBack = {},
                    )
                }
            }
        }
    }

    @Test
    fun confirmingResetsTheAutomationAndKeepsItsDestination() {
        var saved = customized
        setPage(saved = { saved }, onSave = { saved = it })

        compose.onNodeWithTag(AutomationOutputTags.RESET_CONFIGURATION).performScrollTo().performClick()
        compose.onNodeWithText(context.getString(R.string.output_reset_configuration_title)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.output_reset_configuration_message)).assertIsDisplayed()
        compose.onNodeWithTag(AutomationOutputTags.RESET_CONFIGURATION_CONFIRM).performClick()
        compose.mainClock.advanceTimeBy(5_000)
        compose.waitForIdle()

        assertEquals(customized.resettingExportConfiguration(), saved)
        assertEquals("Evening vault", saved.name)
        assertEquals("content://tree/primary%3AVault", saved.folderUri)
        assertEquals("vault/health-data", saved.settings.subfolder)
        assertEquals(21, saved.settings.scheduleHour)
        assertEquals(setOf(ExportFormat.MARKDOWN), saved.settings.exportFormats)
        assertEquals(ExportSettings.DEFAULT_FILENAME_FORMAT, saved.settings.filenameFormat)
        assertEquals(WriteMode.OVERWRITE, saved.settings.writeMode)
        // The page shows the reset file name instead of the old template.
        compose.onNodeWithText(ExportSettings.DEFAULT_FILENAME_FORMAT).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun cancelLeavesTheAutomationUnchanged() {
        var saves = 0
        setPage(saved = { customized }, onSave = { saves++ })

        compose.onNodeWithTag(AutomationOutputTags.RESET_CONFIGURATION).performScrollTo().performClick()
        compose.onNodeWithText(context.getString(R.string.cancel)).performClick()
        compose.mainClock.advanceTimeBy(5_000)
        compose.waitForIdle()

        assertEquals(0, saves)
        compose.onNodeWithTag(AutomationOutputTags.RESET_CONFIGURATION_CONFIRM).assertDoesNotExist()
    }

    @Test
    fun protectedSettingsBlockTheReset() {
        var saves = 0
        var blocked = 0
        setPage(
            saved = { customized },
            onSave = { saves++ },
            protection = ConfigurationProtectionUi(enabled = true, onBlockedChange = { blocked++ }),
        )

        compose.onNodeWithTag(AutomationOutputTags.RESET_CONFIGURATION).performScrollTo().performClick()
        compose.mainClock.advanceTimeBy(5_000)
        compose.waitForIdle()

        assertEquals(1, blocked)
        assertEquals(0, saves)
        compose.onNodeWithTag(AutomationOutputTags.RESET_CONFIGURATION_CONFIRM).assertDoesNotExist()
    }
}
