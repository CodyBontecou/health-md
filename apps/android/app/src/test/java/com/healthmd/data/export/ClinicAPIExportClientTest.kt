package com.healthmd.data.export

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.EntitlementRepository
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.*
import org.junit.Test

/** Exercise the real TLS uploader; signed destination/consent policy has its own shared fixtures. */
class ClinicAPIExportClientTest {
    private class Access(val endpoint: String) : EntitlementRepository {
        var personal = false
        var sharing = true
        override val isUnlocked = MutableStateFlow(false)
        override val sponsoredEndpoint = MutableStateFlow<String?>(endpoint)
        override suspend fun verifyAccess() = personal
        override suspend fun verifyExportAccess(target: ExportTarget, endpoint: String?) =
            personal || (sharing && target == ExportTarget.API_ENDPOINT && endpoint == this.endpoint)
        override suspend fun clinicUploadAuthorization(endpoint: String) =
            "Bearer synthetic-clinic-token".takeIf { sharing && endpoint == this.endpoint }
        override fun refresh() = Unit
        override fun debugSetUnlocked(unlocked: Boolean) { personal = unlocked }
        override fun debugReset() = Unit
    }

    @Test fun clinicDeliveryRejectsRedirectsAndRechecksConsentOnEveryRetry() = runBlocking {
        val certificate = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val serverTLS = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTLS = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val approved = MockWebServer()
        val other = MockWebServer()
        approved.useHttps(serverTLS.sslSocketFactory(), false)
        other.useHttps(serverTLS.sslSocketFactory(), false)
        approved.start(); other.start()
        val transport = OkHttpClient.Builder().sslSocketFactory(clientTLS.sslSocketFactory(), clientTLS.trustManager).build()
        val access = Access(approved.url("/upload").toString())
        val uploader = APIExportClient(transport, access)
        suspend fun upload(endpoint: String = access.endpoint) = uploader.upload(endpoint, "{\"synthetic\":true}",
            "Bearer unrelated-personal-token", listOf(APIExportRequestHeader("X-Personal", "private")))
        try {
            // 307 would replay the entire POST body and credential if redirects were enabled.
            for (status in listOf(301, 302, 303, 307, 308)) {
                approved.enqueue(MockResponse().setResponseCode(status).addHeader("Location", other.url("/stolen")))
                try { upload(); fail("Redirect must fail") }
                catch (error: APIExportClientException) {
                    assertEquals(status, error.statusCode)
                    assertFalse(error.retryable)
                }
                val request = approved.takeRequest(2, TimeUnit.SECONDS)!!
                assertEquals("Bearer synthetic-clinic-token", request.getHeader("Authorization"))
                assertNull(request.getHeader("X-Personal"))
            }
            assertEquals(0, other.requestCount)
            try { upload(other.url("/upload").toString()); fail("Edited destination must not transmit") }
            catch (error: APIExportClientException) { assertEquals(ExportFailureReason.PAYWALL_REQUIRED, error.failureReason) }
            assertEquals(0, other.requestCount)
            approved.enqueue(MockResponse().setResponseCode(503).setBody("private echoed patient response"))
            try { upload(); fail("Expected retryable rejection") }
            catch (error: APIExportClientException) {
                assertTrue(error.retryable)
                assertFalse(error.message!!.contains("patient response"))
            }
            val sent = approved.requestCount
            access.sharing = false
            for (endpoint in listOf(access.endpoint, other.url("/upload").toString(), access.endpoint + "/changed")) {
                try { upload(endpoint); fail("Consent or destination denial must prevent transmission") }
                catch (error: APIExportClientException) { assertEquals(ExportFailureReason.PAYWALL_REQUIRED, error.failureReason) }
            }
            assertEquals(sent, approved.requestCount)
            assertEquals(0, other.requestCount)

            // A personal purchase restores arbitrary destinations, without forwarding clinic credentials.
            access.personal = true
            other.enqueue(MockResponse().setResponseCode(202).setBody("personal response"))
            assertEquals(202, upload(other.url("/personal").toString()).statusCode)
            val personal = other.takeRequest(2, TimeUnit.SECONDS)!!
            assertEquals("Bearer unrelated-personal-token", personal.getHeader("Authorization"))
            assertEquals("private", personal.getHeader("X-Personal"))

            // Even with personal access, a managed clinic keeps its separate credential/response rules.
            access.sharing = true
            approved.enqueue(MockResponse().setResponseCode(202).setBody("private clinic response"))
            assertNull(upload().responseBodyPreview)
            // Discard the earlier 503 request before checking the new managed request.
            approved.takeRequest(2, TimeUnit.SECONDS)
            val managed = approved.takeRequest(2, TimeUnit.SECONDS)!!
            assertEquals("Bearer synthetic-clinic-token", managed.getHeader("Authorization"))
            assertNull(managed.getHeader("X-Personal"))
        } finally {
            approved.shutdown(); other.shutdown()
            transport.dispatcher.executorService.shutdown()
            transport.connectionPool.evictAll()
        }
    }
}
