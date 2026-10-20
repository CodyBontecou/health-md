import Foundation
import HealthMdConnectionCore

/// Native controller worker boundary. Opens only an existing private store and propagates parent
/// cancellation to the actual worker. No wire route, key/grant creation, metadata or health sampling.
nonisolated enum AgentBridgeNativeCatalogPublisher {
    /// Native refresh transaction: the sampler runs under the original observation ticket. Its
    /// failure or cancellation cannot leave an older published readiness cache available.
    static func refresh(lifecycle: AgentBridgeNativeCatalogLifecycle, peer: AgentBridgeExportAuthenticatedPeer,
                        existingDirectory: URL,
                        sample: () async throws -> AgentBridgeNativePlanningFacts,
                        loadStore: @escaping @Sendable (URL) throws -> AgentBridgeExportAuthorityStore = {
                            try AgentBridgeExportAuthorityStore(existingDirectory: $0)
                        }) async throws -> AgentBridgeNativeCatalogPublication {
        try Task.checkCancellation()
        let started = try lifecycle.beginSample()
        do {
            try peer.requireCurrent()
            try Task.checkCancellation()
            let facts = try await sample()
            try Task.checkCancellation()
            try peer.requireCurrent()
            try Task.checkCancellation()
            let accepted = try lifecycle.observe(facts, sampledDuring: started)
            return try await publish(lifecycle: lifecycle, peer: peer, existingDirectory: existingDirectory,
                                     sample: accepted, loadStore: loadStore)
        } catch {
            try? lifecycle.observeNativeChange()
            throw error
        }
    }

    static func publish(lifecycle: AgentBridgeNativeCatalogLifecycle, peer: AgentBridgeExportAuthenticatedPeer,
                        existingDirectory: URL, sample: AgentBridgeNativeCatalogLifecycle.Sample? = nil,
                        loadStore: @escaping @Sendable (URL) throws -> AgentBridgeExportAuthorityStore = {
                            try AgentBridgeExportAuthorityStore(existingDirectory: $0)
                        }) async throws -> AgentBridgeNativeCatalogPublication {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            try peer.requireCurrent()
            let store = try loadStore(existingDirectory)
            return try lifecycle.publish(to: store, sourceInstallationID: peer.peer.sourceInstallationID, sample: sample) {
                try Task.checkCancellation()
                try peer.requireCurrent()
                try Task.checkCancellation()
            }
        }
        do {
            let publication = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            try peer.requireCurrent()
            try Task.checkCancellation()
            guard try lifecycle.currentPublication() == publication else {
                throw AgentBridgeValidationError.bindingChanged
            }
            try Task.checkCancellation()
            return publication
        } catch {
            // A failed worker may have crossed rename/fsync; never reopen an older cached plan.
            try? lifecycle.observeNativeChange()
            throw error
        }
    }
}
