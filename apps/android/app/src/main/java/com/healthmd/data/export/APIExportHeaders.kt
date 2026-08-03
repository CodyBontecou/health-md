package com.healthmd.data.export

import com.healthmd.domain.model.APIExportEndpoint
import java.security.MessageDigest
import java.util.Locale

/** A user-configured HTTP request header stored only in encrypted app preferences. */
data class APIExportRequestHeader(
    val name: String,
    val value: String,
)

/** Structured validation failures for the raw `Name: value` API export header editor. */
sealed interface APIExportHeaderValidationReason {
    data class TotalSizeExceeded(val maximumCharacters: Int) : APIExportHeaderValidationReason
    data object UnsupportedLineBreak : APIExportHeaderValidationReason
    data class MissingSeparator(val headerIndex: Int) : APIExportHeaderValidationReason
    data class InvalidName(
        val headerIndex: Int,
        val maximumNameCharacters: Int,
    ) : APIExportHeaderValidationReason
    data class ReservedName(val headerName: String) : APIExportHeaderValidationReason
    data class DuplicateName(val headerName: String) : APIExportHeaderValidationReason
    data class ValueTooLong(
        val headerName: String,
        val maximumValueCharacters: Int,
    ) : APIExportHeaderValidationReason
    data class UnsupportedValueCharacters(val headerName: String) : APIExportHeaderValidationReason
    data class TooManyHeaders(val maximumCount: Int) : APIExportHeaderValidationReason
}

/**
 * Retains [IllegalArgumentException] compatibility while exposing a reason that UI callers can
 * localize without displaying exception text.
 */
class APIExportHeaderValidationException(
    val reason: APIExportHeaderValidationReason,
) : IllegalArgumentException(reason.compatibilityMessage())

private fun APIExportHeaderValidationReason.compatibilityMessage(): String = when (this) {
    is APIExportHeaderValidationReason.TotalSizeExceeded -> "Request headers must be 16 KB or less."
    APIExportHeaderValidationReason.UnsupportedLineBreak ->
        "Request headers contain an unsupported line break."
    is APIExportHeaderValidationReason.MissingSeparator ->
        "Header line $headerIndex must use Name: value."
    is APIExportHeaderValidationReason.InvalidName ->
        "Header line $headerIndex has an invalid name."
    is APIExportHeaderValidationReason.ReservedName ->
        "$headerName is managed by Health.md and cannot be overridden."
    is APIExportHeaderValidationReason.DuplicateName ->
        "Header $headerName is configured more than once."
    is APIExportHeaderValidationReason.ValueTooLong -> "Header $headerName is too long."
    is APIExportHeaderValidationReason.UnsupportedValueCharacters ->
        "Header $headerName contains unsupported characters."
    is APIExportHeaderValidationReason.TooManyHeaders ->
        "Configure no more than $maximumCount request headers."
}

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
            invalid(APIExportHeaderValidationReason.TotalSizeExceeded(MAX_TOTAL_CHARS))
        }
        if ('\r' in rawValue) {
            invalid(APIExportHeaderValidationReason.UnsupportedLineBreak)
        }

        val seenNames = mutableSetOf<String>()
        val headers = rawValue
            .split('\n')
            .mapIndexedNotNull { index, rawLine ->
                val line = rawLine.trim()
                if (line.isEmpty()) return@mapIndexedNotNull null

                val headerIndex = index + 1
                val separator = line.indexOf(':')
                if (separator <= 0) {
                    invalid(APIExportHeaderValidationReason.MissingSeparator(headerIndex))
                }

                val name = line.substring(0, separator).trim()
                val value = line.substring(separator + 1).trim()
                val normalizedName = name.lowercase(Locale.ROOT)
                when {
                    name.length > MAX_NAME_CHARS || !namePattern.matches(name) ->
                        invalid(APIExportHeaderValidationReason.InvalidName(headerIndex, MAX_NAME_CHARS))
                    normalizedName in reservedNames ->
                        invalid(APIExportHeaderValidationReason.ReservedName(name))
                    !seenNames.add(normalizedName) ->
                        invalid(APIExportHeaderValidationReason.DuplicateName(name))
                    value.length > MAX_VALUE_CHARS ->
                        invalid(APIExportHeaderValidationReason.ValueTooLong(name, MAX_VALUE_CHARS))
                    value.any { it >= '\u007f' || (it < ' ' && it != '\t') } ->
                        invalid(APIExportHeaderValidationReason.UnsupportedValueCharacters(name))
                }
                APIExportRequestHeader(name = name, value = value)
            }

        if (headers.size > MAX_HEADER_COUNT) {
            invalid(APIExportHeaderValidationReason.TooManyHeaders(MAX_HEADER_COUNT))
        }
        return headers
    }

    private fun invalid(reason: APIExportHeaderValidationReason): Nothing =
        throw APIExportHeaderValidationException(reason)

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
        val headers = APIExportHeaders.validate(requestHeaders)
            .sortedBy { it.name.lowercase(Locale.ROOT) }
        val destination = buildString {
            append(endpoint).append('\n')
            authorizationHeader?.takeIf { it.isNotEmpty() }?.let { authorization ->
                append("authorization:").append(authorization).append('\n')
            }
            headers.forEach { header ->
                append(header.name.lowercase(Locale.ROOT))
                    .append(':')
                    .append(header.value)
                    .append('\n')
            }
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(salt + destination.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }
}
