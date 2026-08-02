package com.healthmd.data.onboardinganalytics

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
annotation class OnboardingAnalyticsHttpClient

data class OnboardingAnalyticsConfig(
    val endpointUrl: String,
    val isDebug: Boolean,
)

sealed interface OnboardingAnalyticsReportResult {
    data class Delivered(val statusCode: Int) : OnboardingAnalyticsReportResult
    data class PermanentFailure(val statusCode: Int) : OnboardingAnalyticsReportResult
    data class RetryableFailure(val statusCode: Int? = null) : OnboardingAnalyticsReportResult
    data object NotConfigured : OnboardingAnalyticsReportResult
}

interface OnboardingAnalyticsReporter {
    suspend fun report(envelope: OnboardingAnalyticsEnvelope): OnboardingAnalyticsReportResult
}

object OnboardingAnalyticsPayloadSerializer {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
    }

    fun serialize(envelope: OnboardingAnalyticsEnvelope): String =
        json.encodeToString(OnboardingAnalyticsEnvelope.serializer(), envelope)
}

class OkHttpOnboardingAnalyticsReporter @Inject constructor(
    @OnboardingAnalyticsHttpClient private val client: OkHttpClient,
    private val config: OnboardingAnalyticsConfig,
) : OnboardingAnalyticsReporter {
    override suspend fun report(
        envelope: OnboardingAnalyticsEnvelope,
    ): OnboardingAnalyticsReportResult = withContext(Dispatchers.IO) {
        if (!OnboardingAnalyticsPrivacyValidator.isValid(envelope)) {
            return@withContext OnboardingAnalyticsReportResult.PermanentFailure(0)
        }
        val endpoint = ingestionEndpoint(config)
            ?: return@withContext OnboardingAnalyticsReportResult.NotConfigured
        val payload = OnboardingAnalyticsPayloadSerializer.serialize(envelope)
        val request = try {
            Request.Builder()
                .url(endpoint)
                .post(payload.toRequestBody(JSON_MEDIA_TYPE))
                .header("Accept", "application/json")
                .build()
        } catch (_: IllegalArgumentException) {
            return@withContext OnboardingAnalyticsReportResult.NotConfigured
        }

        val response = try {
            client.newCall(request).execute()
        } catch (error: CancellationException) {
            throw error
        } catch (_: IOException) {
            return@withContext OnboardingAnalyticsReportResult.RetryableFailure()
        } catch (_: Exception) {
            return@withContext OnboardingAnalyticsReportResult.RetryableFailure()
        }

        response.use {
            when {
                it.code in 200..299 -> OnboardingAnalyticsReportResult.Delivered(it.code)
                it.code == 408 || it.code == 425 || it.code == 429 || it.code >= 500 ->
                    OnboardingAnalyticsReportResult.RetryableFailure(it.code)
                else -> OnboardingAnalyticsReportResult.PermanentFailure(it.code)
            }
        }
    }

    private fun ingestionEndpoint(config: OnboardingAnalyticsConfig): HttpUrl? {
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

        val basePath = base.encodedPath.trimEnd('/')
        val eventPath = if (basePath.endsWith(EVENTS_PATH)) basePath else basePath + EVENTS_PATH
        return base.newBuilder()
            .encodedPath(eventPath)
            .build()
    }

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        const val EVENTS_PATH = "/v1/events"
        val LOCALHOST_HOSTS = setOf("localhost", "127.0.0.1", "::1")
    }
}
