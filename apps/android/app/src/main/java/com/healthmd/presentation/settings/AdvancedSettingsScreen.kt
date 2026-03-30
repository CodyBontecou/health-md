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
                Icon(Icons.Filled.ArrowBack, "Back", tint = AppColors.textPrimary)
            }
            Text(
                "Export Settings",
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        // Health Metrics
        SettingsNavRow(
            icon = Icons.Outlined.Checklist,
            title = "Health Metrics",
            subtitle = "${settings.metricSelection.enabledCount}/${HealthMetrics.totalCount} metrics enabled",
            onClick = onNavigateToMetrics,
        )

        // Export Format summary
        GlassCard {
            SectionLabel("Current Format")
            Text(
                settings.exportFormat.displayName,
                style = MaterialTheme.typography.bodyLarge,
                color = AppColors.textPrimary,
            )
            Text(
                "Write mode: ${settings.writeMode.displayName}",
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }

        // Format Customization
        SettingsNavRow(
            icon = Icons.Outlined.Tune,
            title = "Format Customization",
            subtitle = "${settings.formatCustomization.dateFormat.displayName} \u2022 ${settings.formatCustomization.unitPreference.displayName}",
            onClick = onNavigateToFormatCustomization,
        )

        // Daily Note Injection
        SettingsNavRow(
            icon = Icons.Outlined.EditNote,
            title = "Daily Note Injection",
            subtitle = if (settings.dailyNoteInjection.enabled) "Enabled \u2022 ${settings.dailyNoteInjection.folderPath}" else "Disabled",
            onClick = onNavigateToDailyNoteInjection,
        )

        // Individual Entry Tracking
        SettingsNavRow(
            icon = Icons.Outlined.FormatListNumbered,
            title = "Individual Entry Tracking",
            subtitle = if (settings.individualTracking.globalEnabled) "Enabled \u2022 ${settings.individualTracking.enabledMetrics.size} metrics" else "Disabled",
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
