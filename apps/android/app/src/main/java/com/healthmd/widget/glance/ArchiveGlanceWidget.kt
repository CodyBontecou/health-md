package com.healthmd.widget.glance

import android.content.Context
import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.semantics.testTag
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.healthmd.R
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileOccurrenceMath
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.archive.ArchiveCoverage
import com.healthmd.presentation.archive.ArchiveProfile
import com.healthmd.presentation.archive.CoverageStatus
import com.healthmd.presentation.navigation.SubRoutes
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.TextStyle as JavaTextStyle
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.flow.first

/** One square of the recent-coverage strip. */
data class ArchiveWidgetDay(val date: LocalDate, val status: CoverageStatus)

/**
 * What the Archive widgets show. Coverage and schedule only: no health values, so nothing
 * sensitive, and no Health Connect access or setup is needed.
 */
data class ArchiveWidgetSummary(
    val gapCount: Int,
    /** The last [RECENT_DAYS] dates, oldest first, ending today. */
    val recentDays: List<ArchiveWidgetDay>,
    val hasHistory: Boolean,
    val month: YearMonth,
    /** Archived (complete or partial) days so far in [month]; today is still in progress. */
    val monthArchivedCount: Int,
    /** The earliest upcoming scheduled run, or null when no automation is scheduled. */
    val nextRunAtMillis: Long? = null,
) {
    val recent: List<CoverageStatus> get() = recentDays.map(ArchiveWidgetDay::status)

    companion object {
        const val RECENT_DAYS = 14

        /** Gaps count over the last [GAP_WINDOW_DAYS] days, matching the widget description. */
        const val GAP_WINDOW_DAYS = 30

        /** Days read back from today: enough for the gap window and the strip. */
        private const val LOOKBACK_DAYS = 60L

        fun from(
            entries: List<ExportHistoryEntry>,
            today: LocalDate,
            nextRunAtMillis: Long? = null,
            /** Lanes whose automation keeps today updating; others leave today not due. */
            dueToday: Set<ArchiveProfile> = emptySet(),
        ): ArchiveWidgetSummary {
            val days = (LOOKBACK_DAYS - 1 downTo 0).map { back ->
                val date = today.minusDays(back)
                date to ArchiveCoverage.aggregateDay(entries, date, today, dueToday)
            }
            val month = YearMonth.from(today)
            val monthStats = ArchiveCoverage.stats(
                days.filter { YearMonth.from(it.first) == month },
                today,
            )
            return ArchiveWidgetSummary(
                gapCount = days.takeLast(GAP_WINDOW_DAYS).count { it.second == CoverageStatus.MISSING },
                recentDays = days.takeLast(RECENT_DAYS).map { (date, status) -> ArchiveWidgetDay(date, status) },
                hasHistory = entries.isNotEmpty(),
                month = month,
                monthArchivedCount = monthStats.archivedCount,
                nextRunAtMillis = nextRunAtMillis,
            )
        }

        /**
         * The earliest future run across the app-wide schedule and every enabled per-automation
         * schedule, using the same occurrence math that arms their alarms.
         */
        fun nextRunAtMillis(
            appScheduleAtMillis: Long?,
            profileEntries: List<ScheduledProfileEntry>,
            nowMillis: Long,
        ): Long? {
            val profileRuns = profileEntries
                .filter(ScheduledProfileEntry::isEnabled)
                .mapNotNull { entry ->
                    runCatching { ScheduledProfileOccurrenceMath.nextOccurrence(entry, nowMillis) }
                        .getOrNull()
                        ?.toEpochMilli()
                }
            return (profileRuns + listOfNotNull(appScheduleAtMillis))
                .filter { it > nowMillis }
                .minOrNull()
        }
    }
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface ArchiveWidgetEntryPoint {
    fun exportHistoryRepository(): ExportHistoryRepository
    fun exportScheduler(): ExportScheduler
    fun scheduledProfileEntryStore(): ScheduledProfileEntryStore
    fun exportProfileRepository(): ExportProfileRepository
    fun settingsRepository(): SettingsRepository
}

/** Shared loading for both Archive providers; the layout follows the placed size. */
abstract class BaseArchiveGlanceWidget : GlanceAppWidget() {
    final override val sizeMode: SizeMode =
        SizeMode.Responsive(setOf(ArchiveWidgetSizes.Small, ArchiveWidgetSizes.Wide))

    final override suspend fun provideGlance(context: Context, id: GlanceId) {
        val entryPoint = EntryPointAccessors.fromApplication(
            context.applicationContext,
            ArchiveWidgetEntryPoint::class.java,
        )
        val entries = runCatching { entryPoint.exportHistoryRepository().getAllEntries().first() }
            .getOrDefault(emptyList())
        val nowMillis = System.currentTimeMillis()
        val nextRun = runCatching {
            ArchiveWidgetSummary.nextRunAtMillis(
                appScheduleAtMillis = entryPoint.exportScheduler().nextScheduledAtMillis(),
                profileEntries = entryPoint.scheduledProfileEntryStore().getEntries(),
                nowMillis = nowMillis,
            )
        }.getOrNull()
        val dueToday = runCatching {
            ArchiveCoverage.dueToday(
                lanes = ArchiveCoverage.profiles(entries),
                profiles = entryPoint.exportProfileRepository().getProfiles(),
                schedules = entryPoint.scheduledProfileEntryStore().getEntries(),
                settings = entryPoint.settingsRepository().getExportSettings(),
            )
        }.getOrDefault(emptySet())
        val summary = ArchiveWidgetSummary.from(entries, LocalDate.now(), nextRun, dueToday)
        val now = Instant.ofEpochMilli(nowMillis)
        val zoneId = ZoneId.systemDefault()
        provideContent { ArchiveWidgetContent(summary, LocalSize.current, now, zoneId) }
    }
}

/** Archive · small (2×2): this month's archived days, gaps, next run and two weeks of coverage. */
class ArchiveGlanceWidget : BaseArchiveGlanceWidget() {
    companion object {
        /** Re-renders every placed Archive widget; a no-op when none are placed. */
        suspend fun refresh(context: Context) {
            val appContext = context.applicationContext
            ArchiveGlanceWidget().updateAll(appContext)
            ArchiveWideGlanceWidget().updateAll(appContext)
        }
    }
}

/** Archive · wide (4×2): this month's archived days, next run, Export now and the strip. */
class ArchiveWideGlanceWidget : BaseArchiveGlanceWidget()

class ArchiveWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ArchiveGlanceWidget()
}

class ArchiveWideWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ArchiveWideGlanceWidget()
}

object ArchiveWidgetSizes {
    val Small = DpSize(110.dp, 110.dp)
    val Wide = DpSize(250.dp, 110.dp)
}

/** Opens the full Export now screen: the same route as the app's Export launcher shortcut. */
internal val ArchiveExportNowParameters: ActionParameters = actionParametersOf(
    ActionParameters.Key<String>(MainActivity.EXTRA_START_ROUTE) to SubRoutes.EXPORT_NOW,
)

@Composable
internal fun ArchiveWidgetContent(
    summary: ArchiveWidgetSummary,
    size: DpSize,
    now: Instant,
    zoneId: ZoneId,
) {
    val context = LocalContext.current
    val wide = size.width >= ArchiveWidgetSizes.Wide.width
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(HealthWidgetColors.ArchiveSurface)
            .appWidgetBackground()
            .cornerRadius(28.dp)
            .clickable(actionStartActivity<MainActivity>())
            .semantics {
                testTag = "archive-widget-root"
                contentDescription = archiveContentDescription(context, summary)
            }
            .padding(16.dp),
    ) {
        ArchiveHeader(context, summary, wide, now, zoneId)
        if (!summary.hasHistory) {
            Spacer(GlanceModifier.height(8.dp))
            Text(
                text = context.getString(R.string.archive_empty_title),
                style = ArchiveTextStyles.emptyTitle,
                maxLines = 2,
            )
            Spacer(GlanceModifier.defaultWeight())
            Text(
                text = context.getString(R.string.widget_archive_empty_body),
                style = ArchiveTextStyles.secondary,
                maxLines = 3,
            )
            return@Column
        }
        if (wide) ArchiveWideBody(context, summary) else ArchiveSmallBody(context, summary)
    }
}

@Composable
private fun ArchiveHeader(
    context: Context,
    summary: ArchiveWidgetSummary,
    wide: Boolean,
    now: Instant,
    zoneId: ZoneId,
) {
    val nextRun = summary.nextRunAtMillis?.let { formatNextRun(context, it, now, zoneId) }
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Image(
            provider = ImageProvider(R.mipmap.ic_launcher),
            contentDescription = null,
            modifier = GlanceModifier
                .size(if (wide) 18.dp else 16.dp)
                .cornerRadius(if (wide) 9.dp else 8.dp),
        )
        Spacer(GlanceModifier.width(6.dp))
        Text(
            text = context.getString(R.string.widget_archive_name),
            style = if (wide) ArchiveTextStyles.titleWide else ArchiveTextStyles.titleSmall,
            maxLines = 1,
        )
        Spacer(GlanceModifier.defaultWeight())
        nextRun?.let { time ->
            Text(
                text = if (wide) context.getString(R.string.widget_archive_next_run, time) else time,
                style = ArchiveTextStyles.caption,
                maxLines = 1,
            )
        }
        if (wide) {
            Spacer(GlanceModifier.width(4.dp))
            ArchiveExportNowButton(context)
        }
    }
}

@Composable
private fun ArchiveExportNowButton(context: Context) {
    val label = context.getString(R.string.export_now_title)
    Box(
        modifier = GlanceModifier
            .size(32.dp)
            .cornerRadius(16.dp)
            .clickable(actionStartActivity<MainActivity>(ArchiveExportNowParameters))
            .semantics {
                testTag = "archive-export-now"
                contentDescription = label
            },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            provider = ImageProvider(R.drawable.ic_widget_export),
            contentDescription = label,
            colorFilter = ColorFilter.tint(HealthWidgetColors.Brand),
            modifier = GlanceModifier.size(20.dp),
        )
    }
}

@Composable
private fun ColumnScope.ArchiveSmallBody(context: Context, summary: ArchiveWidgetSummary) {
    val locale = context.locale()
    Spacer(GlanceModifier.height(6.dp))
    Text(
        text = formatCount(summary.monthArchivedCount, locale),
        style = ArchiveTextStyles.hero,
        maxLines = 1,
    )
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = daysInMonthText(context, summary, locale),
            style = ArchiveTextStyles.secondary,
            maxLines = 1,
        )
        Text(text = " · ", style = ArchiveTextStyles.secondary, maxLines = 1)
        Text(
            text = gapsText(context, summary.gapCount, locale),
            style = ArchiveTextStyles.gaps(summary.gapCount),
            maxLines = 1,
        )
    }
    Spacer(GlanceModifier.defaultWeight())
    // Two rows of seven, oldest first, so the newest week sits on the bottom row.
    // Gaps are padding, not Spacers: Glance drops a Row's children past ten.
    summary.recentDays.chunked(7).forEachIndexed { rowIndex, week ->
        if (rowIndex > 0) Spacer(GlanceModifier.height(4.dp))
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            week.forEachIndexed { index, day ->
                Box(GlanceModifier.defaultWeight().padding(start = if (index > 0) 4.dp else 0.dp)) {
                    ArchiveCell(day.status, height = 12.dp, radius = 4.dp, modifier = GlanceModifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.ArchiveWideBody(context: Context, summary: ArchiveWidgetSummary) {
    val locale = context.locale()
    Spacer(GlanceModifier.height(6.dp))
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Text(
            text = formatCount(summary.monthArchivedCount, locale),
            style = ArchiveTextStyles.hero,
            maxLines = 1,
        )
        Spacer(GlanceModifier.width(8.dp))
        Column {
            Text(
                text = daysInMonthText(context, summary, locale),
                style = ArchiveTextStyles.secondary,
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(6.dp))
        }
        Spacer(GlanceModifier.defaultWeight())
        Column {
            Text(
                text = gapsText(context, summary.gapCount, locale),
                style = ArchiveTextStyles.gaps(summary.gapCount),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(6.dp))
        }
    }
    Spacer(GlanceModifier.defaultWeight())
    // One row per week inside the strip: Glance drops a Row's children past ten, which showed
    // only the oldest five of the fourteen days.
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        summary.recentDays.chunked(7).forEachIndexed { weekIndex, week ->
            Row(modifier = GlanceModifier.defaultWeight().padding(start = if (weekIndex > 0) 5.dp else 0.dp)) {
                week.forEachIndexed { index, day ->
                    Column(
                        modifier = GlanceModifier.defaultWeight().padding(start = if (index > 0) 5.dp else 0.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        ArchiveCell(day.status, height = 18.dp, radius = 6.dp, modifier = GlanceModifier.fillMaxWidth())
                        Spacer(GlanceModifier.height(4.dp))
                        Text(
                            text = formatCount(day.date.dayOfMonth, locale),
                            style = ArchiveTextStyles.dayNumber,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

/**
 * One coverage square in the design's vocabulary: filled when archived, a primary underline
 * when partial, a coral outline for a gap and a primary outline for today.
 */
@Composable
private fun ArchiveCell(status: CoverageStatus, height: Dp, radius: Dp, modifier: GlanceModifier) {
    val cell = modifier.height(height).cornerRadius(radius)
    when (status) {
        CoverageStatus.COMPLETE -> Box(cell.background(HealthWidgetColors.CoverageComplete)) {}
        CoverageStatus.PARTIAL -> Column(cell.background(HealthWidgetColors.ArchiveSurfaceHighest)) {
            Spacer(GlanceModifier.defaultWeight())
            Box(
                GlanceModifier
                    .fillMaxWidth()
                    .height(if (height >= 18.dp) 3.dp else 2.dp)
                    .background(HealthWidgetColors.Brand),
            ) {}
        }
        CoverageStatus.MISSING -> OutlinedCell(cell, HealthWidgetColors.CoverageMissing, 1.5.dp, radius)
        CoverageStatus.IN_PROGRESS -> OutlinedCell(cell, HealthWidgetColors.Brand, 2.dp, radius)
        CoverageStatus.NOT_DUE -> Box(cell.background(HealthWidgetColors.ArchiveSurfaceHighest)) {}
    }
}

@Composable
private fun OutlinedCell(cell: GlanceModifier, outline: ColorProvider, stroke: Dp, radius: Dp) {
    Box(cell.background(outline).padding(stroke)) {
        Box(
            GlanceModifier
                .fillMaxSize()
                .cornerRadius((radius - stroke).coerceAtLeast(0.dp))
                .background(HealthWidgetColors.ArchiveSurface),
        ) {}
    }
}

private fun archiveContentDescription(context: Context, summary: ArchiveWidgetSummary): String {
    val name = context.getString(R.string.widget_archive_name)
    if (!summary.hasHistory) return "$name: ${context.getString(R.string.archive_empty_title)}"
    val locale = context.locale()
    val archived = "${formatCount(summary.monthArchivedCount, locale)} " + daysInMonthText(context, summary, locale)
    return "$name: $archived, ${gapsText(context, summary.gapCount, locale)}"
}

private fun daysInMonthText(context: Context, summary: ArchiveWidgetSummary, locale: Locale): String =
    context.resources.getQuantityString(
        R.plurals.widget_archive_days_in_month,
        summary.monthArchivedCount,
        summary.month.month.getDisplayName(JavaTextStyle.FULL_STANDALONE, locale),
    )

private fun gapsText(context: Context, count: Int, locale: Locale): String =
    context.resources.getQuantityString(R.plurals.widget_archive_gaps, count, formatCount(count, locale))

private fun formatCount(value: Int, locale: Locale): String =
    NumberFormat.getIntegerInstance(locale).format(value)

/** Today's runs show the time alone; later runs add the weekday so the time is unambiguous. */
internal fun formatNextRun(context: Context, atMillis: Long, now: Instant, zoneId: ZoneId): String {
    val runDate = Instant.ofEpochMilli(atMillis).atZone(zoneId).toLocalDate()
    val today = now.atZone(zoneId).toLocalDate()
    val time = if (DateFormat.is24HourFormat(context)) "Hm" else "hm"
    val skeleton = if (runDate == today) time else "EEE$time"
    val pattern = DateFormat.getBestDateTimePattern(context.locale(), skeleton)
    return SimpleDateFormat(pattern, context.locale()).apply {
        timeZone = TimeZone.getTimeZone(zoneId)
    }.format(Date(atMillis))
}

private fun Context.locale(): Locale = resources.configuration.locales[0]

private object ArchiveTextStyles {
    val titleSmall = TextStyle(
        color = HealthWidgetColors.Brand,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.SansSerif,
    )
    val titleWide = TextStyle(
        color = HealthWidgetColors.Primary,
        fontSize = 14.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.SansSerif,
    )
    val caption = TextStyle(
        color = HealthWidgetColors.Muted,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.SansSerif,
        textAlign = TextAlign.End,
    )
    val hero = TextStyle(
        color = HealthWidgetColors.Primary,
        fontSize = 44.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.SansSerif,
    )
    val secondary = TextStyle(
        color = HealthWidgetColors.Muted,
        fontSize = 13.sp,
        fontFamily = FontFamily.SansSerif,
    )
    val emptyTitle = TextStyle(
        color = HealthWidgetColors.Primary,
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.SansSerif,
    )
    val dayNumber = TextStyle(
        color = HealthWidgetColors.Muted,
        fontSize = 10.sp,
        fontFamily = FontFamily.SansSerif,
        textAlign = TextAlign.Center,
    )

    fun gaps(count: Int) = TextStyle(
        color = if (count > 0) HealthWidgetColors.CoverageMissing else HealthWidgetColors.Muted,
        fontSize = 13.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.SansSerif,
    )
}
