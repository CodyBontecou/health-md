package com.healthmd.presentation.metrics

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.selection.triStateToggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.domain.model.HealthMetricDefinition
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Radii

internal object MetricSelectionTags {
    const val BACK = "metrics.back"
    const val SEARCH_ACTION = "metrics.search.action"
    const val LIST = "metrics.list"
    const val HEADER = "metrics.header"
    const val COUNT = "metrics.count"
    const val PROGRESS = "metrics.progress"
    const val SEARCH_LABEL = "metrics.search.label"
    const val SEARCH_FIELD = "metrics.search.field"
    const val BULK_ACTIONS = "metrics.bulk"
    const val SELECT_ALL = "metrics.selectAll"
    const val DESELECT_ALL = "metrics.deselectAll"
    fun expansion(category: HealthMetricCategory) = "metrics.category.${category.name}.expand"
    fun categoryName(category: HealthMetricCategory) = "metrics.category.${category.name}.name"
    fun categoryCount(category: HealthMetricCategory) = "metrics.category.${category.name}.count"
    fun categorySelection(category: HealthMetricCategory) = "metrics.category.${category.name}.select"
    fun metric(id: String) = "metrics.metric.$id"
    fun metricName(id: String) = "metrics.metric.$id.name"
    fun metricUnit(id: String) = "metrics.metric.$id.unit"
    fun metricIndicator(id: String) = "metrics.metric.$id.indicator"
}

@Composable
internal fun MetricSelectionSearchField(
    query: String,
    onQueryChanged: (String) -> Unit,
    requestFocus: Boolean,
    onFocusRequested: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val label = stringResource(R.string.search_metrics_hint)
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        // A wrapping external label cannot be ellipsized by a single-line field's
        // placeholder constraints, and leaves all of the input width for editing.
        Text(
            label, style = GeistType.copy16, color = colors.secondary,
            modifier = Modifier.fillMaxWidth().testTag(MetricSelectionTags.SEARCH_LABEL),
        )
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChanged,
            modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                .testTag(MetricSelectionTags.SEARCH_FIELD).focusRequester(focusRequester)
                .semantics { contentDescription = label },
            textStyle = GeistType.copy16,
            colors = metricTextFieldColors(),
            shape = RoundedCornerShape(Radii.textField),
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus(); keyboard?.hide() }),
        )
    }
    // The field may have been disposed by the lazy list. Request focus only after
    // the shortcut scrolls it back into composition and attaches its requester.
    LaunchedEffect(requestFocus) {
        if (requestFocus) {
            focusRequester.requestFocus()
            keyboard?.show()
            onFocusRequested()
        }
    }
}

/**
 * The tonal category header that opens a category's list group. Expansion never changes the
 * category's selection; its count keeps full-category meaning.
 */
@Composable
internal fun MetricSelectionCategoryExpansion(
    category: HealthMetricCategory,
    expanded: Boolean,
    enabledCount: Int,
    totalCount: Int,
    onExpand: () -> Unit,
    shape: Shape = RoundedCornerShape(GeistRadii.listGroup),
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val name = category.localizedDisplayName()
    val action = stringResource(
        if (expanded) R.string.a11y_metrics_collapse_category else R.string.a11y_metrics_expand_category,
        name,
    )
    val expandedState = stringResource(if (expanded) R.string.a11y_metrics_expanded else R.string.a11y_metrics_collapsed)
    Column(
        modifier = modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
            .testTag(MetricSelectionTags.expansion(category)).clip(shape)
            .background(colors.gray.c200)
            .clickable(role = Role.Button, onClickLabel = action, onClick = onExpand)
            .semantics { heading(); stateDescription = expandedState }
            // The name keeps (nearly) the full row width; the chevron sits on the count line.
            .padding(start = GeistSpacing.space3, end = GeistSpacing.space1, top = GeistSpacing.space3, bottom = GeistSpacing.space2),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
    ) {
        Text(
            name, style = GeistType.heading16, color = colors.primary,
            modifier = Modifier.fillMaxWidth().testTag(MetricSelectionTags.categoryName(category)),
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            Text(
                stringResource(R.string.metrics_enabled_category, enabledCount, totalCount),
                style = GeistType.copy13, color = colors.secondary,
                modifier = Modifier.weight(1f).testTag(MetricSelectionTags.categoryCount(category)),
            )
            Icon(
                if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null, tint = colors.secondary,
                modifier = Modifier.padding(end = GeistSpacing.space2).size(GeistSpacing.space6),
            )
        }
    }
}

/** One separately labeled tri-state checkbox, never nested in the expansion target. */
@Composable
internal fun MetricSelectionCategoryCheckbox(
    category: HealthMetricCategory,
    selection: MetricSelectionState,
    onToggle: () -> Unit,
    shape: Shape = RoundedCornerShape(GeistRadii.extraSmall),
) {
    val colors = LocalGeistColors.current
    val state = when {
        selection.isCategoryFullyEnabled(category) -> ToggleableState.On
        selection.isCategoryPartiallyEnabled(category) -> ToggleableState.Indeterminate
        else -> ToggleableState.Off
    }
    val description = stringResource(R.string.a11y_metrics_category_selection, category.localizedDisplayName())
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .testTag(MetricSelectionTags.categorySelection(category)).clip(shape)
            .background(colors.background200)
            .triStateToggleable(state = state, role = Role.Checkbox, onClick = onToggle)
            .semantics { contentDescription = description }
            .padding(horizontal = GeistSpacing.space3, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Text(stringResource(R.string.select_all), style = GeistType.button14, color = colors.primary,
            modifier = Modifier.weight(1f))
        TriStateCheckbox(state = state, onClick = null, colors = metricCheckboxColors(), modifier = Modifier.size(GeistSpacing.space6))
    }
}

/** Name, unit, and decorative checkbox share exactly one labeled toggle action. */
@Composable
internal fun MetricSelectionCheckbox(
    metric: HealthMetricDefinition,
    checked: Boolean,
    onToggle: () -> Unit,
    shape: Shape = RoundedCornerShape(GeistRadii.extraSmall),
) {
    val colors = LocalGeistColors.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val reading = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        // Reading-first rows give the name the full inner width, so their gutter stays narrow.
        val horizontal = if (reading) GeistSpacing.space2 else GeistSpacing.space3
        val target = Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .testTag(MetricSelectionTags.metric(metric.id)).clip(shape)
            .background(colors.background200)
            .toggleable(value = checked, role = Role.Checkbox, onValueChange = { onToggle() })
            .padding(horizontal = horizontal, vertical = GeistSpacing.space2)
        val indicator: @Composable () -> Unit = {
            Checkbox(
                checked = checked, onCheckedChange = null, colors = metricCheckboxColors(),
                modifier = Modifier.size(GeistSpacing.space6).testTag(MetricSelectionTags.metricIndicator(metric.id)),
            )
        }
        if (reading) {
            Column(target, verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
                MetricSelectionName(metric)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                    MetricSelectionUnit(metric, Modifier.weight(1f))
                    indicator()
                }
            }
        } else {
            Row(target, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
                    MetricSelectionName(metric)
                    if (metric.unit.isNotEmpty()) MetricSelectionUnit(metric)
                }
                indicator()
            }
        }
    }
}

@Composable
private fun MetricSelectionName(metric: HealthMetricDefinition) {
    val colors = LocalGeistColors.current
    Text(metric.localizedDisplayName(), style = GeistType.copy16,
        color = colors.primary,
        modifier = Modifier.fillMaxWidth().testTag(MetricSelectionTags.metricName(metric.id)))
}

@Composable
private fun MetricSelectionUnit(metric: HealthMetricDefinition, modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    if (metric.unit.isEmpty()) {
        Spacer(modifier)
    } else {
        Text(metric.unit, style = GeistType.copy13,
            color = colors.secondary,
            modifier = modifier.testTag(MetricSelectionTags.metricUnit(metric.id)))
    }
}

@Composable
private fun metricCheckboxColors(): CheckboxColors {
    val colors = LocalGeistColors.current
    return CheckboxDefaults.colors(
        checkedColor = colors.brandPrimary,
        uncheckedColor = colors.secondary,
        checkmarkColor = colors.brandOnPrimary,
    )
}

@Composable
private fun metricTextFieldColors(): TextFieldColors {
    val colors = LocalGeistColors.current
    return OutlinedTextFieldDefaults.colors(
        focusedBorderColor = colors.brandPrimary,
        unfocusedBorderColor = colors.gray.c700,
        focusedTextColor = colors.primary,
        unfocusedTextColor = colors.primary,
        cursorColor = colors.brandPrimary,
    )
}
