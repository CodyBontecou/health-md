package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.records.ExerciseRoute
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.units.Length
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.WorkoutRouteAccess
import com.healthmd.rawexport.ExerciseRouteConsentGateway
import com.healthmd.rawexport.withInteractiveRouteConsent
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Test

/**
 * Issue #132, markdown workout path: Health Connect reports third-party sessions as
 * ConsentRequired. Interactive runs merge granted routes into WorkoutData; every other run keeps
 * reporting WorkoutRouteAccess.CONSENT_REQUIRED without prompting.
 */
class HealthConnectWorkoutRouteConsentTest {

    private val date = LocalDate.of(2026, 7, 12)
    private val grantedRoute = ExerciseRoute(
        listOf(
            ExerciseRoute.Location(Instant.parse("2026-07-12T06:00:00Z"), 45.25, -122.75, Length.meters(3.0), Length.meters(4.0), Length.meters(100.0)),
            ExerciseRoute.Location(Instant.parse("2026-07-12T06:01:00Z"), 45.5, -122.5, null, null, null),
        ),
    )

    /** Consent-required sessions cannot be built through the pinned SDK's public constructors. */
    private fun thirdPartySession(): ExerciseSessionRecord {
        val start = date.atStartOfDay(ZoneId.of("UTC")).plusHours(6).toInstant()
        val end = start.plusSeconds(1_800)
        return mockk {
            every { startTime } returns start
            every { endTime } returns end
            every { startZoneOffset } returns null
            every { endZoneOffset } returns null
            every { metadata } returns Metadata.manualEntryWithId("third-party-1", null)
            every { exerciseType } returns ExerciseSessionRecord.EXERCISE_TYPE_RUNNING
            every { title } returns null
            every { notes } returns null
            every { segments } returns emptyList()
            every { laps } returns emptyList()
            every { plannedExerciseSessionId } returns null
            every { exerciseRouteResult } returns ExerciseRouteResult.ConsentRequired()
        }
    }

    private fun manager(client: HealthConnectClient, gateway: ExerciseRouteConsentGateway) =
        HealthConnectManager(mockk<Context>(relaxed = true), client, routeConsentGateway = gateway)

    private fun stubClient(session: ExerciseSessionRecord): HealthConnectClient {
        val client = mockk<HealthConnectClient>()
        val features = mockk<HealthConnectFeatures>()
        every { features.getFeatureStatus(any()) } returns HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
        every { client.features } returns features
        coEvery { client.aggregate(any<AggregateRequest>()) } returns mockk<AggregationResult>(relaxed = true)
        coEvery { client.readRecords(any<ReadRecordsRequest<ExerciseSessionRecord>>()) } answers {
            val request = firstArg<ReadRecordsRequest<*>>()
            if (request.recordType == ExerciseSessionRecord::class) {
                ReadRecordsResponse(listOf(session), null)
            } else {
                ReadRecordsResponse(emptyList<ExerciseSessionRecord>(), null)
            }
        }
        return client
    }

    private suspend fun fetchWorkouts(client: HealthConnectClient, gateway: ExerciseRouteConsentGateway) =
        manager(client, gateway).fetchHealthDataRange(
            dates = listOf(date),
            selection = DataTypeSelection().deselectAll().copy(workouts = true),
            includeGranularData = true,
            zoneId = ZoneId.of("UTC"),
        )

    @Test
    fun interactiveRunMergesGrantedThirdPartyRouteIntoWorkoutData() = runTest {
        val session = thirdPartySession()
        val requested = mutableListOf<List<com.healthmd.rawexport.PendingExerciseRouteConsent>>()
        val gateway = ExerciseRouteConsentGateway { sessions ->
            requested += sessions
            mapOf("third-party-1" to grantedRoute)
        }

        val data = withInteractiveRouteConsent { fetchWorkouts(stubClient(session), gateway) }

        val workout = data.single().workouts.single()
        assertThat(requested.map { it.map { pending -> pending.sessionId } })
            .containsExactly(listOf("third-party-1"))
        assertThat(workout.routeAccess).isEqualTo(WorkoutRouteAccess.DATA)
        assertThat(workout.route).hasSize(2)
        assertThat(workout.route.first().latitude).isEqualTo(45.25)
        assertThat(workout.route.first().altitude).isEqualTo(100.0)
        assertThat(workout.route.first().longitude).isEqualTo(-122.75)
    }

    @Test
    fun nonInteractiveRunKeepsConsentRequiredAndNeverPrompts() = runTest {
        val session = thirdPartySession()
        val gateway = ExerciseRouteConsentGateway { sessions ->
            error("Non-interactive markdown runs must not prompt for route consent (requested ${sessions.size}).")
        }

        val data = fetchWorkouts(stubClient(session), gateway)

        val workout = data.single().workouts.single()
        assertThat(workout.routeAccess).isEqualTo(WorkoutRouteAccess.CONSENT_REQUIRED)
        assertThat(workout.route).isEmpty()
    }

    @Test
    fun deniedPromptKeepsConsentRequiredReporting() = runTest {
        val session = thirdPartySession()
        val gateway = ExerciseRouteConsentGateway { emptyMap() }

        val data = withInteractiveRouteConsent { fetchWorkouts(stubClient(session), gateway) }

        val workout = data.single().workouts.single()
        assertThat(workout.routeAccess).isEqualTo(WorkoutRouteAccess.CONSENT_REQUIRED)
        assertThat(workout.route).isEmpty()
    }

    @Test
    fun nativeRouteSessionsRemainUnchangedByTheGateway() = runTest {
        // A first-party session whose route Health Connect already returns inline must never be
        // re-prompted; only ConsentRequired sessions become consent candidates.
        val start = date.atStartOfDay(ZoneId.of("UTC")).plusHours(6).toInstant()
        val session = ExerciseSessionRecord(
            startTime = start,
            startZoneOffset = null,
            endTime = start.plusSeconds(1_800),
            endZoneOffset = null,
            metadata = Metadata.manualEntryWithId("first-party-1", null),
            exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
            exerciseRoute = grantedRoute,
        )
        val requested = mutableListOf<Int>()
        val gateway = ExerciseRouteConsentGateway { sessions ->
            requested += sessions.size
            emptyMap()
        }

        val data = withInteractiveRouteConsent { fetchWorkouts(stubClient(session), gateway) }

        val workout = data.single().workouts.single()
        assertThat(requested).isEmpty()
        assertThat(workout.routeAccess).isEqualTo(WorkoutRouteAccess.DATA)
        assertThat(workout.route).hasSize(2)
    }
}
