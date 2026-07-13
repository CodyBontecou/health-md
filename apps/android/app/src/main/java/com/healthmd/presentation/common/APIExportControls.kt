package com.healthmd.presentation.common

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun ExportTargetSelector(
    selectedTarget: ExportTarget,
    folderSubtitle: String,
    apiSubtitle: String,
    onTargetSelected: (ExportTarget) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        Text(
            text = "Export Target",
            style = MaterialTheme.typography.labelSmall,
            color = AppColors.textMuted,
        )
        ExportTargetRow(
            title = "Device folder",
            subtitle = folderSubtitle,
            selected = selectedTarget == ExportTarget.DEVICE_FOLDER,
            onClick = { onTargetSelected(ExportTarget.DEVICE_FOLDER) },
        )
        ExportTargetRow(
            title = "API endpoint",
            subtitle = apiSubtitle,
            selected = selectedTarget == ExportTarget.API_ENDPOINT,
            onClick = { onTargetSelected(ExportTarget.API_ENDPOINT) },
        )
    }
}

@Composable
private fun ExportTargetRow(
    title: String,
    subtitle: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        color = if (selected) AppColors.accentSubtle else AppColors.bgSecondary,
        shape = MaterialTheme.shapes.large,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = Spacing.sm, vertical = Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RadioButton(selected = selected, onClick = onClick)
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall, color = AppColors.textPrimary)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
            }
        }
    }
}

@Composable
fun APIExportSettingsDialog(
    initialEndpointUrl: String,
    authorizationConfigured: Boolean,
    requestHeadersConfigured: Boolean,
    configurationError: String?,
    onDismiss: () -> Unit,
    onSave: (endpointUrl: String, authorization: String?, requestHeaders: String?) -> Unit,
    onClearAuthorization: () -> Unit,
    onClearRequestHeaders: () -> Unit,
) {
    var endpointUrl by remember { mutableStateOf(initialEndpointUrl) }
    var authorization by remember { mutableStateOf("") }
    var requestHeaders by remember { mutableStateOf("") }
    var localError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(configurationError) {
        if (configurationError != null) localError = configurationError
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("API export") },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    "Health.md sends one JSON POST containing the selected daily health records directly to an HTTPS endpoint you control.",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                OutlinedTextField(
                    value = endpointUrl,
                    onValueChange = {
                        endpointUrl = it
                        localError = null
                    },
                    label = { Text("HTTPS endpoint URL") },
                    placeholder = { Text("https://api.example.com/healthmd") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    supportingText = { Text("Put API keys and other secrets in encrypted request headers, not URL query parameters.") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                OutlinedTextField(
                    value = authorization,
                    onValueChange = {
                        authorization = it
                        localError = null
                    },
                    label = {
                        Text(if (authorizationConfigured) "Replace authorization (optional)" else "Bearer token (optional)")
                    },
                    supportingText = {
                        Text("Plain values are sent as Bearer tokens. Full Bearer or Basic values are accepted and encrypted on this device.")
                    },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (authorizationConfigured) {
                    TextButton(onClick = onClearAuthorization) {
                        Text("Clear saved authorization")
                    }
                }
                Spacer(modifier = Modifier.height(Spacing.sm))
                OutlinedTextField(
                    value = requestHeaders,
                    onValueChange = {
                        requestHeaders = it
                        localError = null
                    },
                    label = {
                        Text(if (requestHeadersConfigured) "Replace custom headers (optional)" else "Custom request headers (optional)")
                    },
                    placeholder = {
                        Text("X-API-Key: secret\nX-Client-ID: healthmd")
                    },
                    supportingText = {
                        Text("One Name: value per line. Authorization and service-specific headers are supported. A raw Authorization line replaces the saved token. Values are encrypted and not shown again.")
                    },
                    minLines = 3,
                    maxLines = 6,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (requestHeadersConfigured) {
                    TextButton(onClick = onClearRequestHeaders) {
                        Text("Clear saved custom headers")
                    }
                }
                localError?.let {
                    Text(it, color = AppColors.error, style = MaterialTheme.typography.bodySmall)
                }
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    "Only send health data to services you control or trust. HTTP and redirect destinations are blocked. Health.md controls Content-Type and connection framing headers.",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (!APIExportEndpoint.isConfigured(endpointUrl)) {
                    localError = "Enter a valid HTTPS URL without a fragment or embedded username/password."
                } else {
                    val headerError = requestHeaders
                        .takeIf { it.isNotBlank() }
                        ?.let { raw -> runCatching { APIExportHeaders.parse(raw) }.exceptionOrNull()?.message }
                    if (headerError != null) {
                        localError = headerError
                    } else {
                        onSave(
                            endpointUrl,
                            authorization.takeIf { it.isNotBlank() },
                            requestHeaders.takeIf { it.isNotBlank() },
                        )
                        onDismiss()
                    }
                }
            }) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
