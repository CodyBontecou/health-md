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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
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
import com.healthmd.R
import com.healthmd.data.export.APIExportAuthorization
import com.healthmd.data.export.APIExportAuthorizationValidationReason
import com.healthmd.data.export.APIExportAuthorizationValidationResult
import com.healthmd.data.export.APIExportHeaderValidationException
import com.healthmd.data.export.APIExportHeaderValidationReason
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
            text = stringResource(R.string.api_export_target_title),
            style = MaterialTheme.typography.labelSmall,
            color = AppColors.textMuted,
        )
        ExportTargetRow(
            title = stringResource(R.string.export_preview_device_destination),
            subtitle = folderSubtitle,
            selected = selectedTarget == ExportTarget.DEVICE_FOLDER,
            onClick = { onTargetSelected(ExportTarget.DEVICE_FOLDER) },
        )
        ExportTargetRow(
            title = stringResource(R.string.export_preview_api_destination),
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
    var localError by remember { mutableStateOf<APISettingsValidationError?>(null) }

    LaunchedEffect(configurationError) {
        // View models currently expose only display strings. Do not render those strings because
        // they may be exception/parser English; localize a safe boundary error instead.
        if (configurationError != null) {
            localError = APISettingsValidationError.ConfigurationSaveFailed
        }
    }

    val saveSettings = {
        when {
            !APIExportEndpoint.isConfigured(endpointUrl) -> {
                localError = APISettingsValidationError.InvalidEndpoint
            }
            else -> {
                val authorizationError = authorization
                    .takeIf { it.isNotBlank() }
                    ?.let(APIExportAuthorization::validate)
                    ?.let { result ->
                        (result as? APIExportAuthorizationValidationResult.Invalid)?.reason
                    }
                val headerError = requestHeaders
                    .takeIf { it.isNotBlank() }
                    ?.let { raw ->
                        try {
                            APIExportHeaders.parse(raw)
                            null
                        } catch (error: APIExportHeaderValidationException) {
                            error.reason
                        }
                    }
                when {
                    authorizationError != null -> {
                        localError = APISettingsValidationError.InvalidAuthorization(authorizationError)
                    }
                    headerError != null -> {
                        localError = APISettingsValidationError.InvalidHeaders(headerError)
                        requestHeadersExpanded = true
                    }
                    else -> {
                        onSave(
                            endpointUrl,
                            authorization.takeIf { it.isNotBlank() },
                            requestHeaders.takeIf { it.isNotBlank() },
                        )
                        onDismiss()
                    }
                }
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
                        APISettingsSection(title = stringResource(R.string.api_export_section_endpoint)) {
                            OutlinedTextField(
                                value = endpointUrl,
                                onValueChange = {
                                    endpointUrl = it
                                    localError = null
                                },
                                label = { Text(stringResource(R.string.api_export_endpoint_url_label)) },
                                placeholder = { Text(stringResource(R.string.api_export_endpoint_example)) },
                                textStyle = GeistType.copy14Mono,
                                keyboardOptions = KeyboardOptions(
                                    keyboardType = KeyboardType.Uri,
                                    imeAction = ImeAction.Next,
                                ),
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Text(
                                stringResource(R.string.api_export_endpoint_help),
                                style = GeistType.copy13,
                                color = colors.secondary,
                            )
                        }

                        APISettingsSection(
                            title = stringResource(R.string.api_export_literal_authorization),
                            optional = true,
                        ) {
                            if (authorizationConfigured) {
                                StoredSecretStatus(
                                    label = stringResource(
                                        R.string.api_export_authorization_saved,
                                        stringResource(R.string.api_export_literal_authorization),
                                    ),
                                    removeLabel = stringResource(R.string.api_export_remove_credential),
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
                                    Text(
                                        if (authorizationConfigured) {
                                            stringResource(
                                                R.string.api_export_new_authorization_label,
                                                stringResource(R.string.api_export_literal_authorization),
                                            )
                                        } else {
                                            stringResource(
                                                R.string.api_export_authorization_label,
                                                stringResource(R.string.api_export_literal_bearer),
                                                stringResource(R.string.api_export_literal_basic),
                                            )
                                        },
                                    )
                                },
                                placeholder = {
                                    Text(
                                        if (authorizationConfigured) {
                                            stringResource(R.string.api_export_authorization_replacement_placeholder)
                                        } else {
                                            stringResource(
                                                R.string.api_export_authorization_placeholder,
                                                stringResource(R.string.api_export_literal_authorization),
                                            )
                                        },
                                    )
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
                                    stringResource(
                                        R.string.api_export_authorization_saved_help,
                                        stringResource(R.string.api_export_literal_bearer),
                                    )
                                } else {
                                    stringResource(
                                        R.string.api_export_authorization_help,
                                        stringResource(R.string.api_export_literal_bearer),
                                        stringResource(R.string.api_export_literal_basic),
                                    )
                                },
                                style = GeistType.copy13,
                                color = colors.secondary,
                            )
                        }

                        APISettingsSection(
                            title = stringResource(R.string.api_export_custom_headers_title),
                            optional = true,
                        ) {
                            CustomHeadersDisclosure(
                                configured = requestHeadersConfigured,
                                expanded = requestHeadersExpanded,
                                onClick = { requestHeadersExpanded = !requestHeadersExpanded },
                            )
                            if (requestHeadersExpanded) {
                                if (requestHeadersConfigured) {
                                    StoredSecretStatus(
                                        label = stringResource(R.string.api_export_custom_headers_saved),
                                        removeLabel = stringResource(R.string.api_export_remove_headers),
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
                                        Text(
                                            stringResource(
                                                if (requestHeadersConfigured) {
                                                    R.string.api_export_replacement_headers_label
                                                } else {
                                                    R.string.api_export_request_headers_label
                                                },
                                            ),
                                        )
                                    },
                                    placeholder = {
                                        Text(stringResource(R.string.api_export_headers_example))
                                    },
                                    textStyle = GeistType.copy14Mono,
                                    minLines = 3,
                                    maxLines = 6,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                                Text(
                                    if (requestHeadersConfigured) {
                                        stringResource(
                                            R.string.api_export_replacement_headers_help,
                                            stringResource(R.string.api_export_header_line_syntax),
                                        )
                                    } else {
                                        stringResource(
                                            R.string.api_export_request_headers_help,
                                            stringResource(R.string.api_export_header_line_syntax),
                                            stringResource(R.string.app_name),
                                        )
                                    },
                                    style = GeistType.copy13,
                                    color = colors.secondary,
                                )
                            }
                        }

                        localError?.let { error ->
                            APISettingsError(error = error)
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
                            text = stringResource(R.string.api_export_close_settings),
                            onClick = onDismiss,
                            modifier = Modifier.weight(1f),
                        )
                        PrimaryButton(
                            text = stringResource(R.string.api_export_save_settings),
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
                text = stringResource(R.string.api_export_dialog_title),
                style = GeistType.heading20,
                color = colors.primary,
            )
            Text(
                text = stringResource(
                    R.string.api_export_dialog_description,
                    stringResource(R.string.api_export_literal_json),
                    stringResource(R.string.api_export_literal_post),
                    stringResource(R.string.api_export_literal_http),
                    stringResource(R.string.api_export_literal_https),
                ),
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
                contentDescription = stringResource(R.string.api_export_close_content_description),
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
                    text = stringResource(R.string.api_export_optional_label),
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
                text = stringResource(
                    if (configured) {
                        R.string.api_export_manage_request_headers
                    } else {
                        R.string.api_export_add_request_headers
                    },
                ),
                style = GeistType.label14,
                color = colors.primary,
            )
            Text(
                text = stringResource(
                    if (configured) {
                        R.string.api_export_headers_saved_hidden
                    } else {
                        R.string.api_export_headers_add_help
                    },
                ),
                style = GeistType.copy13,
                color = if (configured) colors.success else colors.secondary,
            )
        }
        Icon(
            imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
            contentDescription = stringResource(
                if (expanded) {
                    R.string.api_export_collapse_custom_headers
                } else {
                    R.string.api_export_expand_custom_headers
                },
            ),
            tint = colors.secondary,
        )
    }
}

private sealed interface APISettingsValidationError {
    data object InvalidEndpoint : APISettingsValidationError
    data class InvalidAuthorization(
        val reason: APIExportAuthorizationValidationReason,
    ) : APISettingsValidationError
    data class InvalidHeaders(
        val reason: APIExportHeaderValidationReason,
    ) : APISettingsValidationError
    data object ConfigurationSaveFailed : APISettingsValidationError
}

@Composable
private fun APISettingsValidationError.apiExportLocalizedMessage(): String = when (this) {
    APISettingsValidationError.InvalidEndpoint -> stringResource(
        R.string.api_export_error_invalid_endpoint,
        stringResource(R.string.api_export_literal_http),
        stringResource(R.string.api_export_literal_https),
    )
    is APISettingsValidationError.InvalidAuthorization -> when (reason) {
        APIExportAuthorizationValidationReason.EMPTY ->
            stringResource(
                R.string.api_export_error_authorization_empty,
                stringResource(R.string.api_export_literal_bearer),
                stringResource(R.string.api_export_literal_authorization),
            )
        APIExportAuthorizationValidationReason.UNSUPPORTED_CHARACTERS ->
            stringResource(
                R.string.api_export_error_authorization_characters,
                stringResource(R.string.api_export_literal_authorization),
            )
    }
    is APISettingsValidationError.InvalidHeaders -> when (val reason = reason) {
        is APIExportHeaderValidationReason.TotalSizeExceeded ->
            stringResource(R.string.api_export_error_headers_total_size, reason.maximumCharacters)
        APIExportHeaderValidationReason.UnsupportedLineBreak ->
            stringResource(R.string.api_export_error_headers_line_break)
        is APIExportHeaderValidationReason.MissingSeparator ->
            stringResource(
                R.string.api_export_error_header_missing_separator,
                reason.headerIndex,
                stringResource(R.string.api_export_header_line_syntax),
            )
        is APIExportHeaderValidationReason.InvalidName ->
            stringResource(
                R.string.api_export_error_header_invalid_name,
                reason.headerIndex,
                reason.maximumNameCharacters,
                stringResource(R.string.api_export_literal_http),
            )
        is APIExportHeaderValidationReason.ReservedName ->
            stringResource(
                R.string.api_export_error_header_reserved_name,
                reason.headerName,
                stringResource(R.string.app_name),
            )
        is APIExportHeaderValidationReason.DuplicateName ->
            stringResource(R.string.api_export_error_header_duplicate_name, reason.headerName)
        is APIExportHeaderValidationReason.ValueTooLong ->
            stringResource(
                R.string.api_export_error_header_value_too_long,
                reason.headerName,
                reason.maximumValueCharacters,
            )
        is APIExportHeaderValidationReason.UnsupportedValueCharacters ->
            stringResource(
                R.string.api_export_error_header_value_characters,
                reason.headerName,
            )
        is APIExportHeaderValidationReason.TooManyHeaders ->
            pluralStringResource(
                R.plurals.api_export_error_header_count,
                reason.maximumCount,
                reason.maximumCount,
            )
    }
    APISettingsValidationError.ConfigurationSaveFailed ->
        stringResource(R.string.api_export_error_save_failed)
}

@Composable
private fun APISettingsError(error: APISettingsValidationError) {
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
            text = error.apiExportLocalizedMessage(),
            style = GeistType.copy13,
            color = colors.error,
            modifier = Modifier.weight(1f),
        )
    }
}
