package com.healthmd.data.drive

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Before
import org.junit.Test

class GoogleDriveRestClientTest {
    private lateinit var server: MockWebServer
    private lateinit var api: OkHttpGoogleDriveApi

    @Before
    fun setUp() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder()
            .addTrustedCertificate(certificate.certificate)
            .build()
        server = MockWebServer().apply {
            useHttps(serverCertificates.sslSocketFactory(), false)
            start()
        }
        val base = server.url("/").toString().removeSuffix("/")
        api = OkHttpGoogleDriveApi(
            client = OkHttpClient.Builder().sslSocketFactory(
                clientCertificates.sslSocketFactory(),
                clientCertificates.trustManager,
            ).build(),
            apiBaseUrl = "$base/drive/v3",
            uploadBaseUrl = "$base/upload/drive/v3",
            additionalAllowedSessionHosts = setOf("localhost"),
        )
    }

    @After
    fun tearDown() = server.shutdown()

    @Test
    fun `about parses stable permission authority without exposing account data`() = runTest {
        server.enqueue(MockResponse().setBody("""{"user":{"permissionId":"permission-1"}}"""))

        assertThat(api.about("token")).isEqualTo(DriveApiResult.Success(GoogleDriveAbout("permission-1")))
        assertThat(server.takeRequest().path).isEqualTo("/drive/v3/about?fields=user(permissionId)")
    }

    @Test
    fun `forbidden quota and rate reasons map to semantic errors`() = runTest {
        server.enqueue(MockResponse().setResponseCode(403).setBody(errorBody("storageQuotaExceeded")))
        server.enqueue(MockResponse().setResponseCode(403).setBody(errorBody("userRateLimitExceeded")))

        assertThat(api.about("token")).isEqualTo(
            DriveApiResult.Failure(GoogleDriveErrorId.QUOTA_EXCEEDED),
        )
        assertThat(api.about("token")).isEqualTo(
            DriveApiResult.Failure(GoogleDriveErrorId.RATE_LIMITED, retryable = true),
        )
    }

    @Test
    fun `resumable status probe recovers acknowledged offset`() = runTest {
        server.enqueue(MockResponse().setResponseCode(308).setHeader("Range", "bytes=0-4"))

        val result = api.queryUpload("token", server.url("/session/1").toString(), totalSize = 10)

        assertThat(result).isEqualTo(
            DriveApiResult.Success(GoogleDriveUploadStatus(acknowledgedBytes = 5, complete = false)),
        )
        val request = server.takeRequest()
        assertThat(request.method).isEqualTo("PUT")
        assertThat(request.getHeader("Content-Range")).isEqualTo("bytes */10")
        assertThat(request.bodySize).isEqualTo(0)
    }

    @Test
    fun `empty resumable upload uses valid zero-byte content range and parses final metadata`() = runTest {
        server.enqueue(MockResponse().setBody(metadataJson(size = 0, md5 = "d41d8cd98f00b204e9800998ecf8427e")))

        val result = api.upload("token", server.url("/session/empty").toString(), byteArrayOf(), 0)

        assertThat(result).isInstanceOf(DriveApiResult.Success::class.java)
        val request = server.takeRequest()
        assertThat(request.getHeader("Content-Range")).isEqualTo("bytes */0")
        assertThat(request.bodySize).isEqualTo(0)
    }

    private fun errorBody(reason: String): String =
        """{"error":{"errors":[{"reason":"$reason"}]}}"""

    private fun metadataJson(size: Long, md5: String): String =
        """{"id":"file-1","name":"file.md","mimeType":"text/markdown","parents":["folder-1"],"version":"2","size":"$size","md5Checksum":"$md5","trashed":false}"""
}
