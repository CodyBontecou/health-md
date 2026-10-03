package com.healthmd.wear.surface

import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.healthmd.wear.MainActivity
import com.healthmd.wear.R
import com.healthmd.wear.WearColors
import com.healthmd.wear.WearSpacing
import com.healthmd.wear.WearType
import com.healthmd.wear.relativeAge
import com.healthmd.wear.sync.WearSnapshotRepository
import com.healthmd.wearable.contract.WearFreshness
import com.healthmd.wearable.contract.WearHealthDay
import com.healthmd.wearable.contract.WearPermissionState
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId

abstract class HealthTileService(private val recovery: Boolean) : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> =
        Futures.immediateFuture(buildTile(this, recovery, requestParams.deviceConfiguration.screenWidthDp))
    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        Futures.immediateFuture(ResourceBuilders.Resources.Builder().setVersion("2").build())
}
class DailyActivityTileService : HealthTileService(false)
class RecoveryTileService : HealthTileService(true)

internal fun buildTile(
    context: Context,
    recovery: Boolean,
    screenWidthDp: Int,
    now: Long = System.currentTimeMillis(),
): TileBuilders.Tile {
    val snapshot = WearSnapshotRepository.load(context)
    val zone = snapshot?.capturedZoneId?.let { runCatching { ZoneId.of(it) }.getOrNull() }
    val boundaries = tileTimelineBoundaries(snapshot, now, zone, recovery)
    val timeline = TimelineBuilders.Timeline.Builder()
    (listOf(now) + boundaries).forEachIndexed { index, renderAt ->
        val endExclusive = boundaries.getOrNull(index) ?: Long.MAX_VALUE
        val entry = TimelineBuilders.TimelineEntry.Builder()
            .setLayout(LayoutElementBuilders.Layout.Builder().setRoot(
                tileLayout(context, recovery, screenWidthDp, snapshot, renderAt),
            ).build())
        if (endExclusive != Long.MAX_VALUE) {
            entry.setValidity(TimelineBuilders.TimeInterval.Builder()
                .setStartMillis(renderAt)
                .setEndMillis(endExclusive)
                .build())
        } else if (index > 0) {
            entry.setValidity(TimelineBuilders.TimeInterval.Builder()
                .setStartMillis(renderAt)
                .setEndMillis(Long.MAX_VALUE)
                .build())
        }
        timeline.addTimelineEntry(entry.build())
    }
    return TileBuilders.Tile.Builder().setResourcesVersion("2").setFreshnessIntervalMillis(60 * 60 * 1000L)
        .setTileTimeline(timeline.build()).build()
}

private fun tileLayout(
    context: Context,
    recovery: Boolean,
    screenWidthDp: Int,
    snapshot: com.healthmd.wearable.contract.WearHealthSnapshot?,
    now: Long,
): LayoutElementBuilders.LayoutElement {
    val day = snapshot?.let { if (recovery) it.recoveryDay(now) else it.currentDay(now) }
    val freshness = snapshot?.freshness(now)
    val title = context.getString(if (recovery) R.string.wear_recovery else R.string.wear_activity)
    val value = when {
        WearSnapshotRepository.versionMismatch.value || WearSnapshotRepository.orderingCorrupt.value -> context.getString(R.string.wear_version_mismatch)
        snapshot == null -> context.getString(R.string.wear_setup)
        snapshot.permissionState == WearPermissionState.HEALTH_CONNECT_UNAVAILABLE -> context.getString(R.string.wear_health_connect_unavailable)
        freshness == WearFreshness.VERSION_MISMATCH -> context.getString(R.string.wear_version_mismatch)
        freshness == WearFreshness.EXPIRED -> context.getString(R.string.wear_expired)
        day == null -> context.getString(R.string.wear_no_data)
        recovery -> recoverySummary(context, day)
        else -> activitySummary(context, day)
    }
    val footer = when {
        WearSnapshotRepository.versionMismatch.value || WearSnapshotRepository.orderingCorrupt.value ||
            freshness == WearFreshness.VERSION_MISMATCH -> context.getString(R.string.wear_version_mismatch)
        freshness == WearFreshness.EXPIRED -> context.getString(R.string.wear_expired)
        freshness == WearFreshness.STALE -> relativeAge(context, snapshot!!.capturedAtEpochMillis, now)
        else -> context.getString(R.string.wear_not_realtime)
    }
    val semantics = listOf(title, value, footer).distinct().joinToString(". ")
    val launch = ActionBuilders.LaunchAction.Builder().setAndroidActivity(
        ActionBuilders.AndroidActivity.Builder().setPackageName(context.packageName).setClassName(MainActivity::class.java.name).build()
    ).build()
    val edgePadding = if (screenWidthDp >= 210) WearSpacing.xlDp else WearSpacing.lgDp
    return LayoutElementBuilders.Column.Builder()
        .setWidth(DimensionBuilders.expand()).setHeight(DimensionBuilders.expand())
        .setModifiers(ModifiersBuilders.Modifiers.Builder()
            .setPadding(ModifiersBuilders.Padding.Builder().setAll(DimensionBuilders.dp(edgePadding)).build())
            .setSemantics(ModifiersBuilders.Semantics.Builder()
                .setRole(ModifiersBuilders.SEMANTICS_ROLE_BUTTON)
                .setContentDescription(semantics)
                .build())
            .setClickable(ModifiersBuilders.Clickable.Builder().setId("open").setOnClick(launch).build()).build())
        .addContent(text(title, WearColors.primaryArgb.toInt(), WearType.titleSp, 1))
        .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.dp(WearSpacing.smDp)).build())
        .addContent(text(value, WearColors.textArgb.toInt(), WearType.bodySp, 3))
        .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.dp(WearSpacing.smDp)).build())
        .addContent(text(footer, WearColors.mutedArgb.toInt(), WearType.captionSp, 2))
        .build()
}

/** Future points at which cached Tile content must change even without a phone or host refresh. */
internal fun tileTimelineBoundaries(
    snapshot: com.healthmd.wearable.contract.WearHealthSnapshot?,
    now: Long,
    zone: ZoneId?,
    recovery: Boolean,
): List<Long> {
    if (snapshot == null || zone == null) return emptyList()
    val stale = snapshot.capturedAtEpochMillis + com.healthmd.wearable.contract.WearHealthSnapshot.CURRENT_MILLIS + 1L
    val expired = snapshot.capturedAtEpochMillis + com.healthmd.wearable.contract.WearHealthSnapshot.MAX_DISPLAY_MILLIS + 1L
    val midnight = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1)
        .atStartOfDay(zone).toInstant().toEpochMilli()
    // Recovery may truthfully carry only today's/yesterday's overnight values across midnight.
    // Continue replacing its localized stale age hourly until expiry; Daily Activity becomes empty
    // at midnight and therefore does not need post-midnight measurement-age entries.
    val staleBoundaryLimit = if (recovery) expired else minOf(expired, midnight)
    val staleHourBoundaries = generateSequence(stale) { previous -> previous + 3_600_000L }
        .takeWhile { it < staleBoundaryLimit }
    return (sequenceOf(stale, expired, midnight) + staleHourBoundaries)
        .filter { it > now }
        .distinct()
        .sorted()
        .toList()
}

internal fun com.healthmd.wearable.contract.WearHealthSnapshot.currentDay(nowMillis: Long = System.currentTimeMillis()): WearHealthDay? {
    val zone = runCatching { ZoneId.of(capturedZoneId) }.getOrNull() ?: return null
    val today = java.time.Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate().toString()
    return days.firstOrNull { it.localDate == today }
}

/**
 * Latest preceding overnight values selected independently. Sleep and HRV can be journaled on
 * different days; combining them must not make either valid value disappear. Activity remains
 * strictly today-only.
 */
internal fun com.healthmd.wearable.contract.WearHealthSnapshot.recoveryDay(
    nowMillis: Long = System.currentTimeMillis(),
): WearHealthDay? {
    val zone = runCatching { ZoneId.of(capturedZoneId) }.getOrNull() ?: return null
    val today = java.time.Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
    // A fresh aggregate envelope does not make an old journal value fresh. Overnight recovery may
    // carry only today's or yesterday's journal into the morning; older values remain hidden.
    val earliest = today.minusDays(1)
    fun latest(predicate: (WearHealthDay) -> Boolean): WearHealthDay? = days.asReversed().firstOrNull { day ->
        val date = runCatching { java.time.LocalDate.parse(day.localDate) }.getOrNull()
        date != null && date in earliest..today && predicate(day)
    }
    val sleep = latest { it.sleepMinutes != null }
    val hrv = latest { it.hrvRmssdMillis != null }
    if (sleep == null && hrv == null) return null
    val latestDate = listOfNotNull(sleep?.localDate, hrv?.localDate).maxOrNull()!!
    return WearHealthDay(
        localDate = latestDate,
        sleepMinutes = sleep?.sleepMinutes,
        hrvRmssdMillis = hrv?.hrvRmssdMillis,
    )
}
internal fun activitySummary(context: Context, day: WearHealthDay): String {
    val nf = NumberFormat.getNumberInstance()
    return listOfNotNull(
        day.steps?.let { context.getString(R.string.wear_tile_steps, nf.format(it)) },
        day.exerciseMinutes?.let { context.getString(R.string.wear_tile_exercise, nf.format(it.toInt())) },
    ).joinToString(context.getString(R.string.wear_metric_separator)).ifBlank { context.getString(R.string.wear_tile_activity_empty) }
}
internal fun recoverySummary(context: Context, day: WearHealthDay): String {
    val nf = NumberFormat.getNumberInstance()
    return listOfNotNull(
        day.sleepMinutes?.let { context.getString(R.string.wear_tile_sleep, nf.format(it / 60)) },
        day.hrvRmssdMillis?.let { context.getString(R.string.wear_tile_hrv, nf.format(it.toInt())) },
    ).joinToString(context.getString(R.string.wear_metric_separator)).ifBlank { context.getString(R.string.wear_tile_recovery_empty) }
}
private fun text(value: String, color: Int, size: Float, lines: Int) = LayoutElementBuilders.Text.Builder().setText(value)
    .setMaxLines(lines).setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
    .setFontStyle(LayoutElementBuilders.FontStyle.Builder().setColor(argb(color)).setSize(DimensionBuilders.sp(size)).build()).build()
