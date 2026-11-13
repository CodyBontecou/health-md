package com.healthmd.presentation.drive

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.drive.GoogleDriveAuthorizationAction
import com.healthmd.data.drive.GoogleDriveErrorId
import com.healthmd.data.drive.GoogleDriveReadiness
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun GoogleDriveSettingsCard(
    viewModel: GoogleDriveViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val protection = LocalConfigurationProtection.current
    val context = LocalContext.current
    val activity = context as? Activity
    val mainActivity = activity as? MainActivity
    val operationId = mainActivity?.googleDriveOperationId
    LaunchedEffect(operationId) {
        viewModel.setPendingOperation(operationId)
        if (operationId != null && mainActivity != null) {
            mainActivity.consumeGoogleDriveOperationId(operationId)
        }
    }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { result -> viewModel.finish(result.data) }

    var showConnectionDetails by rememberSaveable { mutableStateOf(false) }
    var showPrivacyDisclosure by rememberSaveable { mutableStateOf(false) }
    val connect: () -> Unit = {
        showConnectionDetails = false
        if (protection.enabled) {
            protection.onBlockedChange()
        } else {
            showPrivacyDisclosure = true
        }
    }
    val destination = state.destination
    if (destination == null) {
        GoogleDriveConnectionButton(
            text = stringResource(R.string.google_drive_connect),
            enabled = !state.busy && activity != null,
            busy = state.busy,
            onClick = connect,
        )
    } else {
        GeistCardClickable(
            onClick = { showConnectionDetails = true },
            modifier = Modifier.testTag("google_drive_settings"),
        ) {
            Image(
                painter = painterResource(R.drawable.google_drive_logo),
                contentDescription = null,
                modifier = Modifier.size(Spacing.lg),
            )
            Spacer(Modifier.width(Spacing.md))
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.google_drive_destination_label), style = MaterialTheme.typography.titleMedium)
                Text(destination.folderLabel, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
            }
            if (state.busy) {
                CircularProgressIndicator(Modifier.size(Spacing.lg))
            } else {
                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = AppColors.textMuted)
            }
        }
    }

    if (showConnectionDetails && destination != null) {
        AlertDialog(
            onDismissRequest = { showConnectionDetails = false },
            title = { Text(stringResource(R.string.google_drive_destination_label)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    Text(stringResource(R.string.google_drive_connected_destination, destination.accountLabel, destination.folderLabel))
                    GoogleDriveConnectionButton(
                        text = stringResource(R.string.google_drive_reauthorize),
                        enabled = !state.busy && activity != null,
                        onClick = connect,
                    )
                    SecondaryButton(
                        text = stringResource(R.string.google_drive_disconnect),
                        enabled = !state.busy,
                        onClick = {
                            showConnectionDetails = false
                            if (protection.enabled) protection.onBlockedChange() else viewModel.disconnect()
                        },
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showConnectionDetails = false }) { Text(stringResource(R.string.close)) }
            },
        )
    }
    if (showPrivacyDisclosure) {
        AlertDialog(
            onDismissRequest = { showPrivacyDisclosure = false },
            title = { Text(stringResource(R.string.google_drive_connect)) },
            text = {
                val unavailable = state.readiness as? GoogleDriveReadiness.Unavailable
                Text(unavailable?.error?.userText() ?: stringResource(R.string.google_drive_privacy_note))
            },
            confirmButton = {
                if (state.readiness is GoogleDriveReadiness.Ready) {
                    TextButton(onClick = {
                        showPrivacyDisclosure = false
                        viewModel.begin { action ->
                            if (action is GoogleDriveAuthorizationAction.Launch) {
                                launcher.launch(IntentSenderRequest.Builder(action.pendingIntent.intentSender).build())
                            }
                        }
                    }) { Text(stringResource(R.string.google_drive_connect)) }
                } else {
                    TextButton(onClick = { showPrivacyDisclosure = false }) { Text(stringResource(R.string.close)) }
                }
            },
            dismissButton = {
                if (state.readiness is GoogleDriveReadiness.Ready) {
                    TextButton(onClick = { showPrivacyDisclosure = false }) { Text(stringResource(R.string.cancel)) }
                }
            },
        )
    }
    state.error?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearError,
            title = { Text(stringResource(R.string.google_drive_destination_label)) },
            text = { Text(error.userText(), modifier = Modifier.testTag("google_drive_error_${error.name.lowercase()}")) },
            confirmButton = {
                TextButton(onClick = viewModel::clearError) { Text(stringResource(R.string.close)) }
            },
        )
    }
}

/** Original logo from https://developers.google.com/workspace/drive/api/guides/branding. */
@Composable
private fun GoogleDriveConnectionButton(
    text: String,
    enabled: Boolean,
    busy: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = LocalGeistColors.current
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = GeistSizes.controlLarge)
            .testTag("google_drive_connect"),
        shape = RoundedCornerShape(GeistRadii.full),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = colors.background100,
            contentColor = colors.gray.c1000,
            disabledContainerColor = colors.background100,
            disabledContentColor = colors.gray.c700,
        ),
        border = BorderStroke(1.dp, if (enabled) colors.gray.c700 else colors.gray.c300),
    ) {
        Image(
            painter = painterResource(R.drawable.google_drive_logo),
            contentDescription = null,
            modifier = Modifier.size(Spacing.lg),
            alpha = if (enabled) 1f else 0.38f,
        )
        Spacer(Modifier.width(Spacing.sm))
        Text(text, style = GeistType.button16)
        if (busy) {
            Spacer(Modifier.width(Spacing.sm))
            CircularProgressIndicator(Modifier.size(Spacing.lg))
        }
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
