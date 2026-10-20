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
    private var publication: AgentBridgeNativeCatalogPublication?
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

    /// Return-side fence across worker suspension: the same facts may have a newer ABA revision.
    func currentPublication() throws -> AgentBridgeNativeCatalogPublication {
        try lock.withLock {
            try requireAvailable()
            guard publishedGeneration == generation, let publication else {
                throw AgentBridgeValidationError.bindingChanged
            }
            return publication
        }
    }

    /// Call on the native owner's worker. No task is spawned, no store/key is created or repaired,
    /// and no native consent is implied. Concurrent publishers reject instead of queueing stale work.
    @discardableResult
    func publish(to store: AgentBridgeExportAuthorityStore, sourceInstallationID: AgentBridgeUUID,
                 requireOwner: () throws -> Void = {}) throws -> AgentBridgeNativeCatalogPublication {
        guard publisher.try() else { throw AgentBridgeValidationError.busy }
        defer { publisher.unlock() }
        try requireOwner()
        let captured = try lock.withLock { () throws -> (UInt64, Bool, AgentBridgeNativePlanningFacts) in
            try requireAvailable()
            guard let facts else { throw AgentBridgeValidationError.bindingChanged }
            return (generation, observedChange, facts)
        }
        let publication = try store.publishNativeCatalog(sourceInstallationID: sourceInstallationID,
            invalidatingObservedChange: captured.1) { [self] in
                try requireOwner()
                return try lock.withLock {
                    try requireAvailable()
                    guard generation == captured.0, facts == captured.2 else {
                        throw AgentBridgeValidationError.bindingChanged
                    }
                    return captured.2
                }
            }
        try requireOwner()
        try lock.withLock {
            try requireAvailable()
            guard generation == captured.0, facts == captured.2 else {
                throw AgentBridgeValidationError.bindingChanged
            }
            self.publication = publication
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

/// Synchronous native-event relay. Posting threads never read SDK metadata, private settings,
/// issuer files or keys. Replacing/detaching an accepted owner permanently stops the old barrier.
nonisolated final class AgentBridgeNativeCatalogEventRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AgentBridgeNativeCatalogLifecycle?

    func replace(with lifecycle: AgentBridgeNativeCatalogLifecycle?) {
        lock.withLock {
            guard current !== lifecycle else { return }
            current?.stop()
            current = lifecycle
        }
    }

    func observeNativeChange() {
        lock.withLock {
            do { try current?.observeNativeChange() }
            catch { current?.stop() } // Overflow/stopped observation cannot silently reopen reads.
        }
    }
}

/// Foundation registration with exact owner lifetime. No Task/actor hop can coalesce native
/// notifications before the relay latches them. Production supplies native notification names;
/// tests may intercept the SDK boundary using an isolated NotificationCenter.
nonisolated final class AgentBridgeNativeCatalogNotifications {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default, names: [Notification.Name],
         relay: AgentBridgeNativeCatalogEventRelay) {
        self.center = center
        tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in relay.observeNativeChange() }
        }
    }

    deinit { tokens.forEach(center.removeObserver) }
}
