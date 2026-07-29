package com.healthmd.direct

import com.healthmd.BuildConfig
import com.healthmd.core.CoreDirectTransferCapabilities
import com.healthmd.core.CoreDirectTransferChunk
import com.healthmd.core.CoreDirectTransferNegotiation
import com.healthmd.core.HealthMdCoreService
import com.healthmd.direct.protocol.ANDROID_APPLICATION_PROTOCOL_VERSION
import com.healthmd.direct.protocol.ANDROID_PAIRING_PROTOCOL_VERSION
import com.healthmd.direct.protocol.DIRECT_PORT
import com.healthmd.direct.protocol.DirectJson
import com.healthmd.direct.protocol.DirectProtocolDeterministicCore
import com.healthmd.direct.protocol.ExportRequest
import com.healthmd.direct.protocol.JOB_LIFETIME_SECONDS
import com.healthmd.direct.protocol.MAXIMUM_CHUNK_BYTES
import com.healthmd.direct.protocol.MAXIMUM_PACKET_BYTES
import com.healthmd.direct.protocol.MAXIMUM_PARTITION_BYTES
import com.healthmd.direct.protocol.MINIMUM_PARTITION_BYTES
import com.healthmd.direct.protocol.PREFERRED_PARTITION_BYTES
import com.healthmd.direct.protocol.TRANSPORT_PROTOCOL_VERSION
import com.healthmd.direct.protocol.TransferCapabilities
import com.healthmd.direct.protocol.TransferNegotiation
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.encodeToJsonElement

enum class AndroidDirectProtocolEngineMode {
    legacy,
    shadow,
    rust;

    companion object {
        fun parse(value: String): AndroidDirectProtocolEngineMode =
            entries.firstOrNull { it.name == value } ?: legacy
    }
}

enum class AndroidDirectProtocolStage {
    compatibility,
    requestFingerprint,
    v2Envelope,
    transferFrame,
    transferNegotiation,
}

/** Health-free aggregate shadow evidence. No wire bytes, identifiers, paths, or values are retained. */
data class AndroidDirectProtocolComparisonSnapshot(
    val comparisons: Map<AndroidDirectProtocolStage, Int>,
    val mismatches: Map<AndroidDirectProtocolStage, Int>,
)

@Serializable
data class AndroidDirectProtocolPin(
    val version: Int = CURRENT_VERSION,
    val engine: AndroidDirectProtocolEngineMode,
    val coreApiVersion: UInt,
    val protocolApiRevision: UInt,
    val androidApplicationProtocolVersion: UInt,
    val transferProtocolVersion: UInt,
    val coreCrateVersion: String,
    val coreSourceRevision: String,
) {
    init {
        require(version == CURRENT_VERSION)
        require(engine != AndroidDirectProtocolEngineMode.legacy)
        require(coreApiVersion > 0u && protocolApiRevision > 0u)
        require(androidApplicationProtocolVersion > 0u && transferProtocolVersion > 0u)
        require(coreCrateVersion.isNotBlank() && coreCrateVersion.length <= 64)
        require(coreSourceRevision.isNotBlank() && coreSourceRevision.length <= 128)
    }

    companion object {
        const val CURRENT_VERSION = 1
    }
}

class AndroidDirectProtocolAuthorityException internal constructor(
    val stage: AndroidDirectProtocolStage,
) : Exception("shared direct protocol core failed at ${stage.name}")

internal data class AndroidDirectProtocolBuildInfo(
    val coreApiVersion: UInt,
    val crateVersion: String,
    val coreSourceRevision: String,
)

internal interface AndroidDirectProtocolRustCore {
    fun buildInfo(): AndroidDirectProtocolBuildInfo
    fun protocolInfo(): AndroidDirectProtocolInfo
    fun fingerprintAndroidV2Request(bytes: ByteArray): String
    fun canonicalizeAndroidV2Envelope(bytes: ByteArray): ByteArray
    fun encodeTransferChunk(chunk: CoreDirectTransferChunk): ByteArray
    fun negotiateTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities,
    ): CoreDirectTransferNegotiation
}

internal data class AndroidDirectProtocolInfo(
    val protocolApiRevision: UInt,
    val supportedPairingProtocolVersions: List<UInt>,
    val androidApplicationProtocolVersion: UInt,
    val manualIpPort: UInt,
    val maximumControlJsonBytes: ULong,
    val transferProtocolVersion: UInt,
    val transferFrameHeaderBytes: ULong,
    val maximumChunkBytes: ULong,
    val minimumPartitionBytes: ULong,
    val preferredPartitionBytes: ULong,
    val maximumPartitionBytes: ULong,
    val maximumInFlightChunks: UInt,
    val durableJobLifetimeSeconds: ULong,
)

private class UniFfiAndroidDirectProtocolRustCore : AndroidDirectProtocolRustCore {
    private val service by lazy(LazyThreadSafetyMode.SYNCHRONIZED, ::HealthMdCoreService)

    override fun buildInfo(): AndroidDirectProtocolBuildInfo = service.getBuildInfo().let { info ->
        AndroidDirectProtocolBuildInfo(
            coreApiVersion = info.coreApiVersion,
            crateVersion = info.crateVersion,
            coreSourceRevision = info.coreSourceRevision,
        )
    }

    override fun protocolInfo(): AndroidDirectProtocolInfo = service.getDirectProtocolInfo().let { info ->
        AndroidDirectProtocolInfo(
            protocolApiRevision = info.protocolApiRevision,
            supportedPairingProtocolVersions = info.supportedPairingProtocolVersions,
            androidApplicationProtocolVersion = info.androidApplicationProtocolVersion,
            manualIpPort = info.manualIpPort,
            maximumControlJsonBytes = info.maximumControlJsonBytes,
            transferProtocolVersion = info.transferProtocolVersion,
            transferFrameHeaderBytes = info.transferFrameHeaderBytes,
            maximumChunkBytes = info.maximumChunkBytes,
            minimumPartitionBytes = info.minimumPartitionBytes,
            preferredPartitionBytes = info.preferredPartitionBytes,
            maximumPartitionBytes = info.maximumPartitionBytes,
            maximumInFlightChunks = info.maximumInFlightChunks,
            durableJobLifetimeSeconds = info.durableJobLifetimeSeconds,
        )
    }

    override fun fingerprintAndroidV2Request(bytes: ByteArray): String =
        service.fingerprintAndroidV2Request(bytes)

    override fun canonicalizeAndroidV2Envelope(bytes: ByteArray): ByteArray =
        service.canonicalizeAndroidV2Envelope(bytes)

    override fun encodeTransferChunk(chunk: CoreDirectTransferChunk): ByteArray =
        service.encodeTransferChunk(chunk)

    override fun negotiateTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities,
    ): CoreDirectTransferNegotiation = service.negotiateTransfer(local, peer)
}

/**
 * Operation-wide deterministic protocol authority behind the native direct transport.
 *
 * `shadow` always returns the Kotlin-native result. `rust` never falls back after a Rust failure.
 * Sockets, pairing/trust, AEAD, secure-channel sequences, lifecycle, and durable storage stay native.
 */
@Singleton
class AndroidDirectProtocolAuthority internal constructor(
    val mode: AndroidDirectProtocolEngineMode,
    private val rustCore: Lazy<AndroidDirectProtocolRustCore>,
) : DirectProtocolDeterministicCore {
    @Inject
    constructor() : this(
        mode = AndroidDirectProtocolEngineMode.parse(BuildConfig.DIRECT_PROTOCOL_ENGINE),
        rustCore = lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
            UniFfiAndroidDirectProtocolRustCore()
        },
    )

    private val evidenceLock = Any()
    private val comparisons = mutableMapOf<AndroidDirectProtocolStage, Int>()
    private val mismatches = mutableMapOf<AndroidDirectProtocolStage, Int>()
    @Volatile private var operationMode: AndroidDirectProtocolEngineMode? = null

    private val activeMode: AndroidDirectProtocolEngineMode
        get() = operationMode ?: mode

    fun assertCompatible() {
        if (activeMode == AndroidDirectProtocolEngineMode.legacy) return
        val compatible = compatibleNow()
        if (activeMode == AndroidDirectProtocolEngineMode.shadow) {
            record(AndroidDirectProtocolStage.compatibility, !compatible)
        } else if (!compatible) {
            throw AndroidDirectProtocolAuthorityException(AndroidDirectProtocolStage.compatibility)
        }
    }

    fun pinForNewOperation(): AndroidDirectProtocolPin? {
        if (mode == AndroidDirectProtocolEngineMode.legacy) return null
        if (!compatibleNow()) {
            throw AndroidDirectProtocolAuthorityException(
                AndroidDirectProtocolStage.compatibility,
            )
        }
        val build = rustCore.value.buildInfo()
        val info = rustCore.value.protocolInfo()
        return AndroidDirectProtocolPin(
            engine = mode,
            coreApiVersion = build.coreApiVersion,
            protocolApiRevision = info.protocolApiRevision,
            androidApplicationProtocolVersion = info.androidApplicationProtocolVersion,
            transferProtocolVersion = info.transferProtocolVersion,
            coreCrateVersion = build.crateVersion,
            coreSourceRevision = build.coreSourceRevision,
        )
    }

    fun beginBootstrap() {
        operationMode = AndroidDirectProtocolEngineMode.legacy
    }

    fun beginOperation(pin: AndroidDirectProtocolPin?) {
        operationMode = pin?.engine ?: AndroidDirectProtocolEngineMode.legacy
        if (pin == null) return
        val compatible = runCatching {
            val build = rustCore.value.buildInfo()
            val info = rustCore.value.protocolInfo()
            pin.version == AndroidDirectProtocolPin.CURRENT_VERSION &&
                pin.coreApiVersion == build.coreApiVersion &&
                pin.protocolApiRevision == info.protocolApiRevision &&
                pin.androidApplicationProtocolVersion == info.androidApplicationProtocolVersion &&
                pin.transferProtocolVersion == info.transferProtocolVersion
        }.getOrDefault(false)
        if (!compatible) {
            operationMode = null
            throw AndroidDirectProtocolAuthorityException(
                AndroidDirectProtocolStage.compatibility,
            )
        }
    }

    fun endOperation() {
        operationMode = null
    }

    private fun compatibleNow(): Boolean = runCatching {
        val info = rustCore.value.protocolInfo()
        rustCore.value.buildInfo().coreApiVersion == HealthMdCoreService.EXPECTED_CORE_API_VERSION &&
            info.protocolApiRevision == EXPECTED_PROTOCOL_API_REVISION &&
            ANDROID_PAIRING_PROTOCOL_VERSION.toUInt() in info.supportedPairingProtocolVersions &&
            info.androidApplicationProtocolVersion == ANDROID_APPLICATION_PROTOCOL_VERSION.toUInt() &&
            info.manualIpPort == DIRECT_PORT.toUInt() &&
            info.maximumControlJsonBytes == MAXIMUM_PACKET_BYTES.toULong() &&
            info.transferProtocolVersion == TRANSPORT_PROTOCOL_VERSION.toUInt() &&
            info.transferFrameHeaderBytes == TRANSFER_FRAME_HEADER_BYTES.toULong() &&
            info.maximumChunkBytes == MAXIMUM_CHUNK_BYTES.toULong() &&
            info.minimumPartitionBytes == MINIMUM_PARTITION_BYTES.toULong() &&
            info.preferredPartitionBytes == PREFERRED_PARTITION_BYTES.toULong() &&
            info.maximumPartitionBytes == MAXIMUM_PARTITION_BYTES.toULong() &&
            info.maximumInFlightChunks == MAXIMUM_IN_FLIGHT_CHUNKS.toUInt() &&
            info.durableJobLifetimeSeconds == JOB_LIFETIME_SECONDS.toULong()
    }.getOrDefault(false)

    fun requestFingerprint(request: ExportRequest): String {
        val bytes = DirectJson.canonicalBytes(
            DirectJson.json.encodeToJsonElement(ExportRequest.serializer(), request),
        )
        val native = DirectJson.sha256Hex(bytes)
        return select(AndroidDirectProtocolStage.requestFingerprint, native) {
            rustCore.value.fingerprintAndroidV2Request(bytes)
        }
    }

    override fun canonicalizeV2Envelope(nativeBytes: ByteArray): ByteArray =
        selectBytes(AndroidDirectProtocolStage.v2Envelope, nativeBytes) {
            rustCore.value.canonicalizeAndroidV2Envelope(nativeBytes)
        }

    override fun encodeTransferFrame(
        transferId: String,
        sequence: Int,
        data: ByteArray,
        nativeFrame: ByteArray,
    ): ByteArray = selectBytes(AndroidDirectProtocolStage.transferFrame, nativeFrame) {
        rustCore.value.encodeTransferChunk(
            CoreDirectTransferChunk(
                transferId = transferId,
                sequence = sequence.toULong(),
                sha256 = DirectJson.sha256Hex(data),
                chunkBytes = data,
            ),
        )
    }

    fun negotiateTransfer(peer: TransferCapabilities): TransferNegotiation? {
        val local = TransferCapabilities()
        val native = local.negotiatedWith(peer)
        val rust = {
            rustCore.value.negotiateTransfer(local.toCore(), peer.toCore()).toNative()
        }
        return when (activeMode) {
            AndroidDirectProtocolEngineMode.legacy -> native
            AndroidDirectProtocolEngineMode.shadow -> {
                val rustResult = runCatching(rust)
                record(
                    AndroidDirectProtocolStage.transferNegotiation,
                    rustResult.isFailure || rustResult.getOrNull() != native,
                )
                native
            }
            AndroidDirectProtocolEngineMode.rust -> runCatching(rust).getOrElse {
                throw AndroidDirectProtocolAuthorityException(
                    AndroidDirectProtocolStage.transferNegotiation,
                )
            }
        }
    }

    fun comparisonSnapshot(): AndroidDirectProtocolComparisonSnapshot = synchronized(evidenceLock) {
        AndroidDirectProtocolComparisonSnapshot(comparisons.toMap(), mismatches.toMap())
    }

    private fun select(
        stage: AndroidDirectProtocolStage,
        native: String,
        rust: () -> String,
    ): String = when (activeMode) {
        AndroidDirectProtocolEngineMode.legacy -> native
        AndroidDirectProtocolEngineMode.shadow -> {
            val rustResult = runCatching(rust)
            record(stage, rustResult.isFailure || rustResult.getOrNull() != native)
            native
        }
        AndroidDirectProtocolEngineMode.rust -> runCatching(rust).getOrElse {
            throw AndroidDirectProtocolAuthorityException(stage)
        }
    }

    private fun selectBytes(
        stage: AndroidDirectProtocolStage,
        native: ByteArray,
        rust: () -> ByteArray,
    ): ByteArray = when (activeMode) {
        AndroidDirectProtocolEngineMode.legacy -> native
        AndroidDirectProtocolEngineMode.shadow -> {
            val rustResult = runCatching(rust)
            record(stage, rustResult.isFailure || rustResult.getOrNull()?.contentEquals(native) != true)
            native
        }
        AndroidDirectProtocolEngineMode.rust -> runCatching(rust).getOrElse {
            throw AndroidDirectProtocolAuthorityException(stage)
        }
    }

    private fun record(stage: AndroidDirectProtocolStage, mismatch: Boolean) {
        synchronized(evidenceLock) {
            comparisons[stage] = comparisons.getOrDefault(stage, 0) + 1
            if (mismatch) mismatches[stage] = mismatches.getOrDefault(stage, 0) + 1
        }
    }

    private fun TransferCapabilities.toCore() = CoreDirectTransferCapabilities(
        protocolVersions = protocolVersions.map { it.toUInt() },
        binaryFrameVersions = binaryFrameVersions.map { it.toUInt() },
        minimumPartitionBytes = minimumPartitionBytes.toULong(),
        preferredPartitionBytes = preferredPartitionBytes.toULong(),
        maximumPartitionBytes = maximumPartitionBytes.toULong(),
        maximumInFlightChunks = maximumInFlightChunks.toUInt(),
    )

    private fun CoreDirectTransferNegotiation.toNative() = TransferNegotiation(
        protocolVersion = protocolVersion.toInt(),
        binaryFrameVersion = binaryFrameVersion.toInt(),
        partitionTargetBytes = partitionTargetBytes.toLong(),
        maximumInFlightChunks = maximumInFlightChunks.toInt(),
    )

    companion object {
        const val EXPECTED_PROTOCOL_API_REVISION: UInt = 1u
        private const val TRANSFER_FRAME_HEADER_BYTES = 66
        private const val MAXIMUM_IN_FLIGHT_CHUNKS = 4
    }
}
