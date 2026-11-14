package com.healthmd.data.receivercoverage

import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Adoption boundary for receiver-coverage v1; deliberately not wired into a scheduler. The caller
 * must atomically admit the frozen occurrence and selection evidence before capture or upload.
 * Private routing metadata: never serialize or log this instance or its headers/body.
 */
class ReceiverCoveragePreflight private constructor(
    val uploadUrl: URI,
    val preflightUrl: URI,
    private val credentials: Map<String, String>,
    val destinationBinding: String,
    val scopeId: String,
    val calendarTimezone: String,
    val refreshRecentDays: Int,
) {
    enum class Policy { FULL_LOOKBACK, MISSING_DAYS }
    class BoundaryException : Exception("Receiver coverage boundary rejected")

    // Return an independent copy: a transport may not mutate the frozen header authority.
    fun headers(): Map<String, String> = credentials + mapOf(
        "accept" to "application/json", "content-type" to "application/json",
    )

    fun requireOriginalDestination(binding: String) {
        if (binding != destinationBinding) throw BoundaryException()
    }

    /** Today's owner day comes from execution time, independently of the intended fire date. */
    fun requestBody(requestId: String, candidates: List<String>, now: Instant): ByteArray {
        if (!identifier.matches(requestId) || candidates.size !in 1..30 ||
            candidates != candidates.distinct().sorted()) throw BoundaryException()
        val today = now.atZone(ZoneId.of(calendarTimezone)).toLocalDate()
        val dates = candidates.map {
            if (!civil.matches(it)) throw BoundaryException()
            val date = try { LocalDate.parse(it) } catch (_: Exception) { throw BoundaryException() }
            if (date.year !in 1..9999 || date >= today) throw BoundaryException()
            date
        }
        if (ChronoUnit.DAYS.between(dates.first(), dates.last()) >= 30) throw BoundaryException()
        val end = dates.last().plusDays(1)
        if (end.year > 9999) throw BoundaryException()
        // Values are validated opaque IDs, registered zone IDs and Gregorian civil dates. Zone
        // IDs are quoted as JSON too, rather than relying on that validation as an encoder.
        return ("{\"schema\":\"healthmd.receiver_coverage.request\",\"schema_version\":1," +
            "\"request_id\":${quote(requestId)},\"scope_id\":${quote(scopeId)}," +
            "\"calendar_timezone\":${quote(calendarTimezone)}," +
            "\"start\":${quote(candidates.first())},\"end_exclusive\":${quote(end.toString())}}").toByteArray(Charsets.UTF_8)
    }

    companion object {
        const val DEADLINE_SECONDS = 10
        const val MAXIMUM_RESPONSE_BYTES = 64 * 1024
        private val identifier = Regex("[A-Za-z0-9_-]{1,128}")
        private val civil = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")
        private val headerToken = Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")
        private val reservedHeaders = setOf("accept", "content-type", "content-length", "content-encoding",
            "transfer-encoding", "host", "connection", "trailer", "te", "upgrade", "expect", "proxy-authorization", "proxy-connection")

        /** Missing persisted policy means full lookback, with no key/credential access or traffic. */
        fun prepare(
            policy: Policy = Policy.FULL_LOOKBACK,
            uploadUrl: String,
            preflightUrl: String,
            uploadHeaders: Map<String, String>,
            scopeId: String,
            calendarTimezone: String,
            frozenOutputSettings: ByteArray,
            refreshRecentDays: Int,
            installationKey: ByteArray,
        ): ReceiverCoveragePreflight? {
            if (policy == Policy.FULL_LOOKBACK) return null
            val upload = endpoint(uploadUrl)
            val preflight = endpoint(preflightUrl)
            if (upload.host != preflight.host || effectivePort(upload) != effectivePort(preflight) ||
                !identifier.matches(scopeId) ||
                calendarTimezone !in ZoneId.getAvailableZoneIds() ||
                refreshRecentDays !in 0..30 || installationKey.size != 32 || frozenOutputSettings.isEmpty()) {
                throw BoundaryException()
            }
            val credentials = mutableMapOf<String, String>()
            uploadHeaders.forEach { (name, value) ->
                val lower = name.lowercase(Locale.ROOT)
                if (!headerToken.matches(name) || lower in reservedHeaders || lower in credentials ||
                    value.any { it.code !in 32..126 }) throw BoundaryException()
                credentials[lower] = value
            }
            if (credentials.size > 64 || credentials.entries.sumOf { it.key.length + it.value.length } > 16_384) {
                throw BoundaryException()
            }
            // Same length-prefixed binary transcript as Swift. The secure-store owner supplies an
            // installation-specific 32-byte key. Never generate a replacement when recovery fails.
            val fields = mutableListOf("receiver-coverage-destination-v1".toByteArray(), "compatibility_api".toByteArray(),
                upload.toASCIIString().toByteArray(), preflight.toASCIIString().toByteArray(),
                scopeId.toByteArray(), calendarTimezone.toByteArray(), frozenOutputSettings,
                credentials.size.toString().toByteArray())
            credentials.toSortedMap().forEach { (name, value) ->
                fields.add(name.toByteArray(Charsets.UTF_8))
                fields.add(value.toByteArray(Charsets.UTF_8))
            }
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(installationKey, "HmacSHA256"))
            fields.forEach { field ->
                mac.update("${field.size}:".toByteArray(Charsets.UTF_8))
                mac.update(field)
            }
            val binding = mac.doFinal().joinToString("") { "%02x".format(it) }
            return ReceiverCoveragePreflight(upload, preflight, credentials.toMap(), binding, scopeId,
                calendarTimezone, refreshRecentDays)
        }

        private val pathToken = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/".toSet()

        private fun validHost(host: String): Boolean {
            val labels = host.split('.')
            if (host.length > 253 || labels.any { it.isEmpty() || it.length > 63 ||
                    it.startsWith('-') || it.endsWith('-') || !Regex("[a-z0-9-]+").matches(it) }) return false
            if (labels.last().all { it in '0'..'9' }) {
                return labels.size == 4 && labels.all { label ->
                    (label.length == 1 || !label.startsWith('0')) && (label.toIntOrNull() ?: -1) in 0..255
                }
            }
            return true
        }

        private fun effectivePort(url: URI) = if (url.port == -1) 443 else url.port

        private fun endpoint(text: String): URI {
            if (text.any { it.code !in 33..126 } || '\\' in text || '%' in text) throw BoundaryException()
            val url = try { URI(text) } catch (_: Exception) { throw BoundaryException() }
            val host = url.host?.lowercase(Locale.ROOT) ?: throw BoundaryException()
            if (!url.scheme.equals("https", ignoreCase = true) || url.rawUserInfo != null ||
                url.rawQuery != null || url.rawFragment != null || !validHost(host) ||
                url.path.any { it !in pathToken } || '%' in url.rawPath ||
                url.path.split('/').any { it == "." || it == ".." } || effectivePort(url) !in 1..65535) {
                throw BoundaryException()
            }
            val port = effectivePort(url).takeUnless { it == 443 } ?: -1
            return URI("https", null, host, port, url.path.ifEmpty { "/" }, null, null)
        }

        private fun quote(text: String): String = "\"" + buildString {
            text.forEach { ch ->
                when (ch) {
                    '\\' -> append("\\\\")
                    '"' -> append("\\\"")
                    else -> if (ch.code < 32) append("\\u%04x".format(ch.code)) else append(ch)
                }
            }
        } + "\""
    }
}

/** Bounded streaming seam. The transport must reject redirects, enforce the total deadline and
 * cancel its exact call on cancellation, without retries. These bytes are NOT validated coverage. */
class ReceiverCoverageResponseBuffer(statusCode: Int, contentType: String?) {
    private val body = java.io.ByteArrayOutputStream()
    private var rejected = false

    init {
        if (statusCode != 200 || contentType?.substringBefore(';')?.trim()?.lowercase(Locale.ROOT) != "application/json") {
            throw ReceiverCoveragePreflight.BoundaryException()
        }
    }

    fun append(chunk: ByteArray) {
        if (rejected || chunk.size > ReceiverCoveragePreflight.MAXIMUM_RESPONSE_BYTES - body.size()) {
            rejected = true
            body.reset()
            throw ReceiverCoveragePreflight.BoundaryException()
        }
        body.write(chunk)
    }

    fun finish(): ByteArray {
        if (rejected) throw ReceiverCoveragePreflight.BoundaryException()
        return body.toByteArray()
    }
}
