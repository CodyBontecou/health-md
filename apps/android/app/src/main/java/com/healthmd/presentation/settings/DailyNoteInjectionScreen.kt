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
import androidx.compose.ui.res.stringResource
import com.healthmd.R

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
                Icon(Icons.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
            }
            Text(
                stringResource(R.string.section_daily_note_injection),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        // Description
        GlassCard {
            Text(
                stringResource(R.string.daily_note_description),
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
                    Text(stringResource(R.string.daily_note_enable_title), color = AppColors.textPrimary, style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.daily_note_enable_subtitle),
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
                SectionLabel(stringResource(R.string.section_daily_notes_folder))
                OutlinedTextField(
                    value = settings.folderPath,
                    onValueChange = { onSettingsChanged(settings.copy(folderPath = it)) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(stringResource(R.string.daily_notes_folder_hint), color = AppColors.textMuted) },
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
                    stringResource(R.string.daily_notes_folder_help),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }

            // Filename pattern
            GlassCard {
                SectionLabel(stringResource(R.string.section_filename_pattern))
                OutlinedTextField(
                    value = settings.filenamePattern,
                    onValueChange = { onSettingsChanged(settings.copy(filenamePattern = it)) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(stringResource(R.string.filename_template_hint), color = AppColors.textMuted) },
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
                    stringResource(R.string.filename_template_tokens),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }

            // Preview
            GlassCard {
                SectionLabel(stringResource(R.string.section_preview_path))
                Text(
                    settings.previewPath(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.accent,
                )
            }

            // Markdown body sections
            GlassCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.inject_markdown_sections_title), color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            stringResource(R.string.inject_markdown_sections_subtitle),
                            color = AppColors.textSecondary,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Switch(
                        checked = settings.injectMarkdownSections,
                        onCheckedChange = { onSettingsChanged(settings.copy(injectMarkdownSections = it)) },
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

            // Create if missing
            GlassCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text(stringResource(R.string.create_note_if_missing_title), color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            stringResource(R.string.create_note_if_missing_subtitle),
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
