package com.healthmd.data.onboardinganalytics

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class OkHttpOnboardingAnalyticsReporterTest {
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
    fun postsToEventsEndpointWithoutAmbientIdentifiers() = runTest {
        server.enqueue(MockResponse().setResponseCode(202))

        assertThat(reporter().report(envelope()))
            .isEqualTo(OnboardingAnalyticsReportResult.Delivered(202))

        val request = server.takeRequest()
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.path).isEqualTo("/analytics/v1/events")
        assertThat(request.getHeader("Accept")).isEqualTo("application/json")
        assertThat(request.getHeader("User-Agent")).isNull()
        assertThat(request.getHeader("Authorization")).isNull()
        assertThat(request.getHeader("Cookie")).isNull()
    }

    @Test
    fun fullEventsEndpointIsNotAppendedTwice() = runTest {
        server.enqueue(MockResponse().setResponseCode(202))
        val endpoint = server.url("/analytics/v1/events").toString()

        assertThat(
            OkHttpOnboardingAnalyticsReporter(
                client,
                OnboardingAnalyticsConfig(endpoint, isDebug = true),
            ).report(envelope())
        ).isEqualTo(OnboardingAnalyticsReportResult.Delivered(202))

        assertThat(server.takeRequest().path).isEqualTo("/analytics/v1/events")
    }

    @Test
    fun productionRejectsPlainHttpBeforeSending() = runTest {
        val endpoint = server.url("/analytics").toString()

        assertThat(
            OkHttpOnboardingAnalyticsReporter(
                client,
                OnboardingAnalyticsConfig(endpoint, isDebug = false),
            ).report(envelope())
        ).isEqualTo(OnboardingAnalyticsReportResult.NotConfigured)
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun classifiesRetryableResponses() = runTest {
        listOf(408, 425, 429, 500, 503).forEach { statusCode ->
            server.enqueue(MockResponse().setResponseCode(statusCode))
            assertThat(reporter().report(envelope()))
                .isEqualTo(OnboardingAnalyticsReportResult.RetryableFailure(statusCode))
        }
    }

    @Test
    fun classifiesOtherNonSuccessResponsesAsPermanent() = runTest {
        listOf(400, 401, 403, 409, 413).forEach { statusCode ->
            server.enqueue(MockResponse().setResponseCode(statusCode))
            assertThat(reporter().report(envelope()))
                .isEqualTo(OnboardingAnalyticsReportResult.PermanentFailure(statusCode))
        }
    }

    @Test
    fun networkFailureIsRetryable() = runTest {
        val endpoint = server.url("/analytics").toString()
        server.shutdown()

        assertThat(
            OkHttpOnboardingAnalyticsReporter(
                client,
                OnboardingAnalyticsConfig(endpoint, isDebug = true),
            ).report(envelope())
        ).isEqualTo(OnboardingAnalyticsReportResult.RetryableFailure())

        server = MockWebServer()
        server.start()
    }

    private fun reporter() = OkHttpOnboardingAnalyticsReporter(
        client,
        OnboardingAnalyticsConfig(server.url("/analytics/").toString(), isDebug = true),
    )

    private fun envelope() = OnboardingAnalyticsEnvelope(
        installId = "11111111-1111-4111-8111-111111111111",
        events = listOf(
            OnboardingAnalyticsEvent(
                eventId = "22222222-2222-4222-8222-222222222222",
                eventName = PricingOnboardingEventName.STEP_VIEWED.wireName,
                properties = OnboardingAnalyticsProperties(
                    appVersion = "1.5.4",
                    buildNumber = "25",
                    onboardingStep = OnboardingAnalyticsStep.WELCOME.wireName,
                ),
            )
        ),
    )
}
