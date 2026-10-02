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
import com.healthmd.rawexport.RawRecordDecoder
import com.healthmd.rawexport.DecodedFields
import com.healthmd.rawexport.RawRecordKind
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.rawexport.RawSnapshotStatus
import com.healthmd.rawexport.RawTypeStatus
import com.healthmd.rawexport.RawInstant
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
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
            .isEqualTo(RawPaginationSupport.NEXT_TOKEN)
        assertThat(providers[3].rawEndpointDefinitions.filterNot { it.typeKey.startsWith("unsupported/") }
            .all { it.pagination == RawPaginationSupport.NEXT_TOKEN }).isTrue()
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
            CloudHttpResponse(
                200,
                "application/json; charset=UTF-8",
                headers = mapOf(
                    "ETag" to "\"secret-cursor\"",
                    "X-Request-ID" to "request-safe",
                ),
                body = body.toByteArray(),
            )
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
        // The exact provider payload is authoritative, so its internal cursor remains present.
        assertThat(observed[0].responseText).contains("secret-cursor")
        assertThat(observed[0].responseBytes.toString(Charsets.UTF_8)).contains("secret-cursor")
        assertThat(observed[1].queryMetadata).doesNotContainKey("next_token")
        assertThat(observed.flatMap { it.responseHeaders.values }).doesNotContain("\"secret-cursor\"")
        assertThat(observed.first().responseHeaders["X-Request-ID"]).isEqualTo("request-safe")
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
    fun ouraAndWhoopPageCapsStopAtOneHundredWithoutRequestingAnotherPage() = runTest {
        suspend fun assertCap(provider: CloudNativeRawPageProvider, endpoint: String, calls: () -> Int) {
            val results = mutableListOf<CloudNativeEndpointResult>()
            provider.streamNativePages(
                request(),
                setOf(endpoint),
                observerFor = { CloudRawResponseObserver { } },
                onEndpointResult = { results += it },
            )
            assertThat(calls()).isEqualTo(MAX_NATIVE_PAGES_PER_ENDPOINT)
            assertThat(results.first { it.endpointKey == endpoint }.successfulPageCount)
                .isEqualTo(MAX_NATIVE_PAGES_PER_ENDPOINT.toLong())
            assertThat(results.first { it.endpointKey == endpoint }.failure?.code).isEqualTo("pagination_cap")
        }

        var ouraCalls = 0
        val ouraClient = client {
            ouraCalls++
            CloudHttpResponse(200, body = "{\"data\":[],\"next_token\":\"oura-$ouraCalls\"}".toByteArray())
        }
        assertCap(OuraCloudDataProvider(ouraClient, "http://localhost/v2/usercollection"), OuraCloudDataProvider.SLEEP) { ouraCalls }

        var collectionCalls = 0
        val collectionClient = client {
            collectionCalls++
            CloudHttpResponse(200, body = "{\"records\":[],\"next_token\":\"sleep-$collectionCalls\"}".toByteArray())
        }
        assertCap(WhoopCloudDataProvider(collectionClient, "http://localhost/developer/v2"), WhoopCloudDataProvider.SLEEP) { collectionCalls }

        var cycleCalls = 0
        val cycleClient = client {
            cycleCalls++
            CloudHttpResponse(200, body = "{\"records\":[],\"next_token\":\"cycle-$cycleCalls\"}".toByteArray())
        }
        assertCap(WhoopCloudDataProvider(cycleClient, "http://localhost/developer/v2"), WhoopCloudDataProvider.CYCLE) { cycleCalls }
    }

    @Test
    fun whoopCollectionAndCyclePaginationCyclesAreStopped() = runTest {
        suspend fun assertCycle(endpoint: String) {
            var calls = 0
            val client = client {
                calls++
                CloudHttpResponse(200, body = "{\"records\":[],\"next_token\":\"repeat-whoop\"}".toByteArray())
            }
            val results = mutableListOf<CloudNativeEndpointResult>()
            WhoopCloudDataProvider(client, "http://localhost/developer/v2").streamNativePages(
                request(),
                setOf(endpoint),
                observerFor = { CloudRawResponseObserver { } },
                onEndpointResult = { results += it },
            )
            assertThat(calls).isEqualTo(2)
            val result = results.first { it.endpointKey == endpoint }
            assertThat(result.successfulPageCount).isEqualTo(2)
            assertThat(result.failure?.code).isEqualTo("pagination_cycle")
            assertThat(result.failure?.message).doesNotContain("repeat-whoop")
        }

        assertCycle(WhoopCloudDataProvider.SLEEP)
        assertCycle(WhoopCloudDataProvider.CYCLE)
        assertCycle(WhoopCloudDataProvider.RECOVERY)
    }

    @Test
    fun whoopBodyCursorIsExactPayloadDataButNeverSanitizedRequestOrHeaderMetadata() = runTest {
        val requests = mutableListOf<CloudHttpRequest>()
        val observed = mutableListOf<CloudHealthRawResponse>()
        val client = client { request ->
            requests += request
            val body = if (requests.size == 1) {
                "{\"records\":[],\"next_token\":\"whoop-body-secret\"}"
            } else {
                "{\"records\":[],\"next_token\":null}"
            }
            CloudHttpResponse(
                200,
                headers = mapOf(
                    "Authorization" to "Bearer header-secret",
                    "Set-Cookie" to "cursor=header-secret",
                    "X-Arbitrary-Cursor" to "header-secret",
                    "ETag" to "\"whoop-body-secret\"",
                ),
                body = body.toByteArray(),
            )
        }
        val results = mutableListOf<CloudNativeEndpointResult>()
        WhoopCloudDataProvider(client, "http://localhost/developer/v2").streamNativePages(
            request(),
            setOf(WhoopCloudDataProvider.SLEEP),
            observerFor = { CloudRawResponseObserver { observed += it } },
            onEndpointResult = { results += it },
        )

        assertThat(observed).hasSize(2)
        assertThat(observed.first().responseText).contains("whoop-body-secret")
        assertThat(observed.first().responseBytes.toString(Charsets.UTF_8)).contains("whoop-body-secret")
        assertThat(requests[1].url.query).contains("nextToken=whoop-body-secret")
        assertThat(observed[1].queryMetadata).doesNotContainKey("nexttoken")
        assertThat(observed.flatMap { it.responseHeaders.values }).doesNotContain("header-secret")
        assertThat(observed.flatMap { it.responseHeaders.values }).doesNotContain("\"whoop-body-secret\"")
        assertThat(results.single().failure).isNull()
    }

    @Test
    fun providerPaginationErrorsExposeOnlySanitizedStructuredFailure() = runTest {
        val secretBody = "{\"next_token\":\"error-cursor-secret\",\"health\":\"private\"}"
        val observed = mutableListOf<CloudHealthRawResponse>()
        val client = client {
            CloudHttpResponse(429, body = secretBody.toByteArray())
        }
        val results = mutableListOf<CloudNativeEndpointResult>()
        OuraCloudDataProvider(client, "http://localhost/v2/usercollection").streamNativePages(
            request(),
            setOf(OuraCloudDataProvider.WORKOUT),
            observerFor = { CloudRawResponseObserver { observed += it } },
            onEndpointResult = { results += it },
        )

        assertThat(observed).isEmpty()
        val failure = requireNotNull(results.single().failure)
        assertThat(failure.code).isEqualTo("native_endpoint_failed")
        assertThat(failure.message).doesNotContain("error-cursor-secret")
        assertThat(failure.message).doesNotContain("private")
    }

    @Test
    fun withingsPaginatesAllEndpointsUsingBodyMoreAndOffsetWithStableOrdinals() = runTest {
        val endpoints = listOf(
            WithingsCloudDataProvider.ACTIVITY to "getactivity",
            WithingsCloudDataProvider.SLEEP to "getsummary",
            WithingsCloudDataProvider.MEASURES to "getmeas",
        )
        endpoints.forEach { (endpoint, action) ->
            val requests = mutableListOf<CloudHttpRequest>()
            val observed = mutableListOf<CloudHealthRawResponse>()
            val client = client { httpRequest ->
                requests += httpRequest
                val body = if (requests.size == 1) {
                    "{\"status\":0,\"body\":{\"more\":1,\"offset\":\"17\",\"native\":\"first\"}}"
                } else {
                    "{\"status\":0,\"body\":{\"more\":0,\"offset\":\"29\",\"native\":\"second\"}}"
                }
                CloudHttpResponse(200, "application/json", body = body.toByteArray())
            }
            val results = mutableListOf<CloudNativeEndpointResult>()
            WithingsCloudDataProvider(client, "http://localhost").streamNativePages(
                request(),
                setOf(endpoint),
                observerFor = { CloudRawResponseObserver { observed += it } },
                onEndpointResult = { results += it },
            )

            assertThat(requests).hasSize(2)
            assertThat(requests.first().url.query).contains("action=$action")
            assertThat(requests.first().url.query).doesNotContain("offset=")
            assertThat(requests[1].url.query).contains("offset=17")
            assertThat(observed.map { it.pageOrdinal }).containsExactly(1, 2).inOrder()
            assertThat(observed[1].queryMetadata["offset"]).isEqualTo("17")
            assertThat(results.single().successfulPageCount).isEqualTo(2)
            assertThat(results.single().failure).isNull()
        }
    }

    @Test
    fun withingsCycleProducesCapturedPartialPagesAndStructuredPartialStatus() = runTest {
        val client = client {
            CloudHttpResponse(
                200,
                body = "{\"status\":0,\"body\":{\"more\":1,\"offset\":\"repeat\"}}".toByteArray(),
            )
        }
        val provider = CloudRawHealthDataProvider(
            WithingsCloudDataProvider(client, "http://localhost"),
            client,
        )

        val items = provider.stream(request(selectedMetrics = setOf("steps"))).toList()
        val records = items.filterIsInstance<RawExportItem.Record>()
        val failure = items.filterIsInstance<RawExportItem.Issue>().single { it.issue.code == "pagination_cycle" }
        val report = items.filterIsInstance<RawExportItem.TypeReport>()
            .single { it.report.typeKey == WithingsCloudDataProvider.ACTIVITY }

        assertThat(records.map { it.record.providerPayload?.pageOrdinal }).containsExactly(1, 2).inOrder()
        assertThat(failure.issue.message).doesNotContain("repeat")
        assertThat(report.report.status).isEqualTo(RawTypeStatus.READ_ERROR)
        assertThat(items.filterIsInstance<RawExportItem.Status>().last().status).isEqualTo(RawSnapshotStatus.PARTIAL)
    }

    @Test
    fun withingsHardPageCapAndCancellationAreEnforced() = runTest {
        var calls = 0
        val capClient = client {
            calls++
            CloudHttpResponse(
                200,
                body = "{\"status\":0,\"body\":{\"more\":1,\"offset\":\"$calls\"}}".toByteArray(),
            )
        }
        val capResults = mutableListOf<CloudNativeEndpointResult>()
        WithingsCloudDataProvider(capClient, "http://localhost").streamNativePages(
            request(),
            setOf(WithingsCloudDataProvider.MEASURES),
            observerFor = { CloudRawResponseObserver { } },
            onEndpointResult = { capResults += it },
        )
        assertThat(calls).isEqualTo(MAX_NATIVE_PAGES_PER_ENDPOINT)
        assertThat(capResults.single().successfulPageCount).isEqualTo(MAX_NATIVE_PAGES_PER_ENDPOINT.toLong())
        assertThat(capResults.single().failure?.code).isEqualTo("pagination_cap")

        val cancellation = runCatching {
            val cancelClient = client { throw CancellationException("cancel-withings") }
            WithingsCloudDataProvider(cancelClient, "http://localhost").streamNativePages(
                request(),
                setOf(WithingsCloudDataProvider.SLEEP),
                observerFor = { CloudRawResponseObserver { } },
                onEndpointResult = { error("must not report after cancellation") },
            )
        }.exceptionOrNull()
        assertThat(cancellation).isInstanceOf(CancellationException::class.java)
    }

    @Test
    fun withingsApplicationErrorEnvelopeNeverReachesAnyRawObserver() = runTest {
        val exactError = "{\"status\":401,\"body\":{\"access_token\":\"secret\",\"offset\":\"private\"}}"
        val globalObserved = mutableListOf<CloudHealthRawResponse>()
        val endpointObserved = mutableListOf<CloudHealthRawResponse>()
        val client = client(observer = CloudRawResponseObserver { globalObserved += it }) {
            CloudHttpResponse(200, "application/json", body = exactError.toByteArray())
        }
        val results = mutableListOf<CloudNativeEndpointResult>()
        WithingsCloudDataProvider(client, "http://localhost").streamNativePages(
            request(),
            setOf(WithingsCloudDataProvider.ACTIVITY),
            observerFor = { CloudRawResponseObserver { endpointObserved += it } },
            onEndpointResult = { results += it },
        )

        assertThat(globalObserved).isEmpty()
        assertThat(endpointObserved).isEmpty()
        val failure = requireNotNull(results.single().failure)
        assertThat(results.single().successfulPageCount).isEqualTo(0)
        assertThat(failure.code).isEqualTo("provider_application_error")
        assertThat(failure.message).doesNotContain("secret")
        assertThat(failure.message).doesNotContain("private")
        assertThat(failure.message).doesNotContain("401")
    }

    @Test
    fun disconnectedUnsupportedSelectionRemainsUnsupportedInsteadOfPermissionDenied() = runTest {
        var requests = 0
        val client = client(tokens = emptyList()) {
            requests++
            CloudHttpResponse(200, body = "{}".toByteArray())
        }
        val provider = CloudRawHealthDataProvider(
            WithingsCloudDataProvider(client, "http://localhost"),
            client,
        )

        val items = provider.stream(request(selectedMetrics = setOf("steps", "blood_oxygen"))).toList()
        val issues = items.filterIsInstance<RawExportItem.Issue>()
        val report = items.filterIsInstance<RawExportItem.TypeReport>()
            .single { it.report.typeKey == "unsupported/respiratory" }

        assertThat(requests).isEqualTo(0)
        assertThat(issues.map { it.issue.code }).containsAtLeast(
            "unsupported_by_provider",
            "permission_not_granted",
        )
        assertThat(issues.filter { it.issue.recordType == "unsupported/respiratory" }
            .map { it.issue.code }).containsExactly("unsupported_by_provider")
        assertThat(report.report.status).isEqualTo(RawTypeStatus.UNSUPPORTED_BY_PROVIDER)
        assertThat(items.filterIsInstance<RawExportItem.Status>().last().status).isEqualTo(RawSnapshotStatus.FAILED)
    }

    @Test
    fun pagedAdaptersRethrowCancellationWithoutEndpointResults() = runTest {
        suspend fun assertCancelled(provider: CloudNativeRawPageProvider, endpoint: String) {
            val results = mutableListOf<CloudNativeEndpointResult>()
            val failure = runCatching {
                provider.streamNativePages(
                    request(),
                    setOf(endpoint),
                    observerFor = { CloudRawResponseObserver { } },
                    onEndpointResult = { results += it },
                )
            }.exceptionOrNull()
            assertThat(failure).isInstanceOf(CancellationException::class.java)
            assertThat(results).isEmpty()
        }

        val ouraClient = client { throw CancellationException("cancel-oura") }
        assertCancelled(OuraCloudDataProvider(ouraClient, "http://localhost/v2/usercollection"), OuraCloudDataProvider.SLEEP)
        val whoopCollectionClient = client { throw CancellationException("cancel-whoop-collection") }
        assertCancelled(WhoopCloudDataProvider(whoopCollectionClient, "http://localhost/developer/v2"), WhoopCloudDataProvider.SLEEP)
        val whoopCycleClient = client { throw CancellationException("cancel-whoop-cycle") }
        assertCancelled(WhoopCloudDataProvider(whoopCycleClient, "http://localhost/developer/v2"), WhoopCloudDataProvider.CYCLE)
    }

    @Test
    fun whoopRecoveryPageCapStopsAtOneHundredAndCancellationPropagates() = runTest {
        var recoveryCalls = 0
        val client = client { httpRequest ->
            assertThat(httpRequest.url.path).isEqualTo("/developer/v2/recovery")
            recoveryCalls++
            CloudHttpResponse(200, body = "{\"records\":[],\"next_token\":\"recovery-$recoveryCalls\"}".toByteArray())
        }
        val results = mutableListOf<CloudNativeEndpointResult>()
        WhoopCloudDataProvider(client, "http://localhost/developer/v2").streamNativePages(
            request(),
            setOf(WhoopCloudDataProvider.RECOVERY),
            observerFor = { CloudRawResponseObserver { } },
            onEndpointResult = { results += it },
        )
        assertThat(recoveryCalls).isEqualTo(MAX_NATIVE_PAGES_PER_ENDPOINT)
        val recovery = results.single()
        assertThat(recovery.endpointKey).isEqualTo(WhoopCloudDataProvider.RECOVERY)
        assertThat(recovery.successfulPageCount).isEqualTo(MAX_NATIVE_PAGES_PER_ENDPOINT.toLong())
        assertThat(recovery.failure?.code).isEqualTo("pagination_cap")

        val cancelClient = client { throw CancellationException("cancel-recovery") }
        val cancellation = runCatching {
            WhoopCloudDataProvider(cancelClient, "http://localhost/developer/v2").streamNativePages(
                request(),
                setOf(WhoopCloudDataProvider.RECOVERY),
                observerFor = { CloudRawResponseObserver { } },
                onEndpointResult = { },
            )
        }.exceptionOrNull()
        assertThat(cancellation).isInstanceOf(CancellationException::class.java)
    }

    @Test
    fun whoopRecoveryPagesUseFixedRangeWithoutFetchingCyclesOrExportingCursors() = runTest {
        val requests = mutableListOf<CloudHttpRequest>()
        val bodies = listOf(
            "{\n \"records\":[{\"cycle_id\":101,\"sleep_id\":\"00000000-0000-4000-8000-000000000201\"}],\"next_token\":\"recovery-secret\"\n}",
            "{\"records\":[],\"next_token\":null}",
        )
        val client = client { request ->
            requests += request
            CloudHttpResponse(200, "application/json", body = bodies[requests.lastIndex].toByteArray())
        }
        val provider = WhoopCloudDataProvider(client)
        val observed = mutableListOf<CloudHealthRawResponse>()
        val results = mutableListOf<CloudNativeEndpointResult>()

        provider.streamNativePages(
            request(),
            setOf(WhoopCloudDataProvider.RECOVERY),
            observerFor = { key ->
                assertThat(key).isEqualTo(WhoopCloudDataProvider.RECOVERY)
                CloudRawResponseObserver { observed += it }
            },
            onEndpointResult = { results += it },
        )

        assertThat(requests.map { it.url.toString().substringBefore('?') }).containsExactly(
            "https://api.prod.whoop.com/developer/v2/recovery",
            "https://api.prod.whoop.com/developer/v2/recovery",
        ).inOrder()
        assertThat(requests[0].url.query).isEqualTo("start=2026-01-01T00%3A00%3A00Z&end=2026-01-02T00%3A00%3A00Z&limit=25")
        assertThat(requests[1].url.query).isEqualTo("${requests[0].url.query}&nextToken=recovery-secret")
        assertThat(observed.map { it.responseBytes.toString(Charsets.UTF_8) }).containsExactlyElementsIn(bodies).inOrder()
        assertThat(observed.map { it.pageOrdinal }).containsExactly(1, 2).inOrder()
        assertThat(observed[1].queryMetadata).doesNotContainKey("nexttoken")
        assertThat(results.single().endpointKey).isEqualTo(WhoopCloudDataProvider.RECOVERY)
        assertThat(results.single().successfulPageCount).isEqualTo(2)
        assertThat(results.single().failure).isNull()
    }

    @Test
    fun whoopCycleFailureDoesNotPreventIndependentRecoveryCollection() = runTest {
        val client = client { request ->
            if (request.url.path.endsWith("/cycle")) CloudHttpResponse(403) else
                CloudHttpResponse(200, body = "{\"records\":[]}".toByteArray())
        }
        val results = mutableListOf<CloudNativeEndpointResult>()
        WhoopCloudDataProvider(client).streamNativePages(
            request(),
            setOf(WhoopCloudDataProvider.CYCLE, WhoopCloudDataProvider.RECOVERY),
            observerFor = { CloudRawResponseObserver { } },
            onEndpointResult = { results += it },
        )
        assertThat(results.first().failure?.code).isEqualTo("native_endpoint_failed")
        assertThat(results.last().endpointKey).isEqualTo(WhoopCloudDataProvider.RECOVERY)
        assertThat(results.last().successfulPageCount).isEqualTo(1)
        assertThat(results.last().failure).isNull()
    }

    @Test
    fun whoopLaterRecoveryPageFailureRetainsExactFirstPageAndReportsPartial() = runTest {
        val exact = "{\n \"records\":[{\"cycle_id\":101}],\"next_token\":\"private-cursor\"\n}".toByteArray()
        var calls = 0
        val api = client { request ->
            if (request.url.path.endsWith("/cycle")) {
                CloudHttpResponse(200, body = "{\"records\":[]}".toByteArray())
            } else {
                calls++
                if (calls == 1) CloudHttpResponse(200, "application/json", body = exact) else
                    CloudHttpResponse(500, body = "private-provider-error-body".toByteArray())
            }
        }
        val items = CloudRawHealthDataProvider(WhoopCloudDataProvider(api), api)
            .stream(request(selectedMetrics = setOf("hrv"))).toList()

        val recovery = items.filterIsInstance<RawExportItem.Record>()
            .single { it.record.providerPayload!!.endpointKey == WhoopCloudDataProvider.RECOVERY }
        assertThat(calls).isEqualTo(2)
        assertThat(Base64.getDecoder().decode(recovery.record.providerPayload!!.responseBytesBase64)).isEqualTo(exact)
        assertThat(items.filterIsInstance<RawExportItem.TypeReport>()
            .single { it.report.typeKey == WhoopCloudDataProvider.RECOVERY }.report.status).isEqualTo(RawTypeStatus.READ_ERROR)
        assertThat(items.filterIsInstance<RawExportItem.Status>().last().status).isEqualTo(RawSnapshotStatus.PARTIAL)
        assertThat(items.filterIsInstance<RawExportItem.Issue>().all {
            "private-cursor" !in it.issue.message && "private-provider-error-body" !in it.issue.message
        }).isTrue()
    }

    @Test
    fun whoopRecoveryMetricSelectionsNeitherFetchCyclesNorFailOnMissingCyclePermission() = runTest {
        for (metrics in listOf(setOf("hrv"), setOf("resting_hr"), setOf("hrv", "resting_hr"))) {
            val requests = mutableListOf<CloudHttpRequest>()
            val api = client { request ->
                requests += request
                if (request.url.path.endsWith("/cycle")) CloudHttpResponse(403) else
                    CloudHttpResponse(200, body = "{\"records\":[]}".toByteArray())
            }
            val items = CloudRawHealthDataProvider(WhoopCloudDataProvider(api), api)
                .stream(request(selectedMetrics = metrics)).toList()

            assertThat(requests.map { it.url.path }).containsExactly("/developer/v2/recovery")
            assertThat(items.filterIsInstance<RawExportItem.Record>().map { it.record.providerPayload!!.endpointKey })
                .containsExactly(WhoopCloudDataProvider.RECOVERY)
            val reports = items.filterIsInstance<RawExportItem.TypeReport>().associate { it.report.typeKey to it.report }
            assertThat(reports.getValue(WhoopCloudDataProvider.CYCLE).status).isEqualTo(RawTypeStatus.NOT_SELECTED)
            assertThat(reports.getValue(WhoopCloudDataProvider.RECOVERY).status).isEqualTo(RawTypeStatus.EXPORTED)
            assertThat(items.filterIsInstance<RawExportItem.Issue>()).isEmpty()
            assertThat(items.filterIsInstance<RawExportItem.Status>().last().status).isEqualTo(RawSnapshotStatus.COMPLETE)
        }
    }

    @Test
    fun whoopCyclesAreSelectedForNativeEnergyAndHeartRateMetricsOnly() = runTest {
        val exact = """
            {"records":[{"id":101,"score":{"kilojoule":8288.297,"average_heart_rate":68,"max_heart_rate":141}}]}
        """.trimIndent().toByteArray()
        val requests = mutableListOf<CloudHttpRequest>()
        val api = client { request ->
            requests += request
            if (request.url.path.endsWith("/cycle")) CloudHttpResponse(200, "application/json", body = exact) else
                CloudHttpResponse(403)
        }
        val source = WhoopCloudDataProvider(api)
        val cycleDefinition = source.rawEndpointDefinitions.single { it.typeKey == WhoopCloudDataProvider.CYCLE }
        assertThat(cycleDefinition.metricIds).containsExactly("total_calories", "avg_hr", "max_hr")

        val items = CloudRawHealthDataProvider(source, api)
            .stream(request(selectedMetrics = setOf("total_calories"))).toList()
        assertThat(requests.map { it.url.path }).containsExactly("/developer/v2/cycle")
        val payload = items.filterIsInstance<RawExportItem.Record>().single().record.providerPayload!!
        assertThat(payload.endpointKey).isEqualTo(WhoopCloudDataProvider.CYCLE)
        assertThat(Base64.getDecoder().decode(payload.responseBytesBase64)).isEqualTo(exact)
        assertThat(items.filterIsInstance<RawExportItem.TypeReport>()
            .single { it.report.typeKey == WhoopCloudDataProvider.RECOVERY }.report.status).isEqualTo(RawTypeStatus.NOT_SELECTED)
        assertThat(items.filterIsInstance<RawExportItem.Issue>()).isEmpty()
        assertThat(items.filterIsInstance<RawExportItem.Status>().last().status).isEqualTo(RawSnapshotStatus.COMPLETE)
    }

    @Test
    fun whoopRawSnapshotsPreserveRepeatedPagesWithoutNormalizedRecordDedupe() = runTest {
        val exact = "{\n \"records\":[{\"id\":\"00000000-0000-4000-8000-000000000301\"}],\"next_token\":\"repeat\"\n}".toByteArray()
        var calls = 0
        val api = client {
            calls++
            CloudHttpResponse(200, "application/json", body = exact)
        }
        val items = CloudRawHealthDataProvider(WhoopCloudDataProvider(api), api)
            .stream(request(selectedMetrics = setOf("workouts"))).toList()

        val payloads = items.filterIsInstance<RawExportItem.Record>().map { it.record.providerPayload!! }
        assertThat(calls).isEqualTo(2)
        assertThat(payloads.map { it.pageOrdinal }).containsExactly(1, 2).inOrder()
        payloads.forEach { payload ->
            assertThat(Base64.getDecoder().decode(payload.responseBytesBase64)).isEqualTo(exact)
            assertThat(payload.responseSha256).isEqualTo(RawJson.sha256(exact))
        }
        assertThat(items.filterIsInstance<RawExportItem.Issue>().single().issue.code).isEqualTo("pagination_cycle")
        assertThat(items.filterIsInstance<RawExportItem.TypeReport>()
            .single { it.report.typeKey == WhoopCloudDataProvider.WORKOUT }.report.status).isEqualTo(RawTypeStatus.READ_ERROR)
        assertThat(items.filterIsInstance<RawExportItem.Status>().last().status).isEqualTo(RawSnapshotStatus.PARTIAL)
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
        val decoded = RawRecordDecoder.decode(RawJson.codec.parseToJsonElement(serialized).jsonObject)
        val decodedPayload = (decoded.fields as DecodedFields.Provider).payload

        assertThat(record.recordKind).isEqualTo(RawRecordKind.PROVIDER_PAYLOAD)
        assertThat(decodedPayload.exactResponseBytes).isEqualTo(exact)
        assertThat(decodedPayload.exactResponseText).isEqualTo(exact.toString(Charsets.UTF_8))
        assertThat(Base64.getDecoder().decode(payload.responseBytesBase64)).isEqualTo(exact)
        assertThat(payload.responseText).isEqualTo(exact.toString(Charsets.UTF_8))
        assertThat(payload.responseSha256).isEqualTo(RawJson.sha256(exact))
        assertThat(record.hash).isEqualTo(payload.responseSha256)
        assertThat(record.nativeIdentity).isEqualTo("cloud:oura:oura/daily_activity:1:${payload.responseSha256}")
        assertThat(serialized).doesNotContain("oura-oauth-secret")
        assertThat(serialized).doesNotContain("Authorization")
        assertThat(serialized).doesNotContain("cookie-secret")
        assertThat(serialized).doesNotContain("http://localhost")

        val objectValue = RawJson.codec.parseToJsonElement(serialized).jsonObject
        val providerObject = objectValue.getValue("providerPayload").jsonObject
        val corruptProvider = JsonObject(providerObject + (
            "responseBytesBase64" to JsonPrimitive(Base64.getEncoder().encodeToString("different".toByteArray()))
        ))
        val failure = runCatching {
            RawRecordDecoder.decode(JsonObject(objectValue + ("providerPayload" to corruptProvider)))
        }.exceptionOrNull() as com.healthmd.rawexport.RawDecodeException
        assertThat(failure.code).isEqualTo("provider_checksum")
        assertThat(failure.message).doesNotContain(exact.toString(Charsets.UTF_8))
    }

    private fun request(selectedMetrics: Set<String> = emptySet()) = RawSnapshotRequest(
        format = RawExportFormat.JSON,
        scope = if (selectedMetrics.isEmpty()) RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA else RawSnapshotScope.SELECTED_RECORD_TYPES,
        startTime = RawInstant(1_767_225_600, 0),
        endTime = RawInstant(1_767_312_000, 0),
        selectedMetricIds = selectedMetrics,
        calendarZoneId = "UTC",
    )

    private fun client(
        tokens: List<OAuthToken> = listOf(
            OAuthToken("fitbit", "fitbit-oauth-secret"),
            OAuthToken("oura", "oura-oauth-secret"),
            OAuthToken("whoop", "whoop-oauth-secret"),
            OAuthToken("withings", "withings-oauth-secret"),
        ),
        observer: CloudRawResponseObserver? = null,
        transport: suspend (CloudHttpRequest) -> CloudHttpResponse,
    ): CloudHealthApiClient = CloudHealthApiClient.forTesting(
        oauthAuthorizationManager = OAuthAuthorizationManager(
            OAuthConfigRegistry(emptyList()),
            InMemoryOAuthTokenStore(tokens),
        ),
        transport = CloudHttpTransport(transport),
        responseObserver = observer,
        clock = { Instant.parse("2026-01-01T00:00:00.123456789Z") },
    )
}
