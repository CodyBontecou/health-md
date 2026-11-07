package com.healthmd.presentation.archive

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.PauseCircle
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.schedule.automationSentence
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.text.DateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle

/** The Month / Week switch beside the calendar's navigation (iOS `viewModeButton`). */
@Composable
internal fun ArchiveViewModeButton(text: String, onClick: () -> Unit) {
    FilledTonalButton(
        onClick = onClick,
        shape = CircleShape,
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = LocalGeistColors.current.secondaryContainer,
            contentColor = LocalGeistColors.current.onSecondaryContainer,
        ),
    ) { Text(text, style = GeistType.button14) }
}

/** iOS `nextRunCard`: when the next export runs, with the month's gaps beside it. */
@Composable
internal fun ArchiveNextRunCard(state: ArchiveUiState, onShowGap: () -> Unit) {
    val colors = LocalGeistColors.current
    val next = state.nextRun
    GeistCard(padding = GeistSpacing.space4) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
            Box(
                modifier = Modifier.size(44.dp).background(colors.secondaryContainer, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Schedule, contentDescription = null, tint = colors.brandPrimary)
            }
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                Text(stringResource(R.string.archive_next_run), style = GeistType.label13, color = colors.secondary)
                Text(
                    text = if (next == null) {
                        stringResource(R.string.archive_nothing_scheduled)
                    } else {
                        stringResource(
                            R.string.archive_next_run_value,
                            next.profileName ?: profileLabel(ArchiveProfile(null)),
                            whenText(next.atMillis, state.today),
                        )
                    },
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.primary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            ArchiveGapButton(state, onShowGap)
        }
    }
}

/** "No gaps" or "N gaps"; selects the earliest gap of the shown month. */
@Composable
internal fun ArchiveGapButton(state: ArchiveUiState, onShowGap: () -> Unit) {
    val colors = LocalGeistColors.current
    val stats = state.month.stats
    val color = if (stats.gapCount > 0) colors.coverageMissing else colors.coverageNoGaps
    TextButton(
        onClick = onShowGap,
        enabled = stats.earliestGap != null,
        colors = ButtonDefaults.textButtonColors(contentColor = color, disabledContentColor = color),
    ) {
        Text(
            text = if (stats.gapCount > 0) {
                pluralStringResource(R.plurals.archive_gap_count, stats.gapCount, stats.gapCount)
            } else {
                stringResource(R.string.archive_no_gaps)
            },
            style = GeistType.button14,
        )
    }
}

/** "today at 7:30", "tomorrow at 7:30", else the date and time. */
@Composable
private fun whenText(atMillis: Long, today: LocalDate): String {
    val zone = ZoneId.systemDefault()
    val at = Instant.ofEpochMilli(atMillis).atZone(zone)
    val locale = currentLocale()
    val time = at.toLocalTime().format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
    val date = at.toLocalDate()
    return when (date) {
        today -> stringResource(R.string.archive_when_today, time)
        today.plusDays(1) -> stringResource(R.string.archive_when_tomorrow, time)
        else -> DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale).format(java.util.Date(atMillis))
    }
}

/** iOS `weekPanel`: the week's range, week navigation, the Month switch, then seven tiles. */
@Composable
internal fun ArchiveWeekPanel(
    state: ArchiveUiState,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onShowMonth: () -> Unit,
    onSelect: (LocalDate) -> Unit,
) {
    val colors = LocalGeistColors.current
    val locale = currentLocale()
    val first = state.week.firstOrNull()?.date
    val last = state.week.lastOrNull()?.date
    GeistCard(padding = GeistSpacing.space4) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = if (first != null && last != null) {
                    val format = DateTimeFormatter.ofPattern("MMM d", locale)
                    "${first.format(format)} – ${last.format(format)}"
                } else {
                    ""
                },
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = colors.primary,
                maxLines = 1,
                modifier = Modifier.weight(1f).padding(start = GeistSpacing.space1),
            )
            IconButton(onClick = onPrevious, enabled = state.canShowPreviousWeek) {
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowLeft,
                    contentDescription = stringResource(R.string.archive_previous_week),
                    tint = colors.secondary,
                )
            }
            IconButton(onClick = onNext, enabled = state.canShowNextWeek) {
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = stringResource(R.string.archive_next_week),
                    tint = if (state.canShowNextWeek) colors.secondary else colors.gray.c500,
                )
            }
            ArchiveViewModeButton(stringResource(R.string.archive_view_month), onShowMonth)
        }
        Spacer(Modifier.height(GeistSpacing.space3))
        Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
            state.week.forEach { day ->
                WeekTile(
                    day = day,
                    weekday = day.date.dayOfWeek.getDisplayName(TextStyle.SHORT, locale),
                    selected = day.date == state.selection.selectedDate,
                    onClick = { onSelect(day.date) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun WeekTile(
    day: ArchiveWeekDay,
    weekday: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.medium)
    val label = stringResource(
        R.string.archive_day_status,
        localizedDate(day.date, DateFormat.LONG),
        stringResource(day.status.labelRes()),
    )
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(weekday, style = GeistType.label12, color = colors.secondary, maxLines = 1)
        Spacer(Modifier.height(GeistSpacing.space1))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp)
                .then(if (selected) Modifier.border(2.dp, colors.primary, shape) else Modifier)
                .padding(if (selected) 3.dp else 0.dp)
                .clip(shape)
                .dayBackground(day.status, colors)
                .alpha(if (day.isFuture || day.status == CoverageStatus.NOT_DUE) 0.38f else 1f)
                .semantics {
                    contentDescription = label
                    this.selected = selected
                }
                .clickable(enabled = !day.isFuture, role = Role.Button, onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = day.date.dayOfMonth.toString(),
                style = GeistType.label14,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                color = when (day.status) {
                    CoverageStatus.COMPLETE -> colors.onCoverageComplete
                    CoverageStatus.MISSING -> colors.coverageMissing
                    else -> colors.primary
                },
            )
        }
    }
}

/**
 * iOS `readableDayCard`: the lead automation's day (a dashed card with its fix for a gap),
 * a way into the day page, then one line for every other automation.
 */
@Composable
internal fun ArchiveReadableDayCard(
    state: ArchiveUiState,
    onAction: (ArchiveDayAction) -> Unit,
    onOpenDay: (LocalDate) -> Unit,
) {
    val colors = LocalGeistColors.current
    val date = state.selection.selectedDate
    val lead = state.leadRow
    GeistCard(padding = GeistSpacing.space4) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = localizedDate(date, DateFormat.FULL),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = colors.primary,
                modifier = Modifier.weight(1f).padding(horizontal = GeistSpacing.space1),
            )
            lead?.let { StatusBadge(it.day.status) }
        }
        if (lead != null) {
            Spacer(Modifier.height(GeistSpacing.space3))
            LeadDetail(lead, state, onAction, onOpenDay = { onOpenDay(date) })
            val others = if (state.selection.filter == null) state.selectedDay.filter { it !== lead } else emptyList()
            if (others.isNotEmpty()) {
                Spacer(Modifier.height(GeistSpacing.space2))
                others.forEach { row ->
                    HorizontalDivider(color = colors.gray.c300)
                    OtherAutomationRow(row, state, onClick = { onOpenDay(date) })
                }
            }
        }
    }
}

@Composable
private fun LeadDetail(
    lead: ArchiveDayRow,
    state: ArchiveUiState,
    onAction: (ArchiveDayAction) -> Unit,
    onOpenDay: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val status = lead.day.status
    val note = dayNote(lead, state)
    if (status == CoverageStatus.MISSING) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .drawBehind {
                    val stroke = 1.5.dp.toPx()
                    drawRoundRect(
                        color = colors.coverageMissing,
                        topLeft = Offset(stroke / 2, stroke / 2),
                        size = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke),
                        cornerRadius = CornerRadius(GeistRadii.large.toPx()),
                        style = Stroke(width = stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))),
                    )
                }
                .padding(GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            Text(note, style = MaterialTheme.typography.bodyLarge, color = colors.secondary)
            lead.action?.let { action ->
                Button(
                    onClick = { onAction(action) },
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
                ) { Text(stringResource(R.string.archive_day_fix, stringResource(action.labelRes())), style = GeistType.button14) }
            }
        }
        return
    }
    lead.path?.let { path ->
        Text(
            text = path,
            style = GeistType.label13Mono,
            color = colors.secondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1),
        )
        Spacer(Modifier.height(GeistSpacing.space2))
    }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Text(note, style = MaterialTheme.typography.bodyMedium, color = colors.secondary, modifier = Modifier.weight(1f))
        lead.action?.takeIf { it != ArchiveDayAction.OPEN }?.let { action ->
            val label = stringResource(action.labelRes())
            if (action.isProminent) {
                Button(
                    onClick = { onAction(action) },
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
                ) { Text(label, style = GeistType.button14) }
            } else {
                FilledTonalButton(
                    onClick = { onAction(action) },
                    shape = CircleShape,
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = colors.secondaryContainer,
                        contentColor = colors.onSecondaryContainer,
                    ),
                ) { Text(label, style = GeistType.button14) }
            }
        }
    }
    // iOS: every day that was due opens its day page, whether or not a file path resolves.
    if (status != CoverageStatus.NOT_DUE) {
        Spacer(Modifier.height(GeistSpacing.space3))
        OutlinedButton(
            onClick = onOpenDay,
            shape = CircleShape,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
        ) {
            Text(stringResource(R.string.archive_see_this_day), style = GeistType.button14, color = colors.primary)
            Spacer(Modifier.width(GeistSpacing.space2))
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.primary)
        }
    }
}

@Composable
private fun OtherAutomationRow(row: ArchiveDayRow, state: ArchiveUiState, onClick: () -> Unit) {
    val colors = LocalGeistColors.current
    val index = state.month.profiles.indexOf(row.day.profile).coerceAtLeast(0)
    val canOpen = row.day.status != CoverageStatus.NOT_DUE
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .then(if (canOpen) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(vertical = GeistSpacing.space2, horizontal = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        ProfileDot(color = profileColor(colors, index), filled = true)
        Text(
            profileLabel(row.day.profile),
            style = GeistType.heading14,
            color = colors.primary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.weight(1f))
        Text(
            text = dayNote(row, state),
            style = GeistType.label13,
            color = if (row.day.status == CoverageStatus.MISSING) colors.coverageMissing else colors.secondary,
            textAlign = TextAlign.End,
            maxLines = 3,
        )
    }
}

/** iOS `ArchiveCopy.note`, from what Android history records. */
@Composable
private fun dayNote(row: ArchiveDayRow, state: ArchiveUiState): String {
    val day = row.day
    return when {
        day.profile in state.pausedLanes && day.status == CoverageStatus.NOT_DUE ->
            stringResource(R.string.archive_note_paused)
        day.status == CoverageStatus.NOT_DUE -> stringResource(R.string.archive_row_not_due)
        day.status == CoverageStatus.IN_PROGRESS -> stringResource(R.string.archive_note_in_progress)
        day.status == CoverageStatus.MISSING -> stringResource(R.string.archive_note_missing)
        day.status == CoverageStatus.PARTIAL -> stringResource(R.string.archive_note_partial)
        day.latestEntry != null -> stringResource(R.string.archive_row_last_export, localizedDateTime(day.latestEntry.timestamp))
        else -> stringResource(R.string.archive_legend_complete)
    }
}

/** iOS `pausedNote`: the selected automation is paused; Resume turns its schedule back on. */
@Composable
internal fun ArchivePausedNote(automation: ArchiveAutomation, onResume: () -> Unit) {
    val colors = LocalGeistColors.current
    GeistCard(padding = GeistSpacing.space4) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
            Icon(Icons.Outlined.PauseCircle, contentDescription = null, tint = colors.secondary)
            Text(
                stringResource(R.string.archive_paused_note, automation.profile.name),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondary,
                modifier = Modifier.weight(1f),
            )
            OutlinedButton(onClick = onResume, shape = CircleShape) {
                Text(stringResource(R.string.archive_resume), style = GeistType.button14, color = colors.primary)
            }
        }
    }
}

/** iOS `sentenceCard`: Automations · Manage, or the selected automation's sentence with Edit. */
@Composable
internal fun ArchiveSentenceCard(
    state: ArchiveUiState,
    onManage: () -> Unit,
    onEdit: (String) -> Unit,
) {
    val colors = LocalGeistColors.current
    val automation = state.filteredAutomation
    val running = state.automations.count { it.isRunning }
    val paused = state.automations.count { it.isPaused }
    val shape = RoundedCornerShape(GeistRadii.large)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.gray.c100)
            .border(1.dp, colors.gray.c300, shape)
            .clickable(role = Role.Button) { if (automation != null) onEdit(automation.profile.id) else onManage() }
            .padding(horizontal = GeistSpacing.space6, vertical = GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Row {
            Text(
                text = automation?.let { stringResource(R.string.archive_profile_automation, it.profile.name) }
                    ?: stringResource(R.string.nav_automations),
                style = GeistType.label13,
                fontWeight = FontWeight.SemiBold,
                color = colors.secondary,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = stringResource(if (automation == null) R.string.archive_automations_manage else R.string.archive_edit),
                style = GeistType.label13,
                fontWeight = FontWeight.SemiBold,
                color = colors.brandPrimary,
            )
        }
        val sentence = when {
            automation != null -> {
                val text = automationSentence(automation.profile, automation.entry)
                if (automation.isPaused) stringResource(R.string.archive_sentence_paused_suffix, text) else text
            }
            running + paused == 0 -> stringResource(R.string.archive_sentence_none)
            else -> stringResource(R.string.archive_sentence_counts, running, paused)
        }
        Text(sentence, style = MaterialTheme.typography.bodyLarge, color = colors.secondary)
    }
}

/** iOS `EmptyArchiveCard`: what to do before the archive can fill, as three steps. */
@Composable
internal fun ArchiveSetupChecklist(
    healthConnected: Boolean,
    hasFolder: Boolean,
    onConnectHealth: () -> Unit,
    onChooseFolder: () -> Unit,
    onBackfill: () -> Unit,
) {
    val colors = LocalGeistColors.current
    GeistCard {
        Text(stringResource(R.string.archive_empty_title), style = MaterialTheme.typography.headlineSmall, color = colors.primary)
        Spacer(Modifier.height(GeistSpacing.space2))
        Text(stringResource(R.string.archive_setup_body), style = MaterialTheme.typography.bodyMedium, color = colors.secondary)
        Spacer(Modifier.height(GeistSpacing.space4))
        SetupStep(
            title = stringResource(R.string.archive_setup_connect),
            subtitle = stringResource(R.string.archive_setup_connect_subtitle),
            done = healthConnected,
            next = !healthConnected,
            onClick = onConnectHealth,
        )
        SetupStep(
            title = stringResource(R.string.archive_setup_folder),
            subtitle = stringResource(R.string.archive_setup_folder_subtitle),
            done = hasFolder,
            next = healthConnected && !hasFolder,
            onClick = onChooseFolder,
        )
        SetupStep(
            title = stringResource(R.string.archive_setup_backfill),
            subtitle = stringResource(R.string.archive_setup_backfill_subtitle),
            done = false,
            next = healthConnected && hasFolder,
            onClick = onBackfill,
        )
        Spacer(Modifier.height(GeistSpacing.space4))
        PrimaryButton(
            text = stringResource(if (healthConnected) R.string.archive_setup_choose_folder else R.string.archive_setup_connect),
            onClick = if (healthConnected) onChooseFolder else onConnectHealth,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun SetupStep(title: String, subtitle: String, done: Boolean, next: Boolean, onClick: () -> Unit) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = GeistSizes.minimumTouchTarget)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(
            Icons.Outlined.CheckCircle,
            contentDescription = null,
            tint = if (done) colors.success else colors.gray.c500,
        )
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.heading14, color = colors.primary)
            Text(subtitle, style = GeistType.label13, color = colors.secondary)
        }
        if (done || next) {
            Text(
                text = stringResource(if (done) R.string.archive_setup_done else R.string.archive_setup_next),
                style = GeistType.label12,
                color = if (done) colors.success else colors.brandPrimary,
                modifier = Modifier
                    .background(colors.gray.c200, RoundedCornerShape(GeistRadii.small))
                    .padding(horizontal = GeistSpacing.space2, vertical = 2.dp),
            )
        }
    }
}
