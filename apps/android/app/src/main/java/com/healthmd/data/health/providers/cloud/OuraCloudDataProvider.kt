package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.seconds

class OuraCloudDataProvider(
    apiClient: CloudHealthApiClient,
    private val baseUrl: String = BASE_URL,
) : CloudHealthDataProvider("oura", apiClient) {
    override suspend fun fetchHealthData(date: LocalDate): HealthData {
        val nextDate = date.plusDays(1)
        val activity = runCatching { fetchActivity(date) }.getOrDefault(ActivityData())
        val sleep = runCatching { fetchSleep(date) }.getOrDefault(SleepData())
        val heart = runCatching { fetchHeart(date, nextDate) }.getOrDefault(HeartData())
        val workouts = runCatching { fetchWorkouts(date) }.getOrDefault(emptyList())
        return HealthData(
            date = date,
            sleep = sleep,
            activity = activity,
            heart = heart,
            workouts = workouts,
        )
    }

    private suspend fun fetchActivity(date: LocalDate): ActivityData {
        val root = getJson(
            url = "$baseUrl/daily_activity",
            query = mapOf("start_date" to date.toString(), "end_date" to date.toString()),
        ).obj() ?: return ActivityData()
        val item = root.firstArray("data").firstOrNull()?.obj() ?: return ActivityData()
        return ActivityData(
            steps = item.int("steps"),
            activeCalories = item.double("active_calories"),
            totalCalories = item.double("total_calories"),
            walkingRunningDistance = item.double("equivalent_walking_distance") ?: item.double("meters_to_target"),
        )
    }

    private suspend fun fetchSleep(date: LocalDate): SleepData {
        val zone = ZoneId.systemDefault()
        val root = getJson(
            url = "$baseUrl/sleep",
            query = mapOf("start_date" to date.toString(), "end_date" to date.toString()),
        ).obj() ?: return SleepData()
        val items = root.firstArray("data").mapNotNull { it.obj() }
        if (items.isEmpty()) return SleepData()

        var totalSeconds = 0.0
        var deepSeconds = 0.0
        var remSeconds = 0.0
        var lightSeconds = 0.0
        var awakeSeconds = 0.0
        val sessions = items.mapNotNull { item ->
            totalSeconds += item.double("total_sleep_duration") ?: 0.0
            deepSeconds += item.double("deep_sleep_duration") ?: 0.0
            remSeconds += item.double("rem_sleep_duration") ?: 0.0
            lightSeconds += item.double("light_sleep_duration") ?: 0.0
            awakeSeconds += item.double("awake_time") ?: 0.0
            val start = isoToLocalDateTime(item.string("bedtime_start"), zone)
            val end = isoToLocalDateTime(item.string("bedtime_end"), zone)
            if (start != null && end != null) {
                SleepSessionEntry(
                    startTime = start,
                    endTime = end,
                    source = "Oura",
                    metadata = mapOfNotNullValues(
                        "provider" to "Oura",
                        "id" to item.string("id"),
                        "readiness_score_delta" to item.string("readiness_score_delta"),
                    ),
                )
            } else null
        }
        return SleepData(
            totalDuration = totalSeconds.seconds,
            deepSleep = deepSeconds.seconds,
            remSleep = remSeconds.seconds,
            lightSleep = lightSeconds.seconds,
            awakeTime = awakeSeconds.seconds,
            inBedTime = (totalSeconds + awakeSeconds).seconds,
            sessions = sessions,
            sessionStart = sessions.minByOrNull { it.startTime }?.startTime,
            sessionEnd = sessions.maxByOrNull { it.endTime }?.endTime,
        )
    }

    private suspend fun fetchHeart(startDate: LocalDate, endDate: LocalDate): HeartData {
        val zone = ZoneId.systemDefault()
        val root = getJson(
            url = "$baseUrl/heartrate",
            query = mapOf(
                "start_datetime" to startDate.atStartOfDay(zone).toInstant().toString(),
                "end_datetime" to endDate.atStartOfDay(zone).toInstant().toString(),
            ),
        ).obj() ?: return HeartData()
        val samples = root.firstArray("data").mapNotNull { element ->
            val item = element.obj() ?: return@mapNotNull null
            val time = isoToLocalDateTime(item.string("timestamp"), zone) ?: return@mapNotNull null
            val bpm = item.double("bpm") ?: return@mapNotNull null
            TimestampedSample(
                time = time,
                value = bpm,
                source = "Oura",
                metadata = mapOfNotNullValues("source" to item.string("source")),
            )
        }
        val values = samples.map { it.value }
        return HeartData(
            averageHeartRate = values.takeIf { it.isNotEmpty() }?.average(),
            heartRateMin = values.minOrNull(),
            heartRateMax = values.maxOrNull(),
            samples = samples,
        )
    }

    private suspend fun fetchWorkouts(date: LocalDate): List<WorkoutData> {
        val zone = ZoneId.systemDefault()
        val root = getJson(
            url = "$baseUrl/workout",
            query = mapOf("start_date" to date.toString(), "end_date" to date.toString()),
        ).obj() ?: return emptyList()
        return root.firstArray("data").mapNotNull { element ->
            val item = element.obj() ?: return@mapNotNull null
            val start = isoToLocalDateTime(item.string("start_datetime"), zone) ?: return@mapNotNull null
            val end = isoToLocalDateTime(item.string("end_datetime"), zone)
            val durationSeconds = item.double("duration") ?: item.double("duration_seconds") ?: 0.0
            WorkoutData(
                id = item.string("id") ?: "oura-${start}",
                workoutType = mapWorkoutType(item.string("activity")),
                startTime = start,
                endTime = end,
                duration = durationSeconds.seconds,
                calories = item.double("calories"),
                distance = item.double("distance"),
                metadata = mapOfNotNullValues(
                    "provider" to "Oura",
                    "activity" to item.string("activity"),
                    "intensity" to item.string("intensity"),
                ),
            )
        }
    }

    private fun mapWorkoutType(activity: String?): WorkoutType = when (activity?.lowercase()) {
        "running", "run" -> WorkoutType.RUNNING
        "walking", "walk" -> WorkoutType.WALKING
        "cycling", "bike", "biking" -> WorkoutType.CYCLING
        "swimming" -> WorkoutType.SWIMMING
        "hiking" -> WorkoutType.HIKING
        "yoga" -> WorkoutType.YOGA
        "strength_training" -> WorkoutType.STRENGTH_TRAINING
        else -> WorkoutType.OTHER
    }

    private fun mapOfNotNullValues(vararg pairs: Pair<String, String?>): Map<String, String> =
        pairs.mapNotNull { (key, value) -> value?.let { key to it } }.toMap()

    companion object {
        private const val BASE_URL = "https://api.ouraring.com/v2/usercollection"
    }
}
