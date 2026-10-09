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
        ServerSocket().use { server ->
            server.receiveBufferSize = 16 * 1024
            server.bind(java.net.InetSocketAddress("127.0.0.1", 0))
            val packet = DirectPacketConnection.connect("127.0.0.1", server.localPort, 2_000)
            server.accept().use { peer ->
                peer.soTimeout = 5_000
                val ownerLock = ReentrantLock()
                val enqueued = CountDownLatch(1)
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
                    assertThat(ownerLock.tryLock(2, TimeUnit.SECONDS)).isTrue()
                    ownerLock.unlock()
                    // The peer has not drained this full-size packet; ownership must already
                    // be available to cancellation/cleanup while publication remains pending.
                    assertThat(send.isDone).isFalse()
                    val input = DataInputStream(peer.getInputStream())
                    assertThat(input.readLong()).isEqualTo(payload.size.toLong())
                    val received = ByteArray(payload.size).also(input::readFully)
                    assertThat(received).isEqualTo(payload)
                    send.get(5, TimeUnit.SECONDS)
                } finally {
                    packet.close()
                    executor.shutdownNow()
                }
            }
        }
    }
}
