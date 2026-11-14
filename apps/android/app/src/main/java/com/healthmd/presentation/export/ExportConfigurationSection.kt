package com.healthmd.presentation.export

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.settings.SettingsRow
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
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
    OptionsGroup(
        title = stringResource(R.string.section_export_type),
        rows = listOf(
            { shape ->
                ChoiceRow(
                    shape = shape,
                    title = stringResource(R.string.export_type_compatibility),
                    description = stringResource(R.string.export_type_compatibility_description),
                    selected = settings.exportMode == ExportMode.COMPATIBILITY,
                    onClick = { onExportModeChanged(ExportMode.COMPATIBILITY) },
                )
            },
            { shape ->
                ChoiceRow(
                    shape = shape,
                    title = stringResource(R.string.export_type_raw_snapshot),
                    description = stringResource(R.string.export_type_raw_snapshot_description),
                    selected = settings.exportMode == ExportMode.RAW_SNAPSHOT,
                    onClick = { onExportModeChanged(ExportMode.RAW_SNAPSHOT) },
                )
            },
        ),
    )

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

    val colors = LocalGeistColors.current

    // Compatibility export formats: multi-select filter chips that reflow at any font scale.
    OptionsGroup(
        title = stringResource(R.string.section_export_format),
        rows = listOf(
            { shape ->
                ContentRow(shape) {
                    ExportFormatChips(
                        selectedFormats = settings.selectedExportFormats,
                        onToggleExportFormat = onToggleExportFormat,
                    )
                }
            },
        ),
    )

    OptionsGroup(
        title = stringResource(R.string.section_write_mode),
        rows = WriteMode.entries.map { mode ->
            @Composable { shape: Shape ->
                ChoiceRow(
                    shape = shape,
                    title = mode.localizedDisplayName(),
                    description = mode.localizedDescription(),
                    selected = settings.writeMode == mode,
                    onClick = { onWriteModeChanged(mode) },
                )
            }
        },
    )

    OptionsGroup(
        title = stringResource(R.string.section_filename_template),
        rows = listOf(
            { shape ->
                ContentRow(shape) {
                    OutlinedTextField(
                        value = settings.filenameFormat,
                        onValueChange = onFilenameFormatChanged,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text(stringResource(R.string.filename_template_hint), color = colors.secondary) },
                        colors = optionsTextFieldColors(),
                        shape = RoundedCornerShape(GeistRadii.extraSmall),
                        textStyle = GeistType.label16,
                        singleLine = true,
                    )
                    HelperText(stringResource(R.string.filename_template_tokens))
                }
            },
        ),
    )

    OptionsGroup(
        title = stringResource(R.string.section_file_organization),
        rows = listOf(
            { shape ->
                ContentRow(shape) {
                    OutlinedTextField(
                        value = settings.subfolder,
                        onValueChange = onSubfolderChanged,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.health_subfolder_label)) },
                        placeholder = { Text("health", color = colors.secondary) },
                        colors = optionsTextFieldColors(),
                        shape = RoundedCornerShape(GeistRadii.extraSmall),
                        textStyle = GeistType.label16,
                        singleLine = true,
                    )
                }
            },
        ),
    )

    val previewPaths = settings.selectedExportFormats.sortedBy { it.ordinal }.ifEmpty { listOf(settings.exportFormat) }
        .joinToString("\n") { settings.aggregateRelativePath(previewDate, it) }
    OptionsGroup(
        title = stringResource(R.string.folder_organization_label),
        rows = FolderOrganization.entries.map { org ->
            @Composable { shape: Shape ->
                ChoiceRow(
                    shape = shape,
                    title = org.displayLabel(),
                    description = org.previewTemplate(),
                    selected = settings.folderOrganization == org,
                    onClick = { onFolderOrganizationChanged(org) },
                )
            }
        } + listOf(
            @Composable { shape: Shape ->
                ContentRow(shape) {
                    OutlinedTextField(
                        value = settings.folderStructure,
                        onValueChange = onFolderStructureChanged,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.folder_structure_template_label)) },
                        placeholder = { Text("{year}/{month}", color = colors.secondary) },
                        colors = optionsTextFieldColors(),
                        shape = RoundedCornerShape(GeistRadii.extraSmall),
                        textStyle = GeistType.label16,
                        singleLine = true,
                    )
                    HelperText(stringResource(R.string.filename_template_tokens))
                    SecondaryButton(
                        text = stringResource(R.string.folder_organization_by_year_week_label),
                        onClick = { onFolderStructureChanged(ExportSettings.YEAR_WEEK_FOLDER_TEMPLATE) },
                    )
                }
            },
            @Composable { shape: Shape ->
                ContentRow(shape) {
                    Text(stringResource(R.string.path_preview_label), style = GeistType.label12, color = colors.brandPrimary)
                    Text(previewPaths, style = GeistType.copy13Mono, color = colors.primary)
                }
            },
        ),
    )

    OptionsGroup(
        title = stringResource(R.string.section_format_options),
        rows = listOf(
            { shape ->
                SwitchRow(shape, stringResource(R.string.toggle_include_frontmatter), settings.includeMetadata, onIncludeMetadataChanged)
            },
            { shape ->
                SwitchRow(shape, stringResource(R.string.toggle_group_by_category), settings.groupByCategory, onGroupByCategoryChanged)
            },
            { shape ->
                SwitchRow(
                    shape,
                    stringResource(R.string.toggle_emoji_headers),
                    settings.formatCustomization.markdownTemplate.useEmoji,
                    onUseEmojiChanged,
                )
            },
            { shape ->
                ContentRow(shape) {
                    Text(stringResource(R.string.label_units), style = GeistType.label16, color = colors.primary)
                    UnitSegmentedButtons(
                        selected = settings.formatCustomization.unitPreference,
                        onSelected = onUnitPreferenceChanged,
                    )
                }
            },
        ),
    )

    SettingsRow(
        shape = RoundedCornerShape(GeistRadii.listGroup),
        title = stringResource(R.string.advanced_settings_nav_title),
        subtitle = stringResource(R.string.advanced_settings_nav_subtitle),
        icon = Icons.Outlined.Tune,
        onClick = onNavigateToAdvancedSettings,
    )

    SecondaryButton(
        text = stringResource(R.string.reset_to_defaults),
        onClick = onResetSettings,
    )
}

@Composable
internal fun RawSnapshotConfiguration(
    settings: ExportSettings,
    onFormatChanged: (RawExportFormat) -> Unit,
    onScopeChanged: (RawSnapshotScope) -> Unit,
    onIncludeExerciseRoutesChanged: (Boolean) -> Unit,
) {
    val colors = LocalGeistColors.current
    OptionsGroup(
        title = stringResource(R.string.raw_snapshot_about_title),
        rows = listOf(
            { shape ->
                ContentRow(shape) {
                    Text(stringResource(R.string.raw_snapshot_about_body), style = GeistType.copy14, color = colors.secondary)
                }
            },
        ),
    )
    OptionsGroup(
        title = stringResource(R.string.raw_snapshot_format_title),
        rows = listOf(
            { shape ->
                ChoiceRow(
                    shape = shape,
                    title = stringResource(R.string.raw_snapshot_format_json),
                    description = stringResource(R.string.raw_snapshot_format_json_description),
                    selected = settings.rawSnapshot.format == RawExportFormat.JSON,
                    onClick = { onFormatChanged(RawExportFormat.JSON) },
                )
            },
            { shape ->
                ChoiceRow(
                    shape = shape,
                    title = stringResource(R.string.raw_snapshot_format_ndjson),
                    description = stringResource(R.string.raw_snapshot_format_ndjson_description),
                    selected = settings.rawSnapshot.format == RawExportFormat.NDJSON,
                    onClick = { onFormatChanged(RawExportFormat.NDJSON) },
                )
            },
            { shape ->
                ContentRow(shape) {
                    HelperText(stringResource(R.string.raw_snapshot_one_artifact_note))
                }
            },
        ),
    )
    OptionsGroup(
        title = stringResource(R.string.raw_snapshot_scope_title),
        rows = listOf(
            { shape ->
                ChoiceRow(
                    shape = shape,
                    title = stringResource(R.string.raw_snapshot_scope_selected),
                    description = stringResource(R.string.raw_snapshot_scope_selected_description),
                    selected = settings.rawSnapshot.scope == RawSnapshotScope.SELECTED_RECORD_TYPES,
                    onClick = { onScopeChanged(RawSnapshotScope.SELECTED_RECORD_TYPES) },
                )
            },
            { shape ->
                ChoiceRow(
                    shape = shape,
                    title = stringResource(R.string.raw_snapshot_scope_all),
                    description = stringResource(R.string.raw_snapshot_scope_all_description),
                    selected = settings.rawSnapshot.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA,
                    onClick = { onScopeChanged(RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA) },
                )
            },
        ),
    )
    OptionsGroup(
        title = stringResource(R.string.raw_snapshot_routes_title),
        rows = listOf(
            { shape ->
                SwitchRow(
                    shape = shape,
                    title = stringResource(R.string.raw_snapshot_routes_control),
                    description = stringResource(R.string.raw_snapshot_routes_description),
                    checked = settings.rawSnapshot.includeExerciseRoutes,
                    onCheckedChange = onIncludeExerciseRoutesChanged,
                )
            },
        ),
    )
    OptionsGroup(
        title = null,
        rows = listOf(
            { shape ->
                ContentRow(shape) {
                    Text(
                        stringResource(R.string.raw_snapshot_immutable_destination_note),
                        style = GeistType.copy14,
                        color = colors.secondary,
                    )
                }
            },
        ),
    )
}

/**
 * A DESIGN.md list group without the Settings page's top inset (the More options column
 * already spaces its sections): an optional `heading-14` heading, then rows 2dp apart.
 */
@Composable
private fun OptionsGroup(
    title: String?,
    rows: List<@Composable (Shape) -> Unit>,
) {
    val colors = LocalGeistColors.current
    Column(Modifier.fillMaxWidth()) {
        if (title != null) {
            Text(
                text = title,
                style = GeistType.heading14,
                color = colors.brandPrimary,
                modifier = Modifier
                    .padding(start = GeistSpacing.space4, bottom = GeistSpacing.space2)
                    .semantics { heading() },
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            rows.forEachIndexed { index, row -> row(groupRowShape(index, rows.size)) }
        }
    }
}

/** A non-interactive group row for fields, chips and notes. */
@Composable
private fun ContentRow(shape: Shape, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(LocalGeistColors.current.background200)
            .padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        content = content,
    )
}

/** One whole-row radio action; the radio is indicator artwork, the description wraps below. */
@Composable
private fun ChoiceRow(
    shape: Shape,
    title: String,
    description: String?,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) colors.secondaryContainer else colors.background200)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .heightIn(min = if (description != null) 72.dp else 56.dp)
            .padding(start = GeistSpacing.space1, end = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(
            selected = selected,
            onClick = null,
            modifier = Modifier.size(48.dp),
            colors = RadioButtonDefaults.colors(
                selectedColor = colors.brandPrimary,
                unselectedColor = colors.gray.c900,
            ),
        )
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.label16, color = if (selected) colors.onSecondaryContainer else colors.primary)
            description?.let {
                Text(it, style = GeistType.copy14, color = if (selected) colors.onSecondaryContainer else colors.secondary)
            }
        }
    }
}

/** One whole-row switch action; the switch itself adds no second target. */
@Composable
private fun SwitchRow(
    shape: Shape,
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    description: String? = null,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
            .heightIn(min = if (description != null) 72.dp else 56.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.label16, color = colors.primary)
            description?.let { Text(it, style = GeistType.copy14, color = colors.secondary) }
        }
        AppSwitch(checked = checked, onCheckedChange = null)
    }
}

@Composable
private fun HelperText(text: String) {
    Text(text, style = GeistType.copy13, color = LocalGeistColors.current.secondary)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ExportFormatChips(
    selectedFormats: Set<ExportFormat>,
    onToggleExportFormat: (ExportFormat) -> Unit,
) {
    val colors = LocalGeistColors.current
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        ExportFormat.entries.forEach { format ->
            val selected = format in selectedFormats
            FilterChip(
                selected = selected,
                onClick = { onToggleExportFormat(format) },
                label = { Text(format.localizedDisplayName(), style = GeistType.button14) },
                leadingIcon = if (selected) {
                    { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(FilterChipDefaults.IconSize)) }
                } else {
                    null
                },
                shape = RoundedCornerShape(GeistRadii.small),
                colors = FilterChipDefaults.filterChipColors(
                    containerColor = colors.background200,
                    labelColor = colors.secondary,
                    selectedContainerColor = colors.secondaryContainer,
                    selectedLabelColor = colors.onSecondaryContainer,
                    selectedLeadingIconColor = colors.onSecondaryContainer,
                ),
                border = FilterChipDefaults.filterChipBorder(
                    enabled = true,
                    selected = selected,
                    borderColor = colors.gray.c500,
                    selectedBorderColor = colors.secondaryContainer,
                ),
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UnitSegmentedButtons(
    selected: UnitPreference,
    onSelected: (UnitPreference) -> Unit,
) {
    val colors = LocalGeistColors.current
    val options = UnitPreference.entries
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, pref ->
            SegmentedButton(
                selected = selected == pref,
                onClick = { onSelected(pref) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = colors.secondaryContainer,
                    activeContentColor = colors.onSecondaryContainer,
                    inactiveContainerColor = colors.background200,
                    inactiveContentColor = colors.primary,
                    activeBorderColor = colors.gray.c700,
                    inactiveBorderColor = colors.gray.c700,
                ),
            ) {
                Text(pref.localizedDisplayName(), style = GeistType.button14)
            }
        }
    }
}

@Composable
private fun optionsTextFieldColors(): TextFieldColors {
    val colors = LocalGeistColors.current
    return OutlinedTextFieldDefaults.colors(
        focusedBorderColor = colors.brandPrimary,
        unfocusedBorderColor = colors.gray.c700,
        focusedTextColor = colors.primary,
        unfocusedTextColor = colors.primary,
        focusedLabelColor = colors.brandPrimary,
        unfocusedLabelColor = colors.secondary,
        cursorColor = colors.brandPrimary,
    )
}

@Composable
private fun FolderOrganization.displayLabel(): String = stringResource(
    when (this) {
        FolderOrganization.FLAT -> R.string.folder_organization_flat_label
        FolderOrganization.BY_YEAR -> R.string.folder_organization_by_year_label
        FolderOrganization.BY_MONTH -> R.string.folder_organization_by_month_label
        FolderOrganization.BY_YEAR_MONTH -> R.string.folder_organization_by_year_month_label
    },
)

@Composable
private fun FolderOrganization.previewTemplate(): String = when (this) {
    FolderOrganization.FLAT -> stringResource(R.string.folder_organization_flat_preview)
    FolderOrganization.BY_YEAR -> "{year}"
    FolderOrganization.BY_MONTH -> "{month}"
    FolderOrganization.BY_YEAR_MONTH -> "{year}/{month}"
}
