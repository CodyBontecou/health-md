package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.net.ServerSocket
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Test

class PacketPollingTest {
    @Test
    fun timeoutDuringSplitLengthPreservesPacketFraming() {
        val server = ServerSocket(0)
        val firstHalfSent = CountDownLatch(1)
        val payload = "split-packet".toByteArray()
        val writer = thread(start = true) {
            server.accept().use { socket ->
                val length = ByteBuffer.allocate(Long.SIZE_BYTES).putLong(payload.size.toLong()).array()
                socket.getOutputStream().apply {
                    write(length, 0, 4)
                    flush()
                    firstHalfSent.countDown()
                    Thread.sleep(150)
                    write(length, 4, 4)
                    write(payload)
                    flush()
                }
            }
        }
        val connection = DirectPacketConnection.connect("127.0.0.1", server.localPort, 1_000)
        try {
            assertThat(firstHalfSent.await(1, TimeUnit.SECONDS)).isTrue()
            assertThat(connection.receiveOrNull(50)).isNull()
            assertThat(connection.receiveOrNull(1_000)).isEqualTo(payload)
        } finally {
            connection.close()
            server.close()
            writer.join(1_000)
        }
    }
}
