package com.healthmd.wear.surface

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import com.google.common.truth.Truth.assertThat
import com.healthmd.wear.sync.WearSnapshotRepository
import com.healthmd.wearable.contract.WearHealthDay
import com.healthmd.wearable.contract.WearHealthSnapshot
import java.time.Instant
import java.time.ZoneId
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class HealthComplicationRenderingTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val service = StepsComplicationService().also { RobolectricService.attach(it, context) }

    @After fun cleanup() { runCatching { WearSnapshotRepository.clear(context) } }

    @Test fun `all ten metrics build supported native data from local aggregates`() {
        val now = System.currentTimeMillis()
        putSnapshot(now, WearHealthDay(
            localDate = localDate(now), steps = 8420, moveKilocalories = 410.0, exerciseMinutes = 34.0,
            sleepMinutes = 450.0, restingHeartRateBpm = 58.0, averageHeartRateBpm = 73.0,
            hrvRmssdMillis = 46.0, bloodOxygenPercent = 97.0,
        ))

        Metric.entries.forEach { metric ->
            assertThat(metric.data(service, ComplicationType.SHORT_TEXT, now)).isInstanceOf(ShortTextComplicationData::class.java)
            assertThat(metric.data(service, ComplicationType.RANGED_VALUE, now)).isInstanceOf(RangedValueComplicationData::class.java)
        }
    }

    @Test fun `above-goal values clamp ranged progress but preserve truthful text`() {
        val now = System.currentTimeMillis()
        putSnapshot(now, WearHealthDay(
            localDate = localDate(now), steps = 25_000, moveKilocalories = 2_000.0,
            exerciseMinutes = 300.0, sleepMinutes = 900.0, restingHeartRateBpm = 250.0,
            averageHeartRateBpm = 260.0, hrvRmssdMillis = 250.0, bloodOxygenPercent = 100.0,
        ))

        Metric.entries.forEach { metric ->
            val ranged = metric.data(service, ComplicationType.RANGED_VALUE, now) as RangedValueComplicationData
            assertThat(ranged.value).isAtMost(ranged.max)
            assertThat(ranged.value).isAtLeast(ranged.min)
        }
        val steps = Metric.STEPS.data(service, ComplicationType.RANGED_VALUE, now) as RangedValueComplicationData
        assertThat(requireNotNull(steps.text).getTextAt(context.resources, Instant.ofEpochMilli(now)).toString()).contains("25,000")
    }

    @Test fun `activity and recovery use their provider labels`() {
        val now = System.currentTimeMillis()
        putSnapshot(now, WearHealthDay(localDate(now), steps = 8420, sleepMinutes = 450.0))
        val activity = Metric.ACTIVITY.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val recovery = Metric.RECOVERY.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val instant = Instant.ofEpochMilli(now)
        assertThat(requireNotNull(activity.title).getTextAt(context.resources, instant).toString()).isEqualTo("Daily Activity")
        assertThat(requireNotNull(recovery.title).getTextAt(context.resources, instant).toString()).isEqualTo("Recovery")
    }

    @Test fun `sleep recovery and hrv use preceding overnight journal day`() {
        val now = Instant.parse("2026-08-13T06:00:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(
                WearHealthDay("2026-08-12", sleepMinutes = 450.0, hrvRmssdMillis = 46.0),
                WearHealthDay("2026-08-13", steps = 8420),
            ),
        ))

        assertThat(Metric.SLEEP.data(service, ComplicationType.SHORT_TEXT, now)).isInstanceOf(ShortTextComplicationData::class.java)
        assertThat(Metric.RECOVERY.data(service, ComplicationType.SHORT_TEXT, now)).isInstanceOf(ShortTextComplicationData::class.java)
        assertThat(Metric.HRV.data(service, ComplicationType.SHORT_TEXT, now)).isInstanceOf(ShortTextComplicationData::class.java)
        assertThat(Metric.MOVE.data(service, ComplicationType.SHORT_TEXT, now)).isInstanceOf(NoDataComplicationData::class.java)
    }

    @Test fun `two-day-old recovery values remain no-data in a fresh snapshot`() {
        val now = Instant.parse("2026-08-13T06:00:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-11", sleepMinutes = 450.0, hrvRmssdMillis = 46.0)),
        ))

        assertThat(Metric.RECOVERY.data(service, ComplicationType.SHORT_TEXT, now))
            .isInstanceOf(NoDataComplicationData::class.java)
        assertThat(Metric.SLEEP.data(service, ComplicationType.SHORT_TEXT, now))
            .isInstanceOf(NoDataComplicationData::class.java)
        assertThat(Metric.HRV.data(service, ComplicationType.SHORT_TEXT, now))
            .isInstanceOf(NoDataComplicationData::class.java)
    }

    @Test fun `sleep and hrv select their latest preceding days independently`() {
        val now = Instant.parse("2026-08-13T06:00:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(
                WearHealthDay("2026-08-12", sleepMinutes = 450.0, hrvRmssdMillis = 46.0),
                WearHealthDay("2026-08-13", steps = 8420),
            ),
        ))

        val sleep = Metric.SLEEP.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val hrv = Metric.HRV.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val recovery = Metric.RECOVERY.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val instant = Instant.ofEpochMilli(now)
        assertThat(sleep.text.getTextAt(context.resources, instant).toString()).contains("7.5")
        assertThat(hrv.text.getTextAt(context.resources, instant).toString()).contains("46")
        assertThat(recovery.text.getTextAt(context.resources, instant).toString()).contains("7.5")
    }

    @Test fun `rendered data validity ends at next freshness or captured-zone day boundary`() {
        val now = System.currentTimeMillis()
        putSnapshot(now, WearHealthDay(localDate(now), steps = 8420))
        val current = Metric.STEPS.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val dayEnd = Instant.ofEpochMilli(now).atZone(ZoneId.of("UTC")).toLocalDate().plusDays(1)
            .atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli() - 1L
        assertThat(current.validTimeRange.endDateTimeMillis.toEpochMilli())
            .isEqualTo(minOf(now + WearHealthSnapshot.CURRENT_MILLIS, dayEnd))

        val captured = now - WearHealthSnapshot.CURRENT_MILLIS - 60_000L
        WearSnapshotRepository.clear(context)
        putSnapshot(captured, WearHealthDay(localDate(now), steps = 8420))
        val stale = Metric.STEPS.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val nextVisibleHourEnd = captured + 5L * 3_600_000L - 1L
        assertThat(stale.validTimeRange.endDateTimeMillis.toEpochMilli())
            .isEqualTo(minOf(captured + WearHealthSnapshot.MAX_DISPLAY_MILLIS, dayEnd, nextVisibleHourEnd))
    }

    @Test fun `current request includes scheduled stale timeline entry`() {
        // Use a deterministic morning instant so the four-hour current window and the first
        // visible stale-hour transition both occur before the captured-zone midnight boundary.
        val now = Instant.parse("2026-08-12T08:00:00Z").toEpochMilli()
        putSnapshot(now, WearHealthDay(localDate(now), steps = 8420))
        val timeline = Metric.STEPS.timeline(service, ComplicationType.SHORT_TEXT, now)
        assertThat(timeline.timelineEntries).isNotEmpty()
        val stale = timeline.timelineEntries.first()
        assertThat(stale.validity.start.toEpochMilli())
            .isEqualTo(now + WearHealthSnapshot.CURRENT_MILLIS + 1L)
        assertThat(stale.complicationData).isInstanceOf(ShortTextComplicationData::class.java)
        val staleText = stale.complicationData as ShortTextComplicationData
        assertThat(requireNotNull(staleText.title).getTextAt(context.resources, stale.validity.start).toString()).contains("ago")
        val titles = timeline.timelineEntries.take(2).map {
            requireNotNull((it.complicationData as ShortTextComplicationData).title)
                .getTextAt(context.resources, it.validity.start).toString()
        }
        assertThat(titles).hasSize(2)
        assertThat(titles[1]).isNotEqualTo(titles[0])
        assertThat(timeline.timelineEntries.last().validity.end.toEpochMilli())
            .isAtMost(now + WearHealthSnapshot.MAX_DISPLAY_MILLIS)
    }

    @Test fun `recovery timeline reselects at midnight while activity ends`() {
        val now = Instant.parse("2026-08-12T23:59:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-12", steps = 8420, sleepMinutes = 450.0)),
        ))
        val midnight = Instant.parse("2026-08-13T00:00:00Z")

        val recovery = Metric.RECOVERY.timeline(service, ComplicationType.SHORT_TEXT, now)
        assertThat(recovery.timelineEntries.any { it.validity.start == midnight && it.complicationData is ShortTextComplicationData })
            .isTrue()
        val steps = Metric.STEPS.timeline(service, ComplicationType.SHORT_TEXT, now)
        assertThat(steps.timelineEntries.any { it.validity.start == midnight }).isFalse()
        assertThat(Metric.STEPS.data(service, ComplicationType.SHORT_TEXT, midnight.toEpochMilli()))
            .isInstanceOf(NoDataComplicationData::class.java)
    }

    @Test fun `recovery metrics continue with stale hourly entries after midnight`() {
        val captured = Instant.parse("2026-08-12T23:59:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = captured,
            capturedAtEpochMillis = captured,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-12", sleepMinutes = 450.0, hrvRmssdMillis = 46.0)),
        ))
        val midnight = Instant.parse("2026-08-13T00:00:00Z").toEpochMilli()
        val firstStale = captured + WearHealthSnapshot.CURRENT_MILLIS + 1L
        val nextStaleHour = captured + 5L * 3_600_000L
        val expiry = captured + WearHealthSnapshot.MAX_DISPLAY_MILLIS

        listOf(Metric.RECOVERY, Metric.SLEEP, Metric.HRV).forEach { metric ->
            val entries = metric.timeline(service, ComplicationType.SHORT_TEXT, captured).timelineEntries
            assertThat(entries.any { it.validity.start.toEpochMilli() == midnight }).isTrue()
            val stale = entries.first { it.validity.start.toEpochMilli() == firstStale }
            val staleData = stale.complicationData as ShortTextComplicationData
            assertThat(requireNotNull(staleData.title).getTextAt(context.resources, stale.validity.start).toString())
                .contains("ago")
            assertThat(entries.any { it.validity.start.toEpochMilli() == nextStaleHour }).isTrue()
            assertThat(entries.maxOf { it.validity.end.toEpochMilli() }).isAtMost(expiry)
        }
    }

    @Test fun `next boundary honors captured-zone midnight`() {
        val now = Instant.parse("2026-08-12T23:59:00Z").toEpochMilli()
        val snapshot = WearHealthSnapshot(
            sequence = 1, capturedAtEpochMillis = now, capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-12", steps = 8420)),
        )
        assertThat(Metric.STEPS.validThrough(snapshot, now, ZoneId.of("UTC")))
            .isEqualTo(Instant.parse("2026-08-12T23:59:59.999Z").toEpochMilli())
    }

    @Test fun `metric day selection uses supplied render instant`() {
        val captured = Instant.parse("2026-08-12T23:59:00Z").toEpochMilli()
        putSnapshot(captured, WearHealthDay("2026-08-12", steps = 8420))

        val beforeMidnight = Metric.STEPS.data(service, ComplicationType.SHORT_TEXT, captured)
        val afterMidnight = Metric.STEPS.data(
            service,
            ComplicationType.SHORT_TEXT,
            Instant.parse("2026-08-13T00:00:00Z").toEpochMilli(),
        )
        assertThat(beforeMidnight).isInstanceOf(ShortTextComplicationData::class.java)
        assertThat(afterMidnight).isInstanceOf(NoDataComplicationData::class.java)
    }

    @Test fun `expired and missing metric values yield true no-data`() {
        val now = System.currentTimeMillis()
        putSnapshot(now - WearHealthSnapshot.MAX_DISPLAY_MILLIS - 1, WearHealthDay(localDate(now), steps = 8420))
        assertThat(Metric.STEPS.data(service, ComplicationType.SHORT_TEXT, now)).isInstanceOf(NoDataComplicationData::class.java)

        putSnapshot(now, WearHealthDay(localDate(now)))
        assertThat(Metric.BLOOD_OXYGEN.data(service, ComplicationType.RANGED_VALUE, now)).isInstanceOf(NoDataComplicationData::class.java)
    }

    @Test fun `stale short and ranged surfaces disclose localized age`() {
        val now = System.currentTimeMillis()
        putSnapshot(now - WearHealthSnapshot.CURRENT_MILLIS - 60_000, WearHealthDay(localDate(now), steps = 8420))

        val short = Metric.STEPS.data(service, ComplicationType.SHORT_TEXT, now) as ShortTextComplicationData
        val ranged = Metric.STEPS.data(service, ComplicationType.RANGED_VALUE, now) as RangedValueComplicationData
        val instant = Instant.ofEpochMilli(now)

        assertThat(requireNotNull(short.title).getTextAt(context.resources, instant).toString()).contains("ago")
        assertThat(requireNotNull(ranged.title).getTextAt(context.resources, instant).toString()).contains("ago")
    }

    @Test fun `picker preview contains no fabricated measurement`() {
        val preview = Metric.BLOOD_OXYGEN.placeholder(service, ComplicationType.SHORT_TEXT) as ShortTextComplicationData
        val text = preview.text.getTextAt(context.resources, Instant.EPOCH).toString()
        assertThat(text).doesNotContain("97")
        assertThat(text).matches("[-—]+")
    }

    private fun putSnapshot(capturedAt: Long, day: WearHealthDay) {
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = capturedAt,
            capturedAtEpochMillis = capturedAt,
            capturedZoneId = "UTC",
            days = listOf(day),
        ))
    }

    private fun localDate(at: Long): String =
        Instant.ofEpochMilli(at).atZone(ZoneId.of("UTC")).toLocalDate().toString()
}

/** Attach a service instance without launching Android's binding machinery. */
private object RobolectricService {
    fun attach(service: android.app.Service, context: Context) {
        val base = android.content.ContextWrapper::class.java.getDeclaredField("mBase")
        base.isAccessible = true
        base.set(service, context)
    }
}
