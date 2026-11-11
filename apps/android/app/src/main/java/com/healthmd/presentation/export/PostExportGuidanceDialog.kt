package com.healthmd.presentation.export

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import com.healthmd.R
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** A next step after successful work; opening a destination never enables or buys anything. */
@Composable
internal fun PostExportGuidanceDialog(
    milestone: Int,
    remaining: Int,
    onSchedule: () -> Unit,
    onUpgrade: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val isFirstExport = milestone == 1
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        icon = {
            Box(
                Modifier
                    .size(GeistSizes.controlLarge)
                    .background(colors.brandSubtle, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (isFirstExport) Icons.Outlined.Schedule else Icons.Outlined.WorkspacePremium,
                    contentDescription = null,
                    tint = colors.brandOnSubtle,
                )
            }
        },
        title = {
            Text(
                stringResource(if (isFirstExport) R.string.post_export_first_title else R.string.post_export_third_title),
                style = GeistType.heading20,
                color = colors.primary,
                textAlign = TextAlign.Center,
            )
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Text(
                    stringResource(if (isFirstExport) R.string.post_export_first_body else R.string.post_export_third_body),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
                Text(
                    pluralStringResource(R.plurals.free_exports_remaining, remaining, remaining),
                    style = GeistType.label14,
                    color = colors.primary,
                )
            }
        },
        // The next step is the one filled pill; the way out stacks below it as a text button so
        // long translations and large font scales wrap instead of squeezing side by side.
        confirmButton = {
            Column(
                Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
            ) {
                PrimaryButton(
                    text = stringResource(if (isFirstExport) R.string.post_export_schedule_action else R.string.post_export_upgrade_action),
                    onClick = if (isFirstExport) onSchedule else onUpgrade,
                )
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = GeistSizes.minimumTouchTarget),
                ) {
                    Text(
                        stringResource(if (isFirstExport) R.string.post_export_manual_action else R.string.post_export_continue_free),
                        style = GeistType.button14,
                        color = colors.brandPrimary,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        },
    )
}
