import Foundation

/// Neutral hash input for one exact generated-file partition. Not a wire message, committed
/// journal, authority or proof of a host write. Consumers must validate original base/v4 metadata.
public struct AgentBridgeTransferFrontierPartition: Codable, Equatable, Sendable, BridgeValueCodable {
    public let partitionIndex: Int64
    public let transferID: AgentBridgeUUID
    public let artifactID: AgentBridgeUUID
    public let artifactOffset: Int64
    public let byteCount: Int64
    public let chunkCount: Int64
    public let sha256: AgentBridgeDigest

    public init(partitionIndex: Int64, transferID: AgentBridgeUUID, artifactID: AgentBridgeUUID,
        artifactOffset: Int64, byteCount: Int64, chunkCount: Int64, sha256: AgentBridgeDigest) throws {
        guard (0..<2_147_483_647).contains(partitionIndex), (0...67_108_864).contains(byteCount),
              (0...128).contains(chunkCount), artifactOffset >= 0,
              artifactOffset <= 1_099_511_627_776 - byteCount else { throw AgentBridgeValidationError.invalidRequest }
        self.partitionIndex = partitionIndex; self.transferID = transferID; self.artifactID = artifactID
        self.artifactOffset = artifactOffset; self.byteCount = byteCount; self.chunkCount = chunkCount; self.sha256 = sha256
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["partition_index", "transfer_id", "artifact_id", "artifact_offset", "byte_count", "chunk_count", "sha256"])
        try self.init(partitionIndex: o.int("partition_index"), transferID: o.value("transfer_id"), artifactID: o.value("artifact_id"),
            artifactOffset: o.int("artifact_offset"), byteCount: o.int("byte_count"), chunkCount: o.int("chunk_count"), sha256: o.value("sha256"))
    }
    var bridgeJSON: BridgeJSON { .object([("partition_index", .int(partitionIndex)), ("transfer_id", transferID.bridgeJSON),
        ("artifact_id", artifactID.bridgeJSON), ("artifact_offset", .int(artifactOffset)), ("byte_count", .int(byteCount)),
        ("chunk_count", .int(chunkCount)), ("sha256", sha256.bridgeJSON)]) }
}

extension AgentBridgeSemantics {
    /// Frontier1 of an empty post-manifest prefix. Pre-capture accepted receipts still use zero
    /// digests; this seed is not evidence of capture, grant issuance or a durable commit.
    static func transferFrontierSeed(jobID: AgentBridgeUUID, requestSHA256: AgentBridgeDigest,
        manifestSHA256: AgentBridgeDigest, sessionID: AgentBridgeUUID) throws -> AgentBridgeDigest {
        try digest(.object([("schema", .string("healthmd.agent_transfer_frontier_seed")), ("schema_version", .int(1)),
            ("job_id", jobID.bridgeJSON), ("request_sha256", requestSHA256.bridgeJSON),
            ("manifest_sha256", manifestSHA256.bridgeJSON), ("session_id", sessionID.bridgeJSON)]))
    }
    /// Caller supplies its trusted/recomputed prefix, never an incoming resume claim as authority.
    static func transferFrontierStep(previous: AgentBridgeDigest, committedPartitionCount: Int64,
        partition: AgentBridgeTransferFrontierPartition) throws -> AgentBridgeDigest {
        guard (0..<2_147_483_647).contains(committedPartitionCount) else { throw AgentBridgeValidationError.invalidRequest }
        guard partition.partitionIndex == committedPartitionCount else { throw AgentBridgeValidationError.bindingChanged }
        return try digest(.object([("schema", .string("healthmd.agent_transfer_frontier_step")), ("schema_version", .int(1)),
            ("previous_frontier_sha256", previous.bridgeJSON), ("partition", partition.bridgeJSON)]))
    }
}

/// A computed prefix, not a journal or commit receipt. Its count/digest cannot be installed from
/// caller JSON: recovery must recompute the original descriptors and compare the trusted journal.
public struct AgentBridgeTransferFrontier: Equatable, Sendable {
    public let committedPartitionCount: Int64
    public let sha256: AgentBridgeDigest
    public init(jobID: AgentBridgeUUID, requestSHA256: AgentBridgeDigest,
        manifestSHA256: AgentBridgeDigest, sessionID: AgentBridgeUUID) throws {
        committedPartitionCount = 0
        sha256 = try AgentBridgeSemantics.transferFrontierSeed(jobID: jobID, requestSHA256: requestSHA256,
            manifestSHA256: manifestSHA256, sessionID: sessionID)
    }
    private init(count: Int64, digest: AgentBridgeDigest) { committedPartitionCount = count; sha256 = digest }
    public func appending(_ partition: AgentBridgeTransferFrontierPartition) throws -> Self {
        let digest = try AgentBridgeSemantics.transferFrontierStep(previous: sha256,
            committedPartitionCount: committedPartitionCount, partition: partition)
        return .init(count: committedPartitionCount + 1, digest: digest)
    }
}
