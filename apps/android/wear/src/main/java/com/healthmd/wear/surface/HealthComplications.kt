package com.healthmd.wear.surface

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.*
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingTimelineComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.TimeInterval
import androidx.wear.watchface.complications.datasource.TimelineEntry
import com.healthmd.wear.MainActivity
import com.healthmd.wear.R
import com.healthmd.wear.relativeAge
import com.healthmd.wear.sync.WearSnapshotRepository
import com.healthmd.wearable.contract.*
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId

abstract class HealthComplicationService(private val metric: Metric) : SuspendingTimelineComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationDataTimeline =
        metric.timeline(this, request.complicationType)
    override fun getPreviewData(type: ComplicationType): ComplicationData? = metric.placeholder(this, type)
}
class DailyActivityComplicationService : HealthComplicationService(Metric.ACTIVITY)
class RecoveryComplicationService : HealthComplicationService(Metric.RECOVERY)
class StepsComplicationService : HealthComplicationService(Metric.STEPS)
class MoveComplicationService : HealthComplicationService(Metric.MOVE)
class ExerciseComplicationService : HealthComplicationService(Metric.EXERCISE)
class SleepComplicationService : HealthComplicationService(Metric.SLEEP)
class RestingHeartRateComplicationService : HealthComplicationService(Metric.RESTING_HEART_RATE)
class AverageHeartRateComplicationService : HealthComplicationService(Metric.AVERAGE_HEART_RATE)
class HrvComplicationService : HealthComplicationService(Metric.HRV)
class BloodOxygenComplicationService : HealthComplicationService(Metric.BLOOD_OXYGEN)

enum class Metric(val labelRes: Int, val maximum: Float) {
    ACTIVITY(R.string.wear_activity, 10_000f), RECOVERY(R.string.wear_recovery, 12f), STEPS(R.string.wear_steps, 10_000f),
    MOVE(R.string.wear_move, 1_000f), EXERCISE(R.string.wear_exercise, 180f), SLEEP(R.string.wear_sleep, 12f),
    RESTING_HEART_RATE(R.string.wear_resting_hr, 220f), AVERAGE_HEART_RATE(R.string.wear_average_hr, 220f),
    HRV(R.string.wear_hrv, 200f), BLOOD_OXYGEN(R.string.wear_blood_oxygen, 100f);

    fun data(service: android.app.Service, type: ComplicationType): ComplicationData =
        data(service, type, System.currentTimeMillis())

    internal fun data(service: android.app.Service, type: ComplicationType, now: Long): ComplicationData {
        if (WearSnapshotRepository.versionMismatch.value || WearSnapshotRepository.orderingCorrupt.value) {
            return NoDataComplicationData()
        }
        val snapshot = WearSnapshotRepository.load(service) ?: return NoDataComplicationData()
        if (snapshot.permissionState == WearPermissionState.HEALTH_CONNECT_UNAVAILABLE ||
            snapshot.freshness(now) == WearFreshness.EXPIRED || snapshot.freshness(now) == WearFreshness.VERSION_MISMATCH
        ) return NoDataComplicationData()
        val zone = runCatching { ZoneId.of(snapshot.capturedZoneId) }.getOrNull() ?: return NoDataComplicationData()
        val day = if (this == RECOVERY || this == SLEEP || this == HRV) {
            snapshot.recoveryDay(now)
        } else {
            snapshot.currentDay(now)
        } ?: return NoDataComplicationData()
        val numeric = value(day) ?: return NoDataComplicationData()
        val stale = snapshot.freshness(now) == WearFreshness.STALE
        val note = if (stale) relativeAge(service, snapshot.capturedAtEpochMillis, now) else service.getString(R.string.wear_not_realtime)
        val visibleStaleLabel = stale && type != ComplicationType.LONG_TEXT
        return build(
            service,
            type,
            numeric,
            note,
            visibleStaleLabel = visibleStaleLabel,
            validUntilEpochMillis = validThrough(snapshot, now, zone),
        )
    }

    internal fun timeline(service: android.app.Service, type: ComplicationType, now: Long = System.currentTimeMillis()): ComplicationDataTimeline {
        val current = data(service, type, now)
        if (current is NoDataComplicationData) return ComplicationDataTimeline(current, emptyList())
        val snapshot = WearSnapshotRepository.load(service) ?: return ComplicationDataTimeline(current, emptyList())
        val zone = runCatching { ZoneId.of(snapshot.capturedZoneId) }.getOrNull()
            ?: return ComplicationDataTimeline(current, emptyList())
        val day = if (this == RECOVERY || this == SLEEP || this == HRV) {
            snapshot.recoveryDay(now)
        } else {
            snapshot.currentDay(now)
        } ?: return ComplicationDataTimeline(current, emptyList())
        val numeric = value(day) ?: return ComplicationDataTimeline(current, emptyList())
        val starts = staleTimelineStarts(
            snapshot,
            now,
            zone,
            continueAcrossMidnight = isRecoveryMetric(),
        ).toMutableSet()
        // Recovery/Sleep/HRV may carry yesterday's bounded journal value into the morning. Schedule
        // a midnight reselection so the complication remains truthful without a phone push.
        if (isRecoveryMetric()) {
            val midnight = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1)
                .atStartOfDay(zone).toInstant().toEpochMilli()
            val expiry = snapshot.capturedAtEpochMillis + WearHealthSnapshot.MAX_DISPLAY_MILLIS
            if (midnight <= expiry && snapshot.recoveryDay(midnight)?.let(::value) != null) starts += midnight
        }
        val entries = starts.sorted().mapNotNull { start ->
            val selected = if (isRecoveryMetric()) snapshot.recoveryDay(start) else snapshot.currentDay(start)
            val valueAtStart = selected?.let(::value) ?: return@mapNotNull null
            val end = validThrough(snapshot, start, zone)
            // The preceding entry already covers a one-millisecond final boundary. ProtoLayout
            // timeline intervals require start < end, so omit an otherwise zero-length replacement.
            if (end <= start) return@mapNotNull null
            val staleAtStart = snapshot.freshness(start) == WearFreshness.STALE
            val note = if (staleAtStart) relativeAge(service, snapshot.capturedAtEpochMillis, start)
                else service.getString(R.string.wear_not_realtime)
            val data = build(
                service, type, valueAtStart, note,
                visibleStaleLabel = staleAtStart && type != ComplicationType.LONG_TEXT,
                validUntilEpochMillis = end,
            )
            TimelineEntry(TimeInterval(Instant.ofEpochMilli(start), Instant.ofEpochMilli(end)), data)
        }
        return ComplicationDataTimeline(current, entries)
    }

    fun placeholder(service: android.app.Service, type: ComplicationType): ComplicationData =
        // Picker previews contain labels/placeholders only; never invented health measurements.
        build(service, type, 0.0, service.getString(R.string.wear_preview_placeholder), preview = true)

    private fun isRecoveryMetric() = this == RECOVERY || this == SLEEP || this == HRV

    private fun value(day: WearHealthDay): Double? = when (this) {
        ACTIVITY, STEPS -> day.steps?.toDouble(); RECOVERY, SLEEP -> day.sleepMinutes?.div(60)
        MOVE -> day.moveKilocalories; EXERCISE -> day.exerciseMinutes; RESTING_HEART_RATE -> day.restingHeartRateBpm
        AVERAGE_HEART_RATE -> day.averageHeartRateBpm; HRV -> day.hrvRmssdMillis; BLOOD_OXYGEN -> day.bloodOxygenPercent
    }
    private fun build(
        service: android.app.Service,
        type: ComplicationType,
        numeric: Double,
        note: String,
        preview: Boolean = false,
        visibleStaleLabel: Boolean = false,
        validUntilEpochMillis: Long? = null,
    ): ComplicationData {
        val metricLabel = service.getString(labelRes)
        val visibleTitle = if (visibleStaleLabel) note else metricLabel
        val formatted = if (preview) service.getString(R.string.wear_no_data_short) else format(service, numeric)
        val tap = PendingIntent.getActivity(service, ordinal, Intent(service, MainActivity::class.java).putExtra("metric", name), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val title = PlainComplicationText.Builder(visibleTitle).build(); val text = PlainComplicationText.Builder(formatted).build()
        val description = PlainComplicationText.Builder(service.getString(R.string.wear_complication_description, metricLabel, formatted, note)).build()
        val validRange = validUntilEpochMillis?.let { TimeRange.before(Instant.ofEpochMilli(it)) }
        return when (type) {
            ComplicationType.RANGED_VALUE -> if (preview) {
                NoDataComplicationData(placeholder = ShortTextComplicationData.Builder(text, description).setTitle(title).build())
            } else {
                RangedValueComplicationData.Builder(numeric.toFloat().coerceIn(0f, maximum), 0f, maximum, description)
                    .setText(text).setTitle(title).setTapAction(tap)
                    .apply { validRange?.let(::setValidTimeRange) }.build()
            }
            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(PlainComplicationText.Builder(service.getString(R.string.wear_complication_long, metricLabel, formatted, note)).build(), description)
                .setTitle(title).setTapAction(tap).apply { validRange?.let(::setValidTimeRange) }.build()
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(text, description)
                .setTitle(title).setTapAction(tap).apply { validRange?.let(::setValidTimeRange) }.build()
            else -> NoDataComplicationData()
        }
    }

    internal fun validThrough(snapshot: WearHealthSnapshot, now: Long, zone: ZoneId): Long {
        val freshness = snapshot.freshness(now)
        val freshnessEnd = when (freshness) {
            WearFreshness.CURRENT -> snapshot.capturedAtEpochMillis + WearHealthSnapshot.CURRENT_MILLIS
            WearFreshness.STALE -> snapshot.capturedAtEpochMillis + WearHealthSnapshot.MAX_DISPLAY_MILLIS
            else -> now - 1L
        }
        // The previous captured-zone day ceases to be current at midnight itself. TimeRange ends
        // are inclusive, so the last valid millisecond is immediately before each boundary.
        val dayEnd = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1)
            .atStartOfDay(zone).toInstant().toEpochMilli() - 1L
        val visibleAgeEnd = if (freshness == WearFreshness.STALE) {
            val age = (now - snapshot.capturedAtEpochMillis).coerceAtLeast(0L)
            snapshot.capturedAtEpochMillis + ((age / 3_600_000L) + 1L) * 3_600_000L - 1L
        } else Long.MAX_VALUE
        return minOf(freshnessEnd, dayEnd, visibleAgeEnd)
    }

    internal fun staleTimelineStarts(
        snapshot: WearHealthSnapshot,
        now: Long,
        zone: ZoneId,
        continueAcrossMidnight: Boolean = false,
    ): List<Long> {
        val firstStale = snapshot.capturedAtEpochMillis + WearHealthSnapshot.CURRENT_MILLIS + 1L
        val first = if (now < firstStale) firstStale else {
            val age = (now - snapshot.capturedAtEpochMillis).coerceAtLeast(0L)
            snapshot.capturedAtEpochMillis + ((age / 3_600_000L) + 1L) * 3_600_000L
        }
        val expiry = snapshot.capturedAtEpochMillis + WearHealthSnapshot.MAX_DISPLAY_MILLIS
        val dayEnd = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1)
            .atStartOfDay(zone).toInstant().toEpochMilli() - 1L
        // Activity values are today-only and stop at the captured-zone midnight. Recovery values
        // may carry yesterday's journal into the following day, so continue hourly stale entries;
        // mapNotNull in timeline() still suppresses them if midnight makes the source day too old.
        val last = if (continueAcrossMidnight) expiry else minOf(expiry, dayEnd)
        if (first > last) return emptyList()
        return generateSequence(first) { previous ->
            val age = previous - snapshot.capturedAtEpochMillis
            snapshot.capturedAtEpochMillis + ((age / 3_600_000L) + 1L) * 3_600_000L
        }.takeWhile { it <= last }.toList()
    }
    private fun format(service: android.app.Service, value: Double): String {
        val nf = NumberFormat.getNumberInstance().apply { maximumFractionDigits = if (this@Metric == SLEEP || this@Metric == RECOVERY) 1 else 0 }
        val number = nf.format(value)
        return when (this) {
            ACTIVITY, STEPS -> number; RECOVERY, SLEEP -> service.getString(R.string.wear_value_hours, number)
            MOVE -> service.getString(R.string.wear_value_kcal, number); EXERCISE -> service.getString(R.string.wear_value_minutes, number)
            RESTING_HEART_RATE, AVERAGE_HEART_RATE -> service.getString(R.string.wear_value_bpm, number)
            HRV -> service.getString(R.string.wear_value_ms, number); BLOOD_OXYGEN -> service.getString(R.string.wear_value_percent, number)
        }
    }
}
