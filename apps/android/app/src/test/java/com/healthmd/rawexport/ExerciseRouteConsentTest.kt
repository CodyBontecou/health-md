package com.healthmd.rawexport

import androidx.health.connect.client.records.ExerciseRoute
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Length
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

/**
 * Issue #132: third-party exercise routes come back from Health Connect as ConsentRequired.
 * These tests pin the interactive consent merge for raw snapshots:
 * granted routes merge in place, denials fall back to consent_required, and non-interactive
 * consumers (direct CLI protocol, scheduled exports) pass the inline state through untouched.
 */
class ExerciseRouteConsentTest {

    private val rangeStart = Instant.ofEpochSecond(1_000)
    private val rangeEnd = Instant.ofEpochSecond(2_000)

    private fun request(includeRoutes: Boolean = true) = RawSnapshotRequest(
        format = RawExportFormat.NDJSON,
        scope = RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA,
        startTime = RawInstant(rangeStart.epochSecond, 0),
        endTime = RawInstant(rangeEnd.epochSecond, 0),
        selectedMetricIds = setOf("workouts"),
        includeExerciseRoutes = includeRoutes,
    )

    /** Route points must fall inside the owning session's window; the pinned SDK validates this. */
    private fun routeBetween(start: Instant, end: Instant) = ExerciseRoute(
        listOf(
            ExerciseRoute.Location(start.plusSeconds(10), 45.25, -122.75, Length.meters(3.0), Length.meters(4.0), Length.meters(100.0)),
            ExerciseRoute.Location(start.plusSeconds(20).takeIf { it < end } ?: end.minusSeconds(1), 45.5, -122.5, null, null, null),
        ),
    )

    private val grantedRoute = routeBetween(Instant.ofEpochSecond(1_010), Instant.ofEpochSecond(1_100))

    /** Consent-required sessions cannot be constructed through the pinned SDK's public API. */
    private fun consentRequiredSession(id: String, start: Instant, end: Instant): ExerciseSessionRecord =
        mockk {
            every { startTime } returns start
            every { endTime } returns end
            every { startZoneOffset } returns null
            every { endZoneOffset } returns null
            every { metadata } returns Metadata.manualEntryWithId(id, null)
            every { exerciseType } returns ExerciseSessionRecord.EXERCISE_TYPE_RUNNING
            every { title } returns null
            every { notes } returns null
            every { segments } returns emptyList()
            every { laps } returns emptyList()
            every { plannedExerciseSessionId } returns null
            every { exerciseRouteResult } returns ExerciseRouteResult.ConsentRequired()
        }

    private fun nativeDataSession(id: String, start: Instant, end: Instant): ExerciseSessionRecord =
        ExerciseSessionRecord(
            startTime = start,
            startZoneOffset = null,
            endTime = end,
            endZoneOffset = null,
            metadata = Metadata.manualEntryWithId(id, null),
            exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
            exerciseRoute = routeBetween(start, end),
        )

    private fun mapper(record: ExerciseSessionRecord): RawRecord =
        RawHealthConnectMapper.map(record, "exercise_session")

    private class RecordingGateway(
        private val decision: (List<PendingExerciseRouteConsent>) -> Map<String, ExerciseRoute>,
    ) : ExerciseRouteConsentGateway {
        val requests = mutableListOf<List<PendingExerciseRouteConsent>>()
        override suspend fun requestRoutes(sessions: List<PendingExerciseRouteConsent>): Map<String, ExerciseRoute> {
            requests += sessions
            return decision(sessions)
        }
    }

    private fun routeState(record: RawRecord): String =
        record.fields.getValue("route").jsonObject.getValue("state").jsonPrimitive.content

    private fun routeLocationCount(record: RawRecord): Int =
        record.fields.getValue("route").jsonObject.getValue("locations").jsonArray.size

    @Test
    fun grantedRouteMergesInPlaceAndPreservesCanonicalRecordOrder() = runTest {
        val third = consentRequiredSession("third", Instant.ofEpochSecond(1_400), Instant.ofEpochSecond(1_500))
        val gateway = RecordingGateway { sessions ->
            assertThat(sessions.map { it.sessionId }).containsExactly("third", "first").inOrder()
            mapOf("first" to grantedRoute)
        }

        val emitted = withInteractiveRouteConsent {
            collectEmitted(
                listOf(
                    consentRequiredSession("first", Instant.ofEpochSecond(1_010), Instant.ofEpochSecond(1_100)),
                    nativeDataSession("second", Instant.ofEpochSecond(1_110), Instant.ofEpochSecond(1_200)),
                    third,
                    nativeDataSession("fourth", Instant.ofEpochSecond(1_600), Instant.ofEpochSecond(1_700)),
                ),
                gateway,
            )
        }

        assertThat(emitted.records.map { it.metadata!!.id }).containsExactly("first", "second", "third", "fourth").inOrder()
        assertThat(routeState(emitted.records[0])).isEqualTo("data")
        assertThat(routeLocationCount(emitted.records[0])).isEqualTo(2)
        assertThat(routeState(emitted.records[1])).isEqualTo("data")
        assertThat(routeState(emitted.records[2])).isEqualTo("consent_required")
        assertThat(routeLocationCount(emitted.records[2])).isEqualTo(0)
        assertThat(routeState(emitted.records[3])).isEqualTo("data")
        assertThat(emitted.count).isEqualTo(4)
        assertThat(gateway.requests).hasSize(1)
    }

    @Test
    fun deniedConsentKeepsConsentRequiredAndNeverFailsTheExport() = runTest {
        val gateway = RecordingGateway { emptyMap() }

        val emitted = withInteractiveRouteConsent {
            collectEmitted(
                listOf(
                    consentRequiredSession("first", Instant.ofEpochSecond(1_010), Instant.ofEpochSecond(1_100)),
                    consentRequiredSession("second", Instant.ofEpochSecond(1_110), Instant.ofEpochSecond(1_200)),
                ),
                gateway,
            )
        }

        assertThat(emitted.records.map { routeState(it) }).containsExactly("consent_required", "consent_required").inOrder()
        assertThat(emitted.records.map { routeLocationCount(it) }).containsExactly(0, 0).inOrder()
        assertThat(emitted.count).isEqualTo(2)
    }

    @Test
    fun throwingGatewayDegradesToConsentRequiredInsteadOfFailing() = runTest {
        val gateway = ExerciseRouteConsentGateway { throw IllegalStateException("surface unavailable") }

        val emitted = withInteractiveRouteConsent {
            collectEmitted(listOf(consentRequiredSession("first", Instant.ofEpochSecond(1_010), Instant.ofEpochSecond(1_100))), gateway)
        }

        assertThat(emitted.records.single().let(::routeState)).isEqualTo("consent_required")
        assertThat(emitted.count).isEqualTo(1)
    }

    @Test
    fun nonInteractiveRunNeverPromptsAndPassesConsentRequiredThrough() = runTest {
        // Direct protocol / CLI, scheduled, and automation runs execute without the interactive
        // marker; the gateway must not even be consulted.
        val gateway = RecordingGateway { error("non-interactive runs must not prompt") }

        val emitted = collectEmitted(
            listOf(
                consentRequiredSession("first", Instant.ofEpochSecond(1_010), Instant.ofEpochSecond(1_100)),
                nativeDataSession("second", Instant.ofEpochSecond(1_110), Instant.ofEpochSecond(1_200)),
            ),
            gateway,
        )

        assertThat(emitted.records.map { routeState(it) }).containsExactly("consent_required", "data").inOrder()
        assertThat(emitted.count).isEqualTo(2)
        assertThat(gateway.requests).isEmpty()
    }

    @Test
    fun boundedTwoPassPaginationKeepsCanonicalOrderAndNewestCandidateLimit() = runTest {
        val pages = (1..24).chunked(3).map { ids ->
            ids.map { index ->
                consentRequiredSession(
                    "session-$index",
                    Instant.ofEpochSecond(1_000L + index * 10L),
                    Instant.ofEpochSecond(1_005L + index * 10L),
                )
            }
        }
        val starts = mutableListOf<String?>()
        val requested = mutableListOf<PendingExerciseRouteConsent>()
        val emitted = mutableListOf<RawRecord>()

        val count = withInteractiveRouteConsent {
            emitExerciseSessionsWithRouteConsent(
                request = request(),
                gateway = ExerciseRouteConsentGateway { candidates ->
                    requested += candidates
                    emptyMap()
                },
                readPage = { token ->
                    starts += token
                    val index = token?.toInt() ?: 0
                    pages[index] to (index + 1).takeIf { it < pages.size }?.toString()
                },
                mapper = ::mapper,
                emitRecord = { emitted += it },
            )
        }

        assertThat(starts.count { it == null }).isEqualTo(2)
        assertThat(requested).hasSize(ExerciseRouteConsentCoordinator.MAX_PROMPTS_PER_EXPORT)
        assertThat(requested.first().sessionId).isEqualTo("session-24")
        assertThat(requested.last().sessionId).isEqualTo("session-15")
        assertThat(emitted.map { it.metadata!!.id }).containsExactlyElementsIn((1..24).map { "session-$it" }).inOrder()
        assertThat(count).isEqualTo(24)
    }

    @Test
    fun recordsOutsideTheHalfOpenRangeAreStillExcludedOnTheConsentPath() = runTest {
        val emitted = withInteractiveRouteConsent {
            collectEmitted(
                listOf(
                    consentRequiredSession("before", Instant.ofEpochSecond(900), Instant.ofEpochSecond(950)),
                    consentRequiredSession("inside", Instant.ofEpochSecond(1_010), Instant.ofEpochSecond(1_100)),
                    consentRequiredSession("boundary", Instant.ofEpochSecond(2_000), Instant.ofEpochSecond(2_100)),
                ),
                RecordingGateway { mapOf("inside" to grantedRoute) },
            )
        }

        assertThat(emitted.records.map { it.metadata!!.id }).containsExactly("inside")
        assertThat(emitted.records.single().let(::routeState)).isEqualTo("data")
    }

    private class Emitted(val records: List<RawRecord>, val count: Long)

    private suspend fun collectEmitted(
        sessions: List<ExerciseSessionRecord>,
        gateway: ExerciseRouteConsentGateway,
    ): Emitted {
        val records = mutableListOf<RawRecord>()
        val count = emitExerciseSessionsWithRouteConsent(
            request = request(),
            gateway = gateway,
            readPage = { token ->
                if (token == null) sessions to null else emptyList<ExerciseSessionRecord>() to null
            },
            mapper = ::mapper,
            emitRecord = { records += it },
        )
        return Emitted(records, count)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class ExerciseRouteConsentCoordinatorTest {

    private class RecordingSurface(
        private val coordinator: ExerciseRouteConsentCoordinator,
        private val decision: ((PendingExerciseRouteConsent) -> ExerciseRoute?)? = null,
    ) : ExerciseRouteConsentCoordinator.Surface {
        val prompted = mutableListOf<PendingExerciseRouteConsent>()
        override fun launchRouteRequest(session: PendingExerciseRouteConsent): Boolean {
            prompted += session
            decision?.let { coordinator.onRouteResult(it(session)) }
            return true
        }
    }

    private fun route(points: Int) = ExerciseRoute(
        (0 until points).map { index ->
            ExerciseRoute.Location(Instant.ofEpochSecond(1_000L + index), 45.0 + index, -122.0 - index, null, null, null)
        },
    )

    private fun pending(id: String, startEpochSecond: Long) = PendingExerciseRouteConsent(
        sessionId = id,
        sessionStartTime = Instant.ofEpochSecond(startEpochSecond),
        sessionEndTime = Instant.ofEpochSecond(startEpochSecond + 600),
    )

    @Test
    fun grantsAreKeyedBySessionId() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val surface = RecordingSurface(coordinator) { route(3) }
        coordinator.attach(surface)

        val granted = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("a", 100), pending("b", 200)))
        }

        assertThat(granted.keys).containsExactly("a", "b")
        assertThat(granted.values.all { it.route.size == 3 }).isTrue()
    }

    @Test
    fun denialReturnsNoGrantButContinuesPromptingRemainingSessions() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val surface = RecordingSurface(coordinator) { session -> if (session.sessionId == "b") route(1) else null }
        coordinator.attach(surface)

        val granted = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("a", 100), pending("b", 200), pending("c", 300)))
        }

        assertThat(granted.keys).containsExactly("b")
        assertThat(surface.prompted.map { it.sessionId }).containsExactly("c", "b", "a").inOrder()
    }

    @Test
    fun promptCountIsRunScopedAcrossCallsAndNewestSessionsAreFirst() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val surface = RecordingSurface(coordinator) { route(1) }
        coordinator.attach(surface)

        val granted = withInteractiveRouteConsent {
            val newest = coordinator.requestRoutes((16..25).map { pending("session-$it", it * 1_000L) })
            val older = coordinator.requestRoutes((1..15).map { pending("session-$it", it * 1_000L) })
            newest + older
        }

        assertThat(surface.prompted).hasSize(ExerciseRouteConsentCoordinator.MAX_PROMPTS_PER_EXPORT)
        assertThat(surface.prompted.first().sessionId).isEqualTo("session-25")
        assertThat(surface.prompted.last().sessionId).isEqualTo("session-16")
        assertThat(granted).hasSize(ExerciseRouteConsentCoordinator.MAX_PROMPTS_PER_EXPORT)
    }

    @Test
    fun duplicateSessionsArePromptedOncePerRun() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val surface = RecordingSurface(coordinator) { route(1) }
        coordinator.attach(surface)

        withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("a", 100), pending("a", 100)))
            coordinator.requestRoutes(listOf(pending("a", 100)))
        }

        assertThat(surface.prompted.map { it.sessionId }).containsExactly("a")
    }

    @Test
    fun withoutInteractiveRunOrAttachedSurfaceNoPromptHappens() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val detached = coordinator.requestRoutes(listOf(pending("a", 100)))
        val interactiveDetached = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("b", 200)))
        }

        assertThat(detached).isEmpty()
        assertThat(interactiveDetached).isEmpty()
    }

    @Test
    fun pendingResultSurvivesSurfaceRebindingAfterRotation() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val original = RecordingSurface(coordinator)
        coordinator.attach(original)
        val result = async {
            withInteractiveRouteConsent { coordinator.requestRoutes(listOf(pending("a", 100))) }
        }
        runCurrent()
        assertThat(original.prompted.map { it.sessionId }).containsExactly("a")

        coordinator.detach(original)
        val rebound = RecordingSurface(coordinator)
        coordinator.attach(rebound)
        coordinator.onRouteResult(route(2))

        assertThat(result.await().keys).containsExactly("a")
        assertThat(rebound.prompted).isEmpty()
    }

    @Test
    fun timeoutLateResultCannotSatisfyNewerRequest() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val surface = RecordingSurface(coordinator)
        coordinator.attach(surface)
        val timedOut = async {
            withInteractiveRouteConsent { coordinator.requestRoutes(listOf(pending("old", 100))) }
        }
        runCurrent()
        advanceTimeBy(ExerciseRouteConsentCoordinator.PROMPT_TIMEOUT_MS + 1)
        assertThat(timedOut.await()).isEmpty()

        val blockedNew = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("new", 200)))
        }
        assertThat(blockedNew).isEmpty()
        assertThat(surface.prompted.map { it.sessionId }).containsExactly("old")

        coordinator.onRouteResult(route(1)) // drain old late result
        val replacement = RecordingSurface(coordinator) { route(2) }
        coordinator.attach(replacement)
        val afterDrain = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("newer", 300)))
        }
        assertThat(afterDrain.keys).containsExactly("newer")
    }

    @Test
    fun concurrentRunsAreSerialized() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val surface = RecordingSurface(coordinator)
        coordinator.attach(surface)
        val first = async {
            withInteractiveRouteConsent { coordinator.requestRoutes(listOf(pending("first", 200))) }
        }
        val second = async {
            withInteractiveRouteConsent { coordinator.requestRoutes(listOf(pending("second", 100))) }
        }
        runCurrent()
        assertThat(surface.prompted.map { it.sessionId }).containsExactly("first")
        coordinator.onRouteResult(route(1))
        runCurrent()
        assertThat(surface.prompted.map { it.sessionId }).containsExactly("first", "second").inOrder()
        coordinator.onRouteResult(route(1))
        assertThat(first.await().keys).containsExactly("first")
        assertThat(second.await().keys).containsExactly("second")
    }

    @Test
    fun cancellationAbandonsSlotUntilItsLateResultIsDrained() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        val surface = RecordingSurface(coordinator)
        coordinator.attach(surface)
        val cancelled = async {
            withInteractiveRouteConsent { coordinator.requestRoutes(listOf(pending("cancelled", 100))) }
        }
        runCurrent()
        cancelled.cancel()
        runCurrent()

        val blocked = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("blocked", 200)))
        }
        assertThat(blocked).isEmpty()
        coordinator.onRouteResult(route(1))

        val completing = RecordingSurface(coordinator) { route(1) }
        coordinator.attach(completing)
        val granted = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("after", 300)))
        }
        assertThat(granted.keys).containsExactly("after")
    }

    @Test
    fun brokenSurfaceIsTreatedAsDenial() = runTest {
        val coordinator = ExerciseRouteConsentCoordinator()
        coordinator.attach(object : ExerciseRouteConsentCoordinator.Surface {
            override fun launchRouteRequest(session: PendingExerciseRouteConsent): Boolean = false
        })

        val granted = withInteractiveRouteConsent {
            coordinator.requestRoutes(listOf(pending("a", 100)))
        }

        assertThat(granted).isEmpty()
    }
}
