package com.healthmd.data.export

import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import java.time.Duration
import java.time.Instant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** Successor-only source-clock construction; never guesses an instant from a local date-time. */
internal class WakeDateJsonDocument(private val context: AndroidCaptureContext) {
    init {
        require(context.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS &&
            context.exportProfileID == "android-sleep-v6") { "wake-date capture authority is incompatible" }
    }

    val timeContext: JsonObject = buildJsonObject {
        put("calendar_timezone", context.zoneId.id)
        put("timestamp_timezone", "UTC")
        put("sleep_day_attribution", "morning_ends")
        put("sleep_owner_day_rule", "session_end_date")
        put("sleep_interval_clipping", "none")
    }

    fun sleepClocks(data: HealthData): Pair<Instant?, Instant?> {
        require(data.sleep.stages.none { it.stage.equals("core", ignoreCase = true) }) {
            "wake-date native sleep stage identity is incompatible"
        }
        val intervals = data.sleep.sessions.map { session ->
            val start = instant(session.exactStartTime)
            val end = instant(session.exactEndTime)
            require(runCatching { end.atZone(context.zoneId).toLocalDate() == data.date }.getOrDefault(false)) {
                "wake-date native session owner is incompatible"
            }
            start to end
        }.filter { (start, end) -> start < end }.ifEmpty {
            data.sleep.stages.map { stage -> instant(stage.exactStartTime) to instant(stage.exactEndTime) }
                .filter { (start, end) -> start < end }
        }
        val start = intervals.minOfOrNull { it.first }
        val end = intervals.maxOfOrNull { it.second }
        if (data.sleep.sessionStart != null) require(start != null && runCatching {
            start.atZone(context.zoneId).toLocalDateTime().withNano(0) == data.sleep.sessionStart.withNano(0)
        }.getOrDefault(false)) {
            "wake-date native summary clock is incompatible"
        }
        if (data.sleep.sessionEnd != null) require(end != null && runCatching {
            end.atZone(context.zoneId).toLocalDateTime().withNano(0) == data.sleep.sessionEnd.withNano(0) &&
                end.atZone(context.zoneId).toLocalDate() == data.date
        }.getOrDefault(false)) {
            "wake-date native summary clock is incompatible"
        }
        if (end != null) require(runCatching {
            end.atZone(context.zoneId).toLocalDate() == data.date
        }.getOrDefault(false)) {
            "wake-date native session owner is incompatible"
        }
        return start to end
    }

    fun finish(payload: JsonObject, data: HealthData): JsonObject {
        val (start, end) = sleepClocks(data)
        val source = payload.toMutableMap()
        (source["sleep"] as? JsonObject)?.let { original ->
            val sleep = original.toMutableMap()
            if ("bedtimeISO" in sleep) {
                sleep["bedtimeISO"] = JsonPrimitive(start?.toString() ?: unavailable())
            }
            if ("wakeTimeISO" in sleep) {
                sleep["wakeTimeISO"] = JsonPrimitive(end?.toString() ?: unavailable())
            }
            source["sleep"] = JsonObject(sleep)
        }
        val canonical = canonicalize(JsonObject(source), emptyList()) as JsonObject
        return buildJsonObject {
            canonical.forEach { (key, value) -> if (key != "units") put(key, value) }
            put("date", data.date.toString())
            put("schema", "healthmd.health_data")
            put("schema_version", 6)
            put("schema_profile", "android-sleep-v6")
            put("time_context", timeContext)
            put("unit_system", "metric")
            // Bound summary units are assembled by the profile-aware semantic/render consumer.
            put("units", buildJsonObject {})
        }
    }

    private fun canonicalize(value: JsonElement, path: List<String>): JsonElement = when (value) {
        is JsonArray -> JsonArray(value.map { canonicalize(it, path) })
        is JsonObject -> {
            val children = value.mapValues { (key, child) ->
                if (key in OPAQUE_SOURCE_FIELDS) child else canonicalize(child, path + key)
            }.toMutableMap()
            TIMESTAMP_FIELDS.forEach { (field, exactField) ->
                if (field in value) children[field] = JsonPrimitive(instant(value[exactField]).toString())
            }
            if (path.lastOrNull() == "segments") {
                for ((field, exactField) in listOf("startTime" to "exactStartTime", "endTime" to "exactEndTime")) {
                    if (field in value) children[field] = JsonPrimitive(instant(value[exactField]).toString())
                }
            }
            DERIVED_DURATION_FIELDS[path.lastOrNull()]?.let { field ->
                val elapsed = Duration.between(instant(value["exactStartTime"]), instant(value["exactEndTime"]))
                if (elapsed.isNegative || elapsed.isZero) children.remove(field)
                else children[field] = JsonPrimitive(elapsed.seconds.toDouble() + elapsed.nano / 1_000_000_000.0)
            }
            JsonObject(children)
        }
        else -> value
    }

    private fun instant(encoded: JsonElement?): Instant {
        val timestamp = encoded as? JsonObject ?: unavailable()
        val second = (timestamp["epochSecond"] as? JsonPrimitive)?.longOrNull ?: unavailable()
        val nano = (timestamp["nano"] as? JsonPrimitive)?.intOrNull ?: unavailable()
        val offset = timestamp["offset"]?.let {
            if (it == JsonNull) null else (it as? JsonPrimitive)?.contentOrNull ?: unavailable()
        }
        return instant(ExactSourceTimestamp(second, nano, offset))
    }

    private fun instant(timestamp: ExactSourceTimestamp?): Instant {
        if (timestamp == null || timestamp.nano !in 0..999_999_999) unavailable()
        return runCatching {
            // Validate a supplied offset as source metadata, without using it to invent the instant.
            timestamp.toIso8601()
            timestamp.instant()
        }.getOrElse { unavailable() }
    }

    private fun unavailable(): Nothing = throw IllegalArgumentException("wake-date exact source timestamp is unavailable")

    companion object {
        // Only writer-derived interval durations; native workout/split aggregates stay native.
        private val DERIVED_DURATION_FIELDS = mapOf(
            "sleepStages" to "durationSeconds", "segments" to "durationSeconds", "laps" to "duration",
        )
        private val TIMESTAMP_FIELDS = mapOf(
            "timestamp" to "exactTime",
            "startDate" to "exactStartTime",
            "endDate" to "exactEndTime",
            "startTimeISO" to "exactStartTime",
            "endTimeISO" to "exactEndTime",
        )
        private val OPAQUE_SOURCE_FIELDS = setOf(
            "metadata", "context", "identity", "exactTime", "exactEndTime", "exactStartTime", "fhirResourceJson",
        )
    }
}
