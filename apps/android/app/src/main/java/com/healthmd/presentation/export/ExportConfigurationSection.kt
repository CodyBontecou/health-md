package com.healthmd.presentation.export

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode
import com.healthmd.presentation.common.GlassBadge
import com.healthmd.presentation.common.GlassCard
import com.healthmd.presentation.common.GlassCardClickable
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import java.time.LocalDate

@Composable
fun ExportConfigurationSection(
    settings: ExportSettings,
    previewDate: LocalDate,
    onToggleExportFormat: (ExportFormat) -> Unit,
    onWriteModeChanged: (WriteMode) -> Unit,
    onFilenameFormatChanged: (String) -> Unit,
    onSubfolderChanged: (String) -> Unit,
    onFolderOrganizationChanged: (FolderOrganization) -> Unit,
    onFolderStructureChanged: (String) -> Unit,
    onIncludeMetadataChanged: (Boolean) -> Unit,
    onGroupByCategoryChanged: (Boolean) -> Unit,
    onUseEmojiChanged: (Boolean) -> Unit,
    onUnitPreferenceChanged: (UnitPreference) -> Unit,
    onNavigateToAdvancedSettings: () -> Unit,
    onResetSettings: () -> Unit,
) {
    // Export Format
    Column(modifier = Modifier.fillMaxWidth()) {
        SectionLabel(stringResource(R.string.section_export_format))
        GlassCard(padding = Spacing.md) {
            ExportFormat.entries.chunked(2).forEachIndexed { index, rowFormats ->
                if (index > 0) Spacer(modifier = Modifier.height(Spacing.xs))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    rowFormats.forEach { format ->
                        ExportFormatSelectionButton(
                            text = format.localizedDisplayName(),
                            selected = format in settings.selectedExportFormats,
                            onClick = { onToggleExportFormat(format) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (rowFormats.size == 1) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
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
                    .clickable { onWriteModeChanged(mode) }
                    .padding(Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(
                    selected = selected,
                    onClick = { onWriteModeChanged(mode) },
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
            onValueChange = onFilenameFormatChanged,
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
            onValueChange = onSubfolderChanged,
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
                        .clickable { onFolderOrganizationChanged(org) }
                        .padding(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selected,
                        onClick = { onFolderOrganizationChanged(org) },
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
            onValueChange = onFolderStructureChanged,
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

        ExportConfigurationToggleRow(stringResource(R.string.toggle_include_frontmatter), settings.includeMetadata, onIncludeMetadataChanged)
        ExportConfigurationToggleRow(stringResource(R.string.toggle_group_by_category), settings.groupByCategory, onGroupByCategoryChanged)
        ExportConfigurationToggleRow(stringResource(R.string.toggle_emoji_headers), settings.formatCustomization.markdownTemplate.useEmoji, onUseEmojiChanged)

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
                        .clickable { onUnitPreferenceChanged(pref) }
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

    SecondaryButton(
        text = stringResource(R.string.reset_to_defaults),
        onClick = onResetSettings,
    )
}

@Composable
private fun ExportFormatSelectionButton(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(100.dp)
    Row(
        modifier = modifier
            .heightIn(min = 54.dp)
            .clip(shape)
            .background(if (selected) AppColors.accent.copy(alpha = 0.18f) else Color.Transparent)
            .then(
                if (selected) {
                    Modifier.border(1.dp, AppColors.accent.copy(alpha = 0.55f), shape)
                } else {
                    Modifier
                }
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(22.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.xs))
        }
        Text(
            text = text,
            color = if (selected) AppColors.accent else AppColors.textSecondary,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
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
private fun ExportConfigurationToggleRow(
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
