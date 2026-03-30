package com.healthmd.presentation.settings

import androidx.compose.foundation.background
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
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun DailyNoteInjectionScreen(
    settings: DailyNoteInjectionSettings,
    onSettingsChanged: (DailyNoteInjectionSettings) -> Unit,
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
                "Daily Note Injection",
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        // Description
        GlassCard {
            Text(
                "Inject health metrics into the YAML frontmatter of your existing Obsidian daily notes.",
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
            )
        }

        // Enable toggle
        GlassCard {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text("Enable Injection", color = AppColors.textPrimary, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Inject health data into daily notes",
                        color = AppColors.textSecondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = settings.enabled,
                    onCheckedChange = { onSettingsChanged(settings.copy(enabled = it)) },
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

        if (settings.enabled) {
            // Folder path
            GlassCard {
                SectionLabel("Daily Notes Folder")
                OutlinedTextField(
                    value = settings.folderPath,
                    onValueChange = { onSettingsChanged(settings.copy(folderPath = it)) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Daily", color = AppColors.textMuted) },
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
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    "Relative to your export folder (e.g., \"Daily\" or \"Journal/Daily\")",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }

            // Filename pattern
            GlassCard {
                SectionLabel("Filename Pattern")
                OutlinedTextField(
                    value = settings.filenamePattern,
                    onValueChange = { onSettingsChanged(settings.copy(filenamePattern = it)) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("{date}", color = AppColors.textMuted) },
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
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    "{date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }

            // Preview
            GlassCard {
                SectionLabel("Preview Path")
                Text(
                    settings.previewPath(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.accent,
                )
            }

            // Create if missing
            GlassCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text("Create Note if Missing", color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "Create daily note if it doesn't exist",
                            color = AppColors.textSecondary,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Switch(
                        checked = settings.createIfMissing,
                        onCheckedChange = { onSettingsChanged(settings.copy(createIfMissing = it)) },
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
