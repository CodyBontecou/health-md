package com.healthmd.sharedsetup

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.SaveAlt
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.storage.FileExportManager
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.settings.SettingsRow
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import kotlinx.coroutines.launch

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

    when (val current = state) {
        is SharedSetupUiState.Idle -> SharedSetupStart(
            onBack = finishAndBack,
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
        SharedSetupUiState.Loading -> SharedSetupStep(onBack = finishAndBack) {
            SharedSetupProgress(stringResource(R.string.shared_setup_checking), liveRegion = false)
        }
        is SharedSetupUiState.ReviewV2 -> SharedSetupV2Review(
            plan = current.plan,
            transactionState = v2TransactionState,
            blockedProfiles = v2BlockedProfiles,
            rebindState = v2RebindState,
            onBack = finishAndBack,
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
        is SharedSetupUiState.Error -> SharedSetupError(current.message, onBack = finishAndBack, onDismiss = viewModel::dismiss)
    }
}

/**
 * One step of the flow: the sub-screen bar, a scrolling 16dp-gutter body, and an optional pinned
 * action bar that carries the step's single filled primary action.
 */
@Composable
private fun SharedSetupStep(
    onBack: (() -> Unit)?,
    bottomBar: (@Composable ColumnScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    SubScreen(
        title = stringResource(R.string.shared_setup_title),
        onBack = onBack,
        bottomBar = bottomBar?.let { actions -> { SharedSetupActionBar(actions) } },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(
                    start = GeistSpacing.space4,
                    end = GeistSpacing.space4,
                    top = GeistSpacing.space2,
                    bottom = GeistSpacing.space6,
                ),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
            content = content,
        )
    }
}

/** Pinned step actions on `background-200`, centered at the readable width. */
@Composable
private fun SharedSetupActionBar(content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalGeistColors.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.background200)
            .navigationBarsPadding(),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = GeistSizes.readableContentMaxWidth)
                .fillMaxWidth()
                // A scroll container keeps the pinned actions reachable by scroll-to semantics
                // (accessibility services and the instrumented performScrollTo contract).
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            content = content,
        )
    }
}

@Composable
private fun SharedSetupStart(
    onBack: () -> Unit,
    onOpen: () -> Unit,
    onSave: () -> Unit,
    onShare: () -> Unit,
) {
    val colors = LocalGeistColors.current
    SharedSetupStep(onBack = onBack) {
        Text(
            stringResource(R.string.shared_setup_intro),
            style = GeistType.copy16,
            color = colors.secondary,
        )
        SharedSetupNote(
            tone = SharedSetupNoteTone.INFO,
            message = stringResource(R.string.shared_setup_sender_disclosure),
        )
        val actions = listOf(
            Triple(R.string.shared_setup_use, R.string.shared_setup_use_detail, Icons.Outlined.FileOpen) to onOpen,
            Triple(R.string.shared_setup_title, R.string.shared_setup_share_detail, Icons.Outlined.Share) to onShare,
            Triple(R.string.shared_setup_save, R.string.shared_setup_save_detail, Icons.Outlined.SaveAlt) to onSave,
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            actions.forEachIndexed { index, (labels, onClick) ->
                SettingsRow(
                    shape = groupRowShape(index, actions.size),
                    title = stringResource(labels.first),
                    subtitle = stringResource(labels.second),
                    icon = labels.third,
                    onClick = onClick,
                )
            }
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
    onBack: () -> Unit,
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
            onBack = onBack,
            onApply = onApply,
            onCancel = onCancel,
        )
        is SharedSetupV2TransactionState.Applied -> SharedSetupV2Applied(
            result = transactionState.result,
            blockedProfiles = blockedProfiles,
            rebindState = rebindState,
            onBack = onBack,
            onRebindFolder = onRebindFolder,
            onConfirmApiEndpoint = onConfirmApiEndpoint,
            onConfirmApiCredential = onConfirmApiCredential,
            onConfirmMacPairing = onConfirmMacPairing,
            onDismissRebindFailure = onDismissRebindFailure,
            onUndo = onUndo,
            onFinishSetup = onFinishSetup,
        )
        SharedSetupV2TransactionState.Undoing -> SharedSetupStep(onBack = onBack) {
            SharedSetupProgress(stringResource(R.string.shared_setup_v2_undoing), liveRegion = true)
        }
        is SharedSetupV2TransactionState.Undone -> SharedSetupV2Undone(onCancel = onCancel, onBack = onBack)
        is SharedSetupV2TransactionState.Error -> SharedSetupStep(
            onBack = onBack,
            bottomBar = {
                PrimaryButton(
                    text = stringResource(R.string.shared_setup_v2_try_again),
                    onClick = onResetTransaction,
                )
                SharedSetupTextAction(stringResource(R.string.shared_setup_cancel), onClick = onCancel)
            },
        ) {
            SharedSetupStatusHeading(
                icon = Icons.Outlined.ErrorOutline,
                tone = SharedSetupNoteTone.ERROR,
                title = stringResource(R.string.shared_setup_v2_transaction_failed),
                liveRegion = LiveRegionMode.Assertive,
            )
            SharedSetupNote(tone = SharedSetupNoteTone.ERROR, message = transactionState.message)
        }
    }
}

/** Honest one-shot-undone result; the heading is a polite live region for TalkBack. */
@Composable
internal fun SharedSetupV2Undone(onCancel: () -> Unit, onBack: (() -> Unit)? = null) {
    val colors = LocalGeistColors.current
    SharedSetupStep(
        onBack = onBack,
        bottomBar = {
            PrimaryButton(text = stringResource(R.string.shared_setup_done), onClick = onCancel)
        },
    ) {
        SharedSetupStatusHeading(
            icon = Icons.Outlined.CheckCircle,
            tone = null,
            title = stringResource(R.string.shared_setup_v2_undone),
            liveRegion = LiveRegionMode.Polite,
        )
        Text(
            stringResource(R.string.shared_setup_v2_undone_detail),
            style = GeistType.copy16,
            color = colors.secondary,
        )
    }
}

@Composable
private fun SharedSetupV2Selection(
    plan: SharedSetupV2ImportPlan,
    applying: Boolean,
    onBack: () -> Unit,
    onApply: (List<String>, SharedSetupV2ApplyMode) -> Unit,
    onCancel: () -> Unit,
) {
    val colors = LocalGeistColors.current
    var selected by remember(plan) { mutableStateOf(plan.profiles.map { false }) }
    var mode by remember(plan) { mutableStateOf(SharedSetupV2ApplyMode.ADD) }
    val selectedMetricsLabel = stringResource(R.string.shared_setup_selected_metrics)
    val unavailableMetricsLabel = stringResource(R.string.shared_setup_v2_unavailable_metrics)
    val attentionLabel = stringResource(R.string.shared_setup_v2_attention_items)
    val destinationLabel = stringResource(R.string.shared_setup_v2_destination)
    val scheduleLabel = stringResource(R.string.shared_setup_schedule)
    val scheduleOffLabel = stringResource(R.string.shared_setup_remains_off)
    val hasSelection = selected.any { it }

    SharedSetupStep(
        onBack = onBack,
        bottomBar = {
            AdaptiveActionPair(
                primaryAction = { modifier ->
                    PrimaryButton(
                        text = stringResource(R.string.shared_setup_apply),
                        onClick = {
                            val selection = plan.profiles.mapIndexedNotNull { index, profile ->
                                profile.bundleId.takeIf { selected[index] }
                            }
                            onApply(selection, mode)
                        },
                        enabled = hasSelection && !applying,
                        modifier = modifier,
                    )
                },
                secondaryAction = { modifier ->
                    SharedSetupTextAction(
                        stringResource(R.string.shared_setup_cancel),
                        onClick = onCancel,
                        enabled = !applying,
                        modifier = modifier,
                    )
                },
            )
        },
    ) {
        Text(
            stringResource(R.string.shared_setup_v2_review),
            style = GeistType.heading24,
            color = colors.primary,
            modifier = Modifier.semantics { heading() },
        )
        SharedSetupGroup(title = stringResource(R.string.shared_setup_v2_profiles)) {
            plan.profiles.forEachIndexed { index, profile ->
                val isSelected = selected[index]
                val toggle = { selected = selected.toMutableList().also { it[index] = !it[index] } }
                SharedSetupChoiceRow(
                    shape = groupRowShape(index, plan.profiles.size),
                    selected = isSelected,
                    enabled = !applying,
                    onClick = toggle,
                    control = {
                        Checkbox(
                            checked = isSelected,
                            onCheckedChange = if (applying) null else { _ -> toggle() },
                            colors = CheckboxDefaults.colors(
                                checkedColor = colors.brandPrimary,
                                uncheckedColor = colors.secondary,
                                checkmarkColor = colors.brandOnPrimary,
                            ),
                        )
                    },
                ) {
                    Text(profile.name, style = GeistType.label16, color = colors.primary)
                    ProfileDetail("$selectedMetricsLabel: ${profile.supportedMetricIds.size}")
                    if (profile.unavailableMetricIds.isNotEmpty()) {
                        ProfileDetail("$unavailableMetricsLabel: ${profile.unavailableMetricIds.size}")
                    }
                    val attentionCount = profile.compatibility.count {
                        it.status == SharedSetupV2CompatibilityStatus.REQUIRES_ACTION ||
                            it.status == SharedSetupV2CompatibilityStatus.UNSUPPORTED
                    }
                    if (attentionCount > 0) {
                        ProfileDetail("$attentionLabel: $attentionCount", color = colors.warning)
                    }
                    ProfileDetail("$destinationLabel: ${destinationKindLabel(profile.destinationIntent.source.kind)}")
                    if (profile.scheduleIntent != null) {
                        ProfileDetail("$scheduleLabel: $scheduleOffLabel")
                    }
                }
            }
        }
        if (!hasSelection && !applying) {
            Text(
                stringResource(R.string.shared_setup_v2_select_hint),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space4),
            )
        }
        SharedSetupGroup(title = stringResource(R.string.shared_setup_v2_import_mode)) {
            SharedSetupV2ModeOption(
                shape = groupRowShape(0, 2),
                label = stringResource(R.string.shared_setup_v2_mode_add),
                detail = stringResource(R.string.shared_setup_v2_mode_add_detail),
                selected = mode == SharedSetupV2ApplyMode.ADD,
                enabled = !applying,
                onSelect = { mode = SharedSetupV2ApplyMode.ADD },
            )
            SharedSetupV2ModeOption(
                shape = groupRowShape(1, 2),
                label = stringResource(R.string.shared_setup_v2_mode_replace),
                detail = stringResource(R.string.shared_setup_v2_mode_replace_detail),
                selected = mode == SharedSetupV2ApplyMode.REPLACE,
                enabled = !applying,
                onSelect = { mode = SharedSetupV2ApplyMode.REPLACE },
            )
        }
        SharedSetupNote(
            tone = SharedSetupNoteTone.INFO,
            message = stringResource(R.string.shared_setup_device_requirements),
        )
    }
}

/** A list group (DESIGN.md `list-group`): a `heading-14` brand heading over rows 2dp apart. */
@Composable
private fun SharedSetupGroup(title: String, rows: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        SharedSetupGroupHeading(title)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), content = rows)
    }
}

@Composable
private fun SharedSetupGroupHeading(title: String) {
    Text(
        text = title,
        style = GeistType.heading14,
        color = LocalGeistColors.current.brandPrimary,
        modifier = Modifier
            .padding(start = GeistSpacing.space4, top = GeistSpacing.space2)
            .semantics { heading() },
    )
}

@Composable
private fun ProfileDetail(text: String, color: Color = LocalGeistColors.current.secondary) {
    Text(text, style = GeistType.copy14, color = color)
}

/** A selectable list-group row: leading checkbox or radio, then wrapping text content. */
@Composable
private fun SharedSetupChoiceRow(
    shape: Shape,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    control: @Composable () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) colors.secondaryContainer else colors.background200)
            .clickable(enabled = enabled, onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(
                start = GeistSpacing.space1,
                end = GeistSpacing.space4,
                top = GeistSpacing.space2,
                bottom = GeistSpacing.space2,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        control()
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = GeistSpacing.space2),
            verticalArrangement = Arrangement.spacedBy(2.dp),
            content = content,
        )
    }
}

@Composable
private fun SharedSetupV2ModeOption(
    shape: Shape,
    label: String,
    detail: String,
    selected: Boolean,
    enabled: Boolean,
    onSelect: () -> Unit,
) {
    val colors = LocalGeistColors.current
    SharedSetupChoiceRow(
        shape = shape,
        selected = selected,
        enabled = enabled,
        onClick = onSelect,
        control = {
            RadioButton(
                selected = selected,
                onClick = if (enabled) onSelect else null,
                colors = RadioButtonDefaults.colors(
                    selectedColor = colors.brandPrimary,
                    unselectedColor = colors.secondary,
                ),
            )
        },
    ) {
        Text(label, style = GeistType.label16, color = colors.primary)
        Text(detail, style = GeistType.copy14, color = colors.secondary)
    }
}

@Composable
private fun SharedSetupV2Applied(
    result: SharedSetupV2ApplyResult,
    blockedProfiles: List<SharedSetupV2BlockedImportedProfile>?,
    rebindState: SharedSetupV2RebindState,
    onBack: () -> Unit,
    onRebindFolder: (String, Uri, String?) -> Unit,
    onConfirmApiEndpoint: (String) -> Unit,
    onConfirmApiCredential: (String, String) -> Unit,
    onConfirmMacPairing: (String) -> Unit,
    onDismissRebindFailure: () -> Unit,
    onUndo: () -> Unit,
    onFinishSetup: () -> Unit,
) {
    val colors = LocalGeistColors.current
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
    SharedSetupStep(
        onBack = onBack,
        bottomBar = {
            val finish = @Composable { modifier: Modifier ->
                PrimaryButton(
                    text = stringResource(R.string.shared_setup_finish),
                    onClick = onFinishSetup,
                    modifier = modifier,
                )
            }
            if (result.canUndo) {
                AdaptiveActionPair(
                    primaryAction = finish,
                    secondaryAction = { modifier ->
                        SecondaryButton(
                            text = stringResource(R.string.shared_setup_undo),
                            onClick = onUndo,
                            modifier = modifier,
                        )
                    },
                )
            } else {
                finish(Modifier)
            }
        },
    ) {
        SharedSetupStatusHeading(
            icon = Icons.Outlined.CheckCircle,
            tone = null,
            title = stringResource(R.string.shared_setup_v2_applied),
            liveRegion = LiveRegionMode.Polite,
        )
        val summary = listOf(
            stringResource(R.string.shared_setup_v2_applied_count) to result.selectedBundleIds.size.toString(),
            stringResource(R.string.shared_setup_v2_import_mode) to applyModeLabel(result.mode),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            summary.forEachIndexed { index, (label, value) ->
                ReviewRow(groupRowShape(index, summary.size)) { ReviewLine(label, value) }
            }
        }
        SharedSetupGroupHeading(stringResource(R.string.shared_setup_v2_blocked_title))
        SharedSetupNote(
            tone = SharedSetupNoteTone.WARNING,
            message = stringResource(R.string.shared_setup_v2_blocked_notice),
        )
        if (
            rebindState == SharedSetupV2RebindState.Rebinding ||
            rebindState == SharedSetupV2RebindState.ConfirmingApiEndpoint ||
            rebindState == SharedSetupV2RebindState.ConfirmingApiCredential ||
            rebindState == SharedSetupV2RebindState.ConfirmingMacPairing
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
                modifier = Modifier.padding(horizontal = GeistSpacing.space4),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = colors.brandPrimary,
                    strokeWidth = 2.dp,
                )
                Text(
                    stringResource(R.string.shared_setup_v2_rebinding),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
            }
        }
        if (rebindState is SharedSetupV2RebindState.Failed) {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
                SharedSetupNote(tone = SharedSetupNoteTone.ERROR, message = rebindState.message)
                SharedSetupTextAction(
                    stringResource(R.string.shared_setup_done),
                    onClick = onDismissRebindFailure,
                    modifier = Modifier.align(Alignment.End),
                )
            }
        }
        val blocked = blockedProfiles.orEmpty()
        if (blocked.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                blocked.forEachIndexed { index, profile ->
                    ReviewRow(groupRowShape(index, blocked.size)) {
                        Text(profile.name, style = GeistType.label16, color = colors.primary)
                        ReviewLine(
                            stringResource(R.string.shared_setup_v2_destination),
                            destinationKindLabel(profile.sourceDestinationKind),
                        )
                        when (profile.sourceDestinationKind) {
                            "device_folder" -> SecondaryButton(
                                text = stringResource(R.string.shared_setup_v2_rebind_folder),
                                onClick = {
                                    rebindTargetId = profile.profileId
                                    folderPicker.launch(null)
                                },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            "api_endpoint" -> BlockedApiEndpointRebind(
                                blocked = profile,
                                onConfirmEndpoint = { onConfirmApiEndpoint(profile.profileId) },
                                onConfirmCredential = { authorization ->
                                    onConfirmApiCredential(profile.profileId, authorization)
                                },
                            )
                            "connected_mac" -> SecondaryButton(
                                text = stringResource(R.string.shared_setup_v2_rebind_mac_action),
                                onClick = { macConfirmTargetId = profile.profileId },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            else -> Text(
                                stringResource(R.string.shared_setup_v2_rebind_cloud_unavailable),
                                style = GeistType.copy14,
                                color = colors.secondary,
                            )
                        }
                    }
                }
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
}

/** A tonal list-group row that stacks review lines and controls. */
@Composable
private fun ReviewRow(shape: Shape, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(LocalGeistColors.current.background200)
            .heightIn(min = 56.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2, Alignment.CenterVertically),
        content = content,
    )
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
    val colors = LocalGeistColors.current
    val importedUrl = blocked.importedApiEndpointUrl
    var urlConfirmOpen by remember { mutableStateOf(false) }
    when {
        blocked.boundApiEndpointUrl != null -> BlockedApiCredentialConfirmation(onConfirm = onConfirmCredential)
        importedUrl != null -> {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                Text(
                    stringResource(R.string.shared_setup_v2_rebind_api_url_hint),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
                Text(importedUrl, style = GeistType.copy14Mono, color = colors.primary)
                SecondaryButton(
                    text = stringResource(R.string.shared_setup_v2_rebind_api_url_action),
                    onClick = { urlConfirmOpen = true },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        else -> Text(
            stringResource(R.string.shared_setup_v2_rebind_api_unretained),
            style = GeistType.copy14,
            color = colors.secondary,
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
    val colors = LocalGeistColors.current
    SharedSetupConfirmDialog(
        icon = Icons.Outlined.Link,
        title = stringResource(R.string.shared_setup_v2_rebind_api_url_title),
        confirmLabel = stringResource(R.string.shared_setup_v2_rebind_api_url_confirm),
        onConfirm = onConfirm,
        onDismiss = onDismiss,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
            Text(
                stringResource(R.string.shared_setup_v2_rebind_api_url_body),
                style = GeistType.copy14,
                color = colors.secondary,
            )
            Text(url, style = GeistType.copy14Mono, color = colors.primary)
        }
    }
}

/**
 * In-flow credential entry for one blocked API-endpoint imported profile (v2 review). A
 * password-masked authorization field whose value is handed to the ViewModel's verified
 * persistence seam — never stored in the UI layer.
 */
@Composable
private fun BlockedApiCredentialConfirmation(onConfirm: (String) -> Unit) {
    val colors = LocalGeistColors.current
    var authorization by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        Text(
            stringResource(R.string.shared_setup_v2_rebind_api_title),
            style = GeistType.label14,
            color = colors.primary,
        )
        Text(
            stringResource(R.string.shared_setup_v2_rebind_api_hint),
            style = GeistType.copy14,
            color = colors.secondary,
        )
        OutlinedTextField(
            value = authorization,
            onValueChange = { authorization = it },
            label = { Text(stringResource(R.string.shared_setup_authorization_label)) },
            visualTransformation = PasswordVisualTransformation(),
            singleLine = true,
            textStyle = GeistType.copy14Mono,
            modifier = Modifier.fillMaxWidth(),
        )
        SecondaryButton(
            text = stringResource(R.string.shared_setup_v2_rebind_api_confirm),
            onClick = { onConfirm(authorization) },
            enabled = authorization.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        )
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
    val colors = LocalGeistColors.current
    SharedSetupConfirmDialog(
        icon = Icons.Outlined.Computer,
        title = stringResource(R.string.shared_setup_v2_rebind_mac_title),
        confirmLabel = stringResource(R.string.shared_setup_v2_rebind_mac_confirm),
        onConfirm = onConfirm,
        onDismiss = onDismiss,
    ) {
        Text(
            stringResource(R.string.shared_setup_v2_rebind_mac_body),
            style = GeistType.copy14,
            color = colors.secondary,
        )
    }
}

/** M3 confirmation: 28dp `gray-200` container, hero icon, filled-pill confirm, text Cancel. */
@Composable
private fun SharedSetupConfirmDialog(
    icon: ImageVector,
    title: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    body: @Composable () -> Unit,
) {
    val colors = LocalGeistColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        icon = { Icon(icon, contentDescription = null, tint = colors.brandPrimary) },
        title = { Text(title, style = GeistType.heading20, color = colors.primary) },
        text = body,
        confirmButton = {
            Button(
                onClick = onConfirm,
                shape = RoundedCornerShape(GeistRadii.full),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.brandPrimary,
                    contentColor = colors.brandOnPrimary,
                ),
            ) { Text(confirmLabel, style = GeistType.button14) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.shared_setup_cancel), style = GeistType.button14, color = colors.brandPrimary)
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
private fun SharedSetupError(message: String, onBack: () -> Unit, onDismiss: () -> Unit) {
    SharedSetupStep(
        onBack = onBack,
        bottomBar = {
            PrimaryButton(text = stringResource(R.string.shared_setup_done), onClick = onDismiss)
        },
    ) {
        SharedSetupStatusHeading(
            icon = Icons.Outlined.ErrorOutline,
            tone = SharedSetupNoteTone.ERROR,
            title = stringResource(R.string.shared_setup_open_error),
            liveRegion = LiveRegionMode.Assertive,
        )
        SharedSetupNote(tone = SharedSetupNoteTone.ERROR, message = message)
    }
}

/** Centered progress for checking and undoing; undoing announces politely. */
@Composable
private fun SharedSetupProgress(text: String, liveRegion: Boolean) {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = GeistSpacing.space10),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        CircularProgressIndicator(color = colors.brandPrimary)
        Text(
            text,
            style = GeistType.copy16,
            color = colors.secondary,
            modifier = if (liveRegion) Modifier.semantics { this.liveRegion = LiveRegionMode.Polite } else Modifier,
        )
    }
}

/** Outcome heading: a tonal icon circle and a `heading-24` live-region headline. */
@Composable
private fun SharedSetupStatusHeading(
    icon: ImageVector,
    tone: SharedSetupNoteTone?,
    title: String,
    liveRegion: LiveRegionMode,
) {
    val colors = LocalGeistColors.current
    val (container, tint) = when (tone) {
        SharedSetupNoteTone.ERROR -> colors.red.c100 to colors.error
        SharedSetupNoteTone.WARNING -> colors.amber.c100 to colors.warning
        else -> colors.green.c100 to colors.success
    }
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
        Box(
            Modifier
                .size(GeistSizes.controlLarge)
                .background(container, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint)
        }
        Text(
            title,
            style = GeistType.heading24,
            color = colors.primary,
            modifier = Modifier.semantics {
                heading()
                this.liveRegion = liveRegion
            },
        )
    }
}

private enum class SharedSetupNoteTone { INFO, WARNING, ERROR }

/** Tonal info/warning/error note (the Export preview note pattern); no border. */
@Composable
private fun SharedSetupNote(
    tone: SharedSetupNoteTone,
    message: String,
    modifier: Modifier = Modifier,
    title: String? = null,
) {
    val colors = LocalGeistColors.current
    val (container, accent, icon) = when (tone) {
        SharedSetupNoteTone.INFO -> Triple(colors.gray.c200, colors.secondary, Icons.Outlined.Info)
        SharedSetupNoteTone.WARNING -> Triple(colors.amber.c100, colors.warning, Icons.Outlined.WarningAmber)
        SharedSetupNoteTone.ERROR -> Triple(colors.red.c100, colors.error, Icons.Outlined.ErrorOutline)
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.medium))
            .background(container)
            .padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
            title?.let { Text(it, style = GeistType.heading14, color = accent) }
            Text(message, style = GeistType.copy14, color = colors.primary)
        }
    }
}

@Composable
private fun SharedSetupTextAction(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val colors = LocalGeistColors.current
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.heightIn(min = GeistSizes.controlLarge),
    ) {
        Text(text, style = GeistType.button14, color = if (enabled) colors.brandPrimary else colors.gray.c700)
    }
}

/**
 * One label/value review line. Side by side (mirrored in RTL) at normal font scales; the value
 * stacks under its label above 1.3x so neither truncates. [mono] is for paths and identifiers.
 */
@Composable
internal fun ReviewLine(label: String, value: String, mono: Boolean = false) {
    val colors = LocalGeistColors.current
    val valueStyle = if (mono) GeistType.label14Mono else GeistType.label14
    if (LocalDensity.current.fontScale > 1.3f) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
        ) {
            Text(label, style = GeistType.copy14, color = colors.secondary)
            Text(value, style = valueStyle, color = colors.primary)
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
        ) {
            Text(label, style = GeistType.copy14, color = colors.secondary, modifier = Modifier.weight(1f))
            Text(value, style = valueStyle, color = colors.primary, modifier = Modifier.weight(1f))
        }
    }
}
