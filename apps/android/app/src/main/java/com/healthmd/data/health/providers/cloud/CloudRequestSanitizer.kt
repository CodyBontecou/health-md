package com.healthmd.data.health.providers.cloud

import java.net.URL
import java.nio.charset.Charset
import java.security.MessageDigest
import java.util.Locale

internal object CloudRequestSanitizer {
    private val providerIdPattern = Regex("[a-z0-9][a-z0-9._-]{0,63}")
    private val mediaTypePattern = Regex("[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+")
    private val safeActionPattern = Regex("[A-Za-z0-9_-]{1,64}")
    private val safeDateOrNumberPattern = Regex("[0-9]{1,16}|[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]{5,35}Z?")
    private val safeIntegerPattern = Regex("[0-9]{1,9}")
    private val dateKeys = setOf("date", "start", "end", "start_date", "end_date", "start_datetime", "end_datetime")
    private val integerKeys = setOf("limit", "offset", "page", "page_size")

    val allowedResponseHeaders: List<String> = listOf(
        "ETag",
        "Last-Modified",
        "Request-ID",
        "X-Request-ID",
        "X-Correlation-ID",
    )

    fun requireProviderId(providerId: String): String {
        require(providerIdPattern.matches(providerId)) { "Invalid cloud provider identifier" }
        return providerId
    }

    fun validateEndpoint(url: URL) {
        val scheme = url.protocol.lowercase(Locale.US)
        val host = url.host.lowercase(Locale.US)
        val isLoopback = host == "localhost" || host == "::1" || host.startsWith("127.")
        require(scheme == "https" || scheme == "http" && isLoopback) {
            "Cloud API requests require HTTPS"
        }
        require(url.userInfo == null && url.query == null && url.ref == null && host.isNotBlank()) {
            "Cloud API endpoint must not contain credentials, query, or fragment"
        }
    }

    /** Stable opaque endpoint identity: provider plus a digest, never an unredacted URL or path. */
    fun endpointIdentifier(providerId: String, url: URL): String {
        val port = if (url.port == -1) "" else ":${url.port}"
        val material = "${url.protocol.lowercase(Locale.US)}://${url.host.lowercase(Locale.US)}$port${url.path}"
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return "$providerId:${digest.take(24)}"
    }

    /** Values are retained only for explicitly safe keys and strict non-secret value shapes. */
    fun queryMetadata(query: Map<String, String>): Map<String, String> = buildMap {
        query.entries.sortedBy { it.key }.forEach { (rawKey, value) ->
            val key = rawKey.lowercase(Locale.US)
            val safe = when {
                key == "action" -> safeActionPattern.matches(value)
                key in dateKeys -> safeDateOrNumberPattern.matches(value)
                key in integerKeys -> safeIntegerPattern.matches(value)
                else -> false
            }
            if (safe) put(key, value)
        }
    }

    fun responseHeaders(headers: Map<String, String>): Map<String, String> = buildMap {
        allowedResponseHeaders.forEach { allowedName ->
            headers.entries.firstOrNull { it.key.equals(allowedName, ignoreCase = true) }
                ?.value
                ?.let(::safeHeaderValue)
                ?.let { put(allowedName, it) }
        }
    }

    fun contentTypeAndCharset(contentTypeHeader: String?): Pair<String?, Charset> {
        val parts = contentTypeHeader.orEmpty().split(';')
        val mediaType = parts.firstOrNull()
            ?.trim()
            ?.lowercase(Locale.US)
            ?.takeIf(mediaTypePattern::matches)
        val charsetName = parts.drop(1).firstNotNullOfOrNull { parameter ->
            val pieces = parameter.trim().split('=', limit = 2)
            pieces.takeIf { it.size == 2 && it[0].trim().equals("charset", ignoreCase = true) }
                ?.get(1)?.trim()?.trim('"')
        }
        val charset = charsetName
            ?.takeIf { it.length <= 40 && it.all { character -> character.isLetterOrDigit() || character in "-_ ." } }
            ?.let { runCatching { Charset.forName(it) }.getOrNull() }
            ?: Charsets.UTF_8
        return mediaType to charset
    }

    private fun safeHeaderValue(value: String): String? = value.trim()
        .takeIf { it.isNotEmpty() && it.length <= 512 && it.all { character -> character.code in 0x20..0x7e } }
}
