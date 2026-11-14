package com.healthmd.testing

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.VitalsData
import java.time.LocalDate
import kotlin.math.roundToInt
import kotlin.time.Duration.Companion.minutes

/**
 * Synthetic, deterministic health days for [TestMode]. Values vary by date so a week of notes
 * looks plausible, and the same date always yields the same values across runs. No value is
 * derived from a real person's data.
 */
object TestModeHealthFixtures {
    /** Days before today that fixture data starts; mirrors a recently installed tracker. */
    const val HISTORY_DAYS = 30L

    fun day(date: LocalDate): HealthData {
        val v = variation(date)
        val sleepMinutes = 420 + v * 9 // 7h00 - 8h21
        return HealthData(
            date = date,
            sleep = SleepData(
                totalDuration = sleepMinutes.minutes,
                deepSleep = (sleepMinutes * 0.18).roundToInt().minutes,
                remSleep = (sleepMinutes * 0.22).roundToInt().minutes,
                lightSleep = (sleepMinutes * 0.55).roundToInt().minutes,
                awakeTime = (sleepMinutes * 0.05).roundToInt().minutes,
                sessionStart = date.minusDays(1).atTime(23, 10 + v),
                sessionEnd = date.minusDays(1).atTime(23, 10 + v).plusMinutes(sleepMinutes.toLong()),
            ),
            activity = ActivityData(
                steps = 6_400 + v * 410,
                activeCalories = 380.0 + v * 22,
                exerciseMinutes = 24.0 + v * 3,
                flightsClimbed = 6 + v % 5,
                walkingRunningDistance = 4_800.0 + v * 310,
            ),
            heart = HeartData(
                restingHeartRate = 56.0 + v % 4,
                averageHeartRate = 71.0 + v % 6,
                hrv = 44.0 + v * 1.5,
                heartRateMin = 52.0 + v % 3,
                heartRateMax = 132.0 + v * 2,
            ),
            vitals = VitalsData(
                respiratoryRateAvg = 14.0 + (v % 3) * 0.4,
                bloodOxygenAvg = 0.96 + (v % 3) * 0.01,
            ),
            body = BodyData(weight = 70.0 + (v % 5) * 0.2),
        )
    }

    fun earliestDate(today: LocalDate = LocalDate.now()): LocalDate = today.minusDays(HISTORY_DAYS)

    /** 0..9, stable for a date. */
    private fun variation(date: LocalDate): Int = Math.floorMod(date.toEpochDay() * 7 + 3, 10L).toInt()
}
