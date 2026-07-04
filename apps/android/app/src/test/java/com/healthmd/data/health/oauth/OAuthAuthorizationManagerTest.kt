package com.healthmd.data.health.oauth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.net.URI
import java.net.URLDecoder
import java.util.Base64

class OAuthAuthorizationManagerTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun buildAuthorizationUrl_storesPkceStateAndExpectedProviderParams() = runTest {
        val store = InMemoryOAuthTokenStore()
        val manager = manager(store = store)

        val authorizationUrl = requireNotNull(manager.buildAuthorizationUrl("oura"))
        val query = queryParameters(authorizationUrl)
        val pending = store.pendingAuthorizations.getValue(query.getValue("state"))

        assertThat(authorizationUrl).startsWith(server.url("/oauth/authorize").toString())
        assertThat(query).containsEntry("response_type", "code")
        assertThat(query).containsEntry("client_id", "client-id")
        assertThat(query).containsEntry("redirect_uri", OAuthProviderConfig.DEFAULT_REDIRECT_URI)
        assertThat(query).containsEntry("code_challenge_method", "S256")
        assertThat(query).containsEntry("scope", "daily heartrate workout")
        assertThat(query.getValue("code_challenge")).isNotEmpty()
        assertThat(pending.providerId).isEqualTo("oura")
        assertThat(pending.codeVerifier).isNotEmpty()
    }

    @Test
    fun handleCallback_exchangesAuthorizationCodeWithVerifierAndSavesToken() = runTest {
        val store = InMemoryOAuthTokenStore()
        val manager = manager(store = store, clientAuthStyle = OAuthClientAuthStyle.Basic)
        val authorizationUrl = requireNotNull(manager.buildAuthorizationUrl("oura"))
        val state = queryParameters(authorizationUrl).getValue("state")
        val verifier = store.pendingAuthorizations.getValue(state).codeVerifier
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """
                    {
                      "access_token": "access-new",
                      "refresh_token": "refresh-new",
                      "token_type": "Bearer",
                      "scope": "daily heartrate",
                      "expires_in": "3600"
                    }
                    """.trimIndent(),
                ),
        )

        val result = manager.handleCallback("healthmd://oauth2redirect?code=auth-code&state=$state")
        val request = server.takeRequest()
        val body = formParameters(request.body.readUtf8())

        assertThat(result.providerId).isEqualTo("oura")
        assertThat(result.token.accessToken).isEqualTo("access-new")
        assertThat(store.tokens.getValue("oura").refreshToken).isEqualTo("refresh-new")
        assertThat(request.path).isEqualTo("/oauth/token")
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.getHeader("Accept")).isEqualTo("application/json")
        assertThat(request.getHeader("Authorization")).isEqualTo(
            "Basic ${Base64.getEncoder().encodeToString("client-id:client-secret".toByteArray())}",
        )
        assertThat(body).containsEntry("grant_type", "authorization_code")
        assertThat(body).containsEntry("code", "auth-code")
        assertThat(body).containsEntry("client_id", "client-id")
        assertThat(body).containsEntry("redirect_uri", OAuthProviderConfig.DEFAULT_REDIRECT_URI)
        assertThat(body).containsEntry("code_verifier", verifier)
        assertThat(body).doesNotContainKey("client_secret")
        assertThat(store.pendingAuthorizations).doesNotContainKey(state)
    }

    @Test
    fun validAccessToken_refreshesExpiredTokenAndKeepsProviderId() = runTest {
        val store = InMemoryOAuthTokenStore(
            listOf(
                OAuthToken(
                    providerId = "oura",
                    accessToken = "access-old",
                    refreshToken = "refresh-old",
                    expiresAtEpochSeconds = 1,
                ),
            ),
        )
        val manager = manager(store = store)
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """
                    {
                      "access_token": "access-refreshed",
                      "refresh_token": "refresh-refreshed",
                      "token_type": "Bearer",
                      "expires_in": 7200
                    }
                    """.trimIndent(),
                ),
        )

        val token = requireNotNull(manager.validAccessToken("oura"))
        val request = server.takeRequest()
        val body = formParameters(request.body.readUtf8())

        assertThat(token.providerId).isEqualTo("oura")
        assertThat(token.accessToken).isEqualTo("access-refreshed")
        assertThat(store.tokens.getValue("oura").refreshToken).isEqualTo("refresh-refreshed")
        assertThat(body).containsEntry("grant_type", "refresh_token")
        assertThat(body).containsEntry("refresh_token", "refresh-old")
        assertThat(body).containsEntry("client_id", "client-id")
        assertThat(body).containsEntry("client_secret", "client-secret")
    }

    @Test
    fun handleCallback_rejectsUnknownStateBeforeTokenExchange() = runTest {
        val manager = manager(store = InMemoryOAuthTokenStore())

        val failure = runCatching {
            manager.handleCallback("healthmd://oauth2redirect?code=auth-code&state=missing")
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(failure).hasMessageThat().contains("state was not recognized")
        assertThat(server.requestCount).isEqualTo(0)
    }

    private fun manager(
        store: OAuthTokenStore,
        clientAuthStyle: OAuthClientAuthStyle = OAuthClientAuthStyle.RequestBody,
    ): OAuthAuthorizationManager = OAuthAuthorizationManager(
        configRegistry = OAuthConfigRegistry(
            listOf(
                OAuthProviderConfig(
                    providerId = "oura",
                    displayName = "Oura",
                    authorizationEndpoint = server.url("/oauth/authorize").toString().removeSuffix("/"),
                    tokenEndpoint = server.url("/oauth/token").toString(),
                    clientId = "client-id",
                    clientSecret = "client-secret",
                    scopes = listOf("daily", "heartrate", "workout"),
                    clientAuthStyle = clientAuthStyle,
                ),
            ),
        ),
        tokenStore = store,
    )

    private fun queryParameters(url: String): Map<String, String> =
        formParameters(URI(url).rawQuery.orEmpty())

    private fun formParameters(body: String): Map<String, String> =
        body.split("&")
            .filter { it.isNotBlank() }
            .associate { pair ->
                val parts = pair.split("=", limit = 2)
                decode(parts[0]) to decode(parts.getOrElse(1) { "" })
            }

    private fun decode(value: String): String = URLDecoder.decode(value, Charsets.UTF_8.name())
}
