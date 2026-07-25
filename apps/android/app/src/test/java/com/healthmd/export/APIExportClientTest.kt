package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportClient
import com.healthmd.data.export.APIExportClientException
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.domain.model.ExportFailureReason
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Before
import org.junit.Test

class APIExportClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: APIExportClient

    @Before
    fun setUp() {
        val certificate = HeldCertificate.Builder()
            .addSubjectAlternativeName("localhost")
            .build()
        val serverCertificates = HandshakeCertificates.Builder()
            .heldCertificate(certificate)
            .build()
        val clientCertificates = HandshakeCertificates.Builder()
            .addTrustedCertificate(certificate.certificate)
            .build()

        server = MockWebServer()
        server.useHttps(serverCertificates.sslSocketFactory(), false)
        server.start()
        client = APIExportClient(
            OkHttpClient.Builder()
                .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager)
                .followRedirects(true)
                .followSslRedirects(true)
                .build()
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun postsJsonWithAuthorizationAndAcceptsAny2xx() = runTest {
        server.enqueue(MockResponse().setResponseCode(202).setBody("accepted"))

        val result = client.upload(
            endpointUrl = server.url("/healthmd").toString(),
            payload = "{\"schema\":\"healthmd.api_export\"}",
            authorizationHeader = "Bearer secret",
            requestHeaders = listOf(
                APIExportRequestHeader("X-API-Key", "api-secret"),
                APIExportRequestHeader("Accept", "application/health+json"),
            ),
        )

        assertThat(result.statusCode).isEqualTo(202)
        val request = server.takeRequest()
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.getHeader("Content-Type")).startsWith("application/json")
        assertThat(request.getHeader("Accept")).isEqualTo("application/health+json")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer secret")
        assertThat(request.getHeader("X-API-Key")).isEqualTo("api-secret")
        assertThat(request.getHeader("User-Agent")).isEqualTo("Health.md Android API Export")
        assertThat(request.body.readUtf8()).contains("healthmd.api_export")
    }

    @Test
    fun postsToHttpEndpoint() = runTest {
        val httpServer = MockWebServer()
        httpServer.start()
        try {
            httpServer.enqueue(MockResponse().setResponseCode(200))

            val result = client.upload(
                endpointUrl = httpServer.url("/healthmd").toString(),
                payload = "{}",
                authorizationHeader = null,
                requestHeaders = emptyList(),
            )

            assertThat(result.statusCode).isEqualTo(200)
            assertThat(httpServer.takeRequest().method).isEqualTo("POST")
        } finally {
            httpServer.shutdown()
        }
    }

    @Test
    fun rawAuthorizationOverridesConvenienceAuthorization() = runTest {
        server.enqueue(MockResponse().setResponseCode(200))

        client.upload(
            endpointUrl = server.url("/healthmd").toString(),
            payload = "{}",
            authorizationHeader = "Bearer old-token",
            requestHeaders = listOf(APIExportRequestHeader("Authorization", "Token custom-token")),
        )

        assertThat(server.takeRequest().getHeader("Authorization")).isEqualTo("Token custom-token")
    }

    @Test
    fun rejectsUnsafeHeadersBeforeSending() = runTest {
        val error = runCatching {
            client.upload(
                endpointUrl = server.url("/healthmd").toString(),
                payload = "{}",
                authorizationHeader = null,
                requestHeaders = listOf(APIExportRequestHeader("Host", "attacker.example")),
            )
        }.exceptionOrNull() as APIExportClientException

        assertThat(error.failureReason).isEqualTo(ExportFailureReason.INVALID_API_ENDPOINT)
        assertThat(error.retryable).isFalse()
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun followsRedirectAndPreservesPostFor307() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(307)
                .addHeader("Location", server.url("/collect"))
        )
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.upload(
            endpointUrl = server.url("/redirect").toString(),
            payload = "{\"schema\":\"healthmd.api_export\"}",
            authorizationHeader = "Bearer secret",
            requestHeaders = emptyList(),
        )

        assertThat(result.statusCode).isEqualTo(204)
        assertThat(server.requestCount).isEqualTo(2)
        assertThat(server.takeRequest().path).isEqualTo("/redirect")
        val redirectedRequest = server.takeRequest()
        assertThat(redirectedRequest.path).isEqualTo("/collect")
        assertThat(redirectedRequest.method).isEqualTo("POST")
        assertThat(redirectedRequest.getHeader("Authorization")).isEqualTo("Bearer secret")
        assertThat(redirectedRequest.body.readUtf8()).contains("healthmd.api_export")
    }
}
