package com.healthmd.presentation.schedule

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import android.text.format.DateFormat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.settings.SettingsFieldRow
import com.healthmd.presentation.settings.SettingsGroupHeading
import com.healthmd.presentation.settings.SettingsSegmentedChoice
import com.healthmd.presentation.settings.SettingsToggleRow
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle

/** The Android scheduling guide's section on background timing and readiness. */
private const val BACKGROUND_TIMING_URL = "https://healthmd.app/docs/android/#background-readiness-and-scheduled-cancellation"

/**
 * An automation's schedule (iOS `GlassScheduleSheet`): a pushed page that saves as it
 * changes, with the same fields and save path as the profile schedule editor, plus the
 * pending-recovery discard. "Include today" is not offered: Android has it planned.
 */
@Composable
fun ProfileSchedulePage(
    profileId: String,
    onBack: () -> Unit,
    showsAccessNote: Boolean,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
    schedulesViewModel: ProfileSchedulesViewModel = hiltViewModel(),
) {
    val uiState by profilesViewModel.uiState.collectAsStateWithLifecycle()
    val schedules by schedulesViewModel.uiState.collectAsStateWithLifecycle()
    val row = uiState.rows.firstOrNull { it.profile.id == profileId }
    if (row == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = LocalGeistColors.current.brandPrimary)
        }
        return
    }
    val initial = remember(profileId) {
        row.entry ?: ProfileScheduleForm.newEntry(
            profileId = profileId,
            hour = uiState.currentSettings.scheduleHour,
            minute = uiState.currentSettings.scheduleMinute,
            today = LocalDate.now(),
            zone = ZoneId.systemDefault(),
        )
    }
    val state = rememberProfileAutosave("$profileId/schedule", initial) { profilesViewModel.saveEntry(it) }
    val draft = state.value
    // Repeat is the user's choice while the page is open, even when a custom count reads as one day.
    var frequency by rememberSaveable(profileId) { mutableStateOf(ProfileScheduleFrequency.of(initial)) }
    val protection = LocalConfigurationProtection.current
    val guarded: (() -> Unit) -> Unit = { action -> if (protection.enabled) protection.onBlockedChange() else action() }
    var confirmDiscard by remember { mutableStateOf(false) }

    SubScreen(title = stringResource(R.string.automation_detail_schedule), onBack = onBack) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space10),
        ) {
            SettingsToggleRow(
                shape = groupRowShape(0, 1),
                title = stringResource(R.string.schedule_run_on_schedule),
                subtitle = stringResource(R.string.schedule_run_on_schedule_sub),
                checked = draft.isEnabled,
                onCheckedChange = { state.value = draft.copy(isEnabled = it) },
                modifier = Modifier.padding(top = GeistSpacing.space2),
            )

            Heading(stringResource(R.string.schedule_when))
            WhenRows(
                draft = draft,
                frequency = frequency,
                onFrequency = { choice ->
                    guarded {
                        frequency = choice
                        state.value = ProfileScheduleForm.withFrequency(draft, choice, LocalDate.now())
                    }
                },
                onChange = { state.value = it },
            )

            Heading(stringResource(R.string.schedule_today))
            TodayRows(draft = draft, onChange = { state.value = it })
            // Today Refresh resends the current day's complete snapshot, so receivers must upsert.
            if (row.profile.target == ExportTarget.API_ENDPOINT) {
                Footnote(stringResource(R.string.schedule_api_refresh_note))
            }

            val liveEntry = row.entry
            if (liveEntry?.pendingExports?.isNotEmpty() == true) {
                PendingRecoveryCard(
                    range = pendingRecoveryRange(liveEntry),
                    discarding = schedules.discardingRecoveryProfileId != null,
                    failed = schedules.recoveryDiscardFailed,
                    onDiscard = { guarded { confirmDiscard = true } },
                )
            }

            val uriHandler = LocalUriHandler.current
            BackgroundTimingRow(onClick = { uriHandler.openUri(BACKGROUND_TIMING_URL) })
            if (showsAccessNote) Footnote(stringResource(R.string.schedule_access_note))
        }
    }

    if (confirmDiscard) {
        ProfileScheduleDiscardRecoveryDialog(
            profileName = row.profile.name,
            onDismiss = { confirmDiscard = false },
            onDiscard = {
                confirmDiscard = false
                guarded { schedulesViewModel.discardPendingRecovery(profileId) }
            },
        )
    }
}

@Composable
private fun WhenRows(
    draft: ScheduledProfileEntry,
    frequency: ProfileScheduleFrequency,
    onFrequency: (ProfileScheduleFrequency) -> Unit,
    onChange: (ScheduledProfileEntry) -> Unit,
) {
    val colors = LocalGeistColors.current
    val locale = LocalConfiguration.current.locales[0]
    val rows = buildList<@Composable (androidx.compose.ui.graphics.Shape) -> Unit> {
        add { shape ->
            SettingsFieldRow(shape = shape) {
                Text(stringResource(R.string.schedule_repeat), style = GeistType.label16, color = colors.primary)
                SettingsSegmentedChoice(
                    options = ProfileScheduleFrequency.entries.toList(),
                    selected = frequency,
                    label = {
                        stringResource(
                            when (it) {
                                ProfileScheduleFrequency.DAILY -> R.string.schedule_daily
                                ProfileScheduleFrequency.WEEKLY -> R.string.schedule_weekly
                                ProfileScheduleFrequency.CUSTOM -> R.string.schedule_custom
                            },
                        )
                    },
                    onSelect = onFrequency,
                )
            }
        }
        if (frequency == ProfileScheduleFrequency.WEEKLY) {
            add { shape ->
                ValueRow(shape, stringResource(R.string.schedule_day)) {
                    MenuValue(
                        title = stringResource(R.string.schedule_day),
                        value = java.time.DayOfWeek.of(draft.weekdayIso).getDisplayName(TextStyle.FULL, locale),
                        options = (1..7).map { it to java.time.DayOfWeek.of(it).getDisplayName(TextStyle.FULL, locale) },
                        onSelect = { onChange(draft.copy(weekdayIso = it)) },
                    )
                }
            }
        }
        if (frequency == ProfileScheduleFrequency.CUSTOM) {
            add { shape ->
                ValueRow(shape, stringResource(R.string.schedule_every)) {
                    CountStepper(
                        title = stringResource(R.string.schedule_every),
                        value = draft.cadenceValue,
                        range = 1..ProfileScheduleForm.MAX_CUSTOM_INTERVAL,
                        valueText = countText(draft.cadenceValue, draft.cadenceUnit),
                        onValue = { onChange(ProfileScheduleForm.withInterval(draft, it)) },
                        units = ScheduledProfileCadenceUnit.entries.map { it to unitLabel(it) },
                        onUnit = { onChange(draft.copy(cadenceUnit = it)) },
                    )
                }
            }
            add { shape ->
                var picking by remember { mutableStateOf(false) }
                ValueRow(shape, stringResource(R.string.schedule_starting), onClick = { picking = true }) {
                    Text(
                        LocalDate.ofEpochDay(draft.anchorEpochDay).format(
                            DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "yMMMd"), locale),
                        ),
                        style = GeistType.label14,
                        color = colors.secondary,
                    )
                }
                if (picking) {
                    StartDateDialog(
                        epochDay = draft.anchorEpochDay,
                        onDismiss = { picking = false },
                        onPick = { day ->
                            picking = false
                            onChange(draft.copy(anchorEpochDay = day))
                        },
                    )
                }
            }
        }
        add { shape ->
            var picking by remember { mutableStateOf(false) }
            ValueRow(shape, stringResource(R.string.schedule_preferred_time), onClick = { picking = true }) {
                Text(clockText(draft.hour, draft.minute), style = GeistType.label14, color = colors.secondary)
            }
            if (picking) {
                PreferredTimeDialog(
                    hour = draft.hour,
                    minute = draft.minute,
                    onDismiss = { picking = false },
                    onPick = { hour, minute ->
                        picking = false
                        onChange(draft.copy(hour = hour, minute = minute))
                    },
                )
            }
        }
        add { shape ->
            ValueRow(shape, stringResource(R.string.schedule_look_back), subtitle = stringResource(R.string.schedule_look_back_sub)) {
                CountStepper(
                    title = stringResource(R.string.schedule_look_back),
                    value = draft.lookbackDays,
                    range = ProfileScheduleForm.MIN_LOOKBACK_DAYS..ProfileScheduleForm.MAX_LOOKBACK_DAYS,
                    valueText = countText(draft.lookbackDays, ScheduledProfileCadenceUnit.DAY),
                    onValue = { onChange(ProfileScheduleForm.withLookback(draft, it)) },
                )
            }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        rows.forEachIndexed { index, content -> content(groupRowShape(index, rows.size)) }
    }
}

@Composable
private fun TodayRows(draft: ScheduledProfileEntry, onChange: (ScheduledProfileEntry) -> Unit) {
    val count = if (draft.todayRefreshEnabled) 2 else 1
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        SettingsToggleRow(
            shape = groupRowShape(0, count),
            title = stringResource(R.string.schedule_refresh_today),
            subtitle = stringResource(R.string.schedule_refresh_today_sub),
            checked = draft.todayRefreshEnabled,
            onCheckedChange = { onChange(draft.copy(todayRefreshEnabled = it)) },
        )
        if (draft.todayRefreshEnabled) {
            SettingsFieldRow(shape = groupRowShape(1, count)) {
                Text(stringResource(R.string.schedule_every), style = GeistType.label16, color = LocalGeistColors.current.primary)
                SettingsSegmentedChoice(
                    options = ScheduledProfileEntry.TODAY_REFRESH_MINUTE_OPTIONS,
                    selected = draft.todayRefreshMinutes,
                    label = { minutes ->
                        if (minutes < 60) {
                            stringResource(R.string.schedule_refresh_every_minutes, minutes)
                        } else {
                            stringResource(R.string.schedule_refresh_every_hours, minutes / 60)
                        }
                    },
                    onSelect = { onChange(draft.withTodayRefreshMinutes(it)) },
                )
            }
        }
    }
}

@Composable
private fun PendingRecoveryCard(range: String?, discarding: Boolean, failed: Boolean, onDiscard: () -> Unit) {
    val colors = LocalGeistColors.current
    Row(
        Modifier
            .padding(top = GeistSpacing.space6)
            .fillMaxWidth()
            .border(1.dp, colors.coverageMissing, RoundedCornerShape(GeistRadii.listGroup))
            .padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(Icons.Outlined.Warning, contentDescription = null, tint = colors.coverageMissing)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            Text(stringResource(R.string.schedule_pending_recovery), style = GeistType.heading16, color = colors.primary)
            Text(
                if (range != null) stringResource(R.string.schedule_pending_recovery_range, range)
                else stringResource(R.string.schedule_pending_recovery_body),
                style = GeistType.copy14,
                color = colors.secondary,
            )
            OutlinedButton(onClick = onDiscard, enabled = !discarding, shape = CircleShape) {
                Text(stringResource(R.string.profile_schedule_discard_recovery), style = GeistType.button14)
            }
            if (failed) {
                Text(stringResource(R.string.profile_schedule_discard_recovery_failed), style = GeistType.copy14, color = colors.error)
            }
        }
    }
}

@Composable
private fun BackgroundTimingRow(onClick: () -> Unit) {
    val colors = LocalGeistColors.current
    Row(
        Modifier
            .padding(top = GeistSpacing.space6)
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.background200)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.schedule_background_timing), style = GeistType.label16, color = colors.primary)
            Text(stringResource(R.string.schedule_background_timing_sub), style = GeistType.copy14, color = colors.secondary)
        }
        Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null, tint = colors.secondary)
    }
}

@Composable
private fun Heading(text: String) {
    SettingsGroupHeading(text)
}

@Composable
private fun Footnote(text: String) {
    Text(
        text,
        style = GeistType.copy14,
        color = LocalGeistColors.current.secondary,
        modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2),
    )
}

/** A list-group row with a title (and subtitle) and a trailing control or value. */
@Composable
private fun ValueRow(
    shape: androidx.compose.ui.graphics.Shape,
    title: String,
    subtitle: String? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable () -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .heightIn(min = if (subtitle != null) 72.dp else 56.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.label16, color = colors.primary)
            subtitle?.let { Text(it, style = GeistType.copy14, color = colors.secondary) }
        }
        trailing()
        if (onClick != null) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.secondary)
        }
    }
}

@Composable
private fun <T> MenuValue(title: String, value: String, options: List<Pair<T, String>>, onSelect: (T) -> Unit) {
    val colors = LocalGeistColors.current
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { open = true }, modifier = Modifier.semantics { contentDescription = "$title, $value" }) {
            Text(value, style = GeistType.label14, color = colors.secondary)
            Icon(Icons.Outlined.ArrowDropDown, contentDescription = null, tint = colors.secondary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (option, label) ->
                DropdownMenuItem(text = { Text(label) }, onClick = {
                    open = false
                    onSelect(option)
                })
            }
        }
    }
}

/**
 * "− 3 days +" (iOS `GlassCountStepper`). With [units], the value in the middle also opens a
 * menu of units, so the unit stays inline.
 */
@Composable
private fun CountStepper(
    title: String,
    value: Int,
    range: IntRange,
    valueText: String,
    onValue: (Int) -> Unit,
    units: List<Pair<ScheduledProfileCadenceUnit, String>> = emptyList(),
    onUnit: (ScheduledProfileCadenceUnit) -> Unit = {},
) {
    val colors = LocalGeistColors.current
    var open by remember { mutableStateOf(false) }
    Row(
        Modifier
            .border(BorderStroke(1.dp, colors.gray.c500), CircleShape)
            .semantics { stateDescription = valueText },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = { onValue(value - 1) }, enabled = value - 1 in range) {
            Icon(Icons.Outlined.Remove, contentDescription = stringResource(R.string.schedule_decrease, title))
        }
        Box {
            Text(
                valueText,
                style = GeistType.button14,
                color = colors.primary,
                modifier = Modifier
                    .widthIn(min = 56.dp)
                    .then(
                        if (units.isNotEmpty()) {
                            Modifier.clickable(role = Role.DropdownList) { open = true }
                        } else {
                            Modifier
                        },
                    )
                    .padding(vertical = GeistSpacing.space2),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            if (units.isNotEmpty()) {
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    units.forEach { (unit, label) ->
                        DropdownMenuItem(text = { Text(label) }, onClick = {
                            open = false
                            onUnit(unit)
                        })
                    }
                }
            }
        }
        IconButton(onClick = { onValue(value + 1) }, enabled = value + 1 in range) {
            Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.schedule_increase, title))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PreferredTimeDialog(hour: Int, minute: Int, onDismiss: () -> Unit, onPick: (Int, Int) -> Unit) {
    val context = LocalContext.current
    val picker = rememberTimePickerState(initialHour = hour, initialMinute = minute, is24Hour = DateFormat.is24HourFormat(context))
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.schedule_preferred_time)) },
        text = { TimePicker(state = picker) },
        confirmButton = { TextButton(onClick = { onPick(picker.hour, picker.minute) }) { Text(stringResource(R.string.composer_done)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StartDateDialog(epochDay: Long, onDismiss: () -> Unit, onPick: (Long) -> Unit) {
    val picker = rememberDatePickerState(initialSelectedDateMillis = epochDay * MILLIS_PER_DAY)
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val millis = picker.selectedDateMillis
                if (millis == null) onDismiss() else onPick(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate().toEpochDay())
            }) { Text(stringResource(R.string.composer_done)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    ) { DatePicker(state = picker) }
}

private const val MILLIS_PER_DAY = 86_400_000L

@Composable
private fun countText(count: Int, unit: ScheduledProfileCadenceUnit): String = pluralStringResource(
    when (unit) {
        ScheduledProfileCadenceUnit.DAY -> R.plurals.schedule_count_days
        ScheduledProfileCadenceUnit.WEEK -> R.plurals.schedule_count_weeks
        ScheduledProfileCadenceUnit.MONTH -> R.plurals.schedule_count_months
    },
    count,
    count,
)

@Composable
private fun unitLabel(unit: ScheduledProfileCadenceUnit): String = stringResource(
    when (unit) {
        ScheduledProfileCadenceUnit.DAY -> R.string.a11y_profiles_days
        ScheduledProfileCadenceUnit.WEEK -> R.string.a11y_profiles_weeks
        ScheduledProfileCadenceUnit.MONTH -> R.string.a11y_profiles_months
    },
)

/** The preferred time in the user's clock format. */
@Composable
internal fun clockText(hour: Int, minute: Int): String {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val pattern = DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm")
    return LocalTime.of(hour, minute).format(DateTimeFormatter.ofPattern(pattern, locale))
}

/** "Oct 19" or "Oct 19 – Oct 20": the days a pending recovery still holds; null when unknown. */
@Composable
private fun pendingRecoveryRange(entry: ScheduledProfileEntry): String? {
    val (first, last) = AutomationFacts.pendingRecoveryDays(entry) ?: return null
    val locale = LocalConfiguration.current.locales[0]
    val sameYear = first.year == LocalDate.now().year && last.year == LocalDate.now().year
    val formatter = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, if (sameYear) "MMMd" else "yMMMd"), locale)
    return if (first == last) first.format(formatter) else "${first.format(formatter)} – ${last.format(formatter)}"
}
