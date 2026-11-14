package com.healthmd.data.billing

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.billing.VerifiedPlaySubscription
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Test

class PlaySubscriptionStatusApiTest {
    private fun fixture(test: (MockWebServer, PlaySubscriptionStatusApi) -> Unit) {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer()
        server.useHttps(serverCertificates.sslSocketFactory(), false)
        server.start()
        try {
            val client = OkHttpClient.Builder()
                .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager).build()
            test(server, PlaySubscriptionStatusApi(client, server.url("/")))
        } finally { server.shutdown() }
    }

    @Test fun sendsOnlyTheTokenAndReadsTheVerifiedPeriod() = fixture { server, api ->
        server.enqueue(MockResponse().setBody(
            """{"productId":"health_md_premium_yearly","state":"active","expiresAt":"2026-12-01T10:00:00.000Z","autoRenewing":true,"test":true}""",
        ))
        val result = runBlocking { api.verify("purchase-token") }
        assertThat(result).isEqualTo(VerifiedPlaySubscription(
            "health_md_premium_yearly", "active", java.time.Instant.parse("2026-12-01T10:00:00Z").toEpochMilli(), true,
        ))
        val request = server.takeRequest()
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.path).isEqualTo("/api/health-md/play-subscription")
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertThat(body.keys).containsExactly("purchaseToken")
        assertThat(body.getValue("purchaseToken").jsonPrimitive.content).isEqualTo("purchase-token")
    }

    @Test fun nullDateIsKeptUndated() = fixture { server, api ->
        server.enqueue(MockResponse().setBody("""{"productId":"health_md_premium_weekly","state":"canceled","expiresAt":null,"autoRenewing":false}"""))
        assertThat(runBlocking { api.verify("t") }?.expiresAtMillis).isNull()
    }

    @Test fun denialsRedirectsMalformedAndOversizedAnswersAreNull() = fixture { server, api ->
        for (response in listOf(
            MockResponse().setResponseCode(403).setBody("""{"error":"invalid"}"""),
            MockResponse().setResponseCode(503),
            MockResponse().setResponseCode(302).setHeader("Location", server.url("/elsewhere")),
            MockResponse().setBody("not json"),
            MockResponse().setBody("""{"state":"active"}"""),
            MockResponse().setBody("{\"productId\":\"" + "x".repeat(5_000) + "\",\"state\":\"active\"}"),
        )) {
            server.enqueue(response)
            assertThat(runBlocking { api.verify("t") }).isNull()
        }
    }

    @Test fun blankOrOversizedTokensAreNeverSent() = fixture { server, api ->
        assertThat(runBlocking { api.verify("") }).isNull()
        assertThat(runBlocking { api.verify("x".repeat(30_001)) }).isNull()
        assertThat(server.requestCount).isEqualTo(0)
    }
}
