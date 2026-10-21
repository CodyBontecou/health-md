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

@MainActor
extension AgentBridgeNativePlanningSession {
    func prepareExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativePreparedExport {
        try await withCaptureContext(request) { context in
            try await AgentBridgeNativeExportProducer.prepare(request: request, manager: manager, context: context, core: core)
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
    static func prepare(request: AgentBridgeExecute, manager: HealthKitManager, context: AgentBridgeNativeCaptureContext,
        core: any AppleLooseDailyCoreExecuting) async throws -> AgentBridgeNativePreparedExport {
        do {
            let resolution = try context.begin()
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
