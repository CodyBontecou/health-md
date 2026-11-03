package com.healthmd.data.billing

import com.healthmd.domain.billing.ClinicExportAuthorization
import com.healthmd.domain.billing.ClinicGrantVerifier
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.TimeoutCancellationException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response
import java.io.IOException
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Shipped configuration, never taken from the patient's invitation or a downloaded key set. */
data class ClinicLicensingConfiguration(
    val baseURL: String,
    val issuer: String,
    val audience: String,
    val trustedKeys: Map<String, ByteArray>,
) {
    init {
        require(ClinicExportAuthorization.canonicalClinicEndpoint(baseURL) == baseURL)
        require(baseURL.endsWith('/') && java.net.URI(baseURL).path == "/")
        require(issuer.isNotEmpty() && audience.isNotEmpty() && trustedKeys.isNotEmpty())
    }

    fun verifier() = ClinicGrantVerifier(issuer, audience, trustedKeys)
}

@Serializable
data class ClinicLicensingReply(
    val grant: String,
    val clinicName: String,
    val sponsorshipID: String,
    val refreshToken: String? = null,
)

class ClinicLicensingException(val inactive: Boolean) : Exception(
    if (inactive) "sponsorship_inactive" else "licensing_unavailable",
)

interface ClinicLicensingAPI {
    suspend fun redeem(code: String, installationID: String, enrollmentSecret: String): ClinicLicensingReply
    suspend fun refresh(token: String, installationID: String): ClinicLicensingReply
    suspend fun disconnect(token: String, installationID: String)
}

/** Dedicated ephemeral client: no shared interceptors, cookies, credentials or redirect handling. */
class ClinicLicensingClient internal constructor(
    private val configuration: ClinicLicensingConfiguration,
    private val client: OkHttpClient = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .callTimeout(15, TimeUnit.SECONDS).build(),
    private val requestTimeoutMilliseconds: Long = 15_000,
) : ClinicLicensingAPI {
    private val json = Json { ignoreUnknownKeys = false }

    override suspend fun redeem(code: String, installationID: String, enrollmentSecret: String): ClinicLicensingReply =
        json.decodeFromString(post("v2/invitations/redeem", mapOf("invitationCode" to code, "installationID" to installationID, "enrollmentSecret" to enrollmentSecret)))

    override suspend fun refresh(token: String, installationID: String): ClinicLicensingReply =
        json.decodeFromString(post("v1/sponsorship/refresh", mapOf("refreshToken" to token, "installationID" to installationID)))

    override suspend fun disconnect(token: String, installationID: String) {
        post("v1/sponsorship/disconnect", mapOf("refreshToken" to token, "installationID" to installationID))
    }

    private suspend fun post(path: String, body: Map<String, String>): String {
        val request = Request.Builder().url(configuration.baseURL + path)
            .header("Accept", "application/json").header("Cache-Control", "no-store")
            .post(json.encodeToString(body).toRequestBody("application/json".toMediaType())).build()
        try {
            // Async cancellation bounds UI wait even if system DNS cannot be interrupted.
            return withTimeout(requestTimeoutMilliseconds) {
                suspendCancellableCoroutine { continuation ->
                    val call = client.newCall(request)
                    continuation.invokeOnCancellation { call.cancel() }
                    call.enqueue(object : Callback {
                        override fun onFailure(call: Call, error: IOException) {
                            if (continuation.isActive) continuation.resumeWith(Result.failure(ClinicLicensingException(false)))
                        }
                        override fun onResponse(call: Call, response: Response) {
                            val result = runCatching {
                                response.use {
                                    if (it.request.url.toString() != configuration.baseURL + path)
                                        throw ClinicLicensingException(false)
                                    val input = it.body?.byteStream() ?: throw ClinicLicensingException(false)
                                    val output = java.io.ByteArrayOutputStream()
                                    val buffer = ByteArray(1024)
                                    while (true) {
                                        val count = input.read(buffer)
                                        if (count < 0) break
                                        if (output.size() + count > 16384) throw ClinicLicensingException(false)
                                        output.write(buffer, 0, count)
                                    }
                                    val text = output.toByteArray().toString(Charsets.UTF_8)
                                    val denial = runCatching { json.decodeFromString<Map<String, String>>(text) }.getOrNull()
                                    val code = denial?.takeIf { value -> value.size == 1 }?.get("error")
                                    if ((it.code == 401 && code == "unauthorized") ||
                                        (it.code == 403 && code in setOf("invitation_unavailable", "sponsorship_inactive")))
                                        throw ClinicLicensingException(true)
                                    if (!it.isSuccessful) throw ClinicLicensingException(false)
                                    text
                                }
                            }
                            if (continuation.isActive) continuation.resumeWith(result)
                        }
                    })
                }
            }
        } catch (_: TimeoutCancellationException) { throw ClinicLicensingException(false) }
    }
}
