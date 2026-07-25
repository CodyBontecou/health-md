package com.healthmd.presentation.directcli

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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.direct.DirectCliConnectionState
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DirectCliScreen(
    onBack: () -> Unit,
    viewModel: DirectCliViewModel = hiltViewModel(),
) {
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val connection by viewModel.connection.collectAsStateWithLifecycle()

    LaunchedEffect(connection) {
        if (connection is DirectCliConnectionState.Completed) viewModel.refreshTrust()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Direct CLI") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                    Text("Encrypted desktop exports", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "The CLI listens on your computer. Health.md connects directly and sends the export without a cloud relay.",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
            }

            if (!ui.hasTrust) {
                Text("1. On your computer, run:", style = MaterialTheme.typography.titleSmall)
                CommandText("healthmd direct pair")
                Text("2. Enter the computer address and 20-digit Android code shown by the CLI.")
                OutlinedTextField(
                    value = ui.host,
                    onValueChange = viewModel::updateHost,
                    label = { Text("Computer address") },
                    placeholder = { Text("192.168.1.20") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    OutlinedTextField(
                        value = ui.port,
                        onValueChange = viewModel::updatePort,
                        label = { Text("Port") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = ui.pairingCode,
                        onValueChange = viewModel::updatePairingCode,
                        label = { Text("Pairing code") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                }
                Button(
                    onClick = viewModel::pair,
                    enabled = ui.canPair,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Pair with CLI")
                }
            } else {
                Text(
                    "Paired with ${ui.pairedListenerName}",
                    style = MaterialTheme.typography.titleMedium,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    OutlinedTextField(
                        value = ui.host,
                        onValueChange = viewModel::updateHost,
                        label = { Text("Computer address") },
                        singleLine = true,
                        modifier = Modifier.weight(2f),
                    )
                    OutlinedTextField(
                        value = ui.port,
                        onValueChange = viewModel::updatePort,
                        label = { Text("Port") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                }
                OutlinedButton(
                    onClick = viewModel::saveEndpoint,
                    enabled = ui.host.isNotBlank() && ui.port.toIntOrNull() in 1..65_535,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Save address")
                }
                Text("Run an export command on your computer, then tap Connect:")
                CommandText("healthmd export --raw --yesterday")
                CommandText("healthmd export --yesterday --destination /path/to/folder")
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Button(onClick = viewModel::connect, modifier = Modifier.weight(1f)) {
                        Text("Connect")
                    }
                    OutlinedButton(onClick = viewModel::disconnect, modifier = Modifier.weight(1f)) {
                        Text("Disconnect")
                    }
                }
                OutlinedButton(onClick = viewModel::forget, modifier = Modifier.fillMaxWidth()) {
                    Text("Forget paired CLI")
                }
            }

            Spacer(Modifier.height(Spacing.xs))
            Text("Status", style = MaterialTheme.typography.titleSmall)
            Text(
                connectionText(connection),
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

private fun connectionText(state: DirectCliConnectionState): String = when (state) {
    DirectCliConnectionState.Idle -> "Not connected"
    DirectCliConnectionState.Pairing -> "Pairing…"
    DirectCliConnectionState.WaitingForCli -> "Connecting…"
    is DirectCliConnectionState.Connected -> "Connected to ${state.listenerName}"
    is DirectCliConnectionState.Transferring -> "Transferring ${state.completedBytes} of ${state.totalBytes} bytes"
    is DirectCliConnectionState.Completed -> state.message
    is DirectCliConnectionState.Failed -> state.message
}
