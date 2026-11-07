package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dataset
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.healthmd.R
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreenTopBar
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.*

@Composable
fun FormatCustomizationScreen(
    customization: FormatCustomization,
    onCustomizationChanged: (FormatCustomization) -> Unit,
    onNavigateToFrontmatter: () -> Unit = {},
    onBack: () -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize().imePadding(), contentAlignment = Alignment.TopCenter) {
        // Allocate space, never change the font size/scale. The editor scrolls internally
        // after at most half the available height, including when the IME is showing.
        val lineHeight = with(LocalDensity.current) { GeistType.copy13Mono.lineHeight.toDp() }
        val editorMaxLines = ((maxHeight / 2 - GeistSpacing.space4 * 2) / lineHeight).toInt().coerceIn(1, 16)
        Column(
            modifier = Modifier.widthIn(max = GeistSizes.readableContentMaxWidth).fillMaxSize()
                .testTag(FormatCustomizationTags.SCROLL)
                .verticalScroll(rememberScrollState()),
        ) {
            // Back joins the editor's scroll surface rather than consuming scarce fixed height.
            SubScreenTopBar(title = stringResource(R.string.format_customization_title), onBack = onBack, backButtonModifier = Modifier.testTag(FormatCustomizationTags.BACK))
            Column(
                Modifier.fillMaxWidth().padding(
                    start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8,
                ),
            ) {
                FormatCustomizationBody(customization, onCustomizationChanged, onNavigateToFrontmatter, editorMaxLines)
            }
        }
    }
}

@Composable
private fun FormatCustomizationBody(
    customization: FormatCustomization,
    onCustomizationChanged: (FormatCustomization) -> Unit,
    onNavigateToFrontmatter: () -> Unit,
    editorMaxLines: Int,
) {
    val template = customization.markdownTemplate
    fun updateTemplate(transform: (MarkdownTemplateConfig) -> MarkdownTemplateConfig) =
        onCustomizationChanged(customization.copy(markdownTemplate = transform(customization.markdownTemplate)))

    FormatCustomizationChoiceGroup(
        title = stringResource(R.string.section_date_format),
        options = DateFormatPreference.entries, selected = customization.dateFormat,
        onSelected = { onCustomizationChanged(customization.copy(dateFormat = it)) },
        group = FormatCustomizationTags.DATE, label = { it.localizedDisplayName() },
    )
    FormatCustomizationChoiceGroup(
        title = stringResource(R.string.section_time_format),
        options = TimeFormatPreference.entries, selected = customization.timeFormat,
        onSelected = { onCustomizationChanged(customization.copy(timeFormat = it)) },
        group = FormatCustomizationTags.TIME, label = { it.localizedDisplayName() },
    )
    FormatCustomizationChoices(
        title = stringResource(R.string.section_unit_system),
        options = UnitPreference.entries, selected = customization.unitPreference,
        onSelected = { pref -> onCustomizationChanged(customization.copy(unitPreference = pref)) },
        group = FormatCustomizationTags.UNIT,
        label = { it.localizedDisplayName() }, description = { it.localizedDescription() },
    )

    Spacer(Modifier.height(GeistSpacing.space6))
    SettingsNavigationCard(
        title = stringResource(R.string.frontmatter_customization_title),
        subtitle = stringResource(R.string.frontmatter_customization_subtitle),
        icon = Icons.Outlined.Dataset,
        onClick = onNavigateToFrontmatter,
        modifier = Modifier.testTag(FormatCustomizationTags.FRONTMATTER),
    )

    val editor: List<@Composable (Shape) -> Unit> = if (template.style == MarkdownTemplateStyle.CUSTOM) {
        listOf { shape ->
            FormatCustomizationTemplateEditor(
                template = template.customTemplate,
                maxLines = editorMaxLines,
                shape = shape,
                onTemplateChanged = { text -> updateTemplate { it.copy(customTemplate = text) } },
                onReset = { updateTemplate { it.copy(customTemplate = MarkdownTemplateConfig.DEFAULT_TEMPLATE) } },
            )
        }
    } else {
        emptyList()
    }
    FormatCustomizationChoiceGroup(
        title = stringResource(R.string.section_markdown_template),
        options = MarkdownTemplateStyle.entries, selected = template.style,
        onSelected = { style -> updateTemplate { it.copy(style = style) } },
        group = FormatCustomizationTags.TEMPLATE, label = { it.localizedDisplayName() },
        extra = editor,
    )

    FormatCustomizationChoices(
        title = stringResource(R.string.section_bullet_style),
        options = BulletStyle.entries, selected = template.bulletStyle,
        onSelected = { style -> updateTemplate { it.copy(bulletStyle = style) } },
        group = FormatCustomizationTags.BULLET,
        label = { "${it.symbol} ${it.localizedDisplayName()}" },
    )
    FormatCustomizationChoices(
        title = stringResource(R.string.section_header_level),
        options = (1..3).toList(), selected = template.sectionHeaderLevel,
        onSelected = { level -> updateTemplate { it.copy(sectionHeaderLevel = level) } },
        group = FormatCustomizationTags.HEADER,
        label = { "${"#".repeat(it)} H$it" },
    )

    val emoji = stringResource(R.string.toggle_emoji_headers)
    val summary = stringResource(R.string.toggle_include_summary)
    val nativeFields = stringResource(R.string.toggle_android_native_fields)
    val legacyAliases = stringResource(R.string.toggle_legacy_android_aliases)
    SettingsGroup(
        title = stringResource(R.string.section_options),
        rows = listOf(
            { shape ->
                FormatCustomizationToggle(emoji, template.useEmoji, FormatCustomizationTags.EMOJI, shape) { value ->
                    updateTemplate { it.copy(useEmoji = value) }
                }
            },
            { shape ->
                FormatCustomizationToggle(summary, template.includeSummary, FormatCustomizationTags.SUMMARY, shape) { value ->
                    updateTemplate { it.copy(includeSummary = value) }
                }
            },
            { shape ->
                FormatCustomizationToggle(
                    nativeFields, customization.includeAndroidNativeFields, FormatCustomizationTags.NATIVE_FIELDS, shape,
                ) {
                    onCustomizationChanged(
                        customization.copy(
                            includeAndroidNativeFields = it,
                            compatibilitySchemaProfile = if (it) {
                                CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5
                            } else {
                                customization.compatibilitySchemaProfile
                            },
                        )
                    )
                }
            },
            { shape ->
                FormatCustomizationToggle(
                    legacyAliases, customization.includeLegacyAndroidAliases, FormatCustomizationTags.LEGACY_ALIASES, shape,
                ) {
                    onCustomizationChanged(customization.copy(includeLegacyAndroidAliases = it))
                }
            },
        ),
    )
}

/** The custom template editor: one tonal list-group row that follows the template choices. */
@Composable
private fun FormatCustomizationTemplateEditor(
    template: String,
    maxLines: Int,
    shape: Shape,
    onTemplateChanged: (String) -> Unit,
    onReset: () -> Unit,
) {
    val colors = LocalGeistColors.current
    Column(
        Modifier.fillMaxWidth().clip(shape).background(colors.background200).padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Text(
            text = stringResource(R.string.custom_markdown_template_help),
            color = colors.secondary,
            style = GeistType.copy13,
            modifier = Modifier.fillMaxWidth(),
        )
        val label = stringResource(R.string.custom_markdown_template_label)
        // An external label can wrap without being shrunk into an outlined field's floating label.
        Text(
            label, style = GeistType.label16, color = colors.primary,
            modifier = Modifier.fillMaxWidth().padding(top = GeistSpacing.space2)
                .testTag(FormatCustomizationTags.label(FormatCustomizationTags.TEMPLATE_FIELD)),
        )
        if (template.isEmpty()) {
            // Keep the full multiline example outside the bounded editor too. A placeholder
            // paragraph must not force an empty field to grow beyond the keyboard window.
            Text(
                stringResource(R.string.custom_markdown_template_placeholder),
                style = GeistType.copy14Mono,
                color = colors.secondary,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        OutlinedTextField(
            value = template,
            onValueChange = onTemplateChanged,
            modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                .testTag(FormatCustomizationTags.TEMPLATE_FIELD).semantics { contentDescription = label },
            minLines = 1,
            maxLines = maxLines,
            textStyle = GeistType.copy13Mono,
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.brandPrimary,
                unfocusedBorderColor = colors.gray.c700,
                focusedTextColor = colors.primary,
                unfocusedTextColor = colors.primary,
                cursorColor = colors.brandPrimary,
            ),
            shape = RoundedCornerShape(GeistRadii.extraSmall),
        )
        // Keep reset immediately after the editor, rather than beyond a long token reference.
        SecondaryButton(
            text = stringResource(R.string.custom_markdown_template_reset),
            onClick = onReset,
            modifier = Modifier.fillMaxWidth().testTag(FormatCustomizationTags.TEMPLATE_RESET),
        )
        Column(
            Modifier.fillMaxWidth().padding(top = GeistSpacing.space2)
                .clip(RoundedCornerShape(GeistRadii.medium)).background(colors.gray.c200)
                .padding(GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            Text(
                stringResource(R.string.custom_markdown_template_preview),
                style = GeistType.label14, color = colors.secondary,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = renderCustomTemplatePreview(
                    template = template,
                    emptyPreview = stringResource(R.string.custom_markdown_template_empty_preview),
                ),
                color = colors.primary,
                style = GeistType.copy13Mono,
                modifier = Modifier.fillMaxWidth().testTag(FormatCustomizationTags.TEMPLATE_PREVIEW),
            )
        }
        Text(
            text = stringResource(R.string.custom_markdown_template_tokens),
            color = colors.secondary,
            style = GeistType.copy13,
            modifier = Modifier.fillMaxWidth().padding(top = GeistSpacing.space2),
        )
    }
}

private fun renderCustomTemplatePreview(template: String, emptyPreview: String): String {
    var rendered = template
    val sampleSections = setOf("sleep", "activity", "heart", "workouts")
    val allSections = listOf(
        "sleep", "activity", "heart", "vitals", "body", "nutrition", "mobility",
        "reproductive_health", "mindfulness", "workouts",
    )
    for (section in allSections) {
        rendered = applyMarkdownConditionalSection(
            template = rendered,
            section = section,
            include = section in sampleSections,
        )
    }

    val sampleMetrics = """
        ## Sleep
        - **Total:** 7h 30m
        - **REM:** 2h

        ## Activity
        - **Steps:** 8,500
        - **Active Calories:** 350 kcal

        ## Heart
        - **Average HR:** 72 bpm
    """.trimIndent()

    val replacements = mapOf(
        "date" to "2026-03-15",
        "sleep_metrics" to "- **Total:** 7h 30m\n- **Deep:** 1h 30m\n",
        "activity_metrics" to "- **Steps:** 8,500\n- **Active Calories:** 350 kcal\n",
        "heart_metrics" to "- **Average HR:** 72 bpm\n- **HRV:** 42 ms\n",
        "vitals_metrics" to "- **Respiratory Rate:** 15 breaths/min\n",
        "body_metrics" to "- **Weight:** 75.0 kg\n",
        "nutrition_metrics" to "- **Protein:** 120.0 g\n",
        "mobility_metrics" to "- **VO2 Max:** 42.5 mL/kg/min\n",
        "reproductive_health_metrics" to "",
        "mindfulness_metrics" to "- **Mindful Minutes:** 15 min\n",
        "workout_list" to "- **Running** — 30m (at 06:30) — 5.00 km\n",
        "metrics" to sampleMetrics,
    )
    for ((key, value) in replacements) {
        rendered = rendered.replace("{{$key}}", value)
    }
    return rendered.trim().ifBlank { emptyPreview }.take(1_500)
}
