package com.healthmd.presentation.schedule

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.clickable
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Phase-6 profile-schedules section on the Schedule screen: one row per export profile with an
 * enable toggle, a cadence editor dialog, profile creation from current settings, and a usage
 * footer. Pure QA/manage surface — execution lives in the scheduler runtime.
 */
@Composable
fun ProfileSchedulesSection(
    viewModel: ProfileSchedulesViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = AppColors.bgSecondary),
    ) {
        Column(
            modifier = Modifier.padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Text(
                text = "Profile Schedules",
                style = MaterialTheme.typography.titleMedium,
                color = AppColors.textPrimary,
            )
            Text(
                text = "Run each export profile on its own cadence. Profiles keep working when this screen is closed.",
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )

            Spacer(modifier = Modifier.height(Spacing.xs))

            var pendingDelete by remember { mutableStateOf<ProfileScheduleRow?>(null) }
            uiState.rows.forEach { row ->
                ProfileScheduleRow(
                    row = row,
                    onToggle = { enabled -> viewModel.setEnabled(row.profile.id, enabled) },
                    onOpenEditor = { viewModel.openEditor(row.profile.id) },
                    onDelete = { pendingDelete = row },
                )
            }
            pendingDelete?.let { row ->
                AlertDialog(
                    onDismissRequest = { pendingDelete = null },
                    title = { Text("Delete \"${row.profile.name}\"?") },
                    text = {
                        Text("Its saved settings and schedule are removed. The last remaining profile cannot be deleted.")
                    },
                    confirmButton = {
                        TextButton(onClick = {
                            viewModel.deleteProfile(row.profile.id)
                            pendingDelete = null
                        }) { Text("Delete") }
                    },
                    dismissButton = {
                        TextButton(onClick = { pendingDelete = null }) { Text("Cancel") }
                    },
                )
            }

            if (uiState.rows.isEmpty()) {
                Text(
                    text = "No export profiles yet.",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
            }

            TextButton(onClick = viewModel::addProfileFromCurrentSettings) {
                Text("New Profile From Current Settings")
            }

            Text(
                text = if (uiState.projectedMonthlyRequests > 0) {
                    "Projected use: about ${uiState.projectedMonthlyRequests} export actions per month across scheduled profiles."
                } else {
                    "No profile schedules enabled."
                },
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )
        }
    }

    uiState.editingProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        ProfileCadenceEditorDialog(
            profileId = row.profile.id,
            profileName = row.profile.name,
            entry = row.entry,
            onSave = viewModel::saveEntry,
            onDismiss = { viewModel.openEditor(null) },
        )
    }
}

@Composable
private fun ProfileScheduleRow(
    row: ProfileScheduleRow,
    onToggle: (Boolean) -> Unit,
    onOpenEditor: () -> Unit,
    onDelete: () -> Unit,
) {
    val entry = row.entry
    val enabled = entry?.isEnabled == true
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenEditor),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = row.profile.name,
                style = MaterialTheme.typography.bodyLarge,
                color = AppColors.textPrimary,
            )
            Text(
                text = cadenceSummary(entry),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )
        }
        TextButton(onClick = onDelete) { Text("Delete") }
        Switch(checked = enabled, onCheckedChange = onToggle)
    }
}

internal fun cadenceSummary(entry: ScheduledProfileEntry?): String {
    if (entry == null || !entry.isEnabled) return "Not scheduled. Tap to configure."
    val time = LocalTime.of(entry.hour, entry.minute)
        .format(DateTimeFormatter.ofPattern("HH:mm", Locale.getDefault()))
    return when (entry.cadenceUnit) {
        ScheduledProfileCadenceUnit.DAY -> "Every ${entry.cadenceValue} day(s) at $time"
        ScheduledProfileCadenceUnit.WEEK -> {
            val weekday = java.time.DayOfWeek.of(entry.weekdayIso).name.lowercase().replaceFirstChar { it.uppercase() }
            "Every ${entry.cadenceValue} week(s) on $weekday at $time"
        }
        ScheduledProfileCadenceUnit.MONTH -> "Every ${entry.cadenceValue} month(s) at $time"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProfileCadenceEditorDialog(
    profileId: String,
    profileName: String,
    entry: ScheduledProfileEntry?,
    onSave: (ScheduledProfileEntry) -> Unit,
    onDismiss: () -> Unit,
) {
    var draft by remember(entry, profileId) {
        mutableStateOf(
            entry ?: ScheduledProfileEntry(
                profileId = profileId,
                isEnabled = true,
                anchorEpochDay = java.time.LocalDate.now().toEpochDay(),
                zoneId = java.time.ZoneId.systemDefault().id,
            ),
        )
    }
    var cadenceMenuOpen by remember { mutableStateOf(false) }
    var weekdayMenuOpen by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(profileName) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Enabled", modifier = Modifier.weight(1f))
                    Switch(checked = draft.isEnabled, onCheckedChange = { draft = draft.copy(isEnabled = it) })
                }

                ExposedDropdownMenuBox(
                    expanded = cadenceMenuOpen,
                    onExpandedChange = { cadenceMenuOpen = it },
                ) {
                    OutlinedTextField(
                        value = when (draft.cadenceUnit) {
                            ScheduledProfileCadenceUnit.DAY -> "Days"
                            ScheduledProfileCadenceUnit.WEEK -> "Weeks"
                            ScheduledProfileCadenceUnit.MONTH -> "Months"
                        },
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Cadence unit") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = cadenceMenuOpen) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(expanded = cadenceMenuOpen, onDismissRequest = { cadenceMenuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Days") },
                            onClick = {
                                draft = draft.copy(cadenceUnit = ScheduledProfileCadenceUnit.DAY)
                                cadenceMenuOpen = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Weeks") },
                            onClick = {
                                draft = draft.copy(cadenceUnit = ScheduledProfileCadenceUnit.WEEK)
                                cadenceMenuOpen = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Months") },
                            onClick = {
                                draft = draft.copy(cadenceUnit = ScheduledProfileCadenceUnit.MONTH)
                                cadenceMenuOpen = false
                            },
                        )
                    }
                }

                if (draft.cadenceUnit == ScheduledProfileCadenceUnit.WEEK) {
                    ExposedDropdownMenuBox(
                        expanded = weekdayMenuOpen,
                        onExpandedChange = { weekdayMenuOpen = it },
                    ) {
                        OutlinedTextField(
                            value = java.time.DayOfWeek.of(draft.weekdayIso).name.lowercase()
                                .replaceFirstChar { it.uppercase() },
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Weekday") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = weekdayMenuOpen) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .menuAnchor(),
                        )
                        ExposedDropdownMenu(expanded = weekdayMenuOpen, onDismissRequest = { weekdayMenuOpen = false }) {
                            (1..7).forEach { iso ->
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            java.time.DayOfWeek.of(iso).name.lowercase()
                                                .replaceFirstChar { it.uppercase() },
                                        )
                                    },
                                    onClick = {
                                        draft = draft.copy(weekdayIso = iso)
                                        weekdayMenuOpen = false
                                    },
                                )
                            }
                        }
                    }
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    NumberField(
                        label = "Hour",
                        value = draft.hour,
                        onValue = { draft = draft.copy(hour = it.coerceIn(0, 23)) },
                    )
                    NumberField(
                        label = "Minute",
                        value = draft.minute,
                        onValue = { draft = draft.copy(minute = it.coerceIn(0, 59)) },
                    )
                }

                NumberField(
                    label = "Lookback days (1-30)",
                    value = draft.lookbackDays,
                    onValue = { draft = draft.copy(lookbackDays = it.coerceIn(1, 30)) },
                )
                NumberField(
                    label = "Every N ${draft.cadenceUnit.name.lowercase()}s",
                    value = draft.cadenceValue,
                    onValue = { draft = draft.copy(cadenceValue = it.coerceAtLeast(1)) },
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(draft) },
                enabled = draft.profileId.isNotBlank(),
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

@Composable
private fun NumberField(
    label: String,
    value: Int,
    onValue: (Int) -> Unit,
) {
    // Local text state keyed by label (stable across recompositions): typing is never fought by
    // live clamping, and the field resynchronizes only when the external value changes to
    // something other than what the user last typed. Empty/invalid input keeps the prior value.
    var text by rememberSaveable(label, value) { mutableStateOf(value.toString()) }
    var lastCommitted by rememberSaveable(label) { mutableStateOf(value) }
    if (value != lastCommitted && text.toIntOrNull() != value) {
        text = value.toString()
        lastCommitted = value
    }
    OutlinedTextField(
        value = text,
        onValueChange = { raw ->
            text = raw
            raw.toIntOrNull()?.let { typed ->
                val clamped = typed.coerceAtLeast(0)
                if (clamped != lastCommitted) {
                    lastCommitted = clamped
                    onValue(clamped)
                }
            }
        },
        label = { Text(label) },
        modifier = Modifier.width(132.dp),
        singleLine = true,
    )
}
