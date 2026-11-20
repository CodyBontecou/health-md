package com.healthmd.presentation.export

import android.app.Application
import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.export.components.ExportProgressDialog
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.rawexport.ExportMode
import java.time.LocalDate
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Android ledger A-EXP-12: 3.5 offered "Open with" Files or Obsidian after a device-folder
 * export when Obsidian was installed; the 4.0 Export now result and the successful run's done
 * moment must keep offering the folder in Files and, when installed, in Obsidian.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w400dp-h2000dp", application = Application::class)
class ExportResultOpenInObsidianTest {
    @get:Rule val compose = createComposeRule()
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val folder = "content://com.android.externalstorage.documents/tree/primary%3AVault"
    private val partial = ExportResult(successCount = 5, totalCount = 7, artifactCount = 5)

    @Test
    fun obsidianIsOfferedOnlyForWrittenDeviceFolderRunsWhenInstalled() {
        assertThat(ExportNowFlow.opensResultInObsidian(partial, folder, obsidianInstalled = true)).isTrue()
        assertThat(ExportNowFlow.opensResultInObsidian(partial, folder, obsidianInstalled = false)).isFalse()
        assertThat(ExportNowFlow.opensResultInObsidian(partial, null, obsidianInstalled = true)).isFalse()
        assertThat(
            ExportNowFlow.opensResultInObsidian(partial.copy(artifactCount = 0), folder, obsidianInstalled = true),
        ).isFalse()
        ExportTarget.entries.filter { it != ExportTarget.DEVICE_FOLDER }.forEach { target ->
            assertThat(
                ExportNowFlow.opensResultInObsidian(partial.copy(target = target), folder, obsidianInstalled = true),
            ).isFalse()
        }
        // Show in Files is unchanged: it never depends on Obsidian.
        assertThat(ExportNowFlow.opensResultFolder(partial, folder)).isTrue()
        assertThat(ExportNowFlow.opensResultFolder(partial.copy(artifactCount = 0), folder)).isFalse()
    }

    @Test
    fun resultPageShowsOpenInObsidianBesideShowInFilesAndInvokesIt() {
        var obsidianOpens = 0
        var filesOpens = 0
        setResult(onShowInFiles = { filesOpens++ }, onOpenInObsidian = { obsidianOpens++ })

        compose.onNodeWithTag("export.result.showInFiles").assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.export_result_open_in_obsidian)).assertIsDisplayed()
        compose.onNodeWithTag("export.result.openInObsidian").performClick()

        assertThat(obsidianOpens).isEqualTo(1)
        assertThat(filesOpens).isEqualTo(0)
    }

    @Test
    fun resultPageHidesOpenInObsidianWithoutObsidian() {
        setResult(onShowInFiles = {}, onOpenInObsidian = null)

        compose.onNodeWithTag("export.result.showInFiles").assertIsDisplayed()
        compose.onNodeWithTag("export.result.openInObsidian").assertDoesNotExist()
    }

    @Test
    fun doneMomentOffersFilesAndObsidianBesideItsOwnActions() {
        var filesOpens = 0
        var obsidianOpens = 0
        var archiveOpens = 0
        setDone(onShowInFiles = { filesOpens++ }, onOpenInObsidian = { obsidianOpens++ }, onSeeInArchive = { archiveOpens++ })

        compose.onNodeWithText(context.getString(R.string.moment_see_in_archive)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.export_result_show_in_files)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.export_result_open_in_obsidian)).assertIsDisplayed()
        compose.onNodeWithTag("export.done.showInFiles").performClick()
        compose.onNodeWithTag("export.done.openInObsidian").performClick()

        assertThat(filesOpens).isEqualTo(1)
        assertThat(obsidianOpens).isEqualTo(1)
        assertThat(archiveOpens).isEqualTo(0)
    }

    @Test
    fun doneMomentHidesObsidianWithoutObsidian() {
        setDone(onShowInFiles = {}, onOpenInObsidian = null, onSeeInArchive = {})
        compose.onNodeWithTag("export.done.showInFiles").assertIsDisplayed()
        compose.onNodeWithTag("export.done.openInObsidian").assertDoesNotExist()
    }

    @Test
    fun doneMomentWithoutFolderActionsKeepsOnlyItsOwnActions() {
        setDone(onShowInFiles = null, onOpenInObsidian = null, onSeeInArchive = {})
        compose.onNodeWithText(context.getString(R.string.moment_see_in_archive)).assertIsDisplayed()
        compose.onNodeWithTag("export.done.showInFiles").assertDoesNotExist()
        compose.onNodeWithTag("export.done.openInObsidian").assertDoesNotExist()
    }

    @Test
    fun aFullSuccessToADeviceFolderOpensTheFolderWhileItsMomentIsUp() {
        val success = ExportResult(successCount = 7, totalCount = 7, artifactCount = 7)
        assertThat(ExportNowFlow.showsResultSheet(success)).isFalse()
        assertThat(ExportNowFlow.opensResultFolder(success, folder)).isTrue()
        assertThat(ExportNowFlow.opensResultInObsidian(success, folder, obsidianInstalled = true)).isTrue()
        assertThat(ExportNowFlow.opensResultInObsidian(success, folder, obsidianInstalled = false)).isFalse()
        assertThat(
            ExportNowFlow.opensResultFolder(success.copy(target = ExportTarget.API_ENDPOINT), folder),
        ).isFalse()
    }

    private fun setDone(
        onShowInFiles: (() -> Unit)?,
        onOpenInObsidian: (() -> Unit)?,
        onSeeInArchive: (() -> Unit)?,
    ) {
        compose.setContent {
            HealthMdTheme {
                ExportProgressDialog(
                    current = 7,
                    total = 7,
                    currentDate = null,
                    rangeStart = LocalDate.of(2026, 11, 1),
                    rangeEnd = LocalDate.of(2026, 11, 7),
                    exportMode = ExportMode.COMPATIBILITY,
                    onCancel = {},
                    isDone = true,
                    onSeeInArchive = onSeeInArchive,
                    onClose = {},
                    doneSubtitle = "Nov 1 – 7 · 7 files",
                    onShowInFiles = onShowInFiles,
                    onOpenInObsidian = onOpenInObsidian,
                )
            }
        }
    }

    private fun setResult(onShowInFiles: (() -> Unit)?, onOpenInObsidian: (() -> Unit)?) {
        compose.setContent {
            HealthMdTheme {
                ExportResultContent(
                    result = partial,
                    rangeStart = LocalDate.of(2026, 11, 1),
                    rangeEnd = LocalDate.of(2026, 11, 7),
                    profileName = null,
                    onRetry = { _, _ -> },
                    onShowInFiles = onShowInFiles,
                    onDone = {},
                    onOpenInObsidian = onOpenInObsidian,
                )
            }
        }
    }
}
