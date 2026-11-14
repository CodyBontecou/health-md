package com.healthmd.presentation.endpoints

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointError
import com.healthmd.domain.model.SavedAPIEndpointRules
import com.healthmd.presentation.settings.ConnectionTestState
import com.healthmd.presentation.settings.SettingsDestinationActivity
import com.healthmd.presentation.theme.*

internal object EndpointTestTags {
    const val SHEET = "endpoint.sheet"
    const val NAME = "endpoint.name"
    const val URL = "endpoint.url"
    const val TOKEN = "endpoint.token"
    const val TEST = "endpoint.test"
    const val SAVE = "endpoint.save"
    const val DELETE = "endpoint.delete"
    const val ROW = "endpoint.row"
    const val EDIT = "endpoint.edit"
    const val NEW = "endpoint.new"
}

/** "New API endpoint" / "Edit API endpoint" Material bottom sheet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun APIEndpointSheet(
    state: EndpointSheetState,
    onUpdate: ((EndpointSheetState) -> EndpointSheetState) -> Unit,
    onTest: () -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit,
    onRequestDelete: (Boolean) -> Unit,
    onDelete: () -> Unit,
) {
    val colors = LocalGeistColors.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.gray.c200,
        modifier = Modifier.testTag(EndpointTestTags.SHEET),
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).imePadding()
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space6),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                Text(
                    stringResource(if (state.isEditing) R.string.endpoint_sheet_edit_title else R.string.endpoint_sheet_new_title),
                    style = GeistType.heading24,
                    color = colors.primary,
                    modifier = Modifier.semantics { heading() },
                )
                Text(stringResource(R.string.endpoint_sheet_body), style = GeistType.copy14, color = colors.secondary)
            }
            OutlinedTextField(
                value = state.name,
                onValueChange = { value -> onUpdate { it.copy(name = value) } },
                label = { Text(stringResource(R.string.endpoint_sheet_name)) },
                singleLine = true,
                isError = state.error == SavedAPIEndpointError.NAME_REQUIRED,
                supportingText = if (state.error == SavedAPIEndpointError.NAME_REQUIRED) {
                    { Text(stringResource(R.string.endpoint_sheet_name_required)) }
                } else null,
                modifier = Modifier.fillMaxWidth().testTag(EndpointTestTags.NAME),
            )
            OutlinedTextField(
                value = state.url,
                onValueChange = { value -> onUpdate { it.copy(url = value) } },
                label = { Text(stringResource(R.string.endpoint_sheet_url)) },
                placeholder = { Text("https://api.example.com/health", style = GeistType.copy14Mono) },
                singleLine = true,
                textStyle = GeistType.copy14Mono,
                isError = state.error == SavedAPIEndpointError.INVALID_URL || state.error == SavedAPIEndpointError.DUPLICATE_URL,
                supportingText = {
                    Text(
                        stringResource(
                            when (state.error) {
                                SavedAPIEndpointError.INVALID_URL -> R.string.endpoint_sheet_url_invalid
                                SavedAPIEndpointError.DUPLICATE_URL -> R.string.endpoint_sheet_url_duplicate
                                else -> R.string.endpoint_sheet_url_help
                            },
                        ),
                    )
                },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth().testTag(EndpointTestTags.URL),
            )
            OutlinedTextField(
                value = state.token,
                onValueChange = { value -> onUpdate { it.copy(token = value, removeSavedToken = false) } },
                label = { Text(stringResource(R.string.endpoint_sheet_token)) },
                placeholder = if (state.hasSavedToken && !state.removeSavedToken) {
                    { Text(stringResource(R.string.endpoint_sheet_token_saved)) }
                } else null,
                singleLine = true,
                textStyle = GeistType.copy14Mono,
                visualTransformation = if (state.showToken) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                isError = state.error == SavedAPIEndpointError.INVALID_TOKEN,
                trailingIcon = {
                    IconButton(onClick = { onUpdate { it.copy(showToken = !it.showToken) } }) {
                        Icon(
                            if (state.showToken) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                            contentDescription = stringResource(if (state.showToken) R.string.endpoint_sheet_hide_token else R.string.endpoint_sheet_show_token),
                        )
                    }
                },
                supportingText = {
                    Text(
                        stringResource(
                            if (state.error == SavedAPIEndpointError.INVALID_TOKEN) R.string.endpoint_sheet_token_invalid
                            else R.string.endpoint_sheet_token_help,
                        ),
                    )
                },
                modifier = Modifier.fillMaxWidth().testTag(EndpointTestTags.TOKEN),
            )
            if (state.isEditing && state.hasSavedToken && state.token.isBlank()) {
                TextButton(onClick = { onUpdate { it.copy(removeSavedToken = !it.removeSavedToken) } }) {
                    Text(
                        stringResource(if (state.removeSavedToken) R.string.endpoint_sheet_keep_token else R.string.endpoint_sheet_remove_token),
                        style = GeistType.button14,
                        color = colors.brandPrimary,
                    )
                }
            }
            ConnectionTestRow(state, onTest)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                OutlinedButton(
                    onClick = onDismiss,
                    shape = RoundedCornerShape(GeistRadii.full),
                    modifier = Modifier.weight(1f).heightIn(min = GeistSizes.controlLarge),
                ) { Text(stringResource(R.string.cancel), style = GeistType.button14, color = colors.primary) }
                Button(
                    onClick = onSave,
                    enabled = !state.saving,
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.primary, contentColor = colors.background100),
                    modifier = Modifier.weight(1f).heightIn(min = GeistSizes.controlLarge).testTag(EndpointTestTags.SAVE),
                ) { Text(stringResource(R.string.endpoint_sheet_save), style = GeistType.button14) }
            }
            if (state.isEditing) {
                TextButton(
                    onClick = { onRequestDelete(true) },
                    modifier = Modifier.fillMaxWidth().testTag(EndpointTestTags.DELETE),
                ) { Text(stringResource(R.string.endpoint_sheet_delete), style = GeistType.button14, color = colors.error) }
            }
        }
    }
    if (state.confirmingDelete) {
        AlertDialog(
            onDismissRequest = { onRequestDelete(false) },
            title = { Text(stringResource(R.string.endpoint_delete_title, state.name)) },
            text = { Text(stringResource(R.string.endpoint_delete_body)) },
            confirmButton = {
                TextButton(onClick = onDelete) { Text(stringResource(R.string.endpoint_sheet_delete), color = colors.error) }
            },
            dismissButton = { TextButton(onClick = { onRequestDelete(false) }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun ConnectionTestRow(state: EndpointSheetState, onTest: () -> Unit) {
    val colors = LocalGeistColors.current
    val test = state.test
    val ok = test is ConnectionTestState.Finished && SettingsDestinationActivity.isReachable(test.statusCode)
    Row(
        Modifier.fillMaxWidth()
            .background(
                when {
                    ok -> colors.green.c100
                    test is ConnectionTestState.Finished || test == ConnectionTestState.Failed -> colors.amber.c100
                    else -> colors.background200
                },
                RoundedCornerShape(GeistRadii.medium),
            )
            .padding(start = GeistSpacing.space3, end = GeistSpacing.space1, top = GeistSpacing.space1, bottom = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        when (test) {
            ConnectionTestState.Idle -> Text(stringResource(R.string.endpoint_test_idle), style = GeistType.copy14, color = colors.secondary, modifier = Modifier.weight(1f))
            ConnectionTestState.Running -> {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = colors.brandPrimary)
                Text(stringResource(R.string.endpoint_test_running), style = GeistType.copy14, color = colors.secondary, modifier = Modifier.weight(1f))
            }
            is ConnectionTestState.Finished -> {
                Icon(if (ok) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline, contentDescription = null,
                    tint = if (ok) colors.success else colors.warning, modifier = Modifier.size(18.dp))
                Text(
                    stringResource(
                        if (ok) R.string.endpoint_test_ok else R.string.endpoint_test_status,
                        SettingsDestinationActivity.httpStatusText(test.statusCode),
                    ),
                    style = GeistType.label14,
                    color = if (ok) colors.green.c1000 else colors.amber.c1000,
                    modifier = Modifier.weight(1f),
                )
            }
            ConnectionTestState.Failed -> {
                Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = colors.warning, modifier = Modifier.size(18.dp))
                Text(stringResource(R.string.endpoint_test_failed), style = GeistType.label14, color = colors.amber.c1000, modifier = Modifier.weight(1f))
            }
        }
        TextButton(
            onClick = onTest,
            enabled = state.urlValid && test != ConnectionTestState.Running,
            modifier = Modifier.testTag(EndpointTestTags.TEST),
        ) {
            Text(
                stringResource(if (test == ConnectionTestState.Idle) R.string.endpoint_test_action else R.string.endpoint_test_again),
                style = GeistType.button14,
                color = colors.brandPrimary,
            )
        }
    }
}

/** Status dot + name + URL + visible Edit action: the bound endpoint in onboarding's Folder step. */
@Composable
fun BoundEndpointRow(endpoint: SavedAPIEndpoint, onEdit: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    Row(
        modifier.fillMaxWidth().background(colors.background100, RoundedCornerShape(GeistRadii.medium))
            .padding(start = GeistSpacing.space3, top = GeistSpacing.space2, bottom = GeistSpacing.space2, end = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Box(Modifier.size(8.dp).background(colors.success, CircleShape))
        Column(Modifier.weight(1f)) {
            Text(endpoint.name, style = GeistType.label14, color = colors.primary)
            Text(SavedAPIEndpointRules.displayUrl(endpoint.url), style = GeistType.copy13Mono, color = colors.secondary)
        }
        TextButton(onClick = onEdit, modifier = Modifier.testTag(EndpointTestTags.EDIT)) {
            Text(stringResource(R.string.endpoint_edit), style = GeistType.button14, color = colors.brandPrimary)
        }
    }
}

/**
 * AE3: saved endpoints as a radio list with a visible edit button per row, plus New endpoint.
 * [selectedUrl] is the automation's current binding; an unsaved legacy URL is shown as its own row.
 */
@Composable
fun SavedEndpointsPicker(
    rows: List<SavedEndpointRow>,
    selectedUrl: String?,
    onSelect: (SavedAPIEndpoint) -> Unit,
    onEdit: (SavedAPIEndpoint) -> Unit,
    onNew: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val selected = SavedAPIEndpointRules.byUrl(rows.map { it.endpoint }, selectedUrl)
    val legacy = selectedUrl?.takeIf { it.isNotBlank() && selected == null }
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        Text(stringResource(R.string.endpoint_saved_title), style = GeistType.label14, color = colors.secondary)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            rows.forEach { row ->
                val isSelected = row.endpoint.id == selected?.id
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(GeistRadii.medium))
                        .background(if (isSelected) colors.brandSubtle else colors.background200)
                        .selectable(selected = isSelected, role = Role.RadioButton, onClick = { onSelect(row.endpoint) })
                        .testTag(EndpointTestTags.ROW)
                        .padding(start = GeistSpacing.space2, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(selected = isSelected, onClick = null,
                        colors = RadioButtonDefaults.colors(selectedColor = colors.brandPrimary, unselectedColor = colors.secondary))
                    Spacer(Modifier.width(GeistSpacing.space2))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(row.endpoint.name, style = GeistType.label16, color = colors.primary)
                        Text(SavedAPIEndpointRules.displayUrl(row.endpoint.url), style = GeistType.copy13Mono, color = colors.secondary)
                        Text(
                            if (row.usedBy.isEmpty()) stringResource(R.string.endpoint_not_used)
                            else pluralStringResource(R.plurals.endpoint_used_by, row.usedBy.size, row.usedBy.joinToString(", ")),
                            style = GeistType.copy13,
                            color = colors.secondary,
                        )
                    }
                    IconButton(onClick = { onEdit(row.endpoint) }, modifier = Modifier.testTag(EndpointTestTags.EDIT)) {
                        Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.endpoint_edit_named, row.endpoint.name), tint = colors.brandPrimary)
                    }
                }
            }
            if (legacy != null) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(GeistRadii.medium)).background(colors.brandSubtle)
                        .padding(GeistSpacing.space3),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.endpoint_unsaved), style = GeistType.label16, color = colors.primary)
                        Text(SavedAPIEndpointRules.displayUrl(legacy), style = GeistType.copy13Mono, color = colors.secondary)
                    }
                }
            }
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(GeistRadii.medium)).background(colors.background200)
                    .clickable(role = Role.Button, onClick = onNew).testTag(EndpointTestTags.NEW)
                    .heightIn(min = GeistSizes.minimumTouchTarget).padding(horizontal = GeistSpacing.space3),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Icon(Icons.Outlined.Add, contentDescription = null, tint = colors.brandPrimary)
                Text(stringResource(R.string.endpoint_new), style = GeistType.label14, color = colors.brandPrimary)
            }
        }
        Text(stringResource(R.string.endpoint_shared_note), style = GeistType.copy13, color = colors.secondary)
    }
}
