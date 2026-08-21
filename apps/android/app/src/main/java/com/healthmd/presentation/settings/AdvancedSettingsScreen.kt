package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForwardIos
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.*
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import com.healthmd.R

@Composable
fun AdvancedSettingsScreen(
    settings: ExportSettings,
    sleepDayAttribution: SleepDayAttribution,
    onNavigateToMetrics: () -> Unit,
    onNavigateToFormatCustomization: () -> Unit,
    onNavigateToDailyNoteInjection: () -> Unit,
    onNavigateToIndividualTracking: () -> Unit,
    onIncludeGranularDataChanged: (Boolean) -> Unit,
    onSleepDayAttributionChanged: (SleepDayAttribution) -> Unit,
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
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
            }
            Text(
                stringResource(R.string.advanced_settings_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.SemiBold,
            )
        }

        // Health Metrics
        SettingsNavRow(
            icon = Icons.Outlined.Checklist,
            title = stringResource(R.string.section_health_metrics),
            subtitle = pluralStringResource(
                R.plurals.metrics_enabled_summary,
                settings.metricSelection.enabledCount,
                settings.metricSelection.enabledCount,
                HealthMetrics.totalCount,
            ),
            onClick = onNavigateToMetrics,
        )

        // Export Format summary
        GeistCard {
            SectionLabel(stringResource(R.string.section_current_format))
            val selectedFormatNames = buildList {
                if (ExportFormat.MARKDOWN in settings.selectedExportFormats) add(stringResource(R.string.format_display_markdown))
                if (ExportFormat.OBSIDIAN_BASES in settings.selectedExportFormats) add(stringResource(R.string.format_display_obsidian_bases))
                if (ExportFormat.JSON in settings.selectedExportFormats) add(stringResource(R.string.format_display_json))
                if (ExportFormat.CSV in settings.selectedExportFormats) add(stringResource(R.string.format_display_csv))
            }
            Text(
                selectedFormatNames.joinToString(", ").ifBlank {
                    stringResource(R.string.advanced_settings_no_formats_selected)
                },
                style = MaterialTheme.typography.bodyLarge,
                color = AppColors.textPrimary,
            )
            Text(
                stringResource(R.string.write_mode_summary, settings.writeMode.localizedDisplayName()),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }

        // Format Customization
        SettingsNavRow(
            icon = Icons.Outlined.Tune,
            title = stringResource(R.string.section_format_customization),
            subtitle = "${settings.formatCustomization.dateFormat.localizedDisplayName()} \u2022 ${settings.formatCustomization.unitPreference.localizedDisplayName()}",
            onClick = onNavigateToFormatCustomization,
        )

        // Daily Note Injection
        SettingsNavRow(
            icon = Icons.Outlined.EditNote,
            title = stringResource(R.string.section_daily_note_injection),
            subtitle = if (settings.dailyNoteInjection.enabled) stringResource(R.string.daily_note_enabled_summary, settings.dailyNoteInjection.folderPath) else stringResource(R.string.daily_note_disabled),
            onClick = onNavigateToDailyNoteInjection,
        )

        // Individual Entry Tracking
        SettingsNavRow(
            icon = Icons.Outlined.FormatListNumbered,
            title = stringResource(R.string.section_individual_tracking),
            subtitle = if (settings.individualTracking.globalEnabled) {
                pluralStringResource(
                    R.plurals.individual_tracking_enabled_summary,
                    settings.individualTracking.trackedMetricCount,
                    settings.individualTracking.trackedMetricCount,
                )
            } else {
                stringResource(R.string.daily_note_disabled)
            },
            onClick = onNavigateToIndividualTracking,
        )

        // Sleep Day Attribution (issue #104): which daily note owns a
        // midnight-spanning sleep session. Device-local capture preference,
        // applied to every Health Connect capture path and widgets.
        GeistCard {
            Text(
                stringResource(R.string.sleep_attribution_title),
                style = MaterialTheme.typography.bodyLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Medium,
            )
            Spacer(modifier = Modifier.height(Spacing.sm))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs), modifier = Modifier.fillMaxWidth()) {
                listOf(
                    SleepDayAttribution.NIGHT_BEGINS to stringResource(R.string.sleep_attribution_night_begins),
                    SleepDayAttribution.MORNING_ENDS to stringResource(R.string.sleep_attribution_morning_ends),
                ).forEach { (mode, label) ->
                    FilterChip(
                        selected = sleepDayAttribution == mode,
                        onClick = { onSleepDayAttributionChanged(mode) },
                        label = { Text(label) },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("sleep_attribution_${mode.wireValue}"),
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = AppColors.accentSubtle,
                            selectedLabelColor = AppColors.accent,
                        ),
                    )
                }
            }
            Spacer(modifier = Modifier.height(Spacing.xs))
            Text(
                stringResource(
                    when (sleepDayAttribution) {
                        SleepDayAttribution.NIGHT_BEGINS -> R.string.sleep_attribution_night_begins_description
                        SleepDayAttribution.MORNING_ENDS -> R.string.sleep_attribution_morning_ends_description
                    }
                ),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }

        // Granular Data
        GeistCard {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.granular_data_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.granular_data_description),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Switch(
                    checked = settings.includeGranularData,
                    onCheckedChange = onIncludeGranularDataChanged,
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = AppColors.onAccent,
                        checkedTrackColor = AppColors.accent,
                        uncheckedThumbColor = AppColors.textMuted,
                        uncheckedTrackColor = AppColors.bgSecondary,
                        uncheckedBorderColor = AppColors.borderDefault,
                    ),
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

@Composable
private fun SettingsNavRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    GeistCardClickable(onClick = onClick) {
        Icon(icon, contentDescription = null, tint = AppColors.accent, modifier = Modifier.size(24.dp))
        Spacer(modifier = Modifier.width(Spacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
        }
        Icon(Icons.AutoMirrored.Outlined.ArrowForwardIos, contentDescription = null, tint = AppColors.textMuted)
    }
}
