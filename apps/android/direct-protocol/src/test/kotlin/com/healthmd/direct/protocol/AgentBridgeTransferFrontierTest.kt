package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.util.Base64
import kotlinx.serialization.json.*
import org.junit.Assert.assertThrows
import org.junit.Test

class AgentBridgeTransferFrontierTest {
    private val cases by lazy { Json.parseToJsonElement(requireNotNull(javaClass.getResource("/transfer-frontier-v1.json")).readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject } }
    private fun start(seed: JsonObject) = AgentBridgeTransferFrontier.start(seed.getValue("job_id").jsonPrimitive.content,
        seed.getValue("request_sha256").jsonPrimitive.content, seed.getValue("manifest_sha256").jsonPrimitive.content, seed.getValue("session_id").jsonPrimitive.content)
    private fun row(raw: ByteArray) = AgentBridgeTransferFrontierPartition.decode(raw)
    @Test fun independentFrontierVectorsAndRawNegatives() {
        assertThat(cases.size).isGreaterThan(30)
        for (case in cases) {
            try {
                var frontier = start(case.getValue("seed").jsonObject)
                val actual = mutableListOf(frontier.sha256)
                val raw = case["raw_partitions_base64"]?.jsonArray?.map { Base64.getDecoder().decode(it.jsonPrimitive.content) }
                    ?: case.getValue("partitions").jsonArray.map { it.toString().toByteArray() }
                for (bytes in raw) { frontier = frontier.appending(row(bytes)); actual += frontier.sha256 }
                assertThat(case.getValue("expected").jsonPrimitive.content).isEqualTo("valid")
                assertThat(actual).containsExactlyElementsIn(case.getValue("prefix_sha256").jsonArray.map { it.jsonPrimitive.content }).inOrder()
                assertThat(frontier.committedPartitionCount).isEqualTo(raw.size.toLong())
                case.getValue("canonical_base64").jsonArray.zip(actual).forEach { (encoded, digest) ->
                    assertThat(AgentBridgeCodec.sha256(Base64.getDecoder().decode(encoded.jsonPrimitive.content))).isEqualTo(digest)
                }
            } catch (error: AgentBridgeException) {
                com.google.common.truth.Truth.assertWithMessage(case.getValue("id").jsonPrimitive.content).that(error.message).isEqualTo(case.getValue("expected").jsonPrimitive.content)
                assertThat(error.cause).isNull()
            }
        }
    }
    @Test fun computedPrefixIsImmutableAndRejectsDuplicateOrSkippedIndex() {
        val case = cases.single { it.getValue("id").jsonPrimitive.content == "two-artifacts" }
        val original = start(case.getValue("seed").jsonObject)
        val rows = case.getValue("partitions").jsonArray.map { row(it.toString().toByteArray()) }
        val next = original.appending(rows[0])
        assertThat(original.committedPartitionCount).isEqualTo(0L)
        assertThat(next.committedPartitionCount).isEqualTo(1L)
        assertThat(assertThrows(AgentBridgeException::class.java) { next.appending(rows[0]) }.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED)
        assertThat(assertThrows(AgentBridgeException::class.java) { original.appending(rows[1]) }.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED)
        assertThat(next.appending(rows[1]).sha256).isEqualTo(case.getValue("prefix_sha256").jsonArray.last().jsonPrimitive.content)
    }
    @Test fun internalCounterBoundsCannotOverflowPublicReceiptCount() {
        val case = cases.single { it.getValue("id").jsonPrimitive.content == "one-partition" }
        val original = start(case.getValue("seed").jsonObject)
        val partition = row(case.getValue("partitions").jsonArray[0].toString().toByteArray())
        for (count in listOf(-1L, 2_147_483_647L, Long.MAX_VALUE)) {
            assertThat(assertThrows(AgentBridgeException::class.java) { AgentBridgeTransferFrontierHash.step(original.sha256, count, partition) }.code).isEqualTo(AgentBridgeErrorCode.INVALID_REQUEST)
        }
    }
}
