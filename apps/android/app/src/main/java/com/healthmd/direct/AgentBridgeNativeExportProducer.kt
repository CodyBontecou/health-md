package com.healthmd.direct

import kotlinx.coroutines.job
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.direct.protocol.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import java.nio.ByteBuffer
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.CancellationException

/** Owned base-v2 bytes and metadata. Neither this value nor its descriptor grants authority. */
internal class AgentBridgeNativePreparedFile(val manifest: ArtifactManifest, private val artifact: com.healthmd.domain.exportengine.ExportArtifactPlanItem) {
    val content: ByteArray get() = artifact.content
}

/** All approved days cross-checked against v4 and unchanged base-v2 metadata. */
internal class AgentBridgeNativePreparedExport private constructor(val requestSha256: String,
    days: List<AgentBridgeNativeRenderedDay>, val totalByteCount: ULong, publicArtifactIDs: Map<String, String>,
    manifestCanonical: ByteArray, baseFiles: List<AgentBridgeNativePreparedFile>) {
    val days: List<AgentBridgeNativeRenderedDay> = java.util.Collections.unmodifiableList(ArrayList(days))
    private val manifestBytes = manifestCanonical.copyOf()
    val manifestCanonical: ByteArray get() = manifestBytes.copyOf()
    val publicArtifactIDs: Map<String, String> = java.util.Collections.unmodifiableMap(LinkedHashMap(publicArtifactIDs))
    val baseFiles: List<AgentBridgeNativePreparedFile> = java.util.Collections.unmodifiableList(ArrayList(baseFiles))

    companion object {
        /** Pure adapter, never a v4-to-v2 request conversion. Installed senders still require
         * the original native owner and fresh fences at every bounded write. */
        fun make(request: AgentBridgeExecuteRequest, days: List<AgentBridgeNativeRenderedDay>,
            totalByteCount: ULong, publicArtifactIDs: Map<String, String>, manifestCanonical: ByteArray): AgentBridgeNativePreparedExport {
            val fingerprint = AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request))
            val manifest = AgentBridgeCodec.decode(manifestCanonical) as? AgentBridgeArtifactManifest ?: invalid()
            if (!AgentBridgeCodec.encode(manifest).contentEquals(manifestCanonical) || manifest.jobId != request.jobId ||
                manifest.requestSha256 != fingerprint || manifest.binding != AgentBridgeValidation.bindingFor(request.plan) ||
                manifest.captureStatus != AgentBridgeArtifactManifestCaptureStatus.COMPLETE || days.isEmpty() || days.size > 4096 ||
                manifest.artifacts.size != days.size || days.map { it.day }.toSet().size != days.size ||
                publicArtifactIDs.keys != days.map { it.day }.toSet() || publicArtifactIDs.values.toSet().size != days.size) invalid()
            // Bind the complete ordered set to the ORIGINAL plan as well as to each other.
            val plan = request.plan as? AgentBridgeGeneratedPlan ?: invalid()
            val range = (plan.resolvedDates as? AgentBridgeDatesExact)?.range ?: invalid()
            val first = java.time.LocalDate.parse(range.startDate)
            val count = java.time.temporal.ChronoUnit.DAYS.between(first, java.time.LocalDate.parse(range.endDate)) + 1
            if (count != days.size.toLong() || days.withIndex().any { (index, day) -> day.day != first.plusDays(index.toLong()).toString() } ||
                manifest.artifacts.map { it.relativePath } != plan.predictedPaths) invalid()
            var total = 0uL
            val files = manifest.artifacts.zip(days).map { (item, day) ->
                val bytes = day.artifact.content
                if (item.artifactId != publicArtifactIDs[day.day] || item.relativePath != day.artifact.relativePath || day.artifact.mediaType != "application/json" ||
                    day.artifact.writeMode != com.healthmd.domain.exportengine.ExportArtifactWriteMode.overwrite ||
                    item.mediaType != AgentBridgeArtifactMediaType.APPLICATION_JSON || item.profile != AgentBridgeArtifactProfile.ANDROID_FROZEN_V4 ||
                    item.writeMode != AgentBridgeWriteMode.OVERWRITE || item.byteCount != bytes.size.toLong() ||
                    item.byteCount.toULong() != day.artifact.byteCount || item.sha256 != day.artifact.sha256 ||
                    AgentBridgeCodec.sha256(bytes) != item.sha256 || bytes.isEmpty() || total + bytes.size.toULong() > 64uL * 1024uL * 1024uL) invalid()
                total += bytes.size.toULong()
                AgentBridgeNativePreparedFile(ArtifactManifest(jobId = request.jobId, artifactId = item.artifactId,
                    kind = ArtifactKind.GENERATED_FILE, schema = ArtifactSchema("healthmd.generated-files", 1),
                    mediaType = "application/json", byteCount = item.byteCount, sha256 = item.sha256,
                    relativePath = item.relativePath, writeMode = FileWriteMode.OVERWRITE), day.artifact)
            }
            if (total != totalByteCount) invalid()
            return AgentBridgeNativePreparedExport(fingerprint, days, total, publicArtifactIDs, manifestCanonical, files)
        }
        private fun invalid(): Nothing = throw AgentBridgeNativeRenderException(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
    }
}

/** Private metadata1, pinned by signed original-job progress. Not a sender/frontier/receipt. */
@Serializable
internal data class AgentBridgeNativeTransferCheckpoint(val version: Int, val requestContract: String,
    val requestSHA256: String, val manifestSHA256: String, val sessionID: String, private val partitionIDs: List<String>,
    val protocolVersion: Int, val binaryFrameVersion: Int, val partitionTargetBytes: Long,
    val maximumInFlightChunks: Int, val createdAt: String, val expiresAt: String) {
    fun canonical(): ByteArray = AgentBridgeCodec.canonicalize(Json.encodeToString(this).toByteArray())
    fun negotiation() = TransferNegotiation(protocolVersion, binaryFrameVersion, partitionTargetBytes, maximumInFlightChunks)
    fun validate(requestSHA256: String, manifestSHA256: String, createdAt: String, expiresAt: String, artifactIDs: List<String>): List<String> {
        if (version != 1 || requestContract != "healthmd.agent_execute_request/1" || this.requestSHA256 != requestSHA256 ||
            this.manifestSHA256 != manifestSHA256 || this.createdAt != createdAt || this.expiresAt != expiresAt ||
            !validLimits(protocolVersion, binaryFrameVersion, partitionTargetBytes, maximumInFlightChunks) || artifactIDs.size !in 1..4096 || !v4(sessionID)) invalid()
        if (partitionIDs.size != (artifactIDs.size * 16 + 16 * 1024 - 1) / (16 * 1024)) invalid()
        val bytes = ByteBuffer.allocate(artifactIDs.size * 16)
        partitionIDs.forEachIndexed { index, encoded ->
            val chunk = Base64.getDecoder().decode(encoded)
            if (chunk.size != minOf(16 * 1024, artifactIDs.size * 16 - index * 16 * 1024) || Base64.getEncoder().encodeToString(chunk) != encoded) invalid()
            bytes.put(chunk)
        }
        val buffer = ByteBuffer.wrap(bytes.array())
        val ids = artifactIDs.map { UUID(buffer.long, buffer.long).toString().also { if (!v4(it)) invalid() } }
        val all = ids + artifactIDs + sessionID
        if (all.toSet().size != all.size) invalid()
        return java.util.Collections.unmodifiableList(ids)
    }
    companion object {
        const val MAXIMUM_BYTES = 128 * 1024
        fun detachPeerCapabilities(value: TransferCapabilities?): TransferCapabilities? = value?.copy(
            protocolVersions = java.util.Collections.unmodifiableList(ArrayList(value.protocolVersions)),
            binaryFrameVersions = java.util.Collections.unmodifiableList(ArrayList(value.binaryFrameVersions)))
        /** Check support for the original limits, not equality with a new preferred negotiation. */
        fun requireSupported(value: TransferNegotiation, peer: TransferCapabilities?) {
            validateNegotiation(value)
            val local = TransferCapabilities()
            if (peer == null || value.protocolVersion !in local.protocolVersions || value.binaryFrameVersion !in local.binaryFrameVersions ||
                value.protocolVersion !in peer.protocolVersions || value.binaryFrameVersion !in peer.binaryFrameVersions ||
                peer.minimumPartitionBytes <= 0 || peer.minimumPartitionBytes > peer.preferredPartitionBytes ||
                peer.preferredPartitionBytes > peer.maximumPartitionBytes ||
                value.partitionTargetBytes !in peer.minimumPartitionBytes..peer.maximumPartitionBytes ||
                value.partitionTargetBytes !in local.minimumPartitionBytes..local.maximumPartitionBytes ||
                value.maximumInFlightChunks > peer.maximumInFlightChunks || value.maximumInFlightChunks > local.maximumInFlightChunks)
                throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
        private fun validLimits(protocol: Int, binary: Int, target: Long, window: Int) =
            protocol == 1 && binary == 1 && target in MINIMUM_PARTITION_BYTES..MAXIMUM_PARTITION_BYTES && window in 1..8
        fun validateNegotiation(value: TransferNegotiation) {
            if (!validLimits(value.protocolVersion, value.binaryFrameVersion, value.partitionTargetBytes, value.maximumInFlightChunks))
                throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
        fun create(requestSHA256: String, manifestSHA256: String, createdAt: String, expiresAt: String,
            count: Int, negotiation: TransferNegotiation): AgentBridgeNativeTransferCheckpoint {
            validateNegotiation(negotiation)
            if (count !in 1..4096) throw AgentBridgeException(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
            val buffer = ByteBuffer.allocate(count * 16)
            repeat(count) { val id = UUID.randomUUID(); buffer.putLong(id.mostSignificantBits); buffer.putLong(id.leastSignificantBits) }
            val bytes = buffer.array()
            val chunks = java.util.Collections.unmodifiableList((0 until bytes.size step 16 * 1024).map { offset ->
                Base64.getEncoder().encodeToString(bytes.copyOfRange(offset, minOf(offset + 16 * 1024, bytes.size))) })
            return AgentBridgeNativeTransferCheckpoint(1, "healthmd.agent_execute_request/1", requestSHA256, manifestSHA256,
                UUID.randomUUID().toString(), chunks, negotiation.protocolVersion,
                negotiation.binaryFrameVersion, negotiation.partitionTargetBytes, negotiation.maximumInFlightChunks, createdAt, expiresAt)
        }
        fun decode(bytes: ByteArray): AgentBridgeNativeTransferCheckpoint {
            if (bytes.size > MAXIMUM_BYTES || !AgentBridgeCodec.canonicalize(bytes).contentEquals(bytes)) invalid()
            return Json.decodeFromString<AgentBridgeNativeTransferCheckpoint>(bytes.decodeToString()).also { if (!it.canonical().contentEquals(bytes)) invalid() }
        }
        private fun v4(value: String): Boolean = try { val id = UUID.fromString(value); id.toString() == value && id.version() == 4 && id.variant() == 2 } catch (_: IllegalArgumentException) { false }
        private fun invalid(): Nothing = throw AgentBridgeException(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED)
    }
}

/** Retained base session/partitions only. New sender compatibility and every live native fence
 * remain required; this metadata value cannot authorize a send or declare completion. */
internal class AgentBridgeNativePreparedTransfer private constructor(val export: AgentBridgeNativePreparedExport,
    val session: TransferSession, partitions: List<TransferPartition>, val maximumInFlightChunks: Int, checkpointCanonical: ByteArray) {
    val partitions: List<TransferPartition> = java.util.Collections.unmodifiableList(ArrayList(partitions))
    private val checkpointBytes = checkpointCanonical.copyOf()
    val checkpointCanonical: ByteArray get() = checkpointBytes.copyOf()
    companion object {
        fun make(request: AgentBridgeExecuteRequest, export: AgentBridgeNativePreparedExport, checkpointCanonical: ByteArray): AgentBridgeNativePreparedTransfer {
            val checkpoint = AgentBridgeNativeTransferCheckpoint.decode(checkpointCanonical)
            val ids = checkpoint.validate(export.requestSha256, AgentBridgeCodec.sha256(export.manifestCanonical),
                checkpoint.createdAt, checkpoint.expiresAt, export.baseFiles.map { it.manifest.artifactId })
            val peer = (request.plan as? AgentBridgeGeneratedPlan)?.intent?.peer ?: invalid()
            if (export.requestSha256 != AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request)) ||
                java.time.Duration.between(java.time.Instant.parse(checkpoint.createdAt), java.time.Instant.parse(checkpoint.expiresAt)) != java.time.Duration.ofSeconds(JOB_LIFETIME_SECONDS)) invalid()
            val session = TransferSession(checkpoint.sessionID, request.jobId, export.requestSha256,
                PeerBinding(peer.sourceInstallationId, peer.hostInstallationId), checkpoint.partitionTargetBytes, checkpoint.createdAt)
            var previous: String? = null
            val partitions = export.baseFiles.mapIndexed { index, file ->
                val item = file.manifest
                if (item.byteCount !in 1..MAXIMUM_CHUNK_BYTES.toLong()) throw AgentBridgeException(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
                TransferPartition(index.toLong(), ids[index], item.artifactId, 0, item.byteCount, 1, item.sha256, previous).also { previous = item.sha256 }
            }
            return AgentBridgeNativePreparedTransfer(export, session, partitions, checkpoint.maximumInFlightChunks, checkpointCanonical)
        }
        private fun invalid(): Nothing = throw AgentBridgeException(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED)
    }
}

internal suspend fun AgentBridgeNativePlanningSession.prepareExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedExport = withCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepare(request, manager, context, renderer)
}

/** Byte carriage only; does not publish a v4 completion receipt or source frontier. */
internal suspend fun AgentBridgeNativePlanningSession.sendTransferExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, retained: Boolean = false,
    renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()) {
    transmitTransfer(request, retained) { context -> AgentBridgeNativeExportProducer.prepareTransfer(request, manager, context, renderer) }
}

/** Complete confirmation remains in the original native capture/transfer owner. */
internal suspend fun AgentBridgeNativePlanningSession.sendExecutionExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, retained: Boolean = false,
    renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()) {
    transmitTransfer(request, retained, confirmCompletion = true) { context -> AgentBridgeNativeExportProducer.prepareTransfer(request, manager, context, renderer) }
}

/** The Execute comes only from the signed native job. Retained preparation reuses captured
 * bytes and cannot turn the Resume envelope into fresh SDK capture authority. */
internal suspend fun AgentBridgeNativePlanningSession.sendResumedExecutionExport(resume: AgentBridgeResumeRequest,
    manager: HealthConnectManager, acknowledgement: TransferPartitionAcknowledgement? = null,
    renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()) {
    transmitResumedTransfer(resume, acknowledgement, confirmCompletion = true) { request, context ->
        AgentBridgeNativeExportProducer.prepareTransfer(request, manager, context, renderer)
    }
}

/** SDK ownership comes from native composition; no wire value selects a manager or renderer. */
internal suspend fun AgentBridgeNativePlanningSession.receiveAndHandleExecutionNext(channel: DirectSecureChannel,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()): ReceivedAgentBridgePayload? =
    receiveAndHandleResumedNext(channel, kotlinx.coroutines.currentCoroutineContext().job) { request, context ->
        AgentBridgeNativeExportProducer.prepareTransfer(request, manager, context, renderer)
    }

internal suspend fun AgentBridgeNativePlanningSession.prepareTransferExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedTransfer = withCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepareTransfer(request, manager, context, renderer)
}
internal suspend fun AgentBridgeNativePlanningSession.prepareRetainedTransferExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedTransfer = withRetainedCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepareTransfer(request, manager, context, renderer)
}

/** Explicit retained recovery; failed new execution never falls back to this operation. */
internal suspend fun AgentBridgeNativePlanningSession.prepareRetainedExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedExport = withRetainedCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepare(request, manager, context, renderer)
}

private object AgentBridgeNativeExportProducer {
    suspend fun prepareTransfer(request: AgentBridgeExecuteRequest, manager: HealthConnectManager, context: AgentBridgeNativeCaptureContext,
        renderer: AgentBridgeNativeDayRenderer): AgentBridgeNativePreparedTransfer {
        try {
            val prepared = prepare(request, manager, context, renderer, requireTransfer = true)
            val result = AgentBridgeNativePreparedTransfer.make(request, prepared, context.preserveTransferPlan())
            if (context.requestFingerprintForRead() != prepared.requestSha256) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            return result
        } catch (failure: Throwable) { context.invalidate(); throw failure }
    }
    suspend fun prepare(request: AgentBridgeExecuteRequest, manager: HealthConnectManager, context: AgentBridgeNativeCaptureContext,
        renderer: AgentBridgeNativeDayRenderer, requireTransfer: Boolean = false): AgentBridgeNativePreparedExport {
        try {
            val resolution = context.begin()
            if (requireTransfer) context.transferNegotiationForRead()
            val fingerprint = context.requestFingerprintForRead()
            val approved = resolution.requestedDays
            if (approved.isEmpty() || approved.size > 4096 || approved.toSet().size != approved.size ||
                resolution.predictedRelativePaths.size != approved.size) fail(AgentBridgeNativeRenderFailure.INVALID_INPUT)
            val days = mutableListOf<AgentBridgeNativeRenderedDay>()
            var total = 0uL
            val limit = 64uL * 1024uL * 1024uL
            approved.forEachIndexed { index, day ->
                val result = renderer.capture(day, manager, context)
                if (result.day != day || result.artifact.relativePath != resolution.predictedRelativePaths[index] ||
                    result.artifact.byteCount > limit || total > limit - result.artifact.byteCount ||
                    days.firstOrNull()?.let { it.pin != result.pin } == true) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
                total += result.artifact.byteCount
                days += result
            }
            if (days.size != approved.size || days.map { it.artifact.artifactId }.toSet().size != days.size ||
                context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val publicIDs = context.bindPublicArtifactIDs()
            if (publicIDs.keys != approved.toSet() || context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val manifest = context.preserveManifest()
            if (context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val prepared = AgentBridgeNativePreparedExport.make(request, days, total, publicIDs, manifest)
            if (prepared.requestSha256 != fingerprint || context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            return prepared
        } catch (failure: Throwable) {
            context.invalidate()
            if (failure is CancellationException || failure is AgentBridgeException || failure is AgentBridgeNativeRenderException ||
                failure is VirtualMachineError || failure is ThreadDeath) throw failure
            fail(AgentBridgeNativeRenderFailure.RENDER_FAILED)
        }
    }
    private fun fail(code: AgentBridgeNativeRenderFailure): Nothing = throw AgentBridgeNativeRenderException(code)
}
