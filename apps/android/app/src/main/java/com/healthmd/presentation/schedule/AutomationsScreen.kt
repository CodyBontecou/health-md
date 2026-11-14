package com.healthmd.presentation.schedule

import androidx.compose.runtime.getValue
import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileOccurrenceMath
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.archive.CoverageStatus
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.common.LocalAppFolderName
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.LocalFloatingActionClearance
import com.healthmd.presentation.export.ExportProfileEditorDialog
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.schedule.composer.automationSummary
import com.healthmd.presentation.theme.GeistColors
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

internal object AutomationsTags {
    const val CARD = "automations.card"
    const val SWITCH = "automations.card.switch"
    const val STRIP = "automations.card.strip"
    const val NEW = "automations.new"
    const val HISTORY = "automations.history"
}

/**
 * Automations (iOS `AutomationsScreen`): one card per automation (an export profile and its
 * schedule) with its name, on/off switch, the automation as a sentence, its last 14 completed
 * days and its next run. A card opens the automation's detail, which holds Run now, its
 * settings, schedule and Delete. "+" creates an automation in the profile editor. The
 * app-wide schedule settings live in Settings.
 */
@Composable
fun AutomationsScreen(
    /** Opens the automation's detail (a pane beside the list on wide layouts). */
    onOpenAutomation: (String) -> Unit,
    onNavigateToPaywall: () -> Unit,
    /** Opens export history; on iOS it lives under Automations, not the Archive. */
    onOpenHistory: () -> Unit = {},
    modifier: Modifier = Modifier,
    selectedAutomationId: String? = null,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
    schedulesViewModel: ProfileSchedulesViewModel = hiltViewModel(),
    scheduleViewModel: ScheduleViewModel = hiltViewModel(),
    recentViewModel: AutomationRecentViewModel = hiltViewModel(),
) {
    val protection = LocalConfigurationProtection.current
    val state by profilesViewModel.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(state.detailProfileId) {
        state.detailProfileId?.let { id ->
            profilesViewModel.openDetail(null)
            onOpenAutomation(id)
        }
    }
    val schedules by schedulesViewModel.uiState.collectAsStateWithLifecycle()
    val schedule by scheduleViewModel.uiState.collectAsStateWithLifecycle()
    val recent by recentViewModel.recentDays.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    val guarded: (() -> Unit) -> Unit = { action ->
        if (protection.enabled) protection.onBlockedChange() else action()
    }
    LaunchedEffect(schedule.requiresUpgrade) {
        if (schedule.requiresUpgrade) {
            scheduleViewModel.consumeUpgradeRequest()
            onNavigateToPaywall()
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(R.string.nav_automations),
                style = MaterialTheme.typography.headlineMedium,
                color = colors.primary,
                modifier = Modifier.weight(1f).padding(horizontal = GeistSpacing.space1).semantics { heading() },
            )
            FilledTonalIconButton(
                onClick = { guarded(profilesViewModel::startCreation) },
                colors = IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = colors.secondaryContainer,
                    contentColor = colors.onSecondaryContainer,
                ),
                modifier = Modifier.size(GeistSizes.minimumTouchTarget).testTag(AutomationsTags.NEW),
            ) {
                Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.automations_new))
            }
        }
        Text(
            text = stringResource(R.string.automations_subtitle),
            style = GeistType.copy14,
            color = colors.secondary,
            modifier = Modifier.padding(start = GeistSpacing.space1, end = GeistSpacing.space1, bottom = GeistSpacing.space1),
        )

        if (state.rows.isEmpty()) {
            Text(
                stringResource(R.string.a11y_profiles_empty),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space1),
            )
        }
        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                state.rows.forEach { row ->
                    val settings = remember(row.profile.updatedAtEpochMillis, state.currentSettings) {
                        ExportProfilesViewModel.initialEditDraft(row.profile, state.currentSettings).settings
                    }
                    AutomationCard(
                        profile = row.profile,
                        entry = row.entry,
                        settings = settings,
                        recentDays = recent[row.profile.id].orEmpty(),
                        selected = row.profile.id == selectedAutomationId,
                        hasScheduleAccess = schedule.isPurchased || schedule.clinicDestinationAuthorized,
                        onTryFree = onNavigateToPaywall,
                        onToggle = { enabled -> guarded { schedulesViewModel.setEnabled(row.profile.id, enabled) } },
                        onOpen = { onOpenAutomation(row.profile.id) },
                    )
                }
            }
        }
        if (schedules.recoveryDiscardFailed) {
            Text(
                stringResource(R.string.profile_schedule_discard_recovery_failed),
                style = MaterialTheme.typography.bodySmall,
                color = colors.error,
            )
        }

        Spacer(Modifier.height(GeistSpacing.space1))
        GeistCardClickable(onClick = onOpenHistory, modifier = Modifier.testTag(AutomationsTags.HISTORY)) {
            Text(
                stringResource(R.string.nav_history),
                style = GeistType.label16,
                color = colors.primary,
                modifier = Modifier.weight(1f),
            )
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.secondary)
        }

        // Clears the floating Export now action on compact layouts; zero beside the rail.
        val clearance = LocalFloatingActionClearance.current - GeistSpacing.space4 - GeistSpacing.space3
        if (clearance > 0.dp) Spacer(Modifier.height(clearance))
    }

    if (state.creatingProfile) {
        ExportProfileEditorDialog(
            isCreation = true,
            initial = remember { ExportProfilesViewModel.initialCreationDraft(state.rows, state.currentSettings) },
            overlapPreview = { target, folderUri, settings ->
                profilesViewModel.draftOverlapPreview(null, target, folderUri, settings)
            },
            onConfirm = { draft -> guarded { profilesViewModel.createProfile(draft) } },
            onDismiss = profilesViewModel::dismissCreation,
            title = stringResource(R.string.automations_new),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AutomationCard(
    profile: ExportProfile,
    entry: ScheduledProfileEntry?,
    settings: ExportSettings,
    recentDays: List<CoverageStatus>,
    selected: Boolean,
    hasScheduleAccess: Boolean,
    onTryFree: () -> Unit,
    onToggle: (Boolean) -> Unit,
    onOpen: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val name = profile.name
    val shape = RoundedCornerShape(GeistRadii.large)
    val detailsLabel = stringResource(R.string.automation_detail_details_named, name)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(AutomationsTags.CARD)
            .clip(shape)
            .background(colors.background200)
            // The automation open beside the list: the brand focus outline, not a fill.
            .then(if (selected) Modifier.border(2.dp, colors.brandPrimary, shape) else Modifier)
            .then(if (selected) Modifier.semantics { this.selected = true } else Modifier)
            .clickable(role = Role.Button, onClickLabel = detailsLabel, onClick = onOpen)
            .padding(horizontal = GeistSpacing.space6 - GeistSpacing.space1, vertical = GeistSpacing.space4 + 2.dp),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
            Text(
                name,
                style = GeistType.heading16.copy(fontWeight = FontWeight.Bold),
                color = colors.primary,
                modifier = Modifier.weight(1f),
            )
            if (!hasScheduleAccess) {
                // Without paid access the automation only runs on demand: never a live switch.
                Text(
                    stringResource(R.string.automations_manual),
                    style = GeistType.label12,
                    color = colors.secondary,
                    modifier = Modifier
                        .background(colors.gray.c300, RoundedCornerShape(GeistRadii.small))
                        .padding(horizontal = GeistSpacing.space3 - 2.dp, vertical = GeistSpacing.space1 + 2.dp),
                )
            } else if (entry != null) {
                val switchLabel = stringResource(R.string.automations_switch_named, name)
                AppSwitch(
                    checked = entry.isEnabled,
                    onCheckedChange = onToggle,
                    modifier = Modifier.testTag(AutomationsTags.SWITCH).semantics { contentDescription = switchLabel },
                )
            }
        }
        val destination = AutomationSentence.destination(profile, LocalAppFolderName.current)
            ?: stringResource(
                // An API automation whose saved endpoint was deleted sends nowhere until rebound.
                if (profile.target == ExportTarget.API_ENDPOINT) R.string.endpoint_not_configured
                else R.string.automation_destination_selected_folder,
            )
        if (!hasScheduleAccess) {
            val metrics = settings.metricSelection.enabledCount
            Text(
                text = pluralStringResource(R.plurals.automations_writes_metrics, metrics, metrics, destination),
                style = GeistType.copy16,
                color = colors.secondary,
            )
        } else Text(
            text = automationSummary(
                settings = settings,
                entry = entry,
                destination = destination,
                sends = profile.target != ExportTarget.DEVICE_FOLDER,
                tokenStyle = SpanStyle(color = colors.brandPrimary, fontWeight = FontWeight.Medium),
            ),
            style = GeistType.copy16,
            color = colors.secondary,
        )
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            if (recentDays.isNotEmpty()) {
                AutomationRecentStrip(recentDays, Modifier.align(Alignment.CenterVertically))
            }
            Text(
                // "Next · …" only appears when the schedule can actually run.
                if (hasScheduleAccess) nextRunLabel(entry) else stringResource(R.string.automations_manual),
                style = GeistType.label12,
                color = colors.secondary,
                modifier = Modifier.align(Alignment.CenterVertically).padding(start = GeistSpacing.space2),
            )
        }
        if (!hasScheduleAccess) {
            ScheduleOffNotice(hour = entry?.hour ?: 8, minute = entry?.minute ?: 0, onTryFree = onTryFree)
        }
    }
}

/** A6: the schedule needs a subscription; it never shows a next run without access. */
@Composable
private fun ScheduleOffNotice(hour: Int, minute: Int, onTryFree: () -> Unit) {
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val time = java.time.LocalTime.of(hour.coerceIn(0, 23), minute.coerceIn(0, 59)).format(
        DateTimeFormatter.ofPattern(
            DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm"),
            locale,
        ),
    )
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.amber.c100, RoundedCornerShape(GeistRadii.medium))
            .padding(start = GeistSpacing.space3, top = GeistSpacing.space3, bottom = GeistSpacing.space3, end = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Box(
            Modifier.size(34.dp).background(colors.amber.c300, RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.Schedule, contentDescription = null, tint = colors.amber.c900, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.automations_daily_off, time), style = GeistType.label14, color = colors.amber.c1000)
            Text(stringResource(R.string.automations_needs_subscription), style = GeistType.copy13, color = colors.amber.c900)
        }
        Button(
            onClick = onTryFree,
            shape = RoundedCornerShape(GeistRadii.full),
            colors = ButtonDefaults.buttonColors(containerColor = colors.primary, contentColor = colors.background100),
            contentPadding = PaddingValues(horizontal = GeistSpacing.space4),
            modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
        ) {
            Text(stringResource(R.string.automations_try_free), style = GeistType.button14)
        }
    }
}

/** The last 14 completed days of one automation as small tiles, in the Archive's colours. */
@Composable
internal fun AutomationRecentStrip(days: List<CoverageStatus>, modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    Row(
        modifier.testTag(AutomationsTags.STRIP).clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        days.forEach { status ->
            val tile = RoundedCornerShape(3.dp)
            val base = Modifier.size(11.dp)
            Box(
                when (status) {
                    CoverageStatus.COMPLETE -> base.background(colors.coverageComplete, tile)
                    CoverageStatus.PARTIAL, CoverageStatus.IN_PROGRESS -> base.background(colors.brandPrimary, tile)
                    CoverageStatus.MISSING -> base.drawBehind {
                        val stroke = 1.dp.toPx()
                        drawRoundRect(
                            color = colors.coverageMissing,
                            topLeft = Offset(stroke / 2, stroke / 2),
                            size = Size(size.width - stroke, size.height - stroke),
                            cornerRadius = CornerRadius(3.dp.toPx()),
                            style = Stroke(width = stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 2.dp.toPx()))),
                        )
                    }
                    CoverageStatus.NOT_DUE -> base.background(colors.gray.c300, tile)
                },
            )
        }
    }
}

/** "Next · Sun 7:30 AM", "Paused" for a switched-off schedule, or "No schedule" without one. */
@Composable
private fun nextRunLabel(entry: ScheduledProfileEntry?): String {
    if (entry == null) return stringResource(R.string.automations_no_schedule)
    if (!entry.isEnabled) return stringResource(R.string.automations_paused)
    val next = ScheduledProfileOccurrenceMath.nextOccurrence(entry, System.currentTimeMillis())
        ?: return stringResource(R.string.automations_paused)
    return stringResource(R.string.automations_next, formatNextRun(next))
}

@Composable
private fun formatNextRun(instant: Instant): String {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val zone = ZoneId.systemDefault()
    val at = instant.atZone(zone)
    val today = LocalDate.now(zone)
    val hours = if (DateFormat.is24HourFormat(context)) "Hm" else "hm"
    val skeleton = when {
        at.toLocalDate() == today -> hours
        at.toLocalDate().isBefore(today.plusDays(7)) -> "EEE$hours"
        else -> "MMMd$hours"
    }
    return at.format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale))
}

/** Automation identity colours, in profile order; the same ramp the Archive lanes use. */
internal fun automationColor(colors: GeistColors, index: Int): Color = when (index % 4) {
    0 -> colors.brandPrimary
    1 -> colors.blue.c900
    2 -> colors.teal.c900
    else -> colors.amber.c900
}

@Composable
private fun AutomationsNotice(title: String, body: String, action: String, onAction: () -> Unit) {
    val colors = LocalGeistColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.gray.c300, RoundedCornerShape(GeistRadii.listGroup))
            .padding(start = GeistSpacing.space4, top = GeistSpacing.space3, end = GeistSpacing.space2, bottom = GeistSpacing.space1),
    ) {
        Text(title, style = GeistType.heading14, color = colors.primary)
        Text(body, style = GeistType.copy14, color = colors.secondary, modifier = Modifier.padding(end = GeistSpacing.space2))
        TextButton(onClick = onAction, modifier = Modifier.align(Alignment.End)) {
            Text(action, style = GeistType.button14, color = colors.brandPrimary)
        }
    }
}
