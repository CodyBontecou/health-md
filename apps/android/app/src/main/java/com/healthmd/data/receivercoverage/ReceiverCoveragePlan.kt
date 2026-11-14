package com.healthmd.data.receivercoverage

import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlinx.serialization.json.*

/** Recovery-plan v2. Invalid restoration throws; callers preserve bytes and block execution. */
class ReceiverCoveragePlan private constructor(private val wire: JsonObject) {
    val selected: List<String> get() = strings(wire.getValue("selected"))
    val residual: List<String> get() = strings(wire.getValue("residual"))
    val candidates: List<String> get() = strings(request.getValue("candidates"))
    val today: String get() = text(request.getValue("today"))
    val calendarTimezone: String get() = text(request.getValue("calendar_timezone"))
    val destinationBinding: String get() = text(wire.getValue("destination_binding"))
    val status: String get() = text(wire.getValue("coverage_status"))
    private val request: JsonObject get() = wire.getValue("request").jsonObject
    fun json(): String = canonical(wire).toString()

    fun acknowledging(dates: Collection<String>): ReceiverCoveragePlan {
        if (!selected.containsAll(dates)) invalid()
        return ReceiverCoveragePlan(JsonObject(wire + ("residual" to array(residual.filterNot { it in dates })))).also { it.validate() }
    }

    private fun validate() {
        if (wire.keys != setOf("schema","schema_version","destination_binding","request","policy","refresh_recent_days",
                "today_refresh","selected","residual","coverage_status","coverage_response") ||
            request.keys != setOf("request_id","scope_id","calendar_timezone","candidates","today")) invalid()
        val policy = text(wire.getValue("policy"))
        val refresh = integer(wire.getValue("refresh_recent_days"))
        if (text(wire.getValue("schema")) != "healthmd.receiver_coverage.plan" || integer(wire.getValue("schema_version")) != 2 ||
            !Regex("[a-f0-9]{64}").matches(destinationBinding) || policy !in setOf("full_lookback","missing_days") ||
            refresh !in 0..30 || status !in setOf("not_requested","valid","fallback_full") ||
            (policy == "full_lookback") != (status == "not_requested") ||
            (status == "valid") != (wire.getValue("coverage_response") != JsonNull)) invalid()
        val evidence = wire.getValue("coverage_response").takeUnless { it == JsonNull }?.let(::text)
        if (selected != selection(request, refresh, boolean(wire.getValue("today_refresh")), evidence) ||
            residual != residual.distinct().sorted() || !selected.containsAll(residual)) invalid()
    }

    companion object {
        fun select(requestId: String, scopeId: String, zone: String, candidates: List<String>, today: String,
                   binding: String, refreshRecentDays: Int, todayRefresh: Boolean, outcome: ReceiverCoverageOutcome): ReceiverCoveragePlan {
            val request = buildJsonObject {
                put("request_id", requestId); put("scope_id", scopeId); put("calendar_timezone", zone)
                put("candidates", array(candidates)); put("today", today)
            }
            val evidence = (outcome as? ReceiverCoverageOutcome.Valid)?.evidence?.normalizedResponse()?.toString(Charsets.UTF_8)
            val selected = selection(request, refreshRecentDays, todayRefresh, evidence)
            val plan = ReceiverCoveragePlan(buildJsonObject {
                put("schema", "healthmd.receiver_coverage.plan"); put("schema_version", 2)
                put("destination_binding", binding); put("request", request); put("policy", "missing_days")
                put("refresh_recent_days", refreshRecentDays); put("today_refresh", todayRefresh)
                put("selected", array(selected)); put("residual", array(selected))
                put("coverage_status", if (evidence == null) "fallback_full" else "valid")
                put("coverage_response", evidence?.let(::JsonPrimitive) ?: JsonNull)
            })
            plan.validate()
            return plan
        }
        fun restore(json: String, binding: String): ReceiverCoveragePlan {
            if (json.toByteArray().size > 96 * 1024) invalid()
            try {
                val plan = ReceiverCoveragePlan(Json.parseToJsonElement(json).jsonObject)
                if (plan.json() != json || plan.destinationBinding != binding) invalid()
                plan.validate()
                return plan
            } catch (_: Exception) { invalid() }
        }
        private fun selection(request: JsonObject, refresh: Int, todayRefresh: Boolean, evidence: String?): List<String> {
            val id = text(request.getValue("request_id")); val scope = text(request.getValue("scope_id"))
            val zone = text(request.getValue("calendar_timezone")); val today = text(request.getValue("today"))
            val candidates = strings(request.getValue("candidates"))
            if (!Regex("[A-Za-z0-9_-]{1,128}").matches(id) || !Regex("[A-Za-z0-9_-]{1,128}").matches(scope) ||
                zone !in ZoneId.getAvailableZoneIds() || refresh !in 0..30 || candidates.size !in 1..30 ||
                candidates != candidates.distinct().sorted()) invalid()
            val current = civil(today); val days = candidates.map(::civil)
            if (days.last() >= current || ChronoUnit.DAYS.between(days.first(), days.last()) >= 30) invalid()
            val selected = candidates.toMutableSet()
            if (evidence != null) {
                val expected = mapOf("schema" to "healthmd.receiver_coverage.response", "request_id" to id,
                    "scope_id" to scope, "calendar_timezone" to zone, "start" to candidates.first(),
                    "end_exclusive" to days.last().plusDays(1).toString())
                selected.removeAll(ReceiverCoverageEvidence.parse(evidence.toByteArray(), expected, today).completedDates().toSet())
            }
            if (refresh > 0) selected.addAll(candidates.filter { civil(it) >= days.last().minusDays(refresh - 1L) })
            if (todayRefresh) selected.add(today)
            return selected.sorted()
        }
        private fun civil(s: String): LocalDate {
            if (!Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(s)) invalid()
            return LocalDate.parse(s).also { if (it.year < 1) invalid() }
        }
        private fun text(value: JsonElement): String {
            val p = value as? JsonPrimitive ?: invalid()
            if (!p.isString) invalid()
            return p.content
        }
        private fun integer(value: JsonElement): Int {
            val p = value as? JsonPrimitive ?: invalid()
            if (p.isString || !Regex("-?[0-9]+").matches(p.content)) invalid()
            return p.intOrNull ?: invalid()
        }
        private fun boolean(value: JsonElement): Boolean {
            val p = value as? JsonPrimitive ?: invalid()
            if (p.isString) invalid()
            return p.booleanOrNull ?: invalid()
        }
        private fun strings(value: JsonElement): List<String> = (value as? JsonArray ?: invalid()).map(::text)
        private fun array(items: List<String>) = JsonArray(items.map(::JsonPrimitive))
        private fun canonical(value: JsonElement): JsonElement = when (value) {
            is JsonObject -> JsonObject(value.toSortedMap().mapValues { canonical(it.value) })
            is JsonArray -> JsonArray(value.map(::canonical))
            else -> value
        }
        private fun invalid(): Nothing = throw ReceiverCoveragePreflight.BoundaryException()
    }
}
