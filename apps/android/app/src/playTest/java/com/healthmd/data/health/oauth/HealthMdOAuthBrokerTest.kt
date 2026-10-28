package com.healthmd.data.health.oauth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.net.URLEncoder

class HealthMdOAuthBrokerTest {
    private val server = MockWebServer()
    @Before fun start() = server.start()
    @After fun stop() = server.shutdown()

    private fun config() = OAuthProviderConfig(
        providerId = "whoop", displayName = "WHOOP",
        authorizationEndpoint = "https://api.prod.whoop.com/oauth/oauth2/auth",
        tokenEndpoint = "https://api.prod.whoop.com/oauth/oauth2/token",
        clientId = "", scopes = listOf("offline", "read:cycles"),
        redirectUri = "healthmd://oauth/callback",
        healthMdBroker = HealthMdOAuthBrokerConfig(server.url("/").toString(), "test-mobile-gate"),
    )

    @Test fun brokerAuthorizationExchangeAndRefreshUseAppleContract() = runTest {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                if (request.path == "/v1/oauth/authorize-url") {
                    val body = Json.parseToJsonElement(request.body.clone().readUtf8()) as JsonObject
                    val query = body.entries.joinToString("&") { (k, v) ->
                        "$k=${URLEncoder.encode(v.jsonPrimitive.content, "UTF-8")}"
                    }
                    return MockResponse().setBody("""{"provider":"whoop","authorization_url":"https://api.prod.whoop.com/oauth/oauth2/auth?$query"}""")
                }
                return MockResponse().setBody("""{"access_token":"test-access","refresh_token":"test-rotated","expires_in":3600}""")
            }
        }
        val store = InMemoryOAuthTokenStore()
        val config = config()
        val manager = OAuthAuthorizationManager(OAuthConfigRegistry(listOf(config)), store)
        assertThat(manager.isConfigured("whoop")).isTrue()
        manager.buildAuthorizationUrl("whoop")
        val authorization = server.takeRequest()
        val body = Json.parseToJsonElement(authorization.body.readUtf8()) as JsonObject
        val state = body.getValue("state").jsonPrimitive.content
        assertThat(state).hasLength(8)
        assertThat(body.getValue("redirect_uri").jsonPrimitive.content).isEqualTo(config.redirectUri)
        assertThat(body.getValue("code_challenge").jsonPrimitive.content).isNotEmpty()
        assertThat(authorization.getHeader("Authorization")).isEqualTo("Bearer test-mobile-gate")
        val verifier = store.pendingAuthorizations.getValue(state).codeVerifier
        manager.handleCallback("${config.redirectUri}?state=$state&code=test-code")
        val exchange = server.takeRequest()
        assertThat(exchange.path).isEqualTo("/v1/oauth/token")
        val exchangeBody = Json.parseToJsonElement(exchange.body.readUtf8()) as JsonObject
        assertThat(exchangeBody.getValue("code_verifier").jsonPrimitive.content).isEqualTo(verifier)
        assertThat(exchangeBody.keys).doesNotContain("client_secret")
        assertThat(exchangeBody.getValue("provider").jsonPrimitive.content).isEqualTo("whoop")
        assertThat(store.getToken("whoop")?.refreshToken).isEqualTo("test-rotated")
        manager.refreshToken(config, "test-rotated")
        val refresh = server.takeRequest()
        assertThat(refresh.path).isEqualTo("/v1/oauth/refresh")
        assertThat(refresh.getHeader("Content-Type")).isEqualTo("application/json")
        assertThat(refresh.body.readUtf8()).contains("\"scope\":\"offline\"")
    }

    @Test fun wrongCallbackAndDuplicateStateNeverExchangeTokens() = runTest {
        for (callback in listOf("healthmd://oauth/wrong?state=s&code=c", "healthmd://oauth/callback?state=s&state=s&code=c")) {
            val store = InMemoryOAuthTokenStore()
            store.savePendingAuthorization(PendingOAuthAuthorization("whoop", "s", "test-verifier"))
            val manager = OAuthAuthorizationManager(OAuthConfigRegistry(listOf(config())), store)
            val failure = runCatching { manager.handleCallback(callback) }.exceptionOrNull()
            assertThat((failure as OAuthAuthorizationException).reason).isEqualTo(OAuthFailureReason.INVALID_CALLBACK)
        }
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test fun incompleteAndInsecureBrokerConfigurationsFailClosed() {
        assertThat(HealthMdOAuthBrokerConfig("https://broker.example", "").isConfigured).isFalse()
        assertThat(HealthMdOAuthBrokerConfig("http://broker.example", "gate").isConfigured).isFalse()
        assertThat(HealthMdOAuthBrokerConfig("https://user@broker.example", "gate").isConfigured).isFalse()
        assertThat(config().copy(clientId = "legacy-id", healthMdBroker = HealthMdOAuthBrokerConfig("", "gate")).isConfigured).isFalse()
    }

    @Test fun failedBrokerDoesNotFollowRedirectOrLeakResponseBody() = runTest {
        server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/should-not-follow").setBody("sensitive-test-body"))
        val failure = runCatching { HealthMdOAuthBrokerClient(config().healthMdBroker!!).token("whoop", mapOf("grant_type" to "refresh_token")) }.exceptionOrNull()
        assertThat(failure).isInstanceOf(OAuthAuthorizationException::class.java)
        assertThat(failure?.message).doesNotContain("sensitive-test-body")
        assertThat(server.requestCount).isEqualTo(1)
    }

    @Test fun malformedBrokerResponseDoesNotLeakBody() = runTest {
        server.enqueue(MockResponse().setBody("sensitive-test-body"))
        val failure = runCatching { HealthMdOAuthBrokerClient(config().healthMdBroker!!).token("whoop", mapOf("grant_type" to "refresh_token")) }.exceptionOrNull()
        assertThat((failure as OAuthAuthorizationException).reason).isEqualTo(OAuthFailureReason.INVALID_TOKEN_RESPONSE)
        assertThat(failure.message).doesNotContain("sensitive-test-body")
        assertThat(failure.cause).isNull()
    }
}
