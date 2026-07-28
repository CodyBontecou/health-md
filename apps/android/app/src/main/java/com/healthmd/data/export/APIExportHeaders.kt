package com.healthmd.data.export

import com.healthmd.domain.model.APIExportEndpoint
import java.security.MessageDigest

/** A user-configured HTTP request header stored only in encrypted app preferences. */
data class APIExportRequestHeader(
    val name: String,
    val value: String,
)

/** Parses and validates the raw `Name: value` header editor used by API exports. */
object APIExportHeaders {
    private const val MAX_HEADER_COUNT = 20
    private const val MAX_TOTAL_CHARS = 16_384
    private const val MAX_NAME_CHARS = 128
    private const val MAX_VALUE_CHARS = 8_192

    // OkHttp must control framing and the JSON body content type. Proxy headers must never be
    // accepted from user configuration because they can expose credentials to intermediaries.
    private val reservedNames = setOf(
        "connection",
        "content-length",
        "content-type",
        "host",
        "proxy-authorization",
        "proxy-connection",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    )
    private val namePattern = Regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$")

    fun parse(rawValue: String): List<APIExportRequestHeader> {
        if (rawValue.length > MAX_TOTAL_CHARS) {
            throw IllegalArgumentException("Request headers must be 16 KB or less.")
        }
        if ('\r' in rawValue) {
            throw IllegalArgumentException("Request headers contain an unsupported line break.")
        }

        val seenNames = mutableSetOf<String>()
        val headers = rawValue
            .split('\n')
            .mapIndexedNotNull { index, rawLine ->
                val line = rawLine.trim()
                if (line.isEmpty()) return@mapIndexedNotNull null

                val separator = line.indexOf(':')
                if (separator <= 0) {
                    throw IllegalArgumentException("Header line ${index + 1} must use Name: value.")
                }

                val name = line.substring(0, separator).trim()
                val value = line.substring(separator + 1).trim()
                val normalizedName = name.lowercase()
                when {
                    name.length > MAX_NAME_CHARS || !namePattern.matches(name) ->
                        throw IllegalArgumentException("Header line ${index + 1} has an invalid name.")
                    normalizedName in reservedNames ->
                        throw IllegalArgumentException("$name is managed by Health.md and cannot be overridden.")
                    !seenNames.add(normalizedName) ->
                        throw IllegalArgumentException("Header $name is configured more than once.")
                    value.length > MAX_VALUE_CHARS ->
                        throw IllegalArgumentException("Header $name is too long.")
                    value.any { it >= '\u007f' || (it < ' ' && it != '\t') } ->
                        throw IllegalArgumentException("Header $name contains unsupported characters.")
                }
                APIExportRequestHeader(name = name, value = value)
            }

        if (headers.size > MAX_HEADER_COUNT) {
            throw IllegalArgumentException("Configure no more than $MAX_HEADER_COUNT request headers.")
        }
        return headers
    }

    fun validate(headers: List<APIExportRequestHeader>): List<APIExportRequestHeader> =
        parse(headers.joinToString("\n") { "${it.name}: ${it.value}" })

    fun normalize(rawValue: String): String = parse(rawValue)
        .joinToString("\n") { "${it.name}: ${it.value}" }
}

object APIExportDestinationFingerprint {
    fun create(
        salt: ByteArray,
        endpointUrl: String,
        authorizationHeader: String?,
        requestHeaders: List<APIExportRequestHeader>,
    ): String? {
        val endpoint = APIExportEndpoint.normalizedOrNull(endpointUrl) ?: return null
        val headers = APIExportHeaders.validate(requestHeaders).sortedBy { it.name.lowercase() }
        val destination = buildString {
            append(endpoint).append('\n')
            authorizationHeader?.takeIf { it.isNotEmpty() }?.let { authorization ->
                append("authorization:").append(authorization).append('\n')
            }
            headers.forEach { header ->
                append(header.name.lowercase()).append(':').append(header.value).append('\n')
            }
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(salt + destination.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }
}
