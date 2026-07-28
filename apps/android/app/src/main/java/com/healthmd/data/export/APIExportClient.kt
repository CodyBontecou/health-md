package com.healthmd.data.export

import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFailureReason
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import javax.inject.Inject

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
    private val client: OkHttpClient,
) : APIExportUploader {
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

        val request = Request.Builder()
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

        val response = try {
            client.newCall(request).execute()
        } catch (error: IOException) {
            throw APIExportClientException(
                failureReason = ExportFailureReason.NETWORK_ERROR,
                retryable = true,
                message = "Could not reach the API endpoint.",
                cause = error,
            )
        }

        response.use {
            val preview = responsePreview(it)
            if (!it.isSuccessful) {
                val message = buildString {
                    append("API endpoint returned HTTP ").append(it.code).append('.')
                    preview?.let { body -> append(' ').append(body) }
                }
                throw APIExportClientException(
                    failureReason = ExportFailureReason.API_REJECTED,
                    retryable = it.code == 408 || it.code == 429 || it.code >= 500,
                    statusCode = it.code,
                    message = message,
                )
            }
            APIExportUploadResult(it.code, preview)
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
    }
}
