package com.healthmd.data.health.providers.cloud

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.oauth.InMemoryOAuthTokenStore
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthToken
import com.healthmd.domain.model.WorkoutType
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.time.LocalDate

class CloudProviderFixtureMappingTest {
    private lateinit var server: MockWebServer
    private val date: LocalDate = LocalDate.parse("2026-06-02")

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
    fun fitbitFixture_mapsActivitySleepHeartAndBodyData() = runTest {
        enqueueFixture("fitbit/activity.json")
        enqueueFixture("fitbit/sleep.json")
        enqueueFixture("fitbit/heart.json")
        enqueueFixture("fitbit/body.json")

        val data = FitbitCloudDataProvider(apiClient("fitbit"), baseUrl()).fetchHealthData(date)

        assertThat(data.date).isEqualTo(date)
        assertThat(data.activity.steps).isEqualTo(12345)
        assertThat(data.activity.activeCalories).isWithin(0.001).of(678.0)
        assertThat(data.activity.totalCalories).isWithin(0.001).of(2345.0)
        assertThat(data.activity.exerciseMinutes).isWithin(0.001).of(35.0)
        assertThat(data.activity.walkingRunningDistance).isWithin(0.001).of(7890.0)
        assertThat(data.activity.flightsClimbed).isEqualTo(8)
        assertThat(data.sleep.totalDuration.inWholeMinutes).isEqualTo(480)
        assertThat(data.sleep.deepSleep.inWholeMinutes).isEqualTo(70)
        assertThat(data.sleep.remSleep.inWholeMinutes).isEqualTo(90)
        assertThat(data.sleep.lightSleep.inWholeMinutes).isEqualTo(280)
        assertThat(data.sleep.awakeTime.inWholeMinutes).isEqualTo(55)
        assertThat(data.sleep.sessions).hasSize(1)
        assertThat(data.sleep.sessions.single().source).isEqualTo("Fitbit")
        assertThat(data.heart.restingHeartRate).isWithin(0.001).of(58.0)
        assertThat(data.heart.averageHeartRate).isWithin(0.001).of(65.0)
        assertThat(data.heart.heartRateMin).isWithin(0.001).of(60.0)
        assertThat(data.heart.heartRateMax).isWithin(0.001).of(70.0)
        assertThat(data.heart.samples).hasSize(3)
        assertThat(data.body.weight).isWithin(0.001).of(70.2)
        assertThat(data.body.bodyFatPercentage).isWithin(0.001).of(18.0)
        assertThat(data.body.bmi).isWithin(0.001).of(22.3)

        assertThat(server.takeRequest().path).isEqualTo("/1/user/-/activities/date/2026-06-02.json")
        assertThat(server.takeRequest().path).isEqualTo("/1.2/user/-/sleep/date/2026-06-02.json")
        assertThat(server.takeRequest().getHeader("Authorization")).isEqualTo("Bearer token-fitbit")
    }

    @Test
    fun withingsFixture_mapsActivitySleepHeartAndBodyData() = runTest {
        enqueueFixture("withings/activity.json")
        enqueueFixture("withings/sleep.json")
        enqueueFixture("withings/activity.json")
        enqueueFixture("withings/measures.json")
        enqueueFixture("withings/measures.json")

        val data = WithingsCloudDataProvider(apiClient("withings"), baseUrl()).fetchHealthData(date)

        assertThat(data.activity.steps).isEqualTo(9000)
        assertThat(data.activity.activeCalories).isWithin(0.001).of(450.0)
        assertThat(data.activity.totalCalories).isWithin(0.001).of(2100.0)
        assertThat(data.activity.walkingRunningDistance).isWithin(0.001).of(6400.5)
        assertThat(data.activity.elevationGained).isWithin(0.001).of(32.0)
        assertThat(data.sleep.totalDuration.inWholeSeconds).isEqualTo(27000)
        assertThat(data.sleep.deepSleep.inWholeSeconds).isEqualTo(5400)
        assertThat(data.sleep.lightSleep.inWholeSeconds).isEqualTo(14400)
        assertThat(data.sleep.remSleep.inWholeSeconds).isEqualTo(7200)
        assertThat(data.sleep.awakeTime.inWholeSeconds).isEqualTo(1800)
        assertThat(data.heart.restingHeartRate).isWithin(0.001).of(60.0)
        assertThat(data.heart.averageHeartRate).isWithin(0.001).of(62.0)
        assertThat(data.heart.heartRateMin).isWithin(0.001).of(50.0)
        assertThat(data.heart.heartRateMax).isWithin(0.001).of(140.0)
        assertThat(data.body.weight).isWithin(0.001).of(70.5)
        assertThat(data.body.height).isWithin(0.001).of(1.8)
        assertThat(data.body.bodyFatPercentage).isWithin(0.001).of(18.2)
        assertThat(data.body.leanBodyMass).isWithin(0.001).of(55.0)

        assertThat(server.takeRequest().path).startsWith("/v2/measure?action=getactivity")
        assertThat(server.takeRequest().path).startsWith("/v2/sleep?action=getsummary")
    }

    @Test
    fun ouraFixture_mapsActivitySleepHeartAndWorkoutData() = runTest {
        enqueueFixture("oura/daily_activity.json")
        enqueueFixture("oura/sleep.json")
        enqueueFixture("oura/heartrate.json")
        enqueueFixture("oura/workout.json")

        val data = OuraCloudDataProvider(apiClient("oura"), baseUrl()).fetchHealthData(date)

        assertThat(data.activity.steps).isEqualTo(10101)
        assertThat(data.activity.activeCalories).isWithin(0.001).of(555.0)
        assertThat(data.activity.totalCalories).isWithin(0.001).of(2400.0)
        assertThat(data.activity.walkingRunningDistance).isWithin(0.001).of(8123.4)
        assertThat(data.sleep.totalDuration.inWholeSeconds).isEqualTo(27000)
        assertThat(data.sleep.deepSleep.inWholeSeconds).isEqualTo(5400)
        assertThat(data.sleep.remSleep.inWholeSeconds).isEqualTo(6300)
        assertThat(data.sleep.lightSleep.inWholeSeconds).isEqualTo(15300)
        assertThat(data.sleep.awakeTime.inWholeSeconds).isEqualTo(2700)
        assertThat(data.sleep.sessions.single().metadata).containsEntry("provider", "Oura")
        assertThat(data.heart.averageHeartRate).isWithin(0.001).of(55.0)
        assertThat(data.heart.heartRateMin).isWithin(0.001).of(51.0)
        assertThat(data.heart.heartRateMax).isWithin(0.001).of(59.0)
        assertThat(data.heart.samples).hasSize(3)
        assertThat(data.workouts).hasSize(1)
        assertThat(data.workouts.single().workoutType).isEqualTo(WorkoutType.RUNNING)
        assertThat(data.workouts.single().duration.inWholeSeconds).isEqualTo(1800)
        assertThat(data.workouts.single().calories).isWithin(0.001).of(320.0)
        assertThat(data.workouts.single().distance).isWithin(0.001).of(5000.0)

        assertThat(server.takeRequest().path).startsWith("/daily_activity?start_date=2026-06-02")
    }

    @Test
    fun whoopFixture_mapsSleepActivityRecoveryBodyAndWorkoutData() = runTest {
        enqueueFixture("whoop/sleep.json")
        enqueueFixture("whoop/workouts.json")
        enqueueFixture("whoop/cycle.json")
        enqueueFixture("whoop/recovery.json")
        enqueueFixture("whoop/body.json")
        enqueueFixture("whoop/workouts.json")

        val data = WhoopCloudDataProvider(apiClient("whoop"), baseUrl()).fetchHealthData(date)

        assertThat(data.sleep.totalDuration.inWholeMinutes).isEqualTo(450)
        assertThat(data.sleep.lightSleep.inWholeMinutes).isEqualTo(300)
        assertThat(data.sleep.remSleep.inWholeMinutes).isEqualTo(60)
        assertThat(data.sleep.deepSleep.inWholeMinutes).isEqualTo(90)
        assertThat(data.sleep.awakeTime.inWholeMinutes).isEqualTo(30)
        assertThat(data.sleep.inBedTime.inWholeMinutes).isEqualTo(480)
        assertThat(data.activity.activeCalories).isWithin(0.001).of(300.0)
        assertThat(data.heart.restingHeartRate).isWithin(0.001).of(52.0)
        assertThat(data.heart.hrv).isWithin(0.001).of(68.5)
        assertThat(data.body.height).isWithin(0.001).of(1.82)
        assertThat(data.body.weight).isWithin(0.001).of(78.4)
        assertThat(data.workouts).hasSize(1)
        assertThat(data.workouts.single().workoutType).isEqualTo(WorkoutType.RUNNING)
        assertThat(data.workouts.single().duration.inWholeSeconds).isEqualTo(1800)
        assertThat(data.workouts.single().calories).isWithin(0.001).of(300.0)
        assertThat(data.workouts.single().averageHeartRate).isWithin(0.001).of(145.0)
        assertThat(data.workouts.single().heartRateMax).isWithin(0.001).of(178.0)

        assertThat(server.takeRequest().path).startsWith("/activity/sleep?start=")
        assertThat(server.takeRequest().path).startsWith("/activity/workout?start=")
    }

    @Test
    fun cloudProvider_keepsReadableSectionsWhenOneEndpointFails() = runTest {
        enqueueFixture("fitbit/activity.json")
        server.enqueue(MockResponse().setResponseCode(429).setBody("{\"errors\":[{\"message\":\"rate limited\"}]}"))
        enqueueFixture("fitbit/heart.json")
        enqueueFixture("fitbit/body.json")

        val data = FitbitCloudDataProvider(apiClient("fitbit"), baseUrl()).fetchHealthData(date)

        assertThat(data.activity.steps).isEqualTo(12345)
        assertThat(data.sleep.hasData).isFalse()
        assertThat(data.heart.restingHeartRate).isWithin(0.001).of(58.0)
        assertThat(data.body.weight).isWithin(0.001).of(70.2)
    }

    private fun apiClient(providerId: String): CloudHealthApiClient {
        val tokenStore = InMemoryOAuthTokenStore(
            listOf(OAuthToken(providerId = providerId, accessToken = "token-$providerId")),
        )
        return CloudHealthApiClient(
            OAuthAuthorizationManager(
                configRegistry = OAuthConfigRegistry(emptyList()),
                tokenStore = tokenStore,
            ),
        )
    }

    private fun enqueueFixture(path: String) {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(fixture(path)),
        )
    }

    private fun fixture(path: String): String =
        requireNotNull(javaClass.classLoader?.getResource("health-providers/$path")) {
            "Missing health provider test fixture: $path"
        }.readText()

    private fun baseUrl(): String = server.url("/").toString().removeSuffix("/")
}
