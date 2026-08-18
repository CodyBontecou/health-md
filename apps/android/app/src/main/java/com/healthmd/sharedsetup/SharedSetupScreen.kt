package com.healthmd.sharedsetup

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material.icons.outlined.SaveAlt
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SharedSetupScreen(
    viewModel: SharedSetupViewModel = hiltViewModel(),
    onBack: () -> Unit,
    onFinishSetup: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val shareChooserTitle = stringResource(R.string.shared_setup_title)
    val finishAndBack = {
        viewModel.dismiss()
        onBack()
    }
    val finishSetup = {
        viewModel.dismiss()
        onFinishSetup()
    }
    BackHandler(onBack = finishAndBack)
    val shareDocument = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        viewModel.completeShareArtifactHandoff()
    }
    val openDocument = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(viewModel::import)
    }
    val createDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument(SHARED_SETUP_MIME_TYPE),
    ) { uri -> uri?.let(viewModel::exportTo) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.shared_setup_title)) },
                navigationIcon = {
                    IconButton(onClick = finishAndBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.shared_setup_back))
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
            when (val current = state) {
                is SharedSetupUiState.Idle -> SharedSetupStart(
                    pendingEndpoint = current.pendingEndpoint,
                    onConfirmEndpoint = viewModel::confirmPendingEndpoint,
                    onOpen = { openDocument.launch(arrayOf(SHARED_SETUP_MIME_TYPE, "application/json", "application/octet-stream")) },
                    onSave = { createDocument.launch("HealthMd-Shared-Setup.$SHARED_SETUP_EXTENSION") },
                    onShare = {
                        scope.launch {
                            viewModel.shareIntent()
                                .onSuccess { share ->
                                    runCatching {
                                        shareDocument.launch(Intent.createChooser(share.intent, shareChooserTitle))
                                    }.onFailure { error ->
                                        viewModel.cancelPendingShareArtifact()
                                        viewModel.reportError(error)
                                    }
                                }
                                .onFailure(viewModel::reportError)
                        }
                    },
                )
                SharedSetupUiState.Loading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                    Text(stringResource(R.string.shared_setup_checking), color = AppColors.textSecondary)
                }
                is SharedSetupUiState.Review -> SharedSetupReview(
                    preview = current.preview,
                    onApply = viewModel::apply,
                    onCancel = viewModel::dismiss,
                )
                is SharedSetupUiState.Success -> SharedSetupSuccess(
                    result = current.result,
                    pendingEndpoint = current.pendingEndpoint,
                    onConfirmEndpoint = viewModel::confirmPendingEndpoint,
                    onUndo = viewModel::undo,
                    onFinishSetup = finishSetup,
                )
                is SharedSetupUiState.Error -> SharedSetupError(current.message, viewModel::dismiss)
            }
        }
    }
}

@Composable
private fun SharedSetupStart(
    pendingEndpoint: String?,
    onConfirmEndpoint: (String) -> Unit,
    onOpen: () -> Unit,
    onSave: () -> Unit,
    onShare: () -> Unit,
) {
    Text(
        stringResource(R.string.shared_setup_intro),
        style = MaterialTheme.typography.bodyMedium,
        color = AppColors.textSecondary,
    )
    Text(
        stringResource(R.string.shared_setup_sender_disclosure),
        style = MaterialTheme.typography.bodySmall,
        color = AppColors.textMuted,
    )
    pendingEndpoint?.let {
        PendingEndpointConfirmation(it, onConfirmEndpoint)
    }
    GeistCardClickable(onClick = onOpen) {
        Icon(Icons.Outlined.FileOpen, contentDescription = null, tint = AppColors.accent)
        Column(modifier = Modifier.padding(start = Spacing.sm)) {
            Text(stringResource(R.string.shared_setup_use), fontWeight = FontWeight.Medium)
            Text(stringResource(R.string.shared_setup_use_detail), color = AppColors.textMuted)
        }
    }
    GeistCardClickable(onClick = onShare) {
        Icon(Icons.Outlined.Share, contentDescription = null, tint = AppColors.accent)
        Column(modifier = Modifier.padding(start = Spacing.sm)) {
            Text(stringResource(R.string.shared_setup_title), fontWeight = FontWeight.Medium)
            Text(stringResource(R.string.shared_setup_share_detail), color = AppColors.textMuted)
        }
    }
    GeistCardClickable(onClick = onSave) {
        Icon(Icons.Outlined.SaveAlt, contentDescription = null, tint = AppColors.accent)
        Column(modifier = Modifier.padding(start = Spacing.sm)) {
            Text(stringResource(R.string.shared_setup_save), fontWeight = FontWeight.Medium)
            Text(stringResource(R.string.shared_setup_save_detail), color = AppColors.textMuted)
        }
    }
}

@Composable
private fun SharedSetupReview(preview: SharedSetupPreview, onApply: () -> Unit, onCancel: () -> Unit) {
    val review = preview.review
    Text(
        stringResource(R.string.shared_setup_review),
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.semantics { heading() },
    )
    GeistCard {
        ReviewLine(stringResource(R.string.shared_setup_formats), review.formats.joinToString().ifBlank { stringResource(R.string.shared_setup_none_selected) })
        ReviewLine(stringResource(R.string.shared_setup_selected_metrics), review.metricCount.toString())
        ReviewLine(stringResource(R.string.shared_setup_naming), review.filenameTemplate)
        ReviewLine(stringResource(R.string.shared_setup_units), review.units)
        ReviewLine(stringResource(R.string.shared_setup_daily_notes), if (review.dailyNotesEnabled) stringResource(R.string.shared_setup_on) else stringResource(R.string.shared_setup_off))
        ReviewLine(stringResource(R.string.shared_setup_individual_entries), if (review.individualEntriesEnabled) stringResource(R.string.shared_setup_on) else stringResource(R.string.shared_setup_off))
        ReviewLine(stringResource(R.string.shared_setup_custom_content), if (review.hasCustomContent) stringResource(R.string.shared_setup_custom_included) else stringResource(R.string.shared_setup_none))
        if (review.scheduleRequested) ReviewLine(stringResource(R.string.shared_setup_schedule), stringResource(R.string.shared_setup_remains_off))
        review.endpointDescription?.let { ReviewLine(stringResource(R.string.shared_setup_endpoint), stringResource(R.string.shared_setup_endpoint_no_auth, it)) }
    }
    review.items.forEach { item ->
        SharedSetupCompatibilityCard(item)
    }
    Text(
        stringResource(R.string.shared_setup_device_requirements),
        color = AppColors.textSecondary,
    )
    Button(onClick = onApply, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.shared_setup_apply)) }
    TextButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.shared_setup_cancel)) }
}

@Composable
internal fun SharedSetupCompatibilityCard(item: SharedSetupCompatibilityItem) {
    val statusLabel = when (item.status) {
        SharedSetupCompatibilityStatus.APPLIED -> stringResource(R.string.shared_setup_status_applied)
        SharedSetupCompatibilityStatus.REQUIRES_ACTION -> stringResource(R.string.shared_setup_status_action)
        SharedSetupCompatibilityStatus.UNSUPPORTED -> stringResource(R.string.shared_setup_status_unsupported)
        SharedSetupCompatibilityStatus.INVALID -> stringResource(R.string.shared_setup_status_invalid)
    }
    val statusColor = when (item.status) {
        SharedSetupCompatibilityStatus.APPLIED -> AppColors.success
        SharedSetupCompatibilityStatus.REQUIRES_ACTION -> AppColors.warning
        SharedSetupCompatibilityStatus.UNSUPPORTED -> AppColors.textMuted
        SharedSetupCompatibilityStatus.INVALID -> AppColors.error
    }
    GeistCard(
        modifier = Modifier.clearAndSetSemantics {
            contentDescription = "$statusLabel: ${item.title}. ${item.detail}"
        }
    ) {
        Text(statusLabel, style = MaterialTheme.typography.labelSmall, color = statusColor)
        Text(item.title, fontWeight = FontWeight.Medium)
        Text(item.detail, color = AppColors.textSecondary)
    }
}

@Composable
internal fun SharedSetupSuccess(
    result: SharedSetupApplyResult,
    pendingEndpoint: String?,
    onConfirmEndpoint: (String) -> Unit,
    onUndo: () -> Unit,
    onFinishSetup: () -> Unit,
) {
    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = AppColors.success)
    Text(
        stringResource(R.string.shared_setup_applied),
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.semantics {
            heading()
            liveRegion = LiveRegionMode.Polite
        },
    )
    GeistCard {
        ReviewLine(stringResource(R.string.shared_setup_applied_items), result.review.appliedCount.toString())
        ReviewLine(stringResource(R.string.shared_setup_attention_items), result.review.requiresActionCount.toString())
        ReviewLine(stringResource(R.string.shared_setup_unsupported_items), result.review.unsupportedCount.toString())
    }
    pendingEndpoint?.let {
        PendingEndpointConfirmation(it, onConfirmEndpoint)
    }
    if (result.canUndo) OutlinedButton(onClick = onUndo, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.shared_setup_undo)) }
    Button(onClick = onFinishSetup, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.shared_setup_finish)) }
}

@Composable
private fun PendingEndpointConfirmation(endpoint: String, onConfirm: (String) -> Unit) {
    var authorization by remember(endpoint) { mutableStateOf("") }
    GeistCard {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(stringResource(R.string.shared_setup_finish_endpoint), fontWeight = FontWeight.Medium)
            Text(endpoint, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            Text(
                stringResource(R.string.shared_setup_endpoint_confirmation),
                color = AppColors.textSecondary,
            )
            OutlinedTextField(
                value = authorization,
                onValueChange = { authorization = it },
                label = { Text(stringResource(R.string.shared_setup_authorization_label)) },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { onConfirm(authorization) },
                enabled = authorization.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.shared_setup_confirm_endpoint))
            }
        }
    }
}

@Composable
private fun SharedSetupError(message: String, onDismiss: () -> Unit) {
    Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = AppColors.error)
    Text(
        stringResource(R.string.shared_setup_open_error),
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.semantics {
            heading()
            liveRegion = LiveRegionMode.Assertive
        },
    )
    Text(message, color = AppColors.textSecondary)
    Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.shared_setup_done)) }
}

@Composable
internal fun ReviewLine(label: String, value: String) {
    if (LocalDensity.current.fontScale > 1.3f) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            Text(label, color = AppColors.textSecondary)
            Text(value, fontWeight = FontWeight.Medium)
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Text(label, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
            Text(value, modifier = Modifier.weight(1f), fontWeight = FontWeight.Medium)
        }
    }
    Spacer(Modifier.height(Spacing.xs))
}
