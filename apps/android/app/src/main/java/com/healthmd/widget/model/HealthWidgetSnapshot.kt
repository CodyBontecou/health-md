package com.healthmd.widget.model

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.milliseconds

/**
 * Minimal, versioned cache consumed by the Android home-screen widgets.
 *
 * The snapshot intentionally excludes granular samples, source identities, metadata, and errors.
 * It is stored only in credential-protected no-backup storage.
 */
@Serializable
data class HealthWidgetSnapshot(
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    val capturedAtEpochMillis: Long? = null,
    val capturedZoneId: String = ZoneId.systemDefault().id,
    val days: List<HealthWidgetDay> = emptyList(),
    val permissionRequiredKinds: Set<HealthWidgetKind> = emptySet(),
    val lastAttemptAtEpochMillis: Long? = capturedAtEpochMillis,
    val lastAttemptOutcome: WidgetRefreshOutcome = WidgetRefreshOutcome.NEVER,
) {
    val hasAnyData: Boolean
        get() = days.any(HealthWidgetDay::hasAnyData)

    fun day(date: LocalDate): HealthWidgetDay? =
        days.firstOrNull { it.localDate == date.toString() }

    fun dayFor(kind: HealthWidgetKind, today: LocalDate): HealthWidgetDay? {
        val todayDay = days.firstOrNull { it.localDate == today.toString() }
        val exactOrLatest = todayDay?.takeIf { it.hasDataFor(kind) }
            ?: days.lastOrNull { it.hasDataFor(kind) }
        return when (kind) {
            HealthWidgetKind.SUMMARY -> (todayDay ?: exactOrLatest)?.copy(
                // Daily activity never falls back to yesterday while the widget says “Today.”
                steps = todayDay?.steps,
                activeCaloriesKilocalories = todayDay?.activeCaloriesKilocalories,
                exerciseMinutes = todayDay?.exerciseMinutes,
                // Overnight and resting values commonly belong to the preceding calendar day.
                sleepDurationMinutes = todayDay?.sleepDurationMinutes
                    ?: latestValue(HealthWidgetDay::sleepDurationMinutes),
                sleepStartEpochMillis = todayDay?.sleepStartEpochMillis
                    ?: latestValue(HealthWidgetDay::sleepStartEpochMillis),
                sleepEndEpochMillis = todayDay?.sleepEndEpochMillis
                    ?: latestValue(HealthWidgetDay::sleepEndEpochMillis),
                restingHeartRateBpm = todayDay?.restingHeartRateBpm
                    ?: latestValue(HealthWidgetDay::restingHeartRateBpm),
                averageHeartRateBpm = todayDay?.averageHeartRateBpm
                    ?: latestValue(HealthWidgetDay::averageHeartRateBpm),
                minimumHeartRateBpm = todayDay?.minimumHeartRateBpm
                    ?: latestValue(HealthWidgetDay::minimumHeartRateBpm),
                maximumHeartRateBpm = todayDay?.maximumHeartRateBpm
                    ?: latestValue(HealthWidgetDay::maximumHeartRateBpm),
                hrvRmssdMillis = todayDay?.hrvRmssdMillis
                    ?: latestValue(HealthWidgetDay::hrvRmssdMillis),
            )
            HealthWidgetKind.ACTIVITY -> todayDay?.takeIf { it.hasDataFor(kind) }
            HealthWidgetKind.HEART_RANGE -> exactOrLatest?.copy(
                restingHeartRateBpm = exactOrLatest.restingHeartRateBpm
                    ?: latestValue(HealthWidgetDay::restingHeartRateBpm),
                averageHeartRateBpm = exactOrLatest.averageHeartRateBpm
                    ?: latestValue(HealthWidgetDay::averageHeartRateBpm),
                minimumHeartRateBpm = exactOrLatest.minimumHeartRateBpm
                    ?: latestValue(HealthWidgetDay::minimumHeartRateBpm),
                maximumHeartRateBpm = exactOrLatest.maximumHeartRateBpm
                    ?: latestValue(HealthWidgetDay::maximumHeartRateBpm),
                hrvRmssdMillis = exactOrLatest.hrvRmssdMillis
                    ?: latestValue(HealthWidgetDay::hrvRmssdMillis),
            )
            HealthWidgetKind.SLEEP -> exactOrLatest
        }
    }

    fun hasDataFor(kind: HealthWidgetKind): Boolean = days.any { it.hasDataFor(kind) }

    private fun <T : Any> latestValue(selector: (HealthWidgetDay) -> T?): T? =
        days.asReversed().firstNotNullOfOrNull(selector)

    fun recentDays(limit: Int = CHART_DAY_COUNT): List<HealthWidgetDay> =
        days.takeLast(limit.coerceAtLeast(0))

    fun age(now: Instant): Duration? {
        val capturedAt = capturedAtEpochMillis ?: return null
        val elapsedMillis = now.toEpochMilli() - capturedAt
        if (elapsedMillis < 0) return null
        return elapsedMillis.milliseconds
    }

    fun isFresh(now: Instant, maxAge: Duration = FRESHNESS_WINDOW): Boolean =
        age(now)?.let { it <= maxAge } == true

    fun canDisplayMeasurements(
        now: Instant,
        maximumAge: Duration = MAXIMUM_DISPLAY_AGE,
    ): Boolean = hasAnyData && age(now)?.let { it <= maximumAge } == true

    /** Strict validation for decoded on-disk snapshots. Invalid input fails closed. */
    fun isValid(): Boolean {
        if (schemaVersion != CURRENT_SCHEMA_VERSION) return false
        if (days.size > SNAPSHOT_DAY_COUNT) return false
        if (capturedAtEpochMillis != null && capturedAtEpochMillis < 0) return false
        if (lastAttemptAtEpochMillis != null && lastAttemptAtEpochMillis < 0) return false
        if (runCatching { ZoneId.of(capturedZoneId) }.isFailure) return false

        val parsedDates = days.map { day ->
            if (!day.isValid()) return false
            runCatching { LocalDate.parse(day.localDate) }.getOrNull() ?: return false
        }
        if (parsedDates != parsedDates.sorted() || parsedDates.distinct().size != parsedDates.size) {
            return false
        }
        return true
    }

    companion object {
        const val CURRENT_SCHEMA_VERSION = 1
        const val SNAPSHOT_DAY_COUNT = 14
        const val CHART_DAY_COUNT = 7
        val FRESHNESS_WINDOW: Duration = 4.hours
        val MAXIMUM_DISPLAY_AGE: Duration = 24.hours
    }
}

@Serializable
data class HealthWidgetDay(
    /** ISO-8601 local date. */
    val localDate: String,
    val steps: Int? = null,
    val activeCaloriesKilocalories: Double? = null,
    val exerciseMinutes: Double? = null,
    val sleepDurationMinutes: Double? = null,
    val sleepStartEpochMillis: Long? = null,
    val sleepEndEpochMillis: Long? = null,
    val restingHeartRateBpm: Double? = null,
    val averageHeartRateBpm: Double? = null,
    val minimumHeartRateBpm: Double? = null,
    val maximumHeartRateBpm: Double? = null,
    /** Android Health Connect reports RMSSD, not Apple HealthKit SDNN. */
    val hrvRmssdMillis: Double? = null,
) {
    val hasAnyData: Boolean
        get() = steps != null || activeCaloriesKilocalories != null || exerciseMinutes != null ||
            sleepDurationMinutes != null || sleepStartEpochMillis != null || sleepEndEpochMillis != null ||
            restingHeartRateBpm != null || averageHeartRateBpm != null ||
            minimumHeartRateBpm != null || maximumHeartRateBpm != null || hrvRmssdMillis != null

    fun hasDataFor(kind: HealthWidgetKind): Boolean = when (kind) {
        HealthWidgetKind.SUMMARY -> hasAnyData
        HealthWidgetKind.ACTIVITY ->
            steps != null || activeCaloriesKilocalories != null || exerciseMinutes != null
        HealthWidgetKind.HEART_RANGE ->
            restingHeartRateBpm != null || averageHeartRateBpm != null ||
                minimumHeartRateBpm != null || maximumHeartRateBpm != null || hrvRmssdMillis != null
        HealthWidgetKind.SLEEP ->
            sleepDurationMinutes != null || sleepStartEpochMillis != null || sleepEndEpochMillis != null
    }

    fun isValid(): Boolean {
        if (runCatching { LocalDate.parse(localDate) }.isFailure) return false
        if (steps != null && steps !in 0..10_000_000) return false
        if (!activeCaloriesKilocalories.isValidMeasurement(0.0, 100_000.0)) return false
        if (!exerciseMinutes.isValidMeasurement(0.0, 10_080.0)) return false
        if (!sleepDurationMinutes.isValidMeasurement(0.0, 2_880.0)) return false
        if (sleepStartEpochMillis != null && sleepStartEpochMillis < 0) return false
        if (sleepEndEpochMillis != null && sleepEndEpochMillis < 0) return false
        if (
            sleepStartEpochMillis != null && sleepEndEpochMillis != null &&
            sleepEndEpochMillis < sleepStartEpochMillis
        ) return false
        if (!restingHeartRateBpm.isValidMeasurement(1.0, 400.0)) return false
        if (!averageHeartRateBpm.isValidMeasurement(1.0, 400.0)) return false
        if (!minimumHeartRateBpm.isValidMeasurement(1.0, 400.0)) return false
        if (!maximumHeartRateBpm.isValidMeasurement(1.0, 400.0)) return false
        if (!hrvRmssdMillis.isValidMeasurement(0.0, 10_000.0)) return false
        return true
    }
}

@Serializable
enum class WidgetRefreshOutcome {
    NEVER,
    SUCCESS,
    NO_DATA,
    FOREGROUND_PERMISSION_REQUIRED,
    BACKGROUND_PERMISSION_REQUIRED,
    HEALTH_CONNECT_UNAVAILABLE,
    BEFORE_FIRST_UNLOCK,
    TEMPORARY_FAILURE,
}

object HealthWidgetGoals {
    const val STEPS = 10_000.0
    const val ACTIVE_CALORIES_KILOCALORIES = 500.0
    const val EXERCISE_MINUTES = 30.0
    const val SLEEP_HOURS = 8.0
}

private fun Double?.isValidMeasurement(minimum: Double, maximum: Double): Boolean =
    this == null || (isFinite() && this in minimum..maximum)
