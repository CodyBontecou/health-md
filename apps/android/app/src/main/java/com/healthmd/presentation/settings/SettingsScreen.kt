package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.*
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import java.time.LocalDate

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onNavigateToAdvancedSettings: () -> Unit = {},
    onNavigateToPaywall: () -> Unit = {},
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val isPurchased by viewModel.isPurchased.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Spacer(modifier = Modifier.height(Spacing.sm))

        // Settings icon header
        GlassIconCircle(size = 84.dp) {
            Icon(
                Icons.Outlined.Settings,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(40.dp),
            )
        }

        Text(
            text = stringResource(R.string.settings_title),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 2.sp,
            lineHeight = 36.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.settings_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )

        // Premium upgrade (show at top for free users)
        if (!isPurchased) {
            GlassCardClickable(onClick = onNavigateToPaywall) {
                Icon(
                    Icons.Outlined.WorkspacePremium,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.settings_upgrade_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.settings_upgrade_subtitle),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Icon(
                    Icons.Outlined.ChevronRight,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Export Format
        GlassCard {
            SectionLabel(stringResource(R.string.section_export_format))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                ExportFormat.entries.forEach { format ->
                    val selected = format in settings.selectedExportFormats
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
                            .clickable { viewModel.toggleExportFormat(format) }
                            .padding(horizontal = 8.dp, vertical = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            format.localizedDisplayName(),
                            modifier = Modifier.fillMaxWidth(),
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            maxLines = 1,
                        )
                    }
                }
            }
        }

        // Write Mode
        GlassCard {
            SectionLabel(stringResource(R.string.section_write_mode))
            WriteMode.entries.forEach { mode ->
                val selected = settings.writeMode == mode
                val shape = RoundedCornerShape(12.dp)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(shape)
                        .background(if (selected) AppColors.accent.copy(alpha = 0.08f) else Color.Transparent)
                        .clickable { viewModel.updateWriteMode(mode) }
                        .padding(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selected,
                        onClick = { viewModel.updateWriteMode(mode) },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = AppColors.accent,
                            unselectedColor = AppColors.textMuted,
                        ),
                    )
                    Column(modifier = Modifier.padding(start = Spacing.xs)) {
                        Text(mode.localizedDisplayName(), color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Text(mode.localizedDescription(), color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        // Filename Template
        GlassCard {
            SectionLabel(stringResource(R.string.section_filename_template))
            OutlinedTextField(
                value = settings.filenameFormat,
                onValueChange = { viewModel.updateFilenameFormat(it) },
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

        // Folder Organization
        GlassCard {
            SectionLabel(stringResource(R.string.section_file_organization))
            OutlinedTextField(
                value = settings.subfolder,
                onValueChange = { viewModel.updateSubfolder(it) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.health_subfolder_label)) },
                placeholder = { Text("health", color = AppColors.textMuted) },
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
            Spacer(modifier = Modifier.height(Spacing.sm))
            Text(stringResource(R.string.folder_organization_label), style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary)
            Spacer(modifier = Modifier.height(Spacing.xs))
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                FolderOrganization.entries.forEach { org ->
                    val selected = settings.folderOrganization == org
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (selected) AppColors.accent.copy(alpha = 0.08f) else Color.Transparent)
                            .clickable { viewModel.updateFolderOrganization(org) }
                            .padding(Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(
                            selected = selected,
                            onClick = { viewModel.updateFolderOrganization(org) },
                            colors = RadioButtonDefaults.colors(selectedColor = AppColors.accent, unselectedColor = AppColors.textMuted),
                        )
                        Column(modifier = Modifier.padding(start = Spacing.xs)) {
                            Text(org.displayLabel(), color = AppColors.textPrimary, style = MaterialTheme.typography.bodyMedium)
                            Text(org.previewTemplate(), color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(Spacing.sm))
            OutlinedTextField(
                value = settings.folderStructure,
                onValueChange = { viewModel.updateFolderStructure(it) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.folder_structure_template_label)) },
                placeholder = { Text("{year}/{month}", color = AppColors.textMuted) },
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
            Spacer(modifier = Modifier.height(Spacing.sm))
            val previewDate = LocalDate.now()
            val previewPaths = settings.selectedExportFormats.sortedBy { it.ordinal }.ifEmpty { listOf(settings.exportFormat) }
                .joinToString("\n") { settings.aggregateRelativePath(previewDate, it) }
            GlassBadge(borderColor = AppColors.accent.copy(alpha = 0.35f)) {
                Column {
                    Text(stringResource(R.string.path_preview_label), color = AppColors.textPrimary, style = MaterialTheme.typography.labelMedium)
                    Text(previewPaths, color = AppColors.textSecondary, style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        // Format options
        GlassCard {
            SectionLabel(stringResource(R.string.section_format_options))

            SettingsToggleRow(stringResource(R.string.toggle_include_frontmatter), settings.includeMetadata) { viewModel.updateIncludeMetadata(it) }
            SettingsToggleRow(stringResource(R.string.toggle_group_by_category), settings.groupByCategory) { viewModel.updateGroupByCategory(it) }
            SettingsToggleRow(stringResource(R.string.toggle_emoji_headers), settings.formatCustomization.markdownTemplate.useEmoji) { viewModel.updateUseEmoji(it) }

            Spacer(modifier = Modifier.height(Spacing.sm))
            Text(stringResource(R.string.label_units), style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary)
            Spacer(modifier = Modifier.height(Spacing.xs))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                UnitPreference.entries.forEach { pref ->
                    val selected = settings.formatCustomization.unitPreference == pref
                    val shape = RoundedCornerShape(100.dp)
                    Box(
                        modifier = Modifier
                            .clip(shape)
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                            .border(
                                1.dp,
                                if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder,
                                shape,
                            )
                            .clickable { viewModel.updateUnitPreference(pref) }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                    ) {
                        Text(
                            pref.localizedDisplayName(),
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }

        // Advanced Settings Navigation
        GlassCardClickable(onClick = onNavigateToAdvancedSettings) {
            Icon(
                Icons.Outlined.Tune,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.advanced_settings_nav_title),
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    stringResource(R.string.advanced_settings_nav_subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
            Icon(
                Icons.Outlined.ChevronRight,
                contentDescription = null,
                tint = AppColors.textMuted,
            )
        }

        // Feedback
        val context = LocalContext.current
        GlassCard {
            SectionLabel(stringResource(R.string.section_feedback))

            GlassCardClickable(onClick = { FeedbackHelper.sendFeedbackEmail(context) }) {
                Icon(
                    Icons.Outlined.Email,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.feedback_send_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.feedback_send_subtitle),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Icon(
                    Icons.Outlined.ArrowOutward,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(16.dp),
                )
            }

            Spacer(modifier = Modifier.height(Spacing.xs))

            GlassCardClickable(onClick = { FeedbackHelper.openGitHubIssue(context) }) {
                Icon(
                    Icons.Outlined.BugReport,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.feedback_github_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.feedback_github_subtitle),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Icon(
                    Icons.Outlined.ArrowOutward,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        // Reset
        SecondaryButton(
            text = stringResource(R.string.reset_to_defaults),
            onClick = { viewModel.resetSettings() },
        )

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

private fun FolderOrganization.displayLabel(): String = when (this) {
    FolderOrganization.FLAT -> "Flat"
    FolderOrganization.BY_YEAR -> "By year"
    FolderOrganization.BY_MONTH -> "By month"
    FolderOrganization.BY_YEAR_MONTH -> "By year/month"
}

private fun FolderOrganization.previewTemplate(): String = when (this) {
    FolderOrganization.FLAT -> "No automatic date folders"
    FolderOrganization.BY_YEAR -> "{year}"
    FolderOrganization.BY_MONTH -> "{month}"
    FolderOrganization.BY_YEAR_MONTH -> "{year}/{month}"
}

@Composable
private fun SettingsToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
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
