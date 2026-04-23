package com.healthmd.export

import com.healthmd.domain.model.*
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

/**
 * Canonical fixture datasets for Android exporter contract tests.
 *
 * Mirrors iOS `HealthMdTests/Fixtures/Export/ExportFixtures.swift` as closely as possible.
 * Where iOS/Android differ (e.g. "coreSleep" vs "lightSleep", missing stand hours), the
 * Android equivalent is used and the mapping documented inline.
 *
 * All fixtures use a fixed reference date: 2026-03-15 (same as iOS).
 */
object ExportFixtures {

    /** Fixed reference date: 2026-03-15T00:00:00 */
    val referenceDate: LocalDate = LocalDate.of(2026, 3, 15)

    /** Midnight of the reference date — use as base for relative DateTimes. */
    val referenceDateTime: LocalDateTime = LocalDateTime.of(2026, 3, 15, 0, 0, 0)

    // ── Empty Day ─────────────────────────────────────────────────────────────────────────────

    /** A day with no health data at all. Mirrors iOS `ExportFixtures.emptyDay`. */
    val emptyDay: HealthData = HealthData(date = referenceDate)

    // ── Partial Day ───────────────────────────────────────────────────────────────────────────

    /**
     * A day with only sleep and activity data. Mirrors iOS `ExportFixtures.partialDay`.
     *
     * iOS uses `coreSleep = 4.0h`; Android equivalent is `lightSleep = 4.0h`
     * (Health Connect "light" stage = iOS/Apple Watch "core" stage).
     */
    val partialDay: HealthData = HealthData(
        date = referenceDate,
        sleep = SleepData(
            totalDuration = 7.hours + 30.minutes,
            deepSleep = 1.hours + 30.minutes,
            remSleep = 2.hours,
            lightSleep = 4.hours,            // iOS: coreSleep = 4.0h
        ),
        activity = ActivityData(
            steps = 8500,
            activeCalories = 350.0,
            exerciseMinutes = 32.0,
            flightsClimbed = 5,
            walkingRunningDistance = 6200.0, // meters
        ),
    )

    // ── Fully Populated Day ───────────────────────────────────────────────────────────────────

    /**
     * A day with all categories populated. Mirrors iOS `ExportFixtures.fullDay`.
     *
     * iOS/Android differences:
     *  - iOS `activity.vo2Max = 42.5`    → Android `mobility.vo2Max = 42.5`
     *    (JSON exporter dual-writes to both `activity.vo2Max` AND `mobility.vo2Max`)
     *  - iOS `activity.standHours = 11`  → not available from Health Connect (omitted)
     *  - iOS `sleep.coreSleep = 4.0h`    → Android `sleep.lightSleep = 4.0h`
     *  - iOS `hearing`                   → not yet supported on Android (omitted)
     */
    val fullDay: HealthData = HealthData(
        date = referenceDate,
        sleep = SleepData(
            totalDuration = 7.hours + 45.minutes,
            deepSleep = 1.hours + 30.minutes,
            remSleep = 2.hours + 15.minutes,
            lightSleep = 4.hours,            // iOS: coreSleep
            awakeTime = 15.minutes,
            inBedTime = 8.hours,
            sessionStart = referenceDateTime.minusHours(8),
            sessionEnd = referenceDateTime,
        ),
        activity = ActivityData(
            steps = 12500,
            activeCalories = 520.0,
            basalEnergyBurned = 1650.0,
            exerciseMinutes = 45.0,
            flightsClimbed = 8,
            walkingRunningDistance = 9500.0, // meters
            cyclingDistance = 3200.0,        // meters
        ),
        heart = HeartData(
            restingHeartRate = 58.0,
            averageHeartRate = 72.0,
            heartRateMin = 52.0,
            heartRateMax = 155.0,
            hrv = 42.0,
        ),
        vitals = VitalsData(
            respiratoryRateAvg = 15.0,
            respiratoryRateMin = 12.0,
            respiratoryRateMax = 18.0,
            bloodOxygenAvg = 0.97,           // fraction; iOS contract stores fraction
            bloodOxygenMin = 0.94,
            bloodOxygenMax = 0.99,
        ),
        body = BodyData(
            weight = 75.0,                   // kg
            bodyFatPercentage = 0.18,        // ratio → 18%
            height = 1.78,                   // meters
            bmi = 23.7,
        ),
        nutrition = NutritionData(
            dietaryEnergy = 2100.0,
            protein = 120.0,
            carbohydrates = 250.0,
            fat = 70.0,
            fiber = 25.0,
            sugar = 45.0,
            water = 2.5,
            caffeine = 200.0,
        ),
        mindfulness = MindfulnessData(
            mindfulnessMinutes = 15.0,
            mindfulSessions = 2,
        ),
        mobility = MobilityData(
            walkingSpeed = 1.4,
            vo2Max = 42.5,                   // iOS: under activity.vo2Max
        ),
        workouts = listOf(
            WorkoutData(
                workoutType = WorkoutType.RUNNING,
                startTime = referenceDateTime,
                duration = 30.minutes,
                calories = 300.0,
                distance = 5000.0,           // meters
            ),
        ),
    )

    // ── Fully Populated Day with Granular Data ────────────────────────────────────────────────

    /**
     * Same as [fullDay] but with time-series sample arrays populated.
     * Mirrors iOS `ExportFixtures.fullDayGranular`.
     */
    val fullDayGranular: HealthData = run {
        val h6  = referenceDateTime.plusHours(6)
        val h9  = referenceDateTime.plusHours(9)
        val h12 = referenceDateTime.plusHours(12)
        val h15 = referenceDateTime.plusHours(15)
        val h20 = referenceDateTime.plusHours(20)

        val bedtime = referenceDateTime.minusHours(8) // 16:00 day before

        fullDay.copy(
            heart = fullDay.heart.copy(
                samples = listOf(
                    TimestampedSample(h6,  55.0),
                    TimestampedSample(h9,  72.0),
                    TimestampedSample(h12, 85.0),
                    TimestampedSample(h15, 68.0),
                    TimestampedSample(h20, 60.0),
                ),
                hrvSamples = listOf(
                    TimestampedSample(h6,  45.0),
                    TimestampedSample(h20, 38.0),
                ),
            ),
            sleep = fullDay.sleep.copy(
                stages = listOf(
                    SleepStageEntry(
                        startTime = bedtime,
                        endTime   = bedtime.plusMinutes(90),
                        stage     = "deep",
                    ),
                    SleepStageEntry(
                        startTime = bedtime.plusMinutes(90),
                        endTime   = bedtime.plusMinutes(210),
                        stage     = "rem",
                    ),
                    SleepStageEntry(
                        startTime = bedtime.plusMinutes(210),
                        endTime   = bedtime.plusMinutes(450),
                        stage     = "light",
                    ),
                    SleepStageEntry(
                        startTime = bedtime.plusMinutes(450),
                        endTime   = bedtime.plusMinutes(465),
                        stage     = "awake",
                    ),
                ),
            ),
            vitals = fullDay.vitals.copy(
                bloodOxygenSamples = listOf(
                    TimestampedSample(h6,  0.96),
                    TimestampedSample(h12, 0.98),
                    TimestampedSample(h20, 0.97),
                ),
                bloodGlucoseSamples = listOf(
                    TimestampedSample(h9,  90.0),
                    TimestampedSample(h15, 110.0),
                ),
                respiratoryRateSamples = listOf(
                    TimestampedSample(h6,  14.0),
                    TimestampedSample(h12, 16.0),
                ),
            ),
        )
    }

    // ── Edge Case Day ─────────────────────────────────────────────────────────────────────────

    /**
     * A day with edge cases: zero-value sleep, zero steps, body temperature only.
     * Mirrors iOS `ExportFixtures.edgeCaseDay` (excluding Apple-only state-of-mind entries).
     */
    val edgeCaseDay: HealthData = HealthData(
        date = referenceDate,
        sleep = SleepData(
            totalDuration = kotlin.time.Duration.ZERO,  // no sleep recorded → hasData=false
        ),
        activity = ActivityData(
            steps = 0,
        ),
        heart = HeartData(
            restingHeartRate = null,
            averageHeartRate = 0.0,
        ),
        vitals = VitalsData(
            bodyTemperatureAvg = 36.5,  // only temperature recorded
        ),
        mindfulness = MindfulnessData(
            mindfulnessMinutes = 15.0,  // mindfulness still present
        ),
    )
}
