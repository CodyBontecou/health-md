package com.healthmd.presentation.accessibility

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.presentation.settings.FrontmatterCustomizationScreen
import com.healthmd.presentation.settings.FrontmatterCustomizationTags as Tags
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** Production screen + synthetic controlled configuration only; never real settings or exporters. */
@RunWith(Parameterized::class)
class FrontmatterCustomizationAccessibilityTest(display: AccessibilityDisplayCase) : AccessibilityTestHarness(display) {
    companion object {
        private const val METRIC = "blood_pressure_diastolic_avg"
        private const val LONG_OUTPUT = "synthetic_original_output_key_with_a_long_unbroken_identifier_for_reading"
        private const val LONG_CUSTOM_KEY = "synthetic_custom_metadata_key_for_accessibility"
        private const val LONG_CUSTOM_VALUE = "Synthetic metadata only: this long value stays readable at the chosen text and display scale."

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun displays() = accessibilityDisplays()
    }

    @Test
    fun keyStyleSelectionReappliesOnceAndPreservesDefaultFieldPolicy() {
        val retained = CustomFrontmatterField("steps", "synthetic_saved_steps", isEnabled = false)
        val initial = FrontmatterConfiguration(
            fields = listOf(
                CustomFrontmatterField("steps", "earlier_duplicate"),
                CustomFrontmatterField("synthetic_unknown_key", "unknown_value"),
                retained,
            ),
            customFields = mapOf("synthetic_tag" to "synthetic_value"),
            placeholderFields = listOf("synthetic_blank"),
            customDateKey = "synthetic_date", customTypeKey = "synthetic_type", customTypeValue = "synthetic_kind",
        )
        val fixture = show(initial)
        val normalized = initial.copy(fields = FrontmatterConfiguration.defaultFields.map {
            if (it.originalKey == retained.originalKey) retained else it
        })
        // Opening is presentation-only; the last saved duplicate wins, unknowns are not shown,
        // and every missing known field is supplied by the real screen without a write.
        expect(fixture, initial, 0)
        node(Tags.metric("synthetic_unknown_key")).assertDoesNotExist()
        node(Tags.metric("steps")).assertIsOff()
        node(Tags.outputKey("steps")).assertIsNotEnabled().assertEditableValue(retained.customKey)
        node(Tags.metric("sleep_total_hours")).assertIsOn()

        FrontmatterKeyStyle.entries.forEach { style ->
            val tag = Tags.style(style)
            val label = if (style == FrontmatterKeyStyle.SNAKE_CASE) "snake_case" else "camelCase"
            assertActionLabel(tag, label, GeistType.copy16.fontSize, Role.RadioButton)
            node(tag).performScrollTo().assertComfortable().assertMinimumTouchTarget()
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton))
            assertSingleAction(tag)
        }
        node(Tags.style(FrontmatterKeyStyle.SNAKE_CASE)).assertIsSelected()
        node(Tags.style(FrontmatterKeyStyle.CAMEL_CASE)).assertIsNotSelected()
        tap(Tags.style(FrontmatterKeyStyle.CAMEL_CASE))
        val camel = normalized.withKeyStyle(FrontmatterKeyStyle.CAMEL_CASE)
        expect(fixture, camel, 1)
        node(Tags.style(FrontmatterKeyStyle.CAMEL_CASE)).assertIsSelected()
        node(Tags.style(FrontmatterKeyStyle.SNAKE_CASE)).assertIsNotSelected()
        compose.runOnIdle {
            assertEquals(HealthDataFields.allKeys, fixture.state.value.fields.map { it.originalKey })
            assertEquals("bloodPressureDiastolicAvg", fixture.state.value.outputKey(METRIC))
            assertFalse(fixture.state.value.isFieldEnabled("steps"))
        }
        // Tapping the selected style still reapplies it, as the original screen did.
        tap(Tags.style(FrontmatterKeyStyle.CAMEL_CASE))
        expect(fixture, camel, 2)
        tap(Tags.style(FrontmatterKeyStyle.SNAKE_CASE))
        expect(fixture, normalized.withKeyStyle(FrontmatterKeyStyle.SNAKE_CASE), 3)
    }

    @Test
    fun dateAndTypeHaveOneWideSwitchAndKeepExactKeyboardEdits() {
        val initial = FrontmatterConfiguration()
        val fixture = show(initial)
        var expected = initial
        assertToggle(Tags.DATE_TOGGLE, text(R.string.frontmatter_include_date), checked = true)
        assertToggle(Tags.TYPE_TOGGLE, text(R.string.frontmatter_include_type), checked = true)

        replace(Tags.DATE_KEY, "  synthetic_export_date  ")
        expected = expected.copy(customDateKey = "  synthetic_export_date  ")
        expect(fixture, expected, 1)
        node(Tags.DATE_KEY).performImeAction().assertIsNotFocused()
        expect(fixture, expected, 1) // Done/focus loss never introduces another configuration write.
        tap(Tags.DATE_TOGGLE)
        expected = expected.copy(includeDate = false)
        expect(fixture, expected, 2)
        node(Tags.DATE_TOGGLE).assertIsOff()
        node(Tags.DATE_KEY).assertDoesNotExist()
        tap(Tags.DATE_TOGGLE)
        expected = expected.copy(includeDate = true)
        expect(fixture, expected, 3)
        node(Tags.DATE_KEY).assertEditableValue(expected.customDateKey)

        replace(Tags.TYPE_KEY, "  synthetic_type_key  ")
        expected = expected.copy(customTypeKey = "  synthetic_type_key  ")
        expect(fixture, expected, 4)
        node(Tags.TYPE_KEY).performImeAction()
        node(Tags.TYPE_VALUE).assertIsFocused().performScrollTo().assertComfortable()
        node(Tags.TYPE_VALUE).performTextReplacement("  synthetic type value  ")
        expected = expected.copy(customTypeValue = "  synthetic type value  ")
        expect(fixture, expected, 5)
        node(Tags.TYPE_VALUE).performImeAction().assertIsNotFocused()
        tap(Tags.TYPE_TOGGLE)
        expected = expected.copy(includeType = false)
        expect(fixture, expected, 6)
        node(Tags.TYPE_TOGGLE).assertIsOff()
        node(Tags.TYPE_KEY).assertDoesNotExist()
        node(Tags.TYPE_VALUE).assertDoesNotExist()
        tap(Tags.TYPE_TOGGLE)
        expected = expected.copy(includeType = true)
        expect(fixture, expected, 7)
        node(Tags.TYPE_KEY).assertEditableValue(expected.customTypeKey)
        node(Tags.TYPE_VALUE).assertEditableValue(expected.customTypeValue)
        listOf(Tags.DATE_KEY, Tags.TYPE_KEY, Tags.TYPE_VALUE).forEach { tag ->
            assertFieldLabel(tag)
            assertEditingTypography(tag)
        }
        node(Tags.BACK).performScrollTo().assertComfortable().assertMinimumTouchTarget().performTouchInput { click() }
        compose.runOnIdle { assertEquals(1, fixture.backCalls) }
        expect(fixture, expected, 7)
    }

    @Test
    fun customFieldsReflowTrimReplaceAndDeleteWithoutLosingLongValues() {
        val initial = FrontmatterConfiguration(customFields = linkedMapOf(
            "zeta_synthetic" to "last",
            LONG_CUSTOM_KEY to LONG_CUSTOM_VALUE,
            "alpha_synthetic" to "first",
        ))
        val fixture = show(initial)
        assertFieldLabel(Tags.CUSTOM_KEY)
        assertFieldLabel(Tags.CUSTOM_VALUE)
        val keyBounds = node(Tags.CUSTOM_KEY).getUnclippedBoundsInRoot()
        val valueBounds = node(Tags.CUSTOM_VALUE).getUnclippedBoundsInRoot()
        if (GeistAdaptiveLayout.stackActions(display.width - 64f, display.fontScale)) {
            assertTrue("Key and value reflow into separate wide rows", valueBounds.top >= keyBounds.bottom)
            assertEquals(keyBounds.left, valueBounds.left)
            assertEquals(keyBounds.right, valueBounds.right)
            assertReadingWidth(node(Tags.label(Tags.CUSTOM_KEY), unmerged = true))
        }
        assertActionLabel(Tags.CUSTOM_ADD, text(R.string.a11y_frontmatter_add_custom_field))
        replace(Tags.CUSTOM_KEY, "   ")
        replace(Tags.CUSTOM_VALUE, "  synthetic draft  ")
        tap(Tags.CUSTOM_ADD)
        expect(fixture, initial, 0)
        node(Tags.CUSTOM_KEY).assertEditableValue("   ")
        node(Tags.CUSTOM_VALUE).assertEditableValue("  synthetic draft  ")

        replace(Tags.CUSTOM_KEY, "  middle_synthetic  ")
        node(Tags.CUSTOM_KEY).performImeAction()
        node(Tags.CUSTOM_VALUE).assertIsFocused()
        tap(Tags.CUSTOM_ADD)
        var expected = initial.copy(customFields = initial.customFields + ("middle_synthetic" to "synthetic draft"))
        expect(fixture, expected, 1)
        node(Tags.CUSTOM_KEY).assertEditableValue("")
        node(Tags.CUSTOM_VALUE).assertEditableValue("")
        node(Tags.CUSTOM_VALUE).performImeAction()
        // Existing custom keys replace their values; they are not rejected like placeholders.
        replace(Tags.CUSTOM_KEY, " middle_synthetic ")
        replace(Tags.CUSTOM_VALUE, "   ")
        tap(Tags.CUSTOM_ADD)
        expected = expected.copy(customFields = expected.customFields + ("middle_synthetic" to ""))
        expect(fixture, expected, 2)
        node(Tags.CUSTOM_VALUE).performImeAction()
        assertEntryOrder(expected.customFields.keys.sorted().map(Tags::custom))

        val entry = Tags.custom(LONG_CUSTOM_KEY)
        assertReadingText(Tags.label(entry), LONG_CUSTOM_KEY, GeistType.copy14Mono.fontSize)
        assertReadingText(Tags.currentValue(entry), LONG_CUSTOM_VALUE, GeistType.copy13.fontSize)
        val delete = node(Tags.delete(entry))
        delete.assertContentDescriptionEquals(text(R.string.a11y_frontmatter_delete_custom_field, LONG_CUSTOM_KEY))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, LONG_CUSTOM_VALUE))
        assertActionLabel(Tags.delete(entry), text(R.string.action_delete_field))
        node(Tags.label(entry), unmerged = true).performScrollTo()
        capture("frontmatter-custom")
        tap(Tags.delete(entry))
        expected = expected.copy(customFields = expected.customFields - LONG_CUSTOM_KEY)
        expect(fixture, expected, 3)
        node(entry).assertDoesNotExist()
        node(Tags.custom("alpha_synthetic")).assertExists()
        node(Tags.custom("zeta_synthetic")).assertExists()
    }

    @Test
    fun placeholderGuardsRetainDraftsAndRemovalKeepsExistingDuplicatePolicy() {
        val initial = FrontmatterConfiguration(placeholderFields = listOf("zeta_blank", "middle_blank", "middle_blank"))
        val fixture = show(initial)
        assertFieldLabel(Tags.PLACEHOLDER_KEY)
        assertActionLabel(Tags.PLACEHOLDER_ADD, text(R.string.a11y_frontmatter_add_placeholder_field))
        replace(Tags.PLACEHOLDER_KEY, "   ")
        tap(Tags.PLACEHOLDER_ADD)
        expect(fixture, initial, 0)
        node(Tags.PLACEHOLDER_KEY).assertEditableValue("   ")
        replace(Tags.PLACEHOLDER_KEY, "  middle_blank  ")
        tap(Tags.PLACEHOLDER_ADD)
        expect(fixture, initial, 0)
        node(Tags.PLACEHOLDER_KEY).assertEditableValue("  middle_blank  ")
        replace(Tags.PLACEHOLDER_KEY, "  alpha_blank  ")
        tap(Tags.PLACEHOLDER_ADD)
        var expected = initial.copy(placeholderFields = listOf("alpha_blank", "middle_blank", "middle_blank", "zeta_blank"))
        expect(fixture, expected, 1)
        node(Tags.PLACEHOLDER_KEY).assertEditableValue("").performImeAction()
        val alpha = Tags.placeholder("alpha_blank")
        val delete = Tags.delete(alpha)
        node(delete).assertContentDescriptionEquals(text(R.string.a11y_frontmatter_delete_placeholder_field, "alpha_blank"))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, text(R.string.frontmatter_placeholder_value)))
        assertReadingText(Tags.label(alpha), "alpha_blank", GeistType.copy14Mono.fontSize)
        assertActionLabel(delete, text(R.string.action_delete_field))
        tap(delete)
        expected = expected.copy(placeholderFields = listOf("middle_blank", "middle_blank", "zeta_blank"))
        expect(fixture, expected, 2)
        node(alpha).assertDoesNotExist()
        // Already-saved duplicate placeholders are not silently normalized. List-minus-key
        // removes one occurrence, exactly as before; the Add guard still prevents new duplicates.
        val duplicateDelete = Tags.delete(Tags.placeholder("middle_blank"))
        compose.onAllNodesWithTag(duplicateDelete).assertCountEquals(2)
        compose.onAllNodesWithTag(duplicateDelete)[0].performScrollTo().assertComfortable()
            .assertMinimumTouchTarget().performTouchInput { click() }
        expected = expected.copy(placeholderFields = listOf("middle_blank", "zeta_blank"))
        expect(fixture, expected, 3)
        compose.onAllNodesWithTag(duplicateDelete).assertCountEquals(1)
    }

    @Test
    fun searchFindsOriginalAndCustomKeysWithOneMetricToggleAndDisabledEditor() {
        val saved = CustomFrontmatterField(METRIC, LONG_OUTPUT)
        val disabledSteps = CustomFrontmatterField("steps", "synthetic_steps", isEnabled = false)
        val initial = FrontmatterConfiguration(fields = listOf(saved, disabledSteps, CustomFrontmatterField("synthetic_unknown")))
        val fixture = show(initial)
        val normalized = initial.copy(fields = FrontmatterConfiguration.defaultFields.map {
            when (it.originalKey) {
                METRIC -> saved
                "steps" -> disabledSteps
                else -> it
            }
        })
        replace(Tags.SEARCH, METRIC.uppercase())
        node(Tags.SEARCH).performImeAction()
        expect(fixture, initial, 0)
        node(Tags.metric("steps")).assertDoesNotExist()
        node(Tags.metric("synthetic_unknown")).assertDoesNotExist()
        assertToggle(Tags.metric(METRIC), METRIC, checked = true, fontSize = GeistType.copy14Mono.fontSize)
        assertReadingWidth(node(Tags.label(Tags.metric(METRIC)), unmerged = true))
        val output = Tags.outputKey(METRIC)
        node(output).assertEditableValue(LONG_OUTPUT).assertIsEnabled()
        assertFieldLabel(output)
        assertEditingTypography(output)
        assertReadingText(Tags.currentValue(output), LONG_OUTPUT, GeistType.copy16.fontSize)

        tap(Tags.metric(METRIC))
        var expected = normalized.copy(fields = normalized.fields.map {
            if (it.originalKey == METRIC) it.copy(isEnabled = false) else it
        })
        expect(fixture, expected, 1)
        node(Tags.metric(METRIC)).assertIsOff()
        node(output).performScrollTo().assertComfortable().assertIsNotEnabled()
            .assertEditableValue(LONG_OUTPUT).performTouchInput { click() }
        node(output).assertIsNotFocused()
        expect(fixture, expected, 1)
        assertReadingText(Tags.currentValue(output), LONG_OUTPUT, GeistType.copy16.fontSize)
        compose.runOnIdle { assertEquals(null, fixture.state.value.outputKey(METRIC)) }
        tap(Tags.metric(METRIC))
        expected = expected.copy(fields = expected.fields.map {
            if (it.originalKey == METRIC) it.copy(isEnabled = true) else it
        })
        expect(fixture, expected, 2)
        val edited = "  synthetic_RENAMED_output_key_for_screen_reader_reading_and_editing  "
        replace(output, edited)
        expected = expected.copy(fields = expected.fields.map {
            if (it.originalKey == METRIC) it.copy(customKey = edited) else it
        })
        expect(fixture, expected, 3)
        node(output).performImeAction()
        node(output).assertEditableValue(edited)
            .assertContentDescriptionEquals("$METRIC, ${text(R.string.frontmatter_output_key)}")
        replace(Tags.SEARCH, "renamed")
        node(Tags.SEARCH).performImeAction()
        node(Tags.metric(METRIC)).assertIsOn()
        node(Tags.metric("steps")).assertDoesNotExist()
        expect(fixture, expected, 3)
        node(Tags.metric(METRIC)).performScrollTo().assertComfortable()
        capture("frontmatter-metric")
        replace(Tags.SEARCH, "   ")
        node(Tags.SEARCH).performImeAction()
        val metricNodes = compose.onAllNodes(SemanticsMatcher("frontmatter metric row") { semanticsNode ->
            SemanticsProperties.TestTag in semanticsNode.config &&
                semanticsNode.config[SemanticsProperties.TestTag].startsWith("frontmatter.metric.")
        }).fetchSemanticsNodes()
        assertEquals(HealthDataFields.allKeys.map(Tags::metric), metricNodes.map { it.config[SemanticsProperties.TestTag] })
        node(Tags.metric("steps")).assertIsOff()
        expect(fixture, expected, 3)
    }

    @Test
    fun focusedDraftKeepsAddDeleteAndBackReachableWithoutExtraWrites() {
        val initial = FrontmatterConfiguration(customFields = mapOf("synthetic_existing" to "existing"))
        val fixture = show(initial)
        replace(Tags.CUSTOM_KEY, "synthetic_keyboard")
        node(Tags.CUSTOM_KEY).performImeAction()
        node(Tags.CUSTOM_VALUE).assertIsFocused().performScrollTo().assertComfortable()
            .performTextReplacement("synthetic keyboard value")
        expect(fixture, initial, 0)
        // Do not dismiss the keyboard to reach these actions. Scroll the real form while
        // its draft input remains focused; keyboard suggestions are never screen-captured.
        node(Tags.BACK).performScrollTo().assertComfortable().assertMinimumTouchTarget()
        tap(Tags.CUSTOM_ADD)
        val added = initial.copy(customFields = initial.customFields + ("synthetic_keyboard" to "synthetic keyboard value"))
        expect(fixture, added, 1)
        node(Tags.CUSTOM_VALUE).assertIsFocused()
        tap(Tags.delete(Tags.custom("synthetic_keyboard")))
        expect(fixture, initial, 2)
        node(Tags.CUSTOM_VALUE).assertIsFocused()
        node(Tags.BACK).performScrollTo().assertComfortable().assertMinimumTouchTarget().performTouchInput { click() }
        compose.runOnIdle { assertEquals(1, fixture.backCalls) }
        expect(fixture, initial, 2)
        node(Tags.CUSTOM_VALUE).performImeAction().assertIsNotFocused()
        expect(fixture, initial, 2)
    }

    private class Fixture(initial: FrontmatterConfiguration) {
        val state = mutableStateOf(initial)
        val updates = mutableListOf<FrontmatterConfiguration>()
        var backCalls = 0
    }

    private fun show(initial: FrontmatterConfiguration): Fixture = Fixture(initial).also { fixture ->
        setContent {
            FrontmatterCustomizationScreen(
                configuration = fixture.state.value,
                onConfigurationChanged = { fixture.updates += it; fixture.state.value = it },
                onBack = { fixture.backCalls++ },
            )
        }
    }

    private fun expect(fixture: Fixture, expected: FrontmatterConfiguration, updates: Int) {
        compose.runOnIdle {
            assertEquals("Exactly one update per accepted action; none for drafts, guards or IME", updates, fixture.updates.size)
            assertEquals(expected, fixture.state.value)
            if (updates > 0) assertEquals(expected, fixture.updates.last())
        }
    }

    private fun node(tag: String, unmerged: Boolean = false) = compose.onNodeWithTag(tag, useUnmergedTree = unmerged)

    private fun tap(tag: String) {
        node(tag).performScrollTo().assertComfortable().assertMinimumTouchTarget().assertIsEnabled()
            .performTouchInput {
                // Label/start edge rather than a switch thumb; the whole row must activate once.
                click(Offset(width * (if (display.language == "ar") 0.9f else 0.1f), height * 0.25f))
            }
    }

    private fun replace(tag: String, value: String) {
        node(tag).performScrollTo().assertComfortable().assertMinimumTouchTarget()
            .performTouchInput { click() }
        node(tag).assertIsFocused().performTextReplacement(value)
        node(tag).performScrollTo().assertComfortable().assertEditableValue(value)
    }

    private fun SemanticsNodeInteraction.assertEditableValue(value: String): SemanticsNodeInteraction =
        assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(value)))

    private fun SemanticsNodeInteraction.assertComfortable(): SemanticsNodeInteraction {
        assertFullyVisible()
        val bounds = getUnclippedBoundsInRoot()
        val body = node(Tags.BODY).getUnclippedBoundsInRoot()
        assertTrue("An entire target must fit inside the IME-padded scroll area, not just its center: $bounds in $body",
            bounds.top >= body.top - 1.dp && bounds.bottom <= body.bottom + 1.dp)
        return this
    }

    private fun assertSingleAction(tag: String) {
        node(tag).assertHasClickAction()
        compose.onAllNodes(hasAnyAncestor(hasTestTag(tag)) and hasClickAction(), useUnmergedTree = true).assertCountEquals(0)
    }

    private fun assertToggle(tag: String, label: String, checked: Boolean, fontSize: TextUnit = GeistType.copy16.fontSize) {
        node(tag).performScrollTo().assertComfortable().assertMinimumTouchTarget()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, text(if (checked) R.string.enabled else R.string.disabled)))
            .assertTextContains(label)
        if (checked) node(tag).assertIsOn() else node(tag).assertIsOff()
        assertSingleAction(tag)
        val labelNode = node(Tags.label(tag), unmerged = true).performScrollTo().assertFullyVisible()
        assertTextFits(labelNode, fontSize)
        if (GeistAdaptiveLayout.stackDetailedControls(display.width - 64f, display.fontScale)) {
            assertReadingWidth(labelNode)
        }
    }

    private fun assertActionLabel(
        tag: String,
        label: String,
        fontSize: TextUnit = GeistType.button14.fontSize,
        role: Role = Role.Button,
    ) {
        val labelNode = compose.onNode(hasText(label) and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
            .performScrollTo().assertFullyVisible()
        assertTextFits(labelNode, fontSize)
        node(tag).performScrollTo().assertComfortable().assertMinimumTouchTarget()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, role))
        assertSingleAction(tag)
    }

    private fun assertFieldLabel(tag: String) {
        val label = node(Tags.label(tag), unmerged = true).performScrollTo().assertFullyVisible()
        assertTextFits(label, GeistType.copy16.fontSize)
        val labelBounds = label.getUnclippedBoundsInRoot()
        val fieldBounds = node(tag).getUnclippedBoundsInRoot()
        assertTrue("Labels stay outside the editing area", labelBounds.bottom <= fieldBounds.top)
        assertEquals("Labels get the entire input width", fieldBounds.right - fieldBounds.left, labelBounds.right - labelBounds.left)
    }

    private fun assertEditingTypography(tag: String) {
        val field = node(tag, unmerged = true).performScrollTo().assertComfortable().assertMinimumTouchTarget()
        val layouts = mutableListOf<TextLayoutResult>()
        field.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        layouts.forEach { result ->
            assertEquals(GeistType.copy16.fontSize, result.layoutInput.style.fontSize)
            assertEquals(display.fontScale, result.layoutInput.density.fontScale)
            assertFalse(result.didOverflowHeight)
            repeat(result.lineCount) { assertFalse(result.isLineEllipsized(it)) }
        }
        // Single-line identifiers can horizontally scroll; long values additionally have a
        // separate wrapping preview checked with assertTextFits, including when disabled.
    }

    private fun assertReadingText(tag: String, value: String, fontSize: TextUnit) {
        val textNode = node(tag, unmerged = true).performScrollTo().assertFullyVisible().assertTextEquals(value)
        assertTextFits(textNode, fontSize)
        assertReadingWidth(textNode)
    }

    private fun assertReadingWidth(textNode: SemanticsNodeInteraction) {
        val bounds = textNode.getUnclippedBoundsInRoot()
        val body = node(Tags.BODY).getUnclippedBoundsInRoot()
        assertTrue("Reading text uses the full width after the page/card's two 16 dp gutters",
            bounds.right - bounds.left >= body.right - body.left - 65.dp)
    }

    private fun assertEntryOrder(tags: List<String>) {
        tags.zipWithNext().forEach { (first, second) ->
            assertTrue("Entries remain sorted", node(first).getUnclippedBoundsInRoot().top < node(second).getUnclippedBoundsInRoot().top)
        }
    }
}
