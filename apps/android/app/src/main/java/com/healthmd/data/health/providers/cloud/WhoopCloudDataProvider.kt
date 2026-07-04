package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

class WhoopCloudDataProvider(
    apiClient: CloudHealthApiClient,
    private val baseUrl: String = BASE_URL,
) : CloudHealthDataProvider("whoop", apiClient) {
    override suspend fun fetchHealthData(date: LocalDate): HealthData {
        val zone = ZoneId.systemDefault()
        val start = date.atStartOfDay(zone).toInstant().toString()
        val end = date.plusDays(1).atStartOfDay(zone).toInstant().toString()
        return HealthData(
            date = date,
            sleep = runCatching { fetchSleep(start, end) }.getOrDefault(SleepData()),
            activity = runCatching { fetchActivity(start, end) }.getOrDefault(ActivityData()),
            heart = runCatching { fetchRecovery(start, end) }.getOrDefault(HeartData()),
            body = runCatching { fetchBody() }.getOrDefault(BodyData()),
            workouts = runCatching { fetchWorkouts(start, end) }.getOrDefault(emptyList()),
        )
    }

    private suspend fun fetchSleep(start: String, end: String): SleepData {
        val root = getJson(
            "$baseUrl/activity/sleep",
            mapOf("start" to start, "end" to end),
        ).obj() ?: return SleepData()
        val records = root.array("records")?.mapNotNull { it.obj() }.orEmpty()
        if (records.isEmpty()) return SleepData()
        var inBedMs = 0L
        var asleepMs = 0L
        var remMs = 0L
        var deepMs = 0L
        var awakeMs = 0L
        val sessions = records.mapNotNull { sleep ->
            val score = sleep.obj("score")
            val stage = score?.obj("stage_summary")
            inBedMs += stage?.long("total_in_bed_time_milli") ?: 0L
            asleepMs += stage?.long("total_light_sleep_time_milli") ?: 0L
            remMs += stage?.long("total_rem_sleep_time_milli") ?: 0L
            deepMs += stage?.long("total_slow_wave_sleep_time_milli") ?: 0L
            awakeMs += stage?.long("total_awake_time_milli") ?: 0L
            val startTime = isoToLocalDateTime(sleep.string("start"))
            val endTime = isoToLocalDateTime(sleep.string("end"))
            if (startTime != null && endTime != null) {
                SleepSessionEntry(
                    startTime = startTime,
                    endTime = endTime,
                    source = "WHOOP",
                    metadata = mapOfNotNullValues(
                        "provider" to "WHOOP",
                        "id" to sleep.string("id"),
                        "score_state" to sleep.string("score_state"),
                    ),
                )
            } else null
        }
        return SleepData(
            totalDuration = (asleepMs + remMs + deepMs).milliseconds,
            lightSleep = asleepMs.milliseconds,
            remSleep = remMs.milliseconds,
            deepSleep = deepMs.milliseconds,
            awakeTime = awakeMs.milliseconds,
            inBedTime = inBedMs.milliseconds,
            sessions = sessions,
            sessionStart = sessions.minByOrNull { it.startTime }?.startTime,
            sessionEnd = sessions.maxByOrNull { it.endTime }?.endTime,
        )
    }

    private suspend fun fetchActivity(start: String, end: String): ActivityData {
        val workouts = getJson("$baseUrl/activity/workout", mapOf("start" to start, "end" to end))
            .obj()?.array("records")?.mapNotNull { it.obj() }.orEmpty()
        val calories = workouts.sumOf { it.obj("score")?.double("kilojoule")?.div(4.184) ?: 0.0 }
        return ActivityData(activeCalories = calories.takeIf { it > 0.0 })
    }

    private suspend fun fetchRecovery(start: String, end: String): HeartData {
        val cycles = getJson("$baseUrl/cycle", mapOf("start" to start, "end" to end))
            .obj()?.array("records")?.mapNotNull { it.obj() }.orEmpty()
        val cycleIds = cycles.mapNotNull { it.string("id") }
        val recoveries = cycleIds.mapNotNull { id ->
            runCatching { getJson("$baseUrl/recovery", mapOf("cycleId" to id)).obj()?.array("records")?.firstOrNull()?.obj() }.getOrNull()
        }
        val scores = recoveries.mapNotNull { it.obj("score") }
        val restingHr = scores.mapNotNull { it.double("resting_heart_rate") }.lastOrNull()
        val hrv = scores.mapNotNull { it.double("hrv_rmssd_milli") }.lastOrNull()
        return HeartData(restingHeartRate = restingHr, hrv = hrv)
    }

    private suspend fun fetchBody(): BodyData {
        val measurement = getJson("$baseUrl/user/measurement/body").obj() ?: return BodyData()
        return BodyData(
            height = measurement.double("height_meter"),
            weight = measurement.double("weight_kilogram"),
        )
    }

    private suspend fun fetchWorkouts(start: String, end: String): List<WorkoutData> {
        val records = getJson("$baseUrl/activity/workout", mapOf("start" to start, "end" to end))
            .obj()?.array("records")?.mapNotNull { it.obj() }.orEmpty()
        return records.mapNotNull { workout ->
            val startTime = isoToLocalDateTime(workout.string("start")) ?: return@mapNotNull null
            val endTime = isoToLocalDateTime(workout.string("end"))
            val score = workout.obj("score")
            WorkoutData(
                id = workout.string("id") ?: "whoop-$startTime",
                workoutType = mapSport(workout.int("sport_id")),
                startTime = startTime,
                endTime = endTime,
                duration = ((score?.long("zone_duration") ?: 0L) / 1000L).seconds,
                calories = score?.double("kilojoule")?.div(4.184),
                distance = score?.double("distance_meter"),
                averageHeartRate = score?.double("average_heart_rate"),
                heartRateMax = score?.double("max_heart_rate"),
                metadata = mapOfNotNullValues(
                    "provider" to "WHOOP",
                    "score_state" to workout.string("score_state"),
                ),
            )
        }
    }

    private fun mapSport(sportId: Int?): WorkoutType = when (sportId) {
        0 -> WorkoutType.OTHER
        1 -> WorkoutType.RUNNING
        44 -> WorkoutType.CYCLING
        48 -> WorkoutType.SWIMMING
        49 -> WorkoutType.WALKING
        52 -> WorkoutType.HIKING
        63 -> WorkoutType.STRENGTH_TRAINING
        84 -> WorkoutType.YOGA
        else -> WorkoutType.OTHER
    }

    private fun mapOfNotNullValues(vararg pairs: Pair<String, String?>): Map<String, String> =
        pairs.mapNotNull { (key, value) -> value?.let { key to it } }.toMap()

    companion object {
        private const val BASE_URL = "https://api.prod.whoop.com/developer/v1"
    }
}
