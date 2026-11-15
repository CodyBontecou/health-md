package com.healthmd.presentation.directcli

import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.direct.DirectCliCompletion
import com.healthmd.direct.DirectCliConnectionState
import com.healthmd.direct.DirectCliFailure
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.diagnostics.ToolFieldRow
import com.healthmd.presentation.diagnostics.ToolGroupHeading
import com.healthmd.presentation.diagnostics.ToolRow
import com.healthmd.presentation.diagnostics.ToolRows
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

object DirectCliTestTags {
    const val SCREEN = "direct_cli_screen"
    const val HOST = "direct_cli_host"
    const val PORT = "direct_cli_port"
    const val PAIRING_CODE = "direct_cli_pairing_code"
    const val PAIR = "direct_cli_pair"
    const val SCAN_QR = "direct_cli_scan_qr"
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
    var showPairingScanner by rememberSaveable { mutableStateOf(false) }

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
        onScanQr = { configurationChange { showPairingScanner = true } },
        onPair = { configurationChange(viewModel::pair) },
        onSaveEndpoint = { configurationChange(viewModel::saveEndpoint) },
        onConnect = viewModel::connect,
        onDisconnect = viewModel::disconnect,
        onForget = { configurationChange(viewModel::forget) },
        agentPermissionsSetup = { AgentExportPermissionsSetupCard() },
    )
    if (showPairingScanner) {
        DirectCliPairingScanner(
            onPairingLink = { link ->
                showPairingScanner = false
                viewModel.pair(link)
            },
            onDismiss = { showPairingScanner = false },
        )
    }
}

@Composable
fun DirectCliContent(
    ui: DirectCliUiState,
    connection: DirectCliConnectionState,
    onBack: () -> Unit,
    onHostChange: (String) -> Unit,
    onPortChange: (String) -> Unit,
    onPairingCodeChange: (String) -> Unit,
    onScanQr: () -> Unit,
    onPair: () -> Unit,
    onSaveEndpoint: () -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onForget: () -> Unit,
    agentPermissionsSetup: @Composable () -> Unit = {},
) {
    val colors = LocalGeistColors.current
    val fieldShape = RoundedCornerShape(GeistRadii.small)
    SubScreen(
        title = stringResource(R.string.direct_cli_title),
        onBack = onBack,
        modifier = Modifier.testTag(DirectCliTestTags.SCREEN),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8),
        ) {
            DirectCliStatusCard(connection)

            agentPermissionsSetup()

            if (!ui.hasTrust) {
                ToolGroupHeading(stringResource(R.string.m3_tools_direct_cli_pairing))
                ToolRows(
                    listOf(
                        { shape ->
                            ToolFieldRow(shape) {
                                Text(stringResource(R.string.direct_cli_pair_step_run), style = GeistType.label14, color = colors.primary)
                                CommandBlock("healthmd direct pair")
                            }
                        },
                    ),
                )
                PrimaryButton(
                    text = stringResource(R.string.direct_cli_scan_qr),
                    onClick = onScanQr,
                    icon = Icons.Outlined.QrCodeScanner,
                    modifier = Modifier
                        .padding(top = GeistSpacing.space4)
                        .testTag(DirectCliTestTags.SCAN_QR),
                )

                ToolGroupHeading(stringResource(R.string.m3_tools_direct_cli_manual))
                Text(
                    stringResource(R.string.direct_cli_pair_step_enter),
                    style = GeistType.copy14,
                    color = colors.secondary,
                    modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space3),
                )
                ToolRows(
                    listOf(
                        { shape ->
                            ToolFieldRow(shape) {
                                OutlinedTextField(
                                    value = ui.host,
                                    onValueChange = onHostChange,
                                    label = { Text(stringResource(R.string.direct_cli_computer_address)) },
                                    placeholder = { Text("192.168.1.20", style = GeistType.label14Mono) },
                                    singleLine = true,
                                    textStyle = GeistType.label14Mono,
                                    shape = fieldShape,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag(DirectCliTestTags.HOST),
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                                    OutlinedTextField(
                                        value = ui.port,
                                        onValueChange = onPortChange,
                                        label = { Text(stringResource(R.string.direct_cli_port)) },
                                        singleLine = true,
                                        textStyle = GeistType.label14Mono,
                                        shape = fieldShape,
                                        modifier = Modifier
                                            .weight(1f)
                                            .testTag(DirectCliTestTags.PORT),
                                    )
                                    OutlinedTextField(
                                        value = ui.pairingCode,
                                        onValueChange = onPairingCodeChange,
                                        label = { Text(stringResource(R.string.direct_cli_pairing_code)) },
                                        singleLine = true,
                                        textStyle = GeistType.label14Mono,
                                        shape = fieldShape,
                                        modifier = Modifier
                                            .weight(1f)
                                            .testTag(DirectCliTestTags.PAIRING_CODE),
                                    )
                                }
                            }
                        },
                    ),
                )
                SecondaryButton(
                    text = stringResource(R.string.direct_cli_pair_button),
                    onClick = onPair,
                    enabled = ui.canPair,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = GeistSpacing.space4)
                        .testTag(DirectCliTestTags.PAIR),
                )
            } else {
                ToolGroupHeading(stringResource(R.string.m3_tools_direct_cli_computer))
                ToolRows(
                    listOf(
                        { shape ->
                            ToolRow(
                                shape = shape,
                                title = stringResource(
                                    R.string.direct_cli_paired_listener,
                                    requireNotNull(ui.pairedListenerName),
                                ),
                                modifier = Modifier.testTag(DirectCliTestTags.PAIRED_LISTENER),
                                trailing = {
                                    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = colors.success)
                                },
                            )
                        },
                        { shape ->
                            ToolFieldRow(shape) {
                                Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                                    OutlinedTextField(
                                        value = ui.host,
                                        onValueChange = onHostChange,
                                        label = { Text(stringResource(R.string.direct_cli_computer_address)) },
                                        singleLine = true,
                                        textStyle = GeistType.label14Mono,
                                        shape = fieldShape,
                                        modifier = Modifier
                                            .weight(2f)
                                            .testTag(DirectCliTestTags.HOST),
                                    )
                                    OutlinedTextField(
                                        value = ui.port,
                                        onValueChange = onPortChange,
                                        label = { Text(stringResource(R.string.direct_cli_port)) },
                                        singleLine = true,
                                        textStyle = GeistType.label14Mono,
                                        shape = fieldShape,
                                        modifier = Modifier
                                            .weight(1f)
                                            .testTag(DirectCliTestTags.PORT),
                                    )
                                }
                            }
                        },
                        { shape ->
                            ToolRow(
                                shape = shape,
                                title = stringResource(R.string.direct_cli_save_address),
                                onClick = onSaveEndpoint,
                                enabled = ui.host.isNotBlank() && ui.port.toIntOrNull() in 1..65_535,
                                titleColor = colors.brandPrimary,
                                showChevron = false,
                                modifier = Modifier.testTag(DirectCliTestTags.SAVE_ENDPOINT),
                            )
                        },
                        { shape ->
                            ToolRow(
                                shape = shape,
                                title = stringResource(R.string.direct_cli_forget),
                                onClick = onForget,
                                titleColor = colors.error,
                                showChevron = false,
                                modifier = Modifier.testTag(DirectCliTestTags.FORGET),
                            )
                        },
                    ),
                )

                ToolGroupHeading(stringResource(R.string.m3_tools_direct_cli_export))
                ToolRows(
                    listOf(
                        { shape ->
                            ToolFieldRow(shape) {
                                Text(stringResource(R.string.direct_cli_export_instruction), style = GeistType.label14, color = colors.primary)
                                CommandBlock("healthmd export --raw --yesterday")
                                CommandBlock("healthmd export --yesterday --destination /path/to/folder")
                            }
                        },
                    ),
                )
                AdaptiveActionPair(
                    primaryAction = { modifier ->
                        PrimaryButton(
                            text = stringResource(R.string.direct_cli_connect),
                            onClick = onConnect,
                            modifier = modifier.testTag(DirectCliTestTags.CONNECT),
                        )
                    },
                    secondaryAction = { modifier ->
                        SecondaryButton(
                            text = stringResource(R.string.direct_cli_disconnect),
                            onClick = onDisconnect,
                            modifier = modifier.testTag(DirectCliTestTags.DISCONNECT),
                        )
                    },
                    modifier = Modifier.padding(top = GeistSpacing.space4),
                )
            }
        }
    }
}

/** The intro and the live connection status on one tonal card. */
@Composable
private fun DirectCliStatusCard(connection: DirectCliConnectionState) {
    val colors = LocalGeistColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.background200)
            .padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(GeistSizes.control)
                    .background(colors.brandSubtle, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Computer, contentDescription = null, tint = colors.brandOnSubtle, modifier = Modifier.size(22.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.direct_cli_intro_title), style = GeistType.heading16, color = colors.primary)
                Text(stringResource(R.string.direct_cli_intro_body), style = GeistType.copy14, color = colors.secondary)
            }
        }
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.medium))
                .background(colors.gray.c200)
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        ) {
            Text(stringResource(R.string.direct_cli_status_title), style = GeistType.label12, color = colors.secondary)
            Text(
                connectionText(connection),
                modifier = Modifier.testTag(DirectCliTestTags.STATUS),
                style = GeistType.label14,
                color = when (connection) {
                    is DirectCliConnectionState.Failed -> colors.error
                    is DirectCliConnectionState.Completed -> colors.success
                    else -> colors.primary
                },
            )
        }
    }
}

/** A selectable CLI command on a tonal `gray-100` code surface. */
@Composable
private fun CommandBlock(command: String) {
    val colors = LocalGeistColors.current
    SelectionContainer {
        Text(
            text = command,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.small))
                .background(colors.gray.c100)
                .padding(horizontal = GeistSpacing.space3, vertical = GeistSpacing.space2),
            style = GeistType.copy13Mono,
            color = colors.primary,
        )
    }
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
        DirectCliFailure.PROVIDER_RANGE_REQUIRED -> stringResource(
            R.string.direct_cli_failure_provider_range,
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
