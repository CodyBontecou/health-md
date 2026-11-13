package com.healthmd.presentation.export

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.R
import com.healthmd.presentation.settings.AutomationOutputPathValidation
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.WriteMode
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.EdgeToEdgeDialogWindow
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.dialogNavigationBarsPadding
import com.healthmd.presentation.i18n.localizedDescription
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.settings.ExportDetailOverridesSection
import com.healthmd.presentation.settings.SettingsRow
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistBreakpoints
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * Unified full-field export-profile editor (Compose parity with the iOS
 * `ExportProfileEditorSheet`). Serves both creation (no profile) and editing: name,
 * destination, output formats, templates, folder layout, Daily Notes, Individual Entries,
 * and metric selection all edit a DRAFT — nothing persists until Create/Save, and the live
 * overlap warning recomputes against the draft so overlap is visible while choices can
 * still change. Cancel discards.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ExportProfileEditorDialog(
    isCreation: Boolean,
    initial: ExportProfileEditorDraft,
    overlapPreview: (target: ExportTarget, folderUri: String?, settings: ExportSettings) -> List<String>,
    onConfirm: (ExportProfileEditorDraft) -> Unit,
    onDismiss: () -> Unit,
    managedClinicEndpoint: String? = null,
    /** Replaces the default title, e.g. "New automation" when created from Automations. */
    title: String? = null,
) {
    val context = LocalContext.current
    val colors = LocalGeistColors.current
    var draft by rememberSaveable(stateSaver = ExportProfileEditorDraftSaver) { mutableStateOf(initial) }
    var showMetricSelection by rememberSaveable { mutableStateOf(false) }

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

    val rawSnapshot = draft.settings.exportMode == ExportMode.RAW_SNAPSHOT
    val trimmedName = draft.name.trim()
    val endpointValid = draft.target != ExportTarget.API_ENDPOINT ||
        APIExportEndpoint.isConfigured(draft.apiEndpointUrl)
    val driveValid = draft.target != ExportTarget.GOOGLE_DRIVE || !draft.destinationId.isNullOrBlank()
    val gatewayValid = draft.target != ExportTarget.AGENT_DATA_GATEWAY ||
        AgentDataGatewayEndpoint.isConfigured(draft.agentDataGatewayUrl)
    val canSave = trimmedName.isNotEmpty() &&
        draft.hasOutputFormat &&
        endpointValid &&
        gatewayValid && driveValid &&
        (rawSnapshot || AutomationOutputPathValidation.isValidDailyNotes(draft.settings.dailyNoteInjection))

    val overlappingNames = overlapPreview(draft.target, draft.folderUri, draft.settings)

    ProfileFullScreenDialog(
        title = title ?: stringResource(if (isCreation) R.string.m3_profiles_editor_new_title else R.string.m3_profiles_editor_edit_title),
        onDismiss = onDismiss,
        actions = {
            AdaptiveActionPair(
                primaryAction = { modifier ->
                    PrimaryButton(
                        text = stringResource(if (isCreation) R.string.m3_profiles_editor_create else R.string.a11y_profiles_save),
                        onClick = { onConfirm(draft.copy(name = trimmedName)) },
                        enabled = canSave,
                        modifier = modifier,
                    )
                },
                secondaryAction = { modifier ->
                    SecondaryButton(
                        text = stringResource(R.string.cancel),
                        onClick = onDismiss,
                        modifier = modifier,
                    )
                },
            )
        },
    ) {
        Text(
            text = stringResource(
                if (isCreation) R.string.m3_profiles_editor_new_body else R.string.m3_profiles_editor_edit_body,
            ),
            style = GeistType.copy14,
            color = colors.secondary,
            modifier = Modifier.padding(top = GeistSpacing.space2),
        )

        ProfileSection(stringResource(R.string.export_profile_label)) {
            EditorTextField(
                value = draft.name,
                onValueChange = { draft = draft.copy(name = it) },
                label = stringResource(R.string.m3_profiles_editor_name),
            )
        }

        ProfileSection(stringResource(R.string.automation_detail_destination)) {
            if (managedClinicEndpoint != null) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    ProfileFactRow(groupRowShape(0, 2), stringResource(R.string.m3_profiles_editor_target), targetLabel(draft.target))
                    ProfileFactRow(groupRowShape(1, 2), stringResource(R.string.m3_profiles_editor_clinic_destination), managedClinicEndpoint, mono = true)
                }
                ProfileNote(
                    tone = ProfileNoteTone.INFO,
                    message = stringResource(R.string.m3_profiles_editor_clinic_body),
                )
            } else {
                TargetChoice(
                    selected = draft.target,
                    onSelect = { draft = draft.copy(target = it) },
                )
                when (draft.target) {
                    ExportTarget.DEVICE_FOLDER -> {
                        ProfileFactRow(
                            shape = RoundedCornerShape(GeistRadii.listGroup),
                            title = stringResource(R.string.m3_profiles_editor_folder),
                            value = draft.folderDisplayName
                                ?: draft.folderUri
                                ?: stringResource(R.string.m3_profiles_editor_folder_current),
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                        ) {
                            SecondaryButton(
                                text = stringResource(
                                    if (draft.folderUri == null) R.string.folder_destination_choose else R.string.folder_destination_change,
                                ),
                                onClick = { folderPickerLauncher.launch(null) },
                            )
                            if (draft.folderUri != null) {
                                TextButton(
                                    onClick = { draft = draft.copy(folderUri = null, folderDisplayName = null) },
                                    modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                                ) {
                                    Text(stringResource(R.string.m3_profiles_editor_folder_reset), style = GeistType.button14)
                                }
                            }
                        }
                    }
                    ExportTarget.API_ENDPOINT -> {
                        EditorTextField(
                            value = draft.apiEndpointUrl,
                            onValueChange = { draft = draft.copy(apiEndpointUrl = it) },
                            label = stringResource(R.string.api_export_endpoint_url_label),
                            error = stringResource(R.string.m3_profiles_editor_endpoint_invalid).takeIf { !endpointValid },
                        )
                    }
                    ExportTarget.GOOGLE_DRIVE -> Text(
                        text = if (driveValid) {
                            "Uses the connected local Google Drive destination."
                        } else {
                            "Connect Google Drive in Settings before saving this profile."
                        },
                        style = GeistType.copy14,
                        color = if (driveValid) colors.secondary else colors.error,
                    )
                    ExportTarget.AGENT_DATA_GATEWAY -> {
                        EditorTextField(
                            value = draft.agentDataGatewayUrl,
                            onValueChange = { draft = draft.copy(agentDataGatewayUrl = it) },
                            label = stringResource(R.string.agent_data_gateway_url_label),
                            error = stringResource(R.string.m3_profiles_editor_gateway_invalid).takeIf { !gatewayValid },
                        )
                    }
                }
            }
        }

        if (rawSnapshot) {
            ProfileSection(stringResource(R.string.m3_profiles_editor_output)) {
                RawSnapshotConfiguration(
                    settings = draft.settings,
                    onFormatChanged = { value -> updateSettings { it.copy(rawSnapshot = it.rawSnapshot.copy(format = value)) } },
                    onScopeChanged = { value -> updateSettings { it.copy(rawSnapshot = it.rawSnapshot.copy(scope = value)) } },
                    onIncludeExerciseRoutesChanged = { value -> updateSettings { it.copy(rawSnapshot = it.rawSnapshot.copy(includeExerciseRoutes = value)) } },
                )
                EditorTextField(
                    value = draft.settings.subfolder,
                    onValueChange = { value -> updateSettings { it.copy(subfolder = value) } },
                    label = stringResource(R.string.health_subfolder_label),
                )
            }
        } else {
            ProfileSection(stringResource(R.string.m3_profiles_editor_output)) {
                Text(stringResource(R.string.automation_detail_formats), style = GeistType.label14, color = colors.secondary)
                FormatChoice(
                    selected = draft.settings.exportFormats,
                    onToggle = { format ->
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
                )
                Text(stringResource(R.string.section_write_mode), style = GeistType.label14, color = colors.secondary)
                val modes = WriteMode.entries
                ChoiceRows {
                    modes.forEachIndexed { index, mode ->
                        EditorRadioRow(
                            shape = groupRowShape(index, modes.size),
                            title = mode.localizedDisplayName(),
                            description = mode.localizedDescription(),
                            selected = draft.settings.writeMode == mode,
                            onClick = { updateSettings { it.copy(writeMode = mode) } },
                        )
                    }
                }
                EditorTextField(
                    value = draft.settings.filenameFormat,
                    onValueChange = { value -> updateSettings { it.copy(filenameFormat = value) } },
                    label = stringResource(R.string.m3_profiles_editor_filename_template),
                    supporting = stringResource(R.string.filename_template_tokens),
                )
                EditorTextField(
                    value = draft.settings.folderStructure,
                    onValueChange = { value -> updateSettings { it.copy(folderStructure = value) } },
                    label = stringResource(R.string.folder_structure_template_label),
                )
                Text(stringResource(R.string.folder_organization_label), style = GeistType.label14, color = colors.secondary)
                val organizations = FolderOrganization.entries
                ChoiceRows {
                    organizations.forEachIndexed { index, org ->
                        EditorRadioRow(
                            shape = groupRowShape(index, organizations.size),
                            title = folderOrganizationLabel(org),
                            description = folderOrganizationPreview(org),
                            selected = draft.settings.folderOrganization == org,
                            onClick = { updateSettings { it.copy(folderOrganization = org) } },
                        )
                    }
                }
                EditorTextField(
                    value = draft.settings.subfolder,
                    onValueChange = { value -> updateSettings { it.copy(subfolder = value) } },
                    label = stringResource(R.string.health_subfolder_label),
                )
                ToggleRows(
                    listOf(
                        ToggleItem(stringResource(R.string.m3_profiles_editor_include_metadata), draft.settings.includeMetadata) { value ->
                            updateSettings { it.copy(includeMetadata = value) }
                        },
                        ToggleItem(stringResource(R.string.toggle_group_by_category), draft.settings.groupByCategory) { value ->
                            updateSettings { it.copy(groupByCategory = value) }
                        },
                        ToggleItem(stringResource(R.string.m3_profiles_detailed), draft.settings.includeGranularData) { value ->
                            updateSettings { it.copy(includeGranularData = value) }
                        },
                    ),
                )
                ExportDetailOverridesSection(
                    settings = draft.settings,
                    onDetailChoiceChanged = { group, choice -> updateSettings { it.withDetailChoice(group, choice) } },
                )
            }
        }

        if (!rawSnapshot || draft.settings.rawSnapshot.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) {
            ProfileSection(stringResource(R.string.automation_detail_metrics)) {
                SettingsRow(
                    shape = RoundedCornerShape(GeistRadii.listGroup),
                    title = stringResource(R.string.metric_selection_title),
                    icon = Icons.Outlined.Checklist,
                    subtitle = stringResource(R.string.m3_profiles_editor_metrics_body),
                    trailing = stringResource(
                        R.string.m3_profiles_editor_metrics_count,
                        draft.settings.metricSelection.enabledCount,
                        HealthMetrics.totalCount,
                    ),
                    onClick = { showMetricSelection = true },
                )
            }
        }

        if (!rawSnapshot) {
            ProfileSection(stringResource(R.string.m3_profiles_editor_daily_notes)) {
                val daily = draft.settings.dailyNoteInjection
                ToggleRows(
                    listOf(
                        ToggleItem(stringResource(R.string.m3_profiles_editor_daily_inject), daily.enabled) { value ->
                            updateSettings { it.copy(dailyNoteInjection = it.dailyNoteInjection.copy(enabled = value)) }
                        },
                    ),
                )
                if (daily.enabled) {
                    EditorTextField(
                        value = daily.folderPath,
                        error = if (!AutomationOutputPathValidation.isSafeDailyNoteFolder(daily.folderPath)) stringResource(R.string.automation_output_path_invalid) else null,
                        onValueChange = { value ->
                            updateSettings { it.copy(dailyNoteInjection = it.dailyNoteInjection.copy(folderPath = value)) }
                        },
                        label = stringResource(R.string.m3_profiles_editor_notes_folder),
                    )
                    EditorTextField(
                        value = daily.filenamePattern,
                        error = if (!AutomationOutputPathValidation.isSafeDailyNoteFilename(daily.filenamePattern)) stringResource(R.string.automation_output_path_invalid) else null,
                        onValueChange = { value ->
                            updateSettings { it.copy(dailyNoteInjection = it.dailyNoteInjection.copy(filenamePattern = value)) }
                        },
                        label = stringResource(R.string.m3_profiles_editor_notes_filename),
                    )
                    ToggleRows(
                        listOf(
                            ToggleItem(stringResource(R.string.m3_profiles_editor_create_missing), daily.createIfMissing) { value ->
                                updateSettings {
                                    it.copy(dailyNoteInjection = it.dailyNoteInjection.copy(createIfMissing = value))
                                }
                            },
                            ToggleItem(stringResource(R.string.m3_profiles_editor_markdown_sections), daily.injectMarkdownSections) { value ->
                                updateSettings {
                                    it.copy(dailyNoteInjection = it.dailyNoteInjection.copy(injectMarkdownSections = value))
                                }
                            },
                        ),
                    )
                }
            }

            ProfileSection(stringResource(R.string.m3_profiles_editor_individual)) {
                val tracking = draft.settings.individualTracking
                ToggleRows(
                    listOf(
                        ToggleItem(stringResource(R.string.m3_profiles_editor_individual_toggle), tracking.globalEnabled) { value ->
                            updateSettings { it.copy(individualTracking = it.individualTracking.copy(globalEnabled = value)) }
                        },
                    ),
                )
                if (tracking.globalEnabled) {
                    EditorTextField(
                        value = tracking.entriesFolder,
                        onValueChange = { value ->
                            updateSettings { it.copy(individualTracking = it.individualTracking.copy(entriesFolder = value)) }
                        },
                        label = stringResource(R.string.m3_profiles_editor_entries_folder),
                    )
                    ToggleRows(
                        listOf(
                            ToggleItem(stringResource(R.string.m3_profiles_editor_category_folders), tracking.organizeByCategory) { value ->
                                updateSettings {
                                    it.copy(individualTracking = it.individualTracking.copy(organizeByCategory = value))
                                }
                            },
                        ),
                    )
                    EditorTextField(
                        value = tracking.filenameTemplate,
                        onValueChange = { value ->
                            updateSettings {
                                it.copy(individualTracking = it.individualTracking.copy(filenameTemplate = value))
                            }
                        },
                        label = stringResource(R.string.m3_profiles_editor_entry_filename),
                        supporting = stringResource(R.string.individual_tracking_filename_tokens),
                    )
                }
                Text(
                    text = stringResource(R.string.m3_profiles_editor_entry_rules_note),
                    style = GeistType.copy13,
                    color = colors.secondary,
                )
            }
        }

        if (overlappingNames.isNotEmpty()) {
            ProfileNote(
                tone = ProfileNoteTone.WARNING,
                message = stringResource(R.string.m3_profiles_editor_overlap, overlappingNames.joinToString(", ")),
                modifier = Modifier.padding(top = GeistSpacing.space6),
            )
        }
    }

    if (showMetricSelection) {
        // Full-screen overlay reusing the shipped metric-selection surface against the draft.
        Dialog(
            onDismissRequest = { showMetricSelection = false },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            EdgeToEdgeDialogWindow(fullScreenPage = true)
            Surface(modifier = Modifier.fillMaxSize(), color = colors.background100) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout))
                        .dialogNavigationBarsPadding()
                        .imePadding(),
                ) {
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
}

/**
 * The profile full-screen dialog (DESIGN.md profile-dialog scaling): a close/title bar, a
 * scrolling body at the readable width, and a pinned action bar. Short windows (below 401dp
 * of height per font scale) or a title taking over a third of the height scroll the same
 * composition as a whole, so the title, fields and actions stay reachable. Only modifiers
 * change between the two modes, which keeps field state and keyboard focus.
 */
@Composable
internal fun ProfileFullScreenDialog(
    title: String,
    onDismiss: () -> Unit,
    actions: @Composable () -> Unit,
    body: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        EdgeToEdgeDialogWindow(fullScreenPage = true)
        // A separate native window keeps the anchor's density and direction; never override font scale.
        CompositionLocalProvider(LocalDensity provides density, LocalLayoutDirection provides direction) {
            Surface(modifier = Modifier.fillMaxSize(), color = colors.background100) {
                BoxWithConstraints(
                    Modifier
                        .fillMaxSize()
                        .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout))
                        .dialogNavigationBarsPadding()
                        .imePadding(),
                ) {
                    val measurer = rememberTextMeasurer()
                    val titleHeight = with(density) {
                        measurer.measure(
                            title,
                            GeistType.heading20,
                            constraints = Constraints(
                                maxWidth = (maxWidth - GeistSizes.minimumTouchTarget - GeistSpacing.space4)
                                    .roundToPx()
                                    .coerceAtLeast(1),
                            ),
                        ).size.height.toDp()
                    }
                    val scrollTogether = maxHeight.value / density.fontScale < GeistBreakpoints.small ||
                        titleHeight + GeistSpacing.space2 * 2 > maxHeight / 3
                    val wholeScroll = rememberScrollState()
                    val bodyScroll = rememberScrollState()
                    Column(
                        Modifier
                            .fillMaxSize()
                            .then(if (scrollTogether) Modifier.verticalScroll(wholeScroll) else Modifier),
                    ) {
                        ProfileDialogTopBar(title = title, onClose = onDismiss)
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .then(if (scrollTogether) Modifier else Modifier.weight(1f)),
                            contentAlignment = Alignment.TopCenter,
                        ) {
                            Column(
                                Modifier
                                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                                    .fillMaxWidth()
                                    .then(if (scrollTogether) Modifier else Modifier.verticalScroll(bodyScroll))
                                    .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space6),
                                content = body,
                            )
                        }
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .background(colors.background200)
                                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
                            contentAlignment = Alignment.Center,
                        ) {
                            Box(Modifier.widthIn(max = GeistSizes.readableContentMaxWidth)) { actions() }
                        }
                    }
                }
            }
        }
    }
}

/** Full-screen dialog top bar: Close, then the `heading-20` title, which wraps rather than shrinks. */
@Composable
private fun ProfileDialogTopBar(title: String, onClose: () -> Unit) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .padding(horizontal = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onClose, modifier = Modifier.size(GeistSizes.minimumTouchTarget)) {
            Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.close), tint = colors.primary)
        }
        Text(
            title,
            style = GeistType.heading20,
            color = colors.primary,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = GeistSpacing.space1, vertical = GeistSpacing.space2)
                .semantics { heading() },
        )
    }
}

/** A list-group section: the `heading-14` brand heading, then its rows and fields. */
@Composable
internal fun ProfileSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    Column(Modifier.fillMaxWidth()) {
        Text(
            text = title,
            style = GeistType.heading14,
            color = colors.brandPrimary,
            modifier = Modifier
                .padding(start = GeistSpacing.space4, top = GeistSpacing.space6, bottom = GeistSpacing.space2)
                .semantics { heading() },
        )
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3), content = content)
    }
}

/** A read-only fact as a grouped row: label above a full-width value, so long values wrap. */
@Composable
internal fun ProfileFactRow(
    shape: Shape,
    title: String,
    value: String,
    mono: Boolean = false,
    below: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val colors = LocalGeistColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .heightIn(min = 56.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(title, style = GeistType.label13, color = colors.secondary)
        Text(value, style = if (mono) GeistType.copy14Mono else GeistType.label16, color = colors.primary)
        below?.invoke(this)
    }
}

internal enum class ProfileNoteTone { INFO, WARNING, ERROR }

/** Tonal info/warning/error note (the Export preview pattern): no border. */
@Composable
internal fun ProfileNote(
    tone: ProfileNoteTone,
    message: String,
    modifier: Modifier = Modifier,
    title: String? = null,
) {
    val colors = LocalGeistColors.current
    val (container, accent, icon) = when (tone) {
        ProfileNoteTone.INFO -> Triple(colors.gray.c200, colors.secondary, Icons.Outlined.Info)
        ProfileNoteTone.WARNING -> Triple(colors.amber.c100, colors.warning, Icons.Outlined.WarningAmber)
        ProfileNoteTone.ERROR -> Triple(colors.red.c100, colors.error, Icons.Outlined.ErrorOutline)
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
private fun targetLabel(target: ExportTarget): String = when (target) {
    ExportTarget.DEVICE_FOLDER -> stringResource(R.string.m3_profiles_editor_target_device)
    ExportTarget.GOOGLE_DRIVE -> stringResource(R.string.google_drive_destination_label)
    ExportTarget.API_ENDPOINT -> stringResource(R.string.m3_profiles_editor_target_api)
    ExportTarget.AGENT_DATA_GATEWAY -> stringResource(R.string.export_preview_gateway_destination)
}

/** Exclusive destinations: segmented buttons, or wrapping chips when labels would crowd. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TargetChoice(selected: ExportTarget, onSelect: (ExportTarget) -> Unit) {
    val colors = LocalGeistColors.current
    val targets = ExportTarget.entries
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val reading = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        if (!reading) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                targets.forEachIndexed { index, target ->
                    SegmentedButton(
                        selected = selected == target,
                        onClick = { onSelect(target) },
                        shape = SegmentedButtonDefaults.itemShape(index, targets.size),
                        colors = SegmentedButtonDefaults.colors(
                            activeContainerColor = colors.secondaryContainer,
                            activeContentColor = colors.onSecondaryContainer,
                            inactiveContentColor = colors.primary,
                            activeBorderColor = colors.gray.c700,
                            inactiveBorderColor = colors.gray.c700,
                        ),
                        modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                    ) {
                        Text(targetLabel(target), style = GeistType.button14)
                    }
                }
            }
        } else {
            FlowRow(
                Modifier.fillMaxWidth().selectableGroup(),
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                targets.forEach { target ->
                    val isSelected = selected == target
                    FilterChip(
                        selected = isSelected,
                        onClick = { onSelect(target) },
                        label = { Text(targetLabel(target), style = GeistType.button14) },
                        leadingIcon = if (isSelected) {
                            { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                        } else {
                            null
                        },
                        shape = RoundedCornerShape(GeistRadii.small),
                        colors = profileChipColors(),
                        modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                    )
                }
            }
        }
    }
}

/** Output formats are a multi-select: filled filter chips with a check. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FormatChoice(selected: Set<ExportFormat>, onToggle: (ExportFormat) -> Unit) {
    FlowRow(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        ExportFormat.entries.forEach { format ->
            val isSelected = format in selected
            FilterChip(
                selected = isSelected,
                onClick = { onToggle(format) },
                label = { Text(format.localizedDisplayName(), style = GeistType.button14) },
                leadingIcon = if (isSelected) {
                    { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                } else {
                    null
                },
                shape = RoundedCornerShape(GeistRadii.small),
                colors = profileChipColors(),
                modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
            )
        }
    }
}

@Composable
private fun profileChipColors() = LocalGeistColors.current.let { colors ->
    FilterChipDefaults.filterChipColors(
        selectedContainerColor = colors.secondaryContainer,
        selectedLabelColor = colors.onSecondaryContainer,
        selectedLeadingIconColor = colors.onSecondaryContainer,
        labelColor = colors.secondary,
    )
}

@Composable
private fun EditorTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    supporting: String? = null,
    error: String? = null,
) {
    val colors = LocalGeistColors.current
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true,
        isError = error != null,
        supportingText = (error ?: supporting)?.let { text ->
            {
                Text(
                    text,
                    style = if (error == null) GeistType.label12Mono else GeistType.copy13,
                    color = if (error == null) colors.secondary else colors.error,
                )
            }
        },
        textStyle = GeistType.copy16,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.brandPrimary,
            unfocusedBorderColor = colors.gray.c500,
            focusedLabelColor = colors.brandPrimary,
            unfocusedLabelColor = colors.secondary,
            focusedTextColor = colors.primary,
            unfocusedTextColor = colors.primary,
            cursorColor = colors.brandPrimary,
        ),
        shape = RoundedCornerShape(GeistRadii.small),
    )
}

private class ToggleItem(val label: String, val checked: Boolean, val onCheckedChange: (Boolean) -> Unit)

/** Grouped switch rows: the whole labeled row is the toggle target. */
@Composable
private fun ToggleRows(items: List<ToggleItem>) {
    val colors = LocalGeistColors.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        items.forEachIndexed { index, item ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(groupRowShape(index, items.size))
                    .background(colors.background200)
                    .toggleable(value = item.checked, role = Role.Switch, onValueChange = item.onCheckedChange)
                    .heightIn(min = 56.dp)
                    .padding(start = GeistSpacing.space4, end = GeistSpacing.space3, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Text(item.label, style = GeistType.label16, color = colors.primary, modifier = Modifier.weight(1f))
                AppSwitch(checked = item.checked, onCheckedChange = null)
            }
        }
    }
}

@Composable
private fun ChoiceRows(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(2.dp), content = content)
}

/** One exclusive choice as a grouped row; the selected row takes the secondary container. */
@Composable
private fun EditorRadioRow(
    shape: Shape,
    title: String,
    description: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val content = if (selected) colors.onSecondaryContainer else colors.primary
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) colors.secondaryContainer else colors.background200)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(start = GeistSpacing.space2, end = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(
            selected = selected,
            onClick = null,
            modifier = Modifier.size(GeistSizes.minimumTouchTarget),
            colors = RadioButtonDefaults.colors(
                selectedColor = colors.brandPrimary,
                unselectedColor = colors.gray.c700,
            ),
        )
        Column(modifier = Modifier.weight(1f).padding(start = GeistSpacing.space1)) {
            Text(title, color = content, style = GeistType.label16)
            Text(
                description,
                color = if (selected) colors.onSecondaryContainer else colors.secondary,
                style = descriptionStyle(description),
            )
        }
    }
}

/** Token previews such as `{year}/{month}` read as code. */
private fun descriptionStyle(description: String): TextStyle =
    if (description.startsWith("{")) GeistType.copy13Mono else GeistType.copy14

@Composable
private fun folderOrganizationLabel(org: FolderOrganization): String = when (org) {
    FolderOrganization.FLAT -> stringResource(R.string.folder_organization_flat_label)
    FolderOrganization.BY_YEAR -> stringResource(R.string.folder_organization_by_year_label)
    FolderOrganization.BY_MONTH -> stringResource(R.string.folder_organization_by_month_label)
    FolderOrganization.BY_YEAR_MONTH -> stringResource(R.string.folder_organization_by_year_month_label)
}

@Composable
private fun folderOrganizationPreview(org: FolderOrganization): String = when (org) {
    FolderOrganization.FLAT -> stringResource(R.string.folder_organization_flat_preview)
    FolderOrganization.BY_YEAR -> "{year}"
    FolderOrganization.BY_MONTH -> "{month}"
    FolderOrganization.BY_YEAR_MONTH -> "{year}/{month}"
}
