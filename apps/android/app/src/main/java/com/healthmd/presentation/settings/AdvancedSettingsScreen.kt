package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
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
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.stringResource
import com.healthmd.R

@Composable
fun AdvancedSettingsScreen(
    settings: ExportSettings,
    onNavigateToMetrics: () -> Unit,
    onNavigateToFormatCustomization: () -> Unit,
    onNavigateToDailyNoteInjection: () -> Unit,
    onNavigateToIndividualTracking: () -> Unit,
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
                Icon(Icons.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
            }
            Text(
                stringResource(R.string.advanced_settings_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        // Health Metrics
        SettingsNavRow(
            icon = Icons.Outlined.Checklist,
            title = stringResource(R.string.section_health_metrics),
            subtitle = stringResource(R.string.metrics_enabled_summary, settings.metricSelection.enabledCount, HealthMetrics.totalCount),
            onClick = onNavigateToMetrics,
        )

        // Export Format summary
        GlassCard {
            SectionLabel(stringResource(R.string.section_current_format))
            Text(
                settings.exportFormat.displayName,
                style = MaterialTheme.typography.bodyLarge,
                color = AppColors.textPrimary,
            )
            Text(
                stringResource(R.string.write_mode_summary, settings.writeMode.displayName),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }

        // Format Customization
        SettingsNavRow(
            icon = Icons.Outlined.Tune,
            title = stringResource(R.string.section_format_customization),
            subtitle = "${settings.formatCustomization.dateFormat.displayName} \u2022 ${settings.formatCustomization.unitPreference.displayName}",
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
            subtitle = if (settings.individualTracking.globalEnabled) stringResource(R.string.individual_tracking_enabled_summary, settings.individualTracking.enabledMetrics.size) else stringResource(R.string.daily_note_disabled),
            onClick = onNavigateToIndividualTracking,
        )

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
    GlassCardClickable(onClick = onClick) {
        Icon(icon, contentDescription = null, tint = AppColors.accent, modifier = Modifier.size(24.dp))
        Spacer(modifier = Modifier.width(Spacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
        }
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = AppColors.textMuted)
    }
}
