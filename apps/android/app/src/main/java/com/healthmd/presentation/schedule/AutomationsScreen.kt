package com.healthmd.presentation.schedule

import android.text.format.DateFormat
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileOccurrenceMath
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.LocalFloatingActionClearance
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
    const val RUN_NOW = "automations.card.runNow"
    const val EDIT = "automations.card.edit"
    const val DETAILS = "automations.card.details"
    const val NEW = "automations.new"
    const val SCHEDULE_SETTINGS = "automations.scheduleSettings"
}

/**
 * Automations as on the board: one card per automation (an export profile and its schedule)
 * with its colour, next run, an on/off switch, the automation as a sentence, and Run now / Edit.
 * Delete, schedule editing, the profile editor and pending-recovery cleanup live in the
 * automation's detail; the app-wide schedule, scheduled target and history sit under
 * Schedule settings.
 */
@Composable
fun AutomationsScreen(
    /** Opens the automation's detail (a pane beside the list on wide layouts). */
    onOpenAutomation: (String) -> Unit,
    /** Opens the sentence composer, the board's Edit. */
    onEditAutomation: (String) -> Unit,
    /** Runs the automation now: makes it active and opens Export now on it. */
    onRunNow: (String) -> Unit,
    onOpenScheduleSettings: () -> Unit,
    onNavigateToPaywall: () -> Unit,
    modifier: Modifier = Modifier,
    selectedAutomationId: String? = null,
    schedulesViewModel: ProfileSchedulesViewModel = hiltViewModel(),
    scheduleViewModel: ScheduleViewModel = hiltViewModel(),
) {
    val state by schedulesViewModel.uiState.collectAsStateWithLifecycle()
    val schedule by scheduleViewModel.uiState.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    val protection = LocalConfigurationProtection.current
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
            IconButton(
                onClick = { guarded(schedulesViewModel::addProfileFromCurrentSettings) },
                modifier = Modifier.testTag(AutomationsTags.NEW),
            ) {
                Icon(
                    Icons.Outlined.Add,
                    contentDescription = stringResource(R.string.automations_new),
                    tint = colors.secondary,
                )
            }
        }
        Text(
            text = stringResource(R.string.automations_subtitle),
            style = GeistType.copy14,
            color = colors.secondary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1),
        )

        if (!schedule.isPurchased) {
            AutomationsNotice(
                title = stringResource(R.string.schedule_unlock_required_title),
                body = stringResource(R.string.schedule_unlock_required_body),
                action = stringResource(R.string.unlock_button),
                onAction = onNavigateToPaywall,
            )
        }

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
                state.rows.forEachIndexed { index, row ->
                    AutomationCard(
                        row = row,
                        color = automationColor(colors, index),
                        selected = row.profile.id == selectedAutomationId,
                        onToggle = { enabled -> guarded { schedulesViewModel.setEnabled(row.profile.id, enabled) } },
                        onOpen = { onOpenAutomation(row.profile.id) },
                        onEdit = { onEditAutomation(row.profile.id) },
                        onRunNow = { onRunNow(row.profile.id) },
                    )
                }
            }
        }
        if (state.recoveryDiscardFailed) {
            Text(
                stringResource(R.string.profile_schedule_discard_recovery_failed),
                style = MaterialTheme.typography.bodySmall,
                color = colors.error,
            )
        }

        Spacer(Modifier.height(GeistSpacing.space1))
        GeistCardClickable(
            onClick = onOpenScheduleSettings,
            modifier = Modifier.testTag(AutomationsTags.SCHEDULE_SETTINGS),
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.automations_schedule_settings_title),
                    style = GeistType.label16,
                    color = colors.primary,
                )
                Text(
                    stringResource(R.string.automations_schedule_settings_subtitle),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
            }
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.secondary)
        }

        // Clears the floating Export now action on compact layouts; zero beside the rail.
        val clearance = LocalFloatingActionClearance.current - GeistSpacing.space4 - GeistSpacing.space3
        if (clearance > 0.dp) Spacer(Modifier.height(clearance))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AutomationCard(
    row: ProfileScheduleRow,
    color: Color,
    selected: Boolean,
    onToggle: (Boolean) -> Unit,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onRunNow: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val entry = row.entry
    val enabled = entry?.isEnabled == true
    val name = row.profile.name
    val detailsLabel = stringResource(R.string.automation_detail_details_named, name)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(AutomationsTags.CARD)
            .clip(RoundedCornerShape(GeistRadii.large))
            .background(if (selected) colors.secondaryContainer else colors.background200)
            .semantics { this.selected = selected }
            .padding(GeistSpacing.space4),
    ) {
        // A paused automation recedes, as on the board; its controls stay fully usable.
        val dim = if (enabled) 1f else 0.72f
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = GeistSizes.minimumTouchTarget)
                    .clip(RoundedCornerShape(GeistRadii.small))
                    .clickable(role = Role.Button, onClick = onOpen)
                    .semantics { contentDescription = detailsLabel }
                    .testTag(AutomationsTags.DETAILS)
                    .alpha(dim),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Box(
                    Modifier.size(GeistSizes.control).background(colors.gray.c300, RoundedCornerShape(GeistSpacing.space3)),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(14.dp).background(color, CircleShape))
                }
                Column(Modifier.weight(1f)) {
                    Text(name, style = GeistType.heading16, color = colors.primary)
                    Text(nextRunLabel(entry), style = GeistType.label12, color = colors.secondary)
                }
            }
            val switchLabel = stringResource(R.string.automations_switch_named, name)
            AppSwitch(
                checked = enabled,
                onCheckedChange = onToggle,
                modifier = Modifier.testTag(AutomationsTags.SWITCH).semantics { contentDescription = switchLabel },
            )
        }
        Spacer(Modifier.height(14.dp))
        Text(
            text = automationSentenceAnnotated(
                row.profile,
                entry,
                SpanStyle(
                    color = colors.brandPrimary,
                    fontWeight = FontWeight.Medium,
                    textDecoration = TextDecoration.Underline,
                ),
            ),
            style = GeistType.copy18,
            color = colors.secondary,
            modifier = Modifier.alpha(dim),
        )
        Spacer(Modifier.height(14.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            val runLabel = stringResource(R.string.automations_run_now_named, name)
            FilledTonalButton(
                onClick = onRunNow,
                shape = CircleShape,
                contentPadding = ButtonDefaults.ButtonWithIconContentPadding,
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = colors.secondaryContainer,
                    contentColor = colors.onSecondaryContainer,
                ),
                modifier = Modifier.testTag(AutomationsTags.RUN_NOW).semantics { contentDescription = runLabel },
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.automations_run_now), style = GeistType.button14)
            }
            val editLabel = stringResource(R.string.automations_edit_named, name)
            OutlinedButton(
                onClick = onEdit,
                shape = CircleShape,
                modifier = Modifier.testTag(AutomationsTags.EDIT).semantics { contentDescription = editLabel },
            ) {
                Text(stringResource(R.string.automations_edit), style = GeistType.button14, color = colors.brandPrimary)
            }
        }
    }
}

/** "Next · Sun 7:30 AM", "Paused" for a switched-off schedule, or "On demand" without one. */
@Composable
private fun nextRunLabel(entry: ScheduledProfileEntry?): String {
    if (entry == null) return stringResource(R.string.automations_on_demand)
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
