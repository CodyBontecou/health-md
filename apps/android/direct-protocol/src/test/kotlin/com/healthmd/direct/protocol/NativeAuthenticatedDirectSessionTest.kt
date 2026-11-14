package com.healthmd.direct.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.Base64
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

/** Actual native connect/crypto/packet/channel paths against synthetic isolated loopback only. */
class NativeAuthenticatedDirectSessionTest {
    @Test
    fun authenticatedReconnectProducesExactChannelCredentialProvenance() {
        SyntheticSessionListener().use { server ->
            val client = server.connect()
            client.channel.use { channel ->
                val proof = requireNotNull(channel.nativeAuthenticatedSession())
                client.listener.reconnectSecret.fill(0) // Caller receives no mutable backing fingerprint.
                assertTrue(proof.matches(channel, SOURCE, HOST, SECRET))
                channel.sendNegotiationHello(SOURCE)
                assertEquals(HOST, channel.receiveNegotiationHello().installationId)
                assertEquals("NativeAuthenticatedDirectSession(redacted)", proof.toString())
                assertFalse(proof is java.io.Serializable)
            }
            server.await()
        }
    }

    @Test
    fun localLegacyFailureRevokesOnlyProvenanceWithoutChangingSocketOrSequence() {
        SyntheticSessionListener(afterHello = { socket, key ->
            val next = DirectCrypto.open(LegacyCodec.encryptedFrame(SyntheticSessionListener.read(DataInputStream(socket.getInputStream()))), key)
            // Deployed send allocates seq1 before the oversized outer packet fails locally.
            assertEquals(2L, ByteBuffer.wrap(next, 8, 8).long)
            assertEquals(SOURCE, LegacyCodec.parseHello(next.copyOfRange(16, next.size)).installationId)
            SyntheticSessionListener.write(DataOutputStream(socket.getOutputStream()), SyntheticSessionListener.encrypted(1,
                V2Codec.encode("pong", JsonObject.serializer(), buildJsonObject {}), key))
        }).use { server ->
            val client = server.connect()
            client.channel.use { channel ->
                val proof = requireNotNull(channel.nativeAuthenticatedSession())
                channel.sendNegotiationHello(SOURCE)
                channel.receiveNegotiationHello()
                val failure = runCatching { channel.sendBinary("HMDDIRCT".toByteArray() + ByteArray(MAXIMUM_PACKET_BYTES)) }.exceptionOrNull()
                assertTrue(failure is IllegalArgumentException)
                assertEquals("Invalid direct packet size.", failure?.message)
                assertFalse(proof.matches(channel, SOURCE, HOST, SECRET))
                assertNull(channel.nativeAuthenticatedSession())
                channel.sendNegotiationHello(SOURCE)
                assertEquals("pong", channel.receiveV2().type)
            }
            server.await()
        }
    }

    @Test
    fun callerCredentialMutationPreservesLegacyHandshakeRejectionAndCannotEmitProvenance() {
        val callerSecret = SECRET.copyOf()
        SyntheticSessionListener(fault = "caller-mutated", beforeResponse = { callerSecret.fill(0) }).use { server ->
            val result = runCatching { server.connect(trustedSecret = callerSecret) }
            result.getOrNull()?.channel?.close() // Control cleanup only, never a new production close.
            val failure = result.exceptionOrNull()
            assertTrue(failure is IllegalArgumentException)
            assertEquals("The paired CLI credential changed.", failure?.message)
            server.await()
        }
    }

    @Test
    fun selectorTwoAndSharedThreePairingProvenanceIsDefensiveAndNotBaseAdmission() {
        for (selector in listOf(2, 3)) SyntheticSessionListener(selector).use { server ->
            val client = server.connect(pairing = true)
            client.channel.use { channel ->
                val proof = requireNotNull(channel.nativeAuthenticatedSession())
                val original = client.listener.reconnectSecret.copyOf()
                client.listener.reconnectSecret.fill(0)
                assertTrue(proof.matches(channel, SOURCE, HOST, original))
                assertFalse(proof.matches(channel, SOURCE, HOST, client.listener.reconnectSecret))
                channel.sendNegotiationHello(SOURCE); channel.receiveNegotiationHello()
            }
            server.await()
        }
    }

    @Test
    fun rejectedBadCodeProofIdentityCredentialLengthAndSelectorCannotReturnProvenance() {
        for (fault in listOf("rejected", "proof", "identity", "credential", "short", "selector")) {
            SyntheticSessionListener(fault = fault).use { server ->
                assertNotNull(runCatching { server.connect() }.exceptionOrNull())
                server.await()
            }
        }
        for (selector in listOf(2, 3)) SyntheticSessionListener(selector).use { server ->
            assertTrue(runCatching { server.connect(pairing = true, code = "00000000000000000000") }.exceptionOrNull() is PairingRejectedException)
            server.await()
        }
    }

    @Test
    fun ordinaryConstructedChannelAndWrongIdentityOrCredentialBindingsCannotReuseProof() {
        ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { raw ->
            val ordinary = DirectSecureChannel(DirectPacketConnection.connect("127.0.0.1", raw.localPort, 1000), ByteArray(32), HOST, "Synthetic CLI")
            raw.accept().use { ordinary.use { unproven ->
                assertNull(unproven.nativeAuthenticatedSession())
                SyntheticSessionListener().use { server ->
                    val client = server.connect()
                    client.channel.use { channel ->
                        val proof = requireNotNull(channel.nativeAuthenticatedSession())
                        assertFalse(proof.matches(unproven, SOURCE, HOST, SECRET))
                        assertFalse(proof.matches(channel, HOST, HOST, SECRET))
                        assertFalse(proof.matches(channel, SOURCE, SOURCE, SECRET))
                        assertFalse(proof.matches(channel, SOURCE, HOST, ByteArray(31)))
                        assertFalse(proof.matches(channel, SOURCE, HOST, ByteArray(32)))
                        assertTrue(proof.matches(channel, SOURCE, HOST, SECRET))
                        channel.sendNegotiationHello(SOURCE); channel.receiveNegotiationHello()
                    }
                    server.await()
                }
            } }
        }
    }

    @Test
    fun closedProofCannotReviveOrBindAnotherSameIdentityAuthenticatedChannel() {
        lateinit var old: DirectSecureChannel
        lateinit var proof: NativeAuthenticatedDirectSession
        SyntheticSessionListener().use { server ->
            old = server.connect().channel
            proof = requireNotNull(old.nativeAuthenticatedSession())
            old.sendNegotiationHello(SOURCE); old.receiveNegotiationHello(); old.close()
            assertFalse(proof.matches(old, SOURCE, HOST, SECRET)); assertNull(old.nativeAuthenticatedSession())
            server.await()
        }
        SyntheticSessionListener().use { server ->
            server.connect().channel.use { next ->
                assertFalse(proof.matches(next, SOURCE, HOST, SECRET))
                assertTrue(requireNotNull(next.nativeAuthenticatedSession()).matches(next, SOURCE, HOST, SECRET))
                assertFalse(proof.matches(old, SOURCE, HOST, SECRET))
                next.sendNegotiationHello(SOURCE); next.receiveNegotiationHello()
            }
            server.await()
        }
    }

    @Test
    fun observedEofCryptoReplayEnvelopeAndDecodeFailuresPermanentlyRevokeOnlyNewProof() {
        for (failure in listOf("eof", "crypto", "replay", "magic", "decode")) {
            SyntheticSessionListener(afterHello = { socket, key ->
                if (failure != "eof") {
                    val bytes = if (failure == "decode") "{}".toByteArray() else V2Codec.encode("pong", JsonObject.serializer(), buildJsonObject {})
                    val frame = if (failure == "magic") LegacyCodec.encrypted(DirectCrypto.seal(ByteArray(16), key))
                        else SyntheticSessionListener.encrypted(if (failure == "replay") 0 else 1, bytes, if (failure == "crypto") ByteArray(32) else key)
                    SyntheticSessionListener.write(DataOutputStream(socket.getOutputStream()), frame)
                }
            }).use { server ->
                server.connect().channel.use { channel ->
                    val proof = requireNotNull(channel.nativeAuthenticatedSession())
                    channel.sendNegotiationHello(SOURCE); channel.receiveNegotiationHello()
                    assertNotNull(runCatching { channel.receiveV2() }.exceptionOrNull())
                    assertNull(channel.nativeAuthenticatedSession()); assertFalse(proof.matches(channel, SOURCE, HOST, SECRET))
                }
                server.await()
            }
        }
    }

    @Test
    fun pollTimeoutIsNotObservedTerminalFailureOrRemoteClosureClaim() {
        val release = java.util.concurrent.CountDownLatch(1)
        SyntheticSessionListener(afterHello = { _, _ -> release.await(5, TimeUnit.SECONDS) }).use { server ->
            server.connect().channel.use { channel ->
                val proof = requireNotNull(channel.nativeAuthenticatedSession())
                channel.sendNegotiationHello(SOURCE); channel.receiveNegotiationHello()
                assertNull(channel.pollV2(25))
                assertTrue(proof.matches(channel, SOURCE, HOST, SECRET))
                release.countDown()
                assertNotNull(runCatching { channel.receive() }.exceptionOrNull())
                assertFalse(proof.matches(channel, SOURCE, HOST, SECRET))
            }
            server.await()
        }
    }

    @Test
    fun legacyDecodeFailureKeepsNextReceiveSequenceAndSocketWhileProofStaysRevoked() {
        SyntheticSessionListener(afterHello = { socket, key ->
            val output = DataOutputStream(socket.getOutputStream())
            SyntheticSessionListener.write(output, SyntheticSessionListener.encrypted(1, "{}".toByteArray(), key))
            SyntheticSessionListener.write(output, SyntheticSessionListener.encrypted(2,
                V2Codec.encode("pong", JsonObject.serializer(), buildJsonObject {}), key))
        }).use { server ->
            server.connect().channel.use { channel ->
                val proof = requireNotNull(channel.nativeAuthenticatedSession())
                channel.sendNegotiationHello(SOURCE); channel.receiveNegotiationHello()
                assertNotNull(runCatching { channel.receiveV2() }.exceptionOrNull())
                assertEquals("pong", channel.receiveV2().type)
                assertFalse(proof.matches(channel, SOURCE, HOST, SECRET)); assertNull(channel.nativeAuthenticatedSession())
            }
            server.await()
        }
    }

    companion object {
        const val SOURCE = "00000000-0000-4000-8000-000000000001"
        const val HOST = "00000000-0000-4000-8000-000000000002"
        val SECRET = ByteArray(32) { 0x29 }
        const val CODE = "12345678901234567890"
    }
}

/** Literal legacy listener role; independent response construction, real proofs and encrypted sequences. */
private class SyntheticSessionListener(
    private val selector: Int = 2,
    private val fault: String = "none",
    private val beforeResponse: () -> Unit = {},
    private val afterHello: (Socket, ByteArray) -> Unit = { _, _ -> },
) : AutoCloseable {
    private val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).apply { soTimeout = 5000 }
    private val done = CompletableFuture<Unit>()
    private var accepted: Socket? = null
    init {
        Thread {
            try {
                server.accept().use { socket ->
                    accepted = socket
                    socket.soTimeout = 5000
                    val input = DataInputStream(socket.getInputStream())
                    val output = DataOutputStream(socket.getOutputStream())
                    val request = DirectJson.json.parseToJsonElement(read(input).decodeToString()).jsonObject
                        .getValue("pairingRequest").jsonObject.getValue("_0").jsonObject
                    val source = request.getValue("clientInstallationID").jsonPrimitive.content.lowercase()
                    val pub = unbase(request, "clientPublicKey")
                    val nonce = unbase(request, "clientNonce")
                    val trusted = request["trustedVerifier"] != null
                    val expected = if (trusted) DirectCrypto.trustedClientVerifier(SECRET, source, pub, nonce)
                        else if (selector == 3) DirectCrypto.sharedPairingVerifier(CODE, source, pub, nonce)
                        else DirectCrypto.androidPairingVerifier(CODE, source, pub, nonce)
                    assertEquals(selector, request.getValue("protocolVersion").jsonPrimitive.int)
                    if (fault == "rejected" || !expected.contentEquals(unbase(request, if (trusted) "trustedVerifier" else "codeVerifier"))) {
                        write(output, "{\"pairingRejected\":{\"_0\":{\"reason\":\"synthetic rejection\"}}}".toByteArray())
                    } else {
                        beforeResponse()
                        val keys = DirectCrypto.ephemeralKeyPair()
                        val serverNonce = DirectCrypto.randomBytes(32)
                        val session = DirectCrypto.sessionKey(DirectCrypto.sharedSecret(keys.privateKey, pub), nonce, serverNonce)
                        val host = if (fault == "identity") SOURCE else HOST
                        val credential = if (fault == "credential") ByteArray(32) { 0x30 } else if (fault == "short") ByteArray(31) else SECRET
                        val sealed = DirectCrypto.seal(credential, session)
                        val proof = if (trusted) DirectCrypto.trustedServerVerifier(SECRET, source, pub, nonce, host, keys.publicKey, serverNonce)
                            else if (selector == 3) DirectCrypto.sharedPairingServerVerifier(CODE, source, pub, nonce, host, keys.publicKey, serverNonce, sealed)
                            else DirectCrypto.androidPairingServerVerifier(CODE, source, pub, nonce, host, keys.publicKey, serverNonce, sealed)
                        if (fault == "proof") proof[0] = (proof[0].toInt() xor 1).toByte()
                        write(output, DirectJson.canonicalBytes(buildJsonObject {
                            put("pairingResponse", buildJsonObject { put("_0", buildJsonObject {
                                put("protocolVersion", if (fault == "selector") 3 else selector); put("macName", "Synthetic CLI")
                                put("macInstallationID", host.uppercase()); put("serverPublicKey", base(keys.publicKey))
                                put("serverNonce", base(serverNonce)); put("authenticationVerifier", base(proof))
                                put("sealedReconnectSecret", buildJsonObject { put("nonce", base(sealed.nonce)); put("ciphertext", base(sealed.ciphertext)); put("tag", base(sealed.tag)) })
                            }) })
                        }))
                        if (fault == "none") {
                            val hello = DirectCrypto.open(LegacyCodec.encryptedFrame(read(input)), session)
                            assertEquals(0L, ByteBuffer.wrap(hello, 8, 8).long)
                            val nativeHello = LegacyCodec.parseHello(hello.copyOfRange(16, hello.size))
                            assertEquals(listOf(2), nativeHello.protocolVersions)
                            assertEquals("android", nativeHello.platform)
                            assertEquals(SOURCE, nativeHello.installationId)
                            write(output, encrypted(0, LegacyCodec.hello(NegotiationHello(
                                protocolVersions = listOf(1, 2), platform = "macos_cli", installationId = HOST,
                                supportedRawProfiles = emptyList(), supportsDurableJobs = true,
                                supportsCanonicalExtraction = false, transfer = TransferCapabilities(),
                            )), session))
                            afterHello(socket, session)
                        }
                    }
                }
                done.complete(Unit)
            } catch (error: Throwable) { done.completeExceptionally(error) }
        }.apply { isDaemon = true; name = "synthetic-native-session" }.start()
    }
    fun connect(pairing: Boolean = false, code: String = CODE, trustedSecret: ByteArray = SECRET.copyOf()) = DirectClient.connect(
        "127.0.0.1", server.localPort, 5000, SOURCE, "Synthetic Android",
        pairingCode = if (pairing) code else null, pairingProtocolVersion = selector,
        trustedListener = if (pairing) null else TrustedListener(HOST, "Synthetic CLI", trustedSecret, "127.0.0.1", server.localPort),
    )
    fun await() { done.get(5, TimeUnit.SECONDS) }
    override fun close() { accepted?.close(); server.close() }
    companion object {
        private val SOURCE = NativeAuthenticatedDirectSessionTest.SOURCE
        private val HOST = NativeAuthenticatedDirectSessionTest.HOST
        private val SECRET = NativeAuthenticatedDirectSessionTest.SECRET
        private val CODE = NativeAuthenticatedDirectSessionTest.CODE
        fun base(b: ByteArray) = Base64.getEncoder().encodeToString(b)
        fun unbase(j: JsonObject, name: String) = Base64.getDecoder().decode(j.getValue(name).jsonPrimitive.content)
        fun read(input: DataInputStream): ByteArray { val size = input.readLong(); require(size in 1..MAXIMUM_PACKET_BYTES); return ByteArray(size.toInt()).also(input::readFully) }
        fun write(output: DataOutputStream, bytes: ByteArray) { output.writeLong(bytes.size.toLong()); output.write(bytes); output.flush() }
        fun encrypted(sequence: Long, bytes: ByteArray, key: ByteArray) = LegacyCodec.encrypted(DirectCrypto.seal(
            ByteBuffer.allocate(16 + bytes.size).put("HMDSC001".toByteArray()).putLong(sequence).put(bytes).array(), key))
    }
}
