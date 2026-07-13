package com.healthmd.presentation.common

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistBreakpoints
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
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
    val colors = LocalGeistColors.current
    val dialogShape = RoundedCornerShape(GeistRadii.medium)
    var endpointUrl by remember { mutableStateOf(initialEndpointUrl) }
    var authorization by remember { mutableStateOf("") }
    var requestHeaders by remember { mutableStateOf("") }
    var requestHeadersExpanded by remember { mutableStateOf(false) }
    var localError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(configurationError) {
        if (configurationError != null) localError = configurationError
    }

    val saveSettings = {
        if (!APIExportEndpoint.isConfigured(endpointUrl)) {
            localError = "Enter a valid HTTP or HTTPS URL without a fragment or embedded username/password."
        } else {
            val headerError = requestHeaders
                .takeIf { it.isNotBlank() }
                ?.let { raw -> runCatching { APIExportHeaders.parse(raw) }.exceptionOrNull()?.message }
            if (headerError != null) {
                localError = headerError
                requestHeadersExpanded = true
            } else {
                onSave(
                    endpointUrl,
                    authorization.takeIf { it.isNotBlank() },
                    requestHeaders.takeIf { it.isNotBlank() },
                )
                onDismiss()
            }
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space10),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(GeistSizes.dialogMaxHeightFraction)
                    .widthIn(max = GeistBreakpoints.medium.dp),
                shape = dialogShape,
                color = colors.background100,
                border = BorderStroke(1.dp, colors.grayAlpha.c400),
                tonalElevation = 0.dp,
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    APISettingsDialogHeader(onDismiss = onDismiss)
                    HorizontalDivider(color = colors.grayAlpha.c200)

                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .padding(GeistSpacing.space6),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space6),
                    ) {
                        APISettingsSection(title = "Endpoint") {
                            OutlinedTextField(
                                value = endpointUrl,
                                onValueChange = {
                                    endpointUrl = it
                                    localError = null
                                },
                                label = { Text("Endpoint URL") },
                                placeholder = { Text("https://api.example.com/healthmd") },
                                textStyle = GeistType.copy14Mono,
                                keyboardOptions = KeyboardOptions(
                                    keyboardType = KeyboardType.Uri,
                                    imeAction = ImeAction.Next,
                                ),
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Text(
                                "Required. Keep API keys and other secrets out of the URL.",
                                style = GeistType.copy13,
                                color = colors.secondary,
                            )
                        }

                        APISettingsSection(title = "Authorization", optional = true) {
                            if (authorizationConfigured) {
                                StoredSecretStatus(
                                    label = "Authorization Saved",
                                    removeLabel = "Remove Credential",
                                    onRemove = {
                                        localError = null
                                        onClearAuthorization()
                                    },
                                )
                            }
                            OutlinedTextField(
                                value = authorization,
                                onValueChange = {
                                    authorization = it
                                    localError = null
                                },
                                label = {
                                    Text(if (authorizationConfigured) "New Authorization" else "Bearer Token or Basic Credential")
                                },
                                placeholder = {
                                    Text(if (authorizationConfigured) "Enter a value to replace the saved one" else "Token or Authorization value")
                                },
                                textStyle = GeistType.copy14Mono,
                                visualTransformation = PasswordVisualTransformation(),
                                keyboardOptions = KeyboardOptions(
                                    keyboardType = KeyboardType.Password,
                                    imeAction = ImeAction.Next,
                                ),
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Text(
                                if (authorizationConfigured) {
                                    "Leave blank to keep the saved value. Plain tokens use Bearer automatically."
                                } else {
                                    "Plain tokens use Bearer automatically. Bearer and Basic values are accepted."
                                },
                                style = GeistType.copy13,
                                color = colors.secondary,
                            )
                        }

                        APISettingsSection(title = "Custom Headers", optional = true) {
                            CustomHeadersDisclosure(
                                configured = requestHeadersConfigured,
                                expanded = requestHeadersExpanded,
                                onClick = { requestHeadersExpanded = !requestHeadersExpanded },
                            )
                            if (requestHeadersExpanded) {
                                if (requestHeadersConfigured) {
                                    StoredSecretStatus(
                                        label = "Custom Headers Saved",
                                        removeLabel = "Remove Headers",
                                        onRemove = {
                                            localError = null
                                            onClearRequestHeaders()
                                        },
                                    )
                                }
                                OutlinedTextField(
                                    value = requestHeaders,
                                    onValueChange = {
                                        requestHeaders = it
                                        localError = null
                                    },
                                    label = {
                                        Text(if (requestHeadersConfigured) "Replacement Headers" else "Request Headers")
                                    },
                                    placeholder = {
                                        Text("X-API-Key: secret\nX-Client-ID: healthmd")
                                    },
                                    textStyle = GeistType.copy14Mono,
                                    minLines = 3,
                                    maxLines = 6,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                                Text(
                                    if (requestHeadersConfigured) {
                                        "Enter the complete replacement set, one Name: value per line."
                                    } else {
                                        "Use one Name: value per line. Health.md keeps transport headers app-managed."
                                    },
                                    style = GeistType.copy13,
                                    color = colors.secondary,
                                )
                            }
                        }

                        localError?.let { error ->
                            APISettingsError(message = error)
                        }
                    }

                    HorizontalDivider(color = colors.grayAlpha.c200)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(GeistSpacing.space4),
                        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
                    ) {
                        SecondaryButton(
                            text = "Close Settings",
                            onClick = onDismiss,
                            modifier = Modifier.weight(1f),
                        )
                        PrimaryButton(
                            text = "Save Settings",
                            onClick = saveSettings,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun APISettingsDialogHeader(onDismiss: () -> Unit) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = GeistSpacing.space6, top = GeistSpacing.space4, end = GeistSpacing.space3, bottom = GeistSpacing.space4),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(top = GeistSpacing.space1),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
        ) {
            Text(
                text = "API Export",
                style = GeistType.heading20,
                color = colors.primary,
            )
            Text(
                text = "Send selected records as one JSON POST to an HTTP or HTTPS endpoint you control.",
                style = GeistType.copy13,
                color = colors.secondary,
            )
        }
        IconButton(
            onClick = onDismiss,
            modifier = Modifier.size(GeistSizes.minimumTouchTarget),
        ) {
            Icon(
                imageVector = Icons.Outlined.Close,
                contentDescription = "Close API export settings",
                tint = colors.secondary,
            )
        }
    }
}

@Composable
private fun APISettingsSection(
    title: String,
    optional: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            Text(
                text = title,
                style = GeistType.heading14,
                color = colors.primary,
                modifier = Modifier.weight(1f),
            )
            if (optional) {
                Text(
                    text = "Optional",
                    style = GeistType.label12,
                    color = colors.disabled,
                )
            }
        }
        content()
    }
}

@Composable
private fun StoredSecretStatus(
    label: String,
    removeLabel: String,
    onRemove: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.small)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.green.c100, shape)
            .border(1.dp, colors.green.c400, shape)
            .padding(start = GeistSpacing.space3, end = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Icon(
            imageVector = Icons.Outlined.CheckCircle,
            contentDescription = null,
            tint = colors.success,
            modifier = Modifier.size(GeistSpacing.space4),
        )
        Text(
            text = label,
            style = GeistType.copy13,
            color = colors.success,
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = onRemove) {
            Text(removeLabel, style = GeistType.button12, color = colors.success)
        }
    }
}

@Composable
private fun CustomHeadersDisclosure(
    configured: Boolean,
    expanded: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.small)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = GeistSizes.minimumTouchTarget)
            .background(colors.background100, shape)
            .border(1.dp, colors.grayAlpha.c400, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = GeistSpacing.space3, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
        ) {
            Text(
                text = if (configured) "Manage Request Headers" else "Add Request Headers",
                style = GeistType.label14,
                color = colors.primary,
            )
            Text(
                text = if (configured) "Saved securely · values hidden" else "Add API keys or service-specific values",
                style = GeistType.copy13,
                color = if (configured) colors.success else colors.secondary,
            )
        }
        Icon(
            imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
            contentDescription = if (expanded) "Collapse custom headers" else "Expand custom headers",
            tint = colors.secondary,
        )
    }
}

@Composable
private fun APISettingsError(message: String) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.small)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.red.c100, shape)
            .border(1.dp, colors.red.c400, shape)
            .padding(GeistSpacing.space3)
            .semantics { liveRegion = LiveRegionMode.Assertive },
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Icon(
            imageVector = Icons.Outlined.ErrorOutline,
            contentDescription = null,
            tint = colors.error,
            modifier = Modifier.size(GeistSpacing.space4),
        )
        Text(
            text = message,
            style = GeistType.copy13,
            color = colors.error,
            modifier = Modifier.weight(1f),
        )
    }
}
