import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust

/// Every approved day, in its frozen order. Durable day artifacts back these bytes; this value
/// is neither a transfer manifest nor a receipt, and carries no authority outside its owner.
nonisolated struct AgentBridgeNativePreparedExport: Sendable {
    let requestSHA256: String
    let days: [AgentBridgeNativeRenderedDay]
    let totalByteCount: UInt64
    // Public UUID identities only. Counts, manifest/session binding and transfer remain separate.
    let publicArtifactIDs: [String: String]
}

@MainActor
extension AgentBridgeNativePlanningSession {
    func prepareExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativePreparedExport {
        try await withCaptureContext(request) { context in
            try await AgentBridgeNativeExportProducer.prepare(manager: manager, context: context, core: core)
        }
    }

    /// Explicit recovery only; failed new execution never falls back to this operation.
    func prepareRetainedExport(_ request: AgentBridgeExecute, manager: HealthKitManager,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativePreparedExport {
        try await withRetainedCaptureContext(request) { context in
            try await AgentBridgeNativeExportProducer.prepare(manager: manager, context: context, core: core)
        }
    }
}

@MainActor
private enum AgentBridgeNativeExportProducer {
    static func prepare(manager: HealthKitManager, context: AgentBridgeNativeCaptureContext,
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
            return .init(requestSHA256: fingerprint, days: days, totalByteCount: total, publicArtifactIDs: publicIDs)
        } catch {
            context.invalidate()
            if error is CancellationError || error is AgentBridgeValidationError || error is AgentBridgeNativeRenderFailure { throw error }
            throw AgentBridgeNativeRenderFailure.renderFailed
        }
    }
}
