package com.healthmd.data.health.providers.cloud

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.oauth.InMemoryOAuthTokenStore
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthToken
import com.healthmd.domain.model.WorkoutType
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test

class WhoopCloudDataProviderTest {
    private val date = LocalDate.parse("2026-06-02")
    private val clock = Clock.fixed(Instant.parse("2026-06-02T18:00:00Z"), ZoneOffset.UTC)

    @Test
    fun compatibilityCollectionsFollowV2PagesAndKeepNewestScoredRecovery() = runTest {
        val requests = mutableListOf<CloudHttpRequest>()
        val provider = provider { request ->
            requests += request
            val next = "nextToken=" in request.url.query.orEmpty()
            when (request.url.path) {
                "/developer/v2/activity/sleep" -> response(if (next) """{"records":[]}""" else """
                    {"records":[],"next_token":"sleep-page-2"}
                """)
                "/developer/v2/activity/workout" -> response("""
                    {"records":[${workout(if (next) 302 else 301)}],"next_token":${if (next) "null" else "\"workout-page-2\""}}
                """)
                "/developer/v2/recovery" -> response(if (next) """
                    {"records":[{"cycle_id":100,"score":{"resting_heart_rate":61,"hrv_rmssd_milli":40}}]}
                """ else """
                    {"records":[{"cycle_id":102,"score_state":"PENDING_SCORE"},
                     {"cycle_id":101,"score":{"resting_heart_rate":52,"hrv_rmssd_milli":68.5}}],"next_token":"recovery-page-2"}
                """)
                "/developer/v2/user/measurement/body" -> response("""{"weight_kilogram":78.4}""")
                else -> error("Unexpected WHOOP endpoint")
            }
        }

        val data = provider.fetchHealthData(date)

        assertThat(data.workouts.map { it.id }).containsExactly(
            "00000000-0000-4000-8000-000000000301", "00000000-0000-4000-8000-000000000302",
        ).inOrder()
        assertThat(data.activity.activeCalories).isWithin(0.001).of(600.0)
        assertThat(data.heart.restingHeartRate).isEqualTo(52.0)
        assertThat(data.heart.hrv).isEqualTo(68.5)
        assertThat(data.body.weight).isEqualTo(78.4)
        assertThat(requests).hasSize(7)
        requests.filterNot { it.url.path.endsWith("/body") }.forEach {
            assertThat(it.url.query).startsWith("start=2026-06-02T00%3A00%3A00Z&end=2026-06-03T00%3A00%3A00Z&limit=25")
            assertThat(it.url.query).doesNotContain("cycleId")
        }
        assertThat(requests.none { it.url.path.endsWith("/cycle") }).isTrue()
    }

    @Test
    fun v2SportNamesAndUuidIdentityDoNotDependOnRemovedSportId() = runTest {
        val names = listOf("running", "cycling", "swimming", "walking", "hiking", "weightlifting", "yoga", "future-sport")
        val data = provider { request ->
            when {
                request.url.path.endsWith("/workout") -> response("""{"records":[${names.mapIndexed { index, name -> workout(301 + index, name) }.joinToString(",") }]}""")
                request.url.path.endsWith("/body") -> response("{}")
                else -> response("""{"records":[]}""")
            }
        }.fetchHealthData(date)

        assertThat(data.workouts.map { it.workoutType }).containsExactly(
            WorkoutType.RUNNING, WorkoutType.CYCLING, WorkoutType.SWIMMING, WorkoutType.WALKING,
            WorkoutType.HIKING, WorkoutType.STRENGTH_TRAINING, WorkoutType.YOGA, WorkoutType.OTHER,
        ).inOrder()
        assertThat(data.workouts.map { it.metadata["sport_name"] }).containsExactlyElementsIn(names).inOrder()
        assertThat(data.workouts.all { it.duration.inWholeMilliseconds == 1_800_125L }).isTrue()
    }

    @Test
    fun historicalDailyExportsDoNotRepeatCurrentBodyProfile() = runTest {
        val requests = mutableListOf<CloudHttpRequest>()
        val data = provider { request ->
            requests += request
            response("""{"records":[]}""")
        }.fetchHealthData(date.minusDays(1))

        assertThat(data.body.hasData).isFalse()
        assertThat(requests).hasSize(3)
        assertThat(requests.none { it.url.path.endsWith("/body") }).isTrue()
    }

    @Test
    fun dayBoundsAndElapsedWorkoutDurationRespectDst() = runTest {
        val dstClock = Clock.fixed(Instant.parse("2026-11-02T12:00:00Z"), ZoneId.of("America/Los_Angeles"))
        val requests = mutableListOf<CloudHttpRequest>()
        val data = provider(dstClock) { request ->
            requests += request
            if (request.url.path.endsWith("/workout")) response("""
                {"records":[{"id":"00000000-0000-4000-8000-000000000301","sport_name":"walking",
                 "start":"2026-11-01T08:30:00Z","end":"2026-11-01T09:30:00.125Z","score_state":"PENDING_SCORE"}]}
            """) else response("""{"records":[]}""")
        }.fetchHealthData(LocalDate.parse("2026-11-01"))

        requests.forEach {
            assertThat(it.url.query).isEqualTo("start=2026-11-01T07%3A00%3A00Z&end=2026-11-02T08%3A00%3A00Z&limit=25")
        }
        assertThat(data.workouts.single().duration.inWholeMilliseconds).isEqualTo(3_600_125L)
        assertThat(data.workouts.single().calories).isNull()
        assertThat(data.activity.activeCalories).isNull()
    }

    @Test
    fun laterPageFailureKeepsSuccessfulWorkoutsAndIndependentRecovery() = runTest {
        val data = provider { request ->
            when {
                request.url.path.endsWith("/sleep") -> CloudHttpResponse(403)
                request.url.path.endsWith("/workout") && "nextToken=" in request.url.query.orEmpty() -> CloudHttpResponse(500)
                request.url.path.endsWith("/workout") -> response("""{"records":[${workout(301)}],"next_token":"later-page"}""")
                request.url.path.endsWith("/recovery") -> response("""{"records":[{"score":{"resting_heart_rate":52}}]}""")
                else -> response("{}")
            }
        }.fetchHealthData(date)

        assertThat(data.sleep.hasData).isFalse()
        assertThat(data.workouts).hasSize(1)
        assertThat(data.activity.activeCalories).isWithin(0.001).of(300.0)
        assertThat(data.heart.restingHeartRate).isEqualTo(52.0)
    }

    @Test
    fun compatibilityPagingStopsRepeatedTokensAndAtOneHundredPages() = runTest {
        suspend fun assertBound(repeat: Boolean, expectedCalls: Int) {
            var calls = 0
            val data = provider { request ->
                if (request.url.path.endsWith("/workout")) {
                    calls++
                    response("""{"records":[${workout(300 + calls)}],"next_token":"${if (repeat) "repeat" else "page-$calls"}"}""")
                } else if (request.url.path.endsWith("/body")) response("{}") else response("""{"records":[]}""")
            }.fetchHealthData(date)
            assertThat(calls).isEqualTo(expectedCalls)
            assertThat(data.workouts).hasSize(expectedCalls)
        }
        assertBound(repeat = true, expectedCalls = 2)
        assertBound(repeat = false, expectedCalls = MAX_NATIVE_PAGES_PER_ENDPOINT)
    }

    @Test
    fun compatibilityCancellationIsNotConvertedToEmptyData() = runTest {
        val failure = runCatching {
            provider { throw CancellationException("synthetic cancellation") }.fetchHealthData(date)
        }.exceptionOrNull()
        assertThat(failure).isInstanceOf(CancellationException::class.java)
    }

    private fun provider(
        clock: Clock = this.clock,
        transport: suspend (CloudHttpRequest) -> CloudHttpResponse,
    ) = WhoopCloudDataProvider(
        CloudHealthApiClient.forTesting(
            OAuthAuthorizationManager(OAuthConfigRegistry(emptyList()), InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "synthetic-token")))),
            CloudHttpTransport(transport),
        ),
        clock = clock,
    )

    private fun response(body: String) = CloudHttpResponse(200, "application/json", body = body.trimIndent().toByteArray())

    private fun workout(id: Int, sport: String = "running") = """
        {"id":"00000000-0000-4000-8000-${id.toString().padStart(12, '0')}","sport_name":"$sport",
         "start":"2026-06-02T12:00:00Z","end":"2026-06-02T12:30:00.125Z","score_state":"SCORED",
         "score":{"kilojoule":1255.2,"zone_durations":{"zone_zero_milli":1000}}}
    """.trimIndent()
}
