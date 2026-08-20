package com.healthmd.presentation.directcli

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.direct.DirectCliCompletion
import com.healthmd.direct.DirectCliConnectionState
import com.healthmd.direct.DirectCliFailure
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

object DirectCliTestTags {
    const val SCREEN = "direct_cli_screen"
    const val HOST = "direct_cli_host"
    const val PORT = "direct_cli_port"
    const val PAIRING_CODE = "direct_cli_pairing_code"
    const val PAIR = "direct_cli_pair"
    const val PAIRED_LISTENER = "direct_cli_paired_listener"
    const val SAVE_ENDPOINT = "direct_cli_save_endpoint"
    const val CONNECT = "direct_cli_connect"
    const val DISCONNECT = "direct_cli_disconnect"
    const val FORGET = "direct_cli_forget"
    const val STATUS = "direct_cli_status"
}

@Composable
fun DirectCliScreen(
    onBack: () -> Unit,
    viewModel: DirectCliViewModel = hiltViewModel(),
) {
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val connection by viewModel.connection.collectAsStateWithLifecycle()
    val protection = LocalConfigurationProtection.current

    fun configurationChange(action: () -> Unit) {
        if (protection.enabled) protection.onBlockedChange() else action()
    }

    LaunchedEffect(connection) {
        if (connection is DirectCliConnectionState.Completed) viewModel.refreshTrust()
    }

    DirectCliContent(
        ui = ui,
        connection = connection,
        onBack = onBack,
        onHostChange = { value -> configurationChange { viewModel.updateHost(value) } },
        onPortChange = { value -> configurationChange { viewModel.updatePort(value) } },
        onPairingCodeChange = { value -> configurationChange { viewModel.updatePairingCode(value) } },
        onPair = { configurationChange(viewModel::pair) },
        onSaveEndpoint = { configurationChange(viewModel::saveEndpoint) },
        onConnect = viewModel::connect,
        onDisconnect = viewModel::disconnect,
        onForget = { configurationChange(viewModel::forget) },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DirectCliContent(
    ui: DirectCliUiState,
    connection: DirectCliConnectionState,
    onBack: () -> Unit,
    onHostChange: (String) -> Unit,
    onPortChange: (String) -> Unit,
    onPairingCodeChange: (String) -> Unit,
    onPair: () -> Unit,
    onSaveEndpoint: () -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onForget: () -> Unit,
) {
    Scaffold(
        modifier = Modifier.testTag(DirectCliTestTags.SCREEN),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.direct_cli_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            GeistCard {
                Icon(Icons.Outlined.Computer, contentDescription = null, tint = AppColors.accent)
                Column(modifier = Modifier.padding(start = Spacing.sm)) {
                    Text(
                        stringResource(R.string.direct_cli_intro_title),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        stringResource(R.string.direct_cli_intro_body),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
            }

            if (!ui.hasTrust) {
                Text(
                    stringResource(R.string.direct_cli_pair_step_run),
                    style = MaterialTheme.typography.titleSmall,
                )
                CommandText("healthmd direct pair")
                Text(stringResource(R.string.direct_cli_pair_step_enter))
                OutlinedTextField(
                    value = ui.host,
                    onValueChange = onHostChange,
                    label = { Text(stringResource(R.string.direct_cli_computer_address)) },
                    placeholder = { Text("192.168.1.20") },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(DirectCliTestTags.HOST),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    OutlinedTextField(
                        value = ui.port,
                        onValueChange = onPortChange,
                        label = { Text(stringResource(R.string.direct_cli_port)) },
                        singleLine = true,
                        modifier = Modifier
                            .weight(1f)
                            .testTag(DirectCliTestTags.PORT),
                    )
                    OutlinedTextField(
                        value = ui.pairingCode,
                        onValueChange = onPairingCodeChange,
                        label = { Text(stringResource(R.string.direct_cli_pairing_code)) },
                        singleLine = true,
                        modifier = Modifier
                            .weight(1f)
                            .testTag(DirectCliTestTags.PAIRING_CODE),
                    )
                }
                Button(
                    onClick = onPair,
                    enabled = ui.canPair,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(DirectCliTestTags.PAIR),
                ) {
                    Text(stringResource(R.string.direct_cli_pair_button))
                }
            } else {
                Text(
                    stringResource(
                        R.string.direct_cli_paired_listener,
                        requireNotNull(ui.pairedListenerName),
                    ),
                    modifier = Modifier.testTag(DirectCliTestTags.PAIRED_LISTENER),
                    style = MaterialTheme.typography.titleMedium,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    OutlinedTextField(
                        value = ui.host,
                        onValueChange = onHostChange,
                        label = { Text(stringResource(R.string.direct_cli_computer_address)) },
                        singleLine = true,
                        modifier = Modifier
                            .weight(2f)
                            .testTag(DirectCliTestTags.HOST),
                    )
                    OutlinedTextField(
                        value = ui.port,
                        onValueChange = onPortChange,
                        label = { Text(stringResource(R.string.direct_cli_port)) },
                        singleLine = true,
                        modifier = Modifier
                            .weight(1f)
                            .testTag(DirectCliTestTags.PORT),
                    )
                }
                OutlinedButton(
                    onClick = onSaveEndpoint,
                    enabled = ui.host.isNotBlank() && ui.port.toIntOrNull() in 1..65_535,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(DirectCliTestTags.SAVE_ENDPOINT),
                ) {
                    Text(stringResource(R.string.direct_cli_save_address))
                }
                Text(stringResource(R.string.direct_cli_export_instruction))
                CommandText("healthmd export --raw --yesterday")
                CommandText("healthmd export --yesterday --destination /path/to/folder")
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Button(
                        onClick = onConnect,
                        modifier = Modifier
                            .weight(1f)
                            .testTag(DirectCliTestTags.CONNECT),
                    ) {
                        Text(stringResource(R.string.direct_cli_connect))
                    }
                    OutlinedButton(
                        onClick = onDisconnect,
                        modifier = Modifier
                            .weight(1f)
                            .testTag(DirectCliTestTags.DISCONNECT),
                    ) {
                        Text(stringResource(R.string.direct_cli_disconnect))
                    }
                }
                OutlinedButton(
                    onClick = onForget,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(DirectCliTestTags.FORGET),
                ) {
                    Text(stringResource(R.string.direct_cli_forget))
                }
            }

            Spacer(Modifier.height(Spacing.xs))
            Text(
                stringResource(R.string.direct_cli_status_title),
                style = MaterialTheme.typography.titleSmall,
            )
            Text(
                connectionText(connection),
                modifier = Modifier.testTag(DirectCliTestTags.STATUS),
                color = when (connection) {
                    is DirectCliConnectionState.Failed -> MaterialTheme.colorScheme.error
                    is DirectCliConnectionState.Completed -> AppColors.success
                    else -> AppColors.textSecondary
                },
            )
        }
    }
}

@Composable
private fun CommandText(command: String) {
    Text(
        text = command,
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        fontFamily = FontFamily.Monospace,
        style = MaterialTheme.typography.bodySmall,
        color = AppColors.textSecondary,
    )
}

@Composable
private fun connectionText(state: DirectCliConnectionState): String = when (state) {
    DirectCliConnectionState.Idle -> stringResource(R.string.direct_cli_status_not_connected)
    DirectCliConnectionState.Pairing -> stringResource(R.string.direct_cli_status_pairing)
    DirectCliConnectionState.WaitingForCli -> stringResource(R.string.direct_cli_status_connecting)
    is DirectCliConnectionState.Connected -> stringResource(
        R.string.direct_cli_status_connected,
        state.listenerName,
    )
    is DirectCliConnectionState.Transferring -> {
        val context = LocalContext.current
        stringResource(
            R.string.direct_cli_status_transferring,
            Formatter.formatFileSize(context, state.completedBytes.coerceAtLeast(0)),
            Formatter.formatFileSize(context, state.totalBytes.coerceAtLeast(0)),
        )
    }
    is DirectCliConnectionState.Completed -> when (val outcome = state.outcome) {
        is DirectCliCompletion.Paired -> stringResource(
            R.string.direct_cli_status_paired,
            outcome.listenerName,
        )
        DirectCliCompletion.SessionFinished -> stringResource(
            R.string.direct_cli_status_session_finished,
        )
        DirectCliCompletion.ExportCompleted -> stringResource(
            R.string.direct_cli_status_export_completed,
        )
        DirectCliCompletion.ExportCancelled -> stringResource(
            R.string.direct_cli_status_export_cancelled,
        )
    }
    is DirectCliConnectionState.Failed -> when (state.reason) {
        DirectCliFailure.PAIRING_FAILED,
        DirectCliFailure.CONNECTION_FAILED -> stringResource(R.string.direct_cli_failure_connection)
        DirectCliFailure.SESSION_TIMEOUT -> stringResource(R.string.direct_cli_failure_timeout)
        DirectCliFailure.QUOTA_EXHAUSTED -> stringResource(R.string.direct_cli_failure_quota)
        DirectCliFailure.FITBIT_RANGE_REQUIRED -> stringResource(
            R.string.direct_cli_failure_fitbit_range,
        )
        DirectCliFailure.PROFILE_NOT_FOUND -> stringResource(
            R.string.direct_cli_failure_profile_not_found,
        )
        DirectCliFailure.SOURCE_UNAVAILABLE -> stringResource(
            R.string.direct_cli_failure_source_unavailable,
        )
        DirectCliFailure.HEALTH_ACCESS_REQUIRED -> stringResource(
            R.string.direct_cli_failure_health_access,
        )
        DirectCliFailure.DEVICE_LOCKED -> stringResource(R.string.direct_cli_failure_device_locked)
        DirectCliFailure.HISTORICAL_ACCESS_REQUIRED -> stringResource(
            R.string.direct_cli_failure_historical_access,
        )
        DirectCliFailure.GENERATED_FILE_LIMIT -> stringResource(
            R.string.direct_cli_failure_file_limit,
        )
        DirectCliFailure.SPOOL_MISSING -> stringResource(R.string.direct_cli_failure_spool_missing)
        DirectCliFailure.EXPORT_FAILED -> stringResource(R.string.direct_cli_failure_export)
    }
}
