import Foundation
import HealthMdConnectionCore

/// Native observer state only, never a wire request, grant or replacement for fresh SDK sampling.
/// The native owner records metadata before scheduling publication; readers reject until that exact
/// observation has committed. SDK event registration and owner cancellation remain separate work.
nonisolated final class AgentBridgeNativeCatalogLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private let publisher = NSLock()
    private var facts: AgentBridgeNativePlanningFacts?
    private var generation: UInt64 = 0
    private var publishedGeneration: UInt64?
    // A fresh native owner cannot prove that a previous owner published its last observation.
    // Invalidate unexecuted old plans once; durable job resume is a separate journal boundary.
    private var observedChange = true
    private var stopped = false
    private var exhausted = false

    /// Initial metadata is not an observed transition. Subsequent unequal samples invalidate reads
    /// immediately, even before a worker starts the filesystem transaction.
    func observe(_ value: AgentBridgeNativePlanningFacts) throws {
        try lock.withLock {
            try requireAvailable()
            guard facts != value else { return }
            if facts != nil { try advance() }
            facts = value
        }
    }

    /// Latch an actual native notification even when deferred SDK sampling has coalesced A→B→A.
    func observeNativeChange() throws {
        try lock.withLock { try requireAvailable(); try advance() }
    }

    func stop() { lock.withLock { stopped = true } }

    func currentFacts() throws -> AgentBridgeNativePlanningFacts {
        try lock.withLock {
            try requireAvailable()
            guard publishedGeneration == generation, let facts else {
                throw AgentBridgeValidationError.bindingChanged
            }
            return facts
        }
    }

    /// Call on the native owner's worker. No task is spawned, no store/key is created or repaired,
    /// and no native consent is implied. Concurrent publishers reject instead of queueing stale work.
    @discardableResult
    func publish(to store: AgentBridgeExportAuthorityStore, sourceInstallationID: AgentBridgeUUID) throws -> AgentBridgeNativeCatalogPublication {
        guard publisher.try() else { throw AgentBridgeValidationError.busy }
        defer { publisher.unlock() }
        let captured = try lock.withLock { () throws -> (UInt64, Bool, AgentBridgeNativePlanningFacts) in
            try requireAvailable()
            guard let facts else { throw AgentBridgeValidationError.bindingChanged }
            return (generation, observedChange, facts)
        }
        let publication = try store.publishNativeCatalog(sourceInstallationID: sourceInstallationID,
            invalidatingObservedChange: captured.1) { [self] in
                try lock.withLock {
                    try requireAvailable()
                    guard generation == captured.0, facts == captured.2 else {
                        throw AgentBridgeValidationError.bindingChanged
                    }
                    return captured.2
                }
            }
        try lock.withLock {
            try requireAvailable()
            guard generation == captured.0, facts == captured.2 else {
                throw AgentBridgeValidationError.bindingChanged
            }
            publishedGeneration = captured.0
            observedChange = false
        }
        return publication
    }

    private func advance() throws {
        guard generation < UInt64.max else {
            exhausted = true
            throw AgentBridgeValidationError.busy
        }
        generation += 1
        observedChange = true
    }
    private func requireAvailable() throws {
        guard !stopped else { throw AgentBridgeValidationError.permissionRequired }
        guard !exhausted else { throw AgentBridgeValidationError.busy }
    }
}
