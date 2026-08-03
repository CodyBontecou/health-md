package com.healthmd.widget.glance

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.semantics
import androidx.glance.semantics.testTag
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.core.text.BidiFormatter
import com.healthmd.R
import com.healthmd.presentation.MainActivity
import com.healthmd.widget.model.HealthWidgetDay
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.math.roundToInt

@Composable
internal fun HealthWidgetContent(
    kind: HealthWidgetKind,
    snapshot: HealthWidgetSnapshot?,
    now: Instant,
    zoneId: ZoneId,
    size: DpSize,
    artwork: HealthWidgetArtwork,
) {
    val context = LocalContext.current
    val today = now.atZone(zoneId).toLocalDate()
    val day = snapshot?.dayFor(kind, today)
    val canDisplay = snapshot?.canDisplayMeasurements(now) == true &&
        snapshot.capturedZoneId == zoneId.id &&
        kind !in snapshot.permissionRequiredKinds &&
        snapshot.hasDataFor(kind)

    WidgetRoot(size) {
        when {
            canDisplay && day != null -> {
                when (kind) {
                    HealthWidgetKind.SUMMARY -> SummaryContent(context, snapshot, day, now, size, artwork)
                    HealthWidgetKind.ACTIVITY -> ActivityContent(context, snapshot, day, now, size, artwork)
                    HealthWidgetKind.HEART_RANGE -> HeartContent(context, snapshot, day, now, size, artwork)
                    HealthWidgetKind.SLEEP -> SleepContent(context, snapshot, day, now, size)
                }
            }
            else -> WidgetStateContent(
                kind = kind,
                snapshot = snapshot,
                measurementsNeedRefresh = snapshot?.hasDataFor(kind) == true &&
                    (snapshot.canDisplayMeasurements(now) != true || snapshot.capturedZoneId != zoneId.id),
            )
        }
    }
}

@Composable
private fun WidgetRoot(size: DpSize, content: @Composable () -> Unit) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(HealthWidgetColors.Background)
            .appWidgetBackground()
            .cornerRadius(12.dp)
            .clickable(actionStartActivity<MainActivity>())
            .semantics { testTag = "widget-root" }
            .padding(if (size.height <= HealthWidgetSizes.Wide.height) 8.dp else 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

@Composable
private fun SummaryContent(
    context: Context,
    snapshot: HealthWidgetSnapshot,
    day: HealthWidgetDay,
    now: Instant,
    size: DpSize,
    artwork: HealthWidgetArtwork,
) {
    when {
        size.width >= HealthWidgetSizes.Medium.width && size.height >= HealthWidgetSizes.Medium.height ->
            SummaryLarge(context, snapshot, day, now, size, artwork)
        size.width >= HealthWidgetSizes.Wide.width -> SummaryWide(context, snapshot, day, now)
        else -> SummaryCompact(context, snapshot, day, now)
    }
}

@Composable
private fun SummaryCompact(
    context: Context,
    snapshot: HealthWidgetSnapshot,
    day: HealthWidgetDay,
    now: Instant,
) {
    val locale = context.resources.configuration.locales[0]
    val largeFont = context.resources.configuration.fontScale > 1f
    val dense = largeFont || !snapshot.isFresh(now)
    Column(modifier = GlanceModifier.fillMaxSize()) {
        WidgetHeader(context.getString(R.string.widget_label_today))
        Spacer(GlanceModifier.defaultWeight())
        Text(
            text = if (largeFont) {
                HealthWidgetFormatters.compactSteps(day.steps, locale)
            } else {
                HealthWidgetFormatters.integer(day.steps, locale)
            },
            style = WidgetTextStyles.hero,
            maxLines = 1,
        )
        Text(
            text = context.getString(R.string.metric_name_steps),
            style = WidgetTextStyles.secondary,
            maxLines = 1,
        )
        if (!dense) {
            Spacer(GlanceModifier.defaultWeight())
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                MiniValue(
                    context.getString(R.string.widget_label_sleep),
                    context.getString(
                        R.string.widget_unit_hours,
                        HealthWidgetFormatters.sleepHours(day.sleepDurationMinutes, locale),
                    ),
                    HealthWidgetColors.Sleep,
                )
                Spacer(GlanceModifier.defaultWeight())
                MiniValue(
                    context.getString(R.string.widget_label_resting),
                    context.getString(
                        R.string.widget_unit_bpm,
                        HealthWidgetFormatters.integer(day.restingHeartRateBpm, locale),
                    ),
                    HealthWidgetColors.Heart,
                )
            }
        }
        StaleLabel(snapshot, now)
    }
}

@Composable
private fun SummaryWide(
    context: Context,
    snapshot: HealthWidgetSnapshot,
    day: HealthWidgetDay,
    now: Instant,
) {
    val locale = context.resources.configuration.locales[0]
    val largeFont = context.resources.configuration.fontScale > 1f
    Row(modifier = GlanceModifier.fillMaxSize()) {
        Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
            WidgetHeader(context.getString(R.string.app_name))
            Spacer(GlanceModifier.defaultWeight())
            Text(
                if (largeFont) {
                    HealthWidgetFormatters.compactSteps(day.steps, locale)
                } else {
                    HealthWidgetFormatters.integer(day.steps, locale)
                },
                style = WidgetTextStyles.hero,
                maxLines = 1,
            )
            Text(context.getString(R.string.metric_name_steps), style = WidgetTextStyles.secondary)
            StaleLabel(snapshot, now)
        }
        Spacer(GlanceModifier.width(12.dp))
        Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
            CompactMetricLine(
                context.getString(R.string.widget_label_move),
                context.getString(
                    R.string.widget_unit_kilocalories,
                    HealthWidgetFormatters.integer(day.activeCaloriesKilocalories, locale),
                ),
                HealthWidgetColors.Activity,
            )
            Spacer(GlanceModifier.height(4.dp))
            CompactMetricLine(
                context.getString(R.string.widget_label_exercise),
                context.getString(
                    R.string.widget_unit_minutes,
                    HealthWidgetFormatters.integer(day.exerciseMinutes, locale),
                ),
                HealthWidgetColors.Exercise,
            )
            Spacer(GlanceModifier.height(4.dp))
            CompactMetricLine(
                context.getString(R.string.widget_label_sleep),
                context.getString(
                    R.string.widget_unit_hours,
                    HealthWidgetFormatters.sleepHours(day.sleepDurationMinutes, locale),
                ),
                HealthWidgetColors.Sleep,
            )
            Spacer(GlanceModifier.height(4.dp))
            CompactMetricLine(
                context.getString(R.string.metric_name_hrv),
                context.getString(
                    R.string.widget_unit_milliseconds,
                    HealthWidgetFormatters.integer(day.hrvRmssdMillis, locale),
                ),
                HealthWidgetColors.Brand,
            )
        }
    }
}

@Composable
private fun SummaryLarge(
    context: Context,
    snapshot: HealthWidgetSnapshot,
    day: HealthWidgetDay,
    now: Instant,
    size: DpSize,
    artwork: HealthWidgetArtwork,
) {
    val locale = context.resources.configuration.locales[0]
    val tall = size.height >= HealthWidgetSizes.Large.height
    Column(modifier = GlanceModifier.fillMaxSize()) {
        WidgetHeader(context.getString(R.string.app_name))
        Spacer(GlanceModifier.height(if (tall) 8.dp else 4.dp))
        if (tall) Spacer(GlanceModifier.defaultWeight())
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            ActivityArtwork(day, artwork.activityRings, if (tall) 96.dp else 68.dp, locale)
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                MetricRow(
                    context.getString(R.string.metric_name_steps),
                    HealthWidgetFormatters.integer(day.steps, locale),
                    HealthWidgetColors.Steps,
                )
                Spacer(GlanceModifier.height(4.dp))
                MetricRow(
                    context.getString(R.string.widget_label_move),
                    context.getString(
                        R.string.widget_unit_kilocalories,
                        HealthWidgetFormatters.integer(day.activeCaloriesKilocalories, locale),
                    ),
                    HealthWidgetColors.Activity,
                )
                Spacer(GlanceModifier.height(4.dp))
                MetricRow(
                    context.getString(R.string.widget_label_resting),
                    context.getString(
                        R.string.widget_unit_bpm,
                        HealthWidgetFormatters.integer(day.restingHeartRateBpm, locale),
                    ),
                    HealthWidgetColors.Heart,
                )
            }
        }
        Spacer(GlanceModifier.height(if (tall) 8.dp else 4.dp))
        Text(context.getString(R.string.widget_label_seven_day_sleep), style = WidgetTextStyles.label)
        SleepBars(context, snapshot.recentDays(), height = if (tall) 88.dp else 32.dp)
        Spacer(GlanceModifier.height(4.dp))
        Text(context.getString(R.string.widget_label_heart_range), style = WidgetTextStyles.label)
        artwork.heartRange?.let { bitmap ->
            Image(
                provider = ImageProvider(bitmap),
                contentDescription = context.getString(R.string.widget_label_heart_range),
                modifier = GlanceModifier.fillMaxWidth().height(if (tall) 76.dp else 28.dp),
            )
        }
        if (tall) Spacer(GlanceModifier.defaultWeight())
        StaleLabel(snapshot, now)
    }
}

@Composable
private fun ActivityContent(
    context: Context,
    snapshot: HealthWidgetSnapshot,
    day: HealthWidgetDay,
    now: Instant,
    size: DpSize,
    artwork: HealthWidgetArtwork,
) {
    val locale = context.resources.configuration.locales[0]
    if (size.width >= HealthWidgetSizes.Wide.width) {
        Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            ActivityArtwork(
                day,
                artwork.activityRings,
                if (context.resources.configuration.fontScale > 1f) 64.dp else 88.dp,
                locale,
            )
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                WidgetHeader(context.getString(R.string.widget_activity_name))
                Spacer(GlanceModifier.height(4.dp))
                GoalRow(
                    context.getString(R.string.widget_label_move),
                    day.activeCaloriesKilocalories,
                    context.getString(
                        R.string.widget_unit_kilocalories,
                        HealthWidgetFormatters.integer(500, locale),
                    ),
                    HealthWidgetColors.Activity,
                    locale,
                )
                Spacer(GlanceModifier.height(4.dp))
                GoalRow(
                    context.getString(R.string.widget_label_exercise),
                    day.exerciseMinutes,
                    context.getString(
                        R.string.widget_unit_minutes,
                        HealthWidgetFormatters.integer(30, locale),
                    ),
                    HealthWidgetColors.Exercise,
                    locale,
                )
                Spacer(GlanceModifier.height(4.dp))
                GoalRow(
                    context.getString(R.string.metric_name_steps),
                    day.steps?.toDouble(),
                    context.getString(
                        R.string.widget_unit_steps,
                        HealthWidgetFormatters.integer(10_000, locale),
                    ),
                    HealthWidgetColors.Steps,
                    locale,
                )
                StaleLabel(snapshot, now)
            }
        }
    } else {
        val dense = context.resources.configuration.fontScale > 1f || !snapshot.isFresh(now)
        Column(
            modifier = GlanceModifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            WidgetHeader(context.getString(R.string.widget_activity_name))
            if (dense) {
                Spacer(GlanceModifier.height(4.dp))
                CompactMetricLine(
                    context.getString(R.string.widget_label_move),
                    HealthWidgetFormatters.integer(day.activeCaloriesKilocalories, locale),
                    HealthWidgetColors.Activity,
                )
                CompactMetricLine(
                    context.getString(R.string.widget_label_exercise),
                    HealthWidgetFormatters.integer(day.exerciseMinutes, locale),
                    HealthWidgetColors.Exercise,
                )
                CompactMetricLine(
                    context.getString(R.string.metric_name_steps),
                    HealthWidgetFormatters.compactSteps(day.steps, locale),
                    HealthWidgetColors.Steps,
                )
            } else {
                Spacer(GlanceModifier.defaultWeight())
                ActivityArtwork(day, artwork.activityRings, 48.dp, locale)
                Spacer(GlanceModifier.defaultWeight())
                Row(modifier = GlanceModifier.fillMaxWidth()) {
                    ActivityCompactValue(
                        context.getString(R.string.widget_label_move),
                        HealthWidgetFormatters.integer(day.activeCaloriesKilocalories, locale),
                        HealthWidgetColors.Activity,
                    )
                    Spacer(GlanceModifier.defaultWeight())
                    ActivityCompactValue(
                        context.getString(R.string.widget_label_exercise),
                        HealthWidgetFormatters.integer(day.exerciseMinutes, locale),
                        HealthWidgetColors.Exercise,
                    )
                    Spacer(GlanceModifier.defaultWeight())
                    ActivityCompactValue(
                        context.getString(R.string.metric_name_steps),
                        HealthWidgetFormatters.integer(day.steps, locale),
                        HealthWidgetColors.Steps,
                    )
                }
            }
            StaleLabel(snapshot, now)
        }
    }
}

@Composable
private fun HeartContent(
    context: Context,
    snapshot: HealthWidgetSnapshot,
    day: HealthWidgetDay,
    now: Instant,
    size: DpSize,
    artwork: HealthWidgetArtwork,
) {
    val locale = context.resources.configuration.locales[0]
    val large = size.height >= HealthWidgetSizes.Medium.height
    val tall = size.height >= HealthWidgetSizes.Large.height
    val denseWide = !large && (
        context.resources.configuration.fontScale > 1f || !snapshot.isFresh(now)
    )
    Column(modifier = GlanceModifier.fillMaxSize()) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            WidgetHeader(context.getString(R.string.widget_heart_range_name))
            Spacer(GlanceModifier.defaultWeight())
            Text(
                context.getString(
                    R.string.widget_unit_bpm,
                    HealthWidgetFormatters.integer(day.averageHeartRateBpm, locale),
                ),
                style = WidgetTextStyles.value(HealthWidgetColors.Heart, 16),
                maxLines = 1,
            )
        }
        Spacer(GlanceModifier.height(if (tall) 12.dp else if (large) 8.dp else 4.dp))
        if (tall || !large) Spacer(GlanceModifier.defaultWeight())
        artwork.heartRange?.let { bitmap ->
            Image(
                provider = ImageProvider(bitmap),
                contentDescription = context.getString(R.string.widget_heart_range_description),
                modifier = GlanceModifier.fillMaxWidth().height(
                    when {
                        tall -> 200.dp
                        large -> 116.dp
                        denseWide -> 36.dp
                        else -> 52.dp
                    },
                ),
            )
        }
        if (large) {
            Spacer(GlanceModifier.height(if (tall) 8.dp else 6.dp))
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                MetricTile(
                    context.getString(R.string.widget_label_average),
                    context.getString(
                        R.string.widget_unit_bpm,
                        HealthWidgetFormatters.integer(day.averageHeartRateBpm, locale),
                    ),
                    HealthWidgetColors.Heart,
                    GlanceModifier.defaultWeight(),
                )
                Spacer(GlanceModifier.width(8.dp))
                MetricTile(
                    context.getString(R.string.widget_label_resting),
                    context.getString(
                        R.string.widget_unit_bpm,
                        HealthWidgetFormatters.integer(day.restingHeartRateBpm, locale),
                    ),
                    HealthWidgetColors.Heart,
                    GlanceModifier.defaultWeight(),
                )
                Spacer(GlanceModifier.width(8.dp))
                MetricTile(
                    context.getString(R.string.metric_name_hrv),
                    context.getString(
                        R.string.widget_unit_milliseconds,
                        HealthWidgetFormatters.integer(day.hrvRmssdMillis, locale),
                    ),
                    HealthWidgetColors.Brand,
                    GlanceModifier.defaultWeight(),
                )
            }
            if (tall) Spacer(GlanceModifier.defaultWeight())
        } else {
            Spacer(GlanceModifier.defaultWeight())
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                InlineMetric(
                    context.getString(
                        R.string.widget_label_minimum,
                        HealthWidgetFormatters.integer(day.minimumHeartRateBpm, locale),
                    ),
                )
                Spacer(GlanceModifier.defaultWeight())
                InlineMetric(
                    context.getString(
                        R.string.widget_label_maximum,
                        HealthWidgetFormatters.integer(day.maximumHeartRateBpm, locale),
                    ),
                )
            }
        }
        StaleLabel(snapshot, now)
    }
}

@Composable
private fun SleepContent(
    context: Context,
    snapshot: HealthWidgetSnapshot,
    day: HealthWidgetDay,
    now: Instant,
    size: DpSize,
) {
    val locale = context.resources.configuration.locales[0]
    when {
        size.height >= HealthWidgetSizes.Medium.height -> {
            val tall = size.height >= HealthWidgetSizes.Large.height
            val dense = !tall && (
                context.resources.configuration.fontScale > 1f || !snapshot.isFresh(now)
            )
            Column(modifier = GlanceModifier.fillMaxSize()) {
                WidgetHeader(context.getString(R.string.widget_sleep_name))
                Spacer(GlanceModifier.height(if (dense) 4.dp else 12.dp))
                if (tall) Spacer(GlanceModifier.defaultWeight())
                Row(modifier = GlanceModifier.fillMaxWidth()) {
                    MetricTile(
                        context.getString(R.string.widget_label_last_night),
                        context.getString(
                            R.string.widget_unit_hours,
                            HealthWidgetFormatters.sleepHours(day.sleepDurationMinutes, locale),
                        ),
                        HealthWidgetColors.Sleep,
                        GlanceModifier.defaultWeight(),
                    )
                    Spacer(GlanceModifier.width(8.dp))
                    MetricTile(
                        context.getString(R.string.widget_label_seven_day_average),
                        context.getString(
                            R.string.widget_unit_hours,
                            HealthWidgetFormatters.decimal(
                                HealthWidgetFormatters.averageSleepHours(snapshot.recentDays()),
                                locale,
                            ),
                        ),
                        HealthWidgetColors.Brand,
                        GlanceModifier.defaultWeight(),
                    )
                }
                Spacer(GlanceModifier.height(if (dense) 4.dp else 12.dp))
                SleepBars(
                    context,
                    snapshot.recentDays(),
                    height = if (tall) 200.dp else if (dense) 72.dp else 96.dp,
                )
                Spacer(GlanceModifier.height(if (dense) 4.dp else 8.dp))
                Row(modifier = GlanceModifier.fillMaxWidth()) {
                    Text(context.getString(R.string.widget_label_bedtime), style = WidgetTextStyles.secondary)
                    Spacer(GlanceModifier.width(4.dp))
                    Text(HealthWidgetFormatters.time(context, day.sleepStartEpochMillis), style = WidgetTextStyles.mono)
                    Spacer(GlanceModifier.defaultWeight())
                    Text(context.getString(R.string.widget_label_wake), style = WidgetTextStyles.secondary)
                    Spacer(GlanceModifier.width(4.dp))
                    Text(HealthWidgetFormatters.time(context, day.sleepEndEpochMillis), style = WidgetTextStyles.mono)
                }
                if (tall) Spacer(GlanceModifier.defaultWeight())
                StaleLabel(snapshot, now)
            }
        }
        size.width >= HealthWidgetSizes.Wide.width -> {
            val dense = context.resources.configuration.fontScale > 1f || !snapshot.isFresh(now)
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    WidgetHeader(context.getString(R.string.widget_sleep_name))
                    Spacer(GlanceModifier.defaultWeight())
                    Text(
                        context.getString(
                            R.string.widget_unit_hours,
                            HealthWidgetFormatters.sleepHours(day.sleepDurationMinutes, locale),
                        ),
                        style = WidgetTextStyles.value(HealthWidgetColors.Sleep, 16),
                    )
                }
                Spacer(GlanceModifier.height(4.dp))
                SleepBars(context, snapshot.recentDays(), height = if (dense) 36.dp else 60.dp)
                Text(
                    context.getString(
                        R.string.widget_goal_eight_hours,
                        HealthWidgetFormatters.integer(8, locale),
                    ),
                    style = WidgetTextStyles.muted,
                )
                StaleLabel(snapshot, now)
            }
        }
        else -> {
            val largeFont = context.resources.configuration.fontScale > 1f
            Column(modifier = GlanceModifier.fillMaxSize()) {
                WidgetHeader(context.getString(R.string.widget_sleep_name))
                Spacer(GlanceModifier.defaultWeight())
                Text(
                    context.getString(
                        R.string.widget_unit_hours,
                        HealthWidgetFormatters.sleepHours(day.sleepDurationMinutes, locale),
                    ),
                    style = WidgetTextStyles.hero,
                    maxLines = 1,
                )
                if (largeFont) {
                    if (snapshot.isFresh(now)) {
                        Text(
                            HealthWidgetFormatters.time(context, day.sleepStartEpochMillis),
                            style = WidgetTextStyles.mono,
                            maxLines = 1,
                        )
                        Text(
                            HealthWidgetFormatters.time(context, day.sleepEndEpochMillis),
                            style = WidgetTextStyles.mono,
                            maxLines = 1,
                        )
                    }
                } else {
                    Text(
                        bidiPair(
                            HealthWidgetFormatters.time(context, day.sleepStartEpochMillis),
                            "–",
                            HealthWidgetFormatters.time(context, day.sleepEndEpochMillis),
                            locale,
                        ),
                        style = WidgetTextStyles.mono,
                        maxLines = 1,
                    )
                }
                if (!largeFont) {
                    Spacer(GlanceModifier.defaultWeight())
                    LinearProgressIndicator(
                        progress = ((day.sleepDurationMinutes ?: 0.0) / (8.0 * 60.0))
                            .coerceIn(0.0, 1.0)
                            .toFloat(),
                        modifier = GlanceModifier.fillMaxWidth(),
                        color = HealthWidgetColors.Sleep,
                        backgroundColor = HealthWidgetColors.Surface,
                    )
                }
                StaleLabel(snapshot, now)
            }
        }
    }
}

@Composable
private fun WidgetStateContent(
    kind: HealthWidgetKind,
    snapshot: HealthWidgetSnapshot?,
    measurementsNeedRefresh: Boolean,
) {
    val context = LocalContext.current
    val title = when (kind) {
        HealthWidgetKind.SUMMARY -> R.string.widget_health_summary_name
        HealthWidgetKind.ACTIVITY -> R.string.widget_activity_name
        HealthWidgetKind.HEART_RANGE -> R.string.widget_heart_range_name
        HealthWidgetKind.SLEEP -> R.string.widget_sleep_name
    }
    val kindHasData = snapshot?.hasDataFor(kind) == true
    val noDataMessage = when (kind) {
        HealthWidgetKind.SUMMARY -> R.string.widget_state_no_summary_data
        HealthWidgetKind.ACTIVITY -> R.string.widget_state_no_activity_data
        HealthWidgetKind.HEART_RANGE -> R.string.widget_state_no_heart_data
        HealthWidgetKind.SLEEP -> R.string.widget_state_no_sleep_data
    }
    val largeFont = context.resources.configuration.fontScale > 1f
    val message = when {
        snapshot == null || snapshot.lastAttemptOutcome == WidgetRefreshOutcome.NEVER ->
            R.string.widget_state_loading
        kind in snapshot.permissionRequiredKinds ->
            R.string.widget_state_open_for_access
        snapshot.lastAttemptOutcome == WidgetRefreshOutcome.FOREGROUND_PERMISSION_REQUIRED ->
            R.string.widget_state_open_for_access
        snapshot.lastAttemptOutcome == WidgetRefreshOutcome.HEALTH_CONNECT_UNAVAILABLE ->
            R.string.widget_state_health_connect_unavailable
        snapshot.lastAttemptOutcome == WidgetRefreshOutcome.BEFORE_FIRST_UNLOCK ->
            R.string.widget_state_unlock
        measurementsNeedRefresh -> R.string.widget_state_background_access
        !kindHasData -> noDataMessage
        snapshot.lastAttemptOutcome == WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED ->
            R.string.widget_state_background_access
        else -> noDataMessage
    }

    Column(
        modifier = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            provider = ImageProvider(R.mipmap.ic_launcher),
            contentDescription = context.getString(R.string.app_name),
            modifier = GlanceModifier
                .size(if (largeFont) 16.dp else 24.dp)
                .cornerRadius(if (largeFont) 4.dp else 6.dp),
        )
        Spacer(GlanceModifier.height(if (largeFont) 4.dp else 8.dp))
        Text(
            context.getString(title),
            style = if (largeFont) WidgetTextStyles.label else WidgetTextStyles.title,
            maxLines = 1,
        )
        Spacer(GlanceModifier.height(4.dp))
        Text(context.getString(message), style = WidgetTextStyles.secondary, maxLines = 3)
    }
}

@Composable
private fun WidgetHeader(title: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Image(
            provider = ImageProvider(R.mipmap.ic_launcher),
            contentDescription = null,
            modifier = GlanceModifier.size(16.dp).cornerRadius(6.dp),
        )
        Spacer(GlanceModifier.width(4.dp))
        Text(title, style = WidgetTextStyles.label, maxLines = 1)
    }
}

@Composable
private fun MetricRow(label: String, value: String, tint: ColorProvider) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .background(HealthWidgetColors.Surface)
            .cornerRadius(6.dp)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(GlanceModifier.size(6.dp).background(tint).cornerRadius(3.dp)) {}
        Spacer(GlanceModifier.width(4.dp))
        Text(label, style = WidgetTextStyles.secondary, maxLines = 1)
        Spacer(GlanceModifier.defaultWeight())
        Text(value, style = WidgetTextStyles.monoStrong, maxLines = 1)
    }
}

@Composable
private fun GoalRow(
    label: String,
    value: Double?,
    goalText: String,
    tint: ColorProvider,
    locale: Locale,
) {
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(GlanceModifier.size(6.dp).background(tint).cornerRadius(3.dp)) {}
        Spacer(GlanceModifier.width(4.dp))
        Text(label, style = WidgetTextStyles.secondary, maxLines = 1)
        Spacer(GlanceModifier.defaultWeight())
        Text(
            bidiPair(
                HealthWidgetFormatters.integer(value, locale),
                "/",
                goalText,
                locale,
            ),
            style = WidgetTextStyles.monoStrong,
            maxLines = 1,
        )
    }
}

@Composable
private fun InlineMetric(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = WidgetTextStyles.monoStrong, maxLines = 1)
    }
}

@Composable
private fun MetricTile(
    label: String,
    value: String,
    tint: ColorProvider,
    modifier: GlanceModifier,
) {
    Column(
        modifier = modifier
            .background(HealthWidgetColors.Surface)
            .cornerRadius(6.dp)
            .padding(8.dp),
    ) {
        Text(label, style = WidgetTextStyles.secondary, maxLines = 1)
        Spacer(GlanceModifier.height(4.dp))
        Text(value, style = WidgetTextStyles.value(tint, 14), maxLines = 1)
    }
}

@Composable
private fun MiniValue(label: String, value: String, tint: ColorProvider) {
    Column {
        Text(label, style = WidgetTextStyles.muted, maxLines = 1)
        Text(value, style = WidgetTextStyles.value(tint, 12), maxLines = 1)
    }
}

@Composable
private fun CompactMetricLine(label: String, value: String, tint: ColorProvider) {
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(GlanceModifier.size(6.dp).background(tint).cornerRadius(3.dp)) {}
        Spacer(GlanceModifier.width(4.dp))
        Text(label, style = WidgetTextStyles.secondary, maxLines = 1)
        Spacer(GlanceModifier.defaultWeight())
        Text(value, style = WidgetTextStyles.monoStrong, maxLines = 1)
    }
}

@Composable
private fun ActivityCompactValue(label: String, value: String, tint: ColorProvider) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = WidgetTextStyles.muted, maxLines = 1)
        Text(value, style = WidgetTextStyles.value(tint, 12), maxLines = 1)
    }
}

@Composable
private fun ActivityArtwork(
    day: HealthWidgetDay,
    bitmap: android.graphics.Bitmap?,
    size: Dp,
    locale: Locale,
) {
    val context = LocalContext.current
    Box(modifier = GlanceModifier.size(size), contentAlignment = Alignment.Center) {
        bitmap?.let {
            Image(
                provider = ImageProvider(it),
                contentDescription = null,
                modifier = GlanceModifier.fillMaxSize(),
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                HealthWidgetFormatters.compactSteps(day.steps, locale),
                style = WidgetTextStyles.value(HealthWidgetColors.Steps, 14),
                maxLines = 1,
            )
            Text(
                context.getString(R.string.metric_name_steps),
                style = WidgetTextStyles.muted,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun SleepBars(context: Context, days: List<HealthWidgetDay>, height: Dp) {
    val locale = context.resources.configuration.locales[0]
    Box(modifier = GlanceModifier.fillMaxWidth().height(height)) {
        Row(
            modifier = GlanceModifier.fillMaxSize(),
            verticalAlignment = Alignment.Bottom,
        ) {
            days.forEach { day ->
                Column(
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Spacer(GlanceModifier.defaultWeight())
                    day.sleepDurationMinutes?.let { sleepMinutes ->
                        val barHeight = ((sleepMinutes / 600.0)
                            .coerceIn(0.04, 1.0) * (height.value - 12f)).dp
                        Box(
                            modifier = GlanceModifier
                                .width(12.dp)
                                .height(barHeight)
                                .background(HealthWidgetColors.Sleep)
                                .cornerRadius(6.dp),
                        ) {}
                    }
                    Text(
                        HealthWidgetFormatters.weekdayInitial(day.localDate, locale),
                        style = WidgetTextStyles.muted,
                        maxLines = 1,
                    )
                }
            }
        }
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .padding(top = ((height.value - 12f) * 0.2f).dp)
                .height(1.dp)
                .background(HealthWidgetColors.Muted),
        ) {}
    }
}

@Composable
private fun StaleLabel(snapshot: HealthWidgetSnapshot, now: Instant) {
    if (snapshot.isFresh(now)) return
    val context = LocalContext.current
    val minutes = HealthWidgetFormatters.ageMinutes(snapshot.capturedAtEpochMillis, now) ?: return
    val locale = context.resources.configuration.locales[0]
    val text = if (minutes < 60) {
        val count = minutes.toInt()
        context.resources.getQuantityString(
            R.plurals.widget_state_updated_minutes,
            count,
            HealthWidgetFormatters.integer(count, locale),
        )
    } else {
        val count = (minutes / 60.0).roundToInt()
        context.resources.getQuantityString(
            R.plurals.widget_state_updated_hours,
            count,
            HealthWidgetFormatters.integer(count, locale),
        )
    }
    Text(text, style = WidgetTextStyles.muted, maxLines = 1)
}

private fun bidiPair(first: String, separator: String, second: String, locale: Locale): String {
    val formatter = BidiFormatter.getInstance(locale)
    return "${formatter.unicodeWrap(first)} $separator ${formatter.unicodeWrap(second)}"
}

private object WidgetTextStyles {
    val title = TextStyle(
        color = HealthWidgetColors.Primary,
        fontSize = 16.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.SansSerif,
    )
    val label = TextStyle(
        color = HealthWidgetColors.Primary,
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.SansSerif,
    )
    val secondary = TextStyle(
        color = HealthWidgetColors.Secondary,
        fontSize = 12.sp,
        fontFamily = FontFamily.SansSerif,
    )
    val muted = TextStyle(
        color = HealthWidgetColors.Muted,
        fontSize = 12.sp,
        fontFamily = FontFamily.SansSerif,
    )
    val mono = TextStyle(
        color = HealthWidgetColors.Secondary,
        fontSize = 12.sp,
        fontFamily = FontFamily.Monospace,
    )
    val monoStrong = TextStyle(
        color = HealthWidgetColors.Primary,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.Monospace,
    )
    val hero = TextStyle(
        color = HealthWidgetColors.Primary,
        fontSize = 32.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.Monospace,
    )

    fun value(color: ColorProvider, size: Int) = TextStyle(
        color = color,
        fontSize = size.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.Monospace,
        textAlign = TextAlign.End,
    )
}
