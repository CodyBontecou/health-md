package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.AgentDataGatewayException
import com.healthmd.data.export.AgentDataGatewayUploadClient
import com.healthmd.data.export.AgentDataIngestManifest
import com.healthmd.data.export.AgentDataIngestManifestBuilder
import com.healthmd.data.export.AgentDataUploadReceipt
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

/**
 * Exercises the client against a MockWebServer implementing the frozen server contract
 * (every validated outcome is HTTP 2xx with a `healthmd.agent_ingest_response` v1 receipt;
 * rejections are protocol outcomes, never HTTP errors).
 */
class AgentDataGatewayUploadClientTest {

    private lateinit var server: MockWebServer
    private lateinit var client: AgentDataGatewayUploadClient

    private val artifact = """{"schema":"healthmd.health_data","schema_version":4}""".encodeToByteArray()

    private fun manifest(): AgentDataIngestManifest =
        AgentDataIngestManifestBuilder.dailyHealthData(
            ownerDate = LocalDate.of(2026, 3, 15),
            artifactBytes = artifact,
        )

    private fun acceptReceipt(): String =
        """
        {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"accepted",
         "stored":{"revision_id":"${AgentDataIngestManifestBuilder.sha256Hex(artifact)}",
                   "byte_count":${artifact.size},"completeness":{"type":"complete"}},
         "partition":{"owner_date":"2026-03-15",
                      "authoritative":{"revision_id":"${AgentDataIngestManifestBuilder.sha256Hex(artifact)}",
                                       "completeness":{"type":"complete"}},
                      "complete_revision_present":true,"partial_revision_present":false}}
        """.trimIndent()

    private fun rejectReceipt(code: String): String =
        """
        {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"rejected",
         "rejection":{"code":"$code"}}
        """.trimIndent()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        // Zero backoff keeps the retry tests fast; attempts remain bounded by maxAttempts.
        client = AgentDataGatewayUploadClient(
            client = OkHttpClient(),
            maxAttempts = 3,
            backoffMillis = { 0 },
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun acceptedUploadSendsTheFrozenFramingAndParsesTheFixtureGrammarReceipt() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(acceptReceipt()))

        val receipt = client.upload(server.url("/").toString(), manifest(), artifact)

        assertThat(receipt).isInstanceOf(AgentDataUploadReceipt.Accepted::class.java)
        assertThat((receipt as AgentDataUploadReceipt.Accepted).revisionId)
            .isEqualTo(AgentDataIngestManifestBuilder.sha256Hex(artifact))

        val recorded = server.takeRequest()
        assertThat(recorded.method).isEqualTo("POST")
        assertThat(recorded.path).isEqualTo("/v1/ingest")
        assertThat(recorded.getHeader("Content-Type"))
            .isEqualTo(AgentDataGatewayUploadClient.INGEST_MEDIA_TYPE_VALUE)
        assertThat(recorded.getHeader("Content-Length")!!.toLong())
            .isEqualTo(recorded.bodySize)

        // Framing: one \n-terminated manifest line followed immediately by the exact bytes.
        val body = recorded.body.readByteArray()
        val newline = body.indexOf('\n'.code.toByte())
        assertThat(newline).isAtLeast(0)
        val manifestLine = body.copyOfRange(0, newline)
        val artifactBytes = body.copyOfRange(newline + 1, body.size)
        assertThat(manifestLine.decodeToString()).isEqualTo(manifest().encodeJsonLine())
        assertThat(artifactBytes).isEqualTo(artifact)
        assertThat(body.size.toLong()).isEqualTo(recorded.getHeader("Content-Length")!!.toLong())
    }

    @Test
    fun ingestPathIsAppendedToTheConfiguredBasePath() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(acceptReceipt()))

        client.upload(server.url("/gateway/base").toString(), manifest(), artifact)

        assertThat(server.takeRequest().path).isEqualTo("/gateway/base/v1/ingest")
    }

    @Test
    fun fixAndReuploadCodesAreNeverRetried() = runTest {
        for (code in listOf("truncated", "checksum_invalid", "manifest_incomplete")) {
            server.enqueue(MockResponse().setResponseCode(200).setBody(rejectReceipt(code)))

            val receipt = client.upload(server.url("/").toString(), manifest(), artifact)

            assertThat(receipt).isInstanceOf(AgentDataUploadReceipt.Rejected::class.java)
            assertThat((receipt as AgentDataUploadReceipt.Rejected).code).isEqualTo(code)
            assertThat(server.requestCount).isEqualTo(1)
            server.takeRequest()
        }
    }

    @Test
    fun transientReceiptIsRetriedUntilAccepted() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(rejectReceipt("transient")))
        server.enqueue(MockResponse().setResponseCode(200).setBody(acceptReceipt()))

        val receipt = client.upload(server.url("/").toString(), manifest(), artifact)

        assertThat(receipt).isInstanceOf(AgentDataUploadReceipt.Accepted::class.java)
        assertThat(server.requestCount).isEqualTo(2)
    }

    @Test
    fun transientReceiptExhaustingTheBudgetSurfacesTheRejection() = runTest {
        repeat(3) {
            server.enqueue(MockResponse().setResponseCode(200).setBody(rejectReceipt("transient")))
        }

        val receipt = client.upload(server.url("/").toString(), manifest(), artifact)

        assertThat(receipt).isInstanceOf(AgentDataUploadReceipt.Rejected::class.java)
        assertThat((receipt as AgentDataUploadReceipt.Rejected).code).isEqualTo("transient")
        assertThat(server.requestCount).isEqualTo(3)
    }

    @Test
    fun transportFailuresAreRetriedWithBoundedAttempts() = runTest {
        // A truncated body (connection closed early) is the receipt-less retryable class;
        // SocketPolicy.DISCONNECT_AT_START drops the connection entirely.
        server.enqueue(MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AT_START))
        server.enqueue(MockResponse().setResponseCode(200).setBody(acceptReceipt()))

        val receipt = client.upload(server.url("/").toString(), manifest(), artifact)

        assertThat(receipt).isInstanceOf(AgentDataUploadReceipt.Accepted::class.java)
        assertThat(server.requestCount).isEqualTo(2)
    }

    @Test
    fun exhaustedTransportRetriesThrowARetryableHealthFreeError() = runTest {
        repeat(3) {
            server.enqueue(
                MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AT_START),
            )
        }

        val error = runCatching {
            client.upload(server.url("/").toString(), manifest(), artifact)
        }.exceptionOrNull()

        assertThat(error).isInstanceOf(AgentDataGatewayException::class.java)
        assertThat((error as AgentDataGatewayException).retryable).isTrue()
        assertThat(error.message).isEqualTo("Could not reach the Agent Data gateway.")
    }

    @Test
    fun nonReceiptHttpStatusCodesFailWithoutRetryingUnlessRetryable() = runTest {
        // 404 is a terminal transport-level error (wrong path): no receipt, no retry.
        server.enqueue(MockResponse().setResponseCode(404).setBody("{}"))
        val notFound = runCatching {
            client.upload(server.url("/").toString(), manifest(), artifact)
        }.exceptionOrNull() as AgentDataGatewayException
        assertThat(notFound.retryable).isFalse()
        assertThat(server.requestCount).isEqualTo(1)

        // 503 is retryable and bounded.
        repeat(3) { server.enqueue(MockResponse().setResponseCode(503).setBody("{}")) }
        val unavailable = runCatching {
            client.upload(server.url("/").toString(), manifest(), artifact)
        }.exceptionOrNull() as AgentDataGatewayException
        assertThat(unavailable.retryable).isTrue()
        assertThat(server.requestCount).isEqualTo(4)
    }

    @Test
    fun malformedReceiptsFailClosedWithoutRetrying() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("not json"))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"outcome":"accepted"}"""))
        server.enqueue(
            MockResponse().setResponseCode(200)
                .setBody(rejectReceipt("invented_code")),
        )

        repeat(3) {
            val error = runCatching {
                client.upload(server.url("/").toString(), manifest(), artifact)
            }.exceptionOrNull()
            assertThat(error).isInstanceOf(AgentDataGatewayException::class.java)
            assertThat((error as AgentDataGatewayException).retryable).isFalse()
            assertThat(error.message).isEqualTo("The Agent Data gateway returned an invalid receipt.")
        }
        assertThat(server.requestCount).isEqualTo(3)
    }

    @Test
    fun unconfiguredEndpointFailsClosedBeforeAnyRequest() = runTest {
        val error = runCatching {
            client.upload("not a url", manifest(), artifact)
        }.exceptionOrNull()

        assertThat(error).isInstanceOf(AgentDataGatewayException::class.java)
        assertThat((error as AgentDataGatewayException).retryable).isFalse()
        assertThat(server.requestCount).isEqualTo(0)
    }
}
