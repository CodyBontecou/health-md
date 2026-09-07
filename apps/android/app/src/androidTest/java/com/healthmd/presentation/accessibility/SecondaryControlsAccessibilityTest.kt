package com.healthmd.presentation.accessibility

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.common.ConfigurationProtectionTestTags
import com.healthmd.presentation.common.ConfigurationProtectionUi
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.export.DateRangeOption
import com.healthmd.presentation.export.DateRangeSelectionSection
import com.healthmd.presentation.export.ExportDateControlTags
import com.healthmd.presentation.schedule.ScheduleHistoryHeading
import com.healthmd.presentation.schedule.ScheduleHistoryTags
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistDarkColors
import com.healthmd.presentation.theme.GeistLightColors
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.Spacing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/** Real stateless controls only: no ViewModels, repositories, calendar windows, or device settings. */
@RunWith(Parameterized::class)
class SecondaryControlsAccessibilityTest(display: AccessibilityDisplayCase) : AccessibilityTestHarness(display) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun displays() = accessibilityDisplays()
    }

    private val presets = listOf(
        DateRangeOption.Today to R.string.date_option_today,
        DateRangeOption.Yesterday to R.string.date_option_yesterday,
        DateRangeOption.AllTime to R.string.date_option_all_time,
        DateRangeOption.Custom to R.string.date_option_custom,
    )

    @Test
    fun datePresetsKeepFullLabelsExclusiveSelectionAndCallbackIdentity() {
        val selected = mutableStateOf(DateRangeOption.Today)
        val calls = mutableListOf<DateRangeOption>()
        setContent {
            ScrollFixture {
                DateRangeSelectionSection(
                    selectedOption = selected.value,
                    startDate = LocalDate.of(2024, 9, 30),
                    endDate = LocalDate.of(2025, 12, 31),
                    onOptionSelected = { calls += it; selected.value = it },
                    onStartDateClick = { error("A preset must not open the start picker") },
                    onEndDateClick = { error("A preset must not open the end picker") },
                )
            }
        }

        assertPresetStates(DateRangeOption.Today)
        presets.forEachIndexed { index, (option, _) ->
            // Includes tapping the already-selected Today preset; every tap still calls once.
            compose.onNodeWithTag(ExportDateControlTags.preset(option)).performScrollTo()
                .assertFullyVisible().assertMinimumTouchTarget().performTouchInput {
                    click(Offset(width * 0.1f, height * 0.5f))
                }
            compose.runOnIdle {
                assertEquals(option, selected.value)
                assertEquals(presets.take(index + 1).map { it.first }, calls)
            }
            assertPresetStates(option)
            val start = compose.onNodeWithTag(ExportDateControlTags.START_DATE)
            val end = compose.onNodeWithTag(ExportDateControlTags.END_DATE)
            if (option == DateRangeOption.Custom) {
                start.assertExists()
                end.assertExists()
            } else {
                start.assertDoesNotExist()
                end.assertDoesNotExist()
            }
        }
        compose.onNodeWithText(text(R.string.section_date_range)).performScrollTo().assertFullyVisible()
        settleAndCapture("secondary-dates")
    }

    @Test
    fun customDatesGiveLabelsAndValuesFullWidthAndOneWholeRowAction() {
        val start = mutableStateOf(LocalDate.of(2024, 9, 30))
        val end = mutableStateOf(LocalDate.of(2025, 12, 31))
        val calls = mutableListOf<String>()
        setContent {
            ScrollFixture {
                DateRangeSelectionSection(
                    selectedOption = DateRangeOption.Custom,
                    startDate = start.value,
                    endDate = end.value,
                    onOptionSelected = { error("A date row must not invoke a preset callback") },
                    onStartDateClick = { calls += "start"; start.value = LocalDate.of(2024, 10, 1) },
                    onEndDateClick = { calls += "end"; end.value = LocalDate.of(2026, 1, 1) },
                )
            }
        }

        assertDateRow(ExportDateControlTags.START_DATE, R.string.date_start_label, start.value)
        capture("secondary-custom-start")
        assertDateRow(ExportDateControlTags.END_DATE, R.string.date_end_label, end.value)
        capture("secondary-custom-end")
        // Both the label and the displayed value activate their single containing button.
        actualText(ExportDateControlTags.START_DATE, text(R.string.date_start_label))
            .performScrollTo().assertFullyVisible().performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(listOf("start"), calls)
            assertEquals(LocalDate.of(2024, 10, 1), start.value)
            assertEquals(LocalDate.of(2025, 12, 31), end.value)
        }
        assertDateRow(ExportDateControlTags.START_DATE, R.string.date_start_label, start.value)
        actualText(ExportDateControlTags.END_DATE, text(R.string.date_end_label))
            .performScrollTo().assertFullyVisible().performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(listOf("start", "end"), calls)
            assertEquals(LocalDate.of(2026, 1, 1), end.value)
        }
        assertDateRow(ExportDateControlTags.END_DATE, R.string.date_end_label, end.value)
        actualText(ExportDateControlTags.START_DATE, compactDate(start.value))
            .performScrollTo().assertFullyVisible().performTouchInput { click() }
        actualText(ExportDateControlTags.END_DATE, compactDate(end.value))
            .performScrollTo().assertFullyVisible().performTouchInput { click() }
        compose.runOnIdle { assertEquals(listOf("start", "end", "start", "end"), calls) }
    }

    @Test
    fun historyHeadingSeparatesTheReadableTitleAndLabeledClearButton() {
        var requests = 0
        setContent {
            ScrollFixture {
                ScheduleHistoryHeading(onRequestClearHistory = { requests++ })
            }
        }
        compose.onNodeWithTag(ScheduleHistoryTags.HEADING).performScrollTo().assertFullyVisible()
        val title = compose.onNodeWithTag(ScheduleHistoryTags.TITLE, useUnmergedTree = true)
        val clear = compose.onNodeWithTag(ScheduleHistoryTags.CLEAR)
        val clearText = actualText(ScheduleHistoryTags.CLEAR, text(R.string.action_clear_history))
        title.assertTextEquals(text(R.string.section_export_history))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        clear.assertHasClickAction().assertMinimumTouchTarget().assertFullyVisible()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assertTextEquals(text(R.string.action_clear_history))
        compose.onAllNodes(hasClickAction()).assertCountEquals(1)
        assertTextFits(title, GeistType.heading16.fontSize)
        assertTextFits(clearText, GeistType.heading14.fontSize)
        assertReadableSecondary(title)
        assertReadableSecondary(clearText)

        val titleBounds = title.getUnclippedBoundsInRoot()
        val clearBounds = clear.getUnclippedBoundsInRoot()
        if (GeistAdaptiveLayout.stackDetailedControls(display.width - 32f, display.fontScale)) {
            assertTrue("Clear is below, not beside, the full-width title",
                clearBounds.top - titleBounds.bottom >= Spacing.xs - 1.dp)
            assertEquals(titleBounds.left, clearBounds.left)
            assertEquals(titleBounds.right, clearBounds.right)
        } else {
            assertTrue("Title and action have a gap in either layout direction",
                maxOf(titleBounds.left, clearBounds.left) - minOf(titleBounds.right, clearBounds.right) >= Spacing.md - 1.dp)
        }
        capture("secondary-history")
        clear.performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
        compose.runOnIdle { assertEquals(1, requests) }
    }

    @Test
    fun protectedHistoryClearBlocksPointersAndUnlockedClearOnlyRequestsConfirmation() {
        val locked = mutableStateOf(false)
        val confirmationRequested = mutableStateOf(false)
        val history = mutableStateOf(listOf("synthetic-history-entry"))
        val originalHistory = history.value
        val calls = mutableListOf<String>()
        setContent {
            ScrollFixture {
                CompositionLocalProvider(
                    LocalConfigurationProtection provides ConfigurationProtectionUi(locked.value, { calls += "blocked" }),
                ) {
                    val protection = LocalConfigurationProtection.current
                    // The same screen-owned attempt path, with synthetic confirmation state only.
                    val attemptConfigurationChange: (() -> Unit) -> Unit = { action ->
                        if (protection.enabled) protection.onBlockedChange() else action()
                    }
                    ScheduleHistoryHeading(onRequestClearHistory = {
                        attemptConfigurationChange {
                            calls += "request-confirmation"
                            confirmationRequested.value = true
                        }
                    })
                }
            }
        }
        compose.onNodeWithTag(ScheduleHistoryTags.HEADING).performScrollTo().assertFullyVisible()
        val clear = compose.onNodeWithTag(ScheduleHistoryTags.CLEAR)
        clear.assertFullyVisible().assertMinimumTouchTarget().performTouchInput { click() }
        val childBounds = clear.fetchSemanticsNode().boundsInRoot
        compose.runOnIdle {
            assertEquals(listOf("request-confirmation"), calls)
            assertTrue(confirmationRequested.value)
            assertSame("The heading cannot delete history directly", originalHistory, history.value)
            confirmationRequested.value = false
            locked.value = true
        }
        clear.assertDoesNotExist()
        val blocked = compose.onNodeWithTag(ConfigurationProtectionTestTags.PROTECTED_REGION)
        blocked.assertFullyVisible().assertMinimumTouchTarget().assertHasClickAction()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assertContentDescriptionEquals(text(R.string.configuration_protection_blocked_title))
        assertEquals("Protection covers the measured clear button in a scrolling column",
            childBounds, blocked.fetchSemanticsNode().boundsInRoot)
        val viewport = compose.onNodeWithTag(VIEWPORT).fetchSemanticsNode().boundsInRoot
        // Tap the real child's old coordinates, not a semantics action that could bypass an overlay.
        compose.onNodeWithTag(VIEWPORT).performTouchInput {
            click(Offset(childBounds.center.x - viewport.left, childBounds.center.y - viewport.top))
        }
        compose.runOnIdle {
            assertEquals(listOf("request-confirmation", "blocked"), calls)
            assertFalse(confirmationRequested.value)
            assertSame(originalHistory, history.value)
            locked.value = false
        }
        blocked.assertDoesNotExist()
        clear.performScrollTo().assertFullyVisible().assertMinimumTouchTarget()
            .performTouchInput { click(Offset(width * 0.9f, height * 0.5f)) }
        compose.runOnIdle {
            assertEquals(listOf("request-confirmation", "blocked", "request-confirmation"), calls)
            assertTrue(confirmationRequested.value)
            assertSame("Deletion is reserved for the unchanged confirmation flow", originalHistory, history.value)
        }
    }

    @Composable
    private fun ScrollFixture(content: @Composable () -> Unit) {
        Column(
            Modifier.fillMaxSize().background(AppColors.bgPrimary)
                .verticalScroll(rememberScrollState()).padding(Spacing.md),
        ) {
            // Force scroll reachability checks even for the small history heading on a tall display.
            Spacer(Modifier.height(display.height.dp))
            content()
        }
    }

    private fun assertPresetStates(selected: DateRangeOption) {
        compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton))
            .assertCountEquals(4)
        compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.Selected, true))
            .assertCountEquals(1)
        presets.forEach { (option, id) ->
            val tag = ExportDateControlTags.preset(option)
            val button = compose.onNodeWithTag(tag).performScrollTo()
                .assertFullyVisible().assertMinimumTouchTarget().assertHasClickAction()
                .assertTextEquals(text(id))
            if (option == selected) button.assertIsSelected() else button.assertIsNotSelected()
            val label = actualText(tag, text(id))
            assertTextFits(label, GeistType.heading16.fontSize)
            val buttonBounds = button.getUnclippedBoundsInRoot()
            val labelBounds = label.getUnclippedBoundsInRoot()
            assertTrue("The selected check never consumes label width",
                labelBounds.right - labelBounds.left >= buttonBounds.right - buttonBounds.left - Spacing.sm * 2 - 1.dp)
            if (GeistAdaptiveLayout.stackActions(display.width - 64f, display.fontScale)) {
                val group = compose.onNodeWithTag(ExportDateControlTags.PRESETS).getUnclippedBoundsInRoot()
                assertEquals("Crowded presets use the whole card width", group.left, buttonBounds.left)
                assertEquals(group.right, buttonBounds.right)
            }
        }
    }

    private fun assertDateRow(tag: String, labelId: Int, date: LocalDate) {
        val row = compose.onNodeWithTag(tag).performScrollTo().assertFullyVisible().assertMinimumTouchTarget()
            .assertHasClickAction().assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assertTextEquals(text(labelId), compactDate(date))
        val label = actualText(tag, text(labelId))
        val value = actualText(tag, compactDate(date))
        assertTextFits(label, GeistType.heading20.fontSize)
        assertTextFits(value, GeistType.label20Mono.fontSize)
        val valueLayout = textLayout(value)
        assertEquals(GeistType.label20Mono.fontFamily, valueLayout.layoutInput.style.fontFamily)
        assertEquals(if (display.language == "ar") LayoutDirection.Rtl else LayoutDirection.Ltr,
            valueLayout.layoutInput.layoutDirection)
        val rowBounds = row.getUnclippedBoundsInRoot()
        val labelBounds = label.getUnclippedBoundsInRoot()
        val valueBounds = value.getUnclippedBoundsInRoot()
        assertTrue("The date label gets the full row width",
            labelBounds.right - labelBounds.left >= rowBounds.right - rowBounds.left - 1.dp)
        assertTrue("The value has its own reading width, not the label's leftover width",
            valueBounds.right - valueBounds.left >= rowBounds.right - rowBounds.left - Spacing.md * 2 - 1.dp)
        assertTrue("Label and date value do not collide",
            valueBounds.top - labelBounds.bottom >= Spacing.xs - 1.dp)
        compose.onAllNodes(hasClickAction() and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
            .assertCountEquals(0)
    }

    private fun actualText(tag: String, label: String) = compose.onNode(
        hasText(label) and hasAnyAncestor(hasTestTag(tag)) and
            SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult),
        useUnmergedTree = true,
    )

    private fun compactDate(date: LocalDate): String = date.format(
        DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT).withLocale(Locale.forLanguageTag(display.language)),
    )

    private fun textLayout(node: SemanticsNodeInteraction): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        return results.single()
    }

    private fun assertReadableSecondary(node: SemanticsNodeInteraction) {
        val colors = if (display.dark) GeistDarkColors else GeistLightColors
        val foreground = textLayout(node).layoutInput.style.color
        assertEquals("Enabled helper actions use the secondary token, not disabled gray", colors.secondary, foreground)
        assertTrue("Secondary text meets AA on the actual synthetic background", contrast(foreground, colors.background100) >= 4.5)
    }

    private fun contrast(first: Color, second: Color): Double {
        val brighter = maxOf(first.luminance(), second.luminance())
        val darker = minOf(first.luminance(), second.luminance())
        return (brighter + 0.05) / (darker + 0.05)
    }

    private fun settleAndCapture(name: String) {
        compose.mainClock.advanceTimeBy(400)
        compose.waitForIdle()
        capture(name)
    }
}
