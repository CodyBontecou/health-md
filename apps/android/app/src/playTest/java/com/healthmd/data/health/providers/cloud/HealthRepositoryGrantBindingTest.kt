package com.healthmd.data.health.providers.cloud

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthDataMerger
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.data.health.oauth.InMemoryOAuthTokenStore
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthProviderConfig
import com.healthmd.data.health.oauth.OAuthToken
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthProviderCaptureAuthority
import com.healthmd.domain.repository.RestorableHealthRepository
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.mockk
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import org.junit.Test

class HealthRepositoryGrantBindingTest {
    private val first = LocalDate.of(2026, 7, 1)
    private val next = first.plusDays(1)

    @Test
    fun acceptedRepositoryKeepsGrantAcrossDaysAndRotationButCannotAdoptReplacement() = runTest {
        for (mode in SleepDayAttribution.entries) {
            val tokens = InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "accepted")))
            val requests = mutableListOf<CloudHttpRequest>()
            val repository = repository(tokens, requests)
            val accepted = repository.forCaptureOperation()
            val context = SleepDayAttributionOverride.Value(mode)
            accepted.fetchHealthDataRange(listOf(first), zoneId = ZoneOffset.UTC, sleepDayAttributionOverride = context)
            assertThat(requests).isNotEmpty()
            assertThat(requests.all { it.authorization == "Bearer accepted" }).isTrue()
            val credential = requireNotNull(tokens.getCredential("whoop"))
            assertThat(tokens.saveRotatedToken(OAuthToken("whoop", "rotated"), credential)).isTrue()
            requests.clear()
            accepted.fetchHealthDataRange(listOf(next), zoneId = ZoneOffset.UTC, sleepDayAttributionOverride = context)
            assertThat(requests).isNotEmpty()
            assertThat(requests.all { it.authorization == "Bearer rotated" }).isTrue()
            assertThat(requests.any { it.url.path.endsWith("/body") }).isTrue()
            assertThat(requests.all { it.url.host == "provider.example.test" && it.url.path.startsWith("/custom/") }).isTrue()
            tokens.saveToken(OAuthToken("whoop", "replacement"))
            requests.clear()
            assertThat(accepted.hasPermissions()).isFalse()
            val failure = runCatching {
                accepted.fetchHealthDataRange(listOf(next), zoneId = ZoneOffset.UTC, sleepDayAttributionOverride = context)
            }.exceptionOrNull()
            if (mode == SleepDayAttribution.MORNING_ENDS) {
                assertThat(failure).isInstanceOf(CloudHealthRequestException::class.java)
            } else {
                assertThat(failure).isNull()
            }
            assertThat(requests).isEmpty()
            repository.forCaptureOperation().fetchHealthDataRange(listOf(next), zoneId = ZoneOffset.UTC,
                sleepDayAttributionOverride = context)
            assertThat(requests).isNotEmpty()
            assertThat(requests.all { it.authorization == "Bearer replacement" }).isTrue()
        }
    }

    @Test
    fun unavailableAcceptedGrantCannotAdoptLaterLogin() = runTest {
        val tokens = InMemoryOAuthTokenStore()
        val requests = mutableListOf<CloudHttpRequest>()
        val repository = repository(tokens, requests)
        val accepted = repository.forCaptureOperation()
        tokens.saveToken(OAuthToken("whoop", "late-login"))
        assertThat(accepted.hasPermissions()).isFalse()
        val failure = runCatching {
            accepted.fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
                SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS))
        }.exceptionOrNull()
        assertThat(failure).isInstanceOf(CloudHealthRequestException::class.java)
        assertThat(requests).isEmpty()
        repository.forCaptureOperation().fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
            SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS))
        assertThat(requests).isNotEmpty()
    }

    @Test
    fun allConnectedKeepsAcceptedFailureFactsInsteadOfReadingReplacementAccount() = runTest {
        val tokens = InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "accepted")))
        val requests = mutableListOf<CloudHttpRequest>()
        val repository = repository(tokens, requests, allConnected = true)
        val accepted = repository.forCaptureOperation()
        tokens.saveToken(OAuthToken("whoop", "replacement"))
        val captured = accepted.fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
            SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS)).single()
        assertThat(captured.activity.steps).isEqualTo(10)
        assertThat(captured.compatibilityProvenance?.providerIdsAttempted).containsExactly("health_connect", "whoop")
        assertThat(captured.compatibilityProvenance?.providerFailures?.single()?.providerId).isEqualTo("whoop")
        assertThat(captured.compatibilityProvenance?.providerFailures?.single()?.errorType).isEqualTo("PermissionDenied")
        assertThat(requests).isEmpty()
    }

    @Test
    fun serializedAuthorityRestoresGrantAcrossRepositoryRecreationAndRotation() = runTest {
        val tokens = InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "accepted")))
        val requests = mutableListOf<CloudHttpRequest>()
        val original = repository(tokens, requests)
        val authority = original.captureProviderAuthority()
        val saved = Json.encodeToString(authority)
        assertThat(saved).doesNotContain("accepted")
        assertThat(saved).doesNotContain("accessToken")
        val rotated = requireNotNull(tokens.getCredential("whoop"))
        assertThat(tokens.saveRotatedToken(OAuthToken("whoop", "rotated"), rotated)).isTrue()
        // A new manager/client/repository and a different current source choice simulate reopening.
        val reopened = repository(tokens, requests, selectedId = "health_connect")
        val restored = reopened.restoreProviderAuthority(Json.decodeFromString<HealthProviderCaptureAuthority>(saved))
        restored.fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
            SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS))
        assertThat(requests).isNotEmpty()
        assertThat(requests.all { it.authorization == "Bearer rotated" }).isTrue()
        assertThat((restored as RestorableHealthRepository).captureProviderAuthority()).isEqualTo(authority)
        val wrong = authority.copy(connectionIds = mapOf("whoop" to java.util.UUID.randomUUID().toString()))
        assertThat(runCatching { restored.restoreProviderAuthority(wrong) }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
    }

    @Test
    fun reopenedAuthorityCannotAdoptReplacementOrReconnectedAccount() = runTest {
        for (disconnect in listOf(false, true)) {
            val tokens = InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "accepted")))
            val requests = mutableListOf<CloudHttpRequest>()
            val saved = Json.encodeToString(repository(tokens, requests).captureProviderAuthority())
            if (disconnect) tokens.clearToken("whoop")
            tokens.saveToken(OAuthToken("whoop", "replacement"))
            val reopened = repository(tokens, requests)
            val restored = reopened.restoreProviderAuthority(Json.decodeFromString<HealthProviderCaptureAuthority>(saved))
            val failure = runCatching {
                restored.fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
                    SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS))
            }.exceptionOrNull()
            assertThat(failure).isInstanceOf(CloudHealthRequestException::class.java)
            assertThat(requests).isEmpty()
            reopened.fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
                SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS))
            assertThat(requests).isNotEmpty()
            assertThat(requests.all { it.authorization == "Bearer replacement" }).isTrue()
        }
    }

    @Test
    fun serializedUnavailableGrantStaysUnavailableAndHealthConnectSelectionStaysLocal() = runTest {
        val tokens = InMemoryOAuthTokenStore()
        val requests = mutableListOf<CloudHttpRequest>()
        val authority = repository(tokens, requests).captureProviderAuthority()
        assertThat(authority.connectionIds).containsEntry("whoop", null)
        val saved = Json.encodeToString(authority)
        tokens.saveToken(OAuthToken("whoop", "late-login"))
        val reopened = repository(tokens, requests)
        val restored = reopened.restoreProviderAuthority(Json.decodeFromString<HealthProviderCaptureAuthority>(saved))
        assertThat(restored.hasPermissions()).isFalse()
        val local = repository(tokens, requests, selectedId = "health_connect").captureProviderAuthority()
        val localRestored = reopened.restoreProviderAuthority(Json.decodeFromString<HealthProviderCaptureAuthority>(Json.encodeToString(local)))
        val data = localRestored.fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
            SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS)).single()
        assertThat(data.activity.steps).isEqualTo(10)
        assertThat(requests).isEmpty()
    }

    @Test
    fun restoredAllConnectedRetainsUnavailableSourceFactsAndUnknownSourceNeverFallsBack() = runTest {
        val tokens = InMemoryOAuthTokenStore()
        val requests = mutableListOf<CloudHttpRequest>()
        val authority = repository(tokens, requests, allConnected = true).captureProviderAuthority()
        tokens.saveToken(OAuthToken("whoop", "late-login"))
        val reopened = repository(tokens, requests)
        val restored = reopened.restoreProviderAuthority(Json.decodeFromString<HealthProviderCaptureAuthority>(Json.encodeToString(authority)))
        val data = restored.fetchHealthDataRange(listOf(first), sleepDayAttributionOverride =
            SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS)).single()
        assertThat(data.activity.steps).isEqualTo(10)
        assertThat(data.compatibilityProvenance?.providerFailures?.single()?.providerId).isEqualTo("whoop")
        assertThat(requests).isEmpty()
        val unknown = HealthProviderCaptureAuthority(selectedProviderId = "unknown", providerIds = listOf("unknown"),
            connectionIds = mapOf("unknown" to null))
        assertThat(runCatching { reopened.restoreProviderAuthority(unknown) }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
    }

    private fun repository(tokens: InMemoryOAuthTokenStore, requests: MutableList<CloudHttpRequest>,
        allConnected: Boolean = false, selectedId: String = "whoop"): HealthRepositoryImpl {
        val sdk = mockk<HealthConnectManager>()
        coEvery { sdk.isAvailable() } returns true
        coEvery { sdk.hasAllPermissions() } returns true
        coEvery { sdk.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
            firstArg<List<LocalDate>>().map { HealthData(it, activity = ActivityData(steps = 10)) }
        }
        val settings = mockk<SettingsRepository>()
        coEvery { settings.getSelectedHealthProviderId() } returns if (allConnected) HealthDataMerger.ALL_CONNECTED_PROVIDER_ID else selectedId
        coEvery { settings.getConnectedHealthProviderIds() } returns setOf("health_connect", "whoop")
        val config = OAuthProviderConfig("whoop", "WHOOP", "https://auth.example.test", "https://token.example.test",
            "synthetic-client", scopes = listOf("read:sleep"))
        val client = CloudHealthApiClient.forTesting(OAuthAuthorizationManager(OAuthConfigRegistry(listOf(config)), tokens),
            transport = CloudHttpTransport { request ->
                requests += request
                CloudHttpResponse(200, "application/json", body = "{\"records\":[]}".toByteArray())
            })
        val provider = WhoopCloudDataProvider(client, baseUrl = "https://provider.example.test/custom",
            clock = Clock.fixed(Instant.parse("2026-07-02T12:00:00Z"), ZoneOffset.UTC))
        return HealthRepositoryImpl(HealthProviderRegistry(HealthConnectDataProvider(sdk), listOf(provider)), settings)
    }
}
