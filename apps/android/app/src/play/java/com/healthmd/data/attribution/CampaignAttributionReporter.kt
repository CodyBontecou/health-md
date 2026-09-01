package com.healthmd.data.attribution

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import javax.inject.Inject
import javax.inject.Qualifier

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class CampaignAttributionHttpClient

interface CampaignAttributionReporter {
    suspend fun report(event: CampaignInstallEvent): CampaignAttributionReportResult
}

sealed interface CampaignAttributionReportResult {
    data class Delivered(val statusCode: Int) : CampaignAttributionReportResult
    data class PermanentFailure(val statusCode: Int) : CampaignAttributionReportResult
    data class RetryableFailure(val statusCode: Int? = null) : CampaignAttributionReportResult
    data object NotConfigured : CampaignAttributionReportResult
}

data class CampaignAttributionConfig(
    val endpointUrl: String,
    val ingestToken: String?,
    val isDebug: Boolean,
)

object CampaignAttributionPayloadSerializer {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
    }

    fun serialize(event: CampaignInstallEvent): String =
        json.encodeToString(CampaignInstallEvent.serializer(), event)
}

class OkHttpCampaignAttributionReporter @Inject constructor(
    @CampaignAttributionHttpClient private val client: OkHttpClient,
    private val config: CampaignAttributionConfig,
) : CampaignAttributionReporter {
    override suspend fun report(
        event: CampaignInstallEvent,
    ): CampaignAttributionReportResult = withContext(Dispatchers.IO) {
        val endpoint = ingestionEndpoint(config)
            ?: return@withContext CampaignAttributionReportResult.NotConfigured
        val token = config.ingestToken?.trim()?.takeIf { it.isNotEmpty() }
        if (token != null && !INGEST_TOKEN_REGEX.matches(token)) {
            return@withContext CampaignAttributionReportResult.NotConfigured
        }
        val payload = CampaignAttributionPayloadSerializer.serialize(event)
        val request = try {
            Request.Builder()
                .url(endpoint)
                .post(payload.toRequestBody(JSON_MEDIA_TYPE))
                .header("Accept", "application/json")
                .apply {
                    token?.let { header("Authorization", "Bearer $it") }
                }
                .build()
        } catch (_: IllegalArgumentException) {
            return@withContext CampaignAttributionReportResult.NotConfigured
        }

        val response = try {
            client.newCall(request).execute()
        } catch (error: CancellationException) {
            throw error
        } catch (_: IOException) {
            return@withContext CampaignAttributionReportResult.RetryableFailure()
        } catch (_: Exception) {
            return@withContext CampaignAttributionReportResult.RetryableFailure()
        }

        response.use {
            when {
                it.code in 200..299 -> CampaignAttributionReportResult.Delivered(it.code)
                it.code == 401 || it.code == 403 ->
                    CampaignAttributionReportResult.NotConfigured
                it.code == 408 || it.code == 429 || it.code >= 500 ->
                    CampaignAttributionReportResult.RetryableFailure(it.code)
                else -> CampaignAttributionReportResult.PermanentFailure(it.code)
            }
        }
    }

    private fun ingestionEndpoint(config: CampaignAttributionConfig): HttpUrl? {
        val rawEndpoint = config.endpointUrl.trim()
        if (rawEndpoint.isEmpty()) return null
        val base = rawEndpoint.toHttpUrlOrNull() ?: return null
        if (base.query != null || base.fragment != null ||
            base.username.isNotEmpty() || base.password.isNotEmpty()
        ) {
            return null
        }
        val allowedScheme = base.isHttps ||
            (config.isDebug && base.scheme == "http" && base.host in LOCALHOST_HOSTS)
        if (!allowedScheme) return null

        return base.newBuilder()
            .encodedPath(base.encodedPath.trimEnd('/') + INSTALLS_PATH)
            .build()
    }

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private const val INSTALLS_PATH = "/v1/installs"
        private val INGEST_TOKEN_REGEX = Regex("^[A-Za-z0-9._~+/=\\-]{1,512}$")
        private val LOCALHOST_HOSTS = setOf("localhost", "127.0.0.1", "::1")
    }
}
