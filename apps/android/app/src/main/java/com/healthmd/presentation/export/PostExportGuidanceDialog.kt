package com.healthmd.presentation.export

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

/** A next step after successful work; opening a destination never enables or buys anything. */
@Composable
internal fun PostExportGuidanceDialog(
    milestone: Int,
    remaining: Int,
    onSchedule: () -> Unit,
    onUpgrade: () -> Unit,
    onDismiss: () -> Unit,
) {
    val isFirstExport = milestone == 1
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(if (isFirstExport) R.string.post_export_first_title else R.string.post_export_third_title)) },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(stringResource(if (isFirstExport) R.string.post_export_first_body else R.string.post_export_third_body))
                Text(
                    pluralStringResource(R.plurals.free_exports_remaining, remaining, remaining),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = if (isFirstExport) onSchedule else onUpgrade) {
                Text(stringResource(if (isFirstExport) R.string.post_export_schedule_action else R.string.post_export_upgrade_action))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(if (isFirstExport) R.string.post_export_manual_action else R.string.post_export_continue_free))
            }
        },
    )
}
