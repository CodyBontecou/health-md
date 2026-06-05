package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Dataset
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.*
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.stringResource
import com.healthmd.R

@Composable
fun FormatCustomizationScreen(
    customization: FormatCustomization,
    onCustomizationChanged: (FormatCustomization) -> Unit,
    onNavigateToFrontmatter: () -> Unit = {},
    onBack: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        // Top bar
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
            }
            Text(
                stringResource(R.string.format_customization_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        // Date Format
        GlassCard {
            SectionLabel(stringResource(R.string.section_date_format))
            DateFormatPreference.entries.forEach { format ->
                val selected = customization.dateFormat == format
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (selected) AppColors.accent.copy(alpha = 0.08f) else Color.Transparent)
                        .clickable { onCustomizationChanged(customization.copy(dateFormat = format)) }
                        .padding(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selected,
                        onClick = { onCustomizationChanged(customization.copy(dateFormat = format)) },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = AppColors.accent,
                            unselectedColor = AppColors.textMuted,
                        ),
                    )
                    Text(
                        format.localizedDisplayName(),
                        color = if (selected) AppColors.textPrimary else AppColors.textSecondary,
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.padding(start = Spacing.xs),
                    )
                }
            }
        }

        // Time Format
        GlassCard {
            SectionLabel(stringResource(R.string.section_time_format))
            TimeFormatPreference.entries.forEach { format ->
                val selected = customization.timeFormat == format
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (selected) AppColors.accent.copy(alpha = 0.08f) else Color.Transparent)
                        .clickable { onCustomizationChanged(customization.copy(timeFormat = format)) }
                        .padding(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selected,
                        onClick = { onCustomizationChanged(customization.copy(timeFormat = format)) },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = AppColors.accent,
                            unselectedColor = AppColors.textMuted,
                        ),
                    )
                    Text(
                        format.localizedDisplayName(),
                        color = if (selected) AppColors.textPrimary else AppColors.textSecondary,
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.padding(start = Spacing.xs),
                    )
                }
            }
        }

        // Unit System
        GlassCard {
            SectionLabel(stringResource(R.string.section_unit_system))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                UnitPreference.entries.forEach { pref ->
                    val selected = customization.unitPreference == pref
                    val shape = RoundedCornerShape(100.dp)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(shape)
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                            .border(1.dp, if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder, shape)
                            .clickable { onCustomizationChanged(customization.copy(unitPreference = pref)) }
                            .padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                pref.localizedDisplayName(),
                                color = if (selected) AppColors.accent else AppColors.textSecondary,
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            )
                            Text(
                                pref.localizedDescription(),
                                color = AppColors.textMuted,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }
            }
        }

        GlassCardClickable(onClick = onNavigateToFrontmatter) {
            Icon(
                Icons.Outlined.Dataset,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.frontmatter_customization_title),
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    stringResource(R.string.frontmatter_customization_subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = AppColors.textMuted)
        }

        // Markdown Template
        GlassCard {
            SectionLabel(stringResource(R.string.section_markdown_template))
            MarkdownTemplateStyle.entries.forEach { style ->
                val selected = customization.markdownTemplate.style == style
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (selected) AppColors.accent.copy(alpha = 0.08f) else Color.Transparent)
                        .clickable {
                            onCustomizationChanged(
                                customization.copy(markdownTemplate = customization.markdownTemplate.copy(style = style))
                            )
                        }
                        .padding(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selected,
                        onClick = {
                            onCustomizationChanged(
                                customization.copy(markdownTemplate = customization.markdownTemplate.copy(style = style))
                            )
                        },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = AppColors.accent,
                            unselectedColor = AppColors.textMuted,
                        ),
                    )
                    Text(
                        style.localizedDisplayName(),
                        color = if (selected) AppColors.textPrimary else AppColors.textSecondary,
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.padding(start = Spacing.xs),
                    )
                }
            }

            if (customization.markdownTemplate.style == MarkdownTemplateStyle.CUSTOM) {
                CustomTemplateEditor(
                    template = customization.markdownTemplate.customTemplate,
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

        // Bullet Style
        GlassCard {
            SectionLabel(stringResource(R.string.section_bullet_style))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                BulletStyle.entries.forEach { style ->
                    val selected = customization.markdownTemplate.bulletStyle == style
                    val shape = RoundedCornerShape(100.dp)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(shape)
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                            .border(1.dp, if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder, shape)
                            .clickable {
                                onCustomizationChanged(
                                    customization.copy(markdownTemplate = customization.markdownTemplate.copy(bulletStyle = style))
                                )
                            }
                            .padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "${style.symbol} ${style.localizedDisplayName()}",
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }

        // Header Level
        GlassCard {
            SectionLabel(stringResource(R.string.section_header_level))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                (1..3).forEach { level ->
                    val selected = customization.markdownTemplate.sectionHeaderLevel == level
                    val shape = RoundedCornerShape(100.dp)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(shape)
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                            .border(1.dp, if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder, shape)
                            .clickable {
                                onCustomizationChanged(
                                    customization.copy(markdownTemplate = customization.markdownTemplate.copy(sectionHeaderLevel = level))
                                )
                            }
                            .padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "${"#".repeat(level)} H$level",
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }

        // Toggles
        GlassCard {
            SectionLabel(stringResource(R.string.section_options))
            SettingsToggle(stringResource(R.string.toggle_emoji_headers), customization.markdownTemplate.useEmoji) {
                onCustomizationChanged(
                    customization.copy(markdownTemplate = customization.markdownTemplate.copy(useEmoji = it))
                )
            }
            SettingsToggle(stringResource(R.string.toggle_include_summary), customization.markdownTemplate.includeSummary) {
                onCustomizationChanged(
                    customization.copy(markdownTemplate = customization.markdownTemplate.copy(includeSummary = it))
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

@Composable
private fun CustomTemplateEditor(
    template: String,
    onTemplateChanged: (String) -> Unit,
    onReset: () -> Unit,
) {
    Spacer(modifier = Modifier.height(Spacing.sm))
    Text(
        text = stringResource(R.string.custom_markdown_template_help),
        color = AppColors.textMuted,
        style = MaterialTheme.typography.bodySmall,
    )
    Spacer(modifier = Modifier.height(Spacing.sm))
    OutlinedTextField(
        value = template,
        onValueChange = onTemplateChanged,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 180.dp),
        label = { Text(stringResource(R.string.custom_markdown_template_label)) },
        placeholder = { Text(stringResource(R.string.custom_markdown_template_placeholder)) },
        minLines = 8,
        maxLines = 16,
        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = AppColors.accent,
            unfocusedBorderColor = AppColors.borderDefault,
            focusedTextColor = AppColors.textPrimary,
            unfocusedTextColor = AppColors.textPrimary,
            cursorColor = AppColors.accent,
        ),
        shape = RoundedCornerShape(12.dp),
    )
    Spacer(modifier = Modifier.height(Spacing.xs))
    Text(
        text = stringResource(R.string.custom_markdown_template_tokens),
        color = AppColors.textMuted,
        style = MaterialTheme.typography.bodySmall,
    )
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
    ) {
        TextButton(onClick = onReset) {
            Text(stringResource(R.string.custom_markdown_template_reset), color = AppColors.accent)
        }
    }
    GlassCard(padding = Spacing.md) {
        SectionLabel(stringResource(R.string.custom_markdown_template_preview))
        Text(
            text = renderCustomTemplatePreview(template),
            color = AppColors.textSecondary,
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        )
    }
}

private fun renderCustomTemplatePreview(template: String): String {
    var rendered = template
    val sampleSections = setOf("sleep", "activity", "heart", "workouts")
    val allSections = listOf(
        "sleep", "activity", "heart", "vitals", "body", "nutrition", "mobility",
        "reproductive_health", "mindfulness", "workouts",
    )
    for (section in allSections) {
        val pattern = Regex("\\{\\{#$section}}(.*?)\\{\\{/$section}}", RegexOption.DOT_MATCHES_ALL)
        rendered = if (section in sampleSections) {
            pattern.replace(rendered) { it.groupValues[1] }
        } else {
            pattern.replace(rendered, "")
        }
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
    return rendered.trim().ifBlank { "(empty preview)" }.take(1_500)
}

@Composable
private fun SettingsToggle(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = Spacing.xs),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = AppColors.accent,
                uncheckedThumbColor = AppColors.textMuted,
                uncheckedTrackColor = AppColors.bgSecondary,
                uncheckedBorderColor = AppColors.borderDefault,
            ),
        )
    }
}
