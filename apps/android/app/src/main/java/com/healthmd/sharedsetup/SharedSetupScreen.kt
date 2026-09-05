package com.healthmd.sharedsetup

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material.icons.outlined.SaveAlt
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.storage.FileExportManager
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
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
    val v2TransactionState by viewModel.v2TransactionState.collectAsStateWithLifecycle()
    val v2BlockedProfiles by viewModel.v2BlockedProfiles.collectAsStateWithLifecycle()
    val v2RebindState by viewModel.v2RebindState.collectAsStateWithLifecycle()
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
                is SharedSetupUiState.ReviewV2 -> SharedSetupV2Review(
                    plan = current.plan,
                    transactionState = v2TransactionState,
                    blockedProfiles = v2BlockedProfiles,
                    rebindState = v2RebindState,
                    onApply = viewModel::applyV2,
                    onUndo = viewModel::undoV2,
                    onRebindFolder = viewModel::rebindBlockedProfileFolder,
                    onConfirmApiEndpoint = viewModel::confirmBlockedApiEndpoint,
                    onConfirmApiCredential = viewModel::confirmBlockedApiCredential,
                    onConfirmMacPairing = viewModel::confirmBlockedMacPairing,
                    onResetTransaction = viewModel::resetV2TransactionState,
                    onDismissRebindFailure = viewModel::dismissRebindFailure,
                    onCancel = viewModel::dismiss,
                    onFinishSetup = finishSetup,
                )
                is SharedSetupUiState.Error -> SharedSetupError(current.message, viewModel::dismiss)
            }
        }
    }
}

@Composable
private fun SharedSetupStart(
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

/** Real v2 review: ordered multi-select, Add/Replace mode, apply, one-shot Undo, and rebind. */
@Composable
private fun SharedSetupV2Review(
    plan: SharedSetupV2ImportPlan,
    transactionState: SharedSetupV2TransactionState,
    blockedProfiles: List<SharedSetupV2BlockedImportedProfile>?,
    rebindState: SharedSetupV2RebindState,
    onApply: (List<String>, SharedSetupV2ApplyMode) -> Unit,
    onUndo: () -> Unit,
    onRebindFolder: (String, Uri, String?) -> Unit,
    onConfirmApiEndpoint: (String) -> Unit,
    onConfirmApiCredential: (String, String) -> Unit,
    onConfirmMacPairing: (String) -> Unit,
    onResetTransaction: () -> Unit,
    onDismissRebindFailure: () -> Unit,
    onCancel: () -> Unit,
    onFinishSetup: () -> Unit,
) {
    when (transactionState) {
        SharedSetupV2TransactionState.Idle,
        SharedSetupV2TransactionState.Applying,
        -> SharedSetupV2Selection(
            plan = plan,
            applying = transactionState == SharedSetupV2TransactionState.Applying,
            onApply = onApply,
            onCancel = onCancel,
        )
        is SharedSetupV2TransactionState.Applied -> SharedSetupV2Applied(
            result = transactionState.result,
            blockedProfiles = blockedProfiles,
            rebindState = rebindState,
            onRebindFolder = onRebindFolder,
            onConfirmApiEndpoint = onConfirmApiEndpoint,
            onConfirmApiCredential = onConfirmApiCredential,
            onConfirmMacPairing = onConfirmMacPairing,
            onDismissRebindFailure = onDismissRebindFailure,
            onUndo = onUndo,
            onFinishSetup = onFinishSetup,
        )
        SharedSetupV2TransactionState.Undoing -> {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                CircularProgressIndicator()
                Text(
                    stringResource(R.string.shared_setup_v2_undoing),
                    color = AppColors.textSecondary,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                )
            }
        }
        is SharedSetupV2TransactionState.Undone -> SharedSetupV2Undone(onCancel = onCancel)
        is SharedSetupV2TransactionState.Error -> {
            Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = AppColors.error)
            Text(
                stringResource(R.string.shared_setup_v2_transaction_failed),
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.semantics {
                    heading()
                    liveRegion = LiveRegionMode.Assertive
                },
            )
            Text(transactionState.message, color = AppColors.textSecondary)
            Button(onClick = onResetTransaction, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.shared_setup_v2_try_again))
            }
            TextButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.shared_setup_cancel))
            }
        }
    }
}

/** Honest one-shot-undone result; the heading is a polite live region for TalkBack. */
@Composable
internal fun SharedSetupV2Undone(onCancel: () -> Unit) {
    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = AppColors.success)
    Text(
        stringResource(R.string.shared_setup_v2_undone),
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.semantics {
            heading()
            liveRegion = LiveRegionMode.Polite
        },
    )
    Text(
        stringResource(R.string.shared_setup_v2_undone_detail),
        color = AppColors.textSecondary,
    )
    Button(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.shared_setup_done))
    }
}

@Composable
private fun SharedSetupV2Selection(
    plan: SharedSetupV2ImportPlan,
    applying: Boolean,
    onApply: (List<String>, SharedSetupV2ApplyMode) -> Unit,
    onCancel: () -> Unit,
) {
    var selected by remember(plan) { mutableStateOf(plan.profiles.map { false }) }
    var mode by remember(plan) { mutableStateOf(SharedSetupV2ApplyMode.ADD) }
    val selectedMetricsLabel = stringResource(R.string.shared_setup_selected_metrics)
    val unavailableMetricsLabel = stringResource(R.string.shared_setup_v2_unavailable_metrics)
    val attentionLabel = stringResource(R.string.shared_setup_v2_attention_items)
    val destinationLabel = stringResource(R.string.shared_setup_v2_destination)
    val scheduleLabel = stringResource(R.string.shared_setup_schedule)
    val scheduleOffLabel = stringResource(R.string.shared_setup_remains_off)
    val hasSelection = selected.any { it }

    Text(
        stringResource(R.string.shared_setup_v2_review),
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.semantics { heading() },
    )
    Text(
        stringResource(R.string.shared_setup_v2_profiles),
        color = AppColors.textSecondary,
    )
    GeistCard {
        plan.profiles.forEachIndexed { index, profile ->
            val isSelected = selected[index]
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = Spacing.xxs)
                    .clip(RoundedCornerShape(Radii.card))
                    .background(if (isSelected) AppColors.accentSubtle else Color.Transparent)
                    .clickable(enabled = !applying) {
                        selected = selected.toMutableList().also { it[index] = !it[index] }
                    }
                    .padding(Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = if (applying) null else { _ ->
                        selected = selected.toMutableList().also { it[index] = !it[index] }
                    },
                    colors = CheckboxDefaults.colors(
                        checkedColor = AppColors.accent,
                        uncheckedColor = AppColors.textMuted,
                        checkmarkColor = AppColors.onAccent,
                    ),
                )
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = Spacing.xs),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xxs),
                ) {
                    Text(
                        profile.name,
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        "$selectedMetricsLabel: ${profile.supportedMetricIds.size}",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                    )
                    if (profile.unavailableMetricIds.isNotEmpty()) {
                        Text(
                            "$unavailableMetricsLabel: ${profile.unavailableMetricIds.size}",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.textSecondary,
                        )
                    }
                    val attentionCount = profile.compatibility.count {
                        it.status == SharedSetupV2CompatibilityStatus.REQUIRES_ACTION ||
                            it.status == SharedSetupV2CompatibilityStatus.UNSUPPORTED
                    }
                    if (attentionCount > 0) {
                        Text(
                            "$attentionLabel: $attentionCount",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.warning,
                        )
                    }
                    Text(
                        "$destinationLabel: ${destinationKindLabel(profile.destinationIntent.source.kind)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                    )
                    if (profile.scheduleIntent != null) {
                        Text(
                            "$scheduleLabel: $scheduleOffLabel",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.textSecondary,
                        )
                    }
                }
            }
        }
    }
    if (!hasSelection && !applying) {
        Text(
            stringResource(R.string.shared_setup_v2_select_hint),
            color = AppColors.textMuted,
        )
    }
    Text(
        stringResource(R.string.shared_setup_v2_import_mode),
        color = AppColors.textSecondary,
    )
    GeistCard {
        SharedSetupV2ModeOption(
            label = stringResource(R.string.shared_setup_v2_mode_add),
            detail = stringResource(R.string.shared_setup_v2_mode_add_detail),
            selected = mode == SharedSetupV2ApplyMode.ADD,
            enabled = !applying,
            onSelect = { mode = SharedSetupV2ApplyMode.ADD },
        )
        SharedSetupV2ModeOption(
            label = stringResource(R.string.shared_setup_v2_mode_replace),
            detail = stringResource(R.string.shared_setup_v2_mode_replace_detail),
            selected = mode == SharedSetupV2ApplyMode.REPLACE,
            enabled = !applying,
            onSelect = { mode = SharedSetupV2ApplyMode.REPLACE },
        )
    }
    Text(
        stringResource(R.string.shared_setup_device_requirements),
        color = AppColors.textSecondary,
    )
    Button(
        onClick = {
            val selection = plan.profiles.mapIndexedNotNull { index, profile ->
                profile.bundleId.takeIf { selected[index] }
            }
            onApply(selection, mode)
        },
        enabled = hasSelection && !applying,
        modifier = Modifier.fillMaxWidth(),
    ) { Text(stringResource(R.string.shared_setup_apply)) }
    TextButton(
        onClick = onCancel,
        enabled = !applying,
        modifier = Modifier.fillMaxWidth(),
    ) { Text(stringResource(R.string.shared_setup_cancel)) }
}

@Composable
private fun SharedSetupV2ModeOption(
    label: String,
    detail: String,
    selected: Boolean,
    enabled: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(if (selected) AppColors.accentSubtle else Color.Transparent)
            .clickable(enabled = enabled) { onSelect() }
            .padding(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(
            selected = selected,
            onClick = if (enabled) onSelect else null,
            colors = RadioButtonDefaults.colors(
                selectedColor = AppColors.accent,
                unselectedColor = AppColors.textMuted,
            ),
        )
        Column(modifier = Modifier.padding(start = Spacing.xs)) {
            Text(
                label,
                color = if (selected) AppColors.textPrimary else AppColors.textSecondary,
                style = MaterialTheme.typography.bodyLarge,
            )
            Text(detail, color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun SharedSetupV2Applied(
    result: SharedSetupV2ApplyResult,
    blockedProfiles: List<SharedSetupV2BlockedImportedProfile>?,
    rebindState: SharedSetupV2RebindState,
    onRebindFolder: (String, Uri, String?) -> Unit,
    onConfirmApiEndpoint: (String) -> Unit,
    onConfirmApiCredential: (String, String) -> Unit,
    onConfirmMacPairing: (String) -> Unit,
    onDismissRebindFailure: () -> Unit,
    onUndo: () -> Unit,
    onFinishSetup: () -> Unit,
) {
    val context = LocalContext.current
    var rebindTargetId by remember { mutableStateOf<String?>(null) }
    var macConfirmTargetId by remember { mutableStateOf<String?>(null) }
    val folderPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri ->
        val targetId = rebindTargetId
        rebindTargetId = null
        if (uri != null && targetId != null) {
            val manager = FileExportManager(context)
            manager.takePersistablePermission(uri)
            onRebindFolder(targetId, uri, manager.getFolderDisplayName(uri.toString()))
        }
    }
    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = AppColors.success)
    Text(
        stringResource(R.string.shared_setup_v2_applied),
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.semantics {
            heading()
            liveRegion = LiveRegionMode.Polite
        },
    )
    GeistCard {
        ReviewLine(
            stringResource(R.string.shared_setup_v2_applied_count),
            result.selectedBundleIds.size.toString(),
        )
        ReviewLine(
            stringResource(R.string.shared_setup_v2_import_mode),
            applyModeLabel(result.mode),
        )
    }
    Text(
        stringResource(R.string.shared_setup_v2_blocked_title),
        fontWeight = FontWeight.Medium,
    )
    Text(
        stringResource(R.string.shared_setup_v2_blocked_notice),
        style = MaterialTheme.typography.bodySmall,
        color = AppColors.textSecondary,
    )
    if (
        rebindState == SharedSetupV2RebindState.Rebinding ||
        rebindState == SharedSetupV2RebindState.ConfirmingApiEndpoint ||
        rebindState == SharedSetupV2RebindState.ConfirmingApiCredential ||
        rebindState == SharedSetupV2RebindState.ConfirmingMacPairing
    ) {
        Text(
            stringResource(R.string.shared_setup_v2_rebinding),
            color = AppColors.textMuted,
        )
    }
    if (rebindState is SharedSetupV2RebindState.Failed) {
        Text(rebindState.message, color = AppColors.error)
        TextButton(
            onClick = onDismissRebindFailure,
            modifier = Modifier.fillMaxWidth(),
        ) { Text(stringResource(R.string.shared_setup_done)) }
    }
    blockedProfiles?.forEach { blocked ->
        GeistCard {
            Text(blocked.name, fontWeight = FontWeight.Medium)
            ReviewLine(
                stringResource(R.string.shared_setup_v2_destination),
                destinationKindLabel(blocked.sourceDestinationKind),
            )
            when (blocked.sourceDestinationKind) {
                "device_folder" -> OutlinedButton(
                    onClick = {
                        rebindTargetId = blocked.profileId
                        folderPicker.launch(null)
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.shared_setup_v2_rebind_folder)) }
                "api_endpoint" -> BlockedApiEndpointRebind(
                    blocked = blocked,
                    onConfirmEndpoint = { onConfirmApiEndpoint(blocked.profileId) },
                    onConfirmCredential = { authorization ->
                        onConfirmApiCredential(blocked.profileId, authorization)
                    },
                )
                "connected_mac" -> OutlinedButton(
                    onClick = { macConfirmTargetId = blocked.profileId },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.shared_setup_v2_rebind_mac_action)) }
                else -> Text(
                    stringResource(R.string.shared_setup_v2_rebind_cloud_unavailable),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
            }
        }
    }
    macConfirmTargetId?.let { targetId ->
        BlockedMacPairingConfirmation(
            onConfirm = {
                macConfirmTargetId = null
                onConfirmMacPairing(targetId)
            },
            onDismiss = { macConfirmTargetId = null },
        )
    }
    if (result.canUndo) {
        OutlinedButton(onClick = onUndo, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.shared_setup_undo))
        }
    }
    Button(onClick = onFinishSetup, modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.shared_setup_finish))
    }
}

/**
 * In-flow endpoint rebind for one blocked API-endpoint imported profile (v2 review). While the
 * destination is unbound and the sidecar retains the imported endpoint URL, the row offers an
 * explicit confirmation of exactly that URL (mirroring the Apple twin's semantics — the app
 * never guesses or edits the identity); once a local binding exists (in-flow confirmation or
 * profile editor), the row offers the verified credential entry instead. When the imported
 * identity was not retained, the row stays honestly blocked and points at the editor.
 */
@Composable
private fun BlockedApiEndpointRebind(
    blocked: SharedSetupV2BlockedImportedProfile,
    onConfirmEndpoint: () -> Unit,
    onConfirmCredential: (String) -> Unit,
) {
    val importedUrl = blocked.importedApiEndpointUrl
    var urlConfirmOpen by remember { mutableStateOf(false) }
    when {
        blocked.boundApiEndpointUrl != null -> BlockedApiCredentialConfirmation(onConfirm = onConfirmCredential)
        importedUrl != null -> {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(
                    stringResource(R.string.shared_setup_v2_rebind_api_url_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
                Text(
                    importedUrl,
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textPrimary,
                )
                OutlinedButton(
                    onClick = { urlConfirmOpen = true },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.shared_setup_v2_rebind_api_url_action)) }
            }
        }
        else -> Text(
            stringResource(R.string.shared_setup_v2_rebind_api_unretained),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )
    }
    if (urlConfirmOpen && importedUrl != null) {
        BlockedApiEndpointUrlConfirmation(
            url = importedUrl,
            onConfirm = {
                urlConfirmOpen = false
                onConfirmEndpoint()
            },
            onDismiss = { urlConfirmOpen = false },
        )
    }
}

/**
 * Explicit confirmation dialog for one imported API endpoint URL (Apple twin precedent: the
 * confirmed URL is exactly what the v2 import retained — shown verbatim, never editable).
 * Confirming binds the endpoint locally through the editor-path seam; canceling keeps the
 * profile blocked and writes nothing.
 */
@Composable
private fun BlockedApiEndpointUrlConfirmation(
    url: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.shared_setup_v2_rebind_api_url_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.shared_setup_v2_rebind_api_url_body))
                Text(
                    url,
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textPrimary,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.shared_setup_v2_rebind_api_url_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.shared_setup_cancel))
            }
        },
    )
}

/**
 * In-flow credential entry for one blocked API-endpoint imported profile (v2 review). A
 * password-masked authorization field whose value is handed to the ViewModel's verified
 * persistence seam — never stored in the UI layer.
 */
@Composable
private fun BlockedApiCredentialConfirmation(onConfirm: (String) -> Unit) {
    var authorization by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(
            stringResource(R.string.shared_setup_v2_rebind_api_title),
            fontWeight = FontWeight.Medium,
        )
        Text(
            stringResource(R.string.shared_setup_v2_rebind_api_hint),
            style = MaterialTheme.typography.bodySmall,
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
        ) { Text(stringResource(R.string.shared_setup_v2_rebind_api_confirm)) }
    }
}

/**
 * Attestation-only connected-Mac pairing confirmation for one blocked imported profile. There
 * is no credential to enter: confirming attests that this Android device is currently paired
 * with the Mac that produced the imported profile (Apple's "Mac Is Paired — Rebind"
 * precedent), and only that explicit attestation can clear the block. Cloud destinations are
 * deliberately not offered here — they stay blocked on Android.
 */
@Composable
private fun BlockedMacPairingConfirmation(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.shared_setup_v2_rebind_mac_title)) },
        text = {
            Text(stringResource(R.string.shared_setup_v2_rebind_mac_body))
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.shared_setup_v2_rebind_mac_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.shared_setup_cancel))
            }
        },
    )
}

@Composable
private fun destinationKindLabel(kind: String): String = when (kind) {
    "device_folder" -> stringResource(R.string.shared_setup_v2_destination_device_folder)
    "connected_mac" -> stringResource(R.string.shared_setup_v2_destination_connected_mac)
    "api_endpoint" -> stringResource(R.string.shared_setup_v2_destination_api_endpoint)
    "cloud" -> stringResource(R.string.shared_setup_v2_destination_cloud)
    else -> stringResource(R.string.shared_setup_v2_destination_unknown)
}

@Composable
private fun applyModeLabel(mode: SharedSetupV2ApplyMode): String = when (mode) {
    SharedSetupV2ApplyMode.ADD -> stringResource(R.string.shared_setup_v2_mode_add)
    SharedSetupV2ApplyMode.REPLACE -> stringResource(R.string.shared_setup_v2_mode_replace)
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
