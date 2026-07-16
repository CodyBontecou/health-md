package com.healthmd.data.health.providers.cloud

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.oauth.InMemoryOAuthTokenStore
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthToken
import com.healthmd.rawexport.CloudRawHealthDataProvider
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawExportItem
import com.healthmd.rawexport.RawJson
import com.healthmd.rawexport.RawPaginationSupport
import com.healthmd.rawexport.RawProviderTypeDefinition
import com.healthmd.rawexport.RawRangeBehavior
import com.healthmd.rawexport.RawRecordKind
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.rawexport.RawInstant
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Base64
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Test

class CloudNativeRawSnapshotTest {
    @Test
    fun normalizedOnlySourceIsRejectedAtNativeRawBoundary() {
        val api = client { CloudHttpResponse(200, body = "{}".toByteArray()) }
        val normalizedOnly = object : CloudNativeRawPageProvider {
            override val rawProviderId = "normalized"
            override val rawFidelityDeclaration = CloudProviderFidelityDeclaration("normalized", CloudProviderFidelity.NORMALIZED_ONLY)
            override val rawEndpointDefinitions = listOf(RawProviderTypeDefinition(
                typeKey = "normalized/data",
                wireType = "provider_payload",
                providerId = "normalized",
                rangeBehavior = RawRangeBehavior.OVERLAP,
                metricIds = setOf("steps"),
            ))
            override suspend fun streamNativePages(
                request: RawSnapshotRequest,
                selectedEndpointKeys: Set<String>,
                observerFor: (String) -> CloudRawResponseObserver,
                onEndpointResult: suspend (CloudNativeEndpointResult) -> Unit,
            ) = Unit
        }

        assertThat(runCatching { CloudRawHealthDataProvider(normalizedOnly, api) }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
    }

    @Test
    fun providerEndpointPlansDeclareImplementedPaginationAndUnsupportedCategories() {
        val client = client { CloudHttpResponse(200, body = "{}".toByteArray()) }
        val providers = listOf<CloudNativeRawPageProvider>(
            FitbitCloudDataProvider(client, "http://localhost"),
            OuraCloudDataProvider(client, "http://localhost"),
            WhoopCloudDataProvider(client, "http://localhost"),
            WithingsCloudDataProvider(client, "http://localhost"),
        )

        assertThat(providers.map { it.rawProviderId }).containsExactly("fitbit", "oura", "whoop", "withings").inOrder()
        providers.forEach { provider ->
            assertThat(provider.rawEndpointDefinitions.map { it.typeKey }).containsAtLeastElementsIn(
                provider.rawEndpointDefinitions.filterNot { it.typeKey.startsWith("unsupported/") }.map { it.typeKey },
            )
            assertThat(provider.rawEndpointDefinitions.any { it.typeKey.startsWith("unsupported/") }).isTrue()
        }
        assertThat(providers[0].rawEndpointDefinitions.filterNot { it.typeKey.startsWith("unsupported/") }
            .all { it.pagination == RawPaginationSupport.NONE }).isTrue()
        assertThat(providers[1].rawEndpointDefinitions.first { it.typeKey == OuraCloudDataProvider.DAILY_ACTIVITY }.pagination)
            .isEqualTo(RawPaginationSupport.NEXT_TOKEN)
        assertThat(providers[2].rawEndpointDefinitions.first { it.typeKey == WhoopCloudDataProvider.RECOVERY }.pagination)
            .isEqualTo(RawPaginationSupport.FAN_OUT)
        assertThat(providers[3].rawEndpointDefinitions.filterNot { it.typeKey.startsWith("unsupported/") }
            .all { it.pagination == RawPaginationSupport.NONE }).isTrue()
    }

    @Test
    fun fitbitProcessesEntireRangeBeyondPaginationPageCap() = runTest {
        var calls = 0
        val client = client {
            calls++
            CloudHttpResponse(200, "application/json", body = "{}".toByteArray())
        }
        val provider = FitbitCloudDataProvider(client, "http://localhost")
        val results = mutableListOf<CloudNativeEndpointResult>()
        val start = LocalDate.of(2026, 1, 1)
        val endExclusive = start.plusDays(101)
        val startInstant = start.atStartOfDay().toInstant(ZoneOffset.UTC)
        val endInstant = endExclusive.atStartOfDay().toInstant(ZoneOffset.UTC)
        val range = request().copy(
            startTime = RawInstant(startInstant.epochSecond, startInstant.nano),
            endTime = RawInstant(endInstant.epochSecond, endInstant.nano),
        )

        provider.streamNativePages(
            range,
            setOf(FitbitCloudDataProvider.ACTIVITY),
            observerFor = { CloudRawResponseObserver { } },
            onEndpointResult = { results += it },
        )

        assertThat(calls).isEqualTo(101)
        assertThat(results.single().successfulPageCount).isEqualTo(101)
        assertThat(results.single().failure).isNull()
    }

    @Test
    fun ouraPagesFollowNextTokenButCursorNeverEntersSanitizedQueryMetadata() = runTest {
        val requests = mutableListOf<CloudHttpRequest>()
        val client = client { request ->
            requests += request
            val body = if (requests.size == 1) {
                "{\n \"data\":[{\"steps\":7}],\"next_token\":\"secret-cursor\"\n}"
            } else {
                "{\"data\":[],\"next_token\":null}"
            }
            CloudHttpResponse(200, "application/json; charset=UTF-8", body = body.toByteArray())
        }
        val provider = OuraCloudDataProvider(client, "http://localhost/v2/usercollection")
        val observed = mutableListOf<CloudHealthRawResponse>()
        val results = mutableListOf<CloudNativeEndpointResult>()

        provider.streamNativePages(
            request(),
            setOf(OuraCloudDataProvider.DAILY_ACTIVITY),
            observerFor = { CloudRawResponseObserver { observed += it } },
            onEndpointResult = { results += it },
        )

        assertThat(observed.map { it.pageOrdinal }).containsExactly(1, 2).inOrder()
        assertThat(observed[0].responseText).contains("\n \"data\"")
        assertThat(observed[1].queryMetadata).doesNotContainKey("next_token")
        assertThat(requests[1].url.query).contains("next_token=secret-cursor")
        assertThat(results.single().successfulPageCount).isEqualTo(2)
    }

    @Test
    fun ouraPaginationCycleIsStoppedWithStructuredFailure() = runTest {
        var calls = 0
        val client = client {
            calls++
            CloudHttpResponse(200, body = "{\"data\":[],\"next_token\":\"repeat-token\"}".toByteArray())
        }
        val provider = OuraCloudDataProvider(client, "http://localhost/v2/usercollection")
        val results = mutableListOf<CloudNativeEndpointResult>()

        provider.streamNativePages(
            request(),
            setOf(OuraCloudDataProvider.SLEEP),
            observerFor = { CloudRawResponseObserver { } },
            onEndpointResult = { results += it },
        )

        assertThat(calls).isEqualTo(2)
        assertThat(results.single().failure?.code).isEqualTo("pagination_cycle")
        assertThat(results.single().successfulPageCount).isEqualTo(2)
    }

    @Test
    fun whoopRecoveryFanOutUsesIdsFromCapturedCyclePageWithoutExportingIdMetadata() = runTest {
        val requests = mutableListOf<CloudHttpRequest>()
        val client = client { request ->
            requests += request
            val body = when (request.url.path) {
                "/developer/v1/cycle" -> "{\"records\":[{\"id\":\"cycle-secret-id\"}],\"next_token\":null}"
                "/developer/v1/recovery" -> "{\"records\":[{\"score\":{\"resting_heart_rate\":50}}]}"
                else -> error("unexpected test URL")
            }
            CloudHttpResponse(200, "application/json", body = body.toByteArray())
        }
        val provider = WhoopCloudDataProvider(client, "http://localhost/developer/v1")
        val observed = mutableMapOf<String, MutableList<CloudHealthRawResponse>>()
        val results = mutableListOf<CloudNativeEndpointResult>()

        provider.streamNativePages(
            request(),
            setOf(WhoopCloudDataProvider.CYCLE, WhoopCloudDataProvider.RECOVERY),
            observerFor = { key -> CloudRawResponseObserver { observed.getOrPut(key) { mutableListOf() } += it } },
            onEndpointResult = { results += it },
        )

        assertThat(requests.map { it.url.path }).containsExactly(
            "/developer/v1/cycle", "/developer/v1/recovery",
        ).inOrder()
        assertThat(requests[1].url.query).contains("cycleId=cycle-secret-id")
        assertThat(observed.getValue(WhoopCloudDataProvider.RECOVERY).single().queryMetadata).isEmpty()
        assertThat(results.map { it.endpointKey }).containsExactly(
            WhoopCloudDataProvider.CYCLE, WhoopCloudDataProvider.RECOVERY,
        ).inOrder()
    }

    @Test
    fun cloudRawBoundaryMapsExactBytesToAuthoritativeBase64AndHashWithoutCredentialsOrUrls() = runTest {
        val exact = "{\n  \"data\": [{\"steps\": 42}]\n}".toByteArray()
        val api = client { CloudHttpResponse(
            200,
            "application/json; charset=UTF-8",
            headers = mapOf("ETag" to "revision-1", "Set-Cookie" to "cookie-secret"),
            body = exact,
        ) }
        val provider = CloudRawHealthDataProvider(
            OuraCloudDataProvider(api, "http://localhost/v2/usercollection"),
            api,
        )

        val items = provider.stream(request(selectedMetrics = setOf("steps"))).toList()
        val record = items.filterIsInstance<RawExportItem.Record>().single().record
        val payload = requireNotNull(record.providerPayload)
        val serialized = RawJson.canonicalRecord(record)

        assertThat(record.recordKind).isEqualTo(RawRecordKind.PROVIDER_PAYLOAD)
        assertThat(Base64.getDecoder().decode(payload.responseBytesBase64)).isEqualTo(exact)
        assertThat(payload.responseText).isEqualTo(exact.toString(Charsets.UTF_8))
        assertThat(payload.responseSha256).isEqualTo(RawJson.sha256(exact))
        assertThat(record.hash).isEqualTo(payload.responseSha256)
        assertThat(record.nativeIdentity).isEqualTo("cloud:oura:oura/daily_activity:1:${payload.responseSha256}")
        assertThat(serialized).doesNotContain("oura-oauth-secret")
        assertThat(serialized).doesNotContain("Authorization")
        assertThat(serialized).doesNotContain("cookie-secret")
        assertThat(serialized).doesNotContain("http://localhost")
    }

    private fun request(selectedMetrics: Set<String> = emptySet()) = RawSnapshotRequest(
        format = RawExportFormat.JSON,
        scope = if (selectedMetrics.isEmpty()) RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA else RawSnapshotScope.SELECTED_RECORD_TYPES,
        startTime = RawInstant(1_767_225_600, 0),
        endTime = RawInstant(1_767_312_000, 0),
        selectedMetricIds = selectedMetrics,
        calendarZoneId = "UTC",
    )

    private fun client(transport: suspend (CloudHttpRequest) -> CloudHttpResponse): CloudHealthApiClient =
        CloudHealthApiClient.forTesting(
            oauthAuthorizationManager = OAuthAuthorizationManager(
                OAuthConfigRegistry(emptyList()),
                InMemoryOAuthTokenStore(listOf(
                    OAuthToken("fitbit", "fitbit-oauth-secret"),
                    OAuthToken("oura", "oura-oauth-secret"),
                    OAuthToken("whoop", "whoop-oauth-secret"),
                    OAuthToken("withings", "withings-oauth-secret"),
                )),
            ),
            transport = CloudHttpTransport(transport),
            clock = { Instant.parse("2026-01-01T00:00:00.123456789Z") },
        )
}
