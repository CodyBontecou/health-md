package com.healthmd.presentation.schedule.composer

import android.text.format.DateFormat
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.LocalAppFolderName
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.export.ExportProfileEditorDialog
import com.healthmd.presentation.export.ExportProfileEditorDraft
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.schedule.ProfileCadenceEditorDialog
import com.healthmd.presentation.schedule.ProfileSchedulesViewModel
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.DayOfWeek
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle

/** Metrics offered as one-tap fields, as on the board; everything else is under All metrics. */
private val QUICK_FIELDS = listOf("sleep_total", "steps", "resting_hr", "hrv", "weight", "blood_oxygen")

/** Content width from which the preview sits beside the sentence (unfolded foldables, tablets). */
private val TWO_PANE_MIN_WIDTH = 600.dp

/** Font scale from which tokens read as a list of labeled choices instead of inline pills. */
private const val LIST_LAYOUT_FONT_SCALE = 1.5f

/**
 * The automation composer: the profile as one editable sentence, each choice a token that opens
 * the editor for that field, with the file it writes rendered live underneath. The daily-note
 * and field choices change in place; everything is staged in the same draft the profile editor
 * uses and is committed with Save. The schedule saves from its own dialog, as elsewhere.
 */
@Composable
fun AutomationComposerScreen(
    profileId: String,
    onBack: () -> Unit,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
    schedulesViewModel: ProfileSchedulesViewModel = hiltViewModel(),
    previewViewModel: ComposerPreviewViewModel = hiltViewModel(),
) {
    val uiState by profilesViewModel.uiState.collectAsStateWithLifecycle()
    val row = uiState.rows.firstOrNull { it.profile.id == profileId }
    val colors = LocalGeistColors.current
    if (row == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = colors.brandPrimary)
        }
        return
    }
    val protection = LocalConfigurationProtection.current
    val guarded: (() -> Unit) -> Unit = { action -> if (protection.enabled) protection.onBlockedChange() else action() }

    // The saved state the draft compares against; refreshed whenever the stored profile changes.
    val baseline = remember(row.profile.updatedAtEpochMillis, uiState.currentSettings) {
        ExportProfilesViewModel.initialEditDraft(row.profile, uiState.currentSettings)
    }
    var draft by remember(baseline) { mutableStateOf(baseline) }
    val dirty = draft != baseline
    val canSave = dirty && draft.settings.exportFormats.isNotEmpty()

    var editingSchedule by rememberSaveable { mutableStateOf(false) }
    var editingMetrics by rememberSaveable { mutableStateOf(false) }
    var editingFormats by rememberSaveable { mutableStateOf(false) }
    var editingAll by rememberSaveable { mutableStateOf(false) }
    var confirmLeave by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(draft.settings) { previewViewModel.preview(draft.settings) }
    val preview by previewViewModel.state.collectAsStateWithLifecycle()

    val save = {
        guarded { profilesViewModel.updateProfile(row.profile.id, draft) }
    }
    val leave = { if (dirty) confirmLeave = true else onBack() }
    BackHandler(enabled = dirty) { confirmLeave = true }

    val onToken: (ComposerToken) -> Unit = { token ->
        guarded {
            when (token) {
                ComposerToken.WHEN, ComposerToken.RANGE -> editingSchedule = true
                ComposerToken.METRICS -> editingMetrics = true
                ComposerToken.WHERE -> editingAll = true
                ComposerToken.FORMATS -> editingFormats = true
                // As on iOS, the note switches in place and Save commits it.
                ComposerToken.NOTE -> draft = draft.copy(
                    settings = draft.settings.copy(
                        dailyNoteInjection = draft.settings.dailyNoteInjection.copy(
                            enabled = !draft.settings.dailyNoteInjection.enabled,
                        ),
                    ),
                )
            }
        }
    }

    Column(Modifier.fillMaxSize().background(colors.background100)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = GeistSpacing.space16)
                .padding(start = GeistSpacing.space1, end = GeistSpacing.space4),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
        ) {
            IconButton(onClick = leave) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.back), tint = colors.primary)
            }
            Text(
                text = row.profile.name,
                style = MaterialTheme.typography.titleLarge,
                color = colors.primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            Button(
                onClick = save,
                enabled = canSave,
                shape = RoundedCornerShape(GeistRadii.full),
                colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
            ) { Text(stringResource(R.string.composer_save), style = GeistType.button14) }
        }

        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val listLayout = LocalDensity.current.fontScale >= LIST_LAYOUT_FONT_SCALE
            val twoPane = maxWidth >= TWO_PANE_MIN_WIDTH && !listLayout
            val values = composerValues(draft, row.entry)
            val sentence: @Composable () -> Unit = {
                if (listLayout) {
                    ComposerTokenList(values = values, onToken = onToken)
                } else {
                    ComposerSentenceView(
                        template = stringResource(
                            if (ComposerSentence.isMultiDay(row.entry)) R.string.composer_template_multi else R.string.composer_template_single,
                        ),
                        values = values,
                        onToken = onToken,
                    )
                }
            }
            val fields: @Composable () -> Unit = {
                ComposerFields(
                    draft = draft,
                    onToggle = { id ->
                        guarded {
                            draft = draft.copy(settings = draft.settings.copy(metricSelection = draft.settings.metricSelection.toggle(id)))
                        }
                    },
                    onAllMetrics = { guarded { editingMetrics = true } },
                )
                AllSettingsRow(onClick = { guarded { editingAll = true } })
            }
            val previewCard: @Composable () -> Unit = { ComposerPreviewCard(preview) }
            if (twoPane) {
                Row(
                    Modifier.fillMaxSize().padding(horizontal = GeistSpacing.space4),
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
                ) {
                    Column(
                        Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = GeistSpacing.space6),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space6 - GeistSpacing.space1),
                    ) {
                        sentence()
                        fields()
                    }
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = GeistSpacing.space6)) {
                        previewCard()
                    }
                }
            } else {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    Column(
                        Modifier
                            .widthIn(max = GeistSizes.readableContentMaxWidth)
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space6),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space6 - GeistSpacing.space1),
                    ) {
                        sentence()
                        previewCard()
                        fields()
                    }
                }
            }
        }
    }

    if (editingSchedule) {
        ProfileCadenceEditorDialog(
            profileId = row.profile.id,
            profileName = row.profile.name,
            entry = row.entry,
            onSave = { entry ->
                editingSchedule = false
                guarded { schedulesViewModel.saveEntry(entry) }
            },
            onDismiss = { editingSchedule = false },
        )
    }
    if (editingMetrics) {
        Dialog(onDismissRequest = { editingMetrics = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(Modifier.fillMaxSize(), color = colors.background100) {
                MetricSelectionScreen(
                    metricSelection = draft.settings.metricSelection,
                    onSelectionChanged = { selection -> draft = draft.copy(settings = draft.settings.copy(metricSelection = selection)) },
                    onBack = { editingMetrics = false },
                )
            }
        }
    }
    if (editingFormats) {
        ComposerFormatsDialog(
            selected = draft.settings.exportFormats,
            onConfirm = { formats ->
                editingFormats = false
                draft = draft.copy(settings = draft.settings.copy(exportFormats = formats))
            },
            onDismiss = { editingFormats = false },
        )
    }
    if (editingAll) {
        // The same full-field editor as Export profiles, seeded with the staged draft.
        ExportProfileEditorDialog(
            isCreation = false,
            initial = draft,
            overlapPreview = { target, folderUri, settings ->
                profilesViewModel.draftOverlapPreview(row.profile.id, target, folderUri, settings)
            },
            onConfirm = { updated ->
                editingAll = false
                draft = updated
            },
            onDismiss = { editingAll = false },
        )
    }
    if (confirmLeave) {
        AlertDialog(
            onDismissRequest = { confirmLeave = false },
            title = { Text(stringResource(R.string.composer_unsaved_title)) },
            text = { Text(stringResource(R.string.composer_unsaved_body)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmLeave = false
                        if (canSave) save()
                        onBack()
                    },
                    enabled = canSave,
                ) { Text(stringResource(R.string.composer_save)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    confirmLeave = false
                    onBack()
                }) { Text(stringResource(R.string.composer_discard), color = colors.error) }
            },
        )
    }
}

/** Token values for the draft in the user's language, time format and calendar. */
@Composable
private fun composerValues(draft: ExportProfileEditorDraft, entry: ScheduledProfileEntry?): ComposerValues {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val clock = entry?.let {
        val pattern = DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm")
        LocalTime.of(it.hour, it.minute).format(DateTimeFormatter.ofPattern(pattern, locale))
    }.orEmpty()
    val whenText = when (ComposerSentence.whenKind(entry)) {
        ComposerWhenKind.MANUAL -> stringResource(R.string.composer_when_manual)
        ComposerWhenKind.DAILY -> stringResource(
            when (ComposerDayPeriod.of(requireNotNull(entry).hour)) {
                ComposerDayPeriod.MORNING -> R.string.composer_when_morning
                ComposerDayPeriod.AFTERNOON -> R.string.composer_when_afternoon
                ComposerDayPeriod.EVENING -> R.string.composer_when_evening
                ComposerDayPeriod.NIGHT -> R.string.composer_when_night
            },
            clock,
        )
        ComposerWhenKind.WEEKLY -> stringResource(
            R.string.composer_when_weekly,
            DayOfWeek.of(requireNotNull(entry).weekdayIso).getDisplayName(TextStyle.FULL, locale),
            clock,
        )
        ComposerWhenKind.MONTHLY -> stringResource(R.string.composer_when_monthly, clock)
        ComposerWhenKind.CUSTOM -> stringResource(R.string.composer_when_custom, clock)
    }
    val days = ComposerSentence.rangeDays(entry)
    val range = if (days > 1) pluralStringResource(R.plurals.composer_range_last_days, days, days) else stringResource(R.string.composer_range_yesterday)
    val metricCount = draft.settings.metricSelection.enabledCount
    val formats = ExportFormat.entries.filter { it in draft.settings.exportFormats }
        .map { it.localizedDisplayName() }.joinToString(" + ")
    val where = destinationLabel(draft)
        ?: LocalAppFolderName.current?.takeIf { draft.target == ExportTarget.DEVICE_FOLDER && draft.folderUri == null }
        ?: stringResource(R.string.automation_destination_selected_folder)
    val values = mapOf(
        ComposerToken.WHEN to whenText,
        ComposerToken.RANGE to range,
        ComposerToken.METRICS to pluralStringResource(R.plurals.composer_metrics, metricCount, metricCount),
        ComposerToken.WHERE to where,
        ComposerToken.FORMATS to formats.ifEmpty { "—" },
        ComposerToken.NOTE to stringResource(
            if (draft.settings.dailyNoteInjection.enabled) R.string.composer_note_update else R.string.composer_note_leave,
        ),
    )
    return ComposerValues(values, emphasis = if (clock.isNotEmpty()) mapOf(ComposerToken.WHEN to clock) else emptyMap())
}

private data class ComposerValues(val values: Map<ComposerToken, String>, val emphasis: Map<ComposerToken, String>)

/** A privacy-safe destination for the draft: the folder name, or only an endpoint's host. */
private fun destinationLabel(draft: ExportProfileEditorDraft): String? = when (draft.target) {
    ExportTarget.DEVICE_FOLDER -> draft.folderDisplayName?.trim()?.takeIf { it.isNotEmpty() }
    ExportTarget.API_ENDPOINT -> runCatching { java.net.URI(draft.apiEndpointUrl.trim()).host }.getOrNull()?.takeIf { it.isNotBlank() }
    ExportTarget.AGENT_DATA_GATEWAY -> runCatching { java.net.URI(draft.agentDataGatewayUrl.trim()).host }.getOrNull()?.takeIf { it.isNotBlank() }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ComposerSentenceView(template: String, values: ComposerValues, onToken: (ComposerToken) -> Unit) {
    val colors = LocalGeistColors.current
    val segments = ComposerSentence.segments(template, values.values, values.emphasis)
    val sentenceStyle = MaterialTheme.typography.headlineSmall.copy(fontSize = 24.sp, lineHeight = 40.sp)
    FlowRow(
        modifier = Modifier.fillMaxWidth().padding(top = GeistSpacing.space3, start = GeistSpacing.space1, end = GeistSpacing.space1),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
    ) {
        segments.forEach { segment ->
            when (segment) {
                is ComposerSegment.Text -> words(segment.text).forEach { word ->
                    Text(word, style = sentenceStyle, color = colors.secondary, modifier = Modifier.align(Alignment.CenterVertically))
                }
                is ComposerSegment.Token -> {
                    val mono = segment.token == ComposerToken.WHERE && (segment.value.contains('/') || segment.value.contains('.'))
                    Text(
                        text = segment.value,
                        style = if (mono) sentenceStyle.copy(fontFamily = GeistType.label14Mono.fontFamily, fontSize = 20.sp) else sentenceStyle,
                        fontWeight = FontWeight.Medium,
                        color = colors.onSecondaryContainer,
                        modifier = Modifier
                            .align(Alignment.CenterVertically)
                            .padding(vertical = 2.dp)
                            .heightIn(min = GeistSizes.control)
                            .clip(RoundedCornerShape(GeistRadii.small + GeistSpacing.space1))
                            .background(colors.secondaryContainer)
                            .clickable(role = Role.Button) { onToken(segment.token) }
                            .padding(horizontal = GeistSpacing.space3),
                    )
                }
            }
        }
    }
}

/** Keeps trailing spaces so wrapped words read naturally. */
private fun words(text: String): List<String> {
    val result = mutableListOf<String>()
    val current = StringBuilder()
    text.forEach { c ->
        current.append(c)
        if (c == ' ') {
            result += current.toString()
            current.clear()
        }
    }
    if (current.isNotEmpty()) result += current.toString()
    return result
}

/** The largest text sizes: each choice as a labeled row, so no token is split across lines. */
@Composable
private fun ComposerTokenList(values: ComposerValues, onToken: (ComposerToken) -> Unit) {
    val colors = LocalGeistColors.current
    val labels = mapOf(
        ComposerToken.WHEN to stringResource(R.string.composer_label_when),
        ComposerToken.RANGE to stringResource(R.string.composer_label_range),
        ComposerToken.METRICS to stringResource(R.string.automation_detail_metrics),
        ComposerToken.WHERE to stringResource(R.string.automation_detail_destination),
        ComposerToken.FORMATS to stringResource(R.string.automation_detail_formats),
        ComposerToken.NOTE to stringResource(R.string.composer_label_note),
    )
    Column(Modifier.fillMaxWidth().padding(top = GeistSpacing.space3), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        ComposerToken.entries.forEachIndexed { index, token ->
            val top = if (index == 0) GeistRadii.listGroup else GeistSpacing.space1
            val bottom = if (index == ComposerToken.entries.lastIndex) GeistRadii.listGroup else GeistSpacing.space1
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(top, top, bottom, bottom))
                    .background(colors.gray.c100)
                    .clickable(role = Role.Button) { onToken(token) }
                    .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
            ) {
                Text(labels.getValue(token), style = GeistType.label14, color = colors.secondary)
                Text(values.values.getValue(token), style = MaterialTheme.typography.titleMedium, color = colors.brandPrimary)
            }
        }
    }
}

@Composable
private fun ComposerPreviewCard(state: ComposerPreviewState) {
    val colors = LocalGeistColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.large))
            .background(colors.gray.c100)
            .padding(GeistSpacing.space4),
    ) {
        val file = (state as? ComposerPreviewState.File)?.file
        Row(
            Modifier.fillMaxWidth().padding(start = GeistSpacing.space1, end = GeistSpacing.space1, bottom = GeistSpacing.space3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            Text(stringResource(R.string.composer_preview_title), style = GeistType.heading14, color = colors.primary, modifier = Modifier.weight(1f))
            if (file != null) {
                Text(
                    file.relativePath,
                    style = GeistType.label12Mono,
                    color = colors.secondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
            }
        }
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 96.dp)
                .clip(RoundedCornerShape(GeistRadii.medium))
                .background(colors.background100)
                .padding(horizontal = GeistSpacing.space3 + 2.dp, vertical = GeistSpacing.space3),
        ) {
            when (state) {
                ComposerPreviewState.Loading -> CircularProgressIndicator(
                    color = colors.brandPrimary,
                    modifier = Modifier.size(24.dp).align(Alignment.Center),
                )
                ComposerPreviewState.RangeArtifactOnly -> PreviewMessage(stringResource(R.string.day_page_range_only))
                ComposerPreviewState.Empty -> PreviewMessage(stringResource(R.string.day_page_empty))
                ComposerPreviewState.Failed -> PreviewMessage(stringResource(R.string.day_page_failed))
                is ComposerPreviewState.File -> {
                    val lines = remember(state.file.content) { state.file.content.trimEnd('\n').lines() }
                    Column {
                        lines.take(PREVIEW_LINES).forEachIndexed { index, line ->
                            val meta = line.trim().let { it == "---" || it == "{" || it == "}" || it.startsWith("date:") || it.startsWith("\"date\":") }
                            Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3 + 2.dp)) {
                                Text(
                                    (index + 1).toString(),
                                    style = GeistType.label12Mono,
                                    color = colors.gray.c700,
                                    textAlign = TextAlign.End,
                                    modifier = Modifier.width(20.dp),
                                )
                                Text(
                                    line.ifEmpty { " " },
                                    style = GeistType.label12Mono,
                                    color = if (meta) colors.secondary else colors.primary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                        if (lines.size > PREVIEW_LINES) {
                            Text("…", style = GeistType.label12Mono, color = colors.secondary, modifier = Modifier.padding(start = 34.dp))
                        }
                    }
                }
            }
        }
        Text(
            stringResource(R.string.composer_preview_note),
            style = MaterialTheme.typography.bodySmall,
            color = colors.secondary,
            modifier = Modifier.padding(start = GeistSpacing.space1, top = GeistSpacing.space3),
        )
    }
}

private const val PREVIEW_LINES = 12

@Composable
private fun PreviewMessage(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = LocalGeistColors.current.secondary)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ComposerFields(draft: ExportProfileEditorDraft, onToggle: (String) -> Unit, onAllMetrics: () -> Unit) {
    val colors = LocalGeistColors.current
    Column {
        Row(Modifier.fillMaxWidth().padding(start = GeistSpacing.space1), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.composer_fields),
                style = GeistType.heading14,
                color = colors.brandPrimary,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onAllMetrics) {
                Text(stringResource(R.string.composer_all_metrics), style = GeistType.button14, color = colors.brandPrimary)
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            QUICK_FIELDS.mapNotNull { id -> HealthMetrics.allMetrics.firstOrNull { it.id == id } }.forEach { metric ->
                val on = draft.settings.metricSelection.isEnabled(metric.id)
                val label = metric.localizedDisplayName()
                val shape = RoundedCornerShape(GeistRadii.small + GeistSpacing.space1)
                Row(
                    Modifier
                        .heightIn(min = GeistSizes.minimumTouchTarget)
                        .clip(shape)
                        .background(if (on) colors.secondaryContainer else androidx.compose.ui.graphics.Color.Transparent)
                        .border(1.dp, if (on) colors.secondaryContainer else colors.gray.c500, shape)
                        .toggleable(value = on, role = Role.Checkbox) { onToggle(metric.id) }
                        .padding(start = if (on) GeistSpacing.space3 - 2.dp else GeistSpacing.space4, end = GeistSpacing.space4),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                ) {
                    if (on) Icon(Icons.Filled.Check, contentDescription = null, tint = colors.onSecondaryContainer, modifier = Modifier.size(18.dp))
                    Text(label, style = GeistType.button14, color = if (on) colors.onSecondaryContainer else colors.secondary)
                }
            }
        }
    }
}

@Composable
private fun AllSettingsRow(onClick: () -> Unit) {
    val colors = LocalGeistColors.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .clip(RoundedCornerShape(GeistRadii.large))
            .background(colors.gray.c100)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(start = GeistSpacing.space6 - GeistSpacing.space1, end = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Icon(Icons.Outlined.Settings, contentDescription = null, tint = colors.secondary)
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.composer_all_settings), style = MaterialTheme.typography.bodyLarge, color = colors.primary)
            Text(stringResource(R.string.composer_all_settings_sub), style = MaterialTheme.typography.bodyMedium, color = colors.secondary)
        }
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.secondary)
    }
}

@Composable
private fun ComposerFormatsDialog(
    selected: Set<ExportFormat>,
    onConfirm: (Set<ExportFormat>) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalGeistColors.current
    var choice by remember(selected) { mutableStateOf(selected) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.automation_detail_formats)) },
        text = {
            Column {
                ExportFormat.entries.forEach { format ->
                    val on = format in choice
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = GeistSizes.minimumTouchTarget)
                            .clickable(role = Role.Checkbox) { choice = if (on) choice - format else choice + format },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(
                            checked = on,
                            onCheckedChange = null,
                            colors = CheckboxDefaults.colors(checkedColor = colors.brandPrimary, checkmarkColor = colors.brandOnPrimary),
                        )
                        Spacer(Modifier.width(GeistSpacing.space3))
                        Text(format.localizedDisplayName(), style = MaterialTheme.typography.bodyLarge, color = colors.primary)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(choice) }, enabled = choice.isNotEmpty()) { Text(stringResource(R.string.composer_done)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
