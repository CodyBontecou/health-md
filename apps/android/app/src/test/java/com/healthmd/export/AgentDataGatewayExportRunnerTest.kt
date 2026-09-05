package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.AgentDataGatewayExportRunner
import com.healthmd.data.export.AgentDataGatewayUploadClient
import com.healthmd.data.export.AgentDataGatewayCaptureSource
import com.healthmd.data.export.AgentDataIngestManifest
import com.healthmd.data.export.AgentDataIngestManifestBuilder
import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.model.AgentDataArtifactOutcome
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.ActivityData
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

class AgentDataGatewayExportRunnerTest {

    private lateinit var server: MockWebServer
    private val day = LocalDate.of(2026, 3, 15)
    private val otherDay = LocalDate.of(2026, 3, 16)

    private val settings = ExportSettings(
        exportTarget = ExportTarget.AGENT_DATA_GATEWAY,
        scheduledExportTarget = ExportTarget.AGENT_DATA_GATEWAY,
        agentDataGatewayUrl = "https://gateway.example.invalid",
        exportFormats = setOf(com.healthmd.domain.model.ExportFormat.JSON),
        exportFormat = com.healthmd.domain.model.ExportFormat.JSON,
    )

    private fun captureSource(dataByDate: Map<LocalDate, HealthData>): AgentDataGatewayCaptureSource =
        object : AgentDataGatewayCaptureSource {
            override fun isBeforeFirstUnlock(): Boolean = false
            override suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData =
                dataByDate[date] ?: HealthData(date)
        }

    private val legacyPlanner: LocalDailyAggregateExportPlanner =
        LocalDailyAggregateExportPlanner { _, _ -> LocalDailyAggregatePlanningResult.Legacy }

    private fun runner(
        dataByDate: Map<LocalDate, HealthData>,
        planner: LocalDailyAggregateExportPlanner = legacyPlanner,
    ): AgentDataGatewayExportRunner {
        val client = AgentDataGatewayUploadClient(
            client = OkHttpClient(),
            maxAttempts = 2,
            backoffMillis = { 0 },
        )
        return AgentDataGatewayExportRunner(
            captureSource = captureSource(dataByDate),
            gatewayClient = client,
            jsonExporter = JsonExporter(),
            dailyAggregatePlanner = planner,
        )
    }

    private fun acceptReceipt(): String =
        """{"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"accepted",
            "stored":{"revision_id":"0000000000000000000000000000000000000000000000000000000000000000",
                      "byte_count":1,"completeness":{"type":"complete"}}}""".trimIndent()

    private fun rejectReceipt(code: String): String =
        """{"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"rejected",
            "rejection":{"code":"$code"}}""".trimIndent()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun localSettings() = settings.copy(
        agentDataGatewayUrl = server.url("/").toString(),
    )

    @Test
    fun uploadsTheExactFolderParityJsonBytesPerDay() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(acceptReceipt()))
        server.enqueue(MockResponse().setResponseCode(200).setBody(acceptReceipt()))
        val data = HealthData(day, activity = ActivityData(steps = 100))
        val runner = runner(mapOf(day to data))

        val result = runner.exportDates(listOf(day), localSettings())

        assertThat(result.target).isEqualTo(ExportTarget.AGENT_DATA_GATEWAY)
        assertThat(result.successCount).isEqualTo(1)
        assertThat(result.failedDateDetails).isEmpty()
        assertThat(result.agentDataOutcomes).hasSize(1)
        assertThat(result.agentDataOutcomes.single().state)
            .isEqualTo(AgentDataArtifactOutcome.State.ACCEPTED)
        assertThat(result.agentDataOutcomes.single().ownerDate).isEqualTo(day)

        val recorded = server.takeRequest()
        assertThat(recorded.path).isEqualTo("/v1/ingest")
        val body = recorded.body.readByteArray()
        val newline = body.indexOf('\n'.code.toByte())
        val manifestRoot = Json.parseToJsonElement(body.copyOfRange(0, newline).decodeToString())
            .jsonObject
        val artifactBytes = body.copyOfRange(newline + 1, body.size)

        // The manifest describes the artifact's own identity and the exact uploaded bytes.
        assertThat(manifestRoot.getValue("schema").jsonPrimitive.content)
            .isEqualTo("healthmd.agent_data_ingest")
        assertThat(manifestRoot.getValue("platform").jsonPrimitive.content).isEqualTo("android")
        assertThat(manifestRoot.getValue("artifact_kind").jsonPrimitive.content)
            .isEqualTo("health_data_daily")
        assertThat(manifestRoot.getValue("artifact_schema").jsonPrimitive.content)
            .isEqualTo("healthmd.health_data")
        assertThat(manifestRoot.getValue("artifact_schema_version").jsonPrimitive.content).isEqualTo("4")
        assertThat(manifestRoot.getValue("owner_date").jsonPrimitive.content).isEqualTo(day.toString())
        assertThat(manifestRoot.getValue("completeness").jsonObject.toString())
            .isEqualTo("{\"type\":\"complete\"}")
        assertThat(manifestRoot.getValue("byte_count").jsonPrimitive.content)
            .isEqualTo(artifactBytes.size.toString())
        assertThat(manifestRoot.getValue("sha256").jsonPrimitive.content)
            .isEqualTo(AgentDataIngestManifestBuilder.sha256Hex(artifactBytes))

        // Folder parity: the uploaded bytes are exactly what the JSON exporter renders.
        val expected = JsonExporter().export(
            data = data,
            customization = localSettings().formatCustomization,
            includeGranularData = false,
        ).encodeToByteArray()
        assertThat(artifactBytes).isEqualTo(expected)
    }

    @Test
    fun rejectedArtifactFailsOnlyItsDayAndNeverBlocksRemainingArtifacts() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(rejectReceipt("checksum_invalid")))
        server.enqueue(MockResponse().setResponseCode(200).setBody(acceptReceipt()))

        val runner = runner(
            mapOf(
                day to HealthData(day, activity = ActivityData(steps = 100)),
                otherDay to HealthData(otherDay, activity = ActivityData(steps = 200)),
            ),
        )

        val result = runner.exportDates(listOf(otherDay, day), localSettings())

        assertThat(result.successCount).isEqualTo(1)
        assertThat(result.failedDateDetails).containsExactly(
            FailedDateDetail(day, ExportFailureReason.API_REJECTED, "checksum_invalid"),
        )
        assertThat(result.agentDataOutcomes).hasSize(2)
        assertThat(result.agentDataOutcomes.first().state)
            .isEqualTo(AgentDataArtifactOutcome.State.REJECTED)
        assertThat(result.agentDataOutcomes.first().rejectionCode).isEqualTo("checksum_invalid")
        assertThat(result.agentDataOutcomes.last().state)
            .isEqualTo(AgentDataArtifactOutcome.State.ACCEPTED)
        assertThat(server.requestCount).isEqualTo(2)
    }

    @Test
    fun uploadFailuresSurfaceAsNetworkErrorsAndNeverBlockRemainingDays() = runTest {
        repeat(2) {
            server.enqueue(
                MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AT_START),
            )
        }
        repeat(2) {
            server.enqueue(
                MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AT_START),
            )
        }

        val runner = runner(
            mapOf(
                day to HealthData(day, activity = ActivityData(steps = 100)),
                otherDay to HealthData(otherDay, activity = ActivityData(steps = 200)),
            ),
        )

        val result = runner.exportDates(listOf(day, otherDay), localSettings())

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.agentDataOutcomes).hasSize(2)
        assertThat(result.agentDataOutcomes.all {
            it.state == AgentDataArtifactOutcome.State.UPLOAD_FAILED
        }).isTrue()
        assertThat(result.failedDateDetails.map { it.reason })
            .containsExactly(ExportFailureReason.NETWORK_ERROR, ExportFailureReason.NETWORK_ERROR)
    }

    @Test
    fun unconfiguredGatewayFailsClosedWithInvalidEndpoint() = runTest {
        val runner = runner(mapOf(day to HealthData(day, activity = ActivityData(steps = 1))))

        val result = runner.exportDates(listOf(day), settings.copy(agentDataGatewayUrl = ""))

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason)
            .isEqualTo(ExportFailureReason.INVALID_API_ENDPOINT)
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun destinationFingerprintMismatchFailsClosed() = runTest {
        val runner = runner(mapOf(day to HealthData(day, activity = ActivityData(steps = 1))))

        val result = runner.exportDates(
            listOf(day),
            localSettings(),
            expectedDestinationFingerprint = "deadbeef",
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason)
            .isEqualTo(ExportFailureReason.INVALID_API_ENDPOINT)
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun daysWithoutUploadableFormatFailWithGatewayFormatUnsupported() = runTest {
        val runner = runner(mapOf(day to HealthData(day, activity = ActivityData(steps = 1))))

        val result = runner.exportDates(
            listOf(day),
            localSettings().copy(
                exportFormats = setOf(com.healthmd.domain.model.ExportFormat.MARKDOWN),
                exportFormat = com.healthmd.domain.model.ExportFormat.MARKDOWN,
            ),
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason)
            .isEqualTo(ExportFailureReason.GATEWAY_FORMAT_UNSUPPORTED)
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun daysWithoutHealthDataReportNoHealthData() = runTest {
        val runner = runner(emptyMap())

        val result = runner.exportDates(listOf(day), localSettings())

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason)
            .isEqualTo(ExportFailureReason.NO_HEALTH_DATA)
    }

    @Test
    fun previewRendersWithoutContactingTheGateway() = runTest {
        val runner = runner(mapOf(day to HealthData(day, activity = ActivityData(steps = 100))))

        val preview = runner.previewDates(listOf(day), localSettings())

        assertThat(preview.previewedDateCount).isEqualTo(1)
        assertThat(preview.days.single().files.single().relativePath)
            .isEqualTo(localSettings().aggregateRelativePath(day, com.healthmd.domain.model.ExportFormat.JSON))
        assertThat(server.requestCount).isEqualTo(0)
    }
}
