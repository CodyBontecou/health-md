package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Radii

@Composable
fun AdvancedSettingsScreen(
    settings: ExportSettings,
    sleepDayAttribution: SleepDayAttribution,
    onNavigateToMetrics: () -> Unit,
    onNavigateToFormatCustomization: () -> Unit,
    onNavigateToDailyNoteInjection: () -> Unit,
    onNavigateToIndividualTracking: () -> Unit,
    onIncludeGranularDataChanged: (Boolean) -> Unit,
    onDetailChoiceChanged: (ExportDetailGroup, ExportDetailChoice?) -> Unit,
    onSleepDayAttributionChanged: (SleepDayAttribution) -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    SubScreen(title = stringResource(R.string.advanced_settings_title), onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8),
        ) {
            val selectedFormatNames = buildList {
                if (ExportFormat.MARKDOWN in settings.selectedExportFormats) add(stringResource(R.string.format_display_markdown))
                if (ExportFormat.OBSIDIAN_BASES in settings.selectedExportFormats) add(stringResource(R.string.format_display_obsidian_bases))
                if (ExportFormat.JSON in settings.selectedExportFormats) add(stringResource(R.string.format_display_json))
                if (ExportFormat.CSV in settings.selectedExportFormats) add(stringResource(R.string.format_display_csv))
            }
            val formatSummary = selectedFormatNames.joinToString(", ").ifBlank {
                stringResource(R.string.advanced_settings_no_formats_selected)
            }
            val writeModeSummary = stringResource(R.string.write_mode_summary, settings.writeMode.localizedDisplayName())
            val metricsSummary = pluralStringResource(
                R.plurals.metrics_enabled_summary,
                settings.metricSelection.enabledCount,
                settings.metricSelection.enabledCount,
                HealthMetrics.totalCount,
            )
            val customizationSummary = "${settings.formatCustomization.dateFormat.localizedDisplayName()} • " +
                settings.formatCustomization.unitPreference.localizedDisplayName()

            SettingsGroup(
                title = stringResource(R.string.section_export_format),
                rows = listOf(
                    { shape ->
                        SettingsRow(
                            shape = shape,
                            title = stringResource(R.string.section_health_metrics),
                            subtitle = metricsSummary,
                            icon = Icons.Outlined.Checklist,
                            onClick = onNavigateToMetrics,
                        )
                    },
                    { shape ->
                        // A read-only summary of the export's formats; it is not an action.
                        SettingsRow(
                            shape = shape,
                            title = stringResource(R.string.section_current_format),
                            subtitle = "$formatSummary\n$writeModeSummary",
                            icon = Icons.Outlined.Description,
                            onClick = null,
                        )
                    },
                    { shape ->
                        SettingsRow(
                            shape = shape,
                            title = stringResource(R.string.section_format_customization),
                            subtitle = customizationSummary,
                            icon = Icons.Outlined.Tune,
                            onClick = onNavigateToFormatCustomization,
                        )
                    },
                ),
            )

            SettingsGroup(
                title = stringResource(R.string.m3_advanced_group_notes),
                rows = listOf(
                    { shape ->
                        SettingsRow(
                            shape = shape,
                            title = stringResource(R.string.section_daily_note_injection),
                            subtitle = if (settings.dailyNoteInjection.enabled) {
                                stringResource(R.string.daily_note_enabled_summary, settings.dailyNoteInjection.folderPath)
                            } else {
                                stringResource(R.string.daily_note_disabled)
                            },
                            icon = Icons.Outlined.EditNote,
                            onClick = onNavigateToDailyNoteInjection,
                        )
                    },
                    { shape ->
                        SettingsRow(
                            shape = shape,
                            title = stringResource(R.string.section_individual_tracking),
                            subtitle = if (settings.individualTracking.globalEnabled) {
                                pluralStringResource(
                                    R.plurals.individual_tracking_enabled_summary,
                                    settings.individualTracking.trackedMetricCount,
                                    settings.individualTracking.trackedMetricCount,
                                )
                            } else {
                                stringResource(R.string.daily_note_disabled)
                            },
                            icon = Icons.Outlined.FormatListNumbered,
                            onClick = onNavigateToIndividualTracking,
                        )
                    },
                ),
            )

            // Sleep Day Attribution (issue #104): which daily note owns a
            // midnight-spanning sleep session. Device-local capture preference,
            // applied to every Health Connect capture path and widgets.
            SettingsGroup(
                title = stringResource(R.string.sleep_attribution_title),
                rows = listOf(
                    { shape ->
                        SettingsFieldRow(shape = shape) {
                            SettingsSegmentedChoice(
                                options = listOf(SleepDayAttribution.NIGHT_BEGINS, SleepDayAttribution.MORNING_ENDS),
                                selected = sleepDayAttribution,
                                label = { mode ->
                                    stringResource(
                                        when (mode) {
                                            SleepDayAttribution.NIGHT_BEGINS -> R.string.sleep_attribution_night_begins
                                            SleepDayAttribution.MORNING_ENDS -> R.string.sleep_attribution_morning_ends
                                        },
                                    )
                                },
                                onSelect = onSleepDayAttributionChanged,
                                enabled = { it.isAvailableForShippedProfiles },
                                tag = { "sleep_attribution_${it.wireValue}" },
                            )
                            Text(
                                stringResource(
                                    when (sleepDayAttribution) {
                                        SleepDayAttribution.NIGHT_BEGINS -> R.string.sleep_attribution_night_begins_description
                                        SleepDayAttribution.MORNING_ENDS -> if (sleepDayAttribution.isAvailableForShippedProfiles) {
                                            R.string.sleep_attribution_morning_ends_wake_description
                                        } else R.string.sleep_attribution_morning_ends_description
                                    },
                                ),
                                style = GeistType.copy14,
                                color = colors.secondary,
                            )
                        }
                    },
                ),
            )

            SettingsGroup(
                title = stringResource(R.string.m3_advanced_group_detail),
                rows = listOf(
                    { shape ->
                        SettingsToggleRow(
                            shape = shape,
                            title = stringResource(R.string.granular_data_title),
                            subtitle = stringResource(R.string.granular_data_description),
                            checked = settings.includeGranularData,
                            onCheckedChange = onIncludeGranularDataChanged,
                        )
                    },
                ),
            )

            ExportDetailOverridesSection(settings = settings, onDetailChoiceChanged = onDetailChoiceChanged)
        }
    }
}

/** A list-group heading for groups composed outside [SettingsGroup] (lazy lists, custom rows). */
@Composable
internal fun SettingsGroupHeading(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = GeistType.heading14,
        color = LocalGeistColors.current.brandPrimary,
        modifier = modifier
            .padding(start = GeistSpacing.space4, top = GeistSpacing.space6, bottom = GeistSpacing.space2)
            .semantics { heading() },
    )
}

/**
 * A list-group row whose whole surface is one labeled switch action (DESIGN.md row-level
 * toggles): title and optional description, with a non-interactive [AppSwitch] trailing.
 */
@Composable
internal fun SettingsToggleRow(
    shape: Shape,
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange)
            .heightIn(min = if (subtitle != null) 72.dp else 56.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.label16, color = if (enabled) colors.primary else colors.disabled)
            subtitle?.let { Text(it, style = GeistType.copy14, color = colors.secondary) }
        }
        AppSwitch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

/** A list-group row holding inline controls (fields, segmented choices) with 16dp padding. */
@Composable
internal fun SettingsFieldRow(
    shape: Shape,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(LocalGeistColors.current.background200)
            .padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        content = content,
    )
}

/** Outlined text-field colors on a tonal list-group row. */
@Composable
internal fun settingsTextFieldColors(): TextFieldColors {
    val colors = LocalGeistColors.current
    return OutlinedTextFieldDefaults.colors(
        focusedBorderColor = colors.brandPrimary,
        unfocusedBorderColor = colors.gray.c700,
        focusedTextColor = colors.primary,
        unfocusedTextColor = colors.primary,
        cursorColor = colors.brandPrimary,
        focusedPlaceholderColor = colors.secondary,
        unfocusedPlaceholderColor = colors.secondary,
    )
}

internal val settingsTextFieldShape = RoundedCornerShape(Radii.textField)

/**
 * A small exclusive choice (2–5 options) as Material 3 segmented buttons. When the segments
 * would be too narrow for their labels at the current font scale, the same choice reflows into
 * full-width radio rows so no label is truncated.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun <T> SettingsSegmentedChoice(
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    enabled: (T) -> Boolean = { true },
    tag: (T) -> String? = { null },
) {
    val colors = LocalGeistColors.current
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val fontScale = LocalDensity.current.fontScale
        val segmentWidth = maxWidth.value / options.size
        val reflow = segmentWidth / fontScale < MIN_SEGMENT_WIDTH_DP ||
            GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, fontScale) && options.size > 2
        if (reflow) {
            Column(Modifier.fillMaxWidth().selectableGroup()) {
                options.forEach { option ->
                    val isSelected = option == selected
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .clip(RoundedCornerShape(GeistRadii.small))
                            .selectable(
                                selected = isSelected,
                                enabled = enabled(option),
                                role = Role.RadioButton,
                                onClick = { onSelect(option) },
                            )
                            .then(tag(option)?.let { Modifier.testTag(it) } ?: Modifier)
                            .padding(horizontal = GeistSpacing.space1),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = null,
                            enabled = enabled(option),
                            colors = RadioButtonDefaults.colors(
                                selectedColor = colors.brandPrimary,
                                unselectedColor = colors.secondary,
                            ),
                        )
                        Text(
                            label(option),
                            style = GeistType.label16,
                            color = if (enabled(option)) colors.primary else colors.disabled,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        } else {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                options.forEachIndexed { index, option ->
                    SegmentedButton(
                        selected = option == selected,
                        onClick = { onSelect(option) },
                        enabled = enabled(option),
                        shape = SegmentedButtonDefaults.itemShape(index, options.size),
                        colors = SegmentedButtonDefaults.colors(
                            activeContainerColor = colors.secondaryContainer,
                            activeContentColor = colors.onSecondaryContainer,
                            inactiveContainerColor = colors.background200,
                            inactiveContentColor = colors.primary,
                            activeBorderColor = colors.gray.c700,
                            inactiveBorderColor = colors.gray.c700,
                            disabledInactiveContainerColor = colors.background200,
                            disabledInactiveContentColor = colors.disabled,
                            disabledInactiveBorderColor = colors.gray.c500,
                        ),
                        // Three or more segments give the check's width back to the label.
                        icon = if (options.size > 2) ({}) else ({ SegmentedButtonDefaults.Icon(option == selected) }),
                        modifier = Modifier
                            .heightIn(min = 48.dp)
                            .then(tag(option)?.let { Modifier.testTag(it) } ?: Modifier),
                    ) {
                        Text(label(option), style = GeistType.button14)
                    }
                }
            }
        }
    }
}

private const val MIN_SEGMENT_WIDTH_DP = 76f
