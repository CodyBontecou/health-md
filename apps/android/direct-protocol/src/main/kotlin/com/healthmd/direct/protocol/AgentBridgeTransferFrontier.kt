package com.healthmd.direct.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Neutral hash input, not a wire control, permission, durable journal or host commit proof. */
@Serializable
data class AgentBridgeTransferFrontierPartition(
    @SerialName("partition_index") val partitionIndex: Long,
    @SerialName("transfer_id") val transferId: String,
    @SerialName("artifact_id") val artifactId: String,
    @SerialName("artifact_offset") val artifactOffset: Long,
    @SerialName("byte_count") val byteCount: Long,
    @SerialName("chunk_count") val chunkCount: Long,
    val sha256: String,
) {
    companion object {
        /** Raw input boundary: generated serializers alone permit quoted integer coercion. */
        fun decode(bytes: ByteArray): AgentBridgeTransferFrontierPartition = AgentBridgeCodec.sanitized {
            val value = AgentBridgeRawJson.parse(bytes)
            AgentBridgeCodec.json.decodeFromJsonElement(AgentBridgeShapes.checked(value, serializer()), value)
        }
    }

    init {
        AgentBridgeChecks.require(partitionIndex in 0 until 2_147_483_647L && byteCount in 0..67_108_864L &&
            chunkCount in 0..128L && artifactOffset >= 0 && artifactOffset <= 1_099_511_627_776L - byteCount)
        AgentBridgeTransferFrontierHash.uuid(transferId); AgentBridgeTransferFrontierHash.uuid(artifactId)
        AgentBridgeTransferFrontierHash.digest(sha256)
    }
}

/** Pure frontier1 computation. Original manifest/base metadata and durable commits remain the
 * caller's obligation. No hash result establishes current native permission or a host write. */
internal object AgentBridgeTransferFrontierHash {
    internal fun uuid(value: String) = AgentBridgeChecks.text(value, 36, 36,
        "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    internal fun digest(value: String) = AgentBridgeChecks.text(value, 64, 64, "^[0-9a-f]{64}$")

    fun seed(jobId: String, requestSha256: String, manifestSha256: String, sessionId: String): String {
        uuid(jobId); uuid(sessionId); digest(requestSha256); digest(manifestSha256)
        return AgentBridgeCodec.digest(buildJsonObject {
            put("schema", "healthmd.agent_transfer_frontier_seed"); put("schema_version", 1)
            put("job_id", jobId); put("request_sha256", requestSha256)
            put("manifest_sha256", manifestSha256); put("session_id", sessionId)
        })
    }
    /** Prefix must come from a trusted/recomputed journal, not the incoming resume request. */
    fun step(previous: String, committedPartitionCount: Long, partition: AgentBridgeTransferFrontierPartition): String {
        digest(previous)
        AgentBridgeChecks.require(committedPartitionCount in 0 until 2_147_483_647L)
        AgentBridgeChecks.require(partition.partitionIndex == committedPartitionCount, AgentBridgeErrorCode.BINDING_CHANGED)
        return AgentBridgeCodec.digest(buildJsonObject {
            put("schema", "healthmd.agent_transfer_frontier_step"); put("schema_version", 1)
            put("previous_frontier_sha256", previous)
            put("partition", AgentBridgeCodec.tree(AgentBridgeTransferFrontierPartition.serializer(), partition))
        })
    }
}

/** Computed immutable prefix only; cannot be installed from caller JSON as journal/authority. */
class AgentBridgeTransferFrontier private constructor(val committedPartitionCount: Long, val sha256: String) {
    companion object {
        fun start(jobId: String, requestSha256: String, manifestSha256: String, sessionId: String) =
            AgentBridgeTransferFrontier(0, AgentBridgeTransferFrontierHash.seed(jobId, requestSha256, manifestSha256, sessionId))
    }
    fun appending(partition: AgentBridgeTransferFrontierPartition): AgentBridgeTransferFrontier =
        AgentBridgeTransferFrontier(committedPartitionCount + 1, AgentBridgeTransferFrontierHash.step(sha256, committedPartitionCount, partition))
}
