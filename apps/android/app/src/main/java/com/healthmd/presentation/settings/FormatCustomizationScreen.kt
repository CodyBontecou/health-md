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
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
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
