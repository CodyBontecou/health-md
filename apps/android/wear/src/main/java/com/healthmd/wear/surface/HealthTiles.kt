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
import com.healthmd.wear.WearSize
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
        Futures.immediateFuture(tileResources())
}
internal const val TILE_RESOURCES_VERSION = "3"
internal const val TILE_ICON_PHONE = "phone"

/** Every image a Tile layout can reference, keyed by the ids used in [tileLayout]. */
internal fun tileResources(): ResourceBuilders.Resources {
    val images = Metric.entries.associate { it.tileIconId to it.iconRes } + (TILE_ICON_PHONE to R.drawable.ic_wear_phone)
    return ResourceBuilders.Resources.Builder().setVersion(TILE_RESOURCES_VERSION).apply {
        images.forEach { (id, drawable) ->
            addIdToImageMapping(id, ResourceBuilders.ImageResource.Builder()
                .setAndroidResourceByResId(ResourceBuilders.AndroidImageResourceByResId.Builder().setResourceId(drawable).build())
                .build())
        }
    }.build()
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
    return TileBuilders.Tile.Builder().setResourcesVersion(TILE_RESOURCES_VERSION).setFreshnessIntervalMillis(60 * 60 * 1000L)
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
    val metric = if (recovery) Metric.RECOVERY else Metric.ACTIVITY
    val title = context.getString(metric.labelRes)
    val versionMismatch = WearSnapshotRepository.versionMismatch.value || WearSnapshotRepository.orderingCorrupt.value
    val measurement = when {
        versionMismatch || snapshot == null -> null
        snapshot.permissionState == WearPermissionState.HEALTH_CONNECT_UNAVAILABLE -> null
        freshness == WearFreshness.VERSION_MISMATCH || freshness == WearFreshness.EXPIRED -> null
        day == null -> null
        recovery -> recoverySummary(context, day)
        else -> activitySummary(context, day)
    }
    val value = measurement ?: when {
        versionMismatch -> context.getString(R.string.wear_version_mismatch)
        snapshot == null -> context.getString(R.string.wear_setup)
        snapshot.permissionState == WearPermissionState.HEALTH_CONNECT_UNAVAILABLE -> context.getString(R.string.wear_health_connect_unavailable)
        freshness == WearFreshness.VERSION_MISMATCH -> context.getString(R.string.wear_version_mismatch)
        freshness == WearFreshness.EXPIRED -> context.getString(R.string.wear_expired)
        else -> context.getString(R.string.wear_no_data)
    }
    val footer = when {
        versionMismatch || freshness == WearFreshness.VERSION_MISMATCH -> context.getString(R.string.wear_version_mismatch)
        freshness == WearFreshness.EXPIRED -> context.getString(R.string.wear_expired)
        freshness == WearFreshness.STALE -> relativeAge(context, snapshot!!.capturedAtEpochMillis, now)
        else -> context.getString(R.string.wear_not_realtime)
    }
    val setup = snapshot == null && !versionMismatch
    // Data age and freshness problems use the warning role; the "not real-time" disclosure is muted.
    val footerColor = if (footer == context.getString(R.string.wear_not_realtime)) WearColors.mutedArgb else WearColors.warningArgb
    val semantics = listOf(title, value, footer).distinct().joinToString(". ")
    val launch = ActionBuilders.LaunchAction.Builder().setAndroidActivity(
        ActionBuilders.AndroidActivity.Builder().setPackageName(context.packageName).setClassName(MainActivity::class.java.name).build()
    ).build()
    val edgePadding = if (screenWidthDp >= 210) WearSpacing.xlDp else WearSpacing.lgDp
    val content = LayoutElementBuilders.Column.Builder()
        .setWidth(DimensionBuilders.expand()).setHeight(DimensionBuilders.wrap())
        .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
        .setModifiers(ModifiersBuilders.Modifiers.Builder()
            .setPadding(ModifiersBuilders.Padding.Builder().setAll(DimensionBuilders.dp(edgePadding)).build())
            .build())
        .addContent(if (setup) setupBadge() else icon(metric.tileIconId, metric.tintArgb.toInt()))
        .addContent(spacer())
        .addContent(text(title, WearColors.primaryArgb.toInt(), WearType.titleSp, 1, LayoutElementBuilders.FONT_WEIGHT_BOLD))
        .addContent(spacer())
        .addContent(if (measurement != null) {
            text(measurement, WearColors.textArgb.toInt(), WearType.displaySp, 2)
        } else {
            text(value, WearColors.textArgb.toInt(), WearType.bodySp, 3)
        })
        .addContent(spacer())
        .addContent(text(footer, footerColor.toInt(), WearType.captionSp, 2))
        .build()
    val root = LayoutElementBuilders.Box.Builder()
        .setWidth(DimensionBuilders.expand()).setHeight(DimensionBuilders.expand())
        .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
        .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        .setModifiers(ModifiersBuilders.Modifiers.Builder()
            .setSemantics(ModifiersBuilders.Semantics.Builder()
                .setRole(ModifiersBuilders.SEMANTICS_ROLE_BUTTON)
                .setContentDescription(semantics)
                .build())
            .setClickable(ModifiersBuilders.Clickable.Builder().setId("open").setOnClick(launch).build()).build())
    // Daily Activity draws step progress toward the same fixed scale its ranged complication
    // uses. The ring appears only beside a real, displayable step count.
    val steps = if (!recovery && measurement != null) day?.steps else null
    if (steps != null) {
        progressRing(steps / Metric.ACTIVITY.maximum).forEach(root::addContent)
    }
    return root.addContent(content).build()
}

/** Track plus progress arcs that follow the round screen edge, starting at 12 o'clock. */
internal fun progressRing(fraction: Float): List<LayoutElementBuilders.LayoutElement> {
    val clamped = fraction.coerceIn(0f, 1f)
    val inset = ModifiersBuilders.Modifiers.Builder()
        .setPadding(ModifiersBuilders.Padding.Builder().setAll(DimensionBuilders.dp(WearSize.progressInsetDp)).build())
        .build()
    fun arc(degrees: Float, color: Long) = LayoutElementBuilders.Arc.Builder()
        .setAnchorAngle(DimensionBuilders.degrees(0f))
        .setAnchorType(LayoutElementBuilders.ARC_ANCHOR_START)
        .setModifiers(inset)
        .addContent(LayoutElementBuilders.ArcLine.Builder()
            .setLength(DimensionBuilders.degrees(degrees))
            .setThickness(DimensionBuilders.dp(WearSize.progressStrokeDp))
            .setColor(argb(color.toInt()))
            .setStrokeCap(LayoutElementBuilders.STROKE_CAP_ROUND)
            .build())
        .build()
    return listOfNotNull(
        arc(360f, WearColors.surfaceArgb),
        if (clamped > 0f) arc(360f * clamped, WearColors.metricStepsArgb) else null,
    )
}

private fun spacer() = LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.dp(WearSpacing.smDp)).build()

private fun icon(resourceId: String, tint: Int, sizeDp: Float = WearSize.iconDp) = LayoutElementBuilders.Image.Builder()
    .setResourceId(resourceId)
    .setWidth(DimensionBuilders.dp(sizeDp)).setHeight(DimensionBuilders.dp(sizeDp))
    .setColorFilter(LayoutElementBuilders.ColorFilter.Builder().setTint(argb(tint)).build())
    .build()

/** Phone glyph in a brand-subtle circle: the "finish setup on your phone" state. */
private fun setupBadge() = LayoutElementBuilders.Box.Builder()
    .setWidth(DimensionBuilders.dp(WearSize.badgeDp)).setHeight(DimensionBuilders.dp(WearSize.badgeDp))
    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
    .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
    .setModifiers(ModifiersBuilders.Modifiers.Builder()
        .setBackground(ModifiersBuilders.Background.Builder()
            .setColor(argb(WearColors.primaryContainerArgb.toInt()))
            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(WearSize.badgeDp / 2)).build())
            .build())
        .build())
    .addContent(icon(TILE_ICON_PHONE, WearColors.onPrimaryContainerArgb.toInt(), WearSize.badgeIconDp))
    .build()

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
private fun text(
    value: String,
    color: Int,
    size: Float,
    lines: Int,
    weight: Int = LayoutElementBuilders.FONT_WEIGHT_NORMAL,
) = LayoutElementBuilders.Text.Builder().setText(value)
    .setMaxLines(lines).setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
    .setMultilineAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER)
    .setFontStyle(LayoutElementBuilders.FontStyle.Builder().setColor(argb(color)).setSize(DimensionBuilders.sp(size))
        .setWeight(weight).build()).build()
