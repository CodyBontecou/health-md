package com.healthmd.presentation.drive

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.drive.GoogleDriveAuthorizationAction
import com.healthmd.data.drive.GoogleDriveErrorId
import com.healthmd.data.drive.GoogleDriveReadiness
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun GoogleDriveSettingsCard(
    viewModel: GoogleDriveViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = context as? Activity
    val operationId = activity?.intent?.getStringExtra(MainActivity.EXTRA_GOOGLE_DRIVE_OPERATION_ID)
    LaunchedEffect(operationId) { viewModel.setPendingOperation(operationId) }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { result -> viewModel.finish(result.data) }

    GeistCard(modifier = Modifier.testTag("google_drive_settings")) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Icon(Icons.Outlined.CloudUpload, contentDescription = null, tint = AppColors.accent)
            Column(modifier = Modifier.weight(1f)) {
                SectionLabel(stringResource(R.string.google_drive_title))
                Text(
                    text = when {
                        state.readiness is GoogleDriveReadiness.Unavailable ->
                            stringResource(R.string.google_drive_configuration_missing)
                        state.destination != null -> stringResource(
                            R.string.google_drive_connected_destination,
                            state.destination!!.accountLabel,
                            state.destination!!.folderLabel,
                        )
                        else -> stringResource(R.string.google_drive_description)
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
            if (state.busy) CircularProgressIndicator(modifier = Modifier.width(24.dp))
        }
        state.error?.let { error ->
            Text(
                text = error.userText(),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.error,
                modifier = Modifier.testTag("google_drive_error_${error.name.lowercase()}"),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            PrimaryButton(
                text = stringResource(
                    if (state.destination == null) R.string.google_drive_connect else R.string.google_drive_reauthorize,
                ),
                enabled = !state.busy && state.readiness is GoogleDriveReadiness.Ready && activity != null,
                onClick = {
                    viewModel.begin { action ->
                        if (action is GoogleDriveAuthorizationAction.Launch) {
                            launcher.launch(IntentSenderRequest.Builder(action.pendingIntent.intentSender).build())
                        }
                    }
                },
            )
            if (state.destination != null) {
                SecondaryButton(
                    text = stringResource(R.string.google_drive_disconnect),
                    enabled = !state.busy,
                    onClick = viewModel::disconnect,
                )
            }
        }
        Text(
            stringResource(R.string.google_drive_privacy_note),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textMuted,
        )
    }
}

@Composable
private fun GoogleDriveErrorId.userText(): String = stringResource(
    when (this) {
        GoogleDriveErrorId.CONFIGURATION_MISSING -> R.string.google_drive_configuration_missing
        GoogleDriveErrorId.REAUTHORIZATION_REQUIRED -> R.string.google_drive_error_reauthorization_required
        GoogleDriveErrorId.ACCOUNT_MISMATCH -> R.string.google_drive_error_account_mismatch
        GoogleDriveErrorId.FOLDER_UNAVAILABLE -> R.string.google_drive_error_folder_unavailable
        GoogleDriveErrorId.PERMISSION_DENIED -> R.string.google_drive_error_permission_denied
        GoogleDriveErrorId.REMOTE_CONFLICT -> R.string.google_drive_error_remote_conflict
        GoogleDriveErrorId.AMBIGUOUS_COMMIT -> R.string.google_drive_error_ambiguous_commit
        GoogleDriveErrorId.QUOTA_EXCEEDED -> R.string.google_drive_error_quota_exceeded
        GoogleDriveErrorId.RATE_LIMITED -> R.string.google_drive_error_rate_limited
        GoogleDriveErrorId.CHECKSUM_MISMATCH -> R.string.google_drive_error_checksum_mismatch
        GoogleDriveErrorId.PARTIAL_COMPLETION -> R.string.google_drive_error_partial_completion
    },
)
