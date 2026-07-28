package com.healthmd.presentation.export.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import com.healthmd.R
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.rawexport.ExportMode
import com.healthmd.presentation.theme.Spacing

@Composable
fun ExportProgressDialog(
    current: Int,
    total: Int,
    currentDate: String,
    exportMode: ExportMode,
    onCancel: () -> Unit,
) {
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
                        stateDescription = if (exportMode == ExportMode.RAW_SNAPSHOT) {
                            "$current of $total raw snapshot actions completed $currentDate"
                        } else {
                            "$current of $total days exported $currentDate"
                        }
                    },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    stringResource(
                        if (exportMode == ExportMode.RAW_SNAPSHOT) R.string.raw_snapshot_progress_count else R.string.export_progress_days,
                        current,
                        total,
                    ),
                    color = AppColors.textPrimary,
                    style = MaterialTheme.typography.bodyLarge,
                )
                if (currentDate.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(Spacing.xxs))
                    Text(currentDate, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
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
