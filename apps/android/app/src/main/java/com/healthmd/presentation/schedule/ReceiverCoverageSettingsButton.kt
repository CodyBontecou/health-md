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
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.receivercoverage.ReceiverCoverageConfiguration
import com.healthmd.data.scheduler.ReceiverCoverageRuntime
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.GeistSpacing
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The app-wide credential store: its lock serializes key creation with background workers. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface ReceiverCoverageSettingsEntryPoint {
    fun apiExportCredentialStore(): APIExportCredentialStore
}

@Composable
fun ReceiverCoverageSettingsButton(scope: String, uploadUrl: String) {
    val context = LocalContext.current
    val protection = LocalConfigurationProtection.current
    val coroutineScope = rememberCoroutineScope()
    val view = LocalView.current
    val saveError = stringResource(R.string.receiver_coverage_save_error)
    var showing by remember(scope) { mutableStateOf(false) }
    var enabled by remember(scope) { mutableStateOf(false) }
    var preflight by remember(scope) { mutableStateOf("") }
    var namespace by remember(scope) { mutableStateOf("") }
    var correction by remember(scope) { mutableStateOf("") }
    var error by remember(scope) { mutableStateOf(false) }
    var saving by remember(scope) { mutableStateOf(false) }
    // Announce every failed attempt; a live region stays silent when the same error repeats.
    @Suppress("DEPRECATION")
    fun fail() { error = true; view.announceForAccessibility(saveError) }
    TextButton(onClick = {
        if (protection.enabled) { protection.onBlockedChange(); return@TextButton }
        try {
            val config = ReceiverCoverageRuntime.configuration(context, scope)?.let(ReceiverCoverageConfiguration::parse)
            enabled = config != null; preflight = config?.preflightUrl.orEmpty(); namespace = config?.scopeId.orEmpty()
            correction = config?.refreshRecentDays?.toString().orEmpty(); error = false
        } catch (_: Exception) { fail() }
        showing = true
    }) { Text(stringResource(R.string.receiver_coverage_title)) }
    if (!showing) return
    AlertDialog(
        onDismissRequest = { if (!saving) showing = false },
        title = { Text(stringResource(R.string.receiver_coverage_title)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                // First in the dialog so a failed OK is visible without scrolling.
                if (error) Text(saveError, color = MaterialTheme.colorScheme.error)
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
            }
        },
        confirmButton = {
            TextButton(enabled = !saving, onClick = {
                if (protection.enabled) { protection.onBlockedChange(); return@TextButton }
                error = false
                val count = correction.toIntOrNull()
                if (enabled && count !in 0..30) { fail(); return@TextButton }
                saving = true
                coroutineScope.launch {
                    try {
                        val credentials = EntryPointAccessors.fromApplication(context.applicationContext,
                            ReceiverCoverageSettingsEntryPoint::class.java).apiExportCredentialStore()
                        // Directory listing, atomic write and fsync stay off the main thread.
                        withContext(Dispatchers.IO) {
                            ReceiverCoverageRuntime.save(context, scope,
                                if (enabled) ReceiverCoverageConfiguration(preflight, namespace, requireNotNull(count)) else null,
                                uploadUrl, credentials)
                        }
                        showing = false
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (_: Exception) { fail() }
                    finally { saving = false }
                }
            }) { Text(stringResource(android.R.string.ok)) }
        },
        dismissButton = { TextButton(enabled = !saving, onClick = { showing = false }) { Text(stringResource(android.R.string.cancel)) } },
    )
}
