package com.healthmd.direct.protocol

import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
data class PreparedTransfer(
    val accepted: ExportAccepted,
    val session: TransferSession,
    val manifests: List<ArtifactManifest>,
    val partitions: List<TransferPartition>,
    val artifactPaths: Map<String, String>,
)

object TransferPlanBuilder {
    fun build(
        accepted: ExportAccepted,
        manifests: List<ArtifactManifest>,
        artifactFiles: Map<String, File>,
        partitionTargetBytes: Long = PREFERRED_PARTITION_BYTES,
        createdAt: String,
        sessionId: String = UUID.randomUUID().toString(),
        checkCancellation: () -> Unit = {},
    ): PreparedTransfer {
        checkCancellation()
        require(partitionTargetBytes in MINIMUM_PARTITION_BYTES..MAXIMUM_PARTITION_BYTES)
        require(manifests.isNotEmpty())
        require(manifests.map { it.artifactId }.toSet().size == manifests.size)
        val paths = mutableMapOf<String, String>()
        val partitions = mutableListOf<TransferPartition>()
        var previousSha256: String? = null
        var partitionIndex = 0L
        manifests.forEach { manifest ->
            checkCancellation()
            val file = requireNotNull(artifactFiles[manifest.artifactId]) {
                "Artifact file is missing."
            }
            require(file.isFile && file.length() == manifest.byteCount)
            require(sha256(file, checkCancellation) == manifest.sha256)
            paths[manifest.artifactId] = file.absolutePath
            var offset = 0L
            while (offset < manifest.byteCount) {
                checkCancellation()
                val byteCount = minOf(partitionTargetBytes, manifest.byteCount - offset)
                val digest = sha256(file, offset, byteCount, checkCancellation)
                partitions += TransferPartition(
                    index = partitionIndex,
                    transferId = UUID.randomUUID().toString(),
                    artifactId = manifest.artifactId,
                    artifactOffset = offset,
                    byteCount = byteCount,
                    chunkCount = (byteCount + MAXIMUM_CHUNK_BYTES - 1) / MAXIMUM_CHUNK_BYTES,
                    sha256 = digest,
                    previousSha256 = previousSha256,
                )
                previousSha256 = digest
                partitionIndex += 1
                offset += byteCount
            }
        }
        return PreparedTransfer(
            accepted = accepted,
            session = TransferSession(
                sessionId = sessionId,
                jobId = accepted.jobId,
                requestFingerprint = accepted.requestFingerprint,
                peerBinding = accepted.peerBinding,
                partitionTargetBytes = partitionTargetBytes,
                createdAt = createdAt,
            ),
            manifests = manifests,
            partitions = partitions,
            artifactPaths = paths,
        )
    }

    private fun sha256(file: File, checkCancellation: () -> Unit): String =
        file.inputStream().buffered().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(128 * 1024)
        while (true) {
            checkCancellation()
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
        digest.digest().toHex()
    }

    private fun sha256(
        file: File,
        offset: Long,
        byteCount: Long,
        checkCancellation: () -> Unit,
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        RandomAccessFile(file, "r").use { input ->
            input.seek(offset)
            val buffer = ByteArray(128 * 1024)
            var remaining = byteCount
            while (remaining > 0) {
                checkCancellation()
                val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                check(count > 0) { "Artifact ended before its declared partition." }
                digest.update(buffer, 0, count)
                remaining -= count
            }
        }
        return digest.digest().toHex()
    }
}

class ArtifactTransferClient(
    private val channel: DirectSecureChannel,
) {
    fun transfer(
        plan: PreparedTransfer,
        onProgress: (committedBytes: Long, totalBytes: Long) -> Unit = { _, _ -> },
        beforeCompletionConfirmed: () -> Unit = {},
        checkCancellation: () -> Unit = {},
        sendAccepted: Boolean = true,
    ): TransferFinalAcknowledgement {
        checkCancellation()
        validatePlan(plan)
        if (sendAccepted) {
            channel.sendV2("export_accepted", ExportAccepted.serializer(), plan.accepted)
        }
        channel.sendV2("transfer_session", TransferSession.serializer(), plan.session)
        plan.manifests.forEach { manifest ->
            checkCancellation()
            channel.sendV2("artifact_manifest", ArtifactManifest.serializer(), manifest)
        }

        val totalBytes = plan.partitions.sumOf { it.byteCount }
        var committedBytes = 0L
        plan.partitions.forEach { partition ->
            checkCancellation()
            channel.sendV2(
                "transfer_open",
                TransferOpen.serializer(),
                TransferOpen(plan.session, partition),
            )
            val disposition = await(
                expectedType = "transfer_disposition",
                deserializer = TransferDisposition.serializer(),
                jobId = plan.accepted.jobId,
            )
            require(disposition.sessionId == plan.session.sessionId)
            require(disposition.partitionIndex == partition.index)
            require(disposition.partitionSha256 == partition.sha256)
            when (disposition.disposition) {
                TransferDispositionKind.REJECTED -> error(
                    disposition.message ?: "The CLI rejected an export partition.",
                )
                TransferDispositionKind.ALREADY_COMMITTED -> Unit
                TransferDispositionKind.NEEDED -> sendPartition(plan, partition, checkCancellation)
            }
            if (disposition.disposition == TransferDispositionKind.NEEDED) {
                channel.sendV2(
                    "transfer_partition_complete",
                    TransferPartitionComplete.serializer(),
                    TransferPartitionComplete(
                        sessionId = plan.session.sessionId,
                        jobId = plan.accepted.jobId,
                        partitionIndex = partition.index,
                        transferId = partition.transferId,
                        partitionSha256 = partition.sha256,
                    ),
                )
                val acknowledgement = await(
                    expectedType = "transfer_partition_acknowledgement",
                    deserializer = TransferPartitionAcknowledgement.serializer(),
                    jobId = plan.accepted.jobId,
                )
                require(acknowledgement.accepted)
                require(acknowledgement.sessionId == plan.session.sessionId)
                require(acknowledgement.partitionIndex == partition.index)
                require(acknowledgement.transferId == partition.transferId)
                require(acknowledgement.partitionSha256 == partition.sha256)
            }
            committedBytes += partition.byteCount
            onProgress(committedBytes, totalBytes)
        }

        val finalize = TransferFinalize(
            sessionId = plan.session.sessionId,
            jobId = plan.accepted.jobId,
            requestFingerprint = plan.session.requestFingerprint,
            totalPartitions = plan.partitions.size.toLong(),
            totalBytes = totalBytes,
            finalPartitionSha256 = plan.partitions.lastOrNull()?.sha256,
        )
        channel.sendV2("transfer_finalize", TransferFinalize.serializer(), finalize)
        val acknowledgement = await(
            expectedType = "transfer_final_acknowledgement",
            deserializer = TransferFinalAcknowledgement.serializer(),
            jobId = plan.accepted.jobId,
        )
        require(acknowledgement.accepted)
        require(acknowledgement.sessionId == plan.session.sessionId)
        require(acknowledgement.totalPartitions == finalize.totalPartitions)
        require(acknowledgement.totalBytes == finalize.totalBytes)
        require(acknowledgement.finalPartitionSha256 == finalize.finalPartitionSha256)
        checkCancellation()
        beforeCompletionConfirmed()
        checkCancellation()
        channel.sendV2(
            "completion_confirmed",
            JobPayload.serializer(),
            JobPayload(plan.accepted.jobId),
        )
        return acknowledgement
    }

    private fun sendPartition(
        plan: PreparedTransfer,
        partition: TransferPartition,
        checkCancellation: () -> Unit,
    ) {
        val file = File(requireNotNull(plan.artifactPaths[partition.artifactId]))
        RandomAccessFile(file, "r").use { input ->
            input.seek(partition.artifactOffset)
            var remaining = partition.byteCount
            var sequence = 1
            while (remaining > 0) {
                checkCancellation()
                val data = ByteArray(minOf(MAXIMUM_CHUNK_BYTES.toLong(), remaining).toInt())
                input.readFully(data)
                channel.sendBinary(BinaryTransferFrame.encode(partition.transferId, sequence, data))
                val acknowledgement = await(
                    expectedType = "transfer_chunk_acknowledgement",
                    deserializer = TransferChunkAcknowledgement.serializer(),
                    jobId = plan.accepted.jobId,
                )
                require(acknowledgement.accepted)
                require(acknowledgement.transferId == partition.transferId)
                require(acknowledgement.sequence == sequence)
                require(acknowledgement.sha256 == DirectJson.sha256Hex(data))
                remaining -= data.size
                sequence += 1
            }
        }
    }

    private fun <T> await(
        expectedType: String,
        deserializer: kotlinx.serialization.DeserializationStrategy<T>,
        jobId: String,
    ): T {
        while (true) {
            val envelope = channel.receiveV2()
            when (envelope.type) {
                expectedType -> return V2Codec.decodePayload(envelope, deserializer)
                "ping" -> channel.sendV2("pong", EmptyPayload.serializer(), EmptyPayload())
                "cancel" -> {
                    val cancellation = V2Codec.decodePayload(envelope, JobPayload.serializer())
                    if (cancellation.jobId == jobId) {
                        channel.sendV2(
                            "cancel_acknowledged",
                            JobPayload.serializer(),
                            cancellation,
                        )
                        throw DirectExportCancelledException()
                    }
                }
                else -> error("The CLI sent an unexpected ${envelope.type} message.")
            }
        }
    }

    private fun validatePlan(plan: PreparedTransfer) {
        require(plan.accepted.jobId == plan.session.jobId)
        require(plan.accepted.peerBinding == plan.session.peerBinding)
        require(plan.accepted.requestFingerprint == plan.session.requestFingerprint)
        require(plan.manifests.all { it.jobId == plan.accepted.jobId })
        require(plan.partitions.map { it.index } == plan.partitions.indices.map(Int::toLong))
        require(plan.partitions.zipWithNext().all { (left, right) -> right.previousSha256 == left.sha256 })
        require(plan.partitions.firstOrNull()?.previousSha256 == null)
    }
}

@Serializable
private class EmptyPayload

class DirectExportCancelledException : Exception("The direct export was cancelled.")

private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
