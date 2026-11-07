package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.selection.triStateToggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.domain.model.HealthMetricDefinition
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.i18n.displayNameRes
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.text.NumberFormat

@Composable
fun IndividualTrackingScreen(
    settings: IndividualTrackingSettings,
    onSettingsChanged: (IndividualTrackingSettings) -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    var searchQuery by remember { mutableStateOf("") }
    var expandedCategories by remember { mutableStateOf(HealthMetrics.categories.toSet()) }
    val context = LocalContext.current
    val locale = context.resources.configuration.locales[0]
    val integerFormat = remember(locale) {
        NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false }
    }

    SubScreen(
        title = stringResource(R.string.individual_tracking_title),
        onBack = onBack,
        actions = {
            Text(
                "${integerFormat.format(settings.trackedMetricCount)}/${integerFormat.format(HealthMetrics.totalCount)}",
                style = GeistType.button14,
                color = colors.brandPrimary,
                modifier = Modifier.padding(end = GeistSpacing.space4),
            )
        },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().imePadding(),
            contentPadding = PaddingValues(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8),
            // Rows of one list group sit 2dp apart; headings add the space between groups.
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            item(key = "description") {
                Text(
                    stringResource(R.string.individual_tracking_description),
                    style = GeistType.copy14,
                    color = colors.secondary,
                    modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space4),
                )
            }

            item(key = "master_toggle") {
                SettingsToggleRow(
                    shape = RoundedCornerShape(GeistRadii.listGroup),
                    title = stringResource(R.string.individual_tracking_enable_title),
                    subtitle = pluralStringResource(
                        R.plurals.individual_tracking_metrics_count,
                        settings.trackedMetricCount,
                        settings.trackedMetricCount,
                    ),
                    checked = settings.globalEnabled,
                    onCheckedChange = { onSettingsChanged(settings.copy(globalEnabled = it)) },
                )
            }

            if (settings.globalEnabled) {
                item(key = "folder_heading") { SettingsGroupHeading(stringResource(R.string.section_file_organization)) }
                item(key = "folder_config") {
                    SettingsFieldRow(shape = groupRowShape(0, 3)) {
                        Text(stringResource(R.string.section_entries_folder), style = GeistType.label16, color = colors.primary)
                        OutlinedTextField(
                            value = settings.entriesFolder,
                            onValueChange = { onSettingsChanged(settings.copy(entriesFolder = it)) },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = GeistType.copy14Mono,
                            placeholder = { Text(stringResource(R.string.entries_folder_hint), style = GeistType.copy14Mono) },
                            colors = settingsTextFieldColors(),
                            shape = settingsTextFieldShape,
                            singleLine = true,
                        )
                    }
                }
                item(key = "filename_config") {
                    SettingsFieldRow(shape = groupRowShape(1, 3)) {
                        Text(stringResource(R.string.section_filename_template), style = GeistType.label16, color = colors.primary)
                        OutlinedTextField(
                            value = settings.filenameTemplate,
                            onValueChange = { onSettingsChanged(settings.copy(filenameTemplate = it)) },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = GeistType.copy14Mono,
                            placeholder = { Text(stringResource(R.string.individual_tracking_filename_hint), style = GeistType.copy14Mono) },
                            colors = settingsTextFieldColors(),
                            shape = settingsTextFieldShape,
                            singleLine = true,
                        )
                        Text(stringResource(R.string.individual_tracking_filename_tokens), style = GeistType.copy14, color = colors.secondary)
                    }
                }
                item(key = "organize_by_category") {
                    SettingsToggleRow(
                        shape = groupRowShape(2, 3),
                        title = stringResource(R.string.organize_by_category_title),
                        subtitle = stringResource(R.string.organize_by_category_subtitle),
                        checked = settings.organizeByCategory,
                        onCheckedChange = { onSettingsChanged(settings.copy(organizeByCategory = it)) },
                    )
                }

                item(key = "metrics_heading") { SettingsGroupHeading(stringResource(R.string.section_health_metrics)) }
                item(key = "search") {
                    val label = stringResource(R.string.search_metrics_hint)
                    Column(
                        Modifier.padding(bottom = GeistSpacing.space3),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    ) {
                        // The label wraps outside the field so the input keeps its full width.
                        Text(label, style = GeistType.copy14, color = colors.secondary, modifier = Modifier.padding(horizontal = GeistSpacing.space4))
                        OutlinedTextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            modifier = Modifier.fillMaxWidth().semantics { contentDescription = label },
                            textStyle = GeistType.copy16,
                            leadingIcon = { Icon(Icons.Outlined.Search, null, tint = colors.secondary) },
                            colors = settingsTextFieldColors(),
                            shape = settingsTextFieldShape,
                            singleLine = true,
                        )
                    }
                }
                item(key = "quick_actions") {
                    IndividualTrackingQuickActions(
                        onSuggested = { onSettingsChanged(settings.enableSuggested()) },
                        onAll = { onSettingsChanged(settings.enableAll()) },
                        onNone = { onSettingsChanged(settings.disableAll()) },
                    )
                }

                HealthMetrics.categories.forEach { category ->
                    val metrics = HealthMetrics.metricsForCategory(category)
                    val filteredMetrics = if (searchQuery.isBlank()) metrics else metrics.filter {
                        context.getString(it.displayNameRes()).contains(searchQuery, ignoreCase = true) ||
                            it.id.contains(searchQuery, ignoreCase = true)
                    }
                    if (filteredMetrics.isEmpty() && searchQuery.isNotBlank()) return@forEach

                    val isExpanded = searchQuery.isNotBlank() || category in expandedCategories
                    // One list group per category: tonal header, its tri-state row, then metrics.
                    val groupSize = 2 + if (isExpanded) filteredMetrics.size else 0

                    item(key = "category_${category.name}") {
                        TrackingCategoryHeader(
                            category = category,
                            expanded = isExpanded,
                            enabledCount = settings.enabledCountForCategory(category),
                            totalCount = settings.totalMetricCount(category),
                            onExpand = {
                                expandedCategories = if (category in expandedCategories) {
                                    expandedCategories - category
                                } else {
                                    expandedCategories + category
                                }
                            },
                            shape = groupRowShape(0, groupSize),
                            modifier = Modifier.padding(top = GeistSpacing.space4),
                        )
                    }
                    item(key = "category_${category.name}_select") {
                        TrackingCategoryCheckbox(
                            category = category,
                            state = when {
                                settings.isCategoryFullyEnabled(category) -> ToggleableState.On
                                settings.isCategoryPartiallyEnabled(category) -> ToggleableState.Indeterminate
                                else -> ToggleableState.Off
                            },
                            onToggle = { onSettingsChanged(settings.toggleCategory(category)) },
                            shape = groupRowShape(1, groupSize),
                        )
                    }
                    if (isExpanded) {
                        itemsIndexed(filteredMetrics, key = { _, metric -> "metric_${metric.id}" }) { index, metric ->
                            TrackingMetricRow(
                                metric = metric,
                                checked = settings.isMetricEnabled(metric.id),
                                suggested = IndividualTrackingSettings.isSuggested(metric.id),
                                onToggle = { onSettingsChanged(settings.toggleMetric(metric.id)) },
                                shape = groupRowShape(index + 2, groupSize),
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Suggested / All / None, reflowing to full-width stacked buttons when they would crowd. */
@Composable
private fun IndividualTrackingQuickActions(onSuggested: () -> Unit, onAll: () -> Unit, onNone: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stack = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        val buttons: @Composable (Modifier) -> Unit = { modifier ->
            SecondaryButton(text = stringResource(R.string.action_suggested), onClick = onSuggested, modifier = modifier)
            SecondaryButton(text = stringResource(R.string.action_all), onClick = onAll, modifier = modifier)
            SecondaryButton(text = stringResource(R.string.action_none), onClick = onNone, modifier = modifier)
        }
        if (stack) {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) { buttons(Modifier.fillMaxWidth()) }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) { buttons(Modifier.weight(1f)) }
        }
    }
}

/** The tonal header opening a category group; expanding never changes the selection. */
@Composable
private fun TrackingCategoryHeader(
    category: HealthMetricCategory,
    expanded: Boolean,
    enabledCount: Int,
    totalCount: Int,
    onExpand: () -> Unit,
    shape: Shape,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val name = category.localizedDisplayName()
    val action = stringResource(
        if (expanded) R.string.a11y_metrics_collapse_category else R.string.a11y_metrics_expand_category,
        name,
    )
    val expandedState = stringResource(if (expanded) R.string.a11y_metrics_expanded else R.string.a11y_metrics_collapsed)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = GeistSizes.minimumTouchTarget)
            .clip(shape)
            .background(colors.gray.c200)
            .clickable(role = Role.Button, onClickLabel = action, onClick = onExpand)
            .semantics { heading(); stateDescription = expandedState }
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(Modifier.weight(1f)) {
            Text(name, style = GeistType.heading16, color = colors.primary)
            Text(
                stringResource(R.string.metrics_enabled_category, enabledCount, totalCount),
                style = GeistType.copy13,
                color = colors.secondary,
            )
        }
        Icon(
            if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
            contentDescription = null,
            tint = colors.secondary,
        )
    }
}

/** The category's separately labeled tri-state checkbox, never nested in the header. */
@Composable
private fun TrackingCategoryCheckbox(
    category: HealthMetricCategory,
    state: ToggleableState,
    onToggle: () -> Unit,
    shape: Shape,
) {
    val colors = LocalGeistColors.current
    val description = stringResource(R.string.a11y_metrics_category_selection, category.localizedDisplayName())
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(colors.background200)
            .triStateToggleable(state = state, role = Role.Checkbox, onClick = onToggle)
            .semantics { contentDescription = description }
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Text(stringResource(R.string.select_all), style = GeistType.button14, color = colors.primary, modifier = Modifier.weight(1f))
        TriStateCheckbox(state = state, onClick = null, colors = trackingCheckboxColors())
    }
}

/** One whole-row checkbox per metric: name, suggested badge, unit (or id) and indicator. */
@Composable
private fun TrackingMetricRow(
    metric: HealthMetricDefinition,
    checked: Boolean,
    suggested: Boolean,
    onToggle: () -> Unit,
    shape: Shape,
) {
    val colors = LocalGeistColors.current
    val content = colors.primary
    val supporting = colors.secondary
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(colors.background200)
            .toggleable(value = checked, role = Role.Checkbox, onValueChange = { onToggle() })
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(metric.localizedDisplayName(), style = GeistType.label16, color = content)
            if (suggested) {
                Text(
                    stringResource(R.string.individual_tracking_suggested_badge),
                    style = GeistType.label12,
                    color = colors.brandOnSubtle,
                    modifier = Modifier
                        .clip(RoundedCornerShape(GeistRadii.full))
                        .background(colors.brandSubtle)
                        .padding(horizontal = GeistSpacing.space2, vertical = 2.dp),
                )
            }
            if (metric.unit.isNotEmpty()) {
                Text(metric.unit, style = GeistType.copy13, color = supporting)
            } else {
                Text(metric.id, style = GeistType.copy13Mono, color = supporting)
            }
        }
        Checkbox(checked = checked, onCheckedChange = null, colors = trackingCheckboxColors())
    }
}

@Composable
private fun trackingCheckboxColors(): CheckboxColors {
    val colors = LocalGeistColors.current
    return CheckboxDefaults.colors(
        checkedColor = colors.brandPrimary,
        uncheckedColor = colors.secondary,
        checkmarkColor = colors.brandOnPrimary,
    )
}
