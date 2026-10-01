package com.healthmd.data.export

import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFailureReason
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import javax.inject.Inject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

interface APIExportUploader {
    suspend fun upload(
        endpointUrl: String,
        payload: String,
        authorizationHeader: String?,
        requestHeaders: List<APIExportRequestHeader>,
    ): APIExportUploadResult
}

data class APIExportUploadResult(
    val statusCode: Int,
    val responseBodyPreview: String? = null,
)

class APIExportClientException(
    val failureReason: ExportFailureReason,
    val retryable: Boolean,
    val statusCode: Int? = null,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

class APIExportClient @Inject constructor(
    client: OkHttpClient,
) : APIExportUploader {
    // Compatibility exports may contain arbitrary encrypted request headers.
    // Handle the narrow safe redirect case here instead of allowing OkHttp to
    // replay those headers or health bytes according to its general policy.
    private val client = client.newBuilder()
        .followRedirects(false)
        .followSslRedirects(false)
        .build()
    override suspend fun upload(
        endpointUrl: String,
        payload: String,
        authorizationHeader: String?,
        requestHeaders: List<APIExportRequestHeader>,
    ): APIExportUploadResult = withContext(Dispatchers.IO) {
        val normalized = APIExportEndpoint.normalizedOrNull(endpointUrl)
            ?: throw APIExportClientException(
                failureReason = ExportFailureReason.INVALID_API_ENDPOINT,
                retryable = false,
                message = "Configure a valid HTTP or HTTPS API endpoint before exporting.",
            )

        val validatedRequestHeaders = try {
            APIExportHeaders.validate(requestHeaders)
        } catch (error: IllegalArgumentException) {
            throw APIExportClientException(
                failureReason = ExportFailureReason.INVALID_API_ENDPOINT,
                retryable = false,
                message = error.message ?: "Configure valid API request headers before exporting.",
                cause = error,
            )
        }

        var request = Request.Builder()
            .url(normalized)
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .header("Accept", "application/json")
            .header("User-Agent", "Health.md Android API Export")
            .apply {
                authorizationHeader?.takeIf { it.isNotBlank() }?.let {
                    header("Authorization", it)
                }
                // Custom headers are applied last intentionally. This lets advanced users use an
                // arbitrary Authorization scheme or override defaults such as Accept/User-Agent.
                validatedRequestHeaders.forEach { configuredHeader ->
                    header(configuredHeader.name, configuredHeader.value)
                }
            }
            .build()

        val originalUrl = request.url
        var redirectCount = 0
        while (true) {
            val response = execute(request)
            response.use {
                val redirectedUrl = safeRedirectTarget(it, originalUrl)
                if (redirectedUrl != null && redirectCount < MAX_REDIRECTS) {
                    // Only 307/308 reach this branch, so the immutable POST body
                    // and exact frozen headers remain valid for the next hop.
                    request = request.newBuilder().url(redirectedUrl).build()
                    redirectCount += 1
                    return@use
                }

                val preview = responsePreview(it)
                if (!it.isSuccessful) {
                    // Response bodies are untrusted and may echo request data or
                    // credentials. Keep every durable/UI failure status-only.
                    throw APIExportClientException(
                        failureReason = ExportFailureReason.API_REJECTED,
                        retryable = it.code == 408 || it.code == 429 || it.code >= 500,
                        statusCode = it.code,
                        message = "API endpoint returned HTTP ${it.code}.",
                    )
                }
                return@withContext APIExportUploadResult(it.code, preview)
            }
        }
        @Suppress("UNREACHABLE_CODE")
        error("Unreachable API redirect state")
    }

    private suspend fun execute(request: Request): Response {
        val call = client.newCall(request)
        return try {
            // Wire cooperative cancellation to every exact redirect-hop call.
            suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { call.cancel() }
                call.enqueue(object : Callback {
                    override fun onResponse(call: Call, response: Response) {
                        continuation.resume(response)
                    }

                    override fun onFailure(call: Call, error: IOException) {
                        continuation.resumeWithException(error)
                    }
                })
            }
        } catch (error: IOException) {
            kotlin.coroutines.coroutineContext.ensureActive()
            throw APIExportClientException(
                failureReason = ExportFailureReason.NETWORK_ERROR,
                retryable = true,
                message = "Could not reach the API endpoint.",
                cause = error,
            )
        }
    }

    private fun safeRedirectTarget(response: Response, originalUrl: okhttp3.HttpUrl): okhttp3.HttpUrl? {
        if (response.code != 307 && response.code != 308) return null
        val target = response.header("Location")?.let(response.request.url::resolve) ?: return null
        if (target.username.isNotEmpty() || target.password.isNotEmpty()) return null
        return target.takeIf {
            it.scheme == originalUrl.scheme && it.host == originalUrl.host && it.port == originalUrl.port
        }
    }

    private fun responsePreview(response: okhttp3.Response): String? {
        val reader = response.body?.charStream() ?: return null
        val buffer = CharArray(MAX_RESPONSE_PREVIEW_CHARS + 1)
        val count = reader.read(buffer)
        if (count <= 0) return null
        val text = String(buffer, 0, count.coerceAtMost(MAX_RESPONSE_PREVIEW_CHARS)).trim()
        if (text.isEmpty()) return null
        return if (count > MAX_RESPONSE_PREVIEW_CHARS) "$text…" else text
    }

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private const val MAX_RESPONSE_PREVIEW_CHARS = 500
        private const val MAX_REDIRECTS = 5
    }
}
