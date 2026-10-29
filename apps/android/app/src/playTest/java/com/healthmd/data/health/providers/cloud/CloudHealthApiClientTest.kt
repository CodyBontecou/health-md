package com.healthmd.data.health.providers.cloud

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.oauth.InMemoryOAuthTokenStore
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthToken
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class CloudHealthApiClientTest {
    @Test
    fun rawResponsePreservesExactBytesAndExistingGetJsonStillParses() = runTest {
        val bytes = "{\n  \"value\": 7, \"order\": [2, 1]\n}".toByteArray()
        val client = client(response = CloudHttpResponse(
            status = 200,
            contentType = "application/json",
            body = bytes,
        ))

        val raw = client.getRawJsonResponse("fitbit", "https://api.example.test/v1/native")
        assertThat(raw.responseBytes).isEqualTo(bytes)
        assertThat(raw.responseText).isEqualTo(bytes.toString(Charsets.UTF_8))
        assertThat(raw.json.jsonObject.getValue("value").jsonPrimitive.int).isEqualTo(7)

        val parsed = client.getJson("fitbit", "https://api.example.test/v1/native")
        assertThat(parsed.jsonObject.getValue("order").toString()).isEqualTo("[2,1]")
    }

    @Test
    fun successfulMalformedJsonIsStillObservedAsExactBytesBeforeParsedClientFails() = runTest {
        val exact = byteArrayOf('{'.code.toByte(), 0xC3.toByte(), 0x28, '}'.code.toByte())
        val observed = mutableListOf<CloudHealthRawResponse>()
        val client = client(
            response = CloudHttpResponse(200, "application/json; charset=UTF-8", body = exact),
            observer = CloudRawResponseObserver { observed += it },
        )

        val raw = client.getRawJsonResponse("fitbit", "https://api.example.test/native")
        assertThat(raw.responseBytes).isEqualTo(exact)
        assertThat(raw.responseText).isNull()
        assertThat(raw.jsonValid).isFalse()
        assertThat(runCatching { client.getJson("fitbit", "https://api.example.test/native") }.exceptionOrNull())
            .isInstanceOf(CloudHealthPayloadException::class.java)
        assertThat(observed).hasSize(2)
    }

    @Test
    fun validUtf8ButInvalidJsonPreservesBytesWithoutTruthfulResponseText() = runTest {
        val exact = "provider maintenance".toByteArray()
        val raw = client(
            response = CloudHttpResponse(200, "application/json; charset=UTF-8", body = exact),
        ).getRawJsonResponse("fitbit", "https://api.example.test/native")

        assertThat(raw.responseBytes).isEqualTo(exact)
        assertThat(raw.responseText).isNull()
        assertThat(raw.jsonValid).isFalse()
    }

    @Test
    fun contentTypeCharsetControlsTextDecodingWithoutChangingBytes() = runTest {
        val bytes = "{\"label\":\"café\"}".toByteArray(Charsets.ISO_8859_1)
        val raw = client(response = CloudHttpResponse(
            status = 200,
            contentType = "Application/JSON; profile=ignored; charset=ISO-8859-1",
            body = bytes,
        )).getRawJsonResponse("oura", "https://api.example.test/usercollection")

        assertThat(raw.responseBytes).isEqualTo(bytes)
        assertThat(raw.responseText).isEqualTo("{\"label\":\"café\"}")
        assertThat(raw.contentType).isEqualTo("application/json")
        assertThat(raw.charset).isEqualTo("ISO-8859-1")
        assertThat(raw.json.jsonObject.getValue("label").jsonPrimitive.content).isEqualTo("café")
    }

    @Test
    fun metadataIncludesOnlyAllowlistedHeadersAndSafeQueryValues() = runTest {
        val fetchedAt = Instant.parse("2026-07-15T12:34:56.123456789Z")
        val raw = client(
            response = CloudHttpResponse(
                status = 206,
                contentType = "application/json; charset=UTF-8",
                headers = mapOf(
                    "etag" to "\"revision-3\"",
                    "Last-Modified" to "Wed, 15 Jul 2026 12:00:00 GMT",
                    "x-request-id" to "request-123",
                    "Set-Cookie" to "session=secret",
                    "Authorization" to "Bearer leaked",
                    "X-Arbitrary" to "private",
                ),
                body = "{}".toByteArray(),
            ),
            clock = { fetchedAt },
        ).getRawJsonResponse(
            providerId = "whoop",
            url = "https://api.example.test/private/user-123/records",
            query = linkedMapOf(
                "start" to "2026-07-01T00:00:00Z",
                "end" to "2026-07-02T00:00:00Z",
                "limit" to "100",
                "cursor" to "secret-cursor",
                "access_token" to "oauth-secret",
                "client_secret" to "provider-secret",
                "date" to "not-a-date-secret",
            ),
            pageOrdinal = 4,
        )

        assertThat(raw.queryMetadata).containsExactly(
            "start", "2026-07-01T00:00:00Z",
            "end", "2026-07-02T00:00:00Z",
            "limit", "100",
        )
        assertThat(raw.responseHeaders).containsExactly(
            "ETag", "\"revision-3\"",
            "Last-Modified", "Wed, 15 Jul 2026 12:00:00 GMT",
            "X-Request-ID", "request-123",
        )
        assertThat(raw.endpointIdentifier).startsWith("whoop:")
        assertThat(raw.endpointIdentifier).doesNotContain("user-123")
        assertThat(raw.providerId).isEqualTo("whoop")
        assertThat(raw.fetchedAt).isEqualTo(fetchedAt)
        assertThat(raw.httpStatus).isEqualTo(206)
        assertThat(raw.pageOrdinal).isEqualTo(4)
        val exposed = raw.endpointIdentifier + raw.queryMetadata + raw.responseHeaders
        assertThat(exposed).doesNotContain("oauth-secret")
        assertThat(exposed).doesNotContain("secret-cursor")
        assertThat(exposed).doesNotContain("session=secret")
        assertThat(exposed).doesNotContain("Bearer leaked")
    }

    @Test
    fun httpErrorsNeverLeakBodiesOrNotifyObservers() = runTest {
        val notifications = AtomicInteger(0)
        val errorBody = "{\"access_token\":\"secret-token\",\"health\":\"private\"}".toByteArray()
        val client = client(
            response = CloudHttpResponse(status = 429, body = errorBody),
            observer = CloudRawResponseObserver { notifications.incrementAndGet() },
        )

        val failure = runCatching {
            client.getRawJsonResponse(
                providerId = "fitbit",
                url = "https://api.example.test/data/private-user",
                query = mapOf("cursor" to "secret-cursor"),
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(CloudHealthRequestException::class.java)
        assertThat(failure!!.message).isEqualTo("fitbit cloud request failed (429)")
        assertThat(failure.message).doesNotContain("secret-token")
        assertThat(failure.message).doesNotContain("private")
        assertThat(failure.cause).isNull()
        assertThat(notifications.get()).isEqualTo(0)
    }

    @Test
    fun nonHttpsNonLoopbackEndpointIsRejectedBeforeTransportOrTokenUse() = runTest {
        val calls = AtomicInteger(0)
        val client = client(transport = CloudHttpTransport {
            calls.incrementAndGet()
            CloudHttpResponse(200, body = "{}".toByteArray())
        })

        val failure = runCatching {
            client.getJson("fitbit", "http://api.example.test/private/path")
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(failure!!.message).isEqualTo("Cloud API requests require HTTPS")
        assertThat(failure.message).doesNotContain("private/path")
        assertThat(calls.get()).isEqualTo(0)
    }

    @Test
    fun observerIsSuspendingBackpressuredAndReceivesOnePageAtATime() = runTest {
        val entered = CompletableDeferred<CloudHealthRawResponse>()
        val release = CompletableDeferred<Unit>()
        val notifications = mutableListOf<Int>()
        val client = client(
            response = CloudHttpResponse(200, body = "{\"ok\":true}".toByteArray()),
            observer = CloudRawResponseObserver { response ->
                notifications += response.pageOrdinal
                entered.complete(response)
                release.await()
            },
        )

        val request = async {
            client.getJson(
                providerId = "oura",
                url = "https://api.example.test/native/page",
            )
        }
        val observed = entered.await()
        assertThat(observed.pageOrdinal).isEqualTo(1)
        assertThat(request.isCompleted).isFalse()
        assertThat(notifications).containsExactly(1)

        release.complete(Unit)
        assertThat(request.await().jsonObject.getValue("ok").jsonPrimitive.boolean).isTrue()
    }

    @Test
    fun responseBytesAreDefensivelyCopiedAcrossObserverAndCaller() = runTest {
        val source = "{\"exact\":1}".toByteArray()
        val observer = CloudRawResponseObserver { response ->
            response.responseBytes.fill(0)
        }
        val raw = client(
            response = CloudHttpResponse(200, body = source),
            observer = observer,
        ).getRawJsonResponse("withings", "https://api.example.test/native")

        source.fill(1)
        assertThat(raw.responseBytes).isEqualTo("{\"exact\":1}".toByteArray())
    }

    @Test
    fun fidelityDeclarationsSerializeToStableManifestValues() {
        val values = CloudProviderFidelity.entries.map { fidelity ->
            Json.encodeToString(
                CloudProviderFidelityDeclaration.serializer(),
                CloudProviderFidelityDeclaration("provider", fidelity),
            )
        }
        assertThat(values).containsExactly(
            "{\"providerId\":\"provider\",\"fidelity\":\"native_api_payload\"}",
            "{\"providerId\":\"provider\",\"fidelity\":\"normalized_only\"}",
            "{\"providerId\":\"provider\",\"fidelity\":\"unsupported\"}",
            "{\"providerId\":\"provider\",\"fidelity\":\"health_connect_api_projected\"}",
        ).inOrder()
    }

    @Test
    fun replacementOrDisconnectDuringRequestPreventsObservationAndReturn() = runTest {
        for (disconnect in listOf(false, true)) {
            val store = InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "accepted")))
            val manager = OAuthAuthorizationManager(OAuthConfigRegistry(emptyList()), store)
            val started = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val observed = mutableListOf<CloudHealthRawResponse>()
            val client = CloudHealthApiClient.forTesting(manager, transport = CloudHttpTransport { request ->
                assertThat(request.authorization).isEqualTo("Bearer accepted")
                started.complete(Unit)
                release.await()
                CloudHttpResponse(200, body = "{\"value\":7}".toByteArray())
            }, responseObserver = CloudRawResponseObserver { observed += it })
            val pending = async { runCatching { client.getRawJsonResponse("whoop", "https://api.example.test/native") } }
            started.await()
            if (disconnect) store.clearToken("whoop") else store.saveToken(OAuthToken("whoop", "replacement"))
            release.complete(Unit)
            assertThat(pending.await().exceptionOrNull()).isInstanceOf(SecurityException::class.java)
            assertThat(observed).isEmpty()
        }
    }

    @Test
    fun disconnectInFirstObserverStopsLaterObserverAndPageReturn() = runTest {
        val store = InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "accepted")))
        val manager = OAuthAuthorizationManager(OAuthConfigRegistry(emptyList()), store)
        var first = 0
        var second = 0
        val client = CloudHealthApiClient.forTesting(manager,
            transport = CloudHttpTransport { CloudHttpResponse(200, body = "{}".toByteArray()) },
            responseObserver = CloudRawResponseObserver { first += 1; store.clearToken("whoop") })
        val result = runCatching {
            client.getRawJsonResponse("whoop", "https://api.example.test/native",
                observer = CloudRawResponseObserver { second += 1 })
        }
        assertThat(result.exceptionOrNull()).isInstanceOf(SecurityException::class.java)
        assertThat(first).isEqualTo(1)
        assertThat(second).isEqualTo(0)
    }

    @Test
    fun boundClientKeepsGrantAcrossPagesAndUnavailableGrantCannotRepairItself() = runTest {
        val store = InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "accepted")))
        val manager = OAuthAuthorizationManager(OAuthConfigRegistry(emptyList()), store)
        val requests = mutableListOf<CloudHttpRequest>()
        val live = CloudHealthApiClient.forTesting(manager, transport = CloudHttpTransport {
            requests += it
            CloudHttpResponse(200, body = "{}".toByteArray())
        })
        val bound = live.forCaptureOperation("whoop")
        assertThat(bound.forCaptureOperation("whoop")).isSameInstanceAs(bound)
        bound.getRawJsonResponse("whoop", "https://api.example.test/page1")
        store.saveToken(OAuthToken("whoop", "replacement"))
        assertThat(bound.token("whoop")).isNull()
        assertThat(runCatching { bound.getRawJsonResponse("whoop", "https://api.example.test/page2") }.isFailure).isTrue()
        assertThat(requests).hasSize(1)
        live.forCaptureOperation("whoop").getRawJsonResponse("whoop", "https://api.example.test/fresh")
        assertThat(requests.last().authorization).isEqualTo("Bearer replacement")
        store.clearToken("whoop")
        val missing = live.forCaptureOperation("whoop")
        store.saveToken(OAuthToken("whoop", "repaired"))
        assertThat(missing.token("whoop")).isNull()
        assertThat(runCatching { missing.getRawJsonResponse("whoop", "https://api.example.test/repaired") }.isFailure).isTrue()
        assertThat(requests).hasSize(2)
    }

    private fun client(
        response: CloudHttpResponse = CloudHttpResponse(200, body = "{}".toByteArray()),
        observer: CloudRawResponseObserver? = null,
        clock: () -> Instant = { Instant.EPOCH },
        transport: CloudHttpTransport = CloudHttpTransport { response },
    ): CloudHealthApiClient = CloudHealthApiClient.forTesting(
        oauthAuthorizationManager = authorizationManager(),
        transport = transport,
        responseObserver = observer,
        clock = clock,
    )

    private fun authorizationManager(): OAuthAuthorizationManager = OAuthAuthorizationManager(
        configRegistry = OAuthConfigRegistry(emptyList()),
        tokenStore = InMemoryOAuthTokenStore(
            listOf(
                OAuthToken("fitbit", "fitbit-oauth-secret"),
                OAuthToken("oura", "oura-oauth-secret"),
                OAuthToken("whoop", "whoop-oauth-secret"),
                OAuthToken("withings", "withings-oauth-secret"),
            ),
        ),
    )
}
