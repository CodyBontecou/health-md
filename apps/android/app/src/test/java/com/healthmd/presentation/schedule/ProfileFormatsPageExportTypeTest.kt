package com.healthmd.presentation.schedule

import android.app.Application
import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ApplicationProvider
import com.healthmd.R
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.presentation.export.ExportChoiceCatalog
import com.healthmd.presentation.export.ExportProfileEditorDraft
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Issue #328: after the Export now redesign no reachable control chose Raw API Snapshot, so
 * NDJSON disappeared. An automation's Formats page must keep offering every export type and
 * every raw snapshot format, and must save the choice to the profile.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w400dp-h2000dp", application = Application::class)
class ProfileFormatsPageExportTypeTest {
    @get:Rule val compose = createComposeRule()
    private val context = ApplicationProvider.getApplicationContext<Context>()

    private fun text(id: Int) = context.getString(id)

    @Test
    fun catalogRegistersEveryExportTypeAndRawFormatWithDistinctLabels() {
        assertEquals(ExportMode.entries.toList(), ExportChoiceCatalog.exportTypes)
        assertEquals(RawExportFormat.entries.toList(), ExportChoiceCatalog.rawFormats)
        val typeTitles = ExportChoiceCatalog.exportTypes.map { text(ExportChoiceCatalog.titleRes(it)) }
        val formatTitles = ExportChoiceCatalog.rawFormats.map { text(ExportChoiceCatalog.titleRes(it)) }
        assertEquals(typeTitles.size, typeTitles.toSet().size)
        assertEquals(formatTitles.size, formatTitles.toSet().size)
        assertEquals("NDJSON", text(ExportChoiceCatalog.titleRes(RawExportFormat.NDJSON)))
        ExportChoiceCatalog.exportTypes.forEach { assertTrue(text(ExportChoiceCatalog.descriptionRes(it)).isNotBlank()) }
        ExportChoiceCatalog.rawFormats.forEach { assertTrue(text(ExportChoiceCatalog.descriptionRes(it)).isNotBlank()) }
    }

    @Test
    fun compatibilityAutomationCanSwitchToRawNdjsonSnapshot() {
        var saved = ExportProfileEditorDraft(
            name = "Default",
            target = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
            settings = ExportSettings(exportMode = ExportMode.COMPATIBILITY),
        )
        val stored = saved.settings.copy(
            rawSnapshot = saved.settings.rawSnapshot.copy(format = RawExportFormat.JSON),
        )
        compose.setContent {
            HealthMdTheme {
                ProfileFormatsPage(
                    key = "profile/formats",
                    stored = stored,
                    onSave = { change -> saved = change(saved) },
                    onBack = {},
                    sleepDayAttribution = SleepDayAttribution.NIGHT_BEGINS,
                    onSleepDayAttributionChanged = {},
                )
            }
        }

        // Every export type is offered on a compatibility automation.
        ExportChoiceCatalog.exportTypes.forEach {
            compose.onNodeWithText(text(ExportChoiceCatalog.titleRes(it))).assertIsDisplayed()
        }

        compose.onNode(hasText(text(R.string.export_type_raw_snapshot)) and hasClickAction()).performClick()
        compose.waitForIdle()

        // Every raw format is offered once Raw API Snapshot is chosen.
        ExportChoiceCatalog.rawFormats.forEach {
            compose.onNode(hasText(text(ExportChoiceCatalog.titleRes(it)), substring = false) and hasClickAction())
                .performScrollTo()
                .assertIsDisplayed()
        }
        compose.onNode(hasText(text(R.string.raw_snapshot_format_ndjson), substring = false) and hasClickAction())
            .performClick()

        compose.mainClock.advanceTimeBy(5_000)
        compose.waitForIdle()

        assertEquals(ExportMode.RAW_SNAPSHOT, saved.settings.exportMode)
        assertEquals(RawExportFormat.NDJSON, saved.settings.rawSnapshot.format)
    }
}
