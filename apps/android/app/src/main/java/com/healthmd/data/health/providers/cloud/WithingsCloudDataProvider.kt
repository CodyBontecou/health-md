package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import java.time.LocalDate
import kotlin.math.pow
import kotlin.time.Duration.Companion.seconds

class WithingsCloudDataProvider(
    apiClient: CloudHealthApiClient,
    private val baseUrl: String = BASE_URL,
) : CloudHealthDataProvider("withings", apiClient) {
    override suspend fun fetchHealthData(date: LocalDate): HealthData = HealthData(
        date = date,
        activity = runCatching { fetchActivity(date) }.getOrDefault(ActivityData()),
        sleep = runCatching { fetchSleep(date) }.getOrDefault(SleepData()),
        heart = runCatching { fetchHeart(date) }.getOrDefault(HeartData()),
        body = runCatching { fetchBody(date) }.getOrDefault(BodyData()),
    )

    private suspend fun fetchActivity(date: LocalDate): ActivityData {
        val root = getJson(
            url = "$baseUrl/v2/measure",
            query = mapOf(
                "action" to "getactivity",
                "startdateymd" to date.toString(),
                "enddateymd" to date.toString(),
                "data_fields" to "steps,distance,calories,totalcalories,elevation,hr_average,hr_min,hr_max",
            ),
        ).obj() ?: return ActivityData()
        val activity = root.obj("body")?.array("activities")?.firstOrNull()?.obj() ?: return ActivityData()
        return ActivityData(
            steps = activity.int("steps"),
            activeCalories = activity.double("calories"),
            totalCalories = activity.double("totalcalories"),
            walkingRunningDistance = activity.double("distance"),
            elevationGained = activity.double("elevation"),
        )
    }

    private suspend fun fetchSleep(date: LocalDate): SleepData {
        val root = getJson(
            url = "$baseUrl/v2/sleep",
            query = mapOf(
                "action" to "getsummary",
                "startdateymd" to date.toString(),
                "enddateymd" to date.toString(),
                "data_fields" to "deepsleepduration,lightsleepduration,remsleepduration,wakeupduration,wakeupcount,durationtosleep,durationtowakeup",
            ),
        ).obj() ?: return SleepData()
        val series = root.obj("body")?.array("series")?.mapNotNull { it.obj() }.orEmpty()
        if (series.isEmpty()) return SleepData()
        var deep = 0.0
        var light = 0.0
        var rem = 0.0
        var awake = 0.0
        for (item in series) {
            val data = item.obj("data") ?: continue
            deep += data.double("deepsleepduration") ?: 0.0
            light += data.double("lightsleepduration") ?: 0.0
            rem += data.double("remsleepduration") ?: 0.0
            awake += data.double("wakeupduration") ?: 0.0
        }
        return SleepData(
            totalDuration = (deep + light + rem).seconds,
            deepSleep = deep.seconds,
            lightSleep = light.seconds,
            remSleep = rem.seconds,
            awakeTime = awake.seconds,
            inBedTime = (deep + light + rem + awake).seconds,
        )
    }

    private suspend fun fetchHeart(date: LocalDate): HeartData {
        val activityRoot = getJson(
            url = "$baseUrl/v2/measure",
            query = mapOf(
                "action" to "getactivity",
                "startdateymd" to date.toString(),
                "enddateymd" to date.toString(),
                "data_fields" to "hr_average,hr_min,hr_max",
            ),
        ).obj()
        val activity = activityRoot?.obj("body")?.array("activities")?.firstOrNull()?.obj()
        val measureHeart = fetchMeasureValues(date).filterKeys { it == 11 }
        return HeartData(
            restingHeartRate = measureHeart[11]?.lastOrNull(),
            averageHeartRate = activity?.double("hr_average"),
            heartRateMin = activity?.double("hr_min"),
            heartRateMax = activity?.double("hr_max"),
        )
    }

    private suspend fun fetchBody(date: LocalDate): BodyData {
        val measures = fetchMeasureValues(date)
        return BodyData(
            weight = measures[1]?.lastOrNull(),
            height = measures[4]?.lastOrNull(),
            bodyFatPercentage = measures[6]?.lastOrNull(),
            leanBodyMass = measures[5]?.lastOrNull(),
        )
    }

    private suspend fun fetchMeasureValues(date: LocalDate): Map<Int, List<Double>> {
        val start = date.atStartOfDay().atZone(java.time.ZoneId.systemDefault()).toEpochSecond()
        val end = date.plusDays(1).atStartOfDay().atZone(java.time.ZoneId.systemDefault()).toEpochSecond()
        val root = getJson(
            url = "$baseUrl/measure",
            query = mapOf(
                "action" to "getmeas",
                "startdate" to start.toString(),
                "enddate" to end.toString(),
            ),
        ).obj() ?: return emptyMap()
        val result = mutableMapOf<Int, MutableList<Double>>()
        val groups = root.obj("body")?.array("measuregrps")?.mapNotNull { it.obj() }.orEmpty()
        for (group in groups) {
            for (measure in group.array("measures")?.mapNotNull { it.obj() }.orEmpty()) {
                val type = measure.int("type") ?: continue
                val rawValue = measure.double("value") ?: continue
                val unit = measure.int("unit") ?: 0
                result.getOrPut(type) { mutableListOf() } += rawValue * 10.0.pow(unit)
            }
        }
        return result
    }

    companion object {
        private const val BASE_URL = "https://wbsapi.withings.net"
    }
}
