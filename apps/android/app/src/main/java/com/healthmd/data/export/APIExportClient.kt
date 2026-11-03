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
    private val client: OkHttpClient,
    private val entitlements: com.healthmd.domain.repository.EntitlementRepository,
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

        // Reauthorize the actual network destination for every batch/retry. A navigation or
        // scheduling check is not authority to transmit to an edited or substituted endpoint.
        val personalAccess = entitlements.verifyAccess()
        if (!personalAccess && !entitlements.verifyExportAccess(
                com.healthmd.domain.model.ExportTarget.API_ENDPOINT, normalized)) {
            throw APIExportClientException(ExportFailureReason.PAYWALL_REQUIRED, false,
                message = "This destination is not covered by your access.")
        }

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

        val clinicAuthorization = entitlements.clinicUploadAuthorization(normalized)
        val managedClinicEndpoint = clinicAuthorization != null || entitlements.sponsoredEndpoint.value?.let {
            val approved = com.healthmd.domain.billing.ClinicExportAuthorization.canonicalClinicEndpoint(it)
            approved != null && approved ==
                com.healthmd.domain.billing.ClinicExportAuthorization.canonicalClinicEndpoint(normalized)
        } == true

        val request = Request.Builder()
            .url(normalized)
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .header("Accept", "application/json")
            .header("User-Agent", "Health.md Android API Export")
            .apply {
                authorizationHeader?.takeIf { personalAccess && !managedClinicEndpoint && it.isNotBlank() }?.let {
                    header("Authorization", it)
                }
                // Custom headers are applied last intentionally. This lets advanced users use an
                // arbitrary Authorization scheme or override defaults such as Accept/User-Agent.
                validatedRequestHeaders.filter { personalAccess && !managedClinicEndpoint }.forEach { configuredHeader ->
                    header(configuredHeader.name, configuredHeader.value)
                }
                clinicAuthorization?.let { header("Authorization", it) }
            }
            .build()

        val deliveryClient = if (personalAccess && !managedClinicEndpoint) client else client.newBuilder()
            .followRedirects(false).followSslRedirects(false).build()
        val call = deliveryClient.newCall(request)
        val response = try {
            // Wire cooperative cancellation to the exact OkHttp call so a user cancellation
            // aborts the in-flight upload immediately instead of waiting for the read timeout.
            suspendCancellableCoroutine<Response> { continuation ->
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

        response.use {
            val preview = if (personalAccess && !managedClinicEndpoint) responsePreview(it) else null
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
