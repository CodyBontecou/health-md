package com.healthmd.core

import java.nio.ByteBuffer

/**
 * Handwritten Android boundary around the generated UniFFI API.
 *
 * Constructing this service does not load the native library. JNA registration and UniFFI
 * checksum validation happen lazily on the first method call.
 */
class HealthMdCoreService internal constructor(
    private val bindings: Lazy<HealthMdCoreBindings>,
) {
    constructor() : this(lazy(LazyThreadSafetyMode.SYNCHRONIZED) { UniFfiHealthMdCoreBindings })

    fun getBuildInfo(): CoreBuildInfo = callNative { getBuildInfo() }

    fun runSelfTest(): CoreSelfTestReport = callNative { runSelfTest() }

    fun getMetricRegistry(
        profile: CoreMetricRegistryProfile,
        expectedRegistryVersion: UInt = EXPECTED_REGISTRY_VERSION,
    ): CoreMetricRegistrySnapshot = callNative {
        getMetricRegistry(profile, expectedRegistryVersion)
    }

    fun createSemanticSession(configurationBytes: ByteArray): HealthMdCoreSemanticSession {
        val directBytes = configurationBytes.toDirectByteBuffer()
        return callNative { HealthMdCoreSemanticSession(createSemanticSession(directBytes)) }
    }

    fun createRenderSession(
        configurationBytes: ByteArray,
        semanticResultBytes: ByteArray,
    ): HealthMdCoreRenderSession {
        val configuration = configurationBytes.toDirectByteBuffer()
        val semanticResult = semanticResultBytes.toDirectByteBuffer()
        return callRenderNative { HealthMdCoreRenderSession(createRenderSession(configuration, semanticResult)) }
    }

    fun createLosslessArtifactStream(mode: CoreStreamMode): HealthMdCoreLosslessArtifactStream =
        HealthMdCoreLosslessArtifactStream(bindings.value.createLosslessArtifactStream(mode))

    fun createPlannedLosslessArtifactStream(
        mode: CoreStreamMode,
        artifact: CoreStreamArtifactConfig,
    ): HealthMdCoreLosslessArtifactStream = callRenderNative {
        HealthMdCoreLosslessArtifactStream(bindings.value.createPlannedLosslessArtifactStream(mode, artifact))
    }

    fun mergeMarkdown(
        profile: CoreMetricRegistryProfile,
        existing: String,
        generated: String,
        preservePreamble: Boolean = false,
    ): String = callRenderNative {
        mergeProfileRenderedMarkdown(profile, existing, generated, preservePreamble)
    }

    fun mergeMarkdown(existing: String, generated: String): String =
        callRenderNative { mergeRenderedMarkdown(existing, generated) }

    fun getDirectProtocolInfo(): CoreDirectProtocolInfo = callProtocolNative { getDirectProtocolInfo() }

    fun fingerprintAppleV1Request(canonicalRequestBytes: ByteArray): String =
        callProtocolNative {
            fingerprintAppleV1DirectRequest(canonicalRequestBytes.toDirectByteBuffer())
        }

    fun fingerprintAndroidV2Request(canonicalRequestBytes: ByteArray): String =
        callProtocolNative {
            fingerprintAndroidV2DirectRequest(canonicalRequestBytes.toDirectByteBuffer())
        }

    fun canonicalizeAppleV1Message(messageBytes: ByteArray): ByteArray =
        callProtocolNative {
            canonicalizeAppleV1DirectMessage(messageBytes.toDirectByteBuffer())
        }

    fun canonicalizeAndroidV2Envelope(envelopeBytes: ByteArray): ByteArray =
        callProtocolNative {
            canonicalizeAndroidV2DirectEnvelope(envelopeBytes.toDirectByteBuffer())
        }

    fun encodeTransferChunk(chunk: CoreDirectTransferChunk): ByteArray =
        callProtocolNative { encodeDirectTransferChunk(chunk) }

    fun decodeTransferChunk(frameBytes: ByteArray): CoreDirectTransferChunk =
        callProtocolNative { decodeDirectTransferChunk(frameBytes.toDirectByteBuffer()) }

    fun getDefaultTransferCapabilities(): CoreDirectTransferCapabilities =
        callProtocolNative { getDefaultDirectTransferCapabilities() }

    fun negotiateTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities,
    ): CoreDirectTransferNegotiation = callProtocolNative {
        negotiateDirectTransfer(local, peer)
    }

    fun verifyPairingClientTranscript(request: CoreDirectPairingVerifierRequest): Boolean =
        callProtocolNative { verifyDirectPairingClientTranscript(request) }

    /** The caller owns the returned key bytes and should overwrite them promptly after use. */
    fun deriveSessionKey(request: CoreDirectSessionKeyRequest): ByteArray =
        callProtocolNative { deriveDirectSessionKey(request) }

    fun validateFixture(
        fixtureBytes: ByteArray,
        expectedSha256: String,
    ): FixtureValidation {
        val directBytes = fixtureBytes.toDirectByteBuffer()
        return callNative { validateFixture(directBytes, expectedSha256) }
    }

    /** Returns health-free compatibility evidence without changing any product capability state. */
    fun checkReadiness(): HealthMdCoreReadiness {
        val buildInfo = getBuildInfo()
        val selfTest = runSelfTest()
        return HealthMdCoreReadiness(
            isReady = selfTest.passed &&
                selfTest.buildInfo == buildInfo &&
                buildInfo.coreSourceRevision.isNotBlank() &&
                buildInfo.registrySha256.matches(Regex("[0-9a-f]{64}")) &&
                buildInfo.coreApiVersion == EXPECTED_CORE_API_VERSION &&
                buildInfo.semanticInputVersion == EXPECTED_SEMANTIC_INPUT_VERSION &&
                buildInfo.canonicalModelVersion == EXPECTED_CANONICAL_MODEL_VERSION &&
                buildInfo.registryVersion == EXPECTED_REGISTRY_VERSION &&
                buildInfo.renderInputVersion == EXPECTED_RENDER_INPUT_VERSION &&
                buildInfo.artifactPlanVersion == EXPECTED_ARTIFACT_PLAN_VERSION &&
                buildInfo.renderProfileRevision == EXPECTED_RENDER_PROFILE_REVISION &&
                buildInfo.persistedStateVersion == EXPECTED_PERSISTED_STATE_VERSION,
            buildInfo = buildInfo,
            selfTest = selfTest,
        )
    }

    private inline fun <T> callProtocolNative(block: HealthMdCoreBindings.() -> T): T =
        try {
            bindings.value.block()
        } catch (error: HealthmdProtocolException) {
            throw error.toProtocolServiceException()
        } catch (_: Exception) {
            throw HealthMdProtocolServiceException(
                HealthMdProtocolErrorCode.INTERNAL_PANIC,
                "shared protocol core failed internally",
            )
        }

    private inline fun <T> callRenderNative(block: HealthMdCoreBindings.() -> T): T =
        try {
            bindings.value.block()
        } catch (error: HealthmdRenderException) {
            throw error.toRenderServiceException()
        }

    private inline fun <T> callNative(block: HealthMdCoreBindings.() -> T): T =
        try {
            bindings.value.block()
        } catch (error: HealthmdCoreException) {
            throw error.toServiceException()
        }

    companion object {
        const val EXPECTED_CORE_API_VERSION: UInt = 4u
        const val EXPECTED_SEMANTIC_INPUT_VERSION: UInt = 1u
        const val EXPECTED_CANONICAL_MODEL_VERSION: UInt = 1u
        const val EXPECTED_REGISTRY_VERSION: UInt = 1u
        const val EXPECTED_RENDER_INPUT_VERSION: UInt = 1u
        const val EXPECTED_ARTIFACT_PLAN_VERSION: UInt = 1u
        const val EXPECTED_RENDER_PROFILE_REVISION: UInt = 2u
        const val EXPECTED_PERSISTED_STATE_VERSION: UInt = 1u
    }
}

data class HealthMdCoreReadiness(
    val isReady: Boolean,
    val buildInfo: CoreBuildInfo,
    val selfTest: CoreSelfTestReport,
)

enum class HealthMdCoreErrorCode {
    INVALID_FIXTURE_DIGEST,
    FIXTURE_TOO_LARGE,
    FIXTURE_DIGEST_MISMATCH,
    INVALID_FIXTURE,
    NON_CANONICAL_FIXTURE,
    UNSUPPORTED_FIXTURE_FORMAT_VERSION,
    UNSUPPORTED_SEMANTIC_INPUT_VERSION,
    UNSUPPORTED_REGISTRY_VERSION,
    UNSUPPORTED_PERSISTED_STATE_VERSION,
    INVALID_REGISTRY,
    UNSUPPORTED_REGISTRY_PROFILE,
    SEMANTIC_CONFIG_TOO_LARGE,
    INVALID_SEMANTIC_CONFIG,
    SEMANTIC_BATCH_TOO_LARGE,
    INVALID_SEMANTIC_BATCH,
    SEMANTIC_LIMIT_EXCEEDED,
    SEMANTIC_SEQUENCE_INVALID,
    SEMANTIC_SESSION_TERMINAL,
    UNSUPPORTED_SEMANTIC_OPERATION,
    INTERNAL_PANIC,
}

class HealthMdCoreServiceException internal constructor(
    val code: HealthMdCoreErrorCode,
    message: String,
    cause: HealthmdCoreException,
) : Exception(message, cause)

enum class HealthMdProtocolErrorCode {
    INPUT_TOO_LARGE,
    INVALID_JSON,
    UNKNOWN_FIELD,
    NON_CANONICAL_JSON,
    WRONG_PROTOCOL_PROFILE,
    UNSUPPORTED_PROTOCOL_VERSION,
    INVALID_REQUEST,
    INVALID_APPLE_MESSAGE,
    INVALID_ANDROID_ENVELOPE,
    INVALID_TRANSFER_CAPABILITIES,
    TRANSFER_NEGOTIATION_FAILED,
    INVALID_TRANSFER_METADATA,
    TRANSFER_FRAME_TOO_LARGE,
    INVALID_TRANSFER_FRAME,
    UNSUPPORTED_TRANSFER_FRAME_VERSION,
    INVALID_TRANSFER_CHUNK,
    INVALID_PAIRING_PROFILE,
    INVALID_PAIRING_CODE,
    INVALID_PAIRING_TRANSCRIPT,
    INVALID_SESSION_KEY_INPUT,
    SERIALIZATION_FAILED,
    INTERNAL_PANIC,
}

class HealthMdProtocolServiceException internal constructor(
    val code: HealthMdProtocolErrorCode,
    message: String,
) : Exception(message)

class HealthMdCoreSemanticSession internal constructor(
    private val generated: CoreSemanticSession,
) : AutoCloseable {
    fun processBatch(batchBytes: ByteArray): ByteArray = try {
        generated.processBatch(batchBytes.toDirectByteBuffer())
    } catch (error: HealthmdCoreException) {
        throw error.toServiceException()
    }

    fun cancel() = generated.cancel()

    override fun close() = generated.close()
}

enum class HealthMdRenderErrorCode {
    CONFIG_TOO_LARGE, INVALID_CONFIG, SEMANTIC_RESULT_TOO_LARGE, INVALID_SEMANTIC_RESULT,
    UNSUPPORTED_RENDER_INPUT_VERSION, UNSUPPORTED_ARTIFACT_PLAN_VERSION, UNSUPPORTED_PROFILE_REVISION,
    BATCH_TOO_LARGE, INVALID_BATCH, SEQUENCE_INVALID, LIMIT_EXCEEDED, PRESENTATION_MISMATCH,
    EXTENSION_NOT_RETAINED, EXTENSION_SELECTION_INVALID, UNSUPPORTED_OPERATION, INVALID_PATH,
    PATH_COLLISION, INVALID_ARTIFACT, ARTIFACT_TOO_LARGE, ARTIFACT_LIMIT_EXCEEDED,
    INLINE_OUTPUT_TOO_LARGE, SESSION_TERMINAL, CANCELLED, INVALID_STREAM_ITEM,
    STREAM_ITEM_TOO_LARGE, STREAM_TOO_LARGE, STREAM_SEQUENCE_INVALID, STREAM_TERMINAL,
    SERIALIZATION_FAILED, INTERNAL_PANIC,
}

class HealthMdRenderServiceException internal constructor(
    val code: HealthMdRenderErrorCode,
    cause: HealthmdRenderException,
) : Exception(code.name.lowercase(), cause)

class HealthMdCoreRenderSession internal constructor(
    private val generated: CoreRenderSession,
) : AutoCloseable {
    fun processBatch(batchBytes: ByteArray): CoreRenderBatchReceipt = renderCall {
        generated.processBatch(batchBytes.toDirectByteBuffer())
    }

    fun finish(): CoreArtifactPlan = renderCall { generated.finish() }

    fun cancel() = generated.cancel()

    override fun close() = generated.close()
}

class HealthMdCoreLosslessArtifactStream internal constructor(
    private val generated: CoreLosslessArtifactStream,
) : AutoCloseable {
    fun pushRaw(bytes: ByteArray): ByteArray = renderCall { generated.pushRaw(bytes.toDirectByteBuffer()) }

    fun pushJsonItem(bytes: ByteArray): ByteArray = renderCall { generated.pushJsonItem(bytes.toDirectByteBuffer()) }

    fun pushRfc4180Row(fields: List<String>): ByteArray = renderCall { generated.pushRfc4180Row(fields) }

    fun finish(): CoreStreamFinish = renderCall { generated.finish() }

    fun cancel() = generated.cancel()

    override fun close() = generated.close()
}

private inline fun <T> renderCall(block: () -> T): T = try {
    block()
} catch (error: HealthmdRenderException) {
    throw error.toRenderServiceException()
}

private fun ByteArray.toDirectByteBuffer(): ByteBuffer =
    ByteBuffer.allocateDirect(size).apply {
        put(this@toDirectByteBuffer)
        flip()
    }

internal interface HealthMdCoreBindings {
    fun getBuildInfo(): CoreBuildInfo

    fun runSelfTest(): CoreSelfTestReport

    fun getDirectProtocolInfo(): CoreDirectProtocolInfo

    fun fingerprintAppleV1DirectRequest(requestBytes: ByteBuffer): String

    fun fingerprintAndroidV2DirectRequest(requestBytes: ByteBuffer): String

    fun canonicalizeAppleV1DirectMessage(messageBytes: ByteBuffer): ByteArray

    fun canonicalizeAndroidV2DirectEnvelope(envelopeBytes: ByteBuffer): ByteArray

    fun encodeDirectTransferChunk(chunk: CoreDirectTransferChunk): ByteArray

    fun decodeDirectTransferChunk(frameBytes: ByteBuffer): CoreDirectTransferChunk

    fun getDefaultDirectTransferCapabilities(): CoreDirectTransferCapabilities

    fun negotiateDirectTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities,
    ): CoreDirectTransferNegotiation

    fun verifyDirectPairingClientTranscript(request: CoreDirectPairingVerifierRequest): Boolean

    fun deriveDirectSessionKey(request: CoreDirectSessionKeyRequest): ByteArray

    fun getMetricRegistry(
        profile: CoreMetricRegistryProfile,
        expectedRegistryVersion: UInt,
    ): CoreMetricRegistrySnapshot

    fun createSemanticSession(configBytes: ByteBuffer): CoreSemanticSession

    fun createRenderSession(configBytes: ByteBuffer, semanticResultBytes: ByteBuffer): CoreRenderSession

    fun createLosslessArtifactStream(mode: CoreStreamMode): CoreLosslessArtifactStream

    fun createPlannedLosslessArtifactStream(
        mode: CoreStreamMode,
        artifact: CoreStreamArtifactConfig,
    ): CoreLosslessArtifactStream

    fun mergeProfileRenderedMarkdown(
        profile: CoreMetricRegistryProfile,
        existing: String,
        generated: String,
        preservePreamble: Boolean,
    ): String

    fun mergeRenderedMarkdown(existing: String, generated: String): String

    fun validateFixture(fixtureBytes: ByteBuffer, expectedSha256: String): FixtureValidation
}

private object UniFfiHealthMdCoreBindings : HealthMdCoreBindings {
    init {
        uniffiEnsureInitialized()
    }

    override fun getBuildInfo(): CoreBuildInfo = com.healthmd.core.getBuildInfo()

    override fun runSelfTest(): CoreSelfTestReport = com.healthmd.core.runSelfTest()

    override fun getDirectProtocolInfo(): CoreDirectProtocolInfo =
        com.healthmd.core.getDirectProtocolInfo()

    override fun fingerprintAppleV1DirectRequest(requestBytes: ByteBuffer): String =
        com.healthmd.core.fingerprintAppleV1DirectRequest(requestBytes)

    override fun fingerprintAndroidV2DirectRequest(requestBytes: ByteBuffer): String =
        com.healthmd.core.fingerprintAndroidV2DirectRequest(requestBytes)

    override fun canonicalizeAppleV1DirectMessage(messageBytes: ByteBuffer): ByteArray =
        com.healthmd.core.canonicalizeAppleV1DirectMessage(messageBytes)

    override fun canonicalizeAndroidV2DirectEnvelope(envelopeBytes: ByteBuffer): ByteArray =
        com.healthmd.core.canonicalizeAndroidV2DirectEnvelope(envelopeBytes)

    override fun encodeDirectTransferChunk(chunk: CoreDirectTransferChunk): ByteArray =
        com.healthmd.core.encodeDirectTransferChunk(chunk)

    override fun decodeDirectTransferChunk(frameBytes: ByteBuffer): CoreDirectTransferChunk =
        com.healthmd.core.decodeDirectTransferChunk(frameBytes)

    override fun getDefaultDirectTransferCapabilities(): CoreDirectTransferCapabilities =
        com.healthmd.core.getDefaultDirectTransferCapabilities()

    override fun negotiateDirectTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities,
    ): CoreDirectTransferNegotiation = com.healthmd.core.negotiateDirectTransfer(local, peer)

    override fun verifyDirectPairingClientTranscript(
        request: CoreDirectPairingVerifierRequest,
    ): Boolean = com.healthmd.core.verifyDirectPairingClientTranscript(request)

    override fun deriveDirectSessionKey(request: CoreDirectSessionKeyRequest): ByteArray =
        com.healthmd.core.deriveDirectSessionKey(request)

    override fun getMetricRegistry(
        profile: CoreMetricRegistryProfile,
        expectedRegistryVersion: UInt,
    ): CoreMetricRegistrySnapshot = com.healthmd.core.getMetricRegistry(profile, expectedRegistryVersion)

    override fun createSemanticSession(configBytes: ByteBuffer): CoreSemanticSession =
        com.healthmd.core.createSemanticSession(configBytes)

    override fun createRenderSession(
        configBytes: ByteBuffer,
        semanticResultBytes: ByteBuffer,
    ): CoreRenderSession = com.healthmd.core.createRenderSession(configBytes, semanticResultBytes)

    override fun createLosslessArtifactStream(mode: CoreStreamMode): CoreLosslessArtifactStream =
        com.healthmd.core.createLosslessArtifactStream(mode)

    override fun createPlannedLosslessArtifactStream(
        mode: CoreStreamMode,
        artifact: CoreStreamArtifactConfig,
    ): CoreLosslessArtifactStream = com.healthmd.core.createPlannedLosslessArtifactStream(mode, artifact)

    override fun mergeProfileRenderedMarkdown(
        profile: CoreMetricRegistryProfile,
        existing: String,
        generated: String,
        preservePreamble: Boolean,
    ): String = com.healthmd.core.mergeProfileRenderedMarkdown(
        profile,
        existing,
        generated,
        preservePreamble,
    )

    override fun mergeRenderedMarkdown(existing: String, generated: String): String =
        com.healthmd.core.mergeRenderedMarkdown(existing, generated)

    override fun validateFixture(
        fixtureBytes: ByteBuffer,
        expectedSha256: String,
    ): FixtureValidation = com.healthmd.core.validateFixture(fixtureBytes, expectedSha256)
}

private fun HealthmdProtocolException.toProtocolServiceException(): HealthMdProtocolServiceException =
    when (this) {
        is HealthmdProtocolException.InputTooLarge -> protocolError(
            HealthMdProtocolErrorCode.INPUT_TOO_LARGE,
            "protocol input exceeds the size limit",
        )
        is HealthmdProtocolException.InvalidJson -> protocolError(
            HealthMdProtocolErrorCode.INVALID_JSON,
            "protocol JSON is invalid",
        )
        is HealthmdProtocolException.UnknownField -> protocolError(
            HealthMdProtocolErrorCode.UNKNOWN_FIELD,
            "protocol JSON contains an unknown field",
        )
        is HealthmdProtocolException.NonCanonicalJson -> protocolError(
            HealthMdProtocolErrorCode.NON_CANONICAL_JSON,
            "protocol JSON is not canonical",
        )
        is HealthmdProtocolException.WrongProtocolProfile -> protocolError(
            HealthMdProtocolErrorCode.WRONG_PROTOCOL_PROFILE,
            "protocol profile does not match the operation",
        )
        is HealthmdProtocolException.UnsupportedProtocolVersion -> protocolError(
            HealthMdProtocolErrorCode.UNSUPPORTED_PROTOCOL_VERSION,
            "direct protocol version is unsupported",
        )
        is HealthmdProtocolException.InvalidRequest -> protocolError(
            HealthMdProtocolErrorCode.INVALID_REQUEST,
            "direct export request is invalid",
        )
        is HealthmdProtocolException.InvalidAppleMessage -> protocolError(
            HealthMdProtocolErrorCode.INVALID_APPLE_MESSAGE,
            "Apple direct message is invalid",
        )
        is HealthmdProtocolException.InvalidAndroidEnvelope -> protocolError(
            HealthMdProtocolErrorCode.INVALID_ANDROID_ENVELOPE,
            "Android direct envelope is invalid",
        )
        is HealthmdProtocolException.InvalidTransferCapabilities -> protocolError(
            HealthMdProtocolErrorCode.INVALID_TRANSFER_CAPABILITIES,
            "transfer capabilities are invalid",
        )
        is HealthmdProtocolException.TransferNegotiationFailed -> protocolError(
            HealthMdProtocolErrorCode.TRANSFER_NEGOTIATION_FAILED,
            "transfer capabilities are incompatible",
        )
        is HealthmdProtocolException.InvalidTransferMetadata -> protocolError(
            HealthMdProtocolErrorCode.INVALID_TRANSFER_METADATA,
            "transfer chunk metadata is invalid",
        )
        is HealthmdProtocolException.TransferFrameTooLarge -> protocolError(
            HealthMdProtocolErrorCode.TRANSFER_FRAME_TOO_LARGE,
            "transfer frame exceeds the size limit",
        )
        is HealthmdProtocolException.InvalidTransferFrame -> protocolError(
            HealthMdProtocolErrorCode.INVALID_TRANSFER_FRAME,
            "transfer frame is invalid",
        )
        is HealthmdProtocolException.UnsupportedTransferFrameVersion -> protocolError(
            HealthMdProtocolErrorCode.UNSUPPORTED_TRANSFER_FRAME_VERSION,
            "transfer frame version is unsupported",
        )
        is HealthmdProtocolException.InvalidTransferChunk -> protocolError(
            HealthMdProtocolErrorCode.INVALID_TRANSFER_CHUNK,
            "transfer chunk is invalid",
        )
        is HealthmdProtocolException.InvalidPairingProfile -> protocolError(
            HealthMdProtocolErrorCode.INVALID_PAIRING_PROFILE,
            "pairing profile is invalid",
        )
        is HealthmdProtocolException.InvalidPairingCode -> protocolError(
            HealthMdProtocolErrorCode.INVALID_PAIRING_CODE,
            "pairing code is invalid",
        )
        is HealthmdProtocolException.InvalidPairingTranscript -> protocolError(
            HealthMdProtocolErrorCode.INVALID_PAIRING_TRANSCRIPT,
            "pairing transcript input is invalid",
        )
        is HealthmdProtocolException.InvalidSessionKeyInput -> protocolError(
            HealthMdProtocolErrorCode.INVALID_SESSION_KEY_INPUT,
            "session-key input is invalid",
        )
        is HealthmdProtocolException.SerializationFailed -> protocolError(
            HealthMdProtocolErrorCode.SERIALIZATION_FAILED,
            "protocol serialization failed",
        )
        is HealthmdProtocolException.InternalPanic -> protocolError(
            HealthMdProtocolErrorCode.INTERNAL_PANIC,
            "shared protocol core failed internally",
        )
    }

private fun HealthmdProtocolException.protocolError(
    code: HealthMdProtocolErrorCode,
    message: String,
) = HealthMdProtocolServiceException(code, message)

private fun HealthmdCoreException.toServiceException(): HealthMdCoreServiceException =
    when (this) {
        is HealthmdCoreException.InvalidFixtureDigest -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.INVALID_FIXTURE_DIGEST,
            "fixture digest must be lowercase SHA-256",
            this,
        )
        is HealthmdCoreException.FixtureTooLarge -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.FIXTURE_TOO_LARGE,
            "fixture exceeds the size limit",
            this,
        )
        is HealthmdCoreException.FixtureDigestMismatch -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.FIXTURE_DIGEST_MISMATCH,
            "fixture digest does not match",
            this,
        )
        is HealthmdCoreException.InvalidFixture -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.INVALID_FIXTURE,
            "fixture envelope is invalid",
            this,
        )
        is HealthmdCoreException.NonCanonicalFixture -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.NON_CANONICAL_FIXTURE,
            "fixture bytes are not canonical",
            this,
        )
        is HealthmdCoreException.UnsupportedFixtureFormatVersion -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.UNSUPPORTED_FIXTURE_FORMAT_VERSION,
            "fixture format version is unsupported",
            this,
        )
        is HealthmdCoreException.UnsupportedSemanticInputVersion -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.UNSUPPORTED_SEMANTIC_INPUT_VERSION,
            "semantic input version is unsupported",
            this,
        )
        is HealthmdCoreException.UnsupportedRegistryVersion -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.UNSUPPORTED_REGISTRY_VERSION,
            "registry version is unsupported",
            this,
        )
        is HealthmdCoreException.UnsupportedPersistedStateVersion -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.UNSUPPORTED_PERSISTED_STATE_VERSION,
            "persisted-state version is unsupported",
            this,
        )
        is HealthmdCoreException.InvalidRegistry -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.INVALID_REGISTRY,
            "metric registry is invalid",
            this,
        )
        is HealthmdCoreException.UnsupportedRegistryProfile -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.UNSUPPORTED_REGISTRY_PROFILE,
            "metric registry profile is unsupported",
            this,
        )
        is HealthmdCoreException.SemanticConfigTooLarge -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.SEMANTIC_CONFIG_TOO_LARGE,
            "semantic configuration exceeds the size limit",
            this,
        )
        is HealthmdCoreException.InvalidSemanticConfig -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.INVALID_SEMANTIC_CONFIG,
            "semantic configuration is invalid",
            this,
        )
        is HealthmdCoreException.SemanticBatchTooLarge -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.SEMANTIC_BATCH_TOO_LARGE,
            "semantic batch exceeds the size limit",
            this,
        )
        is HealthmdCoreException.InvalidSemanticBatch -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.INVALID_SEMANTIC_BATCH,
            "semantic batch is invalid",
            this,
        )
        is HealthmdCoreException.SemanticLimitExceeded -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.SEMANTIC_LIMIT_EXCEEDED,
            "semantic session exceeds a limit",
            this,
        )
        is HealthmdCoreException.SemanticSequenceInvalid -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.SEMANTIC_SEQUENCE_INVALID,
            "semantic input sequence is invalid",
            this,
        )
        is HealthmdCoreException.SemanticSessionTerminal -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.SEMANTIC_SESSION_TERMINAL,
            "semantic session is terminal",
            this,
        )
        is HealthmdCoreException.UnsupportedSemanticOperation -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.UNSUPPORTED_SEMANTIC_OPERATION,
            "semantic operation is unsupported for the profile",
            this,
        )
        is HealthmdCoreException.InternalPanic -> HealthMdCoreServiceException(
            HealthMdCoreErrorCode.INTERNAL_PANIC,
            "shared core failed internally",
            this,
        )
    }

private fun HealthmdRenderException.toRenderServiceException(): HealthMdRenderServiceException =
    HealthMdRenderServiceException(
        when (this) {
            is HealthmdRenderException.ConfigTooLarge -> HealthMdRenderErrorCode.CONFIG_TOO_LARGE
            is HealthmdRenderException.InvalidConfig -> HealthMdRenderErrorCode.INVALID_CONFIG
            is HealthmdRenderException.SemanticResultTooLarge -> HealthMdRenderErrorCode.SEMANTIC_RESULT_TOO_LARGE
            is HealthmdRenderException.InvalidSemanticResult -> HealthMdRenderErrorCode.INVALID_SEMANTIC_RESULT
            is HealthmdRenderException.UnsupportedRenderInputVersion -> HealthMdRenderErrorCode.UNSUPPORTED_RENDER_INPUT_VERSION
            is HealthmdRenderException.UnsupportedArtifactPlanVersion -> HealthMdRenderErrorCode.UNSUPPORTED_ARTIFACT_PLAN_VERSION
            is HealthmdRenderException.UnsupportedProfileRevision -> HealthMdRenderErrorCode.UNSUPPORTED_PROFILE_REVISION
            is HealthmdRenderException.BatchTooLarge -> HealthMdRenderErrorCode.BATCH_TOO_LARGE
            is HealthmdRenderException.InvalidBatch -> HealthMdRenderErrorCode.INVALID_BATCH
            is HealthmdRenderException.SequenceInvalid -> HealthMdRenderErrorCode.SEQUENCE_INVALID
            is HealthmdRenderException.LimitExceeded -> HealthMdRenderErrorCode.LIMIT_EXCEEDED
            is HealthmdRenderException.PresentationMismatch -> HealthMdRenderErrorCode.PRESENTATION_MISMATCH
            is HealthmdRenderException.ExtensionNotRetained -> HealthMdRenderErrorCode.EXTENSION_NOT_RETAINED
            is HealthmdRenderException.ExtensionSelectionInvalid -> HealthMdRenderErrorCode.EXTENSION_SELECTION_INVALID
            is HealthmdRenderException.UnsupportedOperation -> HealthMdRenderErrorCode.UNSUPPORTED_OPERATION
            is HealthmdRenderException.InvalidPath -> HealthMdRenderErrorCode.INVALID_PATH
            is HealthmdRenderException.PathCollision -> HealthMdRenderErrorCode.PATH_COLLISION
            is HealthmdRenderException.InvalidArtifact -> HealthMdRenderErrorCode.INVALID_ARTIFACT
            is HealthmdRenderException.ArtifactTooLarge -> HealthMdRenderErrorCode.ARTIFACT_TOO_LARGE
            is HealthmdRenderException.ArtifactLimitExceeded -> HealthMdRenderErrorCode.ARTIFACT_LIMIT_EXCEEDED
            is HealthmdRenderException.InlineOutputTooLarge -> HealthMdRenderErrorCode.INLINE_OUTPUT_TOO_LARGE
            is HealthmdRenderException.SessionTerminal -> HealthMdRenderErrorCode.SESSION_TERMINAL
            is HealthmdRenderException.Cancelled -> HealthMdRenderErrorCode.CANCELLED
            is HealthmdRenderException.InvalidStreamItem -> HealthMdRenderErrorCode.INVALID_STREAM_ITEM
            is HealthmdRenderException.StreamItemTooLarge -> HealthMdRenderErrorCode.STREAM_ITEM_TOO_LARGE
            is HealthmdRenderException.StreamTooLarge -> HealthMdRenderErrorCode.STREAM_TOO_LARGE
            is HealthmdRenderException.StreamSequenceInvalid -> HealthMdRenderErrorCode.STREAM_SEQUENCE_INVALID
            is HealthmdRenderException.StreamTerminal -> HealthMdRenderErrorCode.STREAM_TERMINAL
            is HealthmdRenderException.SerializationFailed -> HealthMdRenderErrorCode.SERIALIZATION_FAILED
            is HealthmdRenderException.InternalPanic -> HealthMdRenderErrorCode.INTERNAL_PANIC
        },
        this,
    )
