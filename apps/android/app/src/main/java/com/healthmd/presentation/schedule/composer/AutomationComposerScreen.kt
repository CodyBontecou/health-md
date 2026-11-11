package com.healthmd.presentation.schedule.composer

import androidx.compose.runtime.setValue
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.LocalAppFolderName
import com.healthmd.rawexport.ExportMode
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.schedule.AutomationPage
import com.healthmd.presentation.schedule.AutomationSentence
import com.healthmd.presentation.schedule.ComposerDraft
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** Content width from which the preview sits beside the sentence (unfolded foldables, tablets). */
private val TWO_PANE_MIN_WIDTH = 600.dp

/** Font scale from which tokens read as a list of labeled choices instead of inline pills. */
private const val LIST_LAYOUT_FONT_SCALE = 1.5f

/** Fields the composer lists before "All", as on iOS. */
private const val VISIBLE_FIELD_COUNT = 6

/**
 * The automation composer (iOS `ComposerScreen`): the profile as one editable sentence whose
 * tokens push the page for that choice, with the file it writes rendered live underneath.
 * Field checks and the daily-note switch are staged on top of the saved profile and committed
 * with Save; choices made on their own pages save there, so they are never undone here.
 */
@Composable
fun AutomationComposerScreen(
    profileId: String,
    onBack: () -> Unit,
    /** Pushes one of the automation's settings pages. */
    onOpenPage: (AutomationPage) -> Unit,
    onOpenSchedule: () -> Unit,
    /** "All settings": returns to the automation's detail, or opens it. */
    onAllSettings: () -> Unit,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
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

    // The saved profile the staged choices apply to; refreshed whenever a page saves.
    val saved = remember(row.profile.updatedAtEpochMillis, uiState.currentSettings) {
        ExportProfilesViewModel.initialEditDraft(row.profile, uiState.currentSettings)
    }
    var draft by rememberSaveable(profileId, stateSaver = ComposerDraftSaver) { mutableStateOf(ComposerDraft()) }
    val settings = draft.applyTo(saved.settings)
    val rawSnapshot = settings.exportMode == ExportMode.RAW_SNAPSHOT
    var confirmLeave by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(settings) { previewViewModel.preview(settings) }
    val preview by previewViewModel.state.collectAsStateWithLifecycle()

    val save = {
        guarded {
            if (!draft.isEmpty) {
                val staged = draft
                profilesViewModel.saveDraft(profileId) { it.copy(settings = staged.applyTo(it.settings)) }
                draft = ComposerDraft()
            }
            onBack()
        }
    }
    val leave = { if (draft.isEmpty) onBack() else confirmLeave = true }
    BackHandler(enabled = !draft.isEmpty) { confirmLeave = true }

    val onToken: (ComposerToken) -> Unit = { token ->
        guarded {
            when (token) {
                ComposerToken.WHEN, ComposerToken.RANGE -> onOpenSchedule()
                ComposerToken.METRICS -> onOpenPage(AutomationPage.METRICS)
                ComposerToken.WHERE -> onOpenPage(AutomationPage.OUTPUT)
                ComposerToken.FORMATS -> onOpenPage(AutomationPage.FORMATS)
                // As on iOS, the note switches in place and Save commits it.
                ComposerToken.NOTE -> draft = draft.toggleNote(saved.settings)
            }
        }
    }

    val listLayout = LocalDensity.current.fontScale >= LIST_LAYOUT_FONT_SCALE
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
                // The largest text sizes keep the bare name so the title fits.
                text = if (listLayout) row.profile.name else stringResource(R.string.automation_composer_title, row.profile.name),
                style = MaterialTheme.typography.titleLarge,
                color = colors.primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            Button(
                onClick = save,
                shape = RoundedCornerShape(GeistRadii.full),
                colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
            ) { Text(stringResource(R.string.composer_save), style = GeistType.button14) }
        }

        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val twoPane = maxWidth >= TWO_PANE_MIN_WIDTH && !listLayout
            val destination = AutomationSentence.destination(row.profile, LocalAppFolderName.current)
                ?: stringResource(R.string.automation_destination_selected_folder)
            val values = automationSentenceValues(settings, row.entry, destination, summary = false)
            val sentence: @Composable () -> Unit = {
                if (listLayout) {
                    ComposerTokenList(values = values, onToken = onToken)
                } else {
                    ComposerSentenceView(
                        template = stringResource(
                            when {
                                rawSnapshot && ComposerSentence.isMultiDay(row.entry) -> R.string.automation_summary_multi
                                rawSnapshot -> R.string.automation_summary_single
                                ComposerSentence.isMultiDay(row.entry) -> R.string.composer_template_multi
                                else -> R.string.composer_template_single
                            },
                        ),
                        values = values,
                        onToken = onToken,
                    )
                }
            }
            val fields: @Composable () -> Unit = {
                if (!rawSnapshot) ComposerFields(
                    saved = saved.settings,
                    pending = draft.fields,
                    onToggle = { id -> guarded { draft = draft.toggleField(id, saved.settings) } },
                    onAllMetrics = { guarded { onOpenPage(AutomationPage.METRICS) } },
                )
                AllSettingsRow(onClick = onAllSettings)
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

    if (confirmLeave) {
        AlertDialog(
            onDismissRequest = { confirmLeave = false },
            title = { Text(stringResource(R.string.composer_unsaved_title)) },
            text = { Text(stringResource(R.string.composer_unsaved_body)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmLeave = false
                    save()
                }) { Text(stringResource(R.string.composer_save)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    confirmLeave = false
                    draft = ComposerDraft()
                    onBack()
                }) { Text(stringResource(R.string.composer_discard), color = colors.error) }
            },
        )
    }
}

/** Keeps staged choices across configuration changes and process death. */
private val ComposerDraftSaver = androidx.compose.runtime.saveable.Saver<ComposerDraft, ArrayList<String>>(
    save = { draft ->
        ArrayList(
            listOf(draft.note?.toString().orEmpty()) +
                draft.fields.map { (id, on) -> "${if (on) '1' else '0'}$id" },
        )
    },
    restore = { saved ->
        ComposerDraft(
            fields = saved.drop(1).associate { it.drop(1) to (it.first() == '1') },
            note = saved.firstOrNull()?.takeIf { it.isNotEmpty() }?.toBooleanStrict(),
        )
    },
)
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ComposerSentenceView(template: String, values: ComposerValues, onToken: (ComposerToken) -> Unit) {
    val colors = LocalGeistColors.current
    val segments = ComposerSentence.summarySegments(template, values.values, values.emphasis)
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
        val tokens = ComposerToken.entries.filter { it in values.values }
        tokens.forEachIndexed { index, token ->
            val top = if (index == 0) GeistRadii.listGroup else GeistSpacing.space1
            val bottom = if (index == tokens.lastIndex) GeistRadii.listGroup else GeistSpacing.space1
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
            stringResource(if (state == ComposerPreviewState.RangeArtifactOnly) R.string.raw_snapshot_one_artifact_note else R.string.composer_preview_note),
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


@Composable
private fun ComposerFields(
    saved: ExportSettings,
    pending: Map<String, Boolean>,
    onToggle: (String) -> Unit,
    onAllMetrics: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val fields = HealthMetrics.allMetrics
        .filter { saved.metricSelection.isEnabled(it.id) || pending.containsKey(it.id) }
        .take(VISIBLE_FIELD_COUNT)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.large))
            .background(colors.gray.c100)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space1),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.composer_fields),
                style = GeistType.label14,
                color = colors.secondary,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onAllMetrics) {
                Text(
                    stringResource(R.string.composer_all_count, HealthMetrics.totalCount),
                    style = GeistType.button14,
                    color = colors.brandPrimary,
                )
            }
        }
        fields.forEach { metric ->
            val on = pending[metric.id] ?: saved.metricSelection.isEnabled(metric.id)
            HorizontalDivider(color = colors.gray.c400)
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = GeistSizes.minimumTouchTarget)
                    .toggleable(value = on, role = Role.Checkbox) { onToggle(metric.id) },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Text(
                    metric.localizedDisplayName(),
                    style = MaterialTheme.typography.bodyLarge,
                    color = colors.primary,
                    modifier = Modifier.weight(1f),
                )
                Box(
                    Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .then(
                            if (on) Modifier.background(colors.brandPrimary)
                            else Modifier.border(1.5.dp, colors.gray.c600, CircleShape),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (on) Icon(Icons.Filled.Check, contentDescription = null, tint = colors.brandOnPrimary, modifier = Modifier.size(14.dp))
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
            Text(stringResource(R.string.composer_all_settings_hint), style = MaterialTheme.typography.bodyMedium, color = colors.secondary)
        }
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.secondary)
    }
}
