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
                Icon(Icons.Filled.ArrowBack, "Back", tint = AppColors.textPrimary)
            }
            Text(
                "Individual Entry Tracking",
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        GlassCard {
            Text(
                "Export individual timestamped health entries as separate files. Useful for workouts, blood pressure readings, and other discrete measurements.",
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
                    Text("Enable Individual Tracking", color = AppColors.textPrimary, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "${settings.enabledMetrics.size} metrics selected",
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
                SectionLabel("Quick Actions")
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    SecondaryButton(
                        text = "Suggested",
                        onClick = { onSettingsChanged(settings.enableSuggested()) },
                        modifier = Modifier.weight(1f),
                    )
                    SecondaryButton(
                        text = "All",
                        onClick = {
                            onSettingsChanged(settings.enableAll(listOf(
                                "workouts", "blood_pressure", "blood_glucose", "weight",
                            )))
                        },
                        modifier = Modifier.weight(1f),
                    )
                    SecondaryButton(
                        text = "None",
                        onClick = { onSettingsChanged(settings.disableAll()) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            // Metric toggles
            GlassCard {
                SectionLabel("Tracked Metrics")
                val trackableMetrics = listOf(
                    "workouts" to "Workouts",
                    "blood_pressure" to "Blood Pressure",
                    "blood_glucose" to "Blood Glucose",
                    "weight" to "Weight",
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
                SectionLabel("Entries Folder Name")
                OutlinedTextField(
                    value = settings.entriesFolder,
                    onValueChange = { onSettingsChanged(settings.copy(entriesFolder = it)) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("entries", color = AppColors.textMuted) },
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
                        Text("Organize by Category", color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "Group entries into category subfolders",
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
