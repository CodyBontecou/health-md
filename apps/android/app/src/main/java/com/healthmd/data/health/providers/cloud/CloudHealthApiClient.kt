package com.healthmd.data.health.providers.cloud

import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthToken
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

class CloudHealthApiClient private constructor(
    private val oauthAuthorizationManager: OAuthAuthorizationManager,
    private val responseObserver: CloudRawResponseObserver?,
    private val transport: CloudHttpTransport,
    private val clock: () -> Instant,
    private val maxResponseBytes: Int,
) {
    constructor(oauthAuthorizationManager: OAuthAuthorizationManager) : this(
        oauthAuthorizationManager = oauthAuthorizationManager,
        responseObserver = null,
        transport = UrlConnectionCloudTransport(MAX_RESPONSE_BYTES),
        clock = Instant::now,
        maxResponseBytes = MAX_RESPONSE_BYTES,
    )

    constructor(
        oauthAuthorizationManager: OAuthAuthorizationManager,
        responseObserver: CloudRawResponseObserver,
    ) : this(
        oauthAuthorizationManager = oauthAuthorizationManager,
        responseObserver = responseObserver,
        transport = UrlConnectionCloudTransport(MAX_RESPONSE_BYTES),
        clock = Instant::now,
        maxResponseBytes = MAX_RESPONSE_BYTES,
    )

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun isConfigured(providerId: String): Boolean =
        oauthAuthorizationManager.isConfigured(providerId)

    suspend fun token(providerId: String): OAuthToken? =
        oauthAuthorizationManager.validAccessToken(providerId)

    /** Existing parsed-JSON entry point. Successful responses are also sent to the observer. */
    suspend fun getJson(
        providerId: String,
        url: String,
        query: Map<String, String> = emptyMap(),
    ): JsonElement = getRawJsonResponse(providerId, url, query).json

    /**
     * Fetch one provider-native JSON page while preserving its successful response bytes before
     * decoding or parsing. Only sanitized request/response metadata enters the returned value.
     */
    suspend fun getRawJsonResponse(
        providerId: String,
        url: String,
        query: Map<String, String> = emptyMap(),
        pageOrdinal: Int = 1,
        observer: CloudRawResponseObserver? = null,
    ): CloudHealthRawResponse {
        val safeProviderId = CloudRequestSanitizer.requireProviderId(providerId)
        require(pageOrdinal > 0) { "pageOrdinal must be positive" }
        val endpoint = parseAndValidateEndpoint(url)
        val endpointIdentifier = CloudRequestSanitizer.endpointIdentifier(safeProviderId, endpoint)
        val queryMetadata = CloudRequestSanitizer.queryMetadata(query)
        val token = oauthAuthorizationManager.validAccessToken(safeProviderId)
            ?: throw SecurityException("$safeProviderId is not connected")
        val requestUrl = URL(if (query.isEmpty()) endpoint.toString() else "$endpoint?${formEncode(query)}")

        val transportResponse = try {
            transport.execute(
                CloudHttpRequest(
                    url = requestUrl,
                    authorization = "${token.tokenType.ifBlank { "Bearer" }} ${token.accessToken}",
                ),
            )
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Exception) {
            throw CloudHealthRequestException(safeProviderId)
        }

        if (transportResponse.status !in 200..299) {
            throw CloudHealthRequestException(safeProviderId, transportResponse.status)
        }
        if (transportResponse.body.size > maxResponseBytes) {
            throw CloudHealthRequestException(safeProviderId)
        }

        // Capture bytes first. Text decoding and JSON parsing only operate on this exact copy.
        val exactBytes = transportResponse.body.copyOf()
        val (contentType, charset) = CloudRequestSanitizer.contentTypeAndCharset(transportResponse.contentType)
        val responseText = exactBytes.toString(charset)
        val parsed = try {
            json.parseToJsonElement(responseText)
        } catch (_: Exception) {
            throw CloudHealthPayloadException(safeProviderId)
        }
        val response = CloudHealthRawResponse(
            providerId = safeProviderId,
            endpointIdentifier = endpointIdentifier,
            queryMetadata = queryMetadata,
            fetchedAt = clock(),
            httpStatus = transportResponse.status,
            contentType = contentType,
            charset = charset.name(),
            pageOrdinal = pageOrdinal,
            responseHeaders = CloudRequestSanitizer.responseHeaders(transportResponse.headers),
            responseBytes = exactBytes,
            responseText = responseText,
            json = parsed,
        )
        responseObserver?.onResponse(response)
        if (observer !== responseObserver) observer?.onResponse(response)
        return response
    }

    private fun parseAndValidateEndpoint(rawUrl: String): URL {
        val endpoint = try {
            URL(rawUrl)
        } catch (_: Exception) {
            throw IllegalArgumentException("Invalid cloud API endpoint")
        }
        CloudRequestSanitizer.validateEndpoint(endpoint)
        return endpoint
    }

    private fun formEncode(params: Map<String, String>): String =
        params.entries.joinToString("&") { (key, value) ->
            "${urlEncode(key)}=${urlEncode(value)}"
        }

    private fun urlEncode(value: String): String =
        URLEncoder.encode(value, Charsets.UTF_8.name())

    companion object {
        private const val MAX_RESPONSE_BYTES = 16 * 1024 * 1024

        internal fun forTesting(
            oauthAuthorizationManager: OAuthAuthorizationManager,
            transport: CloudHttpTransport,
            responseObserver: CloudRawResponseObserver? = null,
            clock: () -> Instant = Instant::now,
            maxResponseBytes: Int = MAX_RESPONSE_BYTES,
        ): CloudHealthApiClient = CloudHealthApiClient(
            oauthAuthorizationManager = oauthAuthorizationManager,
            responseObserver = responseObserver,
            transport = transport,
            clock = clock,
            maxResponseBytes = maxResponseBytes,
        )
    }
}

internal data class CloudHttpRequest(
    val url: URL,
    val authorization: String,
)

internal data class CloudHttpResponse(
    val status: Int,
    val contentType: String? = null,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray = byteArrayOf(),
)

internal fun interface CloudHttpTransport {
    suspend fun execute(request: CloudHttpRequest): CloudHttpResponse
}

private class UrlConnectionCloudTransport(
    private val maxResponseBytes: Int,
) : CloudHttpTransport {
    override suspend fun execute(request: CloudHttpRequest): CloudHttpResponse = withContext(Dispatchers.IO) {
        val connection = (request.url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = HTTP_TIMEOUT_MS
            readTimeout = HTTP_TIMEOUT_MS
            instanceFollowRedirects = false
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", request.authorization)
        }
        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                // Never read, retain, or surface arbitrary provider error bodies.
                connection.errorStream?.close()
                return@withContext CloudHttpResponse(status = status)
            }
            val body = connection.inputStream.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > maxResponseBytes) throw IllegalStateException("Cloud response exceeded size limit")
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            val headers = buildMap {
                CloudRequestSanitizer.allowedResponseHeaders.forEach { name ->
                    connection.getHeaderField(name)?.let { put(name, it) }
                }
            }
            CloudHttpResponse(
                status = status,
                contentType = connection.getHeaderField("Content-Type"),
                headers = headers,
                body = body,
            )
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val HTTP_TIMEOUT_MS = 20_000
    }
}
