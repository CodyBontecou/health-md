package com.healthmd.presentation.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import com.healthmd.R
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportDetailChoice
import com.healthmd.domain.model.ExportDetailGroup
import com.healthmd.domain.model.ExportSettings
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

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
}

/**
 * Per-category detail overrides. "Default" follows the global time-series switch; any other chip
 * stores an explicit override for that category only.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ExportDetailOverridesSection(
    settings: ExportSettings,
    onDetailChoiceChanged: (ExportDetailGroup, ExportDetailChoice?) -> Unit,
) {
    val groups = settings.visibleDetailGroups()
    if (groups.isEmpty()) return
    val overrides = settings.typedDetailOverrides()
    GeistCard {
        Text(
            stringResource(R.string.detail_overrides_title),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textPrimary,
            fontWeight = FontWeight.Medium,
        )
        Text(
            stringResource(R.string.detail_overrides_description),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textMuted,
        )
        for (group in groups) {
            Spacer(modifier = Modifier.height(Spacing.sm))
            Text(
                stringResource(group.labelRes()),
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textPrimary,
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                val options = listOf<ExportDetailChoice?>(null) + group.supportedChoices
                for (option in options) {
                    FilterChip(
                        selected = overrides[group] == option,
                        onClick = { onDetailChoiceChanged(group, option) },
                        label = { Text(stringResource(option.labelRes())) },
                        modifier = Modifier.testTag("detail_${group.wireId}_${option?.wireId ?: "default"}"),
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = AppColors.accentSubtle,
                            selectedLabelColor = AppColors.accent,
                        ),
                    )
                }
            }
            if (group == ExportDetailGroup.SLEEP) {
                Text(
                    stringResource(R.string.detail_group_sleep_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
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
}

private fun ExportDetailChoice?.labelRes(): Int = when (this) {
    null -> R.string.detail_choice_default
    ExportDetailChoice.SUMMARY -> R.string.detail_choice_summary
    ExportDetailChoice.SESSIONS -> R.string.detail_choice_sessions
    ExportDetailChoice.DETAILED -> R.string.detail_choice_detailed
}
