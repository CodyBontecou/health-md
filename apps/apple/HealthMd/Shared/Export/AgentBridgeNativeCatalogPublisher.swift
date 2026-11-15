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
            lifecycle.failInitialPublication()
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
            try lifecycle.completeInitialPublication(publication)
            return publication
        } catch {
            // A failed worker may have crossed rename/fsync; never reopen an older cached plan.
            try? lifecycle.observeNativeChange()
            lifecycle.failInitialPublication()
            throw error
        }
    }
}


/// One serial native refresh loop per accepted owner. A pending notification retains one follow-up
/// sample while work is suspended. Failures wait for another native event; no polling or retry timer.
@MainActor
final class AgentBridgeNativeCatalogRefresh {
    private let lifecycle: AgentBridgeNativeCatalogLifecycle
    private let task: Task<Void, Never>

    init(lifecycle: AgentBridgeNativeCatalogLifecycle, refresh: @escaping @MainActor () async throws -> Void) throws {
        try Task.checkCancellation()
        let events = try lifecycle.claimRefreshEvents()
        self.lifecycle = lifecycle
        task = Task {
            defer { lifecycle.stop() }
            for await _ in events {
                if Task.isCancelled { return }
                do { try await refresh() }
                catch {
                    try? lifecycle.observeNativeChange()
                    lifecycle.failInitialPublication()
                    if error is CancellationError || Task.isCancelled { return }
                }
            }
        }
    }

    func stop() { task.cancel(); lifecycle.stop() }
    deinit { task.cancel(); lifecycle.stop() }
}


/// App-owned admission signal. Replacing an accepted owner cancels queued work before
/// any SDK/store sampler starts. Wire handlers only replace this identity; native
/// dependencies are installed once by the application composition root.
@MainActor
final class AgentBridgeNativeCatalogAdmission {
    private var start: (@MainActor (AgentBridgeNativeCatalogLifecycle) throws -> Void)?
    private var current: AgentBridgeNativeCatalogLifecycle?
    private var pending: Task<Void, Never>?

    func configure(start: @escaping @MainActor (AgentBridgeNativeCatalogLifecycle) throws -> Void) {
        guard self.start == nil else { return }
        self.start = start
        schedule()
    }

    func replace(with lifecycle: AgentBridgeNativeCatalogLifecycle?) {
        guard current !== lifecycle else { return }
        pending?.cancel()
        current?.stop()
        current = lifecycle
        schedule()
    }

    private func schedule() {
        guard let original = current, let start else { return }
        pending = Task { [weak self] in
            guard !Task.isCancelled, self?.current === original else { return }
            do { _ = try original.beginSample(); try start(original) }
            catch { original.stop() } // A rejected owner is never silently renewed.
        }
    }

    deinit { pending?.cancel(); current?.stop() }
}
