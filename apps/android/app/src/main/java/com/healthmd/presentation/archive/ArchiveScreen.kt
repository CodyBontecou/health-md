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
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.GeistCardClickable
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

@Composable
fun ArchiveScreen(
    onExportNow: () -> Unit,
    onOpenHistory: () -> Unit,
    viewModel: ArchiveViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Text(
            text = stringResource(R.string.nav_archive),
            style = MaterialTheme.typography.headlineMedium,
            color = LocalGeistColors.current.primary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1, vertical = GeistSpacing.space2),
        )
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
            BoxWithConstraints {
                val calendar: @Composable () -> Unit = {
                    ArchiveCalendarCard(
                        state = state,
                        onPrevious = viewModel::showPreviousMonth,
                        onNext = viewModel::showNextMonth,
                        onSelect = viewModel::selectDate,
                    )
                }
                if (maxWidth >= TWO_PANE_MIN_WIDTH) {
                    // Tablets and unfolded foldables: the calendar beside the stats and day.
                    Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4)) {
                        Box(Modifier.weight(1.4f)) { calendar() }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                            ArchiveStatsCard(stats = state.month.stats, onShowGap = viewModel::jumpToGap)
                            ArchiveDayCard(state = state, onExportNow = onExportNow)
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                        ArchiveStatsCard(stats = state.month.stats, onShowGap = viewModel::jumpToGap)
                        calendar()
                        ArchiveDayCard(state = state, onExportNow = onExportNow)
                    }
                }
            }
        }
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
        // Clears the floating Export now action on compact layouts.
        Spacer(Modifier.height(GeistSpacing.space24))
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ArchiveStatsCard(stats: ArchiveStats, onShowGap: () -> Unit) {
    val colors = LocalGeistColors.current
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
                text = stringResource(R.string.archive_stat_archived),
                style = MaterialTheme.typography.bodyLarge,
                color = colors.brandOnSubtle,
                modifier = Modifier.padding(bottom = GeistSpacing.space2),
            )
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
            verticalArrangement = Arrangement.Center,
        ) {
            StatLabel(label = stringResource(R.string.archive_stat_streak), value = stats.streak, color = colors.brandOnSubtle)
            StatLabel(
                label = stringResource(R.string.archive_stat_gaps),
                value = stats.gapCount,
                color = if (stats.gapCount > 0) colors.coverageMissing else colors.brandOnSubtle,
            )
            if (stats.earliestGap != null) {
                TextButton(onClick = onShowGap) {
                    Text(stringResource(R.string.archive_show_gap), style = GeistType.button14, color = colors.brandOnSubtle)
                }
            }
        }
    }
}

@Composable
private fun StatLabel(label: String, value: Int, color: Color) {
    Row(
        modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Text(label, style = GeistType.label14, color = color)
        Text(value.toString(), style = GeistType.heading16, color = color)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ArchiveCalendarCard(
    state: ArchiveUiState,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onSelect: (LocalDate) -> Unit,
) {
    val colors = LocalGeistColors.current
    val locale = currentLocale()
    val firstDayOfWeek = WeekFields.of(locale).firstDayOfWeek
    val month = state.month.month
    GeistCard(padding = GeistSpacing.space4) {
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
            .heightIn(min = GeistSizes.minimumTouchTarget)
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
private fun ArchiveDayCard(state: ArchiveUiState, onExportNow: () -> Unit) {
    val colors = LocalGeistColors.current
    val rows = state.selectedDay
    val (onTrack, due) = ArchiveCoverage.onTrack(rows)
    GeistCard(padding = GeistSpacing.space4) {
        Text(
            text = localizedDate(state.selection.selectedDate, DateFormat.FULL),
            style = MaterialTheme.typography.titleMedium,
            color = colors.primary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1),
        )
        Text(
            text = if (due == 0) {
                stringResource(R.string.archive_day_nothing)
            } else {
                stringResource(R.string.archive_day_on_track, onTrack, due)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = colors.secondary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1),
        )
        rows.forEach { row ->
            Spacer(Modifier.height(GeistSpacing.space3))
            Row(
                modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                ProfileDot(
                    color = profileColor(colors, state.month.profiles.indexOf(row.profile).coerceAtLeast(0)),
                    filled = true,
                    size = 12,
                )
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                        Text(profileLabel(row.profile), style = GeistType.heading14, color = colors.primary)
                        StatusBadge(row.status)
                    }
                    row.latestEntry?.let { entry ->
                        Text(
                            text = stringResource(R.string.archive_row_last_export, localizedDateTime(entry.timestamp)),
                            style = GeistType.label13,
                            color = colors.secondary,
                        )
                    }
                }
                if (row.status == CoverageStatus.MISSING) {
                    Button(
                        onClick = onExportNow,
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.brandPrimary,
                            contentColor = colors.brandOnPrimary,
                        ),
                    ) {
                        Text(stringResource(R.string.archive_action_backfill), style = GeistType.button14)
                    }
                }
            }
        }
    }
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
    Text(
        text = stringResource(status.labelRes()),
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
    profile.name ?: stringResource(R.string.archive_filter_current_settings)

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
    CoverageStatus.NOT_DUE -> R.string.archive_legend_not_exported
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
