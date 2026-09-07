package com.healthmd.presentation.accessibility

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.healthmd.R
import com.healthmd.domain.model.*
import com.healthmd.presentation.settings.FormatCustomizationScreen
import com.healthmd.presentation.settings.FormatCustomizationTags as Tags
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** Production settings UI with synthetic state only; never opens a real settings repository. */
@RunWith(Parameterized::class)
class FormatCustomizationAccessibilityTest(display: AccessibilityDisplayCase) : AccessibilityTestHarness(display) {
    companion object {
        private const val EDITOR_WINDOW = "format.test.editorWindow"

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun displays() = accessibilityDisplays()
    }

    @Test
    fun dateChoicesHaveOneLabeledRadioActionPerLabelOrIndicatorTap() {
        val fixture = showFormat()
        exerciseChoices(
            fixture, Tags.DATE,
            listOf(
                DateFormatPreference.ISO8601 to text(R.string.date_format_display_iso8601),
                DateFormatPreference.US_SHORT to text(R.string.date_format_display_us_short),
                DateFormatPreference.US_LONG to text(R.string.date_format_display_us_long),
                DateFormatPreference.EU_SHORT to text(R.string.date_format_display_eu_short),
                DateFormatPreference.EU_LONG to text(R.string.date_format_display_eu_long),
                DateFormatPreference.COMPACT to text(R.string.date_format_display_compact),
                DateFormatPreference.FRIENDLY to text(R.string.date_format_display_friendly),
            ),
            selected = { it.dateFormat },
            change = { before, option -> before.copy(dateFormat = option) },
        )
        compose.runOnIdle { assertEquals(14, fixture.changes.size) }
    }

    @Test
    fun timeChoicesHaveOneLabeledRadioActionPerLabelOrIndicatorTap() {
        val fixture = showFormat()
        exerciseChoices(
            fixture, Tags.TIME,
            listOf(
                TimeFormatPreference.HOUR_24 to text(R.string.time_format_display_24h),
                TimeFormatPreference.HOUR_24_SECONDS to text(R.string.time_format_display_24h_seconds),
                TimeFormatPreference.HOUR_12 to text(R.string.time_format_display_12h),
                TimeFormatPreference.HOUR_12_SECONDS to text(R.string.time_format_display_12h_seconds),
            ),
            selected = { it.timeFormat },
            change = { before, option -> before.copy(timeFormat = option) },
        )
        compose.runOnIdle { assertEquals(8, fixture.changes.size) }
    }

    @Test
    fun templateChoicesKeepCustomTextAndExposeOnlyOneRadioAction() {
        val fixture = showFormat()
        val original = current(fixture).markdownTemplate.customTemplate
        exerciseChoices(
            fixture, Tags.TEMPLATE,
            listOf(
                MarkdownTemplateStyle.STANDARD to text(R.string.template_display_standard),
                MarkdownTemplateStyle.COMPACT to text(R.string.template_display_compact),
                MarkdownTemplateStyle.DETAILED to text(R.string.template_display_detailed),
                MarkdownTemplateStyle.CUSTOM to text(R.string.template_display_custom),
            ),
            selected = { it.markdownTemplate.style },
            change = { before, option -> before.copy(markdownTemplate = before.markdownTemplate.copy(style = option)) },
        )
        field().assertEditableText(original)
        var expected = current(fixture)
        listOf(MarkdownTemplateStyle.STANDARD, MarkdownTemplateStyle.CUSTOM).forEachIndexed { index, style ->
            choice(Tags.TEMPLATE, style).performScrollTo().assertFullyVisible().performTouchInput { click() }
            expected = expected.copy(markdownTemplate = expected.markdownTemplate.copy(style = style))
            assertChange(fixture, expected, 9 + index)
            if (style == MarkdownTemplateStyle.CUSTOM) field().assertEditableText(original)
            else field().assertDoesNotExist()
        }
    }

    @Test
    fun unitBulletAndHeaderChoicesReflowWithFullDescriptionsAndSelectedState() {
        val fixture = showFormat()
        exerciseChoices(
            fixture, Tags.UNIT,
            listOf(
                UnitPreference.METRIC to text(R.string.unit_display_metric),
                UnitPreference.IMPERIAL to text(R.string.unit_display_imperial),
            ),
            selected = { it.unitPreference },
            change = { before, option -> before.copy(unitPreference = option) },
            fontSize = GeistType.button14.fontSize,
            descriptions = mapOf(
                UnitPreference.METRIC to text(R.string.unit_desc_metric),
                UnitPreference.IMPERIAL to text(R.string.unit_desc_imperial),
            ),
            adaptive = true,
        )
        exerciseChoices(
            fixture, Tags.BULLET,
            listOf(
                BulletStyle.DASH to "${BulletStyle.DASH.symbol} ${text(R.string.bullet_display_dash)}",
                BulletStyle.ASTERISK to "${BulletStyle.ASTERISK.symbol} ${text(R.string.bullet_display_asterisk)}",
                BulletStyle.PLUS to "${BulletStyle.PLUS.symbol} ${text(R.string.bullet_display_plus)}",
            ),
            selected = { it.markdownTemplate.bulletStyle },
            change = { before, option -> before.copy(markdownTemplate = before.markdownTemplate.copy(bulletStyle = option)) },
            fontSize = GeistType.button14.fontSize,
            adaptive = true,
        )
        exerciseChoices(
            fixture, Tags.HEADER, (1..3).map { it to "${"#".repeat(it)} H$it" },
            selected = { it.markdownTemplate.sectionHeaderLevel },
            change = { before, option -> before.copy(markdownTemplate = before.markdownTemplate.copy(sectionHeaderLevel = option)) },
            fontSize = GeistType.button14.fontSize,
            adaptive = true,
        )
        compose.runOnIdle { assertEquals(16, fixture.changes.size) }
    }

    @Test
    fun optionTogglesWrapAndPreserveNativeProfileImplicationAndNavigation() {
        val fixture = showFormat(syntheticCustomization().copy(
            includeAndroidNativeFields = false,
            includeLegacyAndroidAliases = false,
            compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
        ))
        val title = compose.onNodeWithText(text(R.string.format_customization_title), useUnmergedTree = true)
        title.assertFullyVisible()
        assertTextFits(title, GeistType.heading20.fontSize)
        compose.onNodeWithTag(Tags.BACK).assertHasClickAction().assertMinimumTouchTarget().assertFullyVisible()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assertContentDescriptionEquals(text(R.string.back)).performTouchInput { click() }

        exerciseToggle(fixture, Tags.EMOJI, R.string.toggle_emoji_headers,
            checked = { it.markdownTemplate.useEmoji },
            change = { before, value -> before.copy(markdownTemplate = before.markdownTemplate.copy(useEmoji = value)) })
        exerciseToggle(fixture, Tags.SUMMARY, R.string.toggle_include_summary,
            checked = { it.markdownTemplate.includeSummary },
            change = { before, value -> before.copy(markdownTemplate = before.markdownTemplate.copy(includeSummary = value)) })
        exerciseToggle(fixture, Tags.NATIVE_FIELDS, R.string.toggle_android_native_fields,
            checked = { it.includeAndroidNativeFields },
            change = { before, value -> before.copy(
                includeAndroidNativeFields = value,
                compatibilitySchemaProfile = if (value) CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5
                    else before.compatibilitySchemaProfile,
            ) })
        compose.runOnIdle {
            assertEquals(false, fixture.state.value.includeAndroidNativeFields)
            assertEquals("Turning native fields off must not downgrade the profile",
                CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5, fixture.state.value.compatibilitySchemaProfile)
        }
        exerciseToggle(fixture, Tags.LEGACY_ALIASES, R.string.toggle_legacy_android_aliases,
            checked = { it.includeLegacyAndroidAliases },
            change = { before, value -> before.copy(includeLegacyAndroidAliases = value) })
        compose.onNodeWithTag(Tags.NATIVE_FIELDS).performScrollTo().assertFullyVisible()
        settle()
        capture("format-options")

        val entry = compose.onNodeWithTag(Tags.FRONTMATTER).performScrollTo()
            .assertMinimumTouchTarget().assertFullyVisible()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        assertNoChildActions(Tags.FRONTMATTER)
        val subtitle = compose.onNodeWithText(text(R.string.frontmatter_customization_subtitle), useUnmergedTree = true)
        subtitle.performScrollTo()
        assertTextFits(subtitle, GeistType.copy13.fontSize)
        if (GeistAdaptiveLayout.stackDetailedControls(display.width - 32f, display.fontScale)) {
            assertTrue("Frontmatter helper uses the full inner card width",
                width(subtitle) >= width(entry) - 33.dp)
        }
        val entryTitle = compose.onNodeWithText(text(R.string.frontmatter_customization_title), useUnmergedTree = true)
        entryTitle.performScrollTo().assertFullyVisible()
        assertTextFits(entryTitle, GeistType.copy16.fontSize)
        entryTitle.performTouchInput { click() }
        compose.onNodeWithTag(Tags.BACK).performScrollTo().assertFullyVisible().performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(8, fixture.changes.size)
            assertEquals(listOf("back", "frontmatter", "back"), fixture.navigation)
        }
    }

    @Test
    fun focusedTemplateEditingKeepsAllTextAndResetAndPreviewReachableInShortWindows() {
        val initial = syntheticCustomization().copy(
            markdownTemplate = syntheticCustomization().markdownTemplate.copy(
                style = MarkdownTemplateStyle.CUSTOM, customTemplate = "{{date}}",
            ),
        )
        val fixture = showFormat(initial, keyboardWindow = true)
        val field = field().performScrollTo().assertMinimumTouchTarget().assertInsideEditorWindow()
        assertTextFits(field, GeistType.copy13Mono.fontSize)
        val label = compose.onNodeWithTag(Tags.label(Tags.TEMPLATE_FIELD), useUnmergedTree = true)
        label.performScrollTo().assertInsideEditorWindow()
        assertTextFits(label, GeistType.copy16.fontSize)
        field.performScrollTo().assertInsideEditorWindow()
        assertTrue("The template must not require an eight-line editor",
            height(field) <= height(compose.onNodeWithTag(EDITOR_WINDOW)) / 2 + 1.dp)
        compose.onNodeWithTag(Tags.TEMPLATE_RESET).performScrollTo().assertInsideEditorWindow()
        settle()
        capture("format-template")

        field.performScrollTo().assertInsideEditorWindow().performTouchInput { click() }
        field.assertIsFocused()
        waitForKeyboard()
        field.performTextReplacement("Draft")
        var expected = initial.copy(markdownTemplate = initial.markdownTemplate.copy(customTemplate = "Draft"))
        assertChange(fixture, expected, 1)
        field.performScrollTo().assertInsideEditorWindow()
        assertTextFits(field, GeistType.copy13Mono.fontSize)
        field.performTextInputSelection(TextRange(5))
        field.performTextInput("\n{{date}}")
        expected = expected.copy(markdownTemplate = expected.markdownTemplate.copy(customTemplate = "Draft\n{{date}}"))
        assertChange(fixture, expected, 2)
        field.assertIsFocused().assertEditableText("Draft\n{{date}}")
        val preview = compose.onNodeWithTag(Tags.TEMPLATE_PREVIEW)
        preview.performScrollTo().assertInsideEditorWindow().assertTextEquals("Draft\n2026-03-15")
        assertTextFits(preview, GeistType.copy13Mono.fontSize)
        field.assertIsFocused()
        assertKeyboardVisible()

        val longTemplate = "# Synthetic {{date}}\n" + "α العربية 日本語 {{unknown}}\n".repeat(80)
        field.performScrollTo().performTextReplacement(longTemplate)
        expected = expected.copy(markdownTemplate = expected.markdownTemplate.copy(customTemplate = longTemplate))
        assertChange(fixture, expected, 3)
        field.assertEditableText(longTemplate).assertIsFocused()
        val reset = compose.onNodeWithTag(Tags.TEMPLATE_RESET).performScrollTo()
            .assertMinimumTouchTarget().assertInsideEditorWindow()
        val resetLabel = compose.onNode(hasText(text(R.string.custom_markdown_template_reset)) and
            hasAnyAncestor(hasTestTag(Tags.TEMPLATE_RESET)), useUnmergedTree = true)
        assertTextFits(resetLabel, GeistType.button14.fontSize)
        field.assertIsFocused()
        assertKeyboardVisible()
        reset.performTouchInput { click() }
        expected = expected.copy(markdownTemplate = expected.markdownTemplate.copy(customTemplate = MarkdownTemplateConfig.DEFAULT_TEMPLATE))
        assertChange(fixture, expected, 4)
        field.assertEditableText(MarkdownTemplateConfig.DEFAULT_TEMPLATE)
        compose.onNodeWithText(text(R.string.custom_markdown_template_preview), useUnmergedTree = true)
            .performScrollTo().assertInsideEditorWindow()

        field.performScrollTo().performTextReplacement("")
        expected = expected.copy(markdownTemplate = expected.markdownTemplate.copy(customTemplate = ""))
        assertChange(fixture, expected, 5)
        field.assertEditableText("").assertIsFocused()
        field.performScrollTo().assertInsideEditorWindow()
        assertTrue("An empty field's example must not force an oversized editor",
            height(field) <= height(compose.onNodeWithTag(EDITOR_WINDOW)) / 2 + 1.dp)
        val example = compose.onNodeWithText(text(R.string.custom_markdown_template_placeholder), useUnmergedTree = true)
            .performScrollTo()
        assertTextFits(example, GeistType.copy16.fontSize)
        preview.performScrollTo().assertInsideEditorWindow().assertTextEquals(text(R.string.custom_markdown_template_empty_preview))
        assertTextFits(preview, GeistType.copy13Mono.fontSize)
        listOf(R.string.custom_markdown_template_help, R.string.custom_markdown_template_tokens).forEach { id ->
            // Long reference paragraphs scroll; unlike controls they may span the viewport.
            val helper = compose.onNodeWithText(text(id), useUnmergedTree = true).performScrollTo()
            assertTextFits(helper, GeistType.copy13.fontSize)
            assertEquals("Reference text keeps the field's full reading width", width(field), width(helper))
        }
        compose.runOnIdle { assertEquals(5, fixture.changes.size) }
    }

    @Test
    fun previewRetainsConditionalRenderingUnknownTokensAndTheExisting1500CharacterBound() {
        val fixture = showFormat(syntheticCustomization().copy(
            markdownTemplate = MarkdownTemplateConfig(
                style = MarkdownTemplateStyle.CUSTOM,
                customTemplate = "  {{date}} {{#sleep}}kept{{/sleep}}{{#body}}omitted{{/body}} {{unknown}}  ",
            ),
        ))
        val preview = compose.onNodeWithTag(Tags.TEMPLATE_PREVIEW).performScrollTo().assertFullyVisible()
        preview.assertTextEquals("2026-03-15 kept {{unknown}}")
        assertTextFits(preview, GeistType.copy13Mono.fontSize)
        val longTemplate = "x".repeat(1_511)
        compose.runOnIdle {
            fixture.state.value = fixture.state.value.copy(
                markdownTemplate = fixture.state.value.markdownTemplate.copy(customTemplate = longTemplate),
            )
        }
        field().assertEditableText(longTemplate)
        preview.performScrollTo().assertTextEquals("x".repeat(1_500))
        assertTextFits(preview, GeistType.copy13Mono.fontSize)
        compose.runOnIdle { assertTrue("Rendering is not an edit callback", fixture.changes.isEmpty()) }
    }

    private class Fixture(initial: FormatCustomization) {
        val state = mutableStateOf(initial)
        val changes = mutableListOf<FormatCustomization>()
        val navigation = mutableListOf<String>()
    }

    private fun syntheticCustomization() = FormatCustomization(
        dateFormat = DateFormatPreference.FRIENDLY,
        timeFormat = TimeFormatPreference.HOUR_12_SECONDS,
        unitPreference = UnitPreference.IMPERIAL,
        includeAndroidNativeFields = true,
        includeLegacyAndroidAliases = true,
        compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
        markdownTemplate = MarkdownTemplateConfig(
            style = MarkdownTemplateStyle.COMPACT,
            customTemplate = "# Synthetic {{date}}\n{{unknown}}",
            sectionHeaderLevel = 3, useEmoji = true, includeSummary = false, bulletStyle = BulletStyle.PLUS,
        ),
    )

    @OptIn(ExperimentalLayoutApi::class)
    private fun showFormat(
        initial: FormatCustomization = syntheticCustomization(),
        keyboardWindow: Boolean = false,
    ): Fixture {
        val fixture = Fixture(initial)
        setContent {
            // Native IME pixels belong to the physical portrait owner, not the fitted dp
            // viewport. Model a remaining-height budget once, without double-subtracting
            // those pixels from a synthetic landscape window. The actual field still opens
            // the real IME below and must retain focus throughout text input and scrolling.
            val window = if (keyboardWindow) Modifier.fillMaxWidth()
                .height(display.height.dp - GeistSizes.minimumTouchTarget * 2)
                .consumeWindowInsets(WindowInsets.ime).testTag(EDITOR_WINDOW)
            else Modifier.fillMaxSize()
            Box(window) {
                FormatCustomizationScreen(
                    customization = fixture.state.value,
                    onCustomizationChanged = { fixture.changes += it; fixture.state.value = it },
                    onNavigateToFrontmatter = { fixture.navigation += "frontmatter" },
                    onBack = { fixture.navigation += "back" },
                )
            }
        }
        return fixture
    }

    private fun <T : Any> exerciseChoices(
        fixture: Fixture,
        group: String,
        options: List<Pair<T, String>>,
        selected: (FormatCustomization) -> T,
        change: (FormatCustomization, T) -> FormatCustomization,
        fontSize: TextUnit = GeistType.copy16.fontSize,
        descriptions: Map<T, String> = emptyMap(),
        adaptive: Boolean = false,
    ) {
        compose.onNodeWithTag(group).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.SelectableGroup))
        compose.onAllNodes(hasAnyAncestor(hasTestTag(group)) and isSelectable(), useUnmergedTree = true)
            .assertCountEquals(options.size)
        var callbackCount = compose.runOnIdle { fixture.changes.size }
        options.forEach { (option, label) ->
            val tag = Tags.choice(group, option)
            val row = compose.onNodeWithTag(tag).performScrollTo().assertMinimumTouchTarget().assertFullyVisible()
                .assertHasClickAction().assertTextContains(label)
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton))
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, selected(current(fixture)) == option))
            assertNoChildActions(tag)
            val labelNode = compose.onNodeWithTag(Tags.label(tag), useUnmergedTree = true)
            labelNode.assertTextEquals(label)
            assertTextFits(labelNode, fontSize)
            val indicator = compose.onNodeWithTag(Tags.indicator(tag), useUnmergedTree = true)
            assertTrue("Labels receive all space not used by the indicator and token padding",
                width(labelNode) >= width(row) - width(indicator) - 25.dp)
            descriptions[option]?.let { description ->
                val helper = compose.onNodeWithTag(Tags.description(tag), useUnmergedTree = true)
                helper.assertTextEquals(description)
                assertTextFits(helper, GeistType.copy13.fontSize)
                assertTrue("Descriptions are not narrowed beside a radio", width(helper) >= width(row) - 17.dp)
            }
            if (adaptive && GeistAdaptiveLayout.stackDetailedControls(display.width - 64f, display.fontScale)) {
                assertEquals("Crowded choices reflow to the full group width",
                    width(compose.onNodeWithTag(group)), width(row))
            }
            listOf(labelNode, indicator).forEach { target ->
                val expected = change(current(fixture), option)
                row.performScrollTo().assertFullyVisible()
                target.performTouchInput { click() }
                assertChange(fixture, expected, ++callbackCount)
                row.assertIsSelected()
                options.forEach { (other, _) ->
                    choice(group, other).assert(
                        SemanticsMatcher.expectValue(SemanticsProperties.Selected, other == option),
                    )
                }
            }
        }
    }

    private fun exerciseToggle(
        fixture: Fixture,
        tag: String,
        labelId: Int,
        checked: (FormatCustomization) -> Boolean,
        change: (FormatCustomization, Boolean) -> FormatCustomization,
    ) {
        val row = compose.onNodeWithTag(tag).performScrollTo().assertFullyVisible().assertMinimumTouchTarget()
            .assertHasClickAction().assertTextContains(text(labelId))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
        assertNoChildActions(tag)
        val label = compose.onNodeWithTag(Tags.label(tag), useUnmergedTree = true)
        assertTextFits(label, GeistType.copy16.fontSize)
        if (GeistAdaptiveLayout.stackDetailedControls(display.width - 64f, display.fontScale)) {
            assertEquals("Long toggle labels retain full reading width", width(row), width(label))
        }
        listOf(label, compose.onNodeWithTag(Tags.indicator(tag), useUnmergedTree = true)).forEach { target ->
            val before = current(fixture)
            val count = compose.runOnIdle { fixture.changes.size }
            if (checked(before)) row.assertIsOn() else row.assertIsOff()
            row.performScrollTo().assertFullyVisible()
            target.performTouchInput { click() }
            assertChange(fixture, change(before, !checked(before)), count + 1)
            if (checked(before)) row.assertIsOff() else row.assertIsOn()
        }
    }

    private fun assertNoChildActions(tag: String) {
        compose.onAllNodes(hasClickAction() and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
            .assertCountEquals(0)
    }

    private fun current(fixture: Fixture) = compose.runOnIdle { fixture.state.value }

    private fun assertChange(fixture: Fixture, expected: FormatCustomization, count: Int) {
        compose.runOnIdle {
            assertEquals("Exactly one customization callback per edit/tap", count, fixture.changes.size)
            assertEquals("The callback must preserve every unrelated field", expected, fixture.changes.last())
            assertEquals(expected, fixture.state.value)
        }
    }

    private fun field() = compose.onNodeWithTag(Tags.TEMPLATE_FIELD)
    private fun choice(group: String, value: Any) = compose.onNodeWithTag(Tags.choice(group, value))
    private fun width(node: SemanticsNodeInteraction) = node.getUnclippedBoundsInRoot().let { it.right - it.left }
    private fun height(node: SemanticsNodeInteraction) = node.getUnclippedBoundsInRoot().let { it.bottom - it.top }

    private fun SemanticsNodeInteraction.assertEditableText(value: String) =
        assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(value)))

    private fun SemanticsNodeInteraction.assertInsideEditorWindow(): SemanticsNodeInteraction {
        assertFullyVisible()
        val bounds = getUnclippedBoundsInRoot()
        val window = compose.onNodeWithTag(EDITOR_WINDOW).getUnclippedBoundsInRoot()
        assertTrue("Control must fit the keyboard-resized window, not merely the original viewport",
            bounds.top >= window.top - 1.dp && bounds.bottom <= window.bottom + 1.dp &&
                bounds.left >= window.left - 1.dp && bounds.right <= window.right + 1.dp)
        return this
    }

    private fun waitForKeyboard() {
        compose.waitUntil(timeoutMillis = 10_000) { keyboardVisible() }
        compose.waitForIdle()
    }

    private fun keyboardVisible() = ViewCompat.getRootWindowInsets(compose.activity.window.decorView)
        ?.isVisible(WindowInsetsCompat.Type.ime()) == true

    private fun assertKeyboardVisible() {
        compose.runOnIdle { assertTrue("Exercise editing with the real IME visible", keyboardVisible()) }
    }

    private fun settle() {
        compose.mainClock.advanceTimeBy(1_000)
        compose.waitForIdle()
    }
}
