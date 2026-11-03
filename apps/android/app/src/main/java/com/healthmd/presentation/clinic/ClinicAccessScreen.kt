package com.healthmd.presentation.clinic

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.theme.*

@Composable
fun ClinicAccessScreen(onDone: () -> Unit, viewModel: ClinicAccessViewModel = hiltViewModel()) {
    val status by viewModel.status.collectAsStateWithLifecycle()
    val busy by viewModel.busy.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    var code by remember { mutableStateOf("") }
    var uploadToken by remember { mutableStateOf("") }
    var confirmDisconnect by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(GeistRadii.small)

    LaunchedEffect(Unit) { viewModel.refresh() }
    Column(Modifier.fillMaxSize().background(AppColors.bgPrimary).statusBarsPadding().navigationBarsPadding()
        .verticalScroll(rememberScrollState()).padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4)) {
        Text("Clinic access", style = GeistType.heading24, color = AppColors.textPrimary)
        Text("Your clinic can sponsor delivery to its approved endpoint. You choose what to share. Other export destinations require your own Health.md access.",
            style = GeistType.copy14, color = AppColors.textSecondary)
        if (status.storageUnavailable) {
            Text("Unlock your phone and try again. Clinic access could not be read securely.", style = GeistType.copy14)
        } else if (status.active) {
            GeistCard {
                Text(status.clinicName ?: "Clinic", style = GeistType.heading16)
                Text(status.endpoint.orEmpty(), style = GeistType.copy13Mono)
                Row {
                    Text("Allow sharing with this clinic", Modifier.weight(1f), style = GeistType.copy14)
                    Switch(checked = status.sharingAuthorized, onCheckedChange = viewModel::setSharing,
                        enabled = !busy, modifier = Modifier.testTag("clinic-sharing-toggle"))
                }
                Text("Only the metrics and dates you select in Health.md will be sent. Scheduling uses your saved selection. Turning sharing off stops future clinic uploads; it does not delete copies the clinic already received.",
                    style = GeistType.copy13, color = AppColors.textSecondary)
            }
            OutlinedTextField(uploadToken, { uploadToken = it }, label = { Text("Clinic upload token (optional)") },
                visualTransformation = PasswordVisualTransformation(), enabled = !busy,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth().testTag("clinic-upload-token"), shape = shape)
            Text("If your clinic supplies a personal upload token, enter it here. It is stored securely and used only for this clinic's approved endpoint.",
                style = GeistType.copy13, color = AppColors.textSecondary)
            Button(onClick = { viewModel.useDestination(uploadToken) { uploadToken = ""; onDone() } },
                enabled = status.sharingAuthorized && !busy, shape = shape,
                modifier = Modifier.fillMaxWidth().testTag("clinic-use-destination")) { Text("Use clinic destination") }
        } else if (status.configured && !status.enrollmentPending) {
            OutlinedTextField(code, { code = it }, label = { Text("Invitation code") },
                visualTransformation = PasswordVisualTransformation(), enabled = !busy,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth().testTag("clinic-invitation-code"), shape = shape)
            Button(onClick = { viewModel.enroll(code); code = "" }, enabled = code.isNotBlank() && !busy,
                shape = shape, modifier = Modifier.fillMaxWidth().testTag("clinic-accept-invitation")) { Text("Accept invitation") }
        } else if (!status.configured) {
            Text("Clinic access is not configured in this version of Health.md.", style = GeistType.copy14)
        }
        if (status.enrollmentPending) {
            Text("Your invitation is saved securely. Retry to finish enrollment; you do not need a new code.", style = GeistType.copy14)
            Button(onClick = viewModel::resumeEnrollment, enabled = !busy, shape = shape) { Text("Retry enrollment") }
        }
        if (status.clinicName != null || status.enrollmentPending) {
            OutlinedButton(onClick = viewModel::refresh, enabled = !busy, shape = shape) { Text("Refresh clinic access") }
            TextButton(onClick = { confirmDisconnect = true }, enabled = !busy,
                modifier = Modifier.testTag("clinic-disconnect")) { Text("Disconnect clinic") }
        }
        if (busy) CircularProgressIndicator(color = AppColors.accent)
        if (error) Text("Could not update clinic access. Check your connection, or retry your saved enrollment.",
            style = GeistType.copy14, modifier = Modifier.testTag("clinic-access-message"))
        TextButton(onClick = onDone) { Text("Done") }
    }
    if (confirmDisconnect) AlertDialog(onDismissRequest = { confirmDisconnect = false },
        title = { Text("Disconnect this clinic?") },
        text = { Text("Clinic-sponsored sharing will stop. Your own purchased access and local health data remain available.") },
        confirmButton = { TextButton(onClick = { confirmDisconnect = false; viewModel.disconnect() }) { Text("Disconnect") } },
        dismissButton = { TextButton(onClick = { confirmDisconnect = false }) { Text("Cancel") } })
}
