package com.healthmd.direct.protocol

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID
import kotlinx.serialization.SerializationStrategy

private val SECURE_MAGIC = "HMDSC001".toByteArray(StandardCharsets.US_ASCII)
private val BINARY_MAGIC = "HMDDIRCT".toByteArray(StandardCharsets.US_ASCII)

class DirectPacketConnection private constructor(
    private val socket: Socket,
    private val defaultReadTimeoutMillis: Int,
) : Closeable {
    private val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
    private val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
    private val pendingLength = ByteArray(Long.SIZE_BYTES)
    private var pendingLengthBytes = 0
    private var pendingPayload: ByteArray? = null
    private var pendingPayloadBytes = 0

    fun send(packet: ByteArray) {
        require(packet.isNotEmpty() && packet.size <= MAXIMUM_PACKET_BYTES) { "Invalid direct packet size." }
        output.writeLong(packet.size.toLong())
        output.write(packet)
        output.flush()
    }

    @Synchronized
    fun receive(): ByteArray = receiveOrNull(defaultReadTimeoutMillis)
        ?: throw SocketTimeoutException("Timed out waiting for a direct packet.")

    @Synchronized
    fun receiveOrNull(timeoutMillis: Int): ByteArray? {
        require(timeoutMillis > 0)
        socket.soTimeout = timeoutMillis
        return try {
            while (pendingLengthBytes < pendingLength.size) {
                val count = input.read(
                    pendingLength,
                    pendingLengthBytes,
                    pendingLength.size - pendingLengthBytes,
                )
                if (count < 0) throw java.io.EOFException()
                pendingLengthBytes += count
            }
            if (pendingPayload == null) {
                val count = ByteBuffer.wrap(pendingLength).long
                require(count in 1..MAXIMUM_PACKET_BYTES.toLong()) { "Invalid direct packet size." }
                pendingPayload = ByteArray(count.toInt())
            }
            val payload = requireNotNull(pendingPayload)
            while (pendingPayloadBytes < payload.size) {
                val count = input.read(
                    payload,
                    pendingPayloadBytes,
                    payload.size - pendingPayloadBytes,
                )
                if (count < 0) throw java.io.EOFException()
                pendingPayloadBytes += count
            }
            pendingLengthBytes = 0
            pendingPayload = null
            pendingPayloadBytes = 0
            payload
        } catch (_: SocketTimeoutException) {
            null
        } finally {
            socket.soTimeout = defaultReadTimeoutMillis
        }
    }

    override fun close() {
        socket.close()
    }

    companion object {
        fun connect(host: String, port: Int, timeoutMillis: Int): DirectPacketConnection {
            require(host.isNotBlank() && port in 1..65_535)
            val socket = Socket()
            socket.tcpNoDelay = true
            socket.connect(InetSocketAddress(host.trim(), port), timeoutMillis)
            socket.soTimeout = timeoutMillis
            return DirectPacketConnection(socket, timeoutMillis)
        }
    }
}

sealed interface ReceivedSecurePayload {
    data class Control(val bytes: ByteArray) : ReceivedSecurePayload
    data class Binary(val bytes: ByteArray) : ReceivedSecurePayload
}

class DirectSecureChannel internal constructor(
    private val packet: DirectPacketConnection,
    private val sessionKey: ByteArray,
    val listenerInstallationId: String,
    val listenerDisplayName: String,
) : Closeable {
    private var nextSendSequence = 0L
    private var nextReceiveSequence = 0L

    fun sendNegotiationHello(installationId: String) {
        val hello = NegotiationHello(
            protocolVersions = listOf(ANDROID_APPLICATION_PROTOCOL_VERSION),
            platform = "android",
            installationId = installationId.lowercase(),
            supportedRawProfiles = emptyList(),
            supportsDurableJobs = true,
            supportsCanonicalExtraction = false,
            transfer = TransferCapabilities(),
        )
        sendControl(LegacyCodec.hello(hello))
    }

    fun receiveNegotiationHello(): NegotiationHello {
        val payload = receive()
        require(payload is ReceivedSecurePayload.Control) { "Expected a negotiation message." }
        return LegacyCodec.parseHello(payload.bytes)
    }

    fun <T> sendV2(type: String, serializer: SerializationStrategy<T>, payload: T) {
        sendControl(V2Codec.encode(type, serializer, payload))
    }

    fun receiveV2(): ReceivedEnvelope {
        val payload = receive()
        require(payload is ReceivedSecurePayload.Control) { "Expected a control message." }
        return V2Codec.decode(payload.bytes)
    }

    fun pollV2(timeoutMillis: Int): ReceivedEnvelope? {
        val frame = packet.receiveOrNull(timeoutMillis) ?: return null
        val payload = receiveEncryptedFrame(frame)
        require(payload is ReceivedSecurePayload.Control) { "Expected a control message." }
        return V2Codec.decode(payload.bytes)
    }

    fun sendBinary(frame: ByteArray) {
        require(frame.startsWithBytes(BINARY_MAGIC)) { "Invalid transfer frame." }
        sendEncrypted(frame)
    }

    fun receive(): ReceivedSecurePayload = receiveEncryptedFrame(packet.receive())

    private fun receiveEncryptedFrame(packetBytes: ByteArray): ReceivedSecurePayload {
        val frame = LegacyCodec.encryptedFrame(packetBytes)
        val envelope = DirectCrypto.open(frame, sessionKey)
        require(envelope.size >= 16 && envelope.copyOfRange(0, 8).contentEquals(SECURE_MAGIC)) {
            "Malformed secure envelope."
        }
        val sequence = ByteBuffer.wrap(envelope, 8, 8).long
        require(sequence == nextReceiveSequence) { "Replayed or out-of-order direct packet." }
        check(nextReceiveSequence != Long.MAX_VALUE) { "Direct receive sequence exhausted." }
        nextReceiveSequence += 1
        val plaintext = envelope.copyOfRange(16, envelope.size)
        return if (plaintext.startsWithBytes(BINARY_MAGIC)) {
            ReceivedSecurePayload.Binary(plaintext)
        } else {
            ReceivedSecurePayload.Control(plaintext)
        }
    }

    override fun close() {
        packet.close()
    }

    private fun sendControl(bytes: ByteArray) {
        sendEncrypted(bytes)
    }

    @Synchronized
    private fun sendEncrypted(plaintext: ByteArray) {
        check(nextSendSequence != Long.MAX_VALUE) { "Direct send sequence exhausted." }
        val envelope = ByteBuffer.allocate(SECURE_MAGIC.size + Long.SIZE_BYTES + plaintext.size)
            .put(SECURE_MAGIC)
            .putLong(nextSendSequence)
            .put(plaintext)
            .array()
        nextSendSequence += 1
        packet.send(LegacyCodec.encrypted(DirectCrypto.seal(envelope, sessionKey)))
    }
}

data class ConnectedDirectClient(
    val channel: DirectSecureChannel,
    val listener: AuthenticatedListener,
)

object DirectClient {
    fun connect(
        host: String,
        port: Int = DIRECT_PORT,
        timeoutMillis: Int = 10_000,
        installationId: String,
        displayName: String,
        pairingCode: String? = null,
        trustedListener: TrustedListener? = null,
    ): ConnectedDirectClient {
        val packet = DirectPacketConnection.connect(host, port, timeoutMillis)
        try {
            val normalizedCode = pairingCode.orEmpty().filter { it in '0'..'9' }
            val reconnect = if (normalizedCode.isEmpty()) trustedListener else null
            require(normalizedCode.length == 20 || reconnect != null) {
                "Enter the 20-digit Android pairing code shown by the healthmd CLI."
            }

            val keyPair = DirectCrypto.ephemeralKeyPair()
            val clientNonce = DirectCrypto.randomBytes(32)
            val codeVerifier = if (reconnect == null) {
                DirectCrypto.androidPairingVerifier(
                    normalizedCode,
                    installationId,
                    keyPair.publicKey,
                    clientNonce,
                )
            } else {
                ByteArray(0)
            }
            val trustedVerifier = reconnect?.let {
                DirectCrypto.trustedClientVerifier(
                    it.reconnectSecret,
                    installationId,
                    keyPair.publicKey,
                    clientNonce,
                )
            }
            packet.send(LegacyCodec.pairingRequest(PairingRequest(
                protocolVersion = ANDROID_PAIRING_PROTOCOL_VERSION,
                deviceName = displayName,
                clientPublicKey = keyPair.publicKey,
                clientNonce = clientNonce,
                codeVerifier = codeVerifier,
                clientInstallationId = installationId,
                trustedVerifier = trustedVerifier,
            )))

            val response = LegacyCodec.pairingResponse(packet.receive())
            require(response.protocolVersion == ANDROID_PAIRING_PROTOCOL_VERSION) {
                "The CLI uses an incompatible Android pairing protocol."
            }
            if (reconnect != null) {
                require(reconnect.installationId.equals(response.listenerInstallationId, ignoreCase = true)) {
                    "The paired CLI identity changed."
                }
            }

            val sharedSecret = DirectCrypto.sharedSecret(keyPair.privateKey, response.serverPublicKey)
            val sessionKey = DirectCrypto.sessionKey(sharedSecret, clientNonce, response.serverNonce)
            val reconnectSecret = DirectCrypto.open(response.sealedReconnectSecret, sessionKey)
            require(reconnectSecret.size == 32) { "The CLI returned an invalid reconnect credential." }
            if (reconnect != null) {
                require(DirectCrypto.constantTimeEquals(reconnect.reconnectSecret, reconnectSecret)) {
                    "The paired CLI credential changed."
                }
            }

            val expectedVerifier = if (reconnect == null) {
                DirectCrypto.androidPairingServerVerifier(
                    normalizedCode,
                    installationId,
                    keyPair.publicKey,
                    clientNonce,
                    response.listenerInstallationId,
                    response.serverPublicKey,
                    response.serverNonce,
                    response.sealedReconnectSecret,
                )
            } else {
                DirectCrypto.trustedServerVerifier(
                    reconnect.reconnectSecret,
                    installationId,
                    keyPair.publicKey,
                    clientNonce,
                    response.listenerInstallationId,
                    response.serverPublicKey,
                    response.serverNonce,
                )
            }
            require(DirectCrypto.constantTimeEquals(response.authenticationVerifier, expectedVerifier)) {
                "The CLI could not be authenticated."
            }

            val listener = AuthenticatedListener(
                installationId = response.listenerInstallationId,
                displayName = response.listenerName,
                reconnectSecret = reconnectSecret,
            )
            return ConnectedDirectClient(
                channel = DirectSecureChannel(
                    packet = packet,
                    sessionKey = sessionKey,
                    listenerInstallationId = listener.installationId,
                    listenerDisplayName = listener.displayName,
                ),
                listener = listener,
            )
        } catch (error: Throwable) {
            packet.close()
            throw error
        }
    }
}

object BinaryTransferFrame {
    fun encode(transferId: String, sequence: Int, data: ByteArray): ByteArray {
        require(sequence > 0 && data.size <= MAXIMUM_CHUNK_BYTES)
        val id = UUID.fromString(transferId)
        val digest = MessageDigest.getInstance("SHA-256").digest(data)
        return ByteBuffer.allocate(66 + data.size)
            .put(BINARY_MAGIC)
            .putShort(1)
            .putLong(id.mostSignificantBits)
            .putLong(id.leastSignificantBits)
            .putInt(sequence)
            .putInt(data.size)
            .put(digest)
            .put(data)
            .array()
    }
}

private fun ByteArray.startsWithBytes(prefix: ByteArray): Boolean =
    size >= prefix.size && indices.take(prefix.size).all { this[it] == prefix[it] }
