package com.healthmd.presentation.settings

import androidx.compose.foundation.background
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.stringResource
import com.healthmd.R

@Composable
fun IndividualTrackingScreen(
    settings: IndividualTrackingSettings,
    onSettingsChanged: (IndividualTrackingSettings) -> Unit,
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
                stringResource(R.string.individual_tracking_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        GlassCard {
            Text(
                stringResource(R.string.individual_tracking_description),
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
            )
        }

        // Master toggle
        GlassCard {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(stringResource(R.string.individual_tracking_enable_title), color = AppColors.textPrimary, style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.individual_tracking_metrics_count, settings.enabledMetrics.size),
                        color = AppColors.textSecondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = settings.globalEnabled,
                    onCheckedChange = { onSettingsChanged(settings.copy(globalEnabled = it)) },
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

        if (settings.globalEnabled) {
            // Quick actions
            GlassCard {
                SectionLabel(stringResource(R.string.section_quick_actions))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    SecondaryButton(
                        text = stringResource(R.string.action_suggested),
                        onClick = { onSettingsChanged(settings.enableSuggested()) },
                        modifier = Modifier.weight(1f),
                    )
                    SecondaryButton(
                        text = stringResource(R.string.action_all),
                        onClick = {
                            onSettingsChanged(settings.enableAll(listOf(
                                "workouts", "blood_pressure", "blood_glucose", "weight",
                            )))
                        },
                        modifier = Modifier.weight(1f),
                    )
                    SecondaryButton(
                        text = stringResource(R.string.action_none),
                        onClick = { onSettingsChanged(settings.disableAll()) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            // Metric toggles
            GlassCard {
                SectionLabel(stringResource(R.string.section_tracked_metrics))
                val trackableMetrics = listOf(
                    "workouts" to stringResource(R.string.metric_workouts),
                    "blood_pressure" to stringResource(R.string.metric_blood_pressure),
                    "blood_glucose" to stringResource(R.string.metric_blood_glucose),
                    "weight" to stringResource(R.string.metric_weight),
                )
                trackableMetrics.forEach { (id, name) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSettingsChanged(settings.toggleMetric(id)) }
                            .padding(vertical = Spacing.xs),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(name, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Checkbox(
                            checked = id in settings.enabledMetrics,
                            onCheckedChange = { onSettingsChanged(settings.toggleMetric(id)) },
                            colors = CheckboxDefaults.colors(
                                checkedColor = AppColors.accent,
                                uncheckedColor = AppColors.textMuted,
                                checkmarkColor = Color.White,
                            ),
                        )
                    }
                }
            }

            // Folder configuration
            GlassCard {
                SectionLabel(stringResource(R.string.section_entries_folder))
                OutlinedTextField(
                    value = settings.entriesFolder,
                    onValueChange = { onSettingsChanged(settings.copy(entriesFolder = it)) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(stringResource(R.string.entries_folder_hint), color = AppColors.textMuted) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AppColors.accent,
                        unfocusedBorderColor = AppColors.borderDefault,
                        focusedTextColor = AppColors.textPrimary,
                        unfocusedTextColor = AppColors.textPrimary,
                        cursorColor = AppColors.accent,
                    ),
                    shape = RoundedCornerShape(12.dp),
                    singleLine = true,
                )
            }

            // Organize by category
            GlassCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text(stringResource(R.string.organize_by_category_title), color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            stringResource(R.string.organize_by_category_subtitle),
                            color = AppColors.textSecondary,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Switch(
                        checked = settings.organizeByCategory,
                        onCheckedChange = { onSettingsChanged(settings.copy(organizeByCategory = it)) },
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
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}
