package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import com.healthmd.rawexport.RawPaginationSupport
import com.healthmd.rawexport.RawProviderTypeDefinition
import com.healthmd.rawexport.RawRangeBehavior
import com.healthmd.rawexport.RawSnapshotRequest
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlin.time.Duration.Companion.milliseconds

class WhoopCloudDataProvider(
    apiClient: CloudHealthApiClient,
    private val baseUrl: String = BASE_URL,
    private val clock: Clock? = null,
) : CloudHealthDataProvider("whoop", apiClient), CloudNativeRawPageProvider {
    override val rawProviderId: String = providerId
    override val rawFidelityDeclaration: CloudProviderFidelityDeclaration = fidelityDeclaration
    override val rawEndpointDefinitions: List<RawProviderTypeDefinition> = RAW_ENDPOINTS

    override suspend fun streamNativePages(
        request: RawSnapshotRequest,
        selectedEndpointKeys: Set<String>,
        observerFor: (String) -> CloudRawResponseObserver,
        onEndpointResult: suspend (CloudNativeEndpointResult) -> Unit,
    ) {
        val start = Instant.ofEpochSecond(request.startTime.epochSecond, request.startTime.nano.toLong()).toString()
        val end = Instant.ofEpochSecond(request.endTime.epochSecond, request.endTime.nano.toLong()).toString()
        // v2 recovery is an independent collection, not a cycle-ID fan-out request.
        listOf(CYCLE, RECOVERY, SLEEP, WORKOUT).filter { it in selectedEndpointKeys }.forEach { endpointKey ->
            onEndpointResult(readCollection(endpointKey, start, end, observerFor(endpointKey)))
        }
        if (BODY in selectedEndpointKeys) {
            var pages = 0L
            var failure: CloudNativeEndpointFailure? = null
            try {
                // Raw snapshots explicitly label this singleton unbounded_non_temporal.
                getNativePage("$baseUrl/user/measurement/body", pageOrdinal = 1, observer = observerFor(BODY))
                pages = 1
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                failure = CloudNativeEndpointFailure("native_endpoint_failed", "WHOOP body endpoint request failed.")
            }
            onEndpointResult(CloudNativeEndpointResult(BODY, pages, failure))
        }
    }

    /** Shared bounded traversal; a later failure never discards already captured pages. */
    private suspend fun readCollection(
        endpointKey: String,
        start: String,
        end: String,
        observer: CloudRawResponseObserver = CloudRawResponseObserver { },
        onPage: (JsonObject) -> Unit = { },
    ): CloudNativeEndpointResult {
        var pages = 0
        var nextToken: String? = null
        val seen = mutableSetOf<String>()
        var failure: CloudNativeEndpointFailure? = null
        try {
            while (true) {
                val query = mutableMapOf("start" to start, "end" to end, "limit" to "25").apply {
                    nextToken?.let { put("nextToken", it) }
                }
                val response = getNativePage(
                    "$baseUrl/${endpointKey.substringAfter("whoop/")}", query, pages + 1, observer,
                )
                pages++
                val root = requireNotNull(response.json.obj())
                requireNotNull(root.array("records"))
                onPage(root)
                val candidate = root.string("next_token")?.takeIf(String::isNotBlank)
                if (candidate == null) break
                if (!seen.add(candidate)) {
                    failure = CloudNativeEndpointFailure("pagination_cycle", "WHOOP pagination cycle was stopped.", false)
                    break
                }
                if (pages >= MAX_NATIVE_PAGES_PER_ENDPOINT) {
                    failure = CloudNativeEndpointFailure("pagination_cap", "WHOOP pagination page cap was reached.", false)
                    break
                }
                nextToken = candidate
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            failure = CloudNativeEndpointFailure("native_endpoint_failed", "WHOOP native endpoint request failed.")
        }
        return CloudNativeEndpointResult(endpointKey, pages.toLong(), failure)
    }

    private suspend fun fetchCollection(endpointKey: String, start: String, end: String): List<JsonObject> {
        val records = mutableListOf<JsonObject>()
        val identityKey = if (endpointKey == RECOVERY) "cycle_id" else "id"
        val seenIds = mutableSetOf<String>()
        readCollection(endpointKey, start, end, onPage = { page ->
            page.array("records")!!.mapNotNull { it.obj() }.forEach { record ->
                val identity = (record[identityKey] as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
                // Keep the first captured view; absent identities must not collapse unrelated records.
                // This applies only to compatibility projections, never authoritative raw pages.
                if (identity == null || seenIds.add(identity)) records += record
            }
        })
        return records
    }

    override suspend fun fetchHealthData(date: LocalDate): HealthData {
        // Freeze this read's calendar zone, not the singleton provider's creation-time zone.
        val captureClock = clock ?: Clock.systemDefaultZone()
        val zone = captureClock.zone
        val start = date.atStartOfDay(zone).toInstant().toString()
        val end = date.plusDays(1).atStartOfDay(zone).toInstant().toString()
        val sleep = fetchCollection(SLEEP, start, end)
        // Fetch once so daily energy and workout projections use the same provider snapshot.
        val workouts = fetchCollection(WORKOUT, start, end)
        val recoveries = fetchCollection(RECOVERY, start, end)
        return HealthData(
            date = date,
            sleep = mapSectionOrDefault(SleepData()) { mapSleep(sleep, zone) },
            activity = mapSectionOrDefault(ActivityData()) {
                ActivityData(activeCalories = workouts.mapNotNull {
                    it.obj("score")?.double("kilojoule")?.div(4.184)
                }.takeIf { it.isNotEmpty() }?.sum())
            },
            heart = mapSectionOrDefault(HeartData()) { mapRecovery(recoveries) },
            // WHOOP provides a current profile, not a historical body measurement.
            body = if (date == LocalDate.now(captureClock)) fetchBody() else BodyData(),
            workouts = mapSectionOrDefault(emptyList()) { mapWorkouts(workouts, zone) },
        )
    }

    private inline fun <T> mapSectionOrDefault(defaultValue: T, map: () -> T): T = try {
        map()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        defaultValue
    }

    private fun mapSleep(records: List<JsonObject>, zone: ZoneId): SleepData {
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
            val startTime = isoToLocalDateTime(sleep.string("start"), zone)
            val endTime = isoToLocalDateTime(sleep.string("end"), zone)
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

    private fun mapRecovery(records: List<JsonObject>): HeartData {
        // WHOOP collections are newest-first. Unscored recoveries have no score.
        val scores = records.mapNotNull { it.obj("score") }
        return HeartData(
            restingHeartRate = scores.firstNotNullOfOrNull { it.double("resting_heart_rate") },
            hrv = scores.firstNotNullOfOrNull { it.double("hrv_rmssd_milli") },
        )
    }

    private suspend fun fetchBody(): BodyData = try {
        val measurement = getJson("$baseUrl/user/measurement/body").obj()
        BodyData(
            height = measurement?.double("height_meter"),
            weight = measurement?.double("weight_kilogram"),
        )
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        BodyData()
    }

    private fun mapWorkouts(records: List<JsonObject>, zone: ZoneId): List<WorkoutData> = records.mapNotNull { workout ->
        val start = workout.string("start")?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: return@mapNotNull null
        val end = workout.string("end")?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: return@mapNotNull null
        if (end < start) return@mapNotNull null
        val score = workout.obj("score")
        WorkoutData(
            id = workout.string("id") ?: return@mapNotNull null,
            workoutType = mapSport(workout.string("sport_name")),
            startTime = start.atZone(zone).toLocalDateTime(),
            endTime = end.atZone(zone).toLocalDateTime(),
            // zone_durations are scored HR-zone coverage, not elapsed workout duration.
            duration = Duration.between(start, end).toMillis().milliseconds,
            calories = score?.double("kilojoule")?.div(4.184),
            distance = score?.double("distance_meter"),
            averageHeartRate = score?.double("average_heart_rate"),
            heartRateMax = score?.double("max_heart_rate"),
            metadata = mapOfNotNullValues(
                "provider" to "WHOOP",
                "score_state" to workout.string("score_state"),
                "sport_name" to workout.string("sport_name"),
            ),
        )
    }

    private fun mapSport(sportName: String?): WorkoutType = when (sportName?.lowercase(Locale.ROOT)) {
        "running" -> WorkoutType.RUNNING
        "cycling" -> WorkoutType.CYCLING
        "swimming" -> WorkoutType.SWIMMING
        "walking" -> WorkoutType.WALKING
        "hiking" -> WorkoutType.HIKING
        "weightlifting", "strength trainer", "strength training" -> WorkoutType.STRENGTH_TRAINING
        "yoga" -> WorkoutType.YOGA
        else -> WorkoutType.OTHER
    }

    private fun mapOfNotNullValues(vararg pairs: Pair<String, String?>): Map<String, String> =
        pairs.mapNotNull { (key, value) -> value?.let { key to it } }.toMap()

    companion object {
        private const val BASE_URL = "https://api.prod.whoop.com/developer/v2"
        const val CYCLE = "whoop/cycle"
        const val RECOVERY = "whoop/recovery"
        const val SLEEP = "whoop/activity/sleep"
        const val WORKOUT = "whoop/activity/workout"
        const val BODY = "whoop/body_measurement"
        private val RAW_IMPLEMENTED = listOf(
            CloudRawMetrics.endpoint("whoop", CYCLE, setOf("total_calories", "avg_hr", "max_hr"), RawPaginationSupport.NEXT_TOKEN),
            CloudRawMetrics.endpoint("whoop", RECOVERY, setOf("resting_hr", "hrv"), RawPaginationSupport.NEXT_TOKEN),
            CloudRawMetrics.endpoint("whoop", SLEEP, CloudRawMetrics.sleep, RawPaginationSupport.NEXT_TOKEN),
            CloudRawMetrics.endpoint("whoop", WORKOUT, CloudRawMetrics.workouts + setOf("active_calories", "avg_hr", "max_hr", "distance"), RawPaginationSupport.NEXT_TOKEN),
            CloudRawMetrics.endpoint("whoop", BODY, setOf("weight", "height")).copy(rangeBehavior = RawRangeBehavior.UNBOUNDED_NON_TEMPORAL),
        )
        private val RAW_ENDPOINTS = RAW_IMPLEMENTED + CloudRawMetrics.unsupported(
            "whoop",
            RAW_IMPLEMENTED.flatMap { it.metricIds }.toSet(),
        )
    }
}
