package com.healthmd.presentation.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.LocalAppFolderName
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.export.ExportProfileRow
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** Stable display labels matching the platform-neutral format identities. */
private val FormatLabels = mapOf(
    "MARKDOWN" to "Markdown",
    "OBSIDIAN_BASES" to "Obsidian Bases",
    "JSON" to "JSON",
    "CSV" to "CSV",
)

/**
 * The automation detail hub: the sentence, its settings, and the profile ID that
 * automations and the CLI reference. Edits route to the existing editors.
 */
@Composable
fun AutomationDetailPane(
    profileId: String?,
    onEditProfile: (String) -> Unit,
    modifier: Modifier = Modifier,
    /** Opens the sentence composer for this automation. */
    onCompose: ((String) -> Unit)? = null,
    /** Runs the automation now (makes it active and opens Export now on it). */
    onRunNow: ((String) -> Unit)? = null,
    /** Called once the automation is deleted, so a phone screen can close. */
    onDeleted: (() -> Unit)? = null,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
    schedulesViewModel: ProfileSchedulesViewModel = hiltViewModel(),
) {
    val profiles by profilesViewModel.uiState.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    if (profileId == null) {
        Text(
            text = stringResource(R.string.automation_detail_select),
            style = MaterialTheme.typography.bodyLarge,
            color = colors.secondary,
            modifier = modifier.padding(GeistSpacing.space6),
        )
        return
    }
    val row = profiles.rows.firstOrNull { it.profile.id == profileId }
    if (row == null) {
        Text(
            text = stringResource(R.string.automation_detail_not_found),
            style = MaterialTheme.typography.bodyLarge,
            color = colors.secondary,
            modifier = modifier.padding(GeistSpacing.space6),
        )
        return
    }
    var editingSchedule by remember(profileId) { mutableStateOf(false) }
    var confirmDelete by remember(profileId) { mutableStateOf(false) }
    var confirmDiscard by remember(profileId) { mutableStateOf(false) }
    val schedules by schedulesViewModel.uiState.collectAsStateWithLifecycle()
    val protection = LocalConfigurationProtection.current
    val guarded: (() -> Unit) -> Unit = { action -> if (protection.enabled) protection.onBlockedChange() else action() }

    AutomationDetailContent(
        row = row,
        onEditProfile = { onEditProfile(row.profile.id) },
        onEditSchedule = { guarded { editingSchedule = true } },
        onMakeActive = { guarded { profilesViewModel.activate(row.profile.id) } },
        onCompose = onCompose?.let { open -> { open(row.profile.id) } },
        onRunNow = onRunNow?.let { run -> { run(row.profile.id) } },
        onToggleSchedule = { enabled -> guarded { schedulesViewModel.setEnabled(row.profile.id, enabled) } },
        onDelete = { guarded { confirmDelete = true } },
        onDiscardRecovery = { guarded { confirmDiscard = true } },
        discardEnabled = schedules.discardingRecoveryProfileId == null,
        modifier = modifier,
    )

    // Dialogs are separate windows outside the protected region: re-check the lock on confirm.
    if (confirmDelete) {
        ProfileScheduleDeleteDialog(
            profileName = row.profile.name,
            onDismiss = { confirmDelete = false },
            onDelete = {
                confirmDelete = false
                guarded {
                    schedulesViewModel.deleteProfile(row.profile.id)
                    onDeleted?.invoke()
                }
            },
        )
    }
    if (confirmDiscard) {
        ProfileScheduleDiscardRecoveryDialog(
            profileName = row.profile.name,
            onDismiss = { confirmDiscard = false },
            onDiscard = {
                confirmDiscard = false
                guarded { schedulesViewModel.discardPendingRecovery(row.profile.id) }
            },
        )
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
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AutomationDetailContent(
    row: ExportProfileRow,
    onEditProfile: () -> Unit,
    onEditSchedule: () -> Unit,
    onMakeActive: () -> Unit,
    onCompose: (() -> Unit)?,
    onRunNow: (() -> Unit)?,
    onToggleSchedule: (Boolean) -> Unit,
    onDelete: () -> Unit,
    onDiscardRecovery: () -> Unit,
    discardEnabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val clipboard = LocalClipboardManager.current
    var copied by remember(row.profile.id) { mutableStateOf(false) }
    val profile = row.profile
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            Text(profile.name, style = MaterialTheme.typography.headlineSmall, color = colors.primary, modifier = Modifier.weight(1f, fill = false))
            if (row.isActive) {
                Text(
                    text = stringResource(R.string.automation_detail_active),
                    style = GeistType.label12,
                    color = colors.onSecondaryContainer,
                    modifier = Modifier
                        .background(colors.secondaryContainer, RoundedCornerShape(GeistRadii.small))
                        .padding(horizontal = GeistSpacing.space2, vertical = GeistSpacing.space1),
                )
            }
        }
        Text(automationSentence(profile, row.entry), style = GeistType.copy18, color = colors.primary)
        // The automation's own on/off switch: one whole-row target, as on the Automations card.
        ProfileScheduleToggle(
            label = stringResource(R.string.enabled),
            checked = row.entry?.isEnabled == true,
            onCheckedChange = onToggleSchedule,
            description = stringResource(R.string.a11y_profiles_schedule_named, profile.name),
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            if (onRunNow != null) {
                FilledTonalButton(
                    onClick = onRunNow,
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = colors.secondaryContainer,
                        contentColor = colors.onSecondaryContainer,
                    ),
                ) { Text(stringResource(R.string.automations_run_now), style = GeistType.button14) }
            }
            if (!row.isActive) {
                Button(
                    onClick = onMakeActive,
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
                ) { Text(stringResource(R.string.automation_detail_make_active), style = GeistType.button14) }
            }
            if (onCompose != null) {
                OutlinedButton(onClick = onCompose, shape = RoundedCornerShape(GeistRadii.full)) {
                    Text(stringResource(R.string.composer_edit_sentence), style = GeistType.button14, color = colors.brandPrimary)
                }
            }
            OutlinedButton(onClick = onEditSchedule, shape = RoundedCornerShape(GeistRadii.full)) {
                Text(stringResource(R.string.automation_detail_edit_schedule), style = GeistType.button14, color = colors.brandPrimary)
            }
            OutlinedButton(onClick = onEditProfile, shape = RoundedCornerShape(GeistRadii.full)) {
                Text(stringResource(R.string.automation_detail_edit_profile), style = GeistType.button14, color = colors.brandPrimary)
            }
            TextButton(
                onClick = onDelete,
                modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
            ) {
                Text(stringResource(R.string.a11y_profiles_delete), style = GeistType.button14, color = colors.error)
            }
        }
        if (row.entry?.pendingExports?.isNotEmpty() == true) {
            TextButton(
                onClick = onDiscardRecovery,
                enabled = discardEnabled,
                modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
            ) {
                Text(
                    stringResource(R.string.profile_schedule_discard_recovery),
                    style = GeistType.button14,
                    color = if (discardEnabled) colors.error else colors.disabled,
                )
            }
        }

        SectionLabel(stringResource(R.string.nav_settings), modifier = Modifier.padding(top = GeistSpacing.space3))
        GeistCard(padding = GeistSpacing.space4) {
            val snapshot = row.snapshot
            FactRow(
                stringResource(R.string.automation_detail_destination),
                AutomationSentence.destination(profile, LocalAppFolderName.current)
                    ?: stringResource(R.string.automation_destination_selected_folder),
            )
            FactRow(
                stringResource(R.string.automation_detail_formats),
                snapshot?.exportFormats?.mapNotNull { FormatLabels[it] ?: it.takeIf(String::isNotBlank) }
                    ?.joinToString(" · ")?.ifBlank { null } ?: "—",
            )
            FactRow(stringResource(R.string.automation_detail_metrics), snapshot?.enabledMetricCount?.toString() ?: "—")
            FactRow(stringResource(R.string.automation_detail_schedule), automationSentence(profile, row.entry))
        }

        SectionLabel(stringResource(R.string.automation_detail_cli), modifier = Modifier.padding(top = GeistSpacing.space3))
        GeistCard(padding = GeistSpacing.space4) {
            Text(stringResource(R.string.automation_detail_profile_id), style = GeistType.label12, color = colors.secondary)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(profile.id, style = GeistType.label14Mono, color = colors.primary, modifier = Modifier.weight(1f))
                TextButton(
                    onClick = {
                        clipboard.setText(AnnotatedString(profile.id))
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
            Spacer(Modifier.height(GeistSpacing.space2))
            Text(
                text = "healthmd export --profile ${profile.id}",
                style = GeistType.label13Mono,
                color = colors.primary,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.gray.c200, RoundedCornerShape(GeistRadii.medium))
                    .padding(GeistSpacing.space3),
            )
        }
    }
}

@Composable
private fun FactRow(title: String, value: String) {
    val colors = LocalGeistColors.current
    Column(Modifier.fillMaxWidth().padding(vertical = GeistSpacing.space2)) {
        Text(title, style = GeistType.label12, color = colors.secondary)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = colors.primary)
    }
}
