package com.healthmd.presentation.schedule

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.LocalAppFolderName
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.export.ExportProfileRow
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.schedule.composer.automationSummary
import com.healthmd.presentation.settings.SettingsGroupHeading
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.settings.settingsTextFieldColors
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.DayOfWeek
import java.time.format.TextStyle

internal object AutomationDetailTags {
    const val RUN_NOW = "automation.detail.runNow"
    const val DUPLICATE = "automation.detail.duplicate"
    const val PAUSE = "automation.detail.pause"
    const val EDIT_SENTENCE = "automation.detail.editSentence"
    const val DELETE = "automation.detail.delete"
}

/** Android's automation-app documentation: explicit broadcasts that accept a PROFILE extra. */
private const val AUTOMATION_APPS_URL = "https://healthmd.app/docs/android/#scheduling-and-automation"

/**
 * An automation's detail (iOS `AutomationDetailScreen`): its sentence, Run now / Duplicate /
 * Pause, the settings rows that push its own pages, the ID automations and the CLI reference,
 * and Delete. On a phone it is a pushed screen titled with the automation's name ([onBack]);
 * beside the list on wide layouts it is a bare pane.
 */
@Composable
fun AutomationDetailPane(
    profileId: String?,
    onCompose: (String) -> Unit,
    onRunNow: (String) -> Unit,
    onOpenPage: (String, AutomationPage) -> Unit,
    onOpenSchedule: (String) -> Unit,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    /** Called once the automation is deleted, so a phone screen can close. */
    onDeleted: (() -> Unit)? = null,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
    schedulesViewModel: ProfileSchedulesViewModel = hiltViewModel(),
) {
    val profiles by profilesViewModel.uiState.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    val row = profiles.rows.firstOrNull { it.profile.id == profileId }
    val frame: @Composable (String, @Composable () -> Unit) -> Unit = { title, content ->
        if (onBack != null) {
            SubScreen(title = title, onBack = onBack, modifier = modifier) { content() }
        } else {
            Box(modifier) { content() }
        }
    }
    if (profileId == null || row == null) {
        frame(stringResource(R.string.nav_automations)) {
            Text(
                text = stringResource(if (profileId == null) R.string.automation_detail_select else R.string.automation_detail_not_found),
                style = MaterialTheme.typography.bodyLarge,
                color = colors.secondary,
                modifier = Modifier.padding(GeistSpacing.space6),
            )
        }
        return
    }
    var confirmDelete by remember(profileId) { mutableStateOf(false) }
    var renaming by remember(profileId) { mutableStateOf(false) }
    val protection = LocalConfigurationProtection.current
    val guarded: (() -> Unit) -> Unit = { action -> if (protection.enabled) protection.onBlockedChange() else action() }
    val id = row.profile.id
    val settings = remember(row.profile.updatedAtEpochMillis, profiles.currentSettings) {
        ExportProfilesViewModel.initialEditDraft(row.profile, profiles.currentSettings).settings
    }

    frame(row.profile.name) {
        AutomationDetailContent(
            row = row,
            settings = settings,
            canDelete = profiles.rows.size > 1,
            onCompose = { guarded { onCompose(id) } },
            onRunNow = { onRunNow(id) },
            onDuplicate = { guarded { profilesViewModel.duplicate(id) } },
            onToggleSchedule = { enabled -> guarded { schedulesViewModel.setEnabled(id, enabled) } },
            onRename = { guarded { renaming = true } },
            onOpenPage = { page -> guarded { onOpenPage(id, page) } },
            onOpenSchedule = { guarded { onOpenSchedule(id) } },
            onDelete = { guarded { confirmDelete = true } },
        )
    }

    // Dialogs are separate windows outside the protected region: re-check the lock on confirm.
    if (confirmDelete) {
        ProfileScheduleDeleteDialog(
            profileName = row.profile.name,
            onDismiss = { confirmDelete = false },
            onDelete = {
                confirmDelete = false
                guarded {
                    schedulesViewModel.deleteProfile(id)
                    onDeleted?.invoke()
                }
            },
        )
    }
    if (renaming) {
        RenameDialog(
            name = row.profile.name,
            onDismiss = { renaming = false },
            onSave = { name ->
                renaming = false
                guarded { profilesViewModel.rename(id, name) }
            },
        )
    }
}

@Composable
private fun AutomationDetailContent(
    row: ExportProfileRow,
    settings: ExportSettings,
    canDelete: Boolean,
    onCompose: () -> Unit,
    onRunNow: () -> Unit,
    onDuplicate: () -> Unit,
    onToggleSchedule: (Boolean) -> Unit,
    onRename: () -> Unit,
    onOpenPage: (AutomationPage) -> Unit,
    onOpenSchedule: () -> Unit,
    onDelete: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val profile = row.profile
    val entry = row.entry
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space10),
    ) {
        // The automation as a sentence, and the composer that edits it.
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.large))
                .background(colors.background200)
                .padding(start = GeistSpacing.space6 - GeistSpacing.space1, end = GeistSpacing.space6 - GeistSpacing.space1, top = GeistSpacing.space6 - GeistSpacing.space1, bottom = GeistSpacing.space2),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            Text(stringResource(R.string.automation_section_automation), style = GeistType.label12, color = colors.secondary)
            Text(
                automationSummary(
                    settings = settings,
                    entry = entry,
                    destination = AutomationSentence.destination(profile, LocalAppFolderName.current)
                        ?: stringResource(R.string.automation_destination_selected_folder),
                    sends = profile.target != ExportTarget.DEVICE_FOLDER,
                    tokenStyle = SpanStyle(color = colors.brandPrimary, fontWeight = FontWeight.Medium),
                ),
                style = GeistType.copy18,
                color = colors.secondary,
            )
            TextButton(onClick = onCompose, modifier = Modifier.testTag(AutomationDetailTags.EDIT_SENTENCE)) {
                Text(stringResource(R.string.composer_edit_sentence) + " →", style = GeistType.button14, color = colors.brandPrimary)
            }
        }

        // Three equal neutral actions, as on iOS.
        Row(
            Modifier.fillMaxWidth().padding(top = GeistSpacing.space3),
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            DetailAction(stringResource(R.string.automations_run_now), onRunNow, Modifier.weight(1f).testTag(AutomationDetailTags.RUN_NOW))
            DetailAction(stringResource(R.string.automation_duplicate), onDuplicate, Modifier.weight(1f).testTag(AutomationDetailTags.DUPLICATE))
            if (entry != null) {
                DetailAction(
                    stringResource(if (entry.isEnabled) R.string.automation_pause else R.string.automation_resume),
                    { onToggleSchedule(!entry.isEnabled) },
                    Modifier.weight(1f).testTag(AutomationDetailTags.PAUSE),
                )
            }
        }

        if (row.overlappingProfileNames.isNotEmpty()) {
            Row(
                Modifier
                    .padding(top = GeistSpacing.space4)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(GeistRadii.listGroup))
                    .background(colors.tertiaryContainer)
                    .padding(GeistSpacing.space4),
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Icon(Icons.Outlined.Warning, contentDescription = null, tint = colors.onTertiaryContainer)
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.automation_overlap_title), style = GeistType.heading14, color = colors.onTertiaryContainer)
                    Text(
                        stringResource(R.string.automation_overlap_body, row.overlappingProfileNames.joinToString(", ")),
                        style = GeistType.copy14,
                        color = colors.onTertiaryContainer,
                    )
                }
            }
        }

        SettingsGroupHeading(stringResource(R.string.nav_settings))
        val on = stringResource(R.string.automation_value_on)
        val off = stringResource(R.string.automation_value_off)
        val rows = listOf<Triple<String, String, () -> Unit>>(
            Triple(stringResource(R.string.automation_row_name), profile.name, onRename),
            Triple(stringResource(R.string.automation_detail_metrics), settings.metricSelection.enabledCount.toString()) {
                onOpenPage(AutomationPage.METRICS)
            },
            Triple(stringResource(R.string.automation_row_formats), AutomationFacts.formatsShortLabel(settings.exportFormats).ifEmpty { "—" }) {
                onOpenPage(AutomationPage.FORMATS)
            },
            Triple(stringResource(R.string.automation_row_output), settings.writeMode.localizedDisplayName()) {
                onOpenPage(AutomationPage.OUTPUT)
            },
            Triple(
                stringResource(R.string.automation_row_format),
                stringResource(
                    if (AutomationFacts.isStandardFormat(settings.formatCustomization)) {
                        R.string.automation_format_standard
                    } else {
                        R.string.automation_format_custom
                    },
                ),
            ) { onOpenPage(AutomationPage.FORMAT) },
            Triple(stringResource(R.string.automation_row_daily_notes), if (settings.dailyNoteInjection.enabled) on else off) {
                onOpenPage(AutomationPage.DAILY_NOTES)
            },
            Triple(stringResource(R.string.automation_row_entries), if (settings.individualTracking.globalEnabled) on else off) {
                onOpenPage(AutomationPage.ENTRIES)
            },
            Triple(stringResource(R.string.automation_detail_schedule), scheduleShortLabel(entry), onOpenSchedule),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            rows.forEachIndexed { index, (title, value, onClick) ->
                DetailRow(groupRowShape(index, rows.size), title, value, onClick)
            }
        }

        SettingsGroupHeading(stringResource(R.string.automation_detail_cli))
        CliSection(profile.id)

        // Delete, apart from everything else; the last automation stays.
        Column(Modifier.padding(top = GeistSpacing.space8), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .clip(RoundedCornerShape(GeistRadii.listGroup))
                    .background(colors.background200)
                    .clickable(enabled = canDelete, role = Role.Button, onClick = onDelete)
                    .alpha(if (canDelete) 1f else 0.4f)
                    .testTag(AutomationDetailTags.DELETE),
                contentAlignment = Alignment.Center,
            ) {
                Text(stringResource(R.string.automation_delete), style = GeistType.label16, color = colors.error)
            }
            Text(
                stringResource(if (canDelete) R.string.automation_delete_keeps_files else R.string.automation_delete_keep_one),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space4),
            )
        }
    }
}

@Composable
private fun DetailAction(label: String, onClick: () -> Unit, modifier: Modifier) {
    val colors = LocalGeistColors.current
    FilledTonalButton(
        onClick = onClick,
        shape = CircleShape,
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = colors.secondaryContainer,
            contentColor = colors.onSecondaryContainer,
        ),
        modifier = modifier.heightIn(min = GeistSizes.minimumTouchTarget),
    ) {
        Text(label, style = GeistType.button14, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

/** One settings row: title, its current value and a chevron; the whole row pushes its page. */
@Composable
private fun DetailRow(shape: Shape, title: String, value: String, onClick: () -> Unit) {
    val colors = LocalGeistColors.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space3, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Text(title, style = GeistType.label16, color = colors.primary, modifier = Modifier.weight(1f))
        Text(
            value,
            style = GeistType.label14,
            color = colors.secondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.secondary)
    }
}

@Composable
private fun CliSection(profileId: String) {
    val colors = LocalGeistColors.current
    val clipboard = LocalClipboardManager.current
    val uriHandler = LocalUriHandler.current
    var copied by remember(profileId) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(groupRowShape(0, 2))
                .background(colors.background200)
                .heightIn(min = 72.dp)
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space2, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.automation_detail_profile_id), style = GeistType.label16, color = colors.primary)
                Text(profileId, style = GeistType.label12Mono, color = colors.secondary)
            }
            TextButton(
                onClick = {
                    clipboard.setText(AnnotatedString(profileId))
                    copied = true
                },
                modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
            ) {
                Text(
                    stringResource(if (copied) R.string.automation_detail_copied else R.string.automation_detail_copy),
                    style = GeistType.button14,
                )
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .clip(groupRowShape(1, 2))
                .background(colors.background200)
                .clickable(role = Role.Button) { uriHandler.openUri(AUTOMATION_APPS_URL) }
                .heightIn(min = 72.dp)
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.automation_use_in_automation_apps), style = GeistType.label16, color = colors.primary)
                Text(stringResource(R.string.automation_use_in_automation_apps_sub), style = GeistType.copy14, color = colors.secondary)
            }
            Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null, tint = colors.secondary)
        }
    }
    Text(
        text = "healthmd export --profile $profileId",
        style = GeistType.label12Mono,
        color = colors.secondary,
        modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2),
    )
}

/** "Daily 7:30", "Sunday 8:00", "Every 3 days at 7:30", "Paused" or "Off". */
@Composable
internal fun scheduleShortLabel(entry: ScheduledProfileEntry?): String {
    val locale = LocalConfiguration.current.locales[0]
    return when (AutomationFacts.scheduleKind(entry)) {
        AutomationScheduleKind.OFF -> stringResource(R.string.automation_value_off)
        AutomationScheduleKind.PAUSED -> stringResource(R.string.automations_paused)
        AutomationScheduleKind.DAILY -> {
            val e = requireNotNull(entry)
            stringResource(R.string.automation_schedule_daily, clockText(e.hour, e.minute))
        }
        AutomationScheduleKind.WEEKLY -> {
            val e = requireNotNull(entry)
            stringResource(
                R.string.automation_schedule_weekly,
                DayOfWeek.of(e.weekdayIso).getDisplayName(TextStyle.FULL, locale),
                clockText(e.hour, e.minute),
            )
        }
        AutomationScheduleKind.CUSTOM -> {
            val e = requireNotNull(entry)
            pluralStringResource(
                when (e.cadenceUnit) {
                    ScheduledProfileCadenceUnit.DAY -> R.plurals.automation_schedule_every_days
                    ScheduledProfileCadenceUnit.WEEK -> R.plurals.automation_schedule_every_weeks
                    ScheduledProfileCadenceUnit.MONTH -> R.plurals.automation_schedule_every_months
                },
                e.cadenceValue,
                e.cadenceValue,
                clockText(e.hour, e.minute),
            )
        }
    }
}

@Composable
private fun RenameDialog(name: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var text by remember { mutableStateOf(name) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.automation_row_name), modifier = Modifier.semantics { heading() }) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                singleLine = true,
                colors = settingsTextFieldColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = { onSave(text.trim()) }, enabled = text.isNotBlank()) {
                Text(stringResource(R.string.a11y_profiles_save))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
