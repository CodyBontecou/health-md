package com.healthmd.presentation.schedule

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import com.healthmd.R
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing

internal object ScheduleHistoryTags {
    const val HEADING = "schedule.history.heading"
    const val TITLE = "schedule.history.title"
    const val CLEAR = "schedule.history.clear"
}

/** Only requests confirmation; the caller retains its guard and the confirmed deletion policy. */
@Composable
internal fun ScheduleHistoryHeading(
    onRequestClearHistory: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier.fillMaxWidth().testTag(ScheduleHistoryTags.HEADING)) {
        if (GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                HistoryTitle(Modifier.fillMaxWidth())
                ClearHistoryButton(onRequestClearHistory, Modifier.fillMaxWidth())
            }
        } else {
            Row(
                horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                HistoryTitle(Modifier.weight(1f))
                ClearHistoryButton(onRequestClearHistory, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun HistoryTitle(modifier: Modifier) {
    Text(
        text = stringResource(R.string.section_export_history),
        style = MaterialTheme.typography.titleMedium,
        color = AppColors.textSecondary,
        fontWeight = FontWeight.Medium,
        modifier = modifier.testTag(ScheduleHistoryTags.TITLE).semantics { heading() },
    )
}

@Composable
private fun ClearHistoryButton(onRequestClearHistory: () -> Unit, modifier: Modifier) {
    ConfigurationProtectedRegion(modifier) {
        TextButton(
            onClick = onRequestClearHistory,
            modifier = Modifier.fillMaxWidth().testTag(ScheduleHistoryTags.CLEAR)
                .sizeIn(minWidth = GeistSizes.minimumTouchTarget, minHeight = GeistSizes.minimumTouchTarget),
            shape = RoundedCornerShape(Radii.button),
            contentPadding = PaddingValues(horizontal = Spacing.sm, vertical = Spacing.xs),
            colors = ButtonDefaults.textButtonColors(contentColor = AppColors.textSecondary),
        ) {
            Text(
                text = stringResource(R.string.action_clear_history),
                style = MaterialTheme.typography.titleSmall,
            )
        }
    }
}
