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
    fun dailySleepDoesNotAddThePreviousNightsOverlappingApiRecord() = runTest {
        val previousNight = sleep(201, 7 * 3_600_000L)
            .replace("2026-06-02T22:00:00Z", "2026-06-01T23:00:00Z")
            .replace("2026-06-02T23:00:00Z", "2026-06-02T06:00:00Z")
        val requestedNight = sleep(202, 8 * 3_600_000L)
            .replace("2026-06-02T22:00:00Z", "2026-06-02T22:00:00Z")
            .replace("2026-06-02T23:00:00Z", "2026-06-03T06:00:00Z")
        val requests = mutableListOf<CloudHttpRequest>()
        val data = provider { request ->
            requests += request
            if (request.url.path.endsWith("/sleep")) {
                response("""{"records":[$requestedNight,$previousNight]}""")
            } else if (request.url.path.endsWith("/body")) response("{}")
            else response("""{"records":[]}""")
        }.fetchHealthData(date)

        assertThat(data.sleep.totalDuration.inWholeHours).isEqualTo(8)
        assertThat(data.sleep.sessions).hasSize(1)
        val sleepRequest = requests.single { it.url.path.endsWith("/sleep") }
        assertThat(sleepRequest.url.query).startsWith("start=2026-06-02T12%3A00%3A00Z&end=2026-06-03T12%3A00%3A00Z")

        val adjacentDays = provider { request ->
            if (request.url.path.endsWith("/sleep")) response("""{"records":[$requestedNight,$previousNight]}""")
            else if (request.url.path.endsWith("/body")) response("{}") else response("""{"records":[]}""")
        }.fetchHealthDataRange(listOf(date.minusDays(1), date), zoneId = ZoneOffset.UTC)
        assertThat(adjacentDays.map { it.sleep.totalDuration.inWholeHours }).containsExactly(7L, 8L).inOrder()
    }

    @Test
    fun sleepWindowKeepsNapsAdditiveAndExcludesInvalidAndExactBoundaryRecords() = runTest {
        fun session(id: Int, start: String, end: String, minutes: Long) = sleep(id, minutes * 60_000)
            .replace("2026-06-02T22:00:00Z", start)
            .replace("2026-06-02T23:00:00Z", end)
        val records = listOf(
            session(201, "2026-06-02T11:00:00Z", "2026-06-02T12:00:00Z", 60),
            session(202, "2026-06-03T12:00:00Z", "2026-06-03T13:00:00Z", 60),
            session(203, "2026-06-02T12:00:00Z", "2026-06-02T13:00:00Z", 60),
            session(204, "2026-06-02T15:00:00Z", "2026-06-02T15:30:00Z", 30),
            session(205, "2026-06-02T15:00:00Z", "2026-06-02T15:00:00Z", 60),
            session(206, "2026-06-02T16:00:00Z", "2026-06-02T15:00:00Z", 60),
            session(207, "not-a-timestamp", "2026-06-02T18:00:00Z", 60),
        )
        val data = provider { request ->
            if (request.url.path.endsWith("/sleep")) response("""{"records":[${records.joinToString(",")}]}""")
            else if (request.url.path.endsWith("/body")) response("{}") else response("""{"records":[]}""")
        }.fetchHealthData(date)
        assertThat(data.sleep.totalDuration.inWholeMinutes).isEqualTo(90)
        assertThat(data.sleep.sessions).hasSize(2)
    }

    @Test
    fun rangeUsesCapturedExportZoneAndMatchesSingleDayInThatZone() = runTest {
        val zone = ZoneId.of("America/Los_Angeles")
        val records = sleep(201)
            .replace("2026-06-02T22:00:00Z", "2026-06-03T16:00:00Z")
            .replace("2026-06-02T23:00:00Z", "2026-06-03T17:00:00Z")
        val requests = mutableListOf<CloudHttpRequest>()
        val transport: (CloudHttpRequest) -> CloudHttpResponse = { request ->
            requests += request
            if (request.url.path.endsWith("/sleep")) response("""{"records":[$records]}""")
            else if (request.url.path.endsWith("/body")) response("{}") else response("""{"records":[]}""")
        }
        val ranged = provider(clock, transport).fetchHealthDataRange(listOf(date), zoneId = zone).single()
        val single = provider(clock.withZone(zone), transport).fetchHealthData(date)
        assertThat(ranged.sleep).isEqualTo(single.sleep)
        assertThat(ranged.sleep.totalDuration.inWholeMinutes).isEqualTo(60)
        requests.filter { it.url.path.endsWith("/sleep") }.forEach {
            assertThat(it.url.query).startsWith("start=2026-06-02T19%3A00%3A00Z&end=2026-06-03T19%3A00%3A00Z")
        }
    }

    @Test
    fun sleepNoonsRespectBothDstTransitions() = runTest {
        val zone = ZoneId.of("America/Los_Angeles")
        for ((day, bounds) in listOf(
            "2026-03-07" to ("2026-03-07T20%3A00%3A00Z" to "2026-03-08T19%3A00%3A00Z"),
            "2026-10-31" to ("2026-10-31T19%3A00%3A00Z" to "2026-11-01T20%3A00%3A00Z"),
        )) {
            val requests = mutableListOf<CloudHttpRequest>()
            provider(clock.withZone(zone)) { request -> requests += request; response("""{"records":[]}""") }
                .fetchHealthData(LocalDate.parse(day))
            val request = requests.single { it.url.path.endsWith("/sleep") }
            assertThat(request.url.query).isEqualTo("start=${bounds.first}&end=${bounds.second}&limit=25")
        }
    }

    @Test
    fun crossingNoonPreservesWholeProviderStageAggregatesAndSourceTimes() = runTest {
        val source = sleep(201, 90 * 60_000)
            .replace("2026-06-02T22:00:00Z", "2026-06-02T11:00:00Z")
            .replace("2026-06-02T23:00:00Z", "2026-06-02T13:00:00Z")
        val data = provider { request ->
            if (request.url.path.endsWith("/sleep")) response("""{"records":[$source]}""")
            else if (request.url.path.endsWith("/body")) response("{}") else response("""{"records":[]}""")
        }.fetchHealthData(date)
        // WHOOP supplies whole-session stage totals, not timestamped stage intervals.
        assertThat(data.sleep.totalDuration.inWholeMinutes).isEqualTo(90)
        assertThat(data.sleep.sessions.single().startTime.hour).isEqualTo(11)
        assertThat(data.sleep.sessions.single().endTime.hour).isEqualTo(13)
    }

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
            val hour = if (it.url.path.endsWith("/sleep")) "12" else "00"
            assertThat(it.url.query).startsWith("start=2026-06-02T${hour}%3A00%3A00Z&end=2026-06-03T${hour}%3A00%3A00Z&limit=25")
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
            val expected = if (it.url.path.endsWith("/sleep"))
                "start=2026-11-01T20%3A00%3A00Z&end=2026-11-02T20%3A00%3A00Z&limit=25"
            else "start=2026-11-01T07%3A00%3A00Z&end=2026-11-02T08%3A00%3A00Z&limit=25"
            assertThat(it.url.query).isEqualTo(expected)
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
    fun repeatedPagesDoNotDoubleWorkoutCaloriesOrSleepTotals() = runTest {
        val requests = mutableListOf<CloudHttpRequest>()
        val data = provider { request ->
            requests += request
            when {
                request.url.path.endsWith("/sleep") -> response("""{"records":[${sleep(201)}],"next_token":"repeat-sleep"}""")
                request.url.path.endsWith("/workout") -> response("""{"records":[${workout(301)}],"next_token":"repeat-workout"}""")
                request.url.path.endsWith("/body") -> response("{}")
                else -> response("""{"records":[]}""")
            }
        }.fetchHealthData(date)

        assertThat(requests.count { it.url.path.endsWith("/sleep") }).isEqualTo(2)
        assertThat(requests.count { it.url.path.endsWith("/workout") }).isEqualTo(2)
        assertThat(data.workouts).hasSize(1)
        assertThat(data.activity.activeCalories).isWithin(0.001).of(300.0)
        assertThat(data.sleep.totalDuration.inWholeMinutes).isEqualTo(60)
        assertThat(data.sleep.sessions).hasSize(1)
    }

    @Test
    fun overlappingPagesKeepFirstCapturedRecordPerProviderIdentity() = runTest {
        val data = provider { request ->
            val next = "nextToken=" in request.url.query.orEmpty()
            when {
                request.url.path.endsWith("/sleep") -> response(if (next) """
                    {"records":[${sleep(201, 7_200_000)},${sleep(202, 1_800_000)}]}
                """ else """{"records":[${sleep(201)}],"next_token":"sleep-page-2"}""")
                request.url.path.endsWith("/workout") -> response(if (next) """
                    {"records":[${workout(301).replace("1255.2", "4184.0")},${workout(302)}]}
                """ else """{"records":[${workout(301)}],"next_token":"workout-page-2"}""")
                request.url.path.endsWith("/recovery") -> response(if (next) """
                    {"records":[{"cycle_id":"101","score":{"resting_heart_rate":61,"hrv_rmssd_milli":40}},
                     {"cycle_id":100,"score":{"hrv_rmssd_milli":68.5}}]}
                """ else """
                    {"records":[{"cycle_id":101,"score":{"resting_heart_rate":52}}],"next_token":"recovery-page-2"}
                """)
                else -> response("{}")
            }
        }.fetchHealthData(date)

        assertThat(data.workouts.map { it.id }).containsExactly(
            "00000000-0000-4000-8000-000000000301", "00000000-0000-4000-8000-000000000302",
        ).inOrder()
        assertThat(data.workouts.first().calories).isWithin(0.001).of(300.0)
        assertThat(data.activity.activeCalories).isWithin(0.001).of(600.0)
        assertThat(data.sleep.totalDuration.inWholeMinutes).isEqualTo(90)
        assertThat(data.sleep.sessions).hasSize(2)
        assertThat(data.heart.restingHeartRate).isEqualTo(52.0)
        assertThat(data.heart.hrv).isEqualTo(68.5)
    }

    @Test
    fun recordsWithoutProviderIdentityAreNotCollapsedTogether() = runTest {
        val data = provider { request ->
            val next = "nextToken=" in request.url.query.orEmpty()
            when {
                request.url.path.endsWith("/sleep") -> response(if (next) """
                    {"records":[${sleep(null, 1_800_000)}]}
                """ else """{"records":[${sleep(null)}],"next_token":"sleep-page-2"}""")
                request.url.path.endsWith("/recovery") -> response(if (next) """
                    {"records":[{"score":{"hrv_rmssd_milli":68.5}}]}
                """ else """{"records":[{"score":{"resting_heart_rate":52}}],"next_token":"recovery-page-2"}""")
                request.url.path.endsWith("/body") -> response("{}")
                else -> response("""{"records":[]}""")
            }
        }.fetchHealthData(date)

        assertThat(data.sleep.totalDuration.inWholeMinutes).isEqualTo(90)
        assertThat(data.sleep.sessions).hasSize(2)
        assertThat(data.heart.restingHeartRate).isEqualTo(52.0)
        assertThat(data.heart.hrv).isEqualTo(68.5)
    }

    @Test
    fun malformedMappingInOneSectionPreservesHealthySections() = runTest {
        for (malformed in listOf("sleep", "workout-calories", "workout-id", "recovery")) {
            val data = provider { request ->
                when {
                    request.url.path.endsWith("/sleep") -> response("""{"records":[${
                        if (malformed == "sleep") sleep(201).replace("\"total_light_sleep_time_milli\":3600000", "\"total_light_sleep_time_milli\":[]")
                        else sleep(201)
                    }]}""")
                    request.url.path.endsWith("/workout") -> response("""{"records":[${
                        when (malformed) {
                            "workout-calories" -> workout(301).replace("\"kilojoule\":1255.2", "\"kilojoule\":[]")
                            "workout-id" -> workout(301).replace("\"id\":\"00000000-0000-4000-8000-000000000301\"", "\"id\":[]")
                            else -> workout(301)
                        }
                    }]}""")
                    request.url.path.endsWith("/recovery") -> response(if (malformed == "recovery") """
                        {"records":[{"cycle_id":101,"score":{"resting_heart_rate":{}}}]}
                    """ else """{"records":[{"cycle_id":101,"score":{"resting_heart_rate":52,"hrv_rmssd_milli":68.5}}]}""")
                    else -> response("""{"weight_kilogram":78.4}""")
                }
            }.fetchHealthData(date)

            assertThat(data.sleep.hasData).isEqualTo(malformed != "sleep")
            assertThat(data.activity.activeCalories).isEqualTo(if (malformed == "workout-calories") null else 300.0)
            assertThat(data.heart.restingHeartRate).isEqualTo(if (malformed == "recovery") null else 52.0)
            assertThat(data.heart.hrv).isEqualTo(if (malformed == "recovery") null else 68.5)
            assertThat(data.body.weight).isEqualTo(78.4)
            assertThat(data.workouts).hasSize(if (malformed.startsWith("workout-")) 0 else 1)
        }
    }

    @Test
    fun compatibilityCancellationIsNotConvertedToEmptyData() = runTest {
        for (endpoint in listOf("/sleep", "/workout", "/recovery", "/body")) {
            val failure = runCatching {
                provider { request ->
                    if (request.url.path.endsWith(endpoint)) throw CancellationException("synthetic cancellation")
                    response("""{"records":[]}""")
                }.fetchHealthData(date)
            }.exceptionOrNull()
            assertThat(failure).isInstanceOf(CancellationException::class.java)
        }
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

    private fun sleep(id: Int?, lightMs: Long = 3_600_000) = """
        {"id":${id?.let { "\"00000000-0000-4000-8000-${it.toString().padStart(12, '0')}\"" } ?: "null"},
         "start":"2026-06-02T22:00:00Z","end":"2026-06-02T23:00:00Z","score_state":"SCORED",
         "score":{"stage_summary":{"total_light_sleep_time_milli":$lightMs,"total_in_bed_time_milli":3600000}}}
    """.trimIndent()

    private fun workout(id: Int, sport: String = "running") = """
        {"id":"00000000-0000-4000-8000-${id.toString().padStart(12, '0')}","sport_name":"$sport",
         "start":"2026-06-02T12:00:00Z","end":"2026-06-02T12:30:00.125Z","score_state":"SCORED",
         "score":{"kilojoule":1255.2,"zone_durations":{"zone_zero_milli":1000}}}
    """.trimIndent()
}
