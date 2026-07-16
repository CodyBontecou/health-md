package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.rawexport.RawPaginationSupport
import com.healthmd.rawexport.RawProviderTypeDefinition
import com.healthmd.rawexport.RawSnapshotRequest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlin.math.pow
import kotlin.time.Duration.Companion.seconds

class WithingsCloudDataProvider(
    apiClient: CloudHealthApiClient,
    private val baseUrl: String = BASE_URL,
) : CloudHealthDataProvider("withings", apiClient), CloudNativeRawPageProvider {
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
        val endDate = endInstant.minusNanos(1).atZone(zone).toLocalDate()
        RAW_IMPLEMENTED.filter { it.typeKey in selectedEndpointKeys }.forEach { endpoint ->
            val (url, baseQuery) = when (endpoint.typeKey) {
                ACTIVITY -> "$baseUrl/v2/measure" to mapOf(
                    "action" to "getactivity", "startdateymd" to startDate.toString(),
                    "enddateymd" to endDate.toString(),
                    "data_fields" to "steps,distance,calories,totalcalories,elevation,hr_average,hr_min,hr_max",
                )
                SLEEP -> "$baseUrl/v2/sleep" to mapOf(
                    "action" to "getsummary", "startdateymd" to startDate.toString(),
                    "enddateymd" to endDate.toString(),
                    "data_fields" to "deepsleepduration,lightsleepduration,remsleepduration,wakeupduration,wakeupcount,durationtosleep,durationtowakeup",
                )
                MEASURES -> "$baseUrl/measure" to mapOf(
                    "action" to "getmeas", "startdate" to startInstant.epochSecond.toString(),
                    "enddate" to endInstant.epochSecond.toString(),
                )
                else -> error("Unknown Withings endpoint")
            }
            streamPagedEndpoint(endpoint.typeKey, url, baseQuery, observerFor(endpoint.typeKey), onEndpointResult)
        }
    }

    private suspend fun streamPagedEndpoint(
        endpointKey: String,
        url: String,
        baseQuery: Map<String, String>,
        observer: CloudRawResponseObserver,
        onEndpointResult: suspend (CloudNativeEndpointResult) -> Unit,
    ) {
        var pages = 0
        var offset: String? = null
        val seenOffsets = mutableSetOf<String>()
        var failure: CloudNativeEndpointFailure? = null
        try {
            while (true) {
                val query = baseQuery.toMutableMap().apply { offset?.let { put("offset", it) } }
                val response = getNativePage(
                    url = url,
                    query = query,
                    pageOrdinal = pages + 1,
                    observer = observer,
                    acceptance = STATUS_ZERO,
                )
                pages++
                val body = response.json.obj()?.obj("body")
                val more = body?.withingsMore()
                if (more == false) break
                val candidate = body?.string("offset")?.takeIf(String::isNotBlank)
                if (more == null || candidate == null) {
                    failure = CloudNativeEndpointFailure(
                        "pagination_invalid",
                        "Withings pagination metadata was invalid.",
                        false,
                    )
                    break
                }
                if (!seenOffsets.add(candidate)) {
                    failure = CloudNativeEndpointFailure(
                        "pagination_cycle",
                        "Withings pagination cycle was stopped.",
                        false,
                    )
                    break
                }
                if (pages >= MAX_NATIVE_PAGES_PER_ENDPOINT) {
                    failure = CloudNativeEndpointFailure(
                        "pagination_cap",
                        "Withings pagination page cap was reached.",
                        false,
                    )
                    break
                }
                offset = candidate
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: CloudHealthApplicationException) {
            failure = CloudNativeEndpointFailure(
                "provider_application_error",
                "Withings rejected the native endpoint request.",
                false,
            )
        } catch (_: Exception) {
            failure = CloudNativeEndpointFailure("native_endpoint_failed", "Withings native endpoint request failed.")
        }
        onEndpointResult(CloudNativeEndpointResult(endpointKey, pages.toLong(), failure))
    }

    override suspend fun fetchHealthData(date: LocalDate): HealthData = HealthData(
        date = date,
        activity = runCatching { fetchActivity(date) }.getOrDefault(ActivityData()),
        sleep = runCatching { fetchSleep(date) }.getOrDefault(SleepData()),
        heart = runCatching { fetchHeart(date) }.getOrDefault(HeartData()),
        body = runCatching { fetchBody(date) }.getOrDefault(BodyData()),
    )

    private suspend fun fetchActivity(date: LocalDate): ActivityData {
        val root = getWithingsJson(
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
        val root = getWithingsJson(
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
        val activityRoot = getWithingsJson(
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
        val root = getWithingsJson(
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

    private suspend fun getWithingsJson(
        url: String,
        query: Map<String, String> = emptyMap(),
    ) = getJson(url, query, STATUS_ZERO)

    private fun kotlinx.serialization.json.JsonObject.withingsMore(): Boolean? =
        when (string("more")?.lowercase()) {
            "0", "false" -> false
            "1", "true" -> true
            else -> null
        }

    companion object {
        private const val BASE_URL = "https://wbsapi.withings.net"
        const val ACTIVITY = "withings/activity_summary"
        const val SLEEP = "withings/sleep_summary"
        const val MEASURES = "withings/measures"
        private val STATUS_ZERO = CloudRawResponseAcceptance { response ->
            response.jsonValid && response.json.obj()?.int("status") == 0
        }
        private val RAW_IMPLEMENTED = listOf(
            CloudRawMetrics.endpoint("withings", ACTIVITY, setOf("steps", "active_calories", "total_calories", "distance", "elevation_gained", "avg_hr", "min_hr", "max_hr"), RawPaginationSupport.NEXT_TOKEN, serverAggregation = true),
            CloudRawMetrics.endpoint("withings", SLEEP, CloudRawMetrics.sleep, RawPaginationSupport.NEXT_TOKEN, serverAggregation = true),
            CloudRawMetrics.endpoint("withings", MEASURES, setOf("resting_hr", "weight", "height", "body_fat", "lean_mass"), RawPaginationSupport.NEXT_TOKEN),
        )
        private val RAW_ENDPOINTS = RAW_IMPLEMENTED + CloudRawMetrics.unsupported(
            "withings",
            RAW_IMPLEMENTED.flatMap { it.metricIds }.toSet(),
        )
    }
}
