package com.healthmd.domain.billing

import com.healthmd.data.billing.ClinicLicensingClient
import com.healthmd.data.billing.ClinicLicensingConfiguration
import com.healthmd.data.billing.ClinicLicensingException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ClinicLicensingClientTest {
    @Test fun onlyRecognizedLicensingDenialsClearRecoveryProof() = runBlocking {
        for ((status, body, inactive) in listOf(
            Triple(403, "", false), Triple(403, "<html>denied</html>", false),
            Triple(403, """{"error":"native_client_required"}""", false),
            Triple(403, """{"error":"invitation_unavailable"}""", true),
            Triple(403, """{"error":"sponsorship_inactive"}""", true),
            Triple(401, """{"error":"unauthorized"}""", true),
            Triple(500, """{"error":"sponsorship_inactive"}""", false),
        )) {
            val transport = OkHttpClient.Builder().addInterceptor { chain ->
                okhttp3.Response.Builder().request(chain.request()).protocol(okhttp3.Protocol.HTTP_1_1)
                    .code(status).message("synthetic").body(body.toResponseBody()).build()
            }.build()
            try {
                val api = ClinicLicensingClient(ClinicLicensingConfiguration(
                    "https://licensing.clinic.example/", "https://licensing.clinic.example/",
                    "healthmd-clinic-access", mapOf("test" to byteArrayOf(1))), transport)
                try {
                    api.redeem("i".repeat(43), "fictional-installation", "s".repeat(43))
                    throw AssertionError("Expected failure")
                } catch (error: ClinicLicensingException) {
                    org.junit.Assert.assertEquals(inactive, error.inactive)
                }
            } finally {
                transport.dispatcher.executorService.shutdown()
                transport.connectionPool.evictAll()
            }
        }
    }

    @Test fun blockedTransportCannotKeepEnrollmentBusyAfterDeadline() = runBlocking {
        val release = CountDownLatch(1)
        val client = OkHttpClient.Builder().addInterceptor {
            release.await(3, TimeUnit.SECONDS)
            throw java.io.IOException("synthetic blocked transport")
        }.build()
        val licensing = ClinicLicensingClient(ClinicLicensingConfiguration(
            "https://licensing.clinic.example/", "https://licensing.clinic.example/",
            "healthmd-clinic-access", mapOf("test" to byteArrayOf(1))), client, 100)
        val start = System.nanoTime()
        try {
            licensing.redeem("x".repeat(43), "fictional-installation", "s".repeat(43))
            throw AssertionError("Expected a bounded network failure")
        } catch (error: ClinicLicensingException) {
            assertFalse(error.inactive)
            assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start) < 1500)
        } finally {
            release.countDown()
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }
}
