package com.healthmd.presentation.export.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import com.healthmd.R
import androidx.compose.ui.text.font.FontWeight
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.rawexport.ExportMode
import com.healthmd.presentation.theme.Spacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@Composable
fun ExportProgressDialog(
    current: Int,
    total: Int,
    currentDate: LocalDate?,
    rangeStart: LocalDate,
    rangeEnd: LocalDate,
    exportMode: ExportMode,
    onCancel: () -> Unit,
) {
    val locale = LocalConfiguration.current.locales[0]
    val dateFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)
    val localizedCurrentDate = currentDate?.format(dateFormatter)
    val localizedRangeStart = rangeStart.format(dateFormatter)
    val localizedRangeEnd = rangeEnd.format(dateFormatter)
    val progressStateDescription = if (exportMode == ExportMode.RAW_SNAPSHOT) {
        pluralStringResource(
            R.plurals.export_progress_state_raw,
            total,
            current,
            total,
            localizedRangeStart,
            localizedRangeEnd,
        )
    } else if (localizedCurrentDate != null) {
        pluralStringResource(
            R.plurals.export_progress_state_days_with_date,
            total,
            current,
            total,
            localizedCurrentDate,
        )
    } else {
        pluralStringResource(
            R.plurals.export_progress_state_days,
            total,
            current,
            total,
        )
    }

    AlertDialog(
        onDismissRequest = {},
        containerColor = AppColors.bgTertiary,
        shape = RoundedCornerShape(Radii.card),
        title = {
            Text(
                stringResource(R.string.export_progress_title),
                color = AppColors.textPrimary,
                fontWeight = FontWeight.SemiBold,
            )
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        liveRegion = LiveRegionMode.Polite
                        stateDescription = progressStateDescription
                    },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    if (exportMode == ExportMode.RAW_SNAPSHOT) {
                        pluralStringResource(
                            R.plurals.raw_snapshot_progress_actions,
                            total,
                            current,
                            total,
                        )
                    } else {
                        pluralStringResource(
                            R.plurals.export_progress_days_count,
                            total,
                            current,
                            total,
                        )
                    },
                    color = AppColors.textPrimary,
                    style = MaterialTheme.typography.bodyLarge,
                )
                val visibleDate = if (exportMode == ExportMode.RAW_SNAPSHOT) {
                    stringResource(R.string.export_selected_range, localizedRangeStart, localizedRangeEnd)
                } else {
                    localizedCurrentDate
                }
                if (!visibleDate.isNullOrEmpty()) {
                    Spacer(modifier = Modifier.height(Spacing.xxs))
                    Text(visibleDate, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
                }
                Spacer(modifier = Modifier.height(Spacing.md))
                if (total > 0) {
                    LinearProgressIndicator(
                        progress = { current.toFloat() / total.toFloat() },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(Spacing.xs)
                            .clip(RoundedCornerShape(Radii.badge)),
                        color = AppColors.accent,
                        trackColor = AppColors.bgSecondary,
                    )
                } else {
                    LinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(Spacing.xs)
                            .clip(RoundedCornerShape(Radii.badge)),
                        color = AppColors.accent,
                        trackColor = AppColors.bgSecondary,
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onCancel) {
                Text(stringResource(R.string.action_cancel_export), color = AppColors.error)
            }
        },
    )
}
