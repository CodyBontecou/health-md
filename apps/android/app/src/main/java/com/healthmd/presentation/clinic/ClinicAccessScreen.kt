package com.healthmd.presentation.clinic

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.LinkOff
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.clinicsync.ClinicSyncState
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.diagnostics.ToolConfirmDialog
import com.healthmd.presentation.diagnostics.ToolFieldRow
import com.healthmd.presentation.diagnostics.ToolGroupFooter
import com.healthmd.presentation.diagnostics.ToolGroupHeading
import com.healthmd.presentation.diagnostics.ToolNote
import com.healthmd.presentation.diagnostics.ToolRows
import com.healthmd.presentation.diagnostics.ToolSwitchRow
import com.healthmd.presentation.theme.*

@Composable
fun ClinicAccessScreen(onDone: () -> Unit, viewModel: ClinicAccessViewModel = hiltViewModel()) {
    val status by viewModel.status.collectAsStateWithLifecycle()
    val busy by viewModel.busy.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val syncState by viewModel.syncRequestState.collectAsStateWithLifecycle()
    // Android 13+ asks for notification permission before a sync request doorbell is created.
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        viewModel.setSyncRequests(true)
    }
    var code by remember { mutableStateOf("") }
    var uploadToken by remember { mutableStateOf("") }
    var confirmDisconnect by remember { mutableStateOf(false) }
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.small)
    val secretKeyboard = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false)

    LaunchedEffect(Unit) { viewModel.refresh() }
    // Also shown at the app root before navigation exists, so it paints its own page surface.
    SubScreen(
        title = stringResource(R.string.m3_tools_clinic_title),
        onBack = onDone,
        modifier = Modifier.background(colors.background100).statusBarsPadding().navigationBarsPadding(),
    ) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8),
        ) {
            Text(stringResource(R.string.m3_tools_clinic_intro), style = GeistType.copy14, color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space4))
            if (status.storageUnavailable) {
                ToolNote(stringResource(R.string.m3_tools_clinic_storage_unavailable), Modifier.padding(top = GeistSpacing.space4), error = true)
            } else if (status.active) {
                ClinicHeader(status.clinicName ?: stringResource(R.string.m3_tools_clinic_fallback_name), status.endpoint.orEmpty())
                ToolGroupHeading(stringResource(R.string.m3_tools_clinic_sharing))
                ToolRows(listOf(
                    { rowShape ->
                        ToolSwitchRow(rowShape, stringResource(R.string.m3_tools_clinic_allow_sharing), status.sharingAuthorized,
                            enabled = !busy, tag = "clinic-sharing-toggle",
                            onCheckedChange = viewModel::setSharing)
                    },
                    { rowShape ->
                        ToolFieldRow(rowShape) {
                            OutlinedTextField(uploadToken, { uploadToken = it }, label = { Text(stringResource(R.string.m3_tools_clinic_upload_token)) },
                                visualTransformation = PasswordVisualTransformation(), enabled = !busy,
                                keyboardOptions = secretKeyboard,
                                modifier = Modifier.fillMaxWidth().testTag("clinic-upload-token"), shape = shape)
                            Text(stringResource(R.string.m3_tools_clinic_upload_token_description), style = GeistType.copy13, color = colors.secondary)
                        }
                    },
                ))
                ToolGroupFooter(stringResource(R.string.m3_tools_clinic_sharing_description))
                PrimaryButton(stringResource(R.string.m3_tools_clinic_use_destination),
                    onClick = { viewModel.useDestination(uploadToken) { uploadToken = ""; onDone() } },
                    enabled = status.sharingAuthorized && !busy,
                    modifier = Modifier.padding(top = GeistSpacing.space4).testTag("clinic-use-destination"))
                if (viewModel.syncRequestsAvailable) {
                    val syncEnabled = syncState == ClinicSyncState.Enabled
                    ToolGroupHeading(stringResource(R.string.m3_tools_clinic_sync_requests))
                    ToolRows(listOf { rowShape ->
                        ToolSwitchRow(rowShape, stringResource(R.string.m3_tools_clinic_allow_sync), syncEnabled,
                            enabled = syncState != ClinicSyncState.Updating && (syncEnabled || status.sharingAuthorized),
                            tag = "clinic-sync-requests-toggle",
                            onCheckedChange = { enable ->
                                if (enable && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                    notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                                } else {
                                    viewModel.setSyncRequests(enable)
                                }
                            })
                    })
                    ToolGroupFooter(stringResource(R.string.m3_tools_clinic_sync_description))
                    (syncState as? ClinicSyncState.Unavailable)?.let { unavailable ->
                        ToolNote(stringResource(syncUnavailableMessage(unavailable.reason)),
                            Modifier.padding(top = GeistSpacing.space3).testTag("clinic-sync-requests-message"))
                    }
                }
            } else if (status.configured && !status.enrollmentPending) {
                ToolGroupHeading(stringResource(R.string.m3_tools_clinic_invitation))
                ToolRows(listOf { rowShape ->
                    ToolFieldRow(rowShape) {
                        OutlinedTextField(code, { code = it }, label = { Text(stringResource(R.string.m3_tools_clinic_invitation_code)) },
                            visualTransformation = PasswordVisualTransformation(), enabled = !busy,
                            keyboardOptions = secretKeyboard,
                            modifier = Modifier.fillMaxWidth().testTag("clinic-invitation-code"), shape = shape)
                    }
                })
                PrimaryButton(stringResource(R.string.m3_tools_clinic_accept_invitation), onClick = { viewModel.enroll(code); code = "" },
                    enabled = code.isNotBlank() && !busy,
                    modifier = Modifier.padding(top = GeistSpacing.space4).testTag("clinic-accept-invitation"))
            } else if (!status.configured) {
                ToolNote(stringResource(R.string.m3_tools_clinic_not_configured), Modifier.padding(top = GeistSpacing.space4))
            }
            if (status.enrollmentPending) {
                ToolNote(stringResource(R.string.m3_tools_clinic_enrollment_pending), Modifier.padding(top = GeistSpacing.space4))
                PrimaryButton(stringResource(R.string.m3_tools_clinic_retry_enrollment), onClick = viewModel::resumeEnrollment,
                    enabled = !busy, modifier = Modifier.padding(top = GeistSpacing.space3))
            }
            if (status.clinicName != null || status.enrollmentPending) {
                Row(Modifier.fillMaxWidth().padding(top = GeistSpacing.space6),
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2), verticalAlignment = Alignment.CenterVertically) {
                    SecondaryButton(stringResource(R.string.m3_tools_clinic_refresh), onClick = viewModel::refresh, enabled = !busy)
                    TextButton(onClick = { confirmDisconnect = true }, enabled = !busy,
                        modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget).testTag("clinic-disconnect")) {
                        Text(stringResource(R.string.m3_tools_clinic_disconnect_clinic), style = GeistType.button14,
                            color = if (busy) colors.disabled else colors.error)
                    }
                }
            }
            if (busy) {
                Box(Modifier.fillMaxWidth().padding(top = GeistSpacing.space4), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.brandPrimary)
                }
            }
            if (error) ToolNote(stringResource(R.string.m3_tools_clinic_error),
                Modifier.padding(top = GeistSpacing.space4).testTag("clinic-access-message"), error = true)
        }
    }
    if (confirmDisconnect) ToolConfirmDialog(
        icon = Icons.Outlined.LinkOff,
        title = stringResource(R.string.m3_tools_clinic_disconnect_question),
        message = stringResource(R.string.m3_tools_clinic_disconnect_body),
        confirm = stringResource(R.string.m3_tools_clinic_disconnect),
        onDismiss = { confirmDisconnect = false },
        onConfirm = { confirmDisconnect = false; viewModel.disconnect() },
    )
}

/** The connected clinic and its approved endpoint on a tonal card. */
@Composable
private fun ClinicHeader(name: String, endpoint: String) {
    val colors = LocalGeistColors.current
    Row(
        Modifier.fillMaxWidth().padding(top = GeistSpacing.space4).clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.background200).padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(GeistSizes.control).background(colors.brandSubtle, androidx.compose.foundation.shape.CircleShape),
            contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.LocalHospital, contentDescription = null, tint = colors.brandOnSubtle, modifier = Modifier.size(22.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(name, style = GeistType.heading16, color = colors.primary)
            if (endpoint.isNotEmpty()) Text(endpoint, style = GeistType.copy13Mono, color = colors.secondary)
        }
    }
}

@StringRes
private fun syncUnavailableMessage(reason: ClinicSyncState.Reason): Int = when (reason) {
    ClinicSyncState.Reason.SHARING_REQUIRED -> R.string.m3_tools_clinic_sync_sharing_required
    ClinicSyncState.Reason.PUSH_UNAVAILABLE -> R.string.m3_tools_clinic_sync_push_unavailable
    ClinicSyncState.Reason.NOTIFICATIONS_DENIED -> R.string.m3_tools_clinic_sync_notifications_denied
    ClinicSyncState.Reason.WAKE_SERVICE -> R.string.m3_tools_clinic_sync_wake_service
    ClinicSyncState.Reason.CLINIC_UNREACHABLE -> R.string.m3_tools_clinic_sync_clinic_unreachable
    ClinicSyncState.Reason.STORAGE -> R.string.m3_tools_clinic_sync_storage
}
