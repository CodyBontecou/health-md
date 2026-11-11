package com.healthmd.presentation.schedule

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.data.export.EncryptedAPIExportCredentialStore
import com.healthmd.data.receivercoverage.ReceiverCoverageConfiguration
import com.healthmd.data.scheduler.ReceiverCoverageRuntime
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.GeistSpacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun ReceiverCoverageSettingsButton(scope: String, uploadUrl: String) {
    val context = LocalContext.current
    val protection = LocalConfigurationProtection.current
    val coroutineScope = rememberCoroutineScope()
    var showing by remember(scope) { mutableStateOf(false) }
    var enabled by remember(scope) { mutableStateOf(false) }
    var preflight by remember(scope) { mutableStateOf("") }
    var namespace by remember(scope) { mutableStateOf("") }
    var correction by remember(scope) { mutableStateOf("") }
    var error by remember(scope) { mutableStateOf(false) }
    var saving by remember(scope) { mutableStateOf(false) }
    TextButton(onClick = {
        if (protection.enabled) { protection.onBlockedChange(); return@TextButton }
        try {
            val config = ReceiverCoverageRuntime.configuration(context, scope)?.let(ReceiverCoverageConfiguration::parse)
            enabled = config != null; preflight = config?.preflightUrl.orEmpty(); namespace = config?.scopeId.orEmpty()
            correction = config?.refreshRecentDays?.toString().orEmpty(); error = false
        } catch (_: Exception) { error = true }
        showing = true
    }) { Text(stringResource(R.string.receiver_coverage_title)) }
    if (!showing) return
    AlertDialog(
        onDismissRequest = { if (!saving) showing = false },
        title = { Text(stringResource(R.string.receiver_coverage_title)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                Text(stringResource(R.string.receiver_coverage_enable))
                AppSwitch(enabled, { enabled = it }, enabled = !saving)
                Text(stringResource(R.string.receiver_coverage_default_note))
                if (enabled) {
                    OutlinedTextField(preflight, { preflight = it }, label = { Text(stringResource(R.string.receiver_coverage_url)) }, singleLine = true)
                    OutlinedTextField(namespace, { namespace = it }, label = { Text(stringResource(R.string.receiver_coverage_scope)) }, singleLine = true)
                    OutlinedTextField(correction, { correction = it }, label = { Text(stringResource(R.string.receiver_coverage_correction)) }, singleLine = true)
                    Text(stringResource(R.string.receiver_coverage_scope_note))
                    Text(stringResource(R.string.receiver_coverage_warning))
                    Text(stringResource(R.string.receiver_coverage_personal_only))
                }
                if (error) Text(stringResource(R.string.receiver_coverage_save_error), color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = {
            TextButton(enabled = !saving, onClick = {
                if (protection.enabled) { protection.onBlockedChange(); return@TextButton }
                val count = correction.toIntOrNull()
                if (enabled && count !in 0..30) { error = true; return@TextButton }
                saving = true
                coroutineScope.launch {
                    try {
                        ReceiverCoverageRuntime.save(context, scope,
                            if (enabled) ReceiverCoverageConfiguration(preflight, namespace, requireNotNull(count)) else null,
                            uploadUrl, EncryptedAPIExportCredentialStore(context))
                        showing = false
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (_: Exception) { error = true }
                    finally { saving = false }
                }
            }) { Text(stringResource(android.R.string.ok)) }
        },
        dismissButton = { TextButton(enabled = !saving, onClick = { showing = false }) { Text(stringResource(android.R.string.cancel)) } },
    )
}
