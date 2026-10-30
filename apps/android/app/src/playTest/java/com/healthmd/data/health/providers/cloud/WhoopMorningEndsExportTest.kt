package com.healthmd.data.health.providers.cloud

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.*
import com.healthmd.data.health.*
import com.healthmd.data.health.oauth.*
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.mockk
import java.time.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Before
import org.junit.Test

class WhoopMorningEndsExportTest {
    @Before
    fun loadCore() {
        val library = System.getenv("HEALTHMD_HOST_CORE_LIBRARY")
        org.junit.Assume.assumeTrue(!library.isNullOrBlank())
        System.setProperty("uniffi.component.healthmd_core_uniffi.libraryOverride", library!!)
    }

    @Test
    fun actualApiProducerOwnsWholeWhoopSessionsOnWakeDate() = runTest {
        val cases = listOf(
            Case("overnight", "Asia/Kathmandu", "2026-07-02", "2026-07-01T16:15:00Z", "2026-07-02T00:15:00Z", 28_800_000),
            Case("long", "Asia/Kathmandu", "2026-07-02", "2026-07-01T04:15:00Z", "2026-07-02T07:15:00Z", 97_200_000),
            Case("midnight", "Asia/Kathmandu", "2026-07-02", "2026-07-01T17:15:00Z", "2026-07-01T18:15:00Z", 3_600_000),
            Case("fold", "America/Los_Angeles", "2026-11-01", "2026-11-01T01:15:00-07:00", "2026-11-01T01:45:00-08:00", 5_400_000),
        )
        for (case in cases) {
            val zone = ZoneId.of(case.zone)
            val owner = LocalDate.parse(case.owner)
            val context = AndroidCaptureContext(zone, SleepDayAttribution.MORNING_ENDS)
            val requests = mutableListOf<CloudHttpRequest>()
            val repository = repository(case, requests)
            val payloads = mutableListOf<String>()
            val runner = runner(repository, payloads)
            val settings = ExportSettings(exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
                includeGranularData = true, exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.invalid/healthmd", executionSleepCaptureContext = context,
                executionSleepCaptureAuthorityIsFrozen = true)
            val dates = listOf(owner.minusDays(1), owner, owner.plusDays(1))
            val result = runner.exportDates(dates, settings)
            assertThat(result.successCount).isEqualTo(1)
            assertThat(payloads).hasSize(1)
            val records = Json.parseToJsonElement(payloads.single()).jsonObject.getValue("records").jsonArray
            val sleepRecords = records.map { it.jsonObject }.filter { "sleep" in it }
            assertThat(sleepRecords).hasSize(1)
            val record = sleepRecords.single()
            assertThat(record.getValue("date").jsonPrimitive.content).isEqualTo(case.owner)
            assertThat(record.getValue("schema_version").jsonPrimitive.int).isEqualTo(6)
            val sleep = record.getValue("sleep").jsonObject
            assertThat(sleep.getValue("totalDuration").jsonPrimitive.double).isEqualTo(case.millis / 1000.0)
            assertThat(record.toString()).contains("morning_ends")
            assertThat(record.toString()).contains(zone.id)
            writeEvidence(case.name, record.toString())
            val domain = repository.forCaptureOperation().fetchHealthDataRange(dates, zoneId = zone,
                sleepDayAttributionOverride = context.explicitSleepDayAttributionOverride)
            val sessions = domain.flatMap { it.sleep.sessions }
            assertThat(sessions).hasSize(1)
            assertThat(sessions.single().exactStartTime?.instant()).isEqualTo(Instant.parse(case.start))
            assertThat(sessions.single().exactEndTime?.instant()).isEqualTo(Instant.parse(case.end))
            assertThat(sessions.single().identity?.nativeId).isEqualTo(ID)
            assertThat(sessions.single().exactStartTime?.offset).isEqualTo(OffsetDateTime.parse(case.start).offset.id)
            assertThat(sessions.single().exactEndTime?.offset).isEqualTo(OffsetDateTime.parse(case.end).offset.id)
            val expectedBounds = dates.map { day ->
                day.atStartOfDay(zone).toInstant().minusSeconds(1).toString() to day.plusDays(1).atStartOfDay(zone).toInstant().toString()
            }.toSet()
            val actualBounds = requests.filter { it.url.path.endsWith("/sleep") }.map { request ->
                val query = request.url.query.split('&').associate {
                    val parts = it.split('=', limit = 2)
                    parts[0] to java.net.URLDecoder.decode(parts[1], "UTF-8")
                }
                requireNotNull(query["start"]) to requireNotNull(query["end"])
            }.toSet()
            assertThat(actualBounds).isEqualTo(expectedBounds)
            assertThat(domain.single { it.date == owner }.sleep.stages).isEmpty()
        }
    }

    @Test
    fun morningWorkoutRetainsExactSourceClocksAndElapsedNanoseconds() = runTest {
        val case = Case("workout", "America/Los_Angeles", "2026-11-01",
            "2026-11-01T01:15:00.000000001-07:00", "2026-11-01T01:45:00.000000123-08:00", 0, workout = true)
        val owner = LocalDate.parse(case.owner)
        val context = AndroidCaptureContext(ZoneId.of(case.zone), SleepDayAttribution.MORNING_ENDS)
        val data = repository(case, mutableListOf()).forCaptureOperation().fetchHealthDataRange(listOf(owner),
            zoneId = context.zoneId, sleepDayAttributionOverride = context.explicitSleepDayAttributionOverride).single()
        val workout = data.workouts.single()
        assertThat(workout.exactStartTime?.instant()).isEqualTo(Instant.parse(case.start))
        assertThat(workout.exactEndTime?.instant()).isEqualTo(Instant.parse(case.end))
        assertThat(workout.duration.inWholeNanoseconds).isEqualTo(5_400_000_000_122L)
        assertThat(workout.identity?.nativeId).isEqualTo(ID)
        val output = JsonExporter().export(data, includeGranularData = true, captureContext = context)
        assertThat(Json.parseToJsonElement(output).jsonObject.getValue("schema_version").jsonPrimitive.int).isEqualTo(6)
        assertThat(output).contains("morning_ends")
        writeEvidence(case.name, output)
    }

    @Test
    fun selectedMorningEndpointFailuresCannotUploadPartialDays() = runTest {
        val case = Case("failure", "Etc/UTC", "2026-07-02", "2026-07-01T22:00:00Z", "2026-07-02T06:00:00Z", 28_800_000)
        for (mode in listOf("empty", "http", "malformed", "envelope", "cycle", "cap", "http-workout", "http-recovery")) {
            val requests = mutableListOf<CloudHttpRequest>()
            val payloads = mutableListOf<String>()
            val repository = repository(case, requests, mode)
            val context = AndroidCaptureContext(ZoneId.of(case.zone), SleepDayAttribution.MORNING_ENDS)
            val settings = ExportSettings(exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
                includeGranularData = true, exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.invalid/healthmd", executionSleepCaptureContext = context,
                executionSleepCaptureAuthorityIsFrozen = true)
            val result = runner(repository, payloads).exportDates(listOf(LocalDate.parse(case.owner)), settings)
            if (mode == "empty") {
                assertThat(result.successCount).isEqualTo(1)
                assertThat(result.failedDateDetails).isEmpty()
                assertThat(payloads).hasSize(1)
            } else {
                assertThat(result.successCount).isEqualTo(0)
                assertThat(result.failedDateDetails.map { it.date }).containsExactly(LocalDate.parse(case.owner))
                assertThat(payloads).hasSize(1)
                val envelope = Json.parseToJsonElement(payloads.single()).jsonObject
                assertThat(envelope.getValue("records").jsonArray).isEmpty()
                assertThat(envelope.getValue("failed_date_details").jsonArray).hasSize(1)
                assertThat(payloads.single()).contains("whoop cloud request failed")
            }
        }
    }

    @Test
    fun unselectedMorningEndpointsAreNotRequestedAndNightRetainsTolerance() = runTest {
        val case = Case("selection", "UTC", "2027-01-01", "2026-07-01T22:00:00Z", "2026-07-02T06:00:00Z", 28_800_000)
        val requests = mutableListOf<CloudHttpRequest>()
        val repository = repository(case, requests, "http").forCaptureOperation()
        val day = LocalDate.parse(case.owner)
        val data = repository.fetchHealthDataRange(listOf(day),
            dataTypes = DataTypeSelection().deselectAll().copy(heart = true), zoneId = ZoneOffset.UTC,
            sleepDayAttributionOverride = AndroidCaptureContext(ZoneOffset.UTC, SleepDayAttribution.MORNING_ENDS).explicitSleepDayAttributionOverride).single()
        assertThat(data.heart.restingHeartRate).isEqualTo(55.0)
        assertThat(requests.map { it.url.path.substringAfterLast('/') }).containsExactly("recovery")
        requests.clear()
        val night = repository.fetchHealthDataRange(listOf(day), zoneId = ZoneOffset.UTC,
            sleepDayAttributionOverride = AndroidCaptureContext(ZoneOffset.UTC, SleepDayAttribution.NIGHT_BEGINS).explicitSleepDayAttributionOverride).single()
        assertThat(night.heart.restingHeartRate).isEqualTo(55.0)
        assertThat(night.sleep.sessions).isEmpty()
        assertThat(requests.map { it.url.path.substringAfterLast('/') }).containsExactly("sleep", "workout", "recovery", "body")
    }

    @Test
    fun selectedCurrentBodyFailureCannotBecomeEmptyMorningData() = runTest {
        val case = Case("body", "Etc/UTC", "2027-01-01", "2026-12-31T22:00:00Z", "2027-01-01T06:00:00Z", 28_800_000)
        val requests = mutableListOf<CloudHttpRequest>()
        val repository = repository(case, requests, "http-body").forCaptureOperation()
        val error = try {
            repository.fetchHealthDataRange(listOf(LocalDate.parse(case.owner)),
                dataTypes = DataTypeSelection().deselectAll().copy(body = true), zoneId = ZoneId.of(case.zone),
                sleepDayAttributionOverride = AndroidCaptureContext(ZoneId.of(case.zone), SleepDayAttribution.MORNING_ENDS).explicitSleepDayAttributionOverride)
            null
        } catch (error: CloudHealthRequestException) { error }
        assertThat(error?.message).isEqualTo("whoop cloud request failed")
        assertThat(requests.map { it.url.path.substringAfterLast('/') }).containsExactly("body")
    }

    @Test
    fun savedMorningSnapshotRestoresAcceptedAccountThroughActualApiProducer() = runTest {
        for (mode in listOf("unchanged", "rotation", "replacement", "unavailable", "legacy")) {
            val case = Case("saved", "Asia/Kathmandu", "2026-07-02", "2026-07-01T16:15:00Z", "2026-07-02T00:15:00Z", 28_800_000)
            val requests = mutableListOf<CloudHttpRequest>()
            val tokens = InMemoryOAuthTokenStore(if (mode == "unavailable") emptyList() else listOf(OAuthToken("whoop", "accepted")))
            val original = repository(case, requests, tokenStore = tokens)
            val authority = original.captureProviderAuthority()
            val context = AndroidCaptureContext(ZoneId.of(case.zone), SleepDayAttribution.MORNING_ENDS)
            val settings = ExportSettings(exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
                includeGranularData = true, exportTarget = ExportTarget.API_ENDPOINT, scheduledExportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.invalid/healthmd", executionSleepCaptureContext = context,
                executionProviderCaptureAuthority = authority, executionProviderCaptureAuthorityIsFrozen = true)
            val pin = com.healthmd.domain.exportengine.ExportEnginePinPlanner().forScheduledExport(settings, ExportTarget.API_ENDPOINT, context.zoneId)
            val snapshot = com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot.capture(
                if (mode == "legacy") settings.copy(executionProviderCaptureAuthority = null) else settings, pin, context.zoneId)
            val bytes = com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)
            val file = java.nio.file.Files.createTempFile("healthmd-private-snapshot-", ".json")
            try {
                java.nio.file.Files.write(file, bytes.toByteArray())
                if (mode == "rotation") {
                    assertThat(tokens.saveRotatedToken(OAuthToken("whoop", "rotated"), requireNotNull(tokens.getCredential("whoop")))).isTrue()
                } else if (mode in listOf("replacement", "unavailable")) tokens.saveToken(OAuthToken("whoop", "replacement"))
                val reopened = repository(case, requests, tokenStore = tokens, selectedId = "health_connect")
                val decoded = com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec.decode(
                    String(java.nio.file.Files.readAllBytes(file), Charsets.UTF_8))
                val restored = decoded.restoreOnto(settings.copy(executionProviderCaptureAuthority = null))
                    .copy(executionEnginePin = decoded.enginePin)
                val payloads = mutableListOf<String>()
                val result = runner(reopened, payloads).exportDates(listOf(LocalDate.parse(case.owner)), restored)
                val healthy = mode in listOf("unchanged", "rotation")
                assertThat(result.successCount).isEqualTo(if (healthy) 1 else 0)
                assertThat(payloads).hasSize(if (mode == "legacy") 0 else 1)
                val records = payloads.firstOrNull()?.let { Json.parseToJsonElement(it).jsonObject.getValue("records").jsonArray } ?: JsonArray(emptyList())
                assertThat(records).hasSize(if (healthy) 1 else 0)
                if (healthy) {
                    assertThat(requests).isNotEmpty()
                    assertThat(requests.all { it.authorization == "Bearer ${if (mode == "rotation") "rotated" else "accepted"}" }).isTrue()
                    assertThat(records.single().jsonObject.getValue("sleep").jsonObject.getValue("totalDuration").jsonPrimitive.double).isEqualTo(28_800.0)
                } else {
                    assertThat(requests).isEmpty()
                    assertThat(result.failedDateDetails.map { it.date }).containsExactly(LocalDate.parse(case.owner))
                }
                authority.connectionIds.values.filterNotNull().forEach { id -> payloads.forEach { assertThat(it).doesNotContain(id) } }
                requests.clear()
                val captured = mutableListOf<HealthData>()
                val folder = mockk<com.healthmd.domain.repository.ExportRepository>()
                coEvery { folder.hasExportFolder() } returns true
                coEvery { folder.exportHealthData(any(), any()) } answers { captured += firstArg<HealthData>(); true }
                val folderResult = ExportOrchestrator(reopened, folder).exportDates(listOf(LocalDate.parse(case.owner)),
                    restored.copy(exportTarget = ExportTarget.DEVICE_FOLDER, scheduledExportTarget = ExportTarget.DEVICE_FOLDER))
                assertThat(folderResult.successCount).isEqualTo(if (healthy) 1 else 0)
                assertThat(captured).hasSize(if (healthy) 1 else 0)
                if (!healthy) assertThat(requests).isEmpty()
                else assertThat(captured.single().sleep.sessions).hasSize(1)
                requests.clear()
                val gateway = AgentDataGatewayExportRunner(reopened, mockk(relaxed = true), JsonExporter(),
                    MarkdownExporter(), CsvExporter(), ObsidianBasesExporter())
                val preview = gateway.previewDates(listOf(LocalDate.parse(case.owner)), restored.copy(
                    exportTarget = ExportTarget.AGENT_DATA_GATEWAY, scheduledExportTarget = ExportTarget.AGENT_DATA_GATEWAY,
                    agentDataGatewayUrl = "https://gateway.example.invalid"))
                assertThat(preview.previewedDateCount).isEqualTo(if (healthy) 1 else 0)
                if (!healthy) assertThat(requests).isEmpty()
                else assertThat(preview.days.flatMap { it.files }).hasSize(1)
            } finally { java.nio.file.Files.deleteIfExists(file) }
        }
    }

    private fun runner(repository: HealthRepositoryImpl, payloads: MutableList<String>): APIEndpointExportRunner {
        val json = JsonExporter()
        return APIEndpointExportRunner(repository, APIExportEnvelopeBuilder(json), json,
                object : APIExportUploader {
                    override suspend fun upload(endpointUrl: String, payload: String, authorizationHeader: String?,
                        requestHeaders: List<APIExportRequestHeader>): APIExportUploadResult {
                        payloads += payload
                        return APIExportUploadResult(202)
                    }
                }, object : APIExportCredentialStore {
                    override suspend fun authorizationHeader(): String? = null
                    override suspend fun hasAuthorization() = false
                    override suspend fun saveAuthorization(value: String) = Unit
                    override suspend fun clearAuthorization() = Unit
                })
    }

    private fun writeEvidence(name: String, json: String) {
        val folder = System.getenv("HEALTHMD_WHOOP_V6_QA_OUTPUT_DIR") ?: return
        val path = java.nio.file.Path.of(folder)
        java.nio.file.Files.createDirectories(path)
        java.nio.file.Files.write(path.resolve("whoop-$name-v6.json"), json.toByteArray(Charsets.UTF_8))
    }

    private fun repository(case: Case, requests: MutableList<CloudHttpRequest>, failure: String? = null, tokenStore: InMemoryOAuthTokenStore? = null, selectedId: String = "whoop"): HealthRepositoryImpl {
        val token = OAuthToken("whoop", "synthetic")
        val config = OAuthProviderConfig("whoop", "WHOOP", "https://auth.example.test", "https://token.example.test",
            "synthetic-client", scopes = listOf("read:sleep"))
        val client = CloudHealthApiClient.forTesting(
            OAuthAuthorizationManager(OAuthConfigRegistry(listOf(config)), tokenStore ?: InMemoryOAuthTokenStore(listOf(token))),
            CloudHttpTransport { request ->
                requests += request
                // Deliberately overreturn the same whole record. Ownership must be enforced locally.
                val body = if (request.url.path.endsWith("/sleep") && !case.workout) """
                    {"records":[{"id":"$ID","start":"${case.start}","end":"${case.end}","score_state":"SCORED",
                    "score":{"stage_summary":{"total_light_sleep_time_milli":${case.millis},"total_in_bed_time_milli":${case.millis}}}}]}
                """ else if (request.url.path.endsWith("/workout") && case.workout) """
                    {"records":[{"id":"$ID","start":"${case.start}","end":"${case.end}","sport_name":"walking","score_state":"SCORED"}]}
                """ else """{"records":[]}"""
                val isSleep = request.url.path.endsWith("/sleep")
                val responseBody = when {
                    isSleep && failure == "empty" -> """{"records":[]}"""
                    isSleep && failure == "malformed" -> "not json"
                    isSleep && failure == "envelope" -> "{}"
                    isSleep && failure in listOf("cycle", "cap") -> body.trim().dropLast(1) +
                        ",\"next_token\":\"${if (failure == "cycle") "repeat" else requests.size}\"}"
                    request.url.path.endsWith("/recovery") && failure != null ->
                        """{"records":[{"cycle_id":42,"score":{"resting_heart_rate":55}}]}"""
                    else -> body
                }
                val httpFailure = (isSleep && failure == "http") ||
                    (failure == "http-workout" && request.url.path.endsWith("/workout")) ||
                    (failure == "http-recovery" && request.url.path.endsWith("/recovery")) ||
                    (failure == "http-body" && request.url.path.endsWith("/body"))
                CloudHttpResponse(if (httpFailure) 503 else 200,
                    "application/json", body = responseBody.toByteArray())
            })
        val provider = WhoopCloudDataProvider(client, clock = Clock.fixed(Instant.parse("2027-01-01T12:00:00Z"), ZoneOffset.UTC))
        val settings = mockk<SettingsRepository>()
        coEvery { settings.getSelectedHealthProviderId() } returns selectedId
        coEvery { settings.getSleepDayAttribution() } returns SleepDayAttribution.NIGHT_BEGINS
        return HealthRepositoryImpl(HealthProviderRegistry(HealthConnectDataProvider(mockk(relaxed = true)), listOf(provider)), settings)
    }

    private data class Case(val name: String, val zone: String, val owner: String, val start: String, val end: String, val millis: Long, val workout: Boolean = false)
    companion object { private const val ID = "00000000-0000-4000-8000-000000000201" }
}
