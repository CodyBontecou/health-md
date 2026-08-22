package com.healthmd.presentation.export

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForwardIos
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.data.storage.FileExportManager
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.schedule.ProfileCadenceEditorDialog
import com.healthmd.presentation.schedule.cadenceSummary
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

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
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportProfilesScreen(
    onBack: () -> Unit,
    viewModel: ExportProfilesViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Export Profiles") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    TextButton(onClick = { attemptProfileChange(viewModel::startCreation) }) {
                        Text("New")
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
            Text(
                text = "Every saved export configuration in one place. Activate a profile to edit " +
                    "it in the Export tab; schedules keep running with this screen closed.",
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )

            if (uiState.rows.isEmpty()) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = AppColors.bgSecondary),
                ) {
                    Column(
                        modifier = Modifier.padding(Spacing.lg),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = "No export profiles yet.",
                            style = MaterialTheme.typography.titleMedium,
                            color = AppColors.textPrimary,
                        )
                        Text(
                            text = "Use New to create one from your current export settings.",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.textSecondary,
                        )
                    }
                }
            }

            uiState.rows.forEach { row ->
                ProfileCard(
                    row = row,
                    onOpen = { viewModel.openDetail(row.profile.id) },
                )
            }
        }
    }

    uiState.detailProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        ProfileDetailDialog(
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
        AlertDialog(
            onDismissRequest = { viewModel.askDelete(null) },
            title = { Text("Delete \"${row.profile.name}\"?") },
            text = {
                Text("Its saved settings, destination bindings, and schedule are removed. The last remaining profile cannot be deleted.")
            },
            confirmButton = {
                TextButton(onClick = {
                    if (protection.enabled) {
                        viewModel.askDelete(null)
                        protection.onBlockedChange()
                    } else {
                        viewModel.delete(profileId)
                    }
                }) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.askDelete(null) }) { Text("Cancel") }
            },
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
            isCreation = true,
            initial = ExportProfilesViewModel.initialCreationDraft(
                rows = uiState.rows,
                currentSettings = uiState.currentSettings,
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
            isCreation = false,
            initial = ExportProfilesViewModel.initialEditDraft(
                profile = row.profile,
                currentSettings = uiState.currentSettings,
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
private fun ProfileCard(
    row: ExportProfileRow,
    onOpen: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(ExportProfilesTestTags.ROW)
            .clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = AppColors.bgSecondary),
    ) {
        Row(
            modifier = Modifier.padding(Spacing.lg),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Outlined.Layers,
                contentDescription = null,
                tint = if (row.isActive) AppColors.accent else AppColors.textMuted,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.md))
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = row.profile.name,
                        style = MaterialTheme.typography.titleMedium,
                        color = AppColors.textPrimary,
                    )
                    if (row.isActive) {
                        Spacer(modifier = Modifier.width(Spacing.sm))
                        ActiveBadge()
                    }
                }
                Text(
                    text = destinationLine(row.profile),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
                Text(
                    text = cadenceSummary(row.entry),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (row.entry?.isEnabled == true) {
                        AppColors.accent
                    } else {
                        AppColors.textSecondary
                    },
                )
                Text(
                    text = formatsLine(row),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
            Icon(
                Icons.AutoMirrored.Outlined.ArrowForwardIos,
                contentDescription = null,
                tint = AppColors.textMuted,
            )
        }
    }
}

@Composable
private fun ActiveBadge() {
    Surface(
        color = AppColors.accent.copy(alpha = 0.14f),
        shape = MaterialTheme.shapes.extraSmall,
    ) {
        Text(
            text = "Active",
            style = MaterialTheme.typography.labelSmall,
            color = AppColors.accent,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

private fun destinationLine(profile: ExportProfile): String = when (profile.target) {
    ExportTarget.DEVICE_FOLDER ->
        profile.folderDisplayName?.takeIf { it.isNotBlank() }
            ?: profile.folderUri?.takeIf { it.isNotBlank() }
            ?: "Device folder (selected in Export tab)"
    ExportTarget.API_ENDPOINT ->
        "API: ${profile.apiEndpointUrl ?: "not configured"}"
}

private fun formatsLine(row: ExportProfileRow): String {
    val snapshot = row.snapshot
    val formats = snapshot?.exportFormats
        ?.mapNotNull { name -> ExportFormatLabels[name] ?: name.takeIf { it.isNotBlank() } }
        ?.joinToString(" · ")
        .orEmpty()
    val metrics = "${snapshot?.enabledMetricCount ?: 0} metrics"
    return if (formats.isBlank()) metrics else "$formats · $metrics"
}

/** Stable display labels matching the platform-neutral format identities. */
private val ExportFormatLabels = mapOf(
    "MARKDOWN" to "Markdown",
    "OBSIDIAN_BASES" to "Obsidian Bases",
    "JSON" to "JSON",
    "CSV" to "CSV",
)

@Composable
private fun ProfileDetailDialog(
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

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(profile.name) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                FactRow("Status", if (row.isActive) "Active profile — edit it in the Export tab" else "Not active")
                if (row.overlappingProfileNames.isNotEmpty()) {
                    Text(
                        text = "Overlapping exports: writes the same files as " +
                            row.overlappingProfileNames.joinToString(", ") +
                            ". The later run overwrites the earlier one. Give each profile its " +
                            "own folder or filename template to keep them separate.",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.warning,
                    )
                }
                FactRow("Destination", destinationLine(profile))
                if (profile.target == ExportTarget.DEVICE_FOLDER) {
                    TextButton(onClick = {
                        // Rebinding the folder mutates profile configuration;
                        // the launch itself is gated so a pick is never
                        // silently discarded afterwards.
                        if (protection.enabled) {
                            onBlockedChange()
                        } else {
                            folderPickerLauncher.launch(null)
                        }
                    }) {
                        Text(
                            if (profile.folderUri.isNullOrBlank()) {
                                "Choose Folder…"
                            } else {
                                "Change Folder…"
                            }
                        )
                    }
                }
                FactRow("Schedule", cadenceSummary(row.entry))
                val snapshot = row.snapshot
                if (snapshot != null) {
                    FactRow(
                        "Formats",
                        snapshot.exportFormats
                            .mapNotNull { ExportFormatLabels[it] ?: it.takeIf { name -> name.isNotBlank() } }
                            .joinToString(" · ")
                            .ifBlank { "—" },
                    )
                    FactRow("Metrics", "${snapshot.enabledMetricCount} enabled")
                    FactRow(
                        "Lossless records",
                        if (snapshot.includeGranularData == true) "On" else "Off",
                    )
                    snapshot.filenameFormat?.let { FactRow("Filename format", it) }
                } else {
                    FactRow("Settings", "Saved snapshot could not be decoded")
                }

                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    text = "Use this ID to pin the profile in automation and API references " +
                        "(for example the CLI `--profile` flag).",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = profile.id,
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        color = AppColors.textPrimary,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(
                        onClick = {
                            clipboard.setText(AnnotatedString(profile.id))
                            idCopied = true
                        },
                    ) {
                        Icon(
                            Icons.Outlined.ContentCopy,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                        )
                        Spacer(modifier = Modifier.width(Spacing.xs))
                        Text(if (idCopied) "Copied" else "Copy")
                    }
                }
            }
        },
        confirmButton = {
            Row {
                TextButton(onClick = onEdit) { Text("Edit") }
                if (!row.isActive) {
                    TextButton(onClick = onActivate) { Text("Make Active & Edit") }
                }
                TextButton(onClick = onEditSchedule) { Text("Schedule…") }
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onRename) { Text("Rename") }
                TextButton(onClick = onDuplicate) { Text("Duplicate") }
                TextButton(onClick = onDelete, enabled = canDelete) { Text("Delete") }
            }
        },
    )
}

@Composable
private fun FactRow(title: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textMuted,
            modifier = Modifier.width(110.dp),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textPrimary,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun RenameProfileDialog(
    currentName: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var draft by remember { mutableStateOf(currentName) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rename Profile") },
        text = {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                singleLine = true,
                label = { Text("Profile name") },
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(draft) },
                enabled = draft.isNotBlank(),
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

/**
 * Entry card for the Export screen: shows the active profile and total count and
 * opens the management screen.
 */
@Composable
fun ExportProfilesEntryCard(
    onOpen: () -> Unit,
    viewModel: ExportProfilesViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    GeistCardClickable(
        onClick = onOpen,
        modifier = Modifier.testTag("export_profiles_entry"),
    ) {
        Icon(
            Icons.Outlined.Tune,
            contentDescription = null,
            tint = AppColors.accent,
            modifier = Modifier.size(24.dp),
        )
        Spacer(modifier = Modifier.width(Spacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Export Profiles",
                style = MaterialTheme.typography.titleMedium,
                color = AppColors.textPrimary,
            )
            Text(
                text = when {
                    uiState.rows.isEmpty() -> "Save multiple export configurations and run them on their own schedules."
                    else -> {
                        val active = uiState.activeProfileName ?: "—"
                        val count = uiState.rows.size
                        val scheduled = uiState.rows.count { it.entry?.isEnabled == true }
                        "Active: $active · $count profile(s) · $scheduled scheduled"
                    }
                },
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )
        }
        Icon(
            Icons.AutoMirrored.Outlined.ArrowForwardIos,
            contentDescription = null,
            tint = AppColors.textMuted,
        )
    }
}
