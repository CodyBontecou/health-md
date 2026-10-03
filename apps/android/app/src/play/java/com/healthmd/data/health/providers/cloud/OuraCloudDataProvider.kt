package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import com.healthmd.rawexport.RawPaginationSupport
import com.healthmd.rawexport.RawProviderTypeDefinition
import com.healthmd.rawexport.RawSnapshotRequest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlin.time.Duration.Companion.seconds

class OuraCloudDataProvider(
    apiClient: CloudHealthApiClient,
    private val baseUrl: String = BASE_URL,
) : CloudHealthDataProvider("oura", apiClient), CloudNativeRawPageProvider {
    override val rawProviderId: String = providerId
    override val rawFidelityDeclaration: CloudProviderFidelityDeclaration = fidelityDeclaration
    override val rawEndpointDefinitions: List<RawProviderTypeDefinition> = RAW_ENDPOINTS

    override suspend fun streamNativePages(
        request: RawSnapshotRequest,
        selectedEndpointKeys: Set<String>,
        observerFor: (String) -> CloudRawResponseObserver,
        onEndpointResult: suspend (CloudNativeEndpointResult) -> Unit,
    ) {
        val zone = request.calendarZoneId?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneId.of("UTC")
        val startInstant = Instant.ofEpochSecond(request.startTime.epochSecond, request.startTime.nano.toLong())
        val endInstant = Instant.ofEpochSecond(request.endTime.epochSecond, request.endTime.nano.toLong())
        val startDate = startInstant.atZone(zone).toLocalDate()
        val endDateInclusive = endInstant.minusNanos(1).atZone(zone).toLocalDate()
        RAW_IMPLEMENTED.filter { it.typeKey in selectedEndpointKeys }.forEach { endpoint ->
            var pages = 0
            var nextToken: String? = null
            val seenTokens = mutableSetOf<String>()
            var failure: CloudNativeEndpointFailure? = null
            try {
                while (true) {
                    val query = when (endpoint.typeKey) {
                        DAILY_ACTIVITY, SLEEP, WORKOUT -> mapOf(
                            "start_date" to startDate.toString(),
                            "end_date" to endDateInclusive.toString(),
                        )
                        HEARTRATE -> mapOf(
                            "start_datetime" to startInstant.toString(),
                            "end_datetime" to endInstant.toString(),
                        )
                        else -> error("Unknown Oura endpoint")
                    }.toMutableMap().apply { nextToken?.let { put("next_token", it) } }
                    val response = getNativePage(
                        url = "$baseUrl/${endpoint.typeKey.substringAfter('/')}",
                        query = query,
                        pageOrdinal = pages + 1,
                        observer = observerFor(endpoint.typeKey),
                    )
                    pages++
                    val candidate = response.json.obj()?.string("next_token")?.takeIf(String::isNotBlank)
                    if (candidate == null) break
                    if (!seenTokens.add(candidate)) {
                        failure = CloudNativeEndpointFailure("pagination_cycle", "Oura pagination cycle was stopped.", false)
                        break
                    }
                    if (pages >= MAX_NATIVE_PAGES_PER_ENDPOINT) {
                        failure = CloudNativeEndpointFailure("pagination_cap", "Oura pagination page cap was reached.", false)
                        break
                    }
                    nextToken = candidate
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                failure = CloudNativeEndpointFailure("native_endpoint_failed", "Oura native endpoint request failed.")
            }
            onEndpointResult(CloudNativeEndpointResult(endpoint.typeKey, pages.toLong(), failure))
        }
    }

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
        const val DAILY_ACTIVITY = "oura/daily_activity"
        const val SLEEP = "oura/sleep"
        const val HEARTRATE = "oura/heartrate"
        const val WORKOUT = "oura/workout"
        private val RAW_IMPLEMENTED = listOf(
            CloudRawMetrics.endpoint("oura", DAILY_ACTIVITY, setOf("steps", "active_calories", "total_calories", "distance"), RawPaginationSupport.NEXT_TOKEN, serverAggregation = true),
            CloudRawMetrics.endpoint("oura", SLEEP, CloudRawMetrics.sleep, RawPaginationSupport.NEXT_TOKEN),
            CloudRawMetrics.endpoint("oura", HEARTRATE, setOf("avg_hr", "min_hr", "max_hr"), RawPaginationSupport.NEXT_TOKEN),
            CloudRawMetrics.endpoint("oura", WORKOUT, CloudRawMetrics.workouts, RawPaginationSupport.NEXT_TOKEN),
        )
        private val RAW_ENDPOINTS = RAW_IMPLEMENTED + CloudRawMetrics.unsupported(
            "oura",
            RAW_IMPLEMENTED.flatMap { it.metricIds }.toSet(),
        )
    }
}
