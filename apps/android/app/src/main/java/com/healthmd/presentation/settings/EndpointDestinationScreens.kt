package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.export.APIExportAuthorization
import com.healthmd.data.export.APIExportAuthorizationValidationResult
import com.healthmd.data.export.APIExportHeaderValidationException
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.clinic.ClinicAccessViewModel
import com.healthmd.presentation.common.APISettingsError
import com.healthmd.presentation.common.APISettingsValidationError
import com.healthmd.presentation.common.CustomHeadersDisclosure
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.StoredSecretStatus
import com.healthmd.presentation.common.SubScreenTopBar
import com.healthmd.presentation.export.ExportViewModel
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * API endpoint (iOS APIDestG), pushed from Settings. Fields edit a draft; Save commits it through
 * the configuration lock and returns, Back discards it. Status tests the draft URL with a HEAD
 * request and shows the last delivery; Remove clears the endpoint and its stored credentials.
 * Saved credentials are never shown; a typed value replaces them.
 */
@Composable
fun ApiEndpointScreen(
    onBack: () -> Unit,
    exportViewModel: ExportViewModel = hiltViewModel(),
    destinations: SettingsDestinationsViewModel = hiltViewModel(),
    clinicAccess: ClinicAccessViewModel = hiltViewModel(),
) {
    val state by exportViewModel.uiState.collectAsStateWithLifecycle()
    val history by destinations.history.collectAsStateWithLifecycle()
    val testState by destinations.connectionTest.collectAsStateWithLifecycle()
    val clinicStatus by clinicAccess.status.collectAsStateWithLifecycle()
    val independentAccess by clinicAccess.independentAccess.collectAsStateWithLifecycle()
    val managedClinicEndpoint = clinicStatus.endpoint.takeIf { clinicStatus.active && !independentAccess }
    val protection = LocalConfigurationProtection.current
    val colors = LocalGeistColors.current
    val saved = state.settings.apiEndpointUrl

    var endpoint by rememberSaveable(saved) { mutableStateOf(saved) }
    var authorization by rememberSaveable { mutableStateOf("") }
    var headers by rememberSaveable { mutableStateOf("") }
    var headersExpanded by rememberSaveable { mutableStateOf(false) }
    var error by androidx.compose.runtime.remember { mutableStateOf<APISettingsValidationError?>(null) }
    var confirmingRemoval by rememberSaveable { mutableStateOf(false) }
    val hasChanges = endpoint != saved || authorization.isNotBlank() || headers.isNotBlank()
    val draftValid = APIExportEndpoint.isConfigured(endpoint)

    LaunchedEffect(endpoint, authorization) { destinations.resetConnectionTest() }
    LaunchedEffect(state.apiConfigurationError) {
        if (state.apiConfigurationError != null) error = APISettingsValidationError.ConfigurationSaveFailed
    }

    val save: () -> Unit = save@{
        if (protection.enabled) {
            protection.onBlockedChange()
            return@save
        }
        val validation = validateApiDraft(endpoint, authorization, headers)
        if (validation != null) {
            error = validation
            if (validation is APISettingsValidationError.InvalidHeaders) headersExpanded = true
            return@save
        }
        exportViewModel.saveAPIExportConfiguration(
            endpoint,
            authorization.takeIf { it.isNotBlank() },
            headers.takeIf { it.isNotBlank() },
        )
        onBack()
    }

    DestinationPage(
        title = stringResource(R.string.export_preview_api_destination),
        onBack = onBack,
        canSave = hasChanges && managedClinicEndpoint == null,
        onSave = save,
        testTag = "settings.api.page",
    ) {
        if (managedClinicEndpoint != null) {
            SettingsGroup(
                title = stringResource(R.string.m3_schedule_clinic_destination_title),
                rows = listOf { shape ->
                    SettingsValueRow(shape, stringResource(R.string.api_page_endpoint), managedClinicEndpoint, mono = true)
                },
            )
            SettingsFootnote(stringResource(R.string.m3_schedule_clinic_destination_body))
            return@DestinationPage
        }

        DestinationFieldGroup(title = stringResource(R.string.api_page_endpoint)) {
            OutlinedTextField(
                value = endpoint,
                onValueChange = { endpoint = it; error = null },
                label = { Text(stringResource(R.string.api_export_endpoint_url_label)) },
                placeholder = { Text(stringResource(R.string.api_export_endpoint_example)) },
                textStyle = GeistType.copy14Mono,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next, autoCorrectEnabled = false),
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("settings.api.url"),
            )
            if (state.apiAuthorizationConfigured) {
                StoredSecretStatus(
                    label = stringResource(R.string.api_export_authorization_saved, stringResource(R.string.api_export_literal_authorization)),
                    removeLabel = stringResource(R.string.api_export_remove_credential),
                    onRemove = {
                        if (protection.enabled) protection.onBlockedChange() else exportViewModel.clearAPIAuthorization()
                    },
                )
            }
            OutlinedTextField(
                value = authorization,
                onValueChange = { authorization = it; error = null },
                label = { Text(stringResource(R.string.api_page_token)) },
                placeholder = {
                    Text(
                        stringResource(
                            if (state.apiAuthorizationConfigured) R.string.api_export_authorization_replacement_placeholder
                            else R.string.api_page_token_placeholder,
                        ),
                    )
                },
                textStyle = GeistType.copy14Mono,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done, autoCorrectEnabled = false),
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("settings.api.token"),
            )
            Text(stringResource(R.string.api_page_token_help), style = GeistType.copy13, color = colors.secondary)
            // Android-only: extra request headers, kept from the earlier endpoint dialog.
            CustomHeadersDisclosure(
                configured = state.apiRequestHeadersConfigured,
                expanded = headersExpanded,
                onClick = { headersExpanded = !headersExpanded },
            )
            if (headersExpanded) {
                if (state.apiRequestHeadersConfigured) {
                    StoredSecretStatus(
                        label = stringResource(R.string.api_export_custom_headers_saved),
                        removeLabel = stringResource(R.string.api_export_remove_headers),
                        onRemove = {
                            if (protection.enabled) protection.onBlockedChange() else exportViewModel.clearAPIRequestHeaders()
                        },
                    )
                }
                OutlinedTextField(
                    value = headers,
                    onValueChange = { headers = it; error = null },
                    label = { Text(stringResource(R.string.api_export_request_headers_label)) },
                    placeholder = { Text(stringResource(R.string.api_export_headers_example)) },
                    textStyle = GeistType.copy14Mono,
                    minLines = 3,
                    maxLines = 6,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            error?.let { APISettingsError(it) }
        }

        SettingsGroup(
            title = stringResource(R.string.api_page_status),
            rows = listOf<@Composable (Shape) -> Unit>(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.api_page_test_connection),
                        subtitle = when {
                            !draftValid -> stringResource(R.string.api_page_enter_valid_url)
                            testState is ConnectionTestState.Failed -> stringResource(R.string.api_page_test_failed_detail)
                            else -> stringResource(R.string.api_page_test_subtitle)
                        },
                        icon = null,
                        onClick = { destinations.testConnection(endpoint, authorization) },
                        enabled = draftValid && testState != ConnectionTestState.Running,
                        badge = when (val test = testState) {
                            is ConnectionTestState.Finished -> SettingsBadge(
                                SettingsDestinationActivity.httpStatusText(test.statusCode),
                                if (SettingsDestinationActivity.isReachable(test.statusCode)) SettingsBadgeTone.OK else SettingsBadgeTone.ATTENTION,
                            )
                            ConnectionTestState.Failed -> SettingsBadge(stringResource(R.string.api_page_failed), SettingsBadgeTone.ATTENTION)
                            else -> null
                        },
                        trailingContent = if (testState == ConnectionTestState.Running) {
                            { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = colors.brandPrimary) }
                        } else {
                            null
                        },
                        modifier = Modifier.testTag("settings.api.testConnection"),
                    )
                },
                { shape ->
                    SettingsValueRow(
                        shape = shape,
                        title = stringResource(R.string.api_page_last_delivery),
                        value = SettingsDestinationActivity.lastSuccess(ExportTarget.API_ENDPOINT, history)
                            ?.let { settingsTimestampText(it) }
                            ?: stringResource(R.string.settings_none_yet),
                    )
                },
            ),
        )

        SettingsNoticeCard(stringResource(R.string.api_page_trust_note))

        if (saved.isNotEmpty() || state.apiAuthorizationConfigured || state.apiRequestHeadersConfigured) {
            SettingsDestructiveRow(
                title = stringResource(R.string.api_page_remove),
                onClick = { if (protection.enabled) protection.onBlockedChange() else confirmingRemoval = true },
                modifier = Modifier.testTag("settings.api.remove"),
            )
        }
    }

    if (confirmingRemoval) {
        SettingsConfirmDialog(
            title = stringResource(R.string.api_page_remove_title),
            message = stringResource(R.string.api_page_remove_body),
            confirm = stringResource(R.string.api_page_remove),
            onConfirm = {
                confirmingRemoval = false
                if (protection.enabled) {
                    protection.onBlockedChange()
                } else {
                    destinations.removeApiEndpoint()
                    authorization = ""
                    headers = ""
                }
            },
            onDismiss = { confirmingRemoval = false },
        )
    }
}

/** The draft's first problem, checked the same way the endpoint dialog checks it. */
internal fun validateApiDraft(endpoint: String, authorization: String, headers: String): APISettingsValidationError? {
    if (!APIExportEndpoint.isConfigured(endpoint)) return APISettingsValidationError.InvalidEndpoint
    if (authorization.isNotBlank()) {
        val result = APIExportAuthorization.validate(authorization)
        if (result is APIExportAuthorizationValidationResult.Invalid) {
            return APISettingsValidationError.InvalidAuthorization(result.reason)
        }
    }
    if (headers.isNotBlank()) {
        try {
            APIExportHeaders.parse(headers)
        } catch (invalid: APIExportHeaderValidationException) {
            return APISettingsValidationError.InvalidHeaders(invalid.reason)
        }
    }
    return null
}

/**
 * Agent Data gateway (iOS GatewayDestG). Uploads need no token, so the page is the URL, the
 * upload contract, and Remove.
 */
@Composable
fun GatewayDestinationScreen(
    onBack: () -> Unit,
    exportViewModel: ExportViewModel = hiltViewModel(),
    destinations: SettingsDestinationsViewModel = hiltViewModel(),
) {
    val state by exportViewModel.uiState.collectAsStateWithLifecycle()
    val history by destinations.history.collectAsStateWithLifecycle()
    val protection = LocalConfigurationProtection.current
    val colors = LocalGeistColors.current
    val saved = state.settings.agentDataGatewayUrl
    var endpoint by rememberSaveable(saved) { mutableStateOf(saved) }
    var invalid by rememberSaveable { mutableStateOf(false) }
    var confirmingRemoval by rememberSaveable { mutableStateOf(false) }

    val save: () -> Unit = save@{
        if (protection.enabled) {
            protection.onBlockedChange()
            return@save
        }
        if (!AgentDataGatewayEndpoint.isConfigured(endpoint)) {
            invalid = true
            return@save
        }
        exportViewModel.saveAgentDataGatewayConfiguration(endpoint)
        onBack()
    }

    DestinationPage(
        title = stringResource(R.string.export_preview_gateway_destination),
        onBack = onBack,
        canSave = endpoint != saved,
        onSave = save,
        testTag = "settings.gateway.page",
    ) {
        DestinationFieldGroup(title = stringResource(R.string.gateway_page_section)) {
            OutlinedTextField(
                value = endpoint,
                onValueChange = { endpoint = it; invalid = false },
                label = { Text(stringResource(R.string.agent_data_gateway_url_label)) },
                placeholder = { Text(stringResource(R.string.agent_data_gateway_url_example)) },
                textStyle = GeistType.copy14Mono,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done, autoCorrectEnabled = false),
                singleLine = true,
                isError = invalid,
                supportingText = if (invalid) {
                    { Text(stringResource(R.string.api_page_enter_valid_url)) }
                } else {
                    null
                },
                modifier = Modifier.fillMaxWidth().testTag("settings.gateway.url"),
            )
            Text(stringResource(R.string.agent_data_gateway_url_help), style = GeistType.copy13, color = colors.secondary)
        }
        SettingsFootnote(stringResource(R.string.agent_data_gateway_dialog_description))

        SettingsGroup(
            title = stringResource(R.string.api_page_status),
            rows = listOf { shape ->
                SettingsValueRow(
                    shape = shape,
                    title = stringResource(R.string.api_page_last_delivery),
                    value = SettingsDestinationActivity.lastSuccess(ExportTarget.AGENT_DATA_GATEWAY, history)
                        ?.let { settingsTimestampText(it) }
                        ?: stringResource(R.string.settings_none_yet),
                )
            },
        )

        if (saved.isNotEmpty()) {
            SettingsDestructiveRow(
                title = stringResource(R.string.gateway_page_remove),
                onClick = { if (protection.enabled) protection.onBlockedChange() else confirmingRemoval = true },
                modifier = Modifier.testTag("settings.gateway.remove"),
            )
        }
    }

    if (confirmingRemoval) {
        SettingsConfirmDialog(
            title = stringResource(R.string.gateway_page_remove_title),
            message = stringResource(R.string.gateway_page_remove_body),
            confirm = stringResource(R.string.gateway_page_remove),
            onConfirm = {
                confirmingRemoval = false
                if (protection.enabled) protection.onBlockedChange() else destinations.removeGateway()
            },
            onDismiss = { confirmingRemoval = false },
        )
    }
}

/** A pushed destination page: a top bar with Back and Save, then the scrolling form. */
@Composable
private fun DestinationPage(
    title: String,
    onBack: () -> Unit,
    canSave: Boolean,
    onSave: () -> Unit,
    testTag: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    Column(Modifier.fillMaxSize().imePadding().testTag(testTag)) {
        SubScreenTopBar(
            title = title,
            onBack = onBack,
            actions = {
                TextButton(
                    onClick = onSave,
                    enabled = canSave,
                    modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget).testTag("$testTag.save"),
                ) {
                    Text(
                        stringResource(R.string.settings_save),
                        style = GeistType.button14,
                        color = if (canSave) colors.brandPrimary else colors.disabled,
                    )
                }
            },
        )
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GeistSpacing.space4)
                .padding(bottom = GeistSpacing.space8),
            content = content,
        )
    }
}

/** A titled group whose one tonal card holds the form fields. */
@Composable
private fun DestinationFieldGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalGeistColors.current
    Text(
        title,
        style = GeistType.heading14,
        color = colors.brandPrimary,
        modifier = Modifier
            .padding(start = GeistSpacing.space4, top = GeistSpacing.space6, bottom = GeistSpacing.space2)
            .semantics { heading() },
    )
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.background200)
            .padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        content = content,
    )
}
