import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust

/// Base-v1 metadata has no profile field. The canonical v4 manifest remains authoritative
/// for that metadata. These owned bytes/descriptors grant no capture or transfer authority.
nonisolated struct AgentBridgeNativePreparedFile: Sendable {
    let manifest: DirectExportFileManifest
    let content: Data
}

/// Every approved day, in frozen order, cross-checked against both public manifest grammars.
nonisolated struct AgentBridgeNativePreparedExport: Sendable {
    let requestSHA256: String
    let days: [AgentBridgeNativeRenderedDay]
    let totalByteCount: UInt64
    let publicArtifactIDs: [String: String]
    let manifestCanonical: Data
    let baseFiles: [AgentBridgeNativePreparedFile]

    /// Pure adapter, not an authority constructor. Installed senders must retain the original
    /// native owner and fence every write; this never converts a v4 request into a v1 request.
    static func make(request: AgentBridgeExecute, days: [AgentBridgeNativeRenderedDay],
        totalByteCount: UInt64, publicArtifactIDs: [String: String], manifestCanonical: Data
    ) throws -> Self {
        let fingerprint = AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request))
        let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: manifestCanonical)
        guard try AgentBridgeV4Codec.encode(manifest) == manifestCanonical,
              manifest.jobId == request.jobId, manifest.requestSha256.rawValue == fingerprint,
              manifest.binding == AgentBridgeSemantics.binding(request.plan),
              manifest.captureStatus == .complete, !days.isEmpty, days.count <= 4096,
              manifest.artifacts.count == days.count, Set(days.map(\.day)).count == days.count,
              Set(publicArtifactIDs.keys) == Set(days.map { $0.day.rawValue }),
              Set(publicArtifactIDs.values).count == days.count,
              let jobID = UUID(uuidString: request.jobId.rawValue) else {
            throw AgentBridgeNativeRenderFailure.invalidArtifact
        }
        // Compare both supplied sides with the ORIGINAL plan, not merely with one another.
        // UTC is used only for Gregorian civil-label counting; it performs no source query.
        let labels = ISO8601DateFormatter()
        guard case .exact(let range) = request.plan.resolvedDates,
              let first = labels.date(from: range.startDate.rawValue + "T00:00:00Z"),
              let last = labels.date(from: range.endDate.rawValue + "T00:00:00Z"),
              days.first?.day == range.startDate, days.last?.day == range.endDate,
              days.map({ $0.day.rawValue }) == days.map({ $0.day.rawValue }).sorted(),
              Int(last.timeIntervalSince(first) / 86_400) + 1 == days.count,
              manifest.artifacts.map(\.relativePath) == request.plan.predictedPaths else {
            throw AgentBridgeNativeRenderFailure.invalidArtifact
        }
        var files: [AgentBridgeNativePreparedFile] = []
        var total: UInt64 = 0
        for (item, day) in zip(manifest.artifacts, days) {
            let bytes = try day.artifact.content.materializedData()
            guard item.artifactId.rawValue == publicArtifactIDs[day.day.rawValue],
                  item.relativePath.rawValue == day.artifact.relativePath,
                  day.artifact.role == .file, day.artifact.mediaType == "application/json", day.artifact.writeMode == .overwrite,
                  item.mediaType == .applicationJson, item.profile == .appleV8, item.writeMode == .overwrite,
                  item.byteCount == Int64(bytes.count), item.byteCount == Int64(day.artifact.byteCount),
                  item.sha256.rawValue == day.artifact.sha256,
                  AgentBridgeV4Codec.sha256(bytes) == item.sha256.rawValue,
                  !bytes.isEmpty, bytes.count <= 64 * 1024 * 1024, total <= 64 * 1024 * 1024 - UInt64(bytes.count),
                  let fileID = UUID(uuidString: item.artifactId.rawValue) else {
                throw AgentBridgeNativeRenderFailure.invalidArtifact
            }
            total += UInt64(bytes.count)
            files.append(.init(manifest: try .init(jobID: jobID, fileID: fileID,
                relativePath: item.relativePath.rawValue, byteCount: item.byteCount,
                sha256: item.sha256.rawValue, writeMode: .overwrite), content: bytes))
        }
        guard total == totalByteCount else { throw AgentBridgeNativeRenderFailure.invalidArtifact }
        return .init(requestSHA256: fingerprint, days: days, totalByteCount: total,
            publicArtifactIDs: publicArtifactIDs, manifestCanonical: manifestCanonical, baseFiles: files)
    }
}

/// Private transfer metadata1. The signed original-job progress record pins its canonical bytes.
/// This is metadata only: sender/frontier/terminal acknowledgement are separate obligations.
nonisolated struct AgentBridgeNativeTransferCheckpoint: Codable, Sendable {
    let version: Int
    let requestContract: String
    let requestSHA256: String
    let manifestSHA256: String
    let sessionID: String
    let partitionIDs: [Data]
    let protocolVersion: Int
    let binaryFrameVersion: Int
    let partitionTargetBytes: Int64
    let maximumInFlightChunks: Int
    let createdAt: String
    let expiresAt: String
    static let maximumBytes = 128 * 1024
    var negotiation: DirectTransferNegotiation {
        .init(protocolVersion: protocolVersion, binaryFrameVersion: binaryFrameVersion,
            partitionTargetBytes: partitionTargetBytes, maximumInFlightChunks: maximumInFlightChunks)
    }
    /// Current peer support, not its newly selected preferred values, determines whether the
    /// immutable original plan can be resumed. Never rewrite retained limits to fit a reconnect.
    static func requireSupported(_ value: DirectTransferNegotiation, peer: DirectTransferCapabilities?) throws {
        try validateNegotiation(value)
        let local = DirectTransferCapabilities.current
        guard let peer, local.protocolVersions.contains(value.protocolVersion), local.binaryFrameVersions.contains(value.binaryFrameVersion),
              peer.protocolVersions.contains(value.protocolVersion),
              peer.binaryFrameVersions.contains(value.binaryFrameVersion),
              peer.minimumPartitionBytes > 0, peer.minimumPartitionBytes <= peer.preferredPartitionBytes,
              peer.preferredPartitionBytes <= peer.maximumPartitionBytes,
              (peer.minimumPartitionBytes...peer.maximumPartitionBytes).contains(value.partitionTargetBytes),
              (local.minimumPartitionBytes...local.maximumPartitionBytes).contains(value.partitionTargetBytes),
              value.maximumInFlightChunks <= peer.maximumInFlightChunks,
              value.maximumInFlightChunks <= local.maximumInFlightChunks else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
    }
    static func validateNegotiation(_ value: DirectTransferNegotiation) throws {
        guard validLimits(value.protocolVersion, value.binaryFrameVersion, value.partitionTargetBytes, value.maximumInFlightChunks) else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
    }
    private static func validLimits(_ protocolVersion: Int, _ binary: Int, _ target: Int64, _ window: Int) -> Bool {
        protocolVersion == 1 && binary == 1 && (DirectTransferLimits.minimumPartitionBytes...DirectTransferLimits.maximumPartitionBytes).contains(target) && (1...8).contains(window)
    }
    static func create(requestSHA256: String, manifestSHA256: String, createdAt: String, expiresAt: String,
        count: Int, negotiation: DirectTransferNegotiation) throws -> Self {
        try validateNegotiation(negotiation)
        guard (1...4096).contains(count) else { throw AgentBridgeValidationError.queryBudgetExceeded }
        var ids = Data()
        for _ in 0..<count { var uuid = UUID().uuid; withUnsafeBytes(of: &uuid) { ids.append(contentsOf: $0) } }
        return .init(version: 1, requestContract: "healthmd.agent_execute_request/1", requestSHA256: requestSHA256,
            manifestSHA256: manifestSHA256, sessionID: UUID().uuidString.lowercased(), partitionIDs: stride(from: 0, to: ids.count, by: 16 * 1024).map { Data(ids[$0..<min($0 + 16 * 1024, ids.count)]) },
            protocolVersion: negotiation.protocolVersion, binaryFrameVersion: negotiation.binaryFrameVersion,
            partitionTargetBytes: negotiation.partitionTargetBytes, maximumInFlightChunks: negotiation.maximumInFlightChunks,
            createdAt: createdAt, expiresAt: expiresAt)
    }
    func canonical() throws -> Data { try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(self)) }
    static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= maximumBytes, try AgentBridgeV4Codec.canonicalize(bytes) == bytes else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard try value.canonical() == bytes else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return value
    }
    func validate(requestSHA256: String, manifestSHA256: String, createdAt: String, expiresAt: String,
        artifactIDs: [String]) throws -> [UUID] {
        guard (1...4096).contains(artifactIDs.count), partitionIDs.count == (artifactIDs.count * 16 + 16 * 1024 - 1) / (16 * 1024) else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        var table = Data()
        for (index, chunk) in partitionIDs.enumerated() {
            guard chunk.count == min(16 * 1024, artifactIDs.count * 16 - index * 16 * 1024) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            table.append(chunk)
        }
        guard version == 1, requestContract == "healthmd.agent_execute_request/1",
              self.requestSHA256 == requestSHA256, self.manifestSHA256 == manifestSHA256,
              self.createdAt == createdAt, self.expiresAt == expiresAt,
              Self.validLimits(protocolVersion, binaryFrameVersion, partitionTargetBytes, maximumInFlightChunks),
              (1...4096).contains(artifactIDs.count), table.count == artifactIDs.count * 16,
              let session = UUID(uuidString: sessionID), session.uuidString.lowercased() == sessionID,
              session.uuid.6 >> 4 == 4, session.uuid.8 & 0xc0 == 0x80 else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        var ids: [UUID] = []
        for index in 0..<artifactIDs.count {
            let tuple = table.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: index * 16, as: uuid_t.self) }
            guard tuple.6 >> 4 == 4, tuple.8 & 0xc0 == 0x80 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            ids.append(UUID(uuid: tuple))
        }
        let all = ids.map { $0.uuidString.lowercased() } + artifactIDs + [sessionID]
        guard Set(all).count == all.count else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return ids
    }
}

/// Exact retained base session and partition descriptors. This value is never send authority.
nonisolated struct AgentBridgeNativePreparedTransfer: Sendable {
    let export: AgentBridgeNativePreparedExport
    let session: DirectTransferSession
    let partitions: [DirectTransferPartition]
    let maximumInFlightChunks: Int
    let checkpointCanonical: Data
    static func make(request: AgentBridgeExecute, export: AgentBridgeNativePreparedExport, checkpointCanonical: Data) throws -> Self {
        let checkpoint = try AgentBridgeNativeTransferCheckpoint.decode(checkpointCanonical)
        let ids = try checkpoint.validate(requestSHA256: export.requestSHA256,
            manifestSHA256: AgentBridgeV4Codec.sha256(export.manifestCanonical), createdAt: checkpoint.createdAt,
            expiresAt: checkpoint.expiresAt, artifactIDs: export.baseFiles.map { $0.manifest.fileID.uuidString.lowercased() })
        let time = ISO8601DateFormatter()
        guard export.requestSHA256 == AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request)),
              let createdAt = time.date(from: checkpoint.createdAt), let expiresAt = time.date(from: checkpoint.expiresAt),
              expiresAt.timeIntervalSince(createdAt) == 7 * 24 * 60 * 60,
              let sessionID = UUID(uuidString: checkpoint.sessionID), let jobID = UUID(uuidString: request.jobId.rawValue),
              let source = UUID(uuidString: request.plan.intent.peer.sourceInstallationID.rawValue),
              let host = UUID(uuidString: request.plan.intent.peer.hostInstallationID.rawValue) else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        let session = try DirectTransferSession(sessionID: sessionID, jobID: jobID,
            requestFingerprint: DirectRequestFingerprint(sha256: export.requestSHA256),
            peerBinding: .init(sourceInstallationID: source, destinationInstallationID: host),
            partitionTargetBytes: checkpoint.partitionTargetBytes, createdAt: createdAt)
        var previous: String?
        var partitions: [DirectTransferPartition] = []
        for (index, file) in export.baseFiles.enumerated() {
            let itemID = file.manifest.fileID.uuidString.lowercased()
            // The currently reviewed signed daily-JSON payloads fit one unchanged binary chunk.
            guard file.manifest.byteCount > 0, file.manifest.byteCount <= Int64(DirectTransferLimits.chunkBytes) else {
                throw AgentBridgeValidationError.queryBudgetExceeded
            }
            partitions.append(try .init(index: index, transferID: ids[index], sourceDates: [itemID],
                byteCount: file.manifest.byteCount, chunkCount: 1, sha256: file.manifest.sha256, previousSHA256: previous,
                itemSegment: .init(itemID: itemID, offset: 0, itemByteCount: file.manifest.byteCount, isFinalSegment: true)))
            previous = file.manifest.sha256
        }
        return .init(export: export, session: session, partitions: partitions,
            maximumInFlightChunks: checkpoint.maximumInFlightChunks, checkpointCanonical: checkpointCanonical)
    }
}

@MainActor
extension AgentBridgeNativePlanningSession {
    func prepareExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativePreparedExport {
        try await withCaptureContext(request) { context in
            try await AgentBridgeNativeExportProducer.prepare(request: request, manager: manager, context: context, core: core)
        }
    }

    /// Byte carriage only. Full v4 commit/frontier/receipt completion remains a separate step.
    func sendTransferExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        retained: Bool = false,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws {
        try await transmitTransfer(request, retained: retained) { context in
            try await AgentBridgeNativeExportProducer.prepareTransfer(request: request, manager: manager, context: context, core: core)
        }
    }

    /// Complete source confirmation stays inside the original capture/transfer owner.
    func sendExecutionExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        retained: Bool = false,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)) async throws {
        try await transmitTransfer(request, retained: retained, confirmCompletion: true) { context in
            try await AgentBridgeNativeExportProducer.prepareTransfer(request: request, manager: manager, context: context, core: core)
        }
    }

    /// The original Execute is recovered exclusively from the signed native job. Retained
    /// preparation must reuse its captured bytes; Resume cannot cause a fresh SDK capture.
    func sendResumedExecutionExport(_ resume: AgentBridgeResume, manager: HealthKitManager,
        acknowledging acknowledgement: DirectTransferPartitionAcknowledgement? = nil,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)) async throws {
        try await transmitResumedTransfer(resume, acknowledging: acknowledgement, confirmCompletion: true) { request, context in
            try await AgentBridgeNativeExportProducer.prepareTransfer(request: request, manager: manager, context: context, core: core)
        }
    }

    func prepareTransferExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativePreparedTransfer {
        try await withCaptureContext(request) { context in
            try await AgentBridgeNativeExportProducer.prepareTransfer(request: request, manager: manager, context: context, core: core)
        }
    }
    func prepareRetainedTransferExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativePreparedTransfer {
        try await withRetainedCaptureContext(request) { context in
            try await AgentBridgeNativeExportProducer.prepareTransfer(request: request, manager: manager, context: context, core: core)
        }
    }

    /// Explicit recovery only; failed new execution never falls back to this operation.
    func prepareRetainedExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativePreparedExport {
        try await withRetainedCaptureContext(request) { context in
            try await AgentBridgeNativeExportProducer.prepare(request: request, manager: manager, context: context, core: core)
        }
    }
}

@MainActor
private enum AgentBridgeNativeExportProducer {
    static func prepareTransfer(request: AgentBridgeExecute, manager: HealthKitManager, context: AgentBridgeNativeCaptureContext,
        core: any AppleLooseDailyCoreExecuting) async throws -> AgentBridgeNativePreparedTransfer {
        do {
            let prepared = try await prepare(request: request, manager: manager, context: context, core: core, requireTransfer: true)
            let result = try AgentBridgeNativePreparedTransfer.make(request: request, export: prepared, checkpointCanonical: context.preserveTransferPlan())
            guard try context.requestFingerprintForRead() == prepared.requestSHA256 else { throw AgentBridgeValidationError.bindingChanged }
            return result
        } catch { context.invalidate(); throw error }
    }
    static func prepare(request: AgentBridgeExecute, manager: HealthKitManager, context: AgentBridgeNativeCaptureContext,
        core: any AppleLooseDailyCoreExecuting, requireTransfer: Bool = false) async throws -> AgentBridgeNativePreparedExport {
        do {
            let resolution = try context.begin()
            if requireTransfer { _ = try context.transferNegotiationForRead() }
            let fingerprint = try context.requestFingerprintForRead()
            let approved = resolution.requestedDays
            guard !approved.isEmpty, approved.count <= 4096,
                  Set(approved.map(\.rawValue)).count == approved.count,
                  resolution.predictedRelativePaths.count == approved.count else {
                throw AgentBridgeNativeRenderFailure.invalidInput
            }
            var days: [AgentBridgeNativeRenderedDay] = []
            var total: UInt64 = 0
            let limit: UInt64 = 64 * 1024 * 1024
            for (index, day) in approved.enumerated() {
                let result = try await AgentBridgeNativeDayRenderer.capture(day: day, manager: manager, context: context, core: core)
                guard result.day == day, result.artifact.relativePath == resolution.predictedRelativePaths[index],
                      result.artifact.byteCount <= limit, total <= limit - result.artifact.byteCount,
                      days.first.map({ $0.buildInfo == result.buildInfo && $0.registrySHA256 == result.registrySHA256 }) ?? true else {
                    throw AgentBridgeNativeRenderFailure.invalidArtifact
                }
                total += result.artifact.byteCount
                days.append(result)
            }
            guard days.count == approved.count, Set(days.map { $0.artifact.id }).count == days.count,
                  try context.requestFingerprintForRead() == fingerprint else {
                throw AgentBridgeNativeRenderFailure.invalidArtifact
            }
            let publicIDs = try context.bindPublicArtifactIDs()
            guard Set(publicIDs.keys) == Set(approved.map(\.rawValue)),
                  try context.requestFingerprintForRead() == fingerprint else { throw AgentBridgeNativeRenderFailure.invalidArtifact }
            let manifest = try context.preserveManifest()
            guard try context.requestFingerprintForRead() == fingerprint else { throw AgentBridgeNativeRenderFailure.invalidArtifact }
            let prepared = try AgentBridgeNativePreparedExport.make(request: request, days: days,
                totalByteCount: total, publicArtifactIDs: publicIDs, manifestCanonical: manifest)
            guard prepared.requestSHA256 == fingerprint, try context.requestFingerprintForRead() == fingerprint else {
                throw AgentBridgeNativeRenderFailure.invalidArtifact
            }
            return prepared
        } catch {
            context.invalidate()
            if error is CancellationError || error is AgentBridgeValidationError || error is AgentBridgeNativeRenderFailure { throw error }
            throw AgentBridgeNativeRenderFailure.renderFailed
        }
    }
}
