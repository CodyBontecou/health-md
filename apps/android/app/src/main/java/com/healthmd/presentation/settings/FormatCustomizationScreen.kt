package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Dataset
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import com.healthmd.R
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.*
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
    BoxWithConstraints(Modifier.fillMaxSize().background(AppColors.bgPrimary).imePadding()) {
        // Allocate space, never change the font size/scale. The editor scrolls internally
        // after at most half the available height, including when the IME is showing.
        val lineHeight = with(LocalDensity.current) { MaterialTheme.typography.bodySmall.lineHeight.toDp() }
        val editorMaxLines = ((maxHeight / 2 - Spacing.md * 2) / lineHeight).toInt().coerceIn(1, 16)
        Column(
            modifier = Modifier.fillMaxSize().testTag(FormatCustomizationTags.SCROLL)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.md, vertical = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier.size(GeistSizes.minimumTouchTarget).testTag(FormatCustomizationTags.BACK),
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
                }
                Text(
                    stringResource(R.string.format_customization_title),
                    style = MaterialTheme.typography.titleLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.section_date_format))
                Column(Modifier.selectableGroup().testTag(FormatCustomizationTags.DATE)) {
                    DateFormatPreference.entries.forEach { format ->
                        FormatCustomizationChoice(
                            label = format.localizedDisplayName(), selected = customization.dateFormat == format,
                            onClick = { onCustomizationChanged(customization.copy(dateFormat = format)) },
                            tag = FormatCustomizationTags.choice(FormatCustomizationTags.DATE, format),
                        )
                    }
                }
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.section_time_format))
                Column(Modifier.selectableGroup().testTag(FormatCustomizationTags.TIME)) {
                    TimeFormatPreference.entries.forEach { format ->
                        FormatCustomizationChoice(
                            label = format.localizedDisplayName(), selected = customization.timeFormat == format,
                            onClick = { onCustomizationChanged(customization.copy(timeFormat = format)) },
                            tag = FormatCustomizationTags.choice(FormatCustomizationTags.TIME, format),
                        )
                    }
                }
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.section_unit_system))
                FormatCustomizationChoices(
                    options = UnitPreference.entries, selected = customization.unitPreference,
                    onSelected = { pref -> onCustomizationChanged(customization.copy(unitPreference = pref)) },
                    group = FormatCustomizationTags.UNIT,
                    label = { it.localizedDisplayName() }, description = { it.localizedDescription() },
                )
            }

            SettingsNavigationCard(
                title = stringResource(R.string.frontmatter_customization_title),
                subtitle = stringResource(R.string.frontmatter_customization_subtitle),
                icon = Icons.Outlined.Dataset,
                onClick = onNavigateToFrontmatter,
                modifier = Modifier.testTag(FormatCustomizationTags.FRONTMATTER),
            )

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.section_markdown_template))
                Column(Modifier.selectableGroup().testTag(FormatCustomizationTags.TEMPLATE)) {
                    MarkdownTemplateStyle.entries.forEach { style ->
                        FormatCustomizationChoice(
                            label = style.localizedDisplayName(),
                            selected = customization.markdownTemplate.style == style,
                            onClick = {
                                onCustomizationChanged(
                                    customization.copy(markdownTemplate = customization.markdownTemplate.copy(style = style))
                                )
                            },
                            tag = FormatCustomizationTags.choice(FormatCustomizationTags.TEMPLATE, style),
                        )
                    }
                }

                if (customization.markdownTemplate.style == MarkdownTemplateStyle.CUSTOM) {
                    FormatCustomizationTemplateEditor(
                        template = customization.markdownTemplate.customTemplate,
                        maxLines = editorMaxLines,
                        onTemplateChanged = { template ->
                            onCustomizationChanged(
                                customization.copy(
                                    markdownTemplate = customization.markdownTemplate.copy(customTemplate = template),
                                )
                            )
                        },
                        onReset = {
                            onCustomizationChanged(
                                customization.copy(
                                    markdownTemplate = customization.markdownTemplate.copy(
                                        customTemplate = MarkdownTemplateConfig.DEFAULT_TEMPLATE,
                                    ),
                                )
                            )
                        },
                    )
                }
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.section_bullet_style))
                FormatCustomizationChoices(
                    options = BulletStyle.entries, selected = customization.markdownTemplate.bulletStyle,
                    onSelected = { style ->
                        onCustomizationChanged(
                            customization.copy(markdownTemplate = customization.markdownTemplate.copy(bulletStyle = style))
                        )
                    },
                    group = FormatCustomizationTags.BULLET,
                    label = { "${it.symbol} ${it.localizedDisplayName()}" },
                )
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.section_header_level))
                FormatCustomizationChoices(
                    options = (1..3).toList(), selected = customization.markdownTemplate.sectionHeaderLevel,
                    onSelected = { level ->
                        onCustomizationChanged(
                            customization.copy(markdownTemplate = customization.markdownTemplate.copy(sectionHeaderLevel = level))
                        )
                    },
                    group = FormatCustomizationTags.HEADER,
                    label = { "${"#".repeat(it)} H$it" },
                )
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.section_options))
                FormatCustomizationToggle(
                    stringResource(R.string.toggle_emoji_headers), customization.markdownTemplate.useEmoji,
                    FormatCustomizationTags.EMOJI,
                ) {
                    onCustomizationChanged(
                        customization.copy(markdownTemplate = customization.markdownTemplate.copy(useEmoji = it))
                    )
                }
                FormatCustomizationToggle(
                    stringResource(R.string.toggle_include_summary), customization.markdownTemplate.includeSummary,
                    FormatCustomizationTags.SUMMARY,
                ) {
                    onCustomizationChanged(
                        customization.copy(markdownTemplate = customization.markdownTemplate.copy(includeSummary = it))
                    )
                }
                FormatCustomizationToggle(
                    stringResource(R.string.toggle_android_native_fields), customization.includeAndroidNativeFields,
                    FormatCustomizationTags.NATIVE_FIELDS,
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
                FormatCustomizationToggle(
                    stringResource(R.string.toggle_legacy_android_aliases), customization.includeLegacyAndroidAliases,
                    FormatCustomizationTags.LEGACY_ALIASES,
                ) {
                    onCustomizationChanged(customization.copy(includeLegacyAndroidAliases = it))
                }
            }

            Spacer(modifier = Modifier.height(Spacing.xl))
        }
    }
}

@Composable
private fun FormatCustomizationTemplateEditor(
    template: String,
    maxLines: Int,
    onTemplateChanged: (String) -> Unit,
    onReset: () -> Unit,
) {
    Spacer(modifier = Modifier.height(Spacing.sm))
    Text(
        text = stringResource(R.string.custom_markdown_template_help),
        color = AppColors.textSecondary,
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(modifier = Modifier.height(Spacing.sm))
    val label = stringResource(R.string.custom_markdown_template_label)
    // An external label can wrap without being shrunk into an outlined field's floating label.
    Text(label, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
        modifier = Modifier.fillMaxWidth().testTag(FormatCustomizationTags.label(FormatCustomizationTags.TEMPLATE_FIELD)))
    Spacer(modifier = Modifier.height(Spacing.xs))
    if (template.isEmpty()) {
        // Keep the full multiline example outside the bounded editor too. A placeholder
        // paragraph must not force an empty field to grow beyond the keyboard window.
        Text(
            stringResource(R.string.custom_markdown_template_placeholder),
            style = MaterialTheme.typography.bodyLarge.copy(fontFamily = GeistMono),
            color = AppColors.textSecondary,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(modifier = Modifier.height(Spacing.xs))
    }
    OutlinedTextField(
        value = template,
        onValueChange = onTemplateChanged,
        modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
            .testTag(FormatCustomizationTags.TEMPLATE_FIELD).semantics { contentDescription = label },
        minLines = 1,
        maxLines = maxLines,
        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMono),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = AppColors.accent,
            unfocusedBorderColor = AppColors.borderDefault,
            focusedTextColor = AppColors.textPrimary,
            unfocusedTextColor = AppColors.textPrimary,
            cursorColor = AppColors.accent,
        ),
        shape = RoundedCornerShape(Radii.card),
    )
    Spacer(modifier = Modifier.height(Spacing.xs))
    // Keep reset immediately after the editor, rather than beyond a long token reference.
    SecondaryButton(
        text = stringResource(R.string.custom_markdown_template_reset),
        onClick = onReset,
        modifier = Modifier.fillMaxWidth().testTag(FormatCustomizationTags.TEMPLATE_RESET),
    )
    Spacer(modifier = Modifier.height(Spacing.sm))
    GeistCard(padding = Spacing.md) {
        SectionLabel(stringResource(R.string.custom_markdown_template_preview))
        Text(
            text = renderCustomTemplatePreview(
                template = template,
                emptyPreview = stringResource(R.string.custom_markdown_template_empty_preview),
            ),
            color = AppColors.textSecondary,
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMono),
            modifier = Modifier.fillMaxWidth().testTag(FormatCustomizationTags.TEMPLATE_PREVIEW),
        )
    }
    Spacer(modifier = Modifier.height(Spacing.sm))
    Text(
        text = stringResource(R.string.custom_markdown_template_tokens),
        color = AppColors.textSecondary,
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.fillMaxWidth(),
    )
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
