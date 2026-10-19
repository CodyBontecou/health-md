package com.healthmd.myselfclaim

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.*
import org.junit.Test

class MyselfClaimApiTest {
    private fun fixture(test: (MockWebServer, MyselfClaimApi) -> Unit) {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer()
        server.useHttps(serverCertificates.sslSocketFactory(), false)
        server.start()
        try {
            val client = OkHttpClient.Builder()
                .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager)
                .followRedirects(false).followSslRedirects(false).build()
            test(server, MyselfClaimApi(client, server.url("/")))
        } finally { server.shutdown() }
    }

    @Test fun sendsOnlyReviewedPurchaseProofAndValidatesTheReturnedTicket() = fixture { server, api ->
        val url = server.url("/claim").newBuilder().fragment("a".repeat(43)).build().toString()
        server.enqueue(MockResponse().setBody("{\"claimUrl\":\"$url\"}"))
        assertEquals(url, runBlocking { api.verify("fixture-purchase-proof") })
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/migration/proof", request.path)
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals(setOf("app", "store", "kind", "proof"), body.keys)
        assertEquals("health.md", body.getValue("app").jsonPrimitive.content)
        assertEquals("android", body.getValue("store").jsonPrimitive.content)
        assertEquals("iap", body.getValue("kind").jsonPrimitive.content)
        assertEquals("fixture-purchase-proof", body.getValue("proof").jsonPrimitive.content)
    }

    @Test fun rejectsRedirectsServerDenialsMalformedAndOversizedResponses() = fixture { server, api ->
        for (response in listOf(
            MockResponse().setResponseCode(302).setHeader("Location", server.url("/leak")),
            MockResponse().setResponseCode(403).setBody("{\"error\":\"another account\"}"),
            MockResponse().setResponseCode(503),
            MockResponse().setBody("not JSON"),
            MockResponse().setBody("x".repeat(40_001)),
            MockResponse().setBody("{}"),
        )) {
            val before = server.requestCount
            server.enqueue(response)
            assertTrue(runCatching { runBlocking { api.verify("fixture") } }.isFailure)
            assertEquals(before + 1, server.requestCount)
        }
    }

    @Test fun rejectsUntrustedBrowserDestinationsAndMalformedTickets() = fixture { server, api ->
        val base = server.url("/claim").toString()
        val ticket = "a".repeat(43)
        for (url in listOf("https://untrusted.invalid/claim#$ticket", base.replace("https:", "http:") + "#$ticket",
            base.replace("localhost", "user@localhost") + "#$ticket", "$base?proof=bad#$ticket",
            "$base/extra#$ticket", "$base#short", "$base#${"%61".repeat(43)}",
            base.replace(":${server.port}", ":443") + "#$ticket")) {
            assertTrue(url, runCatching { api.validateClaimUrl(url) }.isFailure)
        }
    }
}
