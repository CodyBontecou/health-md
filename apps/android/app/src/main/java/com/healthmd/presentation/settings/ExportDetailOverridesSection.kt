package com.healthmd.presentation.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportDetailSelection
import com.healthmd.domain.model.ExportDetailChoice
import com.healthmd.domain.model.ExportDetailGroup
import com.healthmd.domain.model.ExportSettings
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** Groups shown for the categories the export actually includes. */
internal fun ExportSettings.visibleDetailGroups(): List<ExportDetailGroup> {
    val types = effectiveDataTypeSelection()
    return ExportDetailGroup.entries.filter { types.includes(it) }
}

private fun DataTypeSelection.includes(group: ExportDetailGroup): Boolean = when (group) {
    ExportDetailGroup.SLEEP -> sleep
    ExportDetailGroup.ACTIVITY -> activity
    ExportDetailGroup.HEART -> heart
    ExportDetailGroup.VITALS -> vitals
    ExportDetailGroup.NUTRITION -> nutrition
    ExportDetailGroup.MOBILITY -> mobility
    ExportDetailGroup.REPRODUCTIVE_HEALTH -> reproductiveHealth
    ExportDetailGroup.MINDFULNESS -> mindfulness
    ExportDetailGroup.WORKOUTS -> workouts
    ExportDetailGroup.BODY -> body
}

/**
 * Per-category detail overrides as a list group: one row per included category with a segmented
 * choice. "Default" follows the global time-series switch; any other segment stores an explicit
 * override for that category only.
 */
@Composable
fun ExportDetailOverridesSection(
    settings: ExportSettings,
    onDetailChoiceChanged: (ExportDetailGroup, ExportDetailChoice?) -> Unit,
) {
    val groups = settings.visibleDetailGroups()
    if (groups.isEmpty()) return
    val colors = LocalGeistColors.current
    val overrides = settings.typedDetailOverrides()
    val showSchemaHint = settings.formatCustomization.compatibilitySchemaProfile == CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 &&
        groups.any { it in ExportDetailSelection.ANALYTICAL_EXPANSION_GROUPS }
    Column(Modifier.fillMaxWidth()) {
        SettingsGroupHeading(stringResource(R.string.detail_overrides_title))
        Text(
            stringResource(R.string.detail_overrides_description),
            style = GeistType.copy14,
            color = colors.secondary,
            modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space3),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            groups.forEachIndexed { index, group ->
                SettingsFieldRow(shape = groupRowShape(index, groups.size)) {
                    Text(stringResource(group.labelRes()), style = GeistType.label16, color = colors.primary)
                    SettingsSegmentedChoice(
                        options = listOf<ExportDetailChoice?>(null) + group.supportedChoices,
                        selected = overrides[group],
                        label = { option -> stringResource(option.labelRes()) },
                        onSelect = { option -> onDetailChoiceChanged(group, option) },
                        tag = { option -> "detail_${group.wireId}_${option?.wireId ?: "default"}" },
                    )
                    if (group == ExportDetailGroup.SLEEP) {
                        Text(
                            stringResource(R.string.detail_group_sleep_hint),
                            style = GeistType.copy14,
                            color = colors.secondary,
                        )
                    }
                }
            }
        }
        if (showSchemaHint) {
            Text(
                stringResource(R.string.detail_expansion_schema_hint),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier
                    .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space3)
                    .testTag("detail_expansion_schema_hint"),
            )
        }
    }
}

private fun ExportDetailGroup.labelRes(): Int = when (this) {
    ExportDetailGroup.SLEEP -> R.string.metric_category_sleep
    ExportDetailGroup.ACTIVITY -> R.string.metric_category_activity
    ExportDetailGroup.HEART -> R.string.metric_category_heart
    ExportDetailGroup.VITALS -> R.string.metric_category_vitals
    ExportDetailGroup.NUTRITION -> R.string.metric_category_nutrition
    ExportDetailGroup.MOBILITY -> R.string.metric_category_mobility
    ExportDetailGroup.REPRODUCTIVE_HEALTH -> R.string.metric_category_reproductive
    ExportDetailGroup.MINDFULNESS -> R.string.metric_category_mindfulness
    ExportDetailGroup.WORKOUTS -> R.string.metric_category_workouts
    ExportDetailGroup.BODY -> R.string.metric_category_body
}

private fun ExportDetailChoice?.labelRes(): Int = when (this) {
    null -> R.string.detail_choice_default
    ExportDetailChoice.SUMMARY -> R.string.detail_choice_summary
    ExportDetailChoice.SESSIONS -> R.string.detail_choice_sessions
    ExportDetailChoice.DETAILED -> R.string.detail_choice_detailed
}
