package com.healthmd.presentation.export

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForwardIos
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.WriteMode
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing

/**
 * Unified full-field export-profile editor (Compose parity with the iOS
 * `ExportProfileEditorSheet`). Serves both creation (no profile) and editing: name,
 * destination, output formats, templates, folder layout, Daily Notes, Individual Entries,
 * and metric selection all edit a DRAFT — nothing persists until Create/Save, and the live
 * overlap warning recomputes against the draft so overlap is visible while choices can
 * still change. Cancel discards.
 */
@Composable
fun ExportProfileEditorDialog(
    isCreation: Boolean,
    initial: ExportProfileEditorDraft,
    overlapPreview: (target: ExportTarget, folderUri: String?, settings: ExportSettings) -> List<String>,
    onConfirm: (ExportProfileEditorDraft) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var draft by remember { mutableStateOf(initial) }
    var showMetricSelection by remember { mutableStateOf(false) }

    fun updateSettings(transform: (ExportSettings) -> ExportSettings) {
        draft = draft.copy(settings = transform(draft.settings))
    }

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri ->
        uri?.let {
            FileExportManager(context).takePersistablePermission(it)
            draft = draft.copy(
                folderUri = it.toString(),
                folderDisplayName = FileExportManager(context).getFolderDisplayName(it.toString()),
            )
        }
    }

    val trimmedName = draft.name.trim()
    val endpointValid = draft.target != ExportTarget.API_ENDPOINT ||
        APIExportEndpoint.isConfigured(draft.apiEndpointUrl)
    val canSave = trimmedName.isNotEmpty() &&
        draft.settings.exportFormats.isNotEmpty() &&
        endpointValid

    val overlappingNames = overlapPreview(draft.target, draft.folderUri, draft.settings)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isCreation) "New Profile" else "Edit Profile") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                Text(
                    text = if (isCreation) {
                        "Starts from the current export settings."
                    } else {
                        "Scheduled exports pick up the new settings on their next run."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )

                EditorSectionLabel("Profile")
                EditorTextField(
                    value = draft.name,
                    onValueChange = { draft = draft.copy(name = it) },
                    label = "Name",
                    singleLine = true,
                )

                EditorSectionLabel("Destination")
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    EditorChoiceButton(
                        text = "Device Folder",
                        selected = draft.target == ExportTarget.DEVICE_FOLDER,
                        onClick = { draft = draft.copy(target = ExportTarget.DEVICE_FOLDER) },
                        modifier = Modifier.weight(1f),
                    )
                    EditorChoiceButton(
                        text = "API Endpoint",
                        selected = draft.target == ExportTarget.API_ENDPOINT,
                        onClick = { draft = draft.copy(target = ExportTarget.API_ENDPOINT) },
                        modifier = Modifier.weight(1f),
                    )
                }
                when (draft.target) {
                    ExportTarget.DEVICE_FOLDER -> {
                        FactRow(
                            title = "Folder",
                            value = draft.folderDisplayName
                                ?: draft.folderUri
                                ?: "Current folder (from Export tab)",
                        )
                        Row {
                            TextButton(onClick = { folderPickerLauncher.launch(null) }) {
                                Text(
                                    if (draft.folderUri == null) "Choose Folder…" else "Change Folder…",
                                )
                            }
                            if (draft.folderUri != null) {
                                Spacer(modifier = Modifier.width(Spacing.xs))
                                TextButton(onClick = {
                                    draft = draft.copy(folderUri = null, folderDisplayName = null)
                                }) {
                                    Text("Use Export-tab folder")
                                }
                            }
                        }
                    }
                    ExportTarget.API_ENDPOINT -> {
                        EditorTextField(
                            value = draft.apiEndpointUrl,
                            onValueChange = { draft = draft.copy(apiEndpointUrl = it) },
                            label = "Endpoint URL",
                            singleLine = true,
                        )
                        if (!endpointValid) {
                            Text(
                                text = "Enter a valid http(s) endpoint URL before saving.",
                                style = MaterialTheme.typography.bodySmall,
                                color = AppColors.error,
                            )
                        }
                    }
                }

                EditorSectionLabel("Output")
                ExportFormat.entries.toList().chunked(2).forEach { rowFormats ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                    ) {
                        rowFormats.forEach { format ->
                            EditorChoiceButton(
                                text = format.localizedDisplayName(),
                                selected = format in draft.settings.exportFormats,
                                onClick = {
                                    updateSettings {
                                        it.copy(
                                            exportFormats = if (format in it.exportFormats) {
                                                it.exportFormats - format
                                            } else {
                                                it.exportFormats + format
                                            },
                                        )
                                    }
                                },
                                modifier = Modifier.weight(1f),
                            )
                        }
                        if (rowFormats.size == 1) Spacer(modifier = Modifier.weight(1f))
                    }
                }
                WriteMode.entries.forEach { mode ->
                    EditorRadioRow(
                        title = mode.localizedDisplayName(),
                        description = mode.localizedDescription(),
                        selected = draft.settings.writeMode == mode,
                        onClick = { updateSettings { it.copy(writeMode = mode) } },
                    )
                }
                EditorTextField(
                    value = draft.settings.filenameFormat,
                    onValueChange = { value -> updateSettings { it.copy(filenameFormat = value) } },
                    label = "Filename template",
                    singleLine = true,
                )
                TemplateTokensHint()
                EditorTextField(
                    value = draft.settings.folderStructure,
                    onValueChange = { value -> updateSettings { it.copy(folderStructure = value) } },
                    label = "Custom folder template",
                    singleLine = true,
                )
                FolderOrganization.entries.forEach { org ->
                    EditorRadioRow(
                        title = folderOrganizationLabel(org),
                        description = folderOrganizationPreview(org),
                        selected = draft.settings.folderOrganization == org,
                        onClick = { updateSettings { it.copy(folderOrganization = org) } },
                    )
                }
                EditorTextField(
                    value = draft.settings.subfolder,
                    onValueChange = { value -> updateSettings { it.copy(subfolder = value) } },
                    label = "Health subfolder",
                    singleLine = true,
                )
                EditorToggleRow(
                    label = "Include metadata",
                    checked = draft.settings.includeMetadata,
                    onCheckedChange = { value -> updateSettings { it.copy(includeMetadata = value) } },
                )
                EditorToggleRow(
                    label = "Group by category",
                    checked = draft.settings.groupByCategory,
                    onCheckedChange = { value -> updateSettings { it.copy(groupByCategory = value) } },
                )
                EditorToggleRow(
                    label = "Detailed time-series",
                    checked = draft.settings.includeGranularData,
                    onCheckedChange = { value -> updateSettings { it.copy(includeGranularData = value) } },
                )

                EditorSectionLabel("Metrics")
                GeistCardClickable(
                    onClick = { showMetricSelection = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Health Metrics",
                            style = MaterialTheme.typography.bodyLarge,
                            color = AppColors.textPrimary,
                        )
                        Text(
                            text = "Choose which metrics this profile exports.",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.textMuted,
                        )
                    }
                    Text(
                        text = "${draft.settings.metricSelection.enabledCount} of ${HealthMetrics.totalCount}",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                    )
                    Spacer(modifier = Modifier.width(Spacing.xs))
                    Icon(
                        Icons.AutoMirrored.Outlined.ArrowForwardIos,
                        contentDescription = null,
                        tint = AppColors.textMuted,
                    )
                }

                EditorSectionLabel("Daily Notes")
                EditorToggleRow(
                    label = "Inject into daily notes",
                    checked = draft.settings.dailyNoteInjection.enabled,
                    onCheckedChange = { value ->
                        updateSettings {
                            it.copy(dailyNoteInjection = it.dailyNoteInjection.copy(enabled = value))
                        }
                    },
                )
                if (draft.settings.dailyNoteInjection.enabled) {
                    EditorTextField(
                        value = draft.settings.dailyNoteInjection.folderPath,
                        onValueChange = { value ->
                            updateSettings {
                                it.copy(
                                    dailyNoteInjection = it.dailyNoteInjection.copy(folderPath = value),
                                )
                            }
                        },
                        label = "Notes folder",
                        singleLine = true,
                    )
                    EditorTextField(
                        value = draft.settings.dailyNoteInjection.filenamePattern,
                        onValueChange = { value ->
                            updateSettings {
                                it.copy(
                                    dailyNoteInjection = it.dailyNoteInjection.copy(filenamePattern = value),
                                )
                            }
                        },
                        label = "Notes filename",
                        singleLine = true,
                    )
                    EditorToggleRow(
                        label = "Create if missing",
                        checked = draft.settings.dailyNoteInjection.createIfMissing,
                        onCheckedChange = { value ->
                            updateSettings {
                                it.copy(
                                    dailyNoteInjection = it.dailyNoteInjection.copy(createIfMissing = value),
                                )
                            }
                        },
                    )
                    EditorToggleRow(
                        label = "Markdown sections",
                        checked = draft.settings.dailyNoteInjection.injectMarkdownSections,
                        onCheckedChange = { value ->
                            updateSettings {
                                it.copy(
                                    dailyNoteInjection = it.dailyNoteInjection.copy(
                                        injectMarkdownSections = value,
                                    ),
                                )
                            }
                        },
                    )
                }

                EditorSectionLabel("Individual Entries")
                EditorToggleRow(
                    label = "Individual entries",
                    checked = draft.settings.individualTracking.globalEnabled,
                    onCheckedChange = { value ->
                        updateSettings {
                            it.copy(
                                individualTracking = it.individualTracking.copy(globalEnabled = value),
                            )
                        }
                    },
                )
                if (draft.settings.individualTracking.globalEnabled) {
                    EditorTextField(
                        value = draft.settings.individualTracking.entriesFolder,
                        onValueChange = { value ->
                            updateSettings {
                                it.copy(
                                    individualTracking = it.individualTracking.copy(entriesFolder = value),
                                )
                            }
                        },
                        label = "Entries folder",
                        singleLine = true,
                    )
                    EditorToggleRow(
                        label = "Category folders",
                        checked = draft.settings.individualTracking.organizeByCategory,
                        onCheckedChange = { value ->
                            updateSettings {
                                it.copy(
                                    individualTracking = it.individualTracking.copy(
                                        organizeByCategory = value,
                                    ),
                                )
                            }
                        },
                    )
                    EditorTextField(
                        value = draft.settings.individualTracking.filenameTemplate,
                        onValueChange = { value ->
                            updateSettings {
                                it.copy(
                                    individualTracking = it.individualTracking.copy(
                                        filenameTemplate = value,
                                    ),
                                )
                            }
                        },
                        label = "Entry filename template",
                        singleLine = true,
                    )
                }
                Text(
                    text = "Per-metric entry rules are edited from the Export tab while this profile is active.",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )

                if (overlappingNames.isNotEmpty()) {
                    Text(
                        text = "Overlaps ${overlappingNames.joinToString(", ")}: later runs " +
                            "overwrite earlier ones. Choose a different folder or filename " +
                            "template to keep them separate.",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.warning,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(draft.copy(name = trimmedName)) },
                enabled = canSave,
            ) { Text(if (isCreation) "Create" else "Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )

    if (showMetricSelection) {
        // Full-screen overlay reusing the shipped metric-selection surface against the draft.
        Dialog(
            onDismissRequest = { showMetricSelection = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Surface(modifier = Modifier.fillMaxSize(), color = AppColors.bgPrimary) {
                MetricSelectionScreen(
                    metricSelection = draft.settings.metricSelection,
                    onSelectionChanged = { selection ->
                        updateSettings { it.copy(metricSelection = selection) }
                    },
                    onBack = { showMetricSelection = false },
                )
            }
        }
    }
}

@Composable
private fun EditorSectionLabel(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        color = AppColors.textSecondary,
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
private fun EditorTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    singleLine: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = singleLine,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = AppColors.accent,
            unfocusedBorderColor = AppColors.borderDefault,
            focusedTextColor = AppColors.textPrimary,
            unfocusedTextColor = AppColors.textPrimary,
            cursorColor = AppColors.accent,
        ),
        shape = RoundedCornerShape(Radii.card),
    )
}

@Composable
private fun TemplateTokensHint() {
    Text(
        text = "{date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}",
        style = MaterialTheme.typography.bodySmall,
        color = AppColors.textMuted,
    )
}

@Composable
private fun EditorToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = AppColors.onAccent,
                checkedTrackColor = AppColors.accent,
                uncheckedThumbColor = AppColors.textMuted,
                uncheckedTrackColor = AppColors.bgSecondary,
                uncheckedBorderColor = AppColors.borderDefault,
            ),
        )
    }
}

@Composable
private fun EditorRadioRow(
    title: String,
    description: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(Radii.card)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) AppColors.accentSubtle else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(
            selected = selected,
            onClick = onClick,
            colors = RadioButtonDefaults.colors(
                selectedColor = AppColors.accent,
                unselectedColor = AppColors.textMuted,
            ),
        )
        Column(modifier = Modifier.padding(start = Spacing.xs)) {
            Text(title, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyMedium)
            Text(description, color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun EditorChoiceButton(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(Radii.badge)
    Row(
        modifier = modifier
            .heightIn(min = 44.dp)
            .clip(shape)
            .background(if (selected) AppColors.accentSubtle else Color.Transparent)
            .then(
                if (selected) {
                    Modifier.border(1.dp, AppColors.accentBorder, shape)
                } else {
                    Modifier
                },
            )
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.sm, vertical = Spacing.xs),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.xs))
        }
        Text(
            text = text,
            color = if (selected) AppColors.accent else AppColors.textSecondary,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

@Composable
private fun folderOrganizationLabel(org: FolderOrganization): String = when (org) {
    FolderOrganization.FLAT -> "Flat"
    FolderOrganization.BY_YEAR -> "By year"
    FolderOrganization.BY_MONTH -> "By month"
    FolderOrganization.BY_YEAR_MONTH -> "By year/month"
}

@Composable
private fun folderOrganizationPreview(org: FolderOrganization): String = when (org) {
    FolderOrganization.FLAT -> "All files side by side"
    FolderOrganization.BY_YEAR -> "{year}"
    FolderOrganization.BY_MONTH -> "{month}"
    FolderOrganization.BY_YEAR_MONTH -> "{year}/{month}"
}
