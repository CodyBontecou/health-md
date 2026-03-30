package com.healthmd.presentation.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.stringResource
import com.healthmd.R

@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))

        SectionLabel(stringResource(R.string.section_schedule))

        // Large clock icon with glass circle
        Box(contentAlignment = Alignment.Center) {
            if (uiState.isEnabled) {
                // Glow layer
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                        .background(AppColors.accent.copy(alpha = 0.15f)),
                )
            }
            GlassIconCircle(size = 100.dp) {
                Icon(
                    if (uiState.isEnabled) Icons.Filled.Schedule else Icons.Outlined.Schedule,
                    contentDescription = null,
                    tint = if (uiState.isEnabled) AppColors.accent else AppColors.textMuted,
                    modifier = Modifier.size(56.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Status text
        Text(
            text = if (uiState.isEnabled) stringResource(R.string.schedule_active) else stringResource(R.string.schedule_not_set),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 3.sp,
            lineHeight = 36.sp,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        // Toggle card
        GlassCard {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(stringResource(R.string.automatic_export_title), color = AppColors.textPrimary, style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.automatic_export_subtitle),
                        color = AppColors.textSecondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = uiState.isEnabled,
                    onCheckedChange = { viewModel.toggleSchedule(it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = androidx.compose.ui.graphics.Color.White,
                        checkedTrackColor = AppColors.accent,
                        uncheckedThumbColor = AppColors.textMuted,
                        uncheckedTrackColor = AppColors.bgSecondary,
                        uncheckedBorderColor = AppColors.borderDefault,
                    ),
                )
            }
        }

        // Frequency (when enabled)
        if (uiState.isEnabled) {
            GlassCard {
                SectionLabel(stringResource(R.string.section_frequency))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    listOf(ScheduleFrequency.DAILY to stringResource(R.string.frequency_daily), ScheduleFrequency.WEEKLY to stringResource(R.string.frequency_weekly)).forEach { (freq, label) ->
                        val selected = uiState.frequency == freq
                        val shape = RoundedCornerShape(100.dp)
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(shape)
                                .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                                .border(
                                    1.dp,
                                    if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder,
                                    shape,
                                )
                                .clickable { viewModel.setFrequency(freq) }
                                .padding(vertical = 14.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                label,
                                color = if (selected) AppColors.accent else AppColors.textSecondary,
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            )
                        }
                    }
                }
            }

            // Time picker
            GlassCard {
                SectionLabel(stringResource(R.string.section_export_time))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Hour picker
                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(stringResource(R.string.label_hour), style = MaterialTheme.typography.labelSmall, color = AppColors.textMuted)
                        Spacer(modifier = Modifier.height(4.dp))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            GlassIconButton(
                                icon = Icons.Filled.Remove,
                                onClick = { viewModel.setHour((uiState.hour - 1 + 24) % 24) },
                            )
                            Text(
                                String.format("%02d", uiState.hour),
                                style = MaterialTheme.typography.headlineMedium,
                                color = AppColors.textPrimary,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = Spacing.sm),
                            )
                            GlassIconButton(
                                icon = Icons.Filled.Add,
                                onClick = { viewModel.setHour((uiState.hour + 1) % 24) },
                            )
                        }
                    }

                    Text(":", style = MaterialTheme.typography.headlineMedium, color = AppColors.textMuted)

                    // Minute picker (5-min intervals)
                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(stringResource(R.string.label_minute), style = MaterialTheme.typography.labelSmall, color = AppColors.textMuted)
                        Spacer(modifier = Modifier.height(4.dp))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            GlassIconButton(
                                icon = Icons.Filled.Remove,
                                onClick = { viewModel.setMinute((uiState.minute - 5 + 60) % 60) },
                            )
                            Text(
                                String.format("%02d", uiState.minute),
                                style = MaterialTheme.typography.headlineMedium,
                                color = AppColors.textPrimary,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = Spacing.sm),
                            )
                            GlassIconButton(
                                icon = Icons.Filled.Add,
                                onClick = { viewModel.setMinute((uiState.minute + 5) % 60) },
                            )
                        }
                    }
                }
            }

            // Next export info
            if (uiState.nextExportDescription.isNotEmpty()) {
                GlassBadge(borderColor = AppColors.accent.copy(alpha = 0.3f)) {
                    Text(
                        uiState.nextExportDescription,
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                    )
                }
            }

            GlassCard(padding = Spacing.md) {
                Text(
                    stringResource(R.string.schedule_workmanager_notice),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

enum class ScheduleFrequency { DAILY, WEEKLY }

data class ScheduleUiState(
    val isEnabled: Boolean = false,
    val frequency: ScheduleFrequency = ScheduleFrequency.DAILY,
    val hour: Int = 6,
    val minute: Int = 0,
    val nextExportDescription: String = "",
)
