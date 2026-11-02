package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.*
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthDataProvider
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.direct.DirectGeneratedFilesProducer
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.nio.file.Files
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Before
import org.junit.Test

class RemoteProviderBindingTest {
    @Before
    fun loadQualifiedCore() {
        val library = System.getenv("HEALTHMD_HOST_CORE_LIBRARY")
        org.junit.Assume.assumeTrue(!library.isNullOrBlank())
        System.setProperty("uniffi.component.healthmd_core_uniffi.libraryOverride", library!!)
    }

    @Test
    fun apiPreviewAndUploadUseAcceptedProviderAndNextOperationUsesNewChoice() = runTest {
        for (mode in SleepDayAttribution.entries) {
            val fixture = SourceFixture(mode)
            val payloads = mutableListOf<String>()
            val json = JsonExporter()
            val uploader = object : APIExportUploader {
                override suspend fun upload(endpointUrl: String, payload: String, authorizationHeader: String?,
                    requestHeaders: List<APIExportRequestHeader>): APIExportUploadResult {
                    payloads += payload
                    return APIExportUploadResult(202)
                }
            }
            val credentials = object : APIExportCredentialStore {
                override suspend fun authorizationHeader(): String? = null
                override suspend fun hasAuthorization() = false
                override suspend fun saveAuthorization(value: String) = Unit
                override suspend fun clearAuthorization() = Unit
            }
            val runner = APIEndpointExportRunner(healthRepository = fixture.repository,
                envelopeBuilder = APIExportEnvelopeBuilder(json), jsonExporter = json,
                uploader = uploader, credentialStore = credentials)
            val settings = fixture.settings.copy(exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.invalid/healthmd")
            val preview = runner.previewDates(fixture.dates.take(2), settings,
                onProgress = { _, _, _ -> fixture.selected = "whoop" })
            assertThat(preview.previewedDateCount).isEqualTo(2)
            assertThat(fixture.calls).containsExactly("health_connect", "health_connect").inOrder()
            fixture.reset()
            val result = runner.exportDates(fixture.dates.take(2), settings,
                onProgress = { _, _, _ -> fixture.selected = "whoop" })
            assertThat(result.successCount).isEqualTo(2)
            assertThat(fixture.calls).containsExactly("health_connect", "health_connect").inOrder()
            val records = Json.parseToJsonElement(payloads.single()).jsonObject.getValue("records").jsonArray
            assertThat(records.map { steps(it.jsonObject) }).containsExactly(10, 10)
            fixture.calls.clear()
            assertThat(runner.previewDates(fixture.dates.take(1), settings).previewedDateCount).isEqualTo(1)
            assertThat(fixture.calls).containsExactly("whoop")
        }
    }

    @Test
    fun gatewayPreviewAndUploadUseAcceptedProviderAndNextOperationUsesNewChoice() = runTest {
        for (mode in SleepDayAttribution.entries) {
            MockWebServer().use { server ->
                server.start()
                val fixture = SourceFixture(mode)
                val runner = AgentDataGatewayExportRunner(healthRepository = fixture.repository,
                    gatewayClient = AgentDataGatewayUploadClient(OkHttpClient(), maxAttempts = 1, backoffMillis = { 0 }),
                    jsonExporter = JsonExporter(), markdownExporter = MarkdownExporter(),
                    csvExporter = CsvExporter(), obsidianBasesExporter = ObsidianBasesExporter())
                val settings = fixture.settings.copy(exportTarget = ExportTarget.AGENT_DATA_GATEWAY,
                    agentDataGatewayUrl = server.url("/").toString())
                val preview = runner.previewDates(fixture.dates.take(2), settings,
                    onProgress = { _, _, _ -> fixture.selected = "whoop" })
                assertThat(preview.previewedDateCount).isEqualTo(2)
                assertThat(fixture.calls).containsExactly("health_connect", "health_connect").inOrder()
                assertThat(preview.days.flatMap { it.files }.map { steps(Json.parseToJsonElement(it.content).jsonObject) })
                    .containsExactly(10, 10)
                assertThat(server.requestCount).isEqualTo(0)
                fixture.reset()
                repeat(2) { server.enqueue(MockResponse().setResponseCode(200).setBody(acceptedReceipt)) }
                val result = runner.exportDates(fixture.dates.take(2), settings,
                    onProgress = { _, _, _ -> fixture.selected = "whoop" })
                assertThat(result.successCount).isEqualTo(2)
                assertThat(fixture.calls).containsExactly("health_connect", "health_connect").inOrder()
                assertThat(server.requestCount).isEqualTo(2)
                fixture.calls.clear()
                assertThat(runner.previewDates(fixture.dates.take(1), settings).previewedDateCount).isEqualTo(1)
                assertThat(fixture.calls).containsExactly("whoop")
            }
        }
    }

    @Test
    fun bindingFailureOrCancellationNeverCapturesUploadsOrCreatesDirectOutput() = runTest {
        for (failure in listOf(java.io.IOException("private settings diagnostic"),
            kotlinx.coroutines.CancellationException("binding cancelled"))) {
            val fixture = SourceFixture(SleepDayAttribution.NIGHT_BEGINS)
            fixture.bindingFailure = failure
            val uploader = mockk<APIExportUploader>()
            val json = JsonExporter()
            val api = APIEndpointExportRunner(healthRepository = fixture.repository,
                envelopeBuilder = APIExportEnvelopeBuilder(json), jsonExporter = json,
                uploader = uploader, credentialStore = mockk(relaxed = true))
            val apiResult = runCatching { api.exportDates(fixture.dates.take(2), fixture.settings.copy(
                exportTarget = ExportTarget.API_ENDPOINT, apiEndpointUrl = "https://api.example.invalid/healthmd")) }
            if (failure is kotlinx.coroutines.CancellationException) {
                assertThat(apiResult.exceptionOrNull()).isInstanceOf(kotlinx.coroutines.CancellationException::class.java)
            } else {
                assertThat(apiResult.getOrThrow().successCount).isEqualTo(0)
                assertThat(apiResult.getOrThrow().failedDateDetails.all { it.errorDetails == null }).isTrue()
            }
            io.mockk.coVerify(exactly = 0) { uploader.upload(any(), any(), any(), any()) }
            assertThat(fixture.bindingReads).isEqualTo(1)
            val client = mockk<AgentDataGatewayUploadClient>()
            val gateway = AgentDataGatewayExportRunner(fixture.repository, client, JsonExporter(),
                MarkdownExporter(), CsvExporter(), ObsidianBasesExporter())
            val gatewayResult = gateway.exportDates(fixture.dates.take(2), fixture.settings.copy(
                exportTarget = ExportTarget.AGENT_DATA_GATEWAY, agentDataGatewayUrl = "https://gateway.example.invalid"))
            assertThat(gatewayResult.successCount).isEqualTo(0)
            assertThat(gatewayResult.wasCancelled).isEqualTo(failure is kotlinx.coroutines.CancellationException)
            assertThat(gatewayResult.failedDateDetails.all { it.errorDetails == null }).isTrue()
            io.mockk.confirmVerified(client)
            assertThat(fixture.bindingReads).isEqualTo(2)
            val producer = DirectGeneratedFilesProducer(fixture.repository, MarkdownExporter(), JsonExporter(),
                CsvExporter(), ObsidianBasesExporter())
            val root = Files.createTempDirectory("healthmd-provider-binding-failure-").toFile()
            try {
                val direct = runCatching { producer.produce(root, fixture.dates.take(2), fixture.settings, fixture.context) }
                if (failure is kotlinx.coroutines.CancellationException) {
                    assertThat(direct.exceptionOrNull()).isInstanceOf(kotlinx.coroutines.CancellationException::class.java)
                } else {
                    assertThat(direct.exceptionOrNull()?.message).isEqualTo("Export source selection is unavailable.")
                }
                assertThat(java.io.File(root, "generated").exists()).isFalse()
                assertThat(fixture.bindingReads).isEqualTo(3)
            } finally {
                root.deleteRecursively()
            }
            assertThat(fixture.calls).isEmpty()
        }
    }

    @Test
    fun directChunksUseAcceptedProviderAndReusedProducerBindsNextOperationIndependently() = runTest {
        for (mode in SleepDayAttribution.entries) {
            val fixture = SourceFixture(mode)
            val pin = ExportEnginePinPlanner().forDirectGeneratedFiles(fixture.settings, fixture.context.zoneId)
            if (mode == SleepDayAttribution.MORNING_ENDS) assertThat(pin).isNotNull()
            val settings = fixture.settings.copy(executionEnginePin = pin, executionEngineAuthorityIsFrozen = true)
            val producer = DirectGeneratedFilesProducer(fixture.repository, MarkdownExporter(), JsonExporter(),
                CsvExporter(), ObsidianBasesExporter())
            val root = Files.createTempDirectory("healthmd-provider-binding-").toFile()
            try {
                val files = producer.produce(java.io.File(root, "first"), fixture.dates, settings, fixture.context,
                    onProgress = { _, _ -> fixture.selected = "whoop" })
                assertThat(fixture.calls).containsExactly("health_connect", "health_connect").inOrder()
                assertThat(files).hasSize(31)
                assertThat(files.map { steps(Json.parseToJsonElement(it.file.readText()).jsonObject) }.distinct())
                    .containsExactly(10)
                fixture.calls.clear()
                val next = producer.produce(java.io.File(root, "next"), fixture.dates.take(1), settings, fixture.context)
                assertThat(fixture.calls).containsExactly("whoop")
                assertThat(steps(Json.parseToJsonElement(next.single().file.readText()).jsonObject)).isEqualTo(999)
            } finally {
                root.deleteRecursively()
            }
        }
    }

    private class SourceFixture(mode: SleepDayAttribution) {
        var selected = "health_connect"
        var bindingFailure: Exception? = null
        var bindingReads = 0
        val calls = mutableListOf<String>()
        val dates = (0 until 31).map { LocalDate.of(2026, 7, 1).plusDays(it.toLong()) }
        val context = AndroidCaptureContext(ZoneId.of("UTC"), mode)
        val settings = ExportSettings(exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        val repository: HealthRepositoryImpl
        init {
            val manager = mockk<HealthConnectManager>()
            every { manager.isBeforeFirstUnlock() } returns false
            coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
                calls += "health_connect"
                firstArg<List<LocalDate>>().map { HealthData(it, activity = ActivityData(steps = 10)) }
            }
            val alternate = mockk<HealthDataProvider>()
            every { alternate.providerId } returns "whoop"
            coEvery { alternate.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
                calls += "whoop"
                firstArg<List<LocalDate>>().map { HealthData(it, activity = ActivityData(steps = 999)) }
            }
            val preferences = mockk<SettingsRepository>()
            coEvery { preferences.getSelectedHealthProviderId() } answers {
                bindingReads += 1
                bindingFailure?.let { throw it }
                selected
            }
            coEvery { preferences.getSleepDayAttribution() } returns mode
            repository = HealthRepositoryImpl(HealthProviderRegistry(HealthConnectDataProvider(manager), listOf(alternate)), preferences)
        }
        fun reset() { selected = "health_connect"; calls.clear() }
    }

    companion object {
        private fun steps(root: JsonObject): Int = root.getValue("activity").jsonObject.getValue("steps").jsonPrimitive.int
        private val acceptedReceipt = """{"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"accepted","stored":{"revision_id":"0000000000000000000000000000000000000000000000000000000000000000","byte_count":1,"completeness":{"type":"complete"}}}"""
    }
}
