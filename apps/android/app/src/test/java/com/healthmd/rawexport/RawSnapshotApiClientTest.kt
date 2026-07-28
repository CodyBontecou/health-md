package com.healthmd.rawexport

import com.google.common.truth.Truth.assertThat
import java.io.ByteArrayInputStream
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Test

class RawSnapshotApiClientTest {
    @Test fun rejectsPlainHttpBeforeOpeningSensitiveArtifact() = runTest {
        var opened = false
        val artifact = CompletedRawSnapshot(RawExportFormat.JSON, 2) {
            opened = true
            ByteArrayInputStream("{}".toByteArray())
        }
        val error = try {
            RawSnapshotApiClient(OkHttpClient()).upload("http://example.com/raw", artifact)
            null
        } catch (value: RawSnapshotApiException) {
            value
        }
        assertThat(error).isNotNull()
        assertThat(error!!.retryable).isFalse()
        assertThat(opened).isFalse()
    }

    @Test fun streamsArtifactWithContractHeaders() = runTest {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer()
        server.useHttps(serverCertificates.sslSocketFactory(), false)
        server.start()
        try {
            server.enqueue(MockResponse().setResponseCode(202).setBody("{}"))
            val client = OkHttpClient.Builder()
                .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager)
                .build()
            val artifact = CompletedRawSnapshot(RawExportFormat.NDJSON, 4) {
                ByteArrayInputStream("x\ny\n".toByteArray())
            }
            val result = RawSnapshotApiClient(client).upload(
                endpointUrl = server.url("/raw").toString(),
                artifact = artifact,
                authorizationHeader = "Bearer secret",
                headers = listOf(
                    RawApiHeader("X-HealthMD-Schema", "healthmd.raw-snapshot; version=1"),
                    RawApiHeader("X-HealthMD-Export-ID", "snapshot-id"),
                    RawApiHeader("X-HealthMD-Checksum-SHA256", "a".repeat(64)),
                ),
            )

            assertThat(result.statusCode).isEqualTo(202)
            val request = server.takeRequest()
            assertThat(request.getHeader("Content-Type")).contains("application/x-ndjson")
            assertThat(request.getHeader("X-HealthMD-Export-ID")).isEqualTo("snapshot-id")
            assertThat(request.getHeader("X-HealthMD-Checksum-SHA256")).isEqualTo("a".repeat(64))
            assertThat(request.body.readUtf8()).isEqualTo("x\ny\n")
        } finally {
            server.shutdown()
        }
    }

    @Test fun sharedRedirectFollowingClientNeverReplaysRawUploadAcrossSchemes() = runTest {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val secure = MockWebServer().apply {
            useHttps(serverCertificates.sslSocketFactory(), false)
            start()
        }
        val plaintext = MockWebServer().apply { start() }
        try {
            secure.enqueue(
                MockResponse()
                    .setResponseCode(307)
                    .setHeader("Location", plaintext.url("/stolen")),
            )
            val sharedClient = OkHttpClient.Builder()
                .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager)
                .followRedirects(true)
                .followSslRedirects(true)
                .build()
            val failure = runCatching {
                RawSnapshotApiClient(sharedClient).upload(
                    secure.url("/raw").toString(),
                    CompletedRawSnapshot(RawExportFormat.JSON, 6) { ByteArrayInputStream("secret".toByteArray()) },
                    authorizationHeader = "Bearer sensitive",
                    headers = listOf(RawApiHeader("X-Custom-Secret", "private")),
                )
            }.exceptionOrNull()

            assertThat(failure).isInstanceOf(RawSnapshotApiException::class.java)
            assertThat((failure as RawSnapshotApiException).statusCode).isEqualTo(307)
            assertThat(secure.requestCount).isEqualTo(1)
            assertThat(plaintext.requestCount).isEqualTo(0)
        } finally {
            secure.shutdown()
            plaintext.shutdown()
        }
    }

    @Test fun permitsTwentyUserHeadersPlusSixManagedAndRejectsTwentyOneUsers() = runTest {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer().apply {
            useHttps(serverCertificates.sslSocketFactory(), false)
            start()
            enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        }
        try {
            val client = RawSnapshotApiClient(
                OkHttpClient.Builder()
                    .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager)
                    .build(),
            )
            val users = (1..20).map { RawApiHeader("X-User-$it", "value") }
            val managed = listOf(
                RawApiHeader("X-HealthMD-Schema", "v1"),
                RawApiHeader("X-HealthMD-Export-ID", "id"),
                RawApiHeader("X-HealthMD-Checksum-SHA256", "a"),
                RawApiHeader("X-HealthMD-Artifact-Checksum-SHA256", "b"),
                RawApiHeader("X-HealthMD-Calendar-Zone", "UTC"),
                RawApiHeader("X-HealthMD-Provider", "health_connect"),
            )
            val result = client.upload(
                server.url("/raw").toString(),
                CompletedRawSnapshot(RawExportFormat.JSON, 2) { ByteArrayInputStream("{}".toByteArray()) },
                headers = users + managed,
            )
            assertThat(result.statusCode).isEqualTo(200)
            assertThat(server.takeRequest().headers.names().count { it.startsWith("X-User-", ignoreCase = true) }).isEqualTo(20)

            val tooMany = runCatching {
                client.upload(
                    "https://localhost:1/raw",
                    CompletedRawSnapshot(RawExportFormat.JSON, 2) { ByteArrayInputStream("{}".toByteArray()) },
                    headers = (1..21).map { RawApiHeader("X-User-$it", "value") } + managed,
                )
            }.exceptionOrNull()
            assertThat(tooMany).isInstanceOf(IllegalArgumentException::class.java)
            assertThat(tooMany!!.message).contains("20 user")
        } finally {
            server.shutdown()
        }
    }

    @Test fun exposesVersionedContentTypes() {
        assertThat(RawSnapshotApiClient.contentType(RawExportFormat.JSON).toString())
            .isEqualTo("application/vnd.healthmd.raw-snapshot+json; version=1; charset=utf-8")
        assertThat(RawSnapshotApiClient.contentType(RawExportFormat.NDJSON).toString())
            .isEqualTo("application/x-ndjson; charset=utf-8")
    }
}
