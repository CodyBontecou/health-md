package com.healthmd.presentation.export

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.DriveFileRenameOutline
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.schedule.ProfileCadenceEditorDialog
import com.healthmd.presentation.schedule.cadenceSummary
import com.healthmd.presentation.schedule.todayRefreshSummary
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

object ExportProfilesTestTags {
    const val ROW = "export_profile_row"
}

internal fun attemptExportProfileDetailChange(
    protectionEnabled: Boolean,
    closeDetail: () -> Unit,
    onBlockedChange: () -> Unit,
    action: () -> Unit,
) {
    if (protectionEnabled) {
        // Material dialogs use a separate window. Close it before publishing the graph-level
        // notice so the Settings action is visible and touchable above this screen.
        closeDetail()
        onBlockedChange()
    } else {
        action()
    }
}

/**
 * Dedicated export-profiles management screen (cross-platform parity with the iOS
 * `ExportProfilesView`): every profile at a glance with destination, schedule status,
 * formats, and metric count; a detail dialog with the stable profile id used by
 * automation references; and activate / rename / duplicate / delete management.
 *
 * Profile management stays inspectable while Prevent Accidental Changes is on —
 * opening the screen and a profile's detail is read-only — but every mutating
 * action routes through the shared configuration lock (iOS parity).
 */
@Composable
fun ExportProfilesScreen(
    onBack: () -> Unit,
    viewModel: ExportProfilesViewModel = hiltViewModel(),
    /** Opens this profile's detail once the screen appears. */
    initialDetailProfileId: String? = null,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(initialDetailProfileId) {
        if (initialDetailProfileId != null) viewModel.openDetail(initialDetailProfileId)
    }
    val clinicAccess: com.healthmd.presentation.clinic.ClinicAccessViewModel = hiltViewModel()
    val clinicStatus by clinicAccess.status.collectAsStateWithLifecycle()
    val independentAccess by clinicAccess.independentAccess.collectAsStateWithLifecycle()
    val managedClinicEndpoint = clinicStatus.endpoint.takeIf { clinicStatus.active && !independentAccess }
    val protection = LocalConfigurationProtection.current
    val attemptProfileChange: (() -> Unit) -> Unit = { action ->
        if (protection.enabled) protection.onBlockedChange() else action()
    }
    val attemptDetailProfileChange: (() -> Unit) -> Unit = { action ->
        attemptExportProfileDetailChange(
            protectionEnabled = protection.enabled,
            closeDetail = { viewModel.openDetail(null) },
            onBlockedChange = protection.onBlockedChange,
            action = action,
        )
    }

    val colors = LocalGeistColors.current
    SubScreen(
        title = stringResource(R.string.automations_profiles_title),
        onBack = onBack,
        actions = {
            TextButton(
                onClick = { attemptProfileChange(viewModel::startCreation) },
                modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
            ) {
                Text(stringResource(R.string.m3_profiles_new), style = GeistType.button14)
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space6),
        ) {
            Text(
                text = stringResource(R.string.m3_profiles_intro),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space4),
            )

            if (uiState.rows.isEmpty()) {
                ProfilesEmptyState(Modifier.padding(top = GeistSpacing.space6))
            } else {
                ProfileSection(stringResource(R.string.m3_profiles_section)) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        uiState.rows.forEachIndexed { index, row ->
                            ProfileRow(
                                row = row,
                                shape = groupRowShape(index, uiState.rows.size),
                                onOpen = { viewModel.openDetail(row.profile.id) },
                            )
                        }
                    }
                }
            }
        }
    }

    uiState.detailProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        ProfileDetailDialog(
            clinicSponsoredOnly = managedClinicEndpoint != null,
            row = row,
            canDelete = uiState.rows.size > 1,
            onActivate = { attemptDetailProfileChange { viewModel.activate(row.profile.id) } },
            onEdit = { attemptDetailProfileChange { viewModel.openEditor(row.profile.id) } },
            onRename = { attemptDetailProfileChange { viewModel.startRename(row.profile.id) } },
            onDuplicate = { attemptDetailProfileChange { viewModel.duplicate(row.profile.id) } },
            onEditSchedule = { attemptDetailProfileChange { viewModel.openScheduleEditor(row.profile.id) } },
            onDelete = { attemptDetailProfileChange { viewModel.askDelete(row.profile.id) } },
            onFolderSelected = { uri, name ->
                attemptDetailProfileChange { viewModel.bindProfileFolder(row.profile.id, uri, name) }
            },
            onBlockedChange = { attemptDetailProfileChange {} },
            onDismiss = { viewModel.openDetail(null) },
        )
    }

    uiState.renamingProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        RenameProfileDialog(
            currentName = row.profile.name,
            onSave = { name ->
                // Only reachable when the lock was enabled while the dialog
                // was already open: dismiss first so the shared toast is not
                // hidden behind this dialog window.
                if (protection.enabled) {
                    viewModel.startRename(null)
                    protection.onBlockedChange()
                } else {
                    viewModel.rename(profileId, name)
                }
            },
            onDismiss = { viewModel.startRename(null) },
        )
    }

    uiState.pendingDeleteProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        DeleteProfileDialog(
            profileName = row.profile.name,
            onConfirm = {
                if (protection.enabled) {
                    viewModel.askDelete(null)
                    protection.onBlockedChange()
                } else {
                    viewModel.delete(profileId)
                }
            },
            onDismiss = { viewModel.askDelete(null) },
        )
    }

    uiState.editingScheduleProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        ProfileCadenceEditorDialog(
            profileId = row.profile.id,
            profileName = row.profile.name,
            entry = row.entry,
            onSave = { entry ->
                if (protection.enabled) {
                    viewModel.openScheduleEditor(null)
                    protection.onBlockedChange()
                } else {
                    viewModel.saveEntry(entry)
                }
            },
            onDismiss = { viewModel.openScheduleEditor(null) },
        )
    }

    if (uiState.creatingProfile) {
        ExportProfileEditorDialog(
            managedClinicEndpoint = managedClinicEndpoint,
            isCreation = true,
            initial = ExportProfilesViewModel.initialCreationDraft(
                rows = uiState.rows,
                currentSettings = uiState.currentSettings,
                connectedGoogleDriveDestinationId = uiState.connectedGoogleDriveDestinationId,
            ),
            overlapPreview = { target, folderUri, settings ->
                viewModel.draftOverlapPreview(
                    editingProfileId = null,
                    target = target,
                    folderUri = folderUri,
                    settings = settings,
                )
            },
            onConfirm = { draft ->
                // Drafts stay inspectable, but persisting is a mutation, so an
                // editor already open when the lock was enabled still saves
                // through the shared gate.
                if (protection.enabled) {
                    viewModel.dismissCreation()
                    protection.onBlockedChange()
                } else {
                    viewModel.createProfile(draft)
                }
            },
            onDismiss = viewModel::dismissCreation,
        )
    }

    uiState.editingProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        ExportProfileEditorDialog(
            managedClinicEndpoint = managedClinicEndpoint,
            isCreation = false,
            initial = ExportProfilesViewModel.initialEditDraft(
                profile = row.profile,
                currentSettings = uiState.currentSettings,
                connectedGoogleDriveDestinationId = uiState.connectedGoogleDriveDestinationId,
            ),
            overlapPreview = { target, folderUri, settings ->
                viewModel.draftOverlapPreview(
                    editingProfileId = profileId,
                    target = target,
                    folderUri = folderUri,
                    settings = settings,
                )
            },
            onConfirm = { draft ->
                if (protection.enabled) {
                    viewModel.openEditor(null)
                    protection.onBlockedChange()
                } else {
                    viewModel.updateProfile(profileId, draft)
                }
            },
            onDismiss = { viewModel.openEditor(null) },
        )
    }
}

@Composable
private fun ProfilesEmptyState(modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.background200)
            .padding(GeistSpacing.space6),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Icon(Icons.Outlined.Layers, contentDescription = null, tint = colors.secondary, modifier = Modifier.size(32.dp))
        Text(
            text = stringResource(R.string.a11y_profiles_empty),
            style = GeistType.heading16,
            color = colors.primary,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.m3_profiles_empty_body),
            style = GeistType.copy14,
            color = colors.secondary,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * One profile as a list-group row: the name and summaries take the full text width (the icon
 * gives its space up at the reading-first threshold), and the whole row opens the detail.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProfileRow(
    row: ExportProfileRow,
    shape: Shape,
    onOpen: () -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(ExportProfilesTestTags.ROW)
            .clip(shape)
            .background(colors.background200)
            .clickable(role = Role.Button, onClick = onOpen)
            .heightIn(min = 72.dp)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space3, top = GeistSpacing.space3, bottom = GeistSpacing.space3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BoxWithConstraints(Modifier.weight(1f)) {
            val reading = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
            ) {
                if (!reading) {
                    Box(
                        Modifier
                            .size(GeistSizes.control)
                            .background(if (row.isActive) colors.brandPrimary else colors.gray.c300, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Outlined.Layers,
                            contentDescription = null,
                            tint = if (row.isActive) colors.brandOnPrimary else colors.secondary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
                    ) {
                        Text(
                            text = row.profile.name,
                            style = GeistType.label16,
                            color = colors.primary,
                            modifier = Modifier.align(Alignment.CenterVertically),
                        )
                        if (row.isActive) ActivePill(Modifier.align(Alignment.CenterVertically))
                    }
                    Text(
                        text = destinationLine(row.profile),
                        style = GeistType.copy14,
                        color = colors.secondary,
                    )
                    Text(
                        text = cadenceSummary(row.entry, todayRefreshSummary(row.entry)),
                        style = GeistType.copy14,
                        color = if (row.entry?.isEnabled == true) colors.brandPrimary else colors.secondary,
                    )
                    Text(
                        text = formatsLine(row),
                        style = GeistType.label13,
                        color = colors.secondary,
                    )
                }
            }
        }
        Icon(
            Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = colors.secondary,
            modifier = Modifier.padding(start = GeistSpacing.space2),
        )
    }
}

/** The active profile's tonal pill on the secondary container. */
@Composable
private fun ActivePill(modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    Text(
        text = stringResource(R.string.m3_profiles_active),
        style = GeistType.label12,
        color = colors.onSecondaryContainer,
        modifier = modifier
            .clip(RoundedCornerShape(GeistRadii.full))
            .background(colors.secondaryContainer)
            .padding(horizontal = GeistSpacing.space2, vertical = 2.dp),
    )
}

@Composable
private fun destinationLine(profile: ExportProfile): String = when (profile.target) {
    ExportTarget.DEVICE_FOLDER ->
        profile.folderDisplayName?.takeIf { it.isNotBlank() }
            ?: profile.folderUri?.takeIf { it.isNotBlank() }
            ?: stringResource(R.string.m3_profiles_destination_device_default)
    ExportTarget.API_ENDPOINT -> stringResource(
        R.string.m3_profiles_destination_api,
        profile.apiEndpointUrl ?: stringResource(R.string.m3_profiles_not_configured),
    )
    ExportTarget.AGENT_DATA_GATEWAY -> stringResource(
        R.string.m3_profiles_destination_gateway,
        profile.agentDataGatewayUrl ?: stringResource(R.string.m3_profiles_not_configured),
    )
    ExportTarget.GOOGLE_DRIVE -> stringResource(R.string.google_drive_title)
}

@Composable
private fun formatsLine(row: ExportProfileRow): String {
    val snapshot = row.snapshot
    val formats = snapshot?.exportFormats
        ?.mapNotNull { name -> ExportFormatLabels[name] ?: name.takeIf { it.isNotBlank() } }
        ?.joinToString(" · ")
        .orEmpty()
    val count = snapshot?.enabledMetricCount ?: 0
    val metrics = pluralStringResource(R.plurals.m3_profiles_metrics_count, count, count)
    return if (formats.isBlank()) metrics else "$formats · $metrics"
}

/** Stable display labels matching the platform-neutral format identities. */
private val ExportFormatLabels = mapOf(
    "MARKDOWN" to "Markdown",
    "OBSIDIAN_BASES" to "Obsidian Bases",
    "JSON" to "JSON",
    "CSV" to "CSV",
)

/**
 * Full-screen profile detail: grouped facts, the stable automation ID, and distinct
 * management rows, with Edit as the one filled action in the pinned bar.
 */
@Composable
private fun ProfileDetailDialog(
    clinicSponsoredOnly: Boolean,
    row: ExportProfileRow,
    canDelete: Boolean,
    onActivate: () -> Unit,
    onEdit: () -> Unit,
    onRename: () -> Unit,
    onDuplicate: () -> Unit,
    onEditSchedule: () -> Unit,
    onDelete: () -> Unit,
    onFolderSelected: (Uri, String?) -> Unit,
    onBlockedChange: () -> Unit,
    onDismiss: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val colors = LocalGeistColors.current
    val profile = row.profile
    var idCopied by remember { mutableStateOf(false) }
    val protection = LocalConfigurationProtection.current

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri ->
        uri?.let {
            FileExportManager(context).takePersistablePermission(it)
            val name = FileExportManager(context).getFolderDisplayName(it.toString())
            onFolderSelected(it, name)
        }
    }

    val on = stringResource(R.string.m3_profiles_on)
    val off = stringResource(R.string.m3_profiles_off)
    val facts = buildList<@Composable (Shape) -> Unit> {
        add { shape ->
            ProfileFactRow(
                shape,
                stringResource(R.string.m3_profiles_status),
                stringResource(if (row.isActive) R.string.m3_profiles_status_active else R.string.m3_profiles_status_inactive),
            )
        }
        add { shape ->
            ProfileFactRow(
                shape,
                stringResource(R.string.automation_detail_destination),
                destinationLine(profile),
                below = if (profile.target == ExportTarget.DEVICE_FOLDER && !clinicSponsoredOnly) {
                    {
                        TextButton(
                            onClick = {
                                // Rebinding the folder mutates profile configuration;
                                // the launch itself is gated so a pick is never
                                // silently discarded afterwards.
                                if (protection.enabled) {
                                    onBlockedChange()
                                } else {
                                    folderPickerLauncher.launch(null)
                                }
                            },
                            modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                            contentPadding = PaddingValues(horizontal = 0.dp),
                        ) {
                            Text(
                                stringResource(
                                    if (profile.folderUri.isNullOrBlank()) {
                                        R.string.folder_destination_choose
                                    } else {
                                        R.string.folder_destination_change
                                    },
                                ),
                                style = GeistType.button14,
                            )
                        }
                    }
                } else {
                    null
                },
            )
        }
        add { shape ->
            ProfileFactRow(
                shape,
                stringResource(R.string.automation_detail_schedule),
                cadenceSummary(row.entry, todayRefreshSummary(row.entry)),
            )
        }
        val snapshot = row.snapshot
        if (snapshot != null) {
            add { shape ->
                ProfileFactRow(
                    shape,
                    stringResource(R.string.automation_detail_formats),
                    snapshot.exportFormats
                        .mapNotNull { ExportFormatLabels[it] ?: it.takeIf { name -> name.isNotBlank() } }
                        .joinToString(" · ")
                        .ifBlank { "—" },
                )
            }
            add { shape ->
                ProfileFactRow(
                    shape,
                    stringResource(R.string.automation_detail_metrics),
                    stringResource(R.string.m3_profiles_metrics_enabled, snapshot.enabledMetricCount),
                )
            }
            add { shape ->
                ProfileFactRow(
                    shape,
                    stringResource(R.string.m3_profiles_detailed),
                    if (snapshot.includeGranularData == true) on else off,
                )
            }
            if (snapshot.detailOverrideCount > 0) {
                add { shape ->
                    ProfileFactRow(
                        shape,
                        stringResource(R.string.m3_profiles_detail_overrides),
                        pluralStringResource(
                            R.plurals.m3_profiles_detail_overrides_count,
                            snapshot.detailOverrideCount,
                            snapshot.detailOverrideCount,
                        ),
                    )
                }
            }
            snapshot.filenameFormat?.let { format ->
                add { shape ->
                    ProfileFactRow(shape, stringResource(R.string.m3_profiles_filename_format), format, mono = true)
                }
            }
        } else {
            add { shape ->
                ProfileFactRow(
                    shape,
                    stringResource(R.string.m3_profiles_settings),
                    stringResource(R.string.m3_profiles_snapshot_undecodable),
                )
            }
        }
    }

    ProfileFullScreenDialog(
        title = profile.name,
        onDismiss = onDismiss,
        actions = {
            AdaptiveActionPair(
                primaryAction = { modifier ->
                    PrimaryButton(text = stringResource(R.string.automations_edit), onClick = onEdit, modifier = modifier)
                },
                secondaryAction = { modifier ->
                    SecondaryButton(
                        text = stringResource(R.string.automation_detail_edit_schedule),
                        onClick = onEditSchedule,
                        modifier = modifier,
                    )
                },
            )
        },
    ) {
        if (row.overlappingProfileNames.isNotEmpty()) {
            ProfileNote(
                tone = ProfileNoteTone.WARNING,
                title = stringResource(R.string.m3_profiles_overlap_title),
                message = stringResource(
                    R.string.m3_profiles_overlap_body,
                    row.overlappingProfileNames.joinToString(", "),
                ),
                modifier = Modifier.padding(top = GeistSpacing.space2),
            )
        }

        ProfileSection(stringResource(R.string.automation_detail_details)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                facts.forEachIndexed { index, fact -> fact(groupRowShape(index, facts.size)) }
            }
        }

        ProfileSection(stringResource(R.string.automation_detail_profile_id)) {
            ProfileFactRow(
                shape = RoundedCornerShape(GeistRadii.listGroup),
                title = stringResource(R.string.automation_detail_cli),
                value = profile.id,
                mono = true,
                below = {
                    TextButton(
                        onClick = {
                            clipboard.setText(AnnotatedString(profile.id))
                            idCopied = true
                        },
                        modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                        contentPadding = PaddingValues(horizontal = 0.dp),
                    ) {
                        Icon(Icons.Outlined.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(GeistSpacing.space2))
                        Text(
                            stringResource(if (idCopied) R.string.automation_detail_copied else R.string.automation_detail_copy),
                            style = GeistType.button14,
                        )
                    }
                },
            )
            Text(
                text = stringResource(R.string.m3_profiles_id_hint),
                style = GeistType.copy13,
                color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space4),
            )
        }

        ProfileSection(stringResource(R.string.m3_profiles_manage)) {
            val actions = buildList<@Composable (Shape) -> Unit> {
                if (!row.isActive) {
                    add { shape ->
                        ProfileActionRow(shape, stringResource(R.string.m3_profiles_make_active_edit), Icons.Outlined.CheckCircle, onActivate)
                    }
                }
                add { shape -> ProfileActionRow(shape, stringResource(R.string.m3_profiles_rename), Icons.Outlined.DriveFileRenameOutline, onRename) }
                add { shape -> ProfileActionRow(shape, stringResource(R.string.m3_profiles_duplicate), Icons.Outlined.ContentCopy, onDuplicate) }
                add { shape ->
                    ProfileActionRow(
                        shape,
                        stringResource(R.string.a11y_profiles_delete),
                        Icons.Outlined.Delete,
                        onDelete,
                        enabled = canDelete,
                        destructive = true,
                    )
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                actions.forEachIndexed { index, action -> action(groupRowShape(index, actions.size)) }
            }
        }
    }
}

/** One management action as a grouped row: icon and label, the whole row is the target. */
@Composable
private fun ProfileActionRow(
    shape: Shape,
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
    enabled: Boolean = true,
    destructive: Boolean = false,
) {
    val colors = LocalGeistColors.current
    val tint = when {
        !enabled -> colors.disabled
        destructive -> colors.error
        else -> colors.primary
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Icon(icon, contentDescription = null, tint = if (destructive || !enabled) tint else colors.secondary, modifier = Modifier.size(22.dp))
        Text(label, style = GeistType.label16, color = tint, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun RenameProfileDialog(
    currentName: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalGeistColors.current
    var draft by remember { mutableStateOf(currentName) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        icon = { Icon(Icons.Outlined.DriveFileRenameOutline, contentDescription = null, tint = colors.brandPrimary) },
        title = {
            Text(stringResource(R.string.m3_profiles_rename_title), style = GeistType.heading24, color = colors.primary)
        },
        text = {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                singleLine = true,
                label = { Text(stringResource(R.string.m3_profiles_name_label)) },
                textStyle = GeistType.copy16,
                shape = RoundedCornerShape(GeistRadii.small),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = colors.brandPrimary,
                    unfocusedBorderColor = colors.gray.c500,
                    focusedLabelColor = colors.brandPrimary,
                    cursorColor = colors.brandPrimary,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            Button(
                onClick = { onSave(draft) },
                enabled = draft.isNotBlank(),
                shape = RoundedCornerShape(GeistRadii.full),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.brandPrimary,
                    contentColor = colors.brandOnPrimary,
                ),
            ) { Text(stringResource(R.string.a11y_profiles_save), style = GeistType.button14) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), style = GeistType.button14) }
        },
    )
}

@Composable
private fun DeleteProfileDialog(
    profileName: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalGeistColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        icon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = colors.error) },
        title = {
            Text(
                stringResource(R.string.a11y_profiles_delete_title, profileName),
                style = GeistType.heading24,
                color = colors.primary,
                textAlign = TextAlign.Center,
            )
        },
        text = {
            Text(stringResource(R.string.m3_profiles_delete_body), style = GeistType.copy14, color = colors.secondary)
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                shape = RoundedCornerShape(GeistRadii.full),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.error,
                    contentColor = colors.background100,
                ),
            ) { Text(stringResource(R.string.a11y_profiles_delete), style = GeistType.button14) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), style = GeistType.button14) }
        },
    )
}
