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
import com.healthmd.presentation.common.GeistBadge
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawSnapshotScope
import java.time.LocalDate

@Composable
fun ExportConfigurationSection(
    settings: ExportSettings,
    previewDate: LocalDate,
    onExportModeChanged: (ExportMode) -> Unit,
    onRawExportFormatChanged: (RawExportFormat) -> Unit,
    onRawScopeChanged: (RawSnapshotScope) -> Unit,
    onRawIncludeExerciseRoutesChanged: (Boolean) -> Unit,
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
    Column(modifier = Modifier.fillMaxWidth()) {
        SectionLabel(stringResource(R.string.section_export_type))
        GeistCard {
            ExportTypeRow(
                title = stringResource(R.string.export_type_compatibility),
                description = stringResource(R.string.export_type_compatibility_description),
                selected = settings.exportMode == ExportMode.COMPATIBILITY,
                onClick = { onExportModeChanged(ExportMode.COMPATIBILITY) },
            )
            ExportTypeRow(
                title = stringResource(R.string.export_type_raw_snapshot),
                description = stringResource(R.string.export_type_raw_snapshot_description),
                selected = settings.exportMode == ExportMode.RAW_SNAPSHOT,
                onClick = { onExportModeChanged(ExportMode.RAW_SNAPSHOT) },
            )
        }
    }

    if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
        RawSnapshotConfiguration(
            settings = settings,
            onFormatChanged = onRawExportFormatChanged,
            onScopeChanged = onRawScopeChanged,
            onIncludeExerciseRoutesChanged = onRawIncludeExerciseRoutesChanged,
        )
        SecondaryButton(
            text = stringResource(R.string.reset_to_defaults),
            onClick = onResetSettings,
        )
        return
    }

    // Compatibility Export Format
    Column(modifier = Modifier.fillMaxWidth()) {
        SectionLabel(stringResource(R.string.section_export_format))
        GeistCard(padding = Spacing.md) {
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
    GeistCard {
        SectionLabel(stringResource(R.string.section_write_mode))
        WriteMode.entries.forEach { mode ->
            val selected = settings.writeMode == mode
            val shape = RoundedCornerShape(Radii.card)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(shape)
                    .background(if (selected) AppColors.accentSubtle else Color.Transparent)
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
    GeistCard {
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
            shape = RoundedCornerShape(Radii.card),
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
    GeistCard {
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
            shape = RoundedCornerShape(Radii.card),
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
                        .clip(RoundedCornerShape(Radii.card))
                        .background(if (selected) AppColors.accentSubtle else Color.Transparent)
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
            shape = RoundedCornerShape(Radii.card),
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
        GeistBadge(borderColor = AppColors.accentBorder) {
            Column {
                Text(stringResource(R.string.path_preview_label), color = AppColors.textPrimary, style = MaterialTheme.typography.labelMedium)
                Text(previewPaths, color = AppColors.textSecondary, style = MaterialTheme.typography.bodySmall)
            }
        }
    }

    // Format options
    GeistCard {
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
                val shape = RoundedCornerShape(Radii.badge)
                Box(
                    modifier = Modifier
                        .clip(shape)
                        .background(if (selected) AppColors.accentSubtle else AppColors.bgSecondary)
                        .border(
                            1.dp,
                            if (selected) AppColors.accentBorder else AppColors.borderDefault,
                            shape,
                        )
                        .clickable { onUnitPreferenceChanged(pref) }
                        .padding(horizontal = Spacing.md, vertical = Spacing.xs),
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
    GeistCardClickable(onClick = onNavigateToAdvancedSettings) {
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
private fun RawSnapshotConfiguration(
    settings: ExportSettings,
    onFormatChanged: (RawExportFormat) -> Unit,
    onScopeChanged: (RawSnapshotScope) -> Unit,
    onIncludeExerciseRoutesChanged: (Boolean) -> Unit,
) {
    GeistCard {
        SectionLabel(stringResource(R.string.raw_snapshot_about_title))
        Text(
            stringResource(R.string.raw_snapshot_about_body),
            color = AppColors.textSecondary,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
    GeistCard {
        SectionLabel(stringResource(R.string.raw_snapshot_format_title))
        RawChoiceRow(
            title = stringResource(R.string.raw_snapshot_format_json),
            description = stringResource(R.string.raw_snapshot_format_json_description),
            selected = settings.rawSnapshot.format == RawExportFormat.JSON,
            onClick = { onFormatChanged(RawExportFormat.JSON) },
        )
        RawChoiceRow(
            title = stringResource(R.string.raw_snapshot_format_ndjson),
            description = stringResource(R.string.raw_snapshot_format_ndjson_description),
            selected = settings.rawSnapshot.format == RawExportFormat.NDJSON,
            onClick = { onFormatChanged(RawExportFormat.NDJSON) },
        )
        Text(
            stringResource(R.string.raw_snapshot_one_artifact_note),
            color = AppColors.textMuted,
            style = MaterialTheme.typography.bodySmall,
        )
    }
    GeistCard {
        SectionLabel(stringResource(R.string.raw_snapshot_scope_title))
        RawChoiceRow(
            title = stringResource(R.string.raw_snapshot_scope_selected),
            description = stringResource(R.string.raw_snapshot_scope_selected_description),
            selected = settings.rawSnapshot.scope == RawSnapshotScope.SELECTED_RECORD_TYPES,
            onClick = { onScopeChanged(RawSnapshotScope.SELECTED_RECORD_TYPES) },
        )
        RawChoiceRow(
            title = stringResource(R.string.raw_snapshot_scope_all),
            description = stringResource(R.string.raw_snapshot_scope_all_description),
            selected = settings.rawSnapshot.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA,
            onClick = { onScopeChanged(RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA) },
        )
    }
    GeistCard {
        SectionLabel(stringResource(R.string.raw_snapshot_routes_title))
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.xs),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.raw_snapshot_routes_control), color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                Text(stringResource(R.string.raw_snapshot_routes_description), color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
            }
            Spacer(modifier = Modifier.width(Spacing.sm))
            Switch(
                checked = settings.rawSnapshot.includeExerciseRoutes,
                onCheckedChange = onIncludeExerciseRoutesChanged,
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
    GeistCard {
        Text(
            stringResource(R.string.raw_snapshot_immutable_destination_note),
            color = AppColors.textSecondary,
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(modifier = Modifier.height(Spacing.xs))
        Text(
            stringResource(R.string.raw_snapshot_preview_unavailable),
            color = AppColors.textMuted,
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun ExportTypeRow(
    title: String,
    description: String,
    selected: Boolean,
    onClick: () -> Unit,
) = RawChoiceRow(title, description, selected, onClick)

@Composable
private fun RawChoiceRow(
    title: String,
    description: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(Radii.card)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) AppColors.accentSubtle else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(
            selected = selected,
            onClick = onClick,
            colors = RadioButtonDefaults.colors(
                selectedColor = AppColors.accent,
                unselectedColor = AppColors.textMuted,
            ),
        )
        Column(modifier = Modifier.padding(start = Spacing.xs)) {
            Text(title, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
            Text(description, color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun ExportFormatSelectionButton(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(Radii.badge)
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (selected) AppColors.accentSubtle else Color.Transparent)
            .then(
                if (selected) {
                    Modifier.border(1.dp, AppColors.accentBorder, shape)
                } else {
                    Modifier
                }
            )
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.sm, vertical = Spacing.xs),
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
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.SemiBold,
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
                checkedThumbColor = AppColors.onAccent,
                checkedTrackColor = AppColors.accent,
                uncheckedThumbColor = AppColors.textMuted,
                uncheckedTrackColor = AppColors.bgSecondary,
                uncheckedBorderColor = AppColors.borderDefault,
            ),
        )
    }
}
