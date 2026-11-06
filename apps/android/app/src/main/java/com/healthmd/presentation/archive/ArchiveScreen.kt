package com.healthmd.presentation.archive

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
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
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.LocalFloatingActionClearance
import com.healthmd.presentation.common.LocalUsesNavigationRail
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.theme.GeistBreakpoints
import com.healthmd.presentation.theme.GeistColors
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.text.DateFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Date
import java.util.Locale

/** From the `md` breakpoint (with the navigation rail) the calendar sits beside the day. */
private val TWO_PANE_MIN_WIDTH = GeistBreakpoints.medium.dp

/** Content width from which the side column takes its full 400dp (tablets, landscape). */
private val LARGE_SIDE_BREAKPOINT = 920.dp

/** Content width from which the side column takes the board's compact 300dp. */
private val MEDIUM_SIDE_BREAKPOINT = 700.dp

@Composable
fun ArchiveScreen(
    onExportNow: () -> Unit,
    onOpenHistory: () -> Unit,
    /** Opens Export now preset to one missing date. */
    onBackfill: (LocalDate) -> Unit,
    /** Opens the day page: the file Health.md writes for one date. */
    onOpenDay: (LocalDate) -> Unit = {},
    /** Opens Automations from the large-screen summary card. */
    onOpenAutomations: () -> Unit = {},
    viewModel: ArchiveViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val healthConnectConnected by viewModel.healthConnectConnected.collectAsStateWithLifecycle()
    // Permissions change in Health Connect itself, so re-read them whenever the Archive returns.
    LifecycleResumeEffect(viewModel) {
        viewModel.refreshHealthConnect()
        onPauseOrDispose { }
    }
    val context = LocalContext.current
    val protection = LocalConfigurationProtection.current
    val header: @Composable (Modifier) -> Unit = { modifier ->
        ArchiveHeader(
            healthConnectConnected = healthConnectConnected,
            onOpenHealthConnect = {
                if (protection.enabled) {
                    protection.onBlockedChange()
                } else {
                    HealthConnectIntentLauncher(context).openSettings()
                }
            },
            modifier = modifier,
        )
    }
    CompositionLocalProvider(LocalCurrentSettingsName provides state.currentSettingsName) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // From `md` the rail narrows the content below 601dp on an unfolded foldable, so the
        // window class (the rail) decides, as DESIGN.md does: the calendar sits beside the day.
        val twoPane = LocalUsesNavigationRail.current || maxWidth >= TWO_PANE_MIN_WIDTH
        if (twoPane && !(state.isLoaded && !state.hasHistory)) {
            ArchiveLargeLayout(
                state = state,
                sideWidth = when {
                    maxWidth >= LARGE_SIDE_BREAKPOINT -> 400.dp
                    maxWidth >= MEDIUM_SIDE_BREAKPOINT -> 300.dp
                    // A ~600dp unfolded inner display: keep the calendar readable beside the day.
                    else -> 264.dp
                },
                viewModel = viewModel,
                onBackfill = onBackfill,
                onOpenDay = onOpenDay,
                onOpenHistory = onOpenHistory,
                onOpenAutomations = onOpenAutomations,
                header = header,
            )
            return@BoxWithConstraints
        }
        ArchiveCompactLayout(
            state = state,
            viewModel = viewModel,
            onExportNow = onExportNow,
            onOpenHistory = onOpenHistory,
            onBackfill = onBackfill,
            onOpenDay = onOpenDay,
            header = header,
        )
    }
    }
}

/** The name the current-settings lane reads as: the active profile's. */
private val LocalCurrentSettingsName = compositionLocalOf<String?> { null }

/** The Archive title with the Health Connect status; there is no overflow menu to offer. */
@Composable
private fun ArchiveHeader(
    healthConnectConnected: Boolean?,
    onOpenHealthConnect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = stringResource(R.string.nav_archive),
            style = MaterialTheme.typography.headlineMedium,
            color = colors.primary,
            modifier = Modifier.weight(1f).padding(horizontal = GeistSpacing.space1),
        )
        if (healthConnectConnected != null) {
            IconButton(onClick = onOpenHealthConnect) {
                Icon(
                    imageVector = if (healthConnectConnected) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                    contentDescription = stringResource(
                        if (healthConnectConnected) R.string.archive_health_connected else R.string.archive_health_not_connected,
                    ),
                    tint = if (healthConnectConnected) colors.brandPrimary else colors.secondary,
                )
            }
        }
    }
}

/**
 * Tablets and unfolded foldables: the calendar fills the main pane with the filter chips and
 * month controls inside it; stats, the selected day and an Automations summary sit beside it.
 */
@Composable
private fun ArchiveLargeLayout(
    state: ArchiveUiState,
    sideWidth: androidx.compose.ui.unit.Dp,
    viewModel: ArchiveViewModel,
    onBackfill: (LocalDate) -> Unit,
    onOpenDay: (LocalDate) -> Unit,
    onOpenHistory: () -> Unit,
    onOpenAutomations: () -> Unit,
    header: @Composable (Modifier) -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier.fillMaxSize().padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
                .clip(RoundedCornerShape(GeistRadii.large))
                .background(colors.gray.c100)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            header(Modifier)
            if (state.month.profiles.size > 1) {
                ArchiveFilterChips(
                    profiles = state.month.profiles,
                    selected = state.selection.filter,
                    onSelect = viewModel::selectFilter,
                )
            }
            ArchiveCalendarCard(
                state = state,
                onPrevious = viewModel::showPreviousMonth,
                onNext = viewModel::showNextMonth,
                onSelect = viewModel::selectDate,
                cellMinHeight = 64.dp,
                framed = false,
            )
        }
        Column(
            modifier = Modifier.width(sideWidth).fillMaxHeight().verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            ArchiveStatsCard(state = state, onShowGap = viewModel::jumpToGap)
            ArchiveDayCard(state = state, onBackfill = onBackfill, onOpenDay = onOpenDay)
            GeistCardClickable(onClick = onOpenAutomations) {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = stringResource(R.string.nav_automations),
                            style = GeistType.heading14,
                            color = colors.primary,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = stringResource(R.string.archive_automations_manage),
                            style = GeistType.button14,
                            color = colors.brandPrimary,
                        )
                    }
                    Text(
                        text = stringResource(R.string.archive_automations_card_body),
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.secondary,
                    )
                }
            }
            ArchiveHistoryCard(onOpenHistory)
        }
    }
}

@Composable
private fun ArchiveHistoryCard(onOpenHistory: () -> Unit) {
    GeistCardClickable(onClick = onOpenHistory) {
        Icon(Icons.Outlined.History, contentDescription = null, tint = LocalGeistColors.current.secondary)
        Spacer(Modifier.width(GeistSpacing.space4))
        Text(
            text = stringResource(R.string.nav_history),
            style = MaterialTheme.typography.bodyLarge,
            color = LocalGeistColors.current.primary,
            modifier = Modifier.weight(1f),
        )
        Icon(
            Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = LocalGeistColors.current.secondary,
        )
    }
}

@Composable
private fun ArchiveCompactLayout(
    state: ArchiveUiState,
    viewModel: ArchiveViewModel,
    onExportNow: () -> Unit,
    onOpenHistory: () -> Unit,
    onBackfill: (LocalDate) -> Unit,
    onOpenDay: (LocalDate) -> Unit,
    header: @Composable (Modifier) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        header(Modifier.padding(vertical = GeistSpacing.space1))
        if (state.isLoaded && !state.hasHistory) {
            ArchiveEmptyState(onExportNow = onExportNow)
        } else {
            if (state.month.profiles.size > 1) {
                ArchiveFilterChips(
                    profiles = state.month.profiles,
                    selected = state.selection.filter,
                    onSelect = viewModel::selectFilter,
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                ArchiveStatsCard(state = state, onShowGap = viewModel::jumpToGap)
                ArchiveCalendarCard(
                    state = state,
                    onPrevious = viewModel::showPreviousMonth,
                    onNext = viewModel::showNextMonth,
                    onSelect = viewModel::selectDate,
                )
                ArchiveDayCard(state = state, onBackfill = onBackfill, onOpenDay = onOpenDay)
            }
        }
        ArchiveHistoryCard(onOpenHistory)
        // Clears the floating Export now action; zero beside a navigation rail. The column's
        // own bottom padding and item spacing already sit above it.
        val clearance = LocalFloatingActionClearance.current - GeistSpacing.space4 - GeistSpacing.space3
        if (clearance > 0.dp) Spacer(Modifier.height(clearance))
    }
}

@Composable
private fun ArchiveEmptyState(onExportNow: () -> Unit) {
    val colors = LocalGeistColors.current
    GeistCard {
        Text(
            text = stringResource(R.string.archive_empty_title),
            style = MaterialTheme.typography.headlineSmall,
            color = colors.primary,
        )
        Spacer(Modifier.height(GeistSpacing.space2))
        Text(
            text = stringResource(R.string.archive_empty_body),
            style = MaterialTheme.typography.bodyMedium,
            color = colors.secondary,
        )
        Spacer(Modifier.height(GeistSpacing.space4))
        PrimaryButton(text = stringResource(R.string.export_now_title), onClick = onExportNow)
    }
}

@Composable
private fun ArchiveFilterChips(
    profiles: List<ArchiveProfile>,
    selected: ArchiveProfile?,
    onSelect: (ArchiveProfile?) -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        val chipColors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = colors.secondaryContainer,
            selectedLabelColor = colors.onSecondaryContainer,
            labelColor = colors.secondary,
        )
        FilterChip(
            selected = selected == null,
            onClick = { onSelect(null) },
            label = { Text(stringResource(R.string.archive_filter_all), style = GeistType.button14) },
            colors = chipColors,
            shape = RoundedCornerShape(GeistRadii.small),
        )
        profiles.forEachIndexed { index, profile ->
            FilterChip(
                selected = selected == profile,
                onClick = { onSelect(profile) },
                label = { Text(profileLabel(profile), style = GeistType.button14) },
                leadingIcon = { ProfileDot(color = profileColor(colors, index), filled = true) },
                colors = chipColors,
                shape = RoundedCornerShape(GeistRadii.small),
            )
        }
    }
}

@Composable
private fun ArchiveStatsCard(state: ArchiveUiState, onShowGap: () -> Unit) {
    val colors = LocalGeistColors.current
    val stats = state.month.stats
    val count = stats.archivedCount
    // "All" counts across automations; one automation counts within the shown month.
    val label = if (state.selection.filter == null) {
        pluralStringResource(R.plurals.archive_stat_archived_all, count)
    } else {
        pluralStringResource(
            R.plurals.archive_stat_archived_month,
            count,
            state.month.month.format(DateTimeFormatter.ofPattern("LLLL", currentLocale())),
        )
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.brandSubtle, RoundedCornerShape(GeistRadii.large))
            .padding(GeistSpacing.space6),
    ) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
            Text(
                text = stats.archivedCount.toString(),
                style = GeistType.heading56,
                color = colors.brandOnSubtle,
            )
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                color = colors.brandOnSubtle,
                modifier = Modifier.weight(1f, fill = false).padding(bottom = GeistSpacing.space2),
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Outlined.LocalFireDepartment,
                contentDescription = null,
                tint = colors.brandOnSubtle,
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(GeistSpacing.space2))
            Text(
                text = pluralStringResource(R.plurals.archive_streak_days, stats.streak, stats.streak),
                style = GeistType.label14,
                fontWeight = FontWeight.Medium,
                color = colors.brandOnSubtle,
                modifier = Modifier.weight(1f),
            )
            // Selects the earliest gap of the shown month; with none there is nothing to show.
            val gapColor = if (stats.gapCount > 0) colors.coverageMissing else colors.coverageNoGaps
            TextButton(
                onClick = onShowGap,
                enabled = stats.earliestGap != null,
                colors = ButtonDefaults.textButtonColors(contentColor = gapColor, disabledContentColor = gapColor),
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
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ArchiveCalendarCard(
    state: ArchiveUiState,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onSelect: (LocalDate) -> Unit,
    cellMinHeight: androidx.compose.ui.unit.Dp = GeistSizes.minimumTouchTarget,
    /** False when the calendar already sits inside a tonal pane on large screens. */
    framed: Boolean = true,
) {
    val colors = LocalGeistColors.current
    val locale = currentLocale()
    val firstDayOfWeek = WeekFields.of(locale).firstDayOfWeek
    val month = state.month.month
    val frame: @Composable (@Composable () -> Unit) -> Unit = { body ->
        if (framed) GeistCard(padding = GeistSpacing.space4) { body() } else Column { body() }
    }
    frame {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = month.format(DateTimeFormatter.ofPattern("LLLL yyyy", locale)),
                style = MaterialTheme.typography.titleMedium,
                color = colors.primary,
                modifier = Modifier.weight(1f).padding(start = GeistSpacing.space2),
            )
            IconButton(onClick = onPrevious) {
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowLeft,
                    contentDescription = stringResource(R.string.archive_previous_month),
                    tint = colors.secondary,
                )
            }
            IconButton(onClick = onNext, enabled = state.canShowNextMonth) {
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = stringResource(R.string.archive_next_month),
                    tint = if (state.canShowNextMonth) colors.secondary else colors.gray.c500,
                )
            }
        }
        val weekdays = (0 until 7).map { firstDayOfWeek.plus(it.toLong()) }
        Row(modifier = Modifier.fillMaxWidth().padding(vertical = GeistSpacing.space2)) {
            weekdays.forEach { day ->
                Text(
                    text = day.getDisplayName(TextStyle.NARROW, locale),
                    style = GeistType.label12,
                    color = colors.secondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
            }
        }
        val leading = (month.atDay(1).dayOfWeek.value - firstDayOfWeek.value + 7) % 7
        val cells: List<ArchiveDay?> = List(leading) { null } + state.month.days
        cells.chunked(7).forEach { week ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = GeistSpacing.space1),
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
            ) {
                week.forEach { day ->
                    Box(modifier = Modifier.weight(1f)) {
                        if (day != null) {
                            DayCell(
                                day = day,
                                selected = day.date == state.selection.selectedDate,
                                profiles = state.month.profiles,
                                minHeight = cellMinHeight,
                                onClick = { onSelect(day.date) },
                            )
                        }
                    }
                }
                repeat(7 - week.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Spacer(Modifier.height(GeistSpacing.space3))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            modifier = Modifier.padding(horizontal = GeistSpacing.space2),
        ) {
            LegendItem(CoverageStatus.COMPLETE)
            LegendItem(CoverageStatus.PARTIAL)
            LegendItem(CoverageStatus.MISSING)
            LegendItem(CoverageStatus.NOT_DUE)
        }
    }
}

@Composable
private fun DayCell(
    day: ArchiveDay,
    selected: Boolean,
    profiles: List<ArchiveProfile>,
    minHeight: androidx.compose.ui.unit.Dp = GeistSizes.minimumTouchTarget,
    onClick: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.medium)
    val label = stringResource(
        R.string.archive_day_status,
        localizedDate(day.date, DateFormat.LONG),
        stringResource(day.status.labelRes()),
    )
    val textColor = when (day.status) {
        CoverageStatus.COMPLETE -> colors.onCoverageComplete
        CoverageStatus.MISSING -> colors.coverageMissing
        else -> colors.primary
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = minHeight)
            .then(if (selected) Modifier.border(2.dp, colors.primary, shape) else Modifier)
            .padding(if (selected) 3.dp else 0.dp)
            .clip(shape)
            .dayBackground(day.status, colors)
            .alpha(if (day.status == CoverageStatus.NOT_DUE) 0.38f else 1f)
            .semantics {
                contentDescription = label
                this.selected = selected
            }
            .clickable(role = Role.Button, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = day.date.dayOfMonth.toString(),
            style = GeistType.label14,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            color = textColor,
        )
        if (day.issueDots.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.padding(top = 2.dp)) {
                day.issueDots.forEach { dot ->
                    ProfileDot(
                        color = profileColor(colors, profiles.indexOf(dot.profile).coerceAtLeast(0)),
                        filled = dot.isFilled,
                        size = 5,
                    )
                }
            }
        }
    }
}

private fun Modifier.dayBackground(status: CoverageStatus, colors: GeistColors): Modifier = when (status) {
    CoverageStatus.COMPLETE -> background(colors.coverageComplete)
    CoverageStatus.PARTIAL -> background(colors.gray.c300).drawBehind {
        val bar = 3.dp.toPx()
        drawRect(color = colors.brandPrimary, topLeft = Offset(0f, size.height - bar))
    }
    CoverageStatus.MISSING -> drawBehind {
        val stroke = 1.5.dp.toPx()
        drawRoundRect(
            color = colors.coverageMissing,
            topLeft = Offset(stroke / 2, stroke / 2),
            size = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke),
            cornerRadius = CornerRadius(GeistRadii.medium.toPx()),
            style = Stroke(width = stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
        )
    }
    CoverageStatus.IN_PROGRESS -> border(2.dp, colors.brandPrimary, RoundedCornerShape(GeistRadii.medium))
    CoverageStatus.NOT_DUE -> border(1.dp, colors.gray.c500, RoundedCornerShape(GeistRadii.medium))
}

@Composable
private fun LegendItem(status: CoverageStatus) {
    val colors = LocalGeistColors.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        Box(
            modifier = Modifier
                .size(14.dp)
                .clip(RoundedCornerShape(GeistRadii.extraSmall))
                .dayBackground(status, colors)
                .alpha(if (status == CoverageStatus.NOT_DUE) 0.6f else 1f),
        )
        Text(stringResource(status.labelRes()), style = GeistType.label12, color = colors.secondary)
    }
}

@Composable
private fun ArchiveDayCard(
    state: ArchiveUiState,
    onBackfill: (LocalDate) -> Unit,
    onOpenDay: (LocalDate) -> Unit,
) {
    val colors = LocalGeistColors.current
    val rows = state.selectedDay
    val (onTrack, due) = ArchiveCoverage.onTrack(rows.map { it.day })
    val date = state.selection.selectedDate
    GeistCard(padding = GeistSpacing.space4) {
        Text(
            text = localizedDate(date, DateFormat.FULL),
            style = MaterialTheme.typography.titleMedium,
            color = colors.primary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1),
        )
        Text(
            text = if (due == 0) {
                stringResource(R.string.archive_day_nothing_due)
            } else {
                stringResource(R.string.archive_day_on_track, onTrack, due)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = colors.secondary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1),
        )
        rows.forEach { row ->
            Spacer(Modifier.height(GeistSpacing.space3))
            ArchiveDayRowItem(
                row = row,
                color = profileColor(colors, state.month.profiles.indexOf(row.day.profile).coerceAtLeast(0)),
                onAction = { action ->
                    when (action) {
                        ArchiveDayAction.OPEN -> onOpenDay(date)
                        // Export now preset to this date writes, re-writes or refreshes it.
                        ArchiveDayAction.REEXPORT, ArchiveDayAction.RETRY,
                        ArchiveDayAction.BACKFILL, ArchiveDayAction.REFRESH -> onBackfill(date)
                    }
                },
            )
        }
    }
}

@Composable
private fun ArchiveDayRowItem(row: ArchiveDayRow, color: Color, onAction: (ArchiveDayAction) -> Unit) {
    val colors = LocalGeistColors.current
    val day = row.day
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Box(
            modifier = Modifier.size(GeistSizes.control).background(colors.secondaryContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            ProfileDot(color = color, filled = true, size = 12)
        }
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                Text(
                    profileLabel(day.profile),
                    style = GeistType.heading14,
                    color = colors.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                StatusBadge(day.status)
            }
            row.path?.let { path ->
                Text(
                    text = path,
                    style = GeistType.label13Mono,
                    color = colors.secondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            val note = when {
                day.status == CoverageStatus.NOT_DUE -> stringResource(R.string.archive_row_not_due)
                day.latestEntry != null -> stringResource(R.string.archive_row_last_export, localizedDateTime(day.latestEntry.timestamp))
                else -> null
            }
            note?.let { Text(it, style = GeistType.label13, color = colors.secondary) }
        }
        row.action?.let { action ->
            val label = stringResource(action.labelRes())
            if (action.isProminent) {
                Button(
                    onClick = { onAction(action) },
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.brandPrimary,
                        contentColor = colors.brandOnPrimary,
                    ),
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
}

private fun ArchiveDayAction.labelRes(): Int = when (this) {
    ArchiveDayAction.OPEN -> R.string.archive_action_open
    ArchiveDayAction.REEXPORT -> R.string.archive_action_reexport
    ArchiveDayAction.RETRY -> R.string.archive_action_retry
    ArchiveDayAction.BACKFILL -> R.string.archive_action_backfill
    ArchiveDayAction.REFRESH -> R.string.archive_action_refresh
}

@Composable
private fun StatusBadge(status: CoverageStatus) {
    val colors = LocalGeistColors.current
    val tint = when (status) {
        CoverageStatus.COMPLETE -> colors.success
        CoverageStatus.MISSING -> colors.coverageMissing
        CoverageStatus.PARTIAL, CoverageStatus.IN_PROGRESS -> colors.brandPrimary
        CoverageStatus.NOT_DUE -> colors.secondary
    }
    val label = when (status) {
        CoverageStatus.NOT_DUE -> R.string.archive_status_not_due
        CoverageStatus.IN_PROGRESS -> R.string.archive_status_updating
        else -> status.labelRes()
    }
    Text(
        text = stringResource(label),
        style = GeistType.label12,
        color = tint,
        modifier = Modifier
            .background(colors.gray.c300, RoundedCornerShape(GeistRadii.small))
            .padding(horizontal = GeistSpacing.space2, vertical = 2.dp),
    )
}

@Composable
private fun ProfileDot(color: Color, filled: Boolean, size: Int = 8) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .then(
                if (filled) Modifier.background(color, CircleShape) else Modifier.border(1.5.dp, color, CircleShape),
            ),
    )
}

@Composable
private fun profileLabel(profile: ArchiveProfile): String =
    profile.name ?: LocalCurrentSettingsName.current ?: stringResource(R.string.archive_filter_current_settings)

/** Automation identity colors, in profile order. Pairs with text labels everywhere. */
private fun profileColor(colors: GeistColors, index: Int): Color = when (index % 4) {
    0 -> colors.brandPrimary
    1 -> colors.blue.c900
    2 -> colors.teal.c900
    else -> colors.amber.c900
}

private fun CoverageStatus.labelRes(): Int = when (this) {
    CoverageStatus.COMPLETE -> R.string.archive_legend_complete
    CoverageStatus.PARTIAL -> R.string.archive_legend_partial
    CoverageStatus.MISSING -> R.string.archive_legend_missing
    // Nothing was due on the date (the shared coverage status), as the board's legend reads.
    CoverageStatus.NOT_DUE -> R.string.archive_status_not_due
    CoverageStatus.IN_PROGRESS -> R.string.archive_legend_today
}

@Composable
private fun currentLocale(): Locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()

@Composable
private fun localizedDate(date: LocalDate, style: Int): String {
    val instant = date.atStartOfDay(ZoneId.systemDefault()).toInstant()
    return DateFormat.getDateInstance(style, currentLocale()).format(Date.from(instant))
}

@Composable
private fun localizedDateTime(epochMillis: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, currentLocale()).format(Date(epochMillis))
