package com.healthmd.widget.data

import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.widget.model.HealthWidgetDay
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.time.Duration
import javax.inject.Inject

class HealthWidgetSnapshotMapper @Inject constructor() {
    fun map(
        healthDays: List<HealthData>,
        capturedAt: Instant,
        zoneId: ZoneId,
        permissionRequiredKinds: Set<HealthWidgetKind> = emptySet(),
    ): HealthWidgetSnapshot {
        val daysByDate = linkedMapOf<String, HealthWidgetDay>()
        healthDays.forEach { healthData ->
            daysByDate[healthData.date.toString()] = healthData.toWidgetDay(zoneId)
        }
        val days = daysByDate.values
            .sortedBy(HealthWidgetDay::localDate)
            .takeLast(HealthWidgetSnapshot.SNAPSHOT_DAY_COUNT)

        val hasAnyData = days.any(HealthWidgetDay::hasAnyData)
        return HealthWidgetSnapshot(
            capturedAtEpochMillis = capturedAt.toEpochMilli(),
            capturedZoneId = zoneId.id,
            days = days,
            permissionRequiredKinds = permissionRequiredKinds,
            lastAttemptAtEpochMillis = capturedAt.toEpochMilli(),
            lastAttemptOutcome = if (hasAnyData) {
                WidgetRefreshOutcome.SUCCESS
            } else {
                WidgetRefreshOutcome.NO_DATA
            },
        )
    }
}

private fun HealthData.toWidgetDay(zoneId: ZoneId): HealthWidgetDay {
    val sleepMinutes = sleep.asleepDuration().finiteMinutesOrNull()
    val sleepStart = sleep.sessionStart.toEpochMillisOrNull(zoneId)
    val sleepEnd = sleep.sessionEnd.toEpochMillisOrNull(zoneId)
    val validSleepWindow = sleepStart == null || sleepEnd == null || sleepEnd >= sleepStart

    return HealthWidgetDay(
        localDate = date.toString(),
        steps = activity.steps?.takeIf { it >= 0 },
        activeCaloriesKilocalories = activity.activeCalories.nonNegativeFiniteOrNull(),
        exerciseMinutes = activity.exerciseMinutes.nonNegativeFiniteOrNull(),
        sleepDurationMinutes = sleepMinutes,
        sleepStartEpochMillis = sleepStart.takeIf { validSleepWindow },
        sleepEndEpochMillis = sleepEnd.takeIf { validSleepWindow },
        restingHeartRateBpm = heart.restingHeartRate.positiveFiniteOrNull(),
        averageHeartRateBpm = heart.averageHeartRate.positiveFiniteOrNull(),
        minimumHeartRateBpm = heart.heartRateMin.positiveFiniteOrNull(),
        maximumHeartRateBpm = heart.heartRateMax.positiveFiniteOrNull(),
        hrvRmssdMillis = heart.hrv.nonNegativeFiniteOrNull(),
    )
}

/**
 * Health Connect session duration includes awake stages. Match the Apple widget's asleep-duration
 * semantics when stage totals are available, while retaining a session-duration fallback for
 * providers that omit stages.
 */
private fun SleepData.asleepDuration(): Duration {
    val staged = deepSleep + remSleep + lightSleep
    return if (staged > Duration.ZERO) staged else totalDuration
}

private fun Duration.finiteMinutesOrNull(): Double? =
    takeIf { isFinite() && it > Duration.ZERO }
        ?.inWholeMilliseconds
        ?.toDouble()
        ?.div(MILLISECONDS_PER_MINUTE)

private fun LocalDateTime?.toEpochMillisOrNull(zoneId: ZoneId): Long? = this?.let { value ->
    runCatching { value.atZone(zoneId).toInstant().toEpochMilli() }.getOrNull()
}

private fun Double?.nonNegativeFiniteOrNull(): Double? =
    this?.takeIf { it.isFinite() && it >= 0.0 }

private fun Double?.positiveFiniteOrNull(): Double? =
    this?.takeIf { it.isFinite() && it > 0.0 }

private const val MILLISECONDS_PER_MINUTE = 60_000.0
