package com.healthmd.data.attribution

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class OkHttpCampaignAttributionReporterTest {
    private lateinit var server: MockWebServer
    private lateinit var client: OkHttpClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        client = OkHttpClient.Builder()
            .connectTimeout(1, TimeUnit.SECONDS)
            .readTimeout(1, TimeUnit.SECONDS)
            .writeTimeout(1, TimeUnit.SECONDS)
            .callTimeout(2, TimeUnit.SECONDS)
            .followRedirects(false)
            .retryOnConnectionFailure(false)
            .addNetworkInterceptor { chain ->
                chain.proceed(chain.request().newBuilder().removeHeader("User-Agent").build())
            }
            .build()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun postsAllowlistedJsonContractAndOptionalAuthorization() = runTest {
        server.enqueue(MockResponse().setResponseCode(202))
        val reporter = reporter(token = "throttle-token")

        val result = reporter.report(testEvent())

        assertThat(result).isEqualTo(CampaignAttributionReportResult.Delivered(202))
        val request = server.takeRequest()
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.path).isEqualTo("/attribution/v1/installs")
        assertThat(request.getHeader("Content-Type")).startsWith("application/json")
        assertThat(request.getHeader("Accept")).isEqualTo("application/json")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer throttle-token")
        assertThat(request.getHeader("User-Agent")).isNull()

        val body = request.body.readUtf8()
        assertThat(Json.parseToJsonElement(body).jsonObject.keys).containsExactly(
            "schemaVersion",
            "eventId",
            "installId",
            "eventName",
            "occurredAt",
            "platform",
            "appVersion",
            "buildNumber",
            "campaignToken",
            "source",
            "medium",
            "contentAngle",
            "referrerClickTimestampSeconds",
            "installBeginTimestampSeconds",
        )
        assertThat(body).doesNotContain("installReferrer")
        assertThat(body).doesNotContain("rawReferrer")
        assertThat(body).doesNotContain("health")
        assertThat(body).doesNotContain("filePath")
    }

    @Test
    fun omitsUnavailableOptionalPlayTimestamps() {
        val payload = CampaignAttributionPayloadSerializer.serialize(
            testEvent().copy(
                referrerClickTimestampSeconds = null,
                installBeginTimestampSeconds = null,
            )
        )
        val keys = Json.parseToJsonElement(payload).jsonObject.keys

        assertThat(keys).doesNotContain("referrerClickTimestampSeconds")
        assertThat(keys).doesNotContain("installBeginTimestampSeconds")
    }

    @Test
    fun classifiesPermanentHttpRejections() = runTest {
        listOf(400, 409, 413).forEach { statusCode ->
            server.enqueue(MockResponse().setResponseCode(statusCode))
            assertThat(reporter().report(testEvent()))
                .isEqualTo(CampaignAttributionReportResult.PermanentFailure(statusCode))
        }
    }

    @Test
    fun preservesPendingEventsForAuthorizationConfigurationFailures() = runTest {
        listOf(401, 403).forEach { statusCode ->
            server.enqueue(MockResponse().setResponseCode(statusCode))
            assertThat(reporter().report(testEvent()))
                .isEqualTo(CampaignAttributionReportResult.NotConfigured)
        }
    }

    @Test
    fun classifiesTimeoutRateLimitAndServerResponsesAsRetryable() = runTest {
        listOf(408, 429, 500, 503).forEach { statusCode ->
            server.enqueue(MockResponse().setResponseCode(statusCode))
            assertThat(reporter().report(testEvent()))
                .isEqualTo(CampaignAttributionReportResult.RetryableFailure(statusCode))
        }
    }

    @Test
    fun networkFailureIsRetryable() = runTest {
        val endpoint = server.url("/attribution").toString()
        server.shutdown()
        val reporter = OkHttpCampaignAttributionReporter(
            client = client,
            config = CampaignAttributionConfig(endpoint, null, isDebug = true),
        )

        assertThat(reporter.report(testEvent()))
            .isEqualTo(CampaignAttributionReportResult.RetryableFailure())

        server = MockWebServer()
        server.start()
    }

    @Test
    fun missingOrUnsafeEndpointDoesNotSendAndPreservesReporterState() = runTest {
        val missing = OkHttpCampaignAttributionReporter(
            client,
            CampaignAttributionConfig("", null, isDebug = true),
        )
        val releaseHttp = OkHttpCampaignAttributionReporter(
            client,
            CampaignAttributionConfig(server.url("/").toString(), null, isDebug = false),
        )
        val invalidToken = OkHttpCampaignAttributionReporter(
            client,
            CampaignAttributionConfig(
                server.url("/").toString(),
                "token\nheader-injection",
                isDebug = true,
            ),
        )

        assertThat(missing.report(testEvent()))
            .isEqualTo(CampaignAttributionReportResult.NotConfigured)
        assertThat(releaseHttp.report(testEvent()))
            .isEqualTo(CampaignAttributionReportResult.NotConfigured)
        assertThat(invalidToken.report(testEvent()))
            .isEqualTo(CampaignAttributionReportResult.NotConfigured)
        assertThat(server.requestCount).isEqualTo(0)
    }

    private fun reporter(token: String? = null) = OkHttpCampaignAttributionReporter(
        client = client,
        config = CampaignAttributionConfig(
            endpointUrl = server.url("/attribution/").toString(),
            ingestToken = token,
            isDebug = true,
        ),
    )
}
