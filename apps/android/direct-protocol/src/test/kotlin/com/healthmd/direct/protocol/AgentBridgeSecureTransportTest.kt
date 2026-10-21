package com.healthmd.direct.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

/** Actual native socket/framing/AEAD/sequence paths with a synthetic peer and native callback.
 * No pairing, device, native consent or installed source qualification is inferred. */
class AgentBridgeSecureTransportTest {
    private fun negotiation(versions: List<Int> = listOf(2, 4)) = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, versions, versions)
    private fun message() = AgentBridgeMessage("discovery_request", AgentBridgeDiscoveryRequest(
        AgentBridgePeer(sourceInstallationId = "00000000-0000-4000-8000-000000000001", hostInstallationId = "00000000-0000-4000-8000-000000000002", platform = AgentBridgePlatform.ANDROID),
        "00000000-0000-4000-8000-000000000064", "healthmd.agent_discovery_request", 1))

    @Test fun actualSocketsMixBridgeAndBaseWithUnchangedSequence() {
        WirePair().use { pair ->
            val expected = message(); val neg = negotiation(); var checks = 0
            pair.channel.sendAgentBridge(expected, neg) { checks++ }
            val first = pair.read()
            assertEquals(0L, first.first)
            assertEquals(expected, AgentBridgeCodec.decodeEnvelope(first.second, neg))
            pair.channel.sendV2("ping", JsonObject.serializer(), buildJsonObject {})
            val second = pair.read()
            assertEquals(1L, second.first)
            assertEquals("ping", V2Codec.decode(second.second).type)
            pair.write(0, AgentBridgeCodec.encodeEnvelope(expected, neg))
            assertEquals(expected, (pair.channel.receiveAllowingAgentBridge(neg) { checks++ } as ReceivedAgentBridgePayload.Agent).message)
            pair.write(1, V2Codec.encode("pong", JsonObject.serializer(), buildJsonObject {}))
            assertEquals("pong", (pair.channel.receiveAllowingAgentBridge(neg) { checks++ } as ReceivedAgentBridgePayload.Base).envelope.type)
            assertTrue(checks >= 8)
            assertNull(pair.channel.nativeAuthenticatedSession())
        }
    }
    @Test fun unnegotiatedBridgeCannotProbeOrConsumeNativeIO() {
        WirePair().use { pair ->
            var checks = 0
            rejected { pair.channel.sendAgentBridge(message(), negotiation(listOf(2))) { checks++ } }
            rejected { pair.channel.receiveAllowingAgentBridge(negotiation(listOf(2))) { checks++ } }
            assertEquals(0, checks)
            pair.channel.sendV2("ping", JsonObject.serializer(), buildJsonObject {})
            assertEquals(0L, pair.read().first) // No bridge sequence consumed.
        }
    }
    @Test fun revocationAfterFirstBoundedWriteClosesPartialPacketWithoutRetry() {
        WirePair().use { pair ->
            var checks = 0
            val bytes = ByteArray(96 * 1024) { 0x7a }
            rejected { pair.packet.sendGuarded(bytes) { checks++; if (checks == 3) error("revoked") } }
            val received = pair.server.getInputStream().readBytes()
            assertEquals(3, checks)
            assertTrue(received.size <= 16 * 1024)
            assertTrue(received.size < bytes.size + 8)
        }
    }
    @Test fun returnSideRevocationAbandonsBridgeEvenIfCallerRestoresPolicy() {
        WirePair().use { pair ->
            val neg = negotiation()
            pair.write(0, AgentBridgeCodec.encodeEnvelope(message(), neg))
            var checks = 0
            rejected { pair.channel.receiveAllowingAgentBridge(neg) { checks++; if (checks == 2) error("revoked") } }
            assertEquals(2, checks)
            var restoredChecks = 0
            rejected { pair.channel.sendAgentBridge(message(), neg) { restoredChecks++ } }
            assertEquals(0, restoredChecks)
        }
    }
    @Test fun malformedV4CannotFallThroughBaseDecoder() {
        for (raw in listOf(
            """{"protocol_version":4,"type":"ping","payload":{}}""",
            """{"protocol_version":4,"protocol_version":2,"type":"ping","payload":{}}""",
            """{"protocol_version":"2","type":"ping","payload":{}}""",
        )) WirePair().use { pair ->
            pair.write(0, raw.toByteArray())
            var checks = 0
            rejected { pair.channel.receiveAllowingAgentBridge(negotiation()) { checks++ } }
            assertEquals(1, checks)
            rejected { pair.channel.sendAgentBridge(message(), negotiation()) { checks++ } }
            assertEquals(1, checks)
        }
    }
    @Test fun authenticatedReplaySequenceStillRejects() {
        WirePair().use { pair ->
            val neg = negotiation(); val expected = message(); val bytes = AgentBridgeCodec.encodeEnvelope(expected, neg)
            pair.write(0, bytes)
            assertEquals(expected, (pair.channel.receiveAllowingAgentBridge(neg) {} as ReceivedAgentBridgePayload.Agent).message)
            pair.write(0, bytes)
            rejected { pair.channel.receiveAllowingAgentBridge(neg) {} }
        }
    }
    @Test fun nativeCloseInterruptsPendingReceiveAndCannotRevive() {
        WirePair().use { pair ->
            val entered = CountDownLatch(1)
            val executor = Executors.newSingleThreadExecutor()
            try {
                val task = executor.submit<Boolean> { runCatching { pair.channel.receiveAllowingAgentBridge(negotiation()) { entered.countDown() } }.isFailure }
                assertTrue(entered.await(5, TimeUnit.SECONDS))
                pair.channel.close()
                assertTrue(task.get(5, TimeUnit.SECONDS))
                rejected { pair.channel.receiveAllowingAgentBridge(negotiation()) {} }
            } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS)) }
        }
    }
    private fun rejected(block: () -> Unit) {
        var failed = false
        try { block() } catch (_: Exception) { failed = true }
        assertTrue("Expected native transport rejection", failed)
    }
    private class WirePair : AutoCloseable {
        private val listener = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).apply { soTimeout = 5_000 }
        val packet = try {
            DirectPacketConnection.connect(requireNotNull(listener.inetAddress.hostAddress), listener.localPort, 5_000)
        } catch (failure: Throwable) { listener.close(); throw failure }
        val server: Socket = try { listener.accept().apply { soTimeout = 5_000 } }
            catch (failure: Throwable) { packet.close(); listener.close(); throw failure }
        private val key = ByteArray(32) { 0x51 }
        val channel = DirectSecureChannel(packet, key, "00000000-0000-4000-8000-000000000002", "Synthetic host")
        private val input = DataInputStream(server.getInputStream())
        private val output = DataOutputStream(server.getOutputStream())
        fun read(): Pair<Long, ByteArray> {
            val size = input.readLong(); require(size in 1..MAXIMUM_PACKET_BYTES.toLong())
            val packet = ByteArray(size.toInt()).also(input::readFully)
            val plaintext = DirectCrypto.open(LegacyCodec.encryptedFrame(packet), key)
            assertEquals("HMDSC001", plaintext.copyOfRange(0, 8).decodeToString())
            return ByteBuffer.wrap(plaintext, 8, 8).long to plaintext.copyOfRange(16, plaintext.size)
        }
        fun write(sequence: Long, bytes: ByteArray) {
            val envelope = ByteBuffer.allocate(16 + bytes.size).put("HMDSC001".toByteArray()).putLong(sequence).put(bytes).array()
            val packet = LegacyCodec.encrypted(DirectCrypto.seal(envelope, key))
            output.writeLong(packet.size.toLong()); output.write(packet); output.flush()
        }
        override fun close() { channel.close(); server.close(); listener.close() }
    }
}
