package com.healthmd.data.receivercoverage

import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonPrimitive

/** Immutable new-occurrence context. Persistence/recovery must keep the original request. */
class ReceiverCoverageRequest private constructor(
    private val body: ByteArray,
    val destinationBinding: String,
    private val expected: Map<String, String>,
    internal val today: String,
    val url: URI,
    private val frozenHeaders: Map<String, String>,
) {
    internal fun expectedFields(): Map<String, String> = expected.toMap()
    fun body(): ByteArray = body.copyOf()
    fun headers(): Map<String, String> = frozenHeaders.toMap()

    companion object {
        fun freeze(preflight: ReceiverCoveragePreflight, requestId: String, candidates: List<String>, now: Instant): ReceiverCoverageRequest {
            val originalCandidates = candidates.toList()
            val body = preflight.requestBody(requestId, originalCandidates, now)
            val end = LocalDate.parse(originalCandidates.last()).plusDays(1).toString()
            return ReceiverCoverageRequest(body, preflight.destinationBinding, mapOf(
                "schema" to "healthmd.receiver_coverage.response", "request_id" to requestId,
                "scope_id" to preflight.scopeId, "calendar_timezone" to preflight.calendarTimezone,
                "start" to originalCandidates.first(), "end_exclusive" to end,
            ), now.atZone(ZoneId.of(preflight.calendarTimezone)).toLocalDate().toString(),
                preflight.preflightUrl, preflight.headers())
        }
    }
}

sealed interface ReceiverCoverageOutcome {
    class Valid(val evidence: ReceiverCoverageEvidence) : ReceiverCoverageOutcome
    /** New occurrence only; cannot repair corrupt persisted work. */
    data object FallbackFull : ReceiverCoverageOutcome
}

class ReceiverCoverageEvidence private constructor(
    private val dates: List<String>,
    private val normalized: ByteArray,
) {
    fun completedDates(): List<String> = dates.toList()
    fun normalizedResponse(): ByteArray = normalized.copyOf()

    companion object {
        fun parse(body: ByteArray, request: ReceiverCoverageRequest): ReceiverCoverageEvidence {
            return parse(body, request.expectedFields(), request.today)
        }
        internal fun parse(body: ByteArray, expected: Map<String, String>, today: String): ReceiverCoverageEvidence {
            val (fields, dates) = CoverageJSONReader(body).response()
            if (fields != expected || dates != dates.distinct().sorted()) invalid()
            dates.forEach { day ->
                if (!Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(day)) invalid()
                val date = try { LocalDate.parse(day) } catch (_: Exception) { invalid() }
                if (date.year < 1 || day < expected.getValue("start") ||
                    day >= expected.getValue("end_exclusive") || day >= today) invalid()
            }
            // Encode only validated fields. Sorting gives stable evidence, never an error body.
            val normalized = (fields + mapOf("schema_version" to "1", "completed_dates" to ""))
                .toSortedMap().entries.joinToString(",", "{", "}") { (key, value) ->
                    val encoded = when (key) {
                        "schema_version" -> "1"
                        "completed_dates" -> dates.joinToString(",", "[", "]") { quote(it) }
                        else -> quote(value)
                    }
                    quote(key) + ":" + encoded
                }.toByteArray(Charsets.UTF_8)
            return ReceiverCoverageEvidence(dates.toList(), normalized)
        }
        private fun quote(s: String) = kotlinx.serialization.json.JsonPrimitive(s).toString()
    }
}

private fun invalid(): Nothing = throw ReceiverCoveragePreflight.BoundaryException()

/** Flat, schema-specific reader rejects duplicates/unknown fields before dictionary projection. */
private class CoverageJSONReader(body: ByteArray) {
    private val text: String
    private var offset = 0
    init {
        if (body.size > ReceiverCoveragePreflight.MAXIMUM_RESPONSE_BYTES) invalid()
        text = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(body)).toString()
        } catch (_: Exception) { invalid() }
    }
    fun response(): Pair<Map<String, String>, List<String>> {
        consume('{')
        val seen = mutableSetOf<String>()
        val fields = mutableMapOf<String, String>()
        val days = mutableListOf<String>()
        val names = setOf("schema", "request_id", "scope_id", "calendar_timezone", "start", "end_exclusive")
        while (true) {
            val key = string()
            if (!seen.add(key)) invalid()
            consume(':')
            when {
                key in names -> fields[key] = string()
                key == "schema_version" -> consume('1')
                key == "completed_dates" -> {
                    consume('[')
                    if (!take(']')) while (true) {
                        if (days.size >= 30) invalid()
                        days.add(string())
                        if (take(']')) break
                        consume(',')
                    }
                }
                else -> invalid()
            }
            if (take('}')) break
            consume(',')
        }
        whitespace()
        if (offset != text.length || seen != names + setOf("schema_version", "completed_dates")) invalid()
        return fields.toMap() to days.toList()
    }
    private fun whitespace() { while (offset < text.length && text[offset] in " \t\r\n") offset++ }
    private fun take(ch: Char): Boolean {
        whitespace()
        if (offset >= text.length || text[offset] != ch) return false
        offset++
        return true
    }
    private fun consume(ch: Char) { if (!take(ch)) invalid() }
    private fun string(): String {
        whitespace()
        val start = offset
        consume('"')
        while (offset < text.length) {
            val ch = text[offset++]
            if (ch == '"') {
                return try {
                    Json.parseToJsonElement(text.substring(start, offset)).jsonPrimitive.content.also { value ->
                        // kotlinx JSON permits lone escaped surrogates; v1 accepts Unicode scalars.
                        var i = 0
                        while (i < value.length) {
                            val c = value[i++]
                            if (c.isHighSurrogate()) {
                                if (i >= value.length || !value[i++].isLowSurrogate()) invalid()
                            } else if (c.isLowSurrogate()) invalid()
                        }
                    }
                } catch (_: Exception) { invalid() }
            }
            if (ch.code < 32) invalid()
            if (ch == '\\') offset++
        }
        invalid()
    }
}
