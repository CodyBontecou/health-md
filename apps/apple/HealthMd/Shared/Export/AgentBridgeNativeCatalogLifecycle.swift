import Foundation
import HealthMdConnectionCore

/// Native observer state only, never a wire request, grant or replacement for fresh SDK sampling.
/// The native owner records metadata before scheduling publication; readers reject until that exact
/// observation has committed. SDK event registration and owner cancellation remain separate work.
nonisolated final class AgentBridgeNativeCatalogLifecycle: @unchecked Sendable {
    /// Native-only ticket: binds a suspended metadata sample to this exact owner/generation.
    struct Sample: Sendable {
        fileprivate let owner: UUID
        fileprivate let generation: UInt64
    }
    private let refreshEvents: AsyncStream<Void>
    private let refreshContinuation: AsyncStream<Void>.Continuation
    private var refreshClaimed = false
    private let identity = UUID()
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
    private var initialPublicationFinished = false
    private var initialPublicationFailure: AgentBridgeValidationError?
    private var initialPublicationWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    init() {
        let events = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        refreshEvents = events.stream
        refreshContinuation = events.continuation
    }

    /// Exactly one native controller per accepted owner. Initial refresh catches events that
    /// preceded registration; later events coalesce only after synchronous invalidation.
    func claimRefreshEvents() throws -> AsyncStream<Void> {
        try lock.withLock {
            try requireAvailable()
            guard !refreshClaimed else { throw AgentBridgeValidationError.busy }
            refreshClaimed = true
            refreshContinuation.yield(())
            return refreshEvents
        }
    }

    /// Actual native events wake the controller; publication failures only invalidate and must
    /// not self-schedule an unbounded retry loop against a missing store or unavailable SDK.
    func recordNativeEvent() throws {
        try lock.withLock {
            try requireAvailable()
            try advance()
            refreshContinuation.yield(())
        }
    }

    func beginSample() throws -> Sample {
        try lock.withLock { try requireAvailable(); return Sample(owner: identity, generation: generation) }
    }

    /// A notification during SDK suspension rejects even when sampled facts return to A.
    func observe(_ value: AgentBridgeNativePlanningFacts, sampledDuring sample: Sample) throws -> Sample {
        try lock.withLock {
            try requireSample(sample)
            if facts != value {
                if facts != nil { try advance() }
                facts = value
            }
            return Sample(owner: identity, generation: generation)
        }
    }

    private func requireSample(_ sample: Sample) throws {
        try requireAvailable()
        guard sample.owner == identity, sample.generation == generation else {
            throw AgentBridgeValidationError.bindingChanged
        }
    }

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

    /// Local original-owner liveness only. Pending refresh conveys no catalog/read authority.
    func requireActiveOwner() throws {
        try lock.withLock { try requireAvailable() }
    }

    func stop() {
        lock.withLock { stopped = true; refreshContinuation.finish() }
        finishInitialPublication(.permissionRequired)
    }

    /// Wait only for the original native controller's first publication attempt. This never
    /// schedules a sample, opens storage, retries a failed attempt or renews an owner.
    func awaitInitialPublication() async throws -> AgentBridgeNativeCatalogPublication {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let result: Result<Void, Error>? = lock.withLock {
                    if Task.isCancelled { return .failure(CancellationError()) }
                    do { try requireAvailable() }
                    catch { return .failure(error) }
                    if initialPublicationFinished {
                        if let initialPublicationFailure { return .failure(initialPublicationFailure) }
                        return .success(())
                    }
                    initialPublicationWaiters[id] = continuation
                    return nil
                }
                if let result { continuation.resume(with: result) }
            }
        } onCancel: {
            let continuation = self.lock.withLock { self.initialPublicationWaiters.removeValue(forKey: id) }
            continuation?.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
        return try currentPublication()
    }

    /// Failure ends this admission wait; it cannot turn into an implicit retry loop.
    func failInitialPublication() { finishInitialPublication(.bindingChanged) }

    func completeInitialPublication(_ publication: AgentBridgeNativeCatalogPublication) throws {
        guard try currentPublication() == publication else { throw AgentBridgeValidationError.bindingChanged }
        finishInitialPublication(nil)
    }

    private func finishInitialPublication(_ failure: AgentBridgeValidationError?) {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            guard !initialPublicationFinished else { return [] }
            initialPublicationFinished = true
            initialPublicationFailure = failure
            let waiters = Array(initialPublicationWaiters.values)
            initialPublicationWaiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            if let failure { waiter.resume(throwing: failure) }
            else { waiter.resume() }
        }
    }

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
                 sample: Sample? = nil, requireOwner: () throws -> Void = {}) throws -> AgentBridgeNativeCatalogPublication {
        guard publisher.try() else { throw AgentBridgeValidationError.busy }
        defer { publisher.unlock() }
        try requireOwner()
        let captured = try lock.withLock { () throws -> (UInt64, Bool, AgentBridgeNativePlanningFacts) in
            try requireAvailable()
            if let sample { try requireSample(sample) }
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
            do { try current?.recordNativeEvent() }
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


extension Notification.Name {
    /// Local native issuer mutation only; no peer, consent, path or health payload.
    nonisolated static let healthMdAgentExportAuthorityDidChange = Notification.Name("healthMdAgentExportAuthorityDidChange")
}
