package com.healthmd.presentation.schedule

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.healthmd.R
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.WriteMode
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.export.ExportProfileEditorDraft
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.settings.DailyNoteInjectionScreen
import com.healthmd.presentation.settings.ExportDetailOverridesSection
import com.healthmd.presentation.settings.FormatCustomizationScreen
import com.healthmd.presentation.settings.FrontmatterCustomizationScreen
import com.healthmd.presentation.settings.IndividualTrackingScreen
import com.healthmd.presentation.settings.SettingsFieldRow
import com.healthmd.presentation.settings.SettingsGroupHeading
import com.healthmd.presentation.settings.SettingsSegmentedChoice
import com.healthmd.presentation.settings.SettingsToggleRow
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.settings.settingsTextFieldColors
import com.healthmd.presentation.settings.settingsTextFieldShape
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.LocalDate
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest

/** The settings pages of one automation, pushed from its detail or composer (iOS `GlassProfilePageKind`). */
enum class AutomationPage(val key: String) {
    METRICS("metrics"),
    FORMATS("formats"),
    OUTPUT("output"),
    FORMAT("format"),
    FRONTMATTER("frontmatter"),
    DAILY_NOTES("daily_notes"),
    ENTRIES("entries");

    companion object {
        fun fromKey(key: String?): AutomationPage? = entries.firstOrNull { it.key == key }
    }
}

/** Routes of an automation's own pages, beside `automation/{profileId}` (its detail). */
object AutomationRoutes {
    const val PAGE = "automation/{profileId}/page/{page}"
    const val SCHEDULE = "automation/{profileId}/schedule"

    fun page(profileId: String, page: AutomationPage): String = "automation/$profileId/page/${page.key}"
    fun schedule(profileId: String): String = "automation/$profileId/schedule"
}

/**
 * Registers an automation's settings pages and its Schedule page. Every page edits that one
 * profile and saves as it changes, so there is no Save or Cancel (iOS `glassAutosave`).
 */
fun NavGraphBuilder.automationProfilePages(
    navController: NavController,
    sleepDayAttribution: () -> SleepDayAttribution,
    onSleepDayAttributionChanged: (SleepDayAttribution) -> Unit,
    /** Whether scheduled exports are a paid feature in this build (Play); F-Droid includes them. */
    showsScheduleAccessNote: Boolean,
) {
    composable(AutomationRoutes.PAGE) { entry ->
        val profileId = entry.arguments?.getString("profileId") ?: return@composable
        val page = AutomationPage.fromKey(entry.arguments?.getString("page")) ?: return@composable
        AutomationProfilePage(
            profileId = profileId,
            page = page,
            onBack = { navController.popBackStack() },
            onOpenPage = { next -> navController.navigate(AutomationRoutes.page(profileId, next)) { launchSingleTop = true } },
            sleepDayAttribution = sleepDayAttribution(),
            onSleepDayAttributionChanged = onSleepDayAttributionChanged,
        )
    }
    composable(AutomationRoutes.SCHEDULE) { entry ->
        val profileId = entry.arguments?.getString("profileId") ?: return@composable
        ProfileSchedulePage(
            profileId = profileId,
            onBack = { navController.popBackStack() },
            showsAccessNote = showsScheduleAccessNote,
        )
    }
}

/** How long after the last change a page saves; leaving the page saves at once. */
private const val AUTOSAVE_DELAY_MILLIS = 400L

/** A page's edited value and the value last written. */
@Stable
internal class ProfileAutosave<T>(initial: T) {
    var value by mutableStateOf(initial)
    var saved by mutableStateOf(initial)
        internal set
    val isDirty: Boolean get() = value != saved

    /** Leaves an unsaved (invalid) change behind, as "Discard change" does. */
    fun discard() {
        value = saved
    }
}

/**
 * Saves [ProfileAutosave.value] shortly after it changes and at once when the page goes away.
 * A change made while settings are locked is undone and the lock's notice explains why; an
 * invalid value is never saved.
 */
@Composable
internal fun <T> rememberProfileAutosave(
    key: String,
    initial: T,
    isValid: (T) -> Boolean = { true },
    save: (T) -> Unit,
): ProfileAutosave<T> {
    val state = remember(key) { ProfileAutosave(initial) }
    val protection by rememberUpdatedState(LocalConfigurationProtection.current)
    val currentSave by rememberUpdatedState(save)
    val currentValid by rememberUpdatedState(isValid)
    LaunchedEffect(state) {
        snapshotFlow { state.value }.collectLatest { value ->
            if (value == state.saved) return@collectLatest
            if (protection.enabled) {
                protection.onBlockedChange()
                state.discard()
                return@collectLatest
            }
            if (!currentValid(value)) return@collectLatest
            delay(AUTOSAVE_DELAY_MILLIS)
            currentSave(value)
            state.saved = value
        }
    }
    DisposableEffect(state) {
        onDispose {
            val value = state.value
            if (value != state.saved && !protection.enabled && currentValid(value)) {
                currentSave(value)
                state.saved = value
            }
        }
    }
    return state
}

/**
 * Back for a page that can hold an invalid change: leaving with one asks before discarding it,
 * so Back never drops a change without saying so. Returns the Back action to use.
 */
@Composable
internal fun guardedBack(holdsInvalidChange: Boolean, reason: String, onDiscard: () -> Unit, onBack: () -> Unit): () -> Unit {
    var confirm by remember { mutableStateOf(false) }
    BackHandler(enabled = holdsInvalidChange) { confirm = true }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text(stringResource(R.string.profile_page_discard_title)) },
            text = { Text(reason) },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    onDiscard()
                    onBack()
                }) { Text(stringResource(R.string.profile_page_discard), color = LocalGeistColors.current.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.profile_page_keep_editing)) }
            },
        )
    }
    return { if (holdsInvalidChange) confirm = true else onBack() }
}

/** One automation's settings page, seeded once from the stored profile. */
@Composable
fun AutomationProfilePage(
    profileId: String,
    page: AutomationPage,
    onBack: () -> Unit,
    onOpenPage: (AutomationPage) -> Unit,
    sleepDayAttribution: SleepDayAttribution,
    onSleepDayAttributionChanged: (SleepDayAttribution) -> Unit,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
) {
    val uiState by profilesViewModel.uiState.collectAsStateWithLifecycle()
    val row = uiState.rows.firstOrNull { it.profile.id == profileId }
    if (row == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = LocalGeistColors.current.brandPrimary)
        }
        return
    }
    // Seeded once: later saves refresh the stored profile without resetting what is on screen.
    val stored = remember(profileId) { ExportProfilesViewModel.initialEditDraft(row.profile, uiState.currentSettings) }
    val key = "$profileId/${page.key}"
    val saveDraft: ((ExportProfileEditorDraft) -> ExportProfileEditorDraft) -> Unit = { change ->
        profilesViewModel.saveDraft(profileId, change)
    }
    when (page) {
        AutomationPage.METRICS -> {
            val state = rememberProfileAutosave(key, stored.settings.metricSelection) { value ->
                saveDraft { it.copy(settings = it.settings.copy(metricSelection = value)) }
            }
            MetricSelectionScreen(metricSelection = state.value, onSelectionChanged = { state.value = it }, onBack = onBack)
        }
        AutomationPage.FORMAT -> {
            val state = rememberProfileAutosave(key, stored.settings.formatCustomization) { value ->
                // Frontmatter fields save on their own page; never undo them with this copy.
                saveDraft {
                    it.copy(
                        settings = it.settings.copy(
                            formatCustomization = value.copy(frontmatterConfig = it.settings.formatCustomization.frontmatterConfig),
                        ),
                    )
                }
            }
            FormatCustomizationScreen(
                customization = state.value,
                onCustomizationChanged = { state.value = it },
                onNavigateToFrontmatter = { onOpenPage(AutomationPage.FRONTMATTER) },
                onBack = onBack,
            )
        }
        AutomationPage.FRONTMATTER -> {
            val state = rememberProfileAutosave(key, stored.settings.formatCustomization.frontmatterConfig) { value ->
                saveDraft {
                    it.copy(settings = it.settings.copy(formatCustomization = it.settings.formatCustomization.copy(frontmatterConfig = value)))
                }
            }
            FrontmatterCustomizationScreen(configuration = state.value, onConfigurationChanged = { state.value = it }, onBack = onBack)
        }
        AutomationPage.DAILY_NOTES -> {
            val state = rememberProfileAutosave(key, stored.settings.dailyNoteInjection) { value ->
                saveDraft { it.copy(settings = it.settings.copy(dailyNoteInjection = value)) }
            }
            DailyNoteInjectionScreen(settings = state.value, onSettingsChanged = { state.value = it }, onBack = onBack)
        }
        AutomationPage.ENTRIES -> {
            val state = rememberProfileAutosave(key, stored.settings.individualTracking) { value ->
                saveDraft { it.copy(settings = it.settings.copy(individualTracking = value)) }
            }
            IndividualTrackingScreen(settings = state.value, onSettingsChanged = { state.value = it }, onBack = onBack)
        }
        AutomationPage.FORMATS -> ProfileFormatsPage(
            key = key,
            stored = stored.settings,
            onSave = saveDraft,
            onBack = onBack,
            sleepDayAttribution = sleepDayAttribution,
            onSleepDayAttributionChanged = onSleepDayAttributionChanged,
        )
        AutomationPage.OUTPUT -> ProfileOutputPage(
            key = key,
            stored = stored,
            onSave = saveDraft,
            overlap = { draft ->
                profilesViewModel.draftOverlapPreview(profileId, draft.target, draft.folderUri, draft.settings)
            },
            onBack = onBack,
        )
    }
}

/** The part of a profile's settings the Formats page edits. */
private data class FormatsDraft(
    val formats: Set<ExportFormat>,
    val includeMetadata: Boolean,
    val groupByCategory: Boolean,
    val includeGranularData: Boolean,
    val detailOverrides: Map<String, String>,
) {
    fun applyTo(settings: ExportSettings): ExportSettings = settings.copy(
        exportFormats = formats,
        includeMetadata = includeMetadata,
        groupByCategory = groupByCategory,
        includeGranularData = includeGranularData,
        detailOverrides = detailOverrides,
    )

    companion object {
        fun of(settings: ExportSettings) = FormatsDraft(
            formats = settings.exportFormats,
            includeMetadata = settings.includeMetadata,
            groupByCategory = settings.groupByCategory,
            includeGranularData = settings.includeGranularData,
            detailOverrides = settings.detailOverrides,
        )
    }
}

/** Formats & detail (iOS `GlassFormatsScreen`), without the packaging options Android lacks. */
@Composable
private fun ProfileFormatsPage(
    key: String,
    stored: ExportSettings,
    onSave: ((ExportProfileEditorDraft) -> ExportProfileEditorDraft) -> Unit,
    onBack: () -> Unit,
    sleepDayAttribution: SleepDayAttribution,
    onSleepDayAttributionChanged: (SleepDayAttribution) -> Unit,
) {
    val colors = LocalGeistColors.current
    val protection = LocalConfigurationProtection.current
    val state = rememberProfileAutosave(
        key = key,
        initial = FormatsDraft.of(stored),
        isValid = { it.formats.isNotEmpty() },
    ) { value -> onSave { it.copy(settings = value.applyTo(it.settings)) } }
    val draft = state.value
    // The detail section reads the page's own choices, over the stored settings.
    val settings = draft.applyTo(stored)
    val needsFormat = stringResource(R.string.formats_need_one)
    val back = guardedBack(
        holdsInvalidChange = state.isDirty && draft.formats.isEmpty(),
        reason = needsFormat,
        onDiscard = state::discard,
        onBack = onBack,
    )
    SubScreen(title = stringResource(R.string.formats_page_title), onBack = back) {
        PageColumn {
            SettingsGroupHeading(stringResource(R.string.formats_page_title))
            val formats = ExportFormat.entries
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                formats.forEachIndexed { index, format ->
                    SettingsToggleRow(
                        shape = groupRowShape(index, formats.size),
                        title = format.localizedDisplayName(),
                        subtitle = stringResource(
                            when (format) {
                                ExportFormat.MARKDOWN -> R.string.formats_markdown_description
                                ExportFormat.OBSIDIAN_BASES -> R.string.formats_bases_description
                                ExportFormat.JSON -> R.string.formats_json_description
                                ExportFormat.CSV -> R.string.formats_csv_description
                            },
                        ),
                        checked = format in draft.formats,
                        onCheckedChange = { on ->
                            state.value = draft.copy(formats = if (on) draft.formats + format else draft.formats - format)
                        },
                    )
                }
            }
            if (ExportFormat.MARKDOWN in draft.formats) {
                Column(Modifier.padding(top = GeistSpacing.space4), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    SettingsToggleRow(
                        shape = groupRowShape(0, 2),
                        title = stringResource(R.string.formats_include_metadata),
                        subtitle = stringResource(R.string.formats_include_metadata_sub),
                        checked = draft.includeMetadata,
                        onCheckedChange = { state.value = draft.copy(includeMetadata = it) },
                    )
                    SettingsToggleRow(
                        shape = groupRowShape(1, 2),
                        title = stringResource(R.string.formats_group_by_category),
                        subtitle = stringResource(R.string.formats_group_by_category_sub),
                        checked = draft.groupByCategory,
                        onCheckedChange = { state.value = draft.copy(groupByCategory = it) },
                    )
                }
            }
            if (draft.formats.isEmpty()) {
                Text(
                    needsFormat,
                    style = GeistType.copy14,
                    color = colors.error,
                    modifier = Modifier.padding(start = GeistSpacing.space4, top = GeistSpacing.space3),
                )
            }

            SettingsGroupHeading(stringResource(R.string.formats_data_detail))
            SettingsToggleRow(
                shape = groupRowShape(0, 1),
                title = stringResource(R.string.granular_data_title),
                subtitle = stringResource(R.string.granular_data_description),
                checked = draft.includeGranularData,
                onCheckedChange = { state.value = draft.copy(includeGranularData = it) },
            )
            ExportDetailOverridesSection(
                settings = settings,
                onDetailChoiceChanged = { group, choice ->
                    state.value = draft.copy(detailOverrides = settings.withDetailChoice(group, choice).detailOverrides)
                },
            )
            Text(
                stringResource(R.string.formats_uploads_note),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier.padding(start = GeistSpacing.space4, top = GeistSpacing.space2),
            )

            // A device-local capture preference: it applies to every automation and saves at once.
            SettingsGroupHeading(stringResource(R.string.formats_sleep_day))
            SettingsFieldRow(shape = groupRowShape(0, 1)) {
                SettingsSegmentedChoice(
                    options = listOf(SleepDayAttribution.NIGHT_BEGINS, SleepDayAttribution.MORNING_ENDS),
                    selected = sleepDayAttribution,
                    label = { mode ->
                        stringResource(
                            when (mode) {
                                SleepDayAttribution.NIGHT_BEGINS -> R.string.sleep_attribution_night_begins
                                SleepDayAttribution.MORNING_ENDS -> R.string.sleep_attribution_morning_ends
                            },
                        )
                    },
                    onSelect = { mode ->
                        if (protection.enabled) protection.onBlockedChange() else onSleepDayAttributionChanged(mode)
                    },
                    enabled = { it.isAvailableForShippedProfiles },
                )
                Text(
                    stringResource(
                        when (sleepDayAttribution) {
                            SleepDayAttribution.NIGHT_BEGINS -> R.string.sleep_attribution_night_begins_description
                            SleepDayAttribution.MORNING_ENDS -> if (sleepDayAttribution.isAvailableForShippedProfiles) {
                                R.string.sleep_attribution_morning_ends_wake_description
                            } else {
                                R.string.sleep_attribution_morning_ends_description
                            }
                        },
                    ) + " " + stringResource(R.string.formats_sleep_day_note),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
            }
        }
    }
}

/** Everything the Output page saves, compared as one value for autosave. */
private data class OutputDraft(
    val target: ExportTarget,
    val folderUri: String?,
    val folderDisplayName: String?,
    val apiEndpointUrl: String,
    val agentDataGatewayUrl: String,
    val subfolder: String,
    val folderOrganization: FolderOrganization,
    val folderStructure: String,
    val filenameFormat: String,
    val writeMode: WriteMode,
) {
    val isValid: Boolean
        get() = when (target) {
            ExportTarget.DEVICE_FOLDER -> true
            ExportTarget.API_ENDPOINT -> APIExportEndpoint.isConfigured(apiEndpointUrl)
            ExportTarget.AGENT_DATA_GATEWAY -> AgentDataGatewayEndpoint.isConfigured(agentDataGatewayUrl)
        }

    fun applyTo(draft: ExportProfileEditorDraft): ExportProfileEditorDraft = draft.copy(
        target = target,
        folderUri = folderUri,
        folderDisplayName = folderDisplayName,
        apiEndpointUrl = apiEndpointUrl,
        agentDataGatewayUrl = agentDataGatewayUrl,
        settings = draft.settings.copy(
            subfolder = subfolder,
            folderOrganization = folderOrganization,
            folderStructure = folderStructure,
            filenameFormat = filenameFormat,
            writeMode = writeMode,
        ),
    )

    companion object {
        fun of(draft: ExportProfileEditorDraft) = OutputDraft(
            target = draft.target,
            folderUri = draft.folderUri,
            folderDisplayName = draft.folderDisplayName,
            apiEndpointUrl = draft.apiEndpointUrl,
            agentDataGatewayUrl = draft.agentDataGatewayUrl,
            subfolder = draft.settings.subfolder,
            folderOrganization = draft.settings.folderOrganization,
            folderStructure = draft.settings.folderStructure,
            filenameFormat = draft.settings.filenameFormat,
            writeMode = draft.settings.writeMode,
        )
    }
}

/** Output (iOS `GlassOutputScreen`): where an automation writes, how files are named, and overwrites. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProfileOutputPage(
    key: String,
    stored: ExportProfileEditorDraft,
    onSave: ((ExportProfileEditorDraft) -> ExportProfileEditorDraft) -> Unit,
    overlap: (ExportProfileEditorDraft) -> List<String>,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    val state = rememberProfileAutosave(key, OutputDraft.of(stored), isValid = { it.isValid }) { value ->
        onSave { value.applyTo(it) }
    }
    val draft = state.value
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        val files = FileExportManager(context)
        files.takePersistablePermission(uri)
        state.value = state.value.copy(folderUri = uri.toString(), folderDisplayName = files.getFolderDisplayName(uri.toString()))
    }
    val invalidReason = stringResource(R.string.output_endpoint_invalid)
    val back = guardedBack(
        holdsInvalidChange = state.isDirty && !draft.isValid,
        reason = invalidReason,
        onDiscard = state::discard,
        onBack = onBack,
    )
    val preview = draft.applyTo(stored)
    SubScreen(title = stringResource(R.string.output_page_title), onBack = back) {
        PageColumn(Modifier.imePadding()) {
            SettingsGroupHeading(stringResource(R.string.output_where))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                SettingsFieldRow(shape = groupRowShape(0, 2)) {
                    Text(stringResource(R.string.output_destination), style = GeistType.label16, color = colors.primary)
                    SettingsSegmentedChoice(
                        options = ExportTarget.entries.toList(),
                        selected = draft.target,
                        label = { target ->
                            stringResource(
                                when (target) {
                                    ExportTarget.DEVICE_FOLDER -> R.string.m3_profiles_editor_target_device
                                    ExportTarget.API_ENDPOINT -> R.string.m3_profiles_editor_target_api
                                    ExportTarget.AGENT_DATA_GATEWAY -> R.string.export_preview_gateway_destination
                                },
                            )
                        },
                        onSelect = { state.value = draft.copy(target = it) },
                    )
                }
                SettingsFieldRow(shape = groupRowShape(1, 2)) {
                    when (draft.target) {
                        ExportTarget.DEVICE_FOLDER -> {
                            Text(stringResource(R.string.output_folder), style = GeistType.label16, color = colors.primary)
                            Text(
                                draft.folderDisplayName ?: draft.folderUri ?: stringResource(R.string.output_folder_app),
                                style = GeistType.copy14Mono,
                                color = colors.secondary,
                            )
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                            ) {
                                SecondaryButton(
                                    text = stringResource(
                                        if (draft.folderUri == null) R.string.folder_destination_choose else R.string.folder_destination_change,
                                    ),
                                    onClick = { folderPicker.launch(null) },
                                )
                                if (draft.folderUri != null) {
                                    TextButton(onClick = { state.value = draft.copy(folderUri = null, folderDisplayName = null) }) {
                                        Text(stringResource(R.string.output_use_app_folder), style = GeistType.button14)
                                    }
                                }
                            }
                        }
                        ExportTarget.API_ENDPOINT -> UrlField(
                            value = draft.apiEndpointUrl,
                            label = stringResource(R.string.api_export_endpoint_url_label),
                            error = invalidReason.takeIf { !draft.isValid },
                            onValueChange = { state.value = draft.copy(apiEndpointUrl = it) },
                        )
                        ExportTarget.AGENT_DATA_GATEWAY -> UrlField(
                            value = draft.agentDataGatewayUrl,
                            label = stringResource(R.string.agent_data_gateway_url_label),
                            error = invalidReason.takeIf { !draft.isValid },
                            onValueChange = { state.value = draft.copy(agentDataGatewayUrl = it) },
                        )
                    }
                }
            }

            SettingsGroupHeading(stringResource(R.string.output_files))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                SettingsFieldRow(shape = groupRowShape(0, 3)) {
                    TemplateField(
                        value = draft.subfolder,
                        label = stringResource(R.string.health_subfolder_label),
                        onValueChange = { state.value = draft.copy(subfolder = it) },
                    )
                }
                SettingsFieldRow(shape = groupRowShape(1, 3)) {
                    Text(stringResource(R.string.folder_organization_label), style = GeistType.label16, color = colors.primary)
                    SettingsSegmentedChoice(
                        options = FolderOrganization.entries.toList(),
                        selected = draft.folderOrganization,
                        label = { organization ->
                            stringResource(
                                when (organization) {
                                    FolderOrganization.FLAT -> R.string.folder_organization_flat_label
                                    FolderOrganization.BY_YEAR -> R.string.folder_organization_by_year_label
                                    FolderOrganization.BY_MONTH -> R.string.folder_organization_by_month_label
                                    FolderOrganization.BY_YEAR_MONTH -> R.string.folder_organization_by_year_month_label
                                },
                            )
                        },
                        onSelect = { state.value = draft.copy(folderOrganization = it) },
                    )
                    TemplateField(
                        value = draft.folderStructure,
                        label = stringResource(R.string.folder_structure_template_label),
                        onValueChange = { state.value = draft.copy(folderStructure = it) },
                    )
                }
                SettingsFieldRow(shape = groupRowShape(2, 3)) {
                    TemplateField(
                        value = draft.filenameFormat,
                        label = stringResource(R.string.m3_profiles_editor_filename_template),
                        supporting = stringResource(R.string.filename_template_tokens),
                        onValueChange = { state.value = draft.copy(filenameFormat = it) },
                    )
                }
            }

            SettingsGroupHeading(stringResource(R.string.output_when_file_exists))
            SettingsFieldRow(shape = groupRowShape(0, 1)) {
                SettingsSegmentedChoice(
                    options = WriteMode.entries.toList(),
                    selected = draft.writeMode,
                    label = { it.localizedDisplayName() },
                    onSelect = { state.value = draft.copy(writeMode = it) },
                )
                Text(stringResource(R.string.output_write_mode_note), style = GeistType.copy14, color = colors.secondary)
            }

            val yesterday = LocalDate.now().minusDays(1)
            val paths = ExportFormat.entries.filter { it in preview.settings.exportFormats }
                .map { preview.settings.aggregateRelativePath(yesterday, it) }
            if (draft.target == ExportTarget.DEVICE_FOLDER && paths.isNotEmpty()) {
                SettingsGroupHeading(stringResource(R.string.output_writes_to))
                SettingsFieldRow(shape = groupRowShape(0, 1)) {
                    paths.forEach { Text(it, style = GeistType.copy13Mono, color = colors.primary) }
                }
            }

            val overlapping = overlap(preview)
            if (overlapping.isNotEmpty()) {
                Text(
                    stringResource(R.string.m3_profiles_editor_overlap, overlapping.joinToString(", ")),
                    style = GeistType.copy14,
                    color = colors.warning,
                    modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space4),
                )
            }
        }
    }
}

@Composable
private fun PageColumn(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8),
        content = content,
    )
}

@Composable
private fun TemplateField(value: String, label: String, onValueChange: (String) -> Unit, supporting: String? = null) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        supportingText = supporting?.let { { Text(it, style = GeistType.copy13Mono) } },
        singleLine = true,
        textStyle = GeistType.copy14Mono,
        colors = settingsTextFieldColors(),
        shape = settingsTextFieldShape,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
    )
}

@Composable
private fun UrlField(value: String, label: String, error: String?, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        isError = error != null,
        supportingText = error?.let { { Text(it) } },
        singleLine = true,
        textStyle = GeistType.copy14Mono,
        colors = settingsTextFieldColors(),
        shape = settingsTextFieldShape,
        modifier = Modifier.fillMaxWidth(),
    )
}
