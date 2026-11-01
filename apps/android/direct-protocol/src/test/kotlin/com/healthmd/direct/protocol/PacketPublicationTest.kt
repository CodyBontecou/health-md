package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.io.DataInputStream
import java.net.ServerSocket
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import org.junit.Assert.assertThrows
import org.junit.Test

class PacketPublicationTest {
    @Test
    fun supersededReceiveRevalidatesBeforePropagatingDisconnect() {
        receiveAfterDisconnect(revoke = true)
    }

    @Test
    fun currentReceivePreservesItsDisconnectError() {
        receiveAfterDisconnect(revoke = false)
    }

    private fun receiveAfterDisconnect(revoke: Boolean) {
        ServerSocket(0).use { server ->
            val packet = DirectPacketConnection.connect("127.0.0.1", server.localPort, 2_000)
            server.accept().use { peer ->
                val started = CountDownLatch(1)
                val revoked = java.util.concurrent.atomic.AtomicBoolean(false)
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val disconnect = executor.submit {
                        check(started.await(2, TimeUnit.SECONDS))
                        revoked.set(revoke)
                        peer.close()
                    }
                    DirectSecureChannel(packet, ByteArray(32), "listener", "Listener").use { channel ->
                        val checkOwnership = {
                            check(!revoked.get()) { "superseded" }
                            started.countDown()
                        }
                        if (revoke) {
                            val error = assertThrows(IllegalStateException::class.java) {
                                channel.receiveV2(checkOwnership)
                            }
                            assertThat(error.message).isEqualTo("superseded")
                        } else {
                            assertThrows(java.io.EOFException::class.java) {
                                channel.receiveV2(checkOwnership)
                            }
                        }
                    }
                    disconnect.get(2, TimeUnit.SECONDS)
                } finally {
                    packet.close()
                    executor.shutdownNow()
                }
            }
        }
    }

    @Test
    fun supersededReceiveDoesNotDeliverAValidReply() {
        ServerSocket(0).use { server ->
            val packet = DirectPacketConnection.connect("127.0.0.1", server.localPort, 2_000)
            server.accept().use { peer ->
                val started = CountDownLatch(1)
                val revoked = java.util.concurrent.atomic.AtomicBoolean(false)
                val executor = Executors.newSingleThreadExecutor()
                val key = ByteArray(32) { it.toByte() }
                try {
                    val reply = executor.submit {
                        check(started.await(2, TimeUnit.SECONDS))
                        val plaintext = V2Codec.encode("pong", JobPayload.serializer(), JobPayload("synthetic-job"))
                        val envelope = ByteBuffer.allocate(16 + plaintext.size)
                            .put("HMDSC001".toByteArray()).putLong(0).put(plaintext).array()
                        val encrypted = LegacyCodec.encrypted(DirectCrypto.seal(envelope, key))
                        revoked.set(true)
                        java.io.DataOutputStream(peer.getOutputStream()).apply {
                            writeLong(encrypted.size.toLong())
                            write(encrypted)
                            flush()
                        }
                    }
                    DirectSecureChannel(packet, key, "listener", "Listener").use { channel ->
                        val error = assertThrows(IllegalStateException::class.java) {
                            channel.receiveV2 {
                                check(!revoked.get()) { "superseded" }
                                started.countDown()
                            }
                        }
                        assertThat(error.message).isEqualTo("superseded")
                    }
                    reply.get(2, TimeUnit.SECONDS)
                } finally {
                    packet.close()
                    executor.shutdownNow()
                }
            }
        }
    }

    @Test
    fun artifactTransferRoutesCancellationThroughRevocationAuthorization() {
        val artifact = java.io.File.createTempFile("synthetic-cancel-transfer", ".json")
        artifact.writeText("{}")
        try {
            val jobId = "10000000-0000-4000-8000-000000000001"
            val artifactId = "20000000-0000-4000-8000-000000000002"
            val accepted = ExportAccepted(jobId, "2026-10-09T00:00:00Z", PeerBinding(
                "30000000-0000-4000-8000-000000000003", "40000000-0000-4000-8000-000000000004"),
                ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1, ResolvedRange("2026-10-08", "2026-10-08", "UTC"),
                providerId = "health_connect", requestFingerprint = "synthetic-fingerprint")
            val manifest = ArtifactManifest(jobId, artifactId, ArtifactKind.RAW_SNAPSHOT,
                ArtifactSchema("healthmd.raw-snapshot", 1), "application/json", artifact.length(),
                DirectJson.sha256Hex(artifact.readBytes()))
            val plan = TransferPlanBuilder.build(accepted, listOf(manifest), mapOf(artifactId to artifact),
                createdAt = "2026-10-09T00:00:00Z")
            ServerSocket(0).use { server ->
                val packet = DirectPacketConnection.connect("127.0.0.1", server.localPort, 2_000)
                server.accept().use { peer ->
                    peer.soTimeout = 5_000
                    val key = ByteArray(32) { it.toByte() }
                    val revoked = java.util.concurrent.atomic.AtomicBoolean(false)
                    val ordinary = java.util.concurrent.atomic.AtomicInteger(0)
                    val cancellation = java.util.concurrent.atomic.AtomicInteger(0)
                    val executor = Executors.newSingleThreadExecutor()
                    try {
                        val receiver = executor.submit {
                            val input = DataInputStream(peer.getInputStream())
                            var expectedSequence = 0L
                            fun receiveType(): String {
                                val bytes = ByteArray(input.readLong().toInt()).also(input::readFully)
                                val envelope = DirectCrypto.open(LegacyCodec.encryptedFrame(bytes), key)
                                assertThat(ByteBuffer.wrap(envelope, 8, 8).long).isEqualTo(expectedSequence++)
                                return V2Codec.decode(envelope.copyOfRange(16, envelope.size)).type
                            }
                            assertThat(receiveType()).isEqualTo("export_accepted")
                            assertThat(receiveType()).isEqualTo("transfer_session")
                            assertThat(receiveType()).isEqualTo("artifact_manifest")
                            assertThat(receiveType()).isEqualTo("transfer_open")
                            val plaintext = V2Codec.encode("cancel", JobPayload.serializer(), JobPayload(jobId))
                            val envelope = ByteBuffer.allocate(16 + plaintext.size)
                                .put("HMDSC001".toByteArray()).putLong(0).put(plaintext).array()
                            val bytes = LegacyCodec.encrypted(DirectCrypto.seal(envelope, key))
                            java.io.DataOutputStream(peer.getOutputStream()).apply {
                                writeLong(bytes.size.toLong()); write(bytes); flush()
                            }
                            assertThat(receiveType()).isEqualTo("cancel_acknowledged")
                            assertThat(revoked.get()).isTrue()
                        }
                        DirectSecureChannel(packet, key, "listener", "Listener").use { channel ->
                            val ordinaryAuthorization = DirectPacketSendAuthorization { enqueue ->
                                check(!revoked.get())
                                ordinary.incrementAndGet()
                                enqueue()
                            }
                            val cancelAuthorization = DirectPacketSendAuthorization { enqueue ->
                                check(revoked.compareAndSet(false, true))
                                cancellation.incrementAndGet()
                                enqueue()
                            }
                            assertThrows(DirectExportCancelledException::class.java) {
                                ArtifactTransferClient(channel, ordinaryAuthorization, cancelAuthorization)
                                    .transfer(plan, checkCancellation = { check(!revoked.get()) })
                            }
                            assertThat(ordinary.get()).isEqualTo(4)
                            assertThat(cancellation.get()).isEqualTo(1)
                        }
                        receiver.get(5, TimeUnit.SECONDS)
                    } finally {
                        packet.close()
                        executor.shutdownNow()
                    }
                }
            }
        } finally { artifact.delete() }
    }

    @Test
    fun revokedAuthorizationDoesNotConsumeSecureSequence() {
        ServerSocket(0).use { server ->
            val packet = DirectPacketConnection.connect("127.0.0.1", server.localPort, 2_000)
            server.accept().use { peer ->
                peer.soTimeout = 2_000
                val key = ByteArray(32) { it.toByte() }
                DirectSecureChannel(packet, key, "listener", "Listener").use { channel ->
                    val revoked = DirectPacketSendAuthorization { error("revoked") }
                    assertThrows(IllegalStateException::class.java) {
                        channel.sendV2("ping", JobPayload.serializer(), JobPayload("synthetic-job"), revoked)
                    }
                    var admitted = false
                    channel.sendV2("ping", JobPayload.serializer(), JobPayload("synthetic-job"),
                        DirectPacketSendAuthorization { enqueue ->
                            admitted = true
                            enqueue()
                        })
                    assertThat(admitted).isTrue()
                    val input = DataInputStream(peer.getInputStream())
                    val bytes = ByteArray(input.readLong().toInt()).also(input::readFully)
                    val envelope = DirectCrypto.open(LegacyCodec.encryptedFrame(bytes), key)
                    assertThat(ByteBuffer.wrap(envelope, 8, 8).long).isEqualTo(0L)
                    assertThat(V2Codec.decode(envelope.copyOfRange(16, envelope.size)).type).isEqualTo("ping")
                }
            }
        }
    }

    @Test
    fun ownershipIsReleasedBeforeBlockedSocketPublicationCompletes() {
        val ownerLock = ReentrantLock()
        val enqueued = CountDownLatch(1)
        val writeStarted = CountDownLatch(1)
        val releaseWrite = CountDownLatch(1)
        val published = java.io.ByteArrayOutputStream()
        // A loopback kernel may buffer the entire maximum packet before the peer
        // reads it. Hold the socket output boundary explicitly so this assertion
        // measures publication ownership independently of OS buffer sizes.
        val socket = object : java.net.Socket() {
            override fun getInputStream() = java.io.ByteArrayInputStream(byteArrayOf())
            override fun getOutputStream() = object : java.io.OutputStream() {
                override fun write(value: Int) = write(byteArrayOf(value.toByte()), 0, 1)
                override fun write(bytes: ByteArray, offset: Int, length: Int) {
                    writeStarted.countDown()
                    check(releaseWrite.await(5, TimeUnit.SECONDS)) { "Publication was not released" }
                    published.write(bytes, offset, length)
                }
            }
            override fun close() { releaseWrite.countDown() }
        }
        val packet = DirectPacketConnection(socket, 2_000)
        val executor = Executors.newSingleThreadExecutor()
        val payload = ByteArray(MAXIMUM_PACKET_BYTES) { (it % 251).toByte() }
        try {
            val authorization = DirectPacketSendAuthorization { enqueue ->
                ownerLock.withLock {
                    enqueue()
                    enqueued.countDown()
                }
            }
            val send = executor.submit {
                packet.send(authorization) {
                    check(ownerLock.isHeldByCurrentThread)
                    payload
                }
            }
            assertThat(enqueued.await(2, TimeUnit.SECONDS)).isTrue()
            assertThat(writeStarted.await(2, TimeUnit.SECONDS)).isTrue()
            assertThat(ownerLock.tryLock(2, TimeUnit.SECONDS)).isTrue()
            ownerLock.unlock()
            assertThat(send.isDone).isFalse()
            releaseWrite.countDown()
            send.get(5, TimeUnit.SECONDS)
            val input = DataInputStream(java.io.ByteArrayInputStream(published.toByteArray()))
            assertThat(input.readLong()).isEqualTo(payload.size.toLong())
            val received = ByteArray(payload.size).also(input::readFully)
            assertThat(received).isEqualTo(payload)
            assertThat(input.read()).isEqualTo(-1)
        } finally {
            releaseWrite.countDown()
            packet.close()
            executor.shutdownNow()
        }
    }
}
