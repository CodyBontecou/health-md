package com.healthmd.presentation.accessibility

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.*
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.presentation.i18n.displayNameRes
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.metrics.MetricSelectionTags
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.text.NumberFormat
import java.util.Locale

/** Production UI and real selector definitions, with synthetic state and no ViewModels/Health Connect. */
@RunWith(Parameterized::class)
class MetricSelectionAccessibilityTest(display: AccessibilityDisplayCase) : AccessibilityTestHarness(display) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun displays() = accessibilityDisplays()
    }

    @Test
    fun bulkActionsScrollAndPreserveExactSelectionsAndProgress() {
        val fixture = render()
        assertSummary(fixture.selection.value)
        scrollTo(MetricSelectionTags.HEADER)
        assertTextFits(node(MetricSelectionTags.HEADER, unmerged = true), GeistType.heading20.fontSize)
        capture("metrics-header")

        scrollTo(MetricSelectionTags.SEARCH_LABEL)
        assertTextFits(node(MetricSelectionTags.SEARCH_LABEL, unmerged = true), GeistType.copy16.fontSize)
        scrollTo(MetricSelectionTags.SEARCH_FIELD).assertMinimumTouchTarget()
            .assertContentDescriptionEquals(text(R.string.search_metrics_hint))

        val select = scrollTo(MetricSelectionTags.SELECT_ALL).assertMinimumTouchTarget()
        assertButtonLabel(MetricSelectionTags.SELECT_ALL, R.string.select_all)
        val deselect = scrollTo(MetricSelectionTags.DESELECT_ALL).assertMinimumTouchTarget()
        assertButtonLabel(MetricSelectionTags.DESELECT_ALL, R.string.deselect_all)
        if (GeistAdaptiveLayout.stackActions(display.width - 32f, display.fontScale)) {
            val selectBounds = select.unclippedBoundsOnIdle()
            val deselectBounds = deselect.unclippedBoundsOnIdle()
            assertEquals("Stacked actions use the same full width", selectBounds.left, deselectBounds.left)
            assertEquals(selectBounds.right, deselectBounds.right)
            assertTrue("Select All is first when stacked", selectBounds.bottom <= deselectBounds.top)
        }
        deselect.performTouchInput { click() }
        val none = MetricSelectionState().disableAll()
        fixture.assertChanges(none)
        assertSummary(none)

        scrollTo(MetricSelectionTags.SELECT_ALL).performTouchInput { click() }
        fixture.assertChanges(none, none.enableAll())
        assertSummary(none.enableAll())
        // The final real metric is reachable without being hidden by the growing header.
        scrollTo(MetricSelectionTags.metric(HealthMetrics.allMetrics.last().id)).assertMinimumTouchTarget()
        assertNavigation(fixture, tapBack = true)
    }

    @Test
    fun categorySelectionHasThreeStatesAndExpansionIsIndependent() {
        val category = HealthMetricCategory.REPRODUCTIVE
        val metrics = HealthMetrics.metricsForCategory(category)
        val outside = HealthMetrics.allMetrics.first { it.category != category }
        val initial = MetricSelectionState(setOf(metrics.first().id, outside.id))
        val fixture = render(initial)
        assertCategory(category, initial, expanded = true)
        scrollTo(MetricSelectionTags.expansion(category))
        capture("metrics-category")

        scrollTo(MetricSelectionTags.expansion(category)).performTouchInput { click() }
        fixture.assertChanges()
        assertCategory(category, initial, expanded = false)
        node(MetricSelectionTags.metric(metrics.first().id)).assertDoesNotExist()

        // A partial category selects every metric in that category; it does not expand.
        scrollTo(MetricSelectionTags.categorySelection(category)).performTouchInput { click() }
        val full = initial.toggleCategory(category)
        fixture.assertChanges(full)
        assertCategory(category, full, expanded = false)
        node(MetricSelectionTags.metric(metrics.first().id)).assertDoesNotExist()

        scrollTo(MetricSelectionTags.expansion(category)).performTouchInput { click() }
        fixture.assertChanges(full)
        assertCategory(category, full, expanded = true)
        scrollTo(MetricSelectionTags.categorySelection(category)).performTouchInput { click() }
        val none = full.toggleCategory(category)
        fixture.assertChanges(full, none)
        assertCategory(category, none, expanded = true)
        scrollTo(MetricSelectionTags.metric(metrics.first().id)).assertIsOff().performTouchInput { click() }
        val partial = none.toggle(metrics.first().id)
        fixture.assertChanges(full, none, partial)
        assertCategory(category, partial, expanded = true)
        compose.runOnIdle {
            assertTrue("Changing a category never changes another category", fixture.selection.value.isEnabled(outside.id))
        }
    }

    @Test
    fun longLocalizedMetricNameAndUnitShareOneCheckboxTarget() {
        // Exercise the longest available localized name with a real, unchanged unit.
        val metric = HealthMetrics.allMetrics.filter { it.unit.isNotEmpty() }
            .maxBy { text(it.displayNameRes()).length }
        val initial = MetricSelectionState(emptySet())
        val fixture = render(initial)
        val tag = MetricSelectionTags.metric(metric.id)
        val row = scrollTo(tag).assertMinimumTouchTarget().assertIsOff()
        assertSingleCheckbox(tag)
        row.assertTextContains(text(metric.displayNameRes())).assertTextContains(metric.unit)

        val name = node(MetricSelectionTags.metricName(metric.id), unmerged = true)
        val unit = node(MetricSelectionTags.metricUnit(metric.id), unmerged = true)
        name.assertFullyVisible().assertInsideList()
        unit.assertFullyVisible().assertInsideList()
        assertTextFits(name, GeistType.copy16.fontSize)
        assertTextFits(unit, GeistType.copy13.fontSize)
        val rowBounds = row.unclippedBoundsOnIdle()
        val nameBounds = name.unclippedBoundsOnIdle()
        if (GeistAdaptiveLayout.stackDetailedControls(display.width - 32f, display.fontScale)) {
            assertTrue("The reading label gets the full inner row width, not a checkbox column",
                nameBounds.right - nameBounds.left >= rowBounds.right - rowBounds.left - 17.dp)
        }
        capture("metrics-rows")

        // Real pointer hits on the text and the drawn checkbox each dispatch exactly one
        // identical toggle(metric.id), rather than a row click plus a nested checkbox click.
        name.performTouchInput { click() }
        val enabled = initial.toggle(metric.id)
        fixture.assertChanges(enabled)
        node(tag).assertIsOn()
        node(MetricSelectionTags.metricIndicator(metric.id), unmerged = true)
            .assertFullyVisible().assertInsideList().performTouchInput { click() }
        fixture.assertChanges(enabled, initial)
        node(tag).assertIsOff()
    }

    @Test
    fun localizedSearchKeepsFocusAndFilteredMetricsAndBackAreReachable() {
        val fixture = render(MetricSelectionState(emptySet()))
        // Start far from the editor to verify that the persistent Search shortcut restores it.
        scrollTo(MetricSelectionTags.metric(HealthMetrics.allMetrics.last().id))
        node(MetricSelectionTags.SEARCH_ACTION).assertFullyVisible().assertMinimumTouchTarget()
            .assertContentDescriptionEquals(text(R.string.search)).performTouchInput { click() }
        val field = node(MetricSelectionTags.SEARCH_FIELD)
        field.assertIsFocused().assertMinimumTouchTarget().assertFullyVisible().assertInsideList()
        val query = text(HealthMetrics.allMetrics.first().displayNameRes())
            .take(3).uppercase(Locale.forLanguageTag(display.language))
        field.performTextReplacement(query)
        field.assertIsFocused().assertTextContains(query)
        assertTextFits(field, GeistType.copy16.fontSize)
        // This synthetic Back callback records navigation without removing the fixture,
        // so editing/results can still be verified after tapping Back with focus/IME open.
        assertNavigation(fixture, tapBack = true)
        val filtered = HealthMetrics.allMetrics.filter { text(it.displayNameRes()).contains(query, ignoreCase = true) }
        assertTrue("The localized query must match real metrics", filtered.isNotEmpty())
        assertTrue("The query actually filters", filtered.size < HealthMetrics.totalCount)

        // Keep the editing session open while scrolling the results. The production IME
        // padding applies; no system keyboard, text scale, or display settings are changed.
        val metric = filtered.last()
        val row = scrollTo(MetricSelectionTags.metric(metric.id)).assertMinimumTouchTarget()
        row.assertIsOff().performTouchInput { click() }
        fixture.assertChanges(MetricSelectionState(emptySet()).toggle(metric.id))

        // The shortcut works with an existing query, and the keyboard Search action ends
        // editing without altering the query or selection. It is not a persistence action.
        node(MetricSelectionTags.SEARCH_ACTION).performTouchInput { click() }
        field.assertIsFocused().assertTextContains(query)
        field.performImeAction()
        field.assertIsNotFocused().assertTextContains(query)
        fixture.assertChanges(MetricSelectionState(emptySet()).toggle(metric.id))
        scrollTo(MetricSelectionTags.metric(metric.id)).assertIsOn()
        capture("metrics-search")
        compose.runOnIdle { assertEquals(1, fixture.backCalls) }
    }

    @Test
    fun searchPreservesCollapsedStateAndCategoryActionsStillAffectTheWholeCategory() {
        val metric = HealthMetrics.metricsForCategory(HealthMetricCategory.SLEEP).first()
        val category = metric.category
        val initial = MetricSelectionState(emptySet())
        val fixture = render(initial)
        scrollTo(MetricSelectionTags.expansion(category)).performTouchInput { click() }
        node(MetricSelectionTags.SEARCH_ACTION).performTouchInput { click() }
        val field = node(MetricSelectionTags.SEARCH_FIELD)
        val query = text(metric.displayNameRes())
        field.performTextReplacement(query)
        field.performImeAction()
        assertCategory(category, initial, expanded = false)
        node(MetricSelectionTags.metric(metric.id)).assertDoesNotExist()

        scrollTo(MetricSelectionTags.categorySelection(category)).performTouchInput { click() }
        val full = initial.toggleCategory(category)
        fixture.assertChanges(full)
        assertCategory(category, full, expanded = false)
        assertSummary(full)
        scrollTo(MetricSelectionTags.expansion(category)).performTouchInput { click() }
        scrollTo(MetricSelectionTags.metric(metric.id)).assertIsOn()
        val nonmatchingSibling = HealthMetrics.metricsForCategory(category).first {
            !text(it.displayNameRes()).contains(query, ignoreCase = true)
        }
        node(MetricSelectionTags.metric(nonmatchingSibling.id)).assertDoesNotExist()

        node(MetricSelectionTags.SEARCH_ACTION).performTouchInput { click() }
        field.performTextClearance()
        field.performImeAction()
        assertCategory(category, full, expanded = true)
        scrollTo(MetricSelectionTags.metric(nonmatchingSibling.id)).assertIsOn()
        fixture.assertChanges(full)

        // Do not accidentally expand search semantics to persisted IDs.
        node(MetricSelectionTags.SEARCH_ACTION).performTouchInput { click() }
        field.performTextReplacement(metric.id)
        field.performImeAction()
        compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
            .assertCountEquals(0)
        assertNavigation(fixture, tapBack = false)
        node(MetricSelectionTags.SEARCH_ACTION).performTouchInput { click() }
        field.performTextReplacement("   ")
        field.performImeAction()
        scrollTo(MetricSelectionTags.metric(HealthMetrics.allMetrics.last().id)).assertIsOff()
        assertCategory(category, full, expanded = true)
        fixture.assertChanges(full)
    }

    @Test
    fun callerCanRejectSelectionChangesWithoutOptimisticLocalMutation() {
        // Models a rejecting caller, not the configuration manager itself. The actual
        // permission/configuration navigation guard stays outside this stateless UI.
        val initial = MetricSelectionState()
        val fixture = render(initial, acceptChanges = false)
        val metric = HealthMetrics.allMetrics.first()
        scrollTo(MetricSelectionTags.metric(metric.id)).assertIsOn().performTouchInput { click() }
        node(MetricSelectionTags.metric(metric.id)).assertIsOn()
        scrollTo(MetricSelectionTags.categorySelection(metric.category)).performTouchInput { click() }
        scrollTo(MetricSelectionTags.DESELECT_ALL).performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(listOf(initial.toggle(metric.id), initial.toggleCategory(metric.category), initial.disableAll()), fixture.changes)
            assertEquals("The caller, not a local optimistic copy, owns the selection", initial, fixture.selection.value)
        }
        assertSummary(initial)
        assertCategory(metric.category, initial, expanded = true)
        assertNavigation(fixture, tapBack = true)
    }

    private class SelectionFixture(initial: MetricSelectionState) {
        val selection: MutableState<MetricSelectionState> = mutableStateOf(initial)
        val changes = mutableListOf<MetricSelectionState>()
        var backCalls = 0
    }

    private fun render(initial: MetricSelectionState = MetricSelectionState(), acceptChanges: Boolean = true): SelectionFixture {
        val fixture = SelectionFixture(initial)
        setContent(suppressSoftwareKeyboard = true) {
            MetricSelectionScreen(
                metricSelection = fixture.selection.value,
                onSelectionChanged = {
                    fixture.changes += it
                    if (acceptChanges) fixture.selection.value = it
                },
                onBack = { fixture.backCalls++ },
            )
        }
        return fixture
    }

    private fun SelectionFixture.assertChanges(vararg expected: MetricSelectionState) {
        compose.runOnIdle {
            assertEquals("Exactly one selection callback per tap, with unchanged model semantics", expected.toList(), changes)
            if (expected.isNotEmpty()) assertEquals(expected.last(), selection.value)
        }
    }

    private fun node(tag: String, unmerged: Boolean = false) = compose.onNodeWithTag(tag, useUnmergedTree = unmerged)

    private fun scrollTo(tag: String): SemanticsNodeInteraction {
        val itemKey = when (tag) {
            MetricSelectionTags.COUNT, MetricSelectionTags.PROGRESS -> MetricSelectionTags.HEADER
            MetricSelectionTags.SEARCH_LABEL -> MetricSelectionTags.SEARCH_FIELD
            MetricSelectionTags.SELECT_ALL, MetricSelectionTags.DESELECT_ALL -> MetricSelectionTags.BULK_ACTIONS
            else -> tag
        }
        val list = node(MetricSelectionTags.LIST)
        val listNode = list.fetchSemanticsNode("Metric list is unavailable.")
        compose.runOnIdle {
            val index = listNode.config[SemanticsProperties.IndexForKey](itemKey)
            require(index >= 0) { "No metric-list item has key $itemKey" }
            check(listNode.config[SemanticsActions.ScrollToIndex].action?.invoke(index) == true) {
                "Metric list rejected scroll to $itemKey at index $index"
            }
        }
        compose.waitForIdle()
        // performScrollToNode synchronously measures LazyColumn content on the instrumentation
        // thread and can race AndroidPrefetchScheduler's main-thread premeasure on slow runners.
        return node(tag).assertFullyVisible().assertInsideList()
    }

    private fun SemanticsNodeInteraction.assertInsideList(): SemanticsNodeInteraction {
        val bounds = unclippedBoundsOnIdle()
        val list = node(MetricSelectionTags.LIST).unclippedBoundsOnIdle()
        assertTrue("A whole target must fit in the remaining list height, not just have a tappable center: $bounds in $list",
            bounds.top >= list.top - 1.dp && bounds.bottom <= list.bottom + 1.dp)
        assertTrue("Reading content must fit the list width: $bounds in $list",
            bounds.left >= list.left - 1.dp && bounds.right <= list.right + 1.dp)
        return this
    }

    private fun assertButtonLabel(tag: String, label: Int) {
        node(tag).assertHasClickAction().assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        val labelNode = compose.onNode(hasText(text(label)) and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
        labelNode.assertFullyVisible().assertInsideList()
        assertTextFits(labelNode, GeistType.button14.fontSize)
    }

    private fun assertSummary(selection: MetricSelectionState) {
        val format = NumberFormat.getIntegerInstance(Locale.forLanguageTag(display.language)).apply { isGroupingUsed = false }
        scrollTo(MetricSelectionTags.COUNT)
            .assertTextEquals("${format.format(selection.enabledCount)}/${format.format(HealthMetrics.totalCount)}")
        assertTextFits(node(MetricSelectionTags.COUNT, unmerged = true), GeistType.button14.fontSize)
        scrollTo(MetricSelectionTags.PROGRESS).assert(SemanticsMatcher.expectValue(
            SemanticsProperties.ProgressBarRangeInfo,
            ProgressBarRangeInfo(selection.enabledCount.toFloat() / HealthMetrics.totalCount, 0f..1f),
        ))
    }

    private fun assertCategory(category: HealthMetricCategory, selection: MetricSelectionState, expanded: Boolean) {
        val expansionTag = MetricSelectionTags.expansion(category)
        val expansion = scrollTo(expansionTag).assertMinimumTouchTarget()
        expansion.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription,
                text(if (expanded) R.string.a11y_metrics_expanded else R.string.a11y_metrics_collapsed)))
        assertEquals(text(
            if (expanded) R.string.a11y_metrics_collapse_category else R.string.a11y_metrics_expand_category,
            text(category.displayNameRes()),
        ), expansion.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        val name = node(MetricSelectionTags.categoryName(category), unmerged = true)
        name.assertTextEquals(text(category.displayNameRes()))
        assertTextFits(name, GeistType.heading16.fontSize)
        val count = node(MetricSelectionTags.categoryCount(category), unmerged = true)
        count.assertTextEquals(text(R.string.metrics_enabled_category,
            selection.enabledCountForCategory(category), HealthMetrics.metricsForCategory(category).size))
        assertTextFits(count, GeistType.copy13.fontSize)
        val nameBounds = name.unclippedBoundsOnIdle()
        val expansionBounds = expansion.unclippedBoundsOnIdle()
        assertTrue("Category names get the full inner width, separate from checkbox and chevron",
            nameBounds.right - nameBounds.left >= expansionBounds.right - expansionBounds.left - 17.dp)
        val tag = MetricSelectionTags.categorySelection(category)
        val checkbox = scrollTo(tag).assertMinimumTouchTarget()
        checkbox.assertContentDescriptionEquals(text(R.string.a11y_metrics_category_selection, text(category.displayNameRes())))
        val state = when {
            selection.isCategoryFullyEnabled(category) -> ToggleableState.On
            selection.isCategoryPartiallyEnabled(category) -> ToggleableState.Indeterminate
            else -> ToggleableState.Off
        }
        checkbox.assert(SemanticsMatcher.expectValue(SemanticsProperties.ToggleableState, state))
        assertSingleCheckbox(tag)
        val label = compose.onNode(hasText(text(R.string.select_all)) and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
        assertTextFits(label, GeistType.button14.fontSize)
    }

    private fun assertSingleCheckbox(tag: String) {
        node(tag).assertHasClickAction().assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
        compose.onAllNodes(hasAnyAncestor(hasTestTag(tag)) and hasClickAction(), useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodes(hasAnyAncestor(hasTestTag(tag)) and
            SemanticsMatcher.keyIsDefined(SemanticsProperties.ToggleableState), useUnmergedTree = true).assertCountEquals(0)
    }

    private fun assertNavigation(fixture: SelectionFixture, tapBack: Boolean) {
        node(MetricSelectionTags.BACK).assertFullyVisible().assertMinimumTouchTarget()
            .assertContentDescriptionEquals(text(R.string.back))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        node(MetricSelectionTags.SEARCH_ACTION).assertFullyVisible().assertMinimumTouchTarget()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        if (tapBack) {
            node(MetricSelectionTags.BACK).performTouchInput { click() }
            compose.runOnIdle { assertEquals("Back calls only the supplied navigation callback", 1, fixture.backCalls) }
        } else {
            compose.runOnIdle { assertEquals(0, fixture.backCalls) }
        }
    }
}
