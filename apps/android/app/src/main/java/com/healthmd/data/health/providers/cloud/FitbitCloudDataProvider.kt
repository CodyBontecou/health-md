package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.TimestampedSample
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes

class FitbitCloudDataProvider(
    apiClient: CloudHealthApiClient,
    private val baseUrl: String = BASE_URL,
) : CloudHealthDataProvider("fitbit", apiClient) {
    override suspend fun fetchHealthData(date: LocalDate): HealthData = HealthData(
        date = date,
        activity = runCatching { fetchActivity(date) }.getOrDefault(ActivityData()),
        sleep = runCatching { fetchSleep(date) }.getOrDefault(SleepData()),
        heart = runCatching { fetchHeart(date) }.getOrDefault(HeartData()),
        body = runCatching { fetchBody(date) }.getOrDefault(BodyData()),
    )

    private suspend fun fetchActivity(date: LocalDate): ActivityData {
        val root = getJson("$baseUrl/1/user/-/activities/date/$date.json").obj() ?: return ActivityData()
        val summary = root.obj("summary") ?: return ActivityData()
        val distances = summary.array("distances")?.mapNotNull { it.obj() }.orEmpty()
        val totalDistanceKm = distances.firstOrNull { it.string("activity") == "total" }?.double("distance")
        return ActivityData(
            steps = summary.int("steps"),
            activeCalories = summary.double("activityCalories"),
            totalCalories = summary.double("caloriesOut"),
            exerciseMinutes = summary.double("fairlyActiveMinutes")?.plus(summary.double("veryActiveMinutes") ?: 0.0),
            walkingRunningDistance = totalDistanceKm?.times(1000.0),
            flightsClimbed = summary.int("floors"),
        )
    }

    private suspend fun fetchSleep(date: LocalDate): SleepData {
        val root = getJson("$baseUrl/1.2/user/-/sleep/date/$date.json").obj() ?: return SleepData()
        val sleeps = root.array("sleep")?.mapNotNull { it.obj() }.orEmpty()
        if (sleeps.isEmpty()) return SleepData()
        var totalMs = 0L
        var deepMinutes = 0L
        var remMinutes = 0L
        var lightMinutes = 0L
        var wakeMinutes = 0L
        val sessions = sleeps.mapNotNull { sleep ->
            totalMs += sleep.long("duration") ?: 0L
            val summary = sleep.obj("levels")?.obj("summary")
            deepMinutes += summary?.obj("deep")?.long("minutes") ?: 0L
            remMinutes += summary?.obj("rem")?.long("minutes") ?: 0L
            lightMinutes += summary?.obj("light")?.long("minutes") ?: 0L
            wakeMinutes += summary?.obj("wake")?.long("minutes") ?: 0L
            val start = isoToLocalDateTime(sleep.string("startTime"))
            val end = isoToLocalDateTime(sleep.string("endTime"))
            if (start != null && end != null) {
                SleepSessionEntry(
                    startTime = start,
                    endTime = end,
                    source = "Fitbit",
                    metadata = mapOfNotNullValues(
                        "provider" to "Fitbit",
                        "log_id" to sleep.string("logId"),
                        "is_main_sleep" to sleep.string("isMainSleep"),
                    ),
                )
            } else null
        }
        return SleepData(
            totalDuration = totalMs.milliseconds,
            deepSleep = deepMinutes.minutes,
            remSleep = remMinutes.minutes,
            lightSleep = lightMinutes.minutes,
            awakeTime = wakeMinutes.minutes,
            inBedTime = (totalMs + wakeMinutes * 60_000L).milliseconds,
            sessions = sessions,
            sessionStart = sessions.minByOrNull { it.startTime }?.startTime,
            sessionEnd = sessions.maxByOrNull { it.endTime }?.endTime,
        )
    }

    private suspend fun fetchHeart(date: LocalDate): HeartData {
        val root = getJson("$baseUrl/1/user/-/activities/heart/date/$date/1d/1min.json").obj() ?: return HeartData()
        val dayValue = root.array("activities-heart")
            ?.firstOrNull()?.obj()
            ?.obj("value")
        val resting = dayValue?.double("restingHeartRate")
        val dataset = root.obj("activities-heart-intraday")?.array("dataset")?.mapNotNull { it.obj() }.orEmpty()
        val samples = dataset.mapNotNull { point ->
            val time = point.string("time")?.let { raw ->
                runCatching { LocalDateTime.of(date, LocalTime.parse(raw)) }.getOrNull()
            } ?: return@mapNotNull null
            val value = point.double("value") ?: return@mapNotNull null
            TimestampedSample(time = time, value = value, source = "Fitbit")
        }
        val values = samples.map { it.value }
        return HeartData(
            restingHeartRate = resting,
            averageHeartRate = values.takeIf { it.isNotEmpty() }?.average(),
            heartRateMin = values.minOrNull(),
            heartRateMax = values.maxOrNull(),
            samples = samples,
        )
    }

    private suspend fun fetchBody(date: LocalDate): BodyData {
        val root = getJson("$baseUrl/1/user/-/body/log/weight/date/$date.json").obj() ?: return BodyData()
        val latest = root.array("weight")?.mapNotNull { it.obj() }?.maxByOrNull { it.string("time") ?: "" }
        return BodyData(
            weight = latest?.double("weight"),
            bodyFatPercentage = latest?.double("fat"),
            bmi = latest?.double("bmi"),
        )
    }

    private fun mapOfNotNullValues(vararg pairs: Pair<String, String?>): Map<String, String> =
        pairs.mapNotNull { (key, value) -> value?.let { key to it } }.toMap()

    companion object {
        private const val BASE_URL = "https://api.fitbit.com"
    }
}
