import Foundation

/// Test-only metadata seam, explicitly NOT a real consent/browser/identity adapter.
nonisolated enum AccountAuthSyntheticConsent: Sendable { case sourceMetadataOnly }

/// One root-free installation owner. All injected ports are synthetic; the default calls NONE.
/// No restore method exists: a new process must explicitly authenticate afresh. A stale vault row
/// cannot establish authority or prove signout intent when a durable fence failed before process loss.
actor AccountAuthCoordinator {
    private struct Ports: Sendable {
        let registration: AccountAuthRegistration
        let entropy: any AccountAuthEntropy
        let clock: any AccountAuthClock
        let vault: any AccountAuthVault
        let transport: any AccountAuthSyntheticTransport
    }
    private struct RevokeOnly: Sendable {
        let id: UInt64
        let captured: AccountAuthCapture
        let refresh: AccountAuthSecret
        let namespace: AccountAuthNamespace
        let sessionID: String
        func matches(_ row: AccountAuthStoredRecord) -> Bool {
            row.captured == captured && row.session.namespace == namespace && row.session.sessionID == sessionID
        }
    }
    private let ports: Ports?
    private let fence: AccountAuthCommitFence
    private var phase: AccountAuthPhase
    private var installationID: String?
    private var pending: AccountAuthPending?
    private var current: AccountAuthStoredRecord?
    private var preparingID: UInt64?
    private var exchangeID: UInt64?
    private var erasingID: UInt64?
    private var requestCounter: UInt64 = 0
    private var refreshTask: Task<AccountAuthOutcome, Never>?
    private var refreshID: UInt64?
    private var refreshCallers = 0
    private var revokeID: UInt64?
    // Deliberately inaccessible through normal refresh/config state and never persisted here.
    private var knownActiveFamily: RevokeOnly?
    private var revokeQueue: [RevokeOnly] = []
    private var exchangeMayHaveCommitted = false
    private var unknownRemoteObligation = false
    private var localErase: AccountAuthVerification = .notAttempted
    private var durableFence: AccountAuthVerification = .notAttempted
    private var remoteRevoke: AccountAuthRemoteRevoke = .notRequested
    private var event: AccountAuthEvent = .none

    init() {
        ports = nil
        fence = AccountAuthCommitFence()
        phase = .unavailable
    }
    init(syntheticForSourceTests client: AccountAuthAppleClient?, consent: AccountAuthSyntheticConsent?,
         entropy: any AccountAuthEntropy, clock: any AccountAuthClock, vault: any AccountAuthVault,
         transport: any AccountAuthSyntheticTransport, initialLocalGeneration: UInt64 = 0,
         recreated: Bool = false) {
        if let client, consent != nil {
            ports = Ports(registration: .reviewedSynthetic(apple: client), entropy: entropy,
                clock: AccountAuthSourceClock(source: clock), vault: vault, transport: transport)
            phase = .freshAuthenticationRequired
            remoteRevoke = recreated ? .unknown : .notRequested
            unknownRemoteObligation = recreated
        } else {
            ports = nil
            phase = .unavailable
        }
        fence = AccountAuthCommitFence(generation: initialLocalGeneration)
    }

    func snapshot() -> AccountAuthSnapshot {
        var visiblePhase = phase
        var visibleNamespace: AccountAuthNamespace?
        if let row = current, fence.isCurrent(row.localGeneration) {
            if phase == .signedIn || phase == .refreshing {
                do {
                    let time = try now()
                    guard time >= row.leaseStart else { throw AccountAuthSourceError.uncertain }
                    visiblePhase = time >= row.leaseStart + row.session.expiresIn ? .expired : phase
                    visibleNamespace = row.session.namespace
                } catch {
                    // Losing clock/custody visibility does NOT remove the surviving refresh family.
                    quarantine(row.localGeneration)
                    visiblePhase = phase
                }
            }
        }
        return AccountAuthSnapshot(phase: visiblePhase, namespace: visibleNamespace,
            localGeneration: fence.generation, localErase: localErase, durableFence: durableFence,
            remoteRevoke: remoteRevoke, event: event, refreshInFlight: refreshTask != nil, refreshCallers: refreshCallers)
    }

    private func now() throws -> UInt64 {
        guard let ports else { throw AccountAuthSourceError.unavailable }
        let time = try ports.clock.seconds()
        guard time <= AccountAuthWire.maximumSafeInteger - 300 else { throw AccountAuthSourceError.unavailable }
        return time
    }
    private func nextID() throws -> UInt64 {
        guard requestCounter < UInt64.max else { throw AccountAuthSourceError.exhausted }
        requestCounter += 1
        return requestCounter
    }
    private func active(_ generation: UInt64, exchange: UInt64? = nil) -> Bool {
        fence.isCurrent(generation) && (exchange == nil || exchangeID == exchange)
    }
    private func noteUnknownRemoteObligation() {
        unknownRemoteObligation = true
        remoteRevoke = revokeQueue.isEmpty ? .unknown : .pending
    }
    private func quarantine(_ generation: UInt64, revoked: Bool = false) {
        guard fence.generation == generation else { return }
        fence.close(generation)
        current = nil
        pending = nil
        phase = revoked ? .revoked : .uncertain
        event = .fenced(generation)
        if knownActiveFamily != nil || !revokeQueue.isEmpty { remoteRevoke = .pending }
        else if exchangeMayHaveCommitted { noteUnknownRemoteObligation() }
        // knownActiveFamily survives. Clearing access visibility is not erasure or remote revocation.
    }
    private func verify(_ snapshot: AccountAuthVaultSnapshot, command: AccountAuthVaultCommand) throws {
        guard snapshot.integrity == .complete, snapshot.durableGeneration == command.receipt.generation,
              snapshot.receipt == command.receipt, snapshot.normal == command.normal else {
            throw AccountAuthSourceError.uncertain
        }
        try snapshot.normal?.validate()
    }
    private func commit(_ command: AccountAuthVaultCommand, ports: Ports) async throws {
        guard !Task.isCancelled else { throw AccountAuthSourceError.uncertain }
        do { try await ports.vault.transact(command, fence: fence) } catch { /* Readback, not a return value, is proof. */ }
        let readback = try await ports.vault.read()
        guard !Task.isCancelled else { throw AccountAuthSourceError.uncertain }
        guard active(command.receipt.generation) else { throw AccountAuthSourceError.stale }
        try verify(readback, command: command)
        try command.validateTemporal() // A delayed readback cannot publish an expired/rolled-back lease.
    }

    func begin(scope: String) async throws -> AccountAuthAuthorizationPlan {
        guard let ports else { throw AccountAuthSourceError.unavailable }
        guard pending == nil, preparingID == nil, exchangeID == nil, erasingID == nil,
              current == nil, knownActiveFamily == nil, !exchangeMayHaveCommitted,
              refreshTask == nil, revokeQueue.count < 20 else { throw AccountAuthSourceError.busy }
        let canonical = try AccountAuthCapture.canonicalScope(scope)
        let id = try nextID()
        preparingID = id
        phase = .preparing
        var generation = fence.generation
        var inspectingPriorCustody = false
        defer { if preparingID == id { preparingID = nil } }
        do {
            generation = try fence.advance()
            event = .fenced(generation)
            localErase = .uncertain
            durableFence = .uncertain
            inspectingPriorCustody = true
            let stored = try await ports.vault.read()
            guard active(generation), preparingID == id else { throw AccountAuthSourceError.stale }
            guard stored.integrity == .complete else { throw AccountAuthSourceError.uncertain }
            inspectingPriorCustody = false
            if stored.normal != nil { noteUnknownRemoteObligation() } // Never adopt an unproven row/proof/account.
            if stored.durableGeneration >= generation {
                generation = try fence.advance(minimum: stored.durableGeneration)
                event = .fenced(generation)
            }
            let command = AccountAuthVaultCommand(receipt: .init(kind: .prepare, generation: generation, requestID: id), normal: nil)
            try await commit(command, ports: ports)
            guard preparingID == id else { throw AccountAuthSourceError.stale }
            localErase = .verified
            durableFence = .verified
            if installationID == nil { installationID = try AccountAuthPKCE.reference(entropy: ports.entropy) }
            guard let installationID else { throw AccountAuthSourceError.entropy }
            let capture = try AccountAuthCapture(registration: ports.registration, installationID: installationID, scope: canonical)
            let pkce = try AccountAuthPKCE.make(entropy: ports.entropy)
            let attempt = AccountAuthPending(captured: capture, pkce: pkce, localGeneration: generation, expiresAt: try now() + 300)
            let plan = try AccountAuthAuthorizationPlan(pending: attempt)
            guard active(generation) else { throw AccountAuthSourceError.stale }
            pending = attempt
            phase = .awaitingCallback
            return plan
        } catch {
            if preparingID == id {
                if inspectingPriorCustody { noteUnknownRemoteObligation() }
                quarantine(generation)
                if case AccountAuthSourceError.exhausted = error { phase = .exhausted }
            }
            throw error
        }
    }

    func cancel() {
        guard ports != nil, pending != nil || preparingID != nil || exchangeID != nil else { return }
        if exchangeMayHaveCommitted { unknownRemoteObligation = true; remoteRevoke = .unknown }
        pending = nil
        preparingID = nil
        exchangeID = nil
        current = nil
        do { _ = try fence.advance(); phase = .cancelled } catch { phase = .exhausted }
        durableFence = .uncertain // Process-local cancellation is not a durable write.
        event = .fenced(fence.generation)
    }

    func consumeCallback(_ raw: Data) async -> AccountAuthOutcome {
        guard let ports else { return .unavailable }
        guard let attempt = pending, active(attempt.localGeneration) else { return .superseded }
        let callback: AccountAuthCallback
        do {
            let time = try now()
            if time >= attempt.expiresAt { cancel(); return .superseded }
            callback = try AccountAuthCallback.decode(raw, pending: attempt, localGeneration: fence.generation, now: time)
        } catch { return .denied }
        pending = nil // Consume before any await: code replay cannot dispatch twice.
        if case .denied = callback { phase = .denied; return .denied }
        guard case .code(let code) = callback else { return .denied }
        let generation = attempt.localGeneration
        var id: UInt64 = 0
        do {
            id = try nextID()
            exchangeID = id
            phase = .exchanging
            let plan = try AccountAuthTransportPlan.exchange(pending: attempt, code: code, requestID: id)
            let start = try now()
            exchangeMayHaveCommitted = true
            let reply = try await ports.transport.send(plan)
            guard active(generation, exchange: id) else { return .superseded }
            let bytes = try reply.validatedBody(for: plan)
            let session = try AccountAuthWire.decodeSession(bytes, captured: attempt.captured)
            try AccountAuthWire.validateInitial(session)
            // Even an expired access lease may leave a surviving refresh family. Keep revoke-only
            // knowledge from this correlated valid synthetic reply, NEVER normal account authority.
            knownActiveFamily = RevokeOnly(id: id, captured: attempt.captured, refresh: session.refresh,
                namespace: session.namespace, sessionID: session.sessionID)
            exchangeMayHaveCommitted = false
            let row = AccountAuthStoredRecord(captured: attempt.captured, session: session,
                localGeneration: generation, leaseStart: start, requestID: id)
            let deadline = start + plan.timeoutSeconds
            try row.validateTemporal(at: now(), commitNotAfter: deadline)
            let command = AccountAuthVaultCommand(receipt: .init(kind: .install, generation: generation, requestID: id),
                normal: row, leaseClock: ports.clock, commitNotAfter: deadline)
            localErase = .uncertain // The earlier prepare-clear receipt is superseded BEFORE any new custody write.
            durableFence = .uncertain
            try await commit(command, ports: ports)
            guard active(generation, exchange: id) else { return .superseded }
            try row.validateTemporal(at: now(), commitNotAfter: deadline) // Final visibility boundary.
            current = row
            exchangeID = nil
            phase = .signedIn
            if revokeQueue.isEmpty && !unknownRemoteObligation { remoteRevoke = .notRequested }
            localErase = .notAttempted
            durableFence = .verified
            event = .sessionAvailable(session.namespace, generation)
            return .installed
        } catch {
            guard active(generation, exchange: id) else { return .superseded }
            exchangeID = nil
            quarantine(generation, revoked: (error as? AccountAuthFailure) == .reuseFamilyRevoked)
            return (error as? AccountAuthFailure).map(AccountAuthOutcome.failure) ?? .uncertain
        }
    }

    /// Coalesced callers share ONE load/request/validate/commit, including every suspension.
    func refresh() async -> AccountAuthOutcome {
        guard let ports else { return .unavailable }
        guard let row = current, active(row.localGeneration), erasingID == nil else { return .superseded }
        refreshCallers += 1
        defer { refreshCallers -= 1 }
        if let task = refreshTask {
            let result = await task.value
            return result == .installed && !active(row.localGeneration) ? .superseded : result
        }
        let id: UInt64
        do { id = try nextID() } catch { quarantine(row.localGeneration); phase = .exhausted; return .exhausted }
        refreshID = id
        phase = .refreshing
        let task = Task { await self.performRefresh(row: row, id: id, ports: ports) }
        refreshTask = task
        let outcome = await task.value
        if refreshID == id { refreshID = nil; refreshTask = nil }
        if outcome == .installed && !active(row.localGeneration) { return .superseded }
        return outcome
    }
    private func performRefresh(row: AccountAuthStoredRecord, id: UInt64, ports: Ports) async -> AccountAuthOutcome {
        let generation = row.localGeneration
        do {
            let stored = try await ports.vault.read()
            guard active(generation), current == row else { return .superseded }
            guard stored.integrity == .complete, stored.durableGeneration == generation,
                  stored.normal == row, stored.receipt == .init(kind: .install, generation: generation, requestID: row.requestID) else {
                throw AccountAuthSourceError.uncertain
            }
            try row.validate()
            guard row.session.serverGeneration < AccountAuthWire.maximumSafeInteger else { throw AccountAuthSourceError.exhausted }
            let plan = try AccountAuthTransportPlan.refresh(captured: row.captured, proof: row.session.refresh, requestID: id)
            let start = try now()
            guard start >= row.leaseStart else { throw AccountAuthSourceError.uncertain }
            let reply = try await ports.transport.send(plan)
            guard active(generation), current == row else { return .superseded }
            let session = try AccountAuthWire.decodeSession(reply.validatedBody(for: plan), captured: row.captured)
            try AccountAuthWire.validateRefresh(session, previous: row.session)
            let replacement = AccountAuthStoredRecord(captured: row.captured, session: session,
                localGeneration: generation, leaseStart: start, requestID: id)
            let deadline = start + plan.timeoutSeconds
            try replacement.validateTemporal(at: now(), commitNotAfter: deadline)
            localErase = .uncertain
            durableFence = .uncertain
            try await commit(AccountAuthVaultCommand(receipt: .init(kind: .install, generation: generation, requestID: id),
                normal: replacement, leaseClock: ports.clock, commitNotAfter: deadline), ports: ports)
            guard active(generation), current == row else { return .superseded }
            try replacement.validateTemporal(at: now(), commitNotAfter: deadline)
            current = replacement
            phase = .signedIn
            localErase = .notAttempted
            durableFence = .verified
            event = .sessionAvailable(session.namespace, generation)
            return .installed
        } catch {
            guard active(generation) else { return .superseded }
            quarantine(generation, revoked: (error as? AccountAuthFailure) == .reuseFamilyRevoked)
            return (error as? AccountAuthFailure).map(AccountAuthOutcome.failure) ?? .uncertain
        }
    }

    /// Immediate local fence first; verified normal erasure and remote revoke are separate postconditions.
    func signOut() async -> AccountAuthSnapshot {
        guard let ports else { return snapshot() }
        if let proof = knownActiveFamily, !revokeQueue.contains(where: { $0.id == proof.id }) {
            if revokeQueue.count < 20 { revokeQueue.append(proof) } else { unknownRemoteObligation = true }
        }
        knownActiveFamily = nil
        if exchangeMayHaveCommitted { unknownRemoteObligation = true }
        exchangeMayHaveCommitted = false
        if !revokeQueue.isEmpty { remoteRevoke = .pending }
        else if unknownRemoteObligation { remoteRevoke = .unknown }
        pending = nil; preparingID = nil; exchangeID = nil; current = nil
        localErase = .uncertain; durableFence = .uncertain
        let generation: UInt64, id: UInt64
        do { generation = try fence.advance(); id = try nextID() }
        catch { fence.close(fence.generation); phase = .exhausted; event = .fenced(fence.generation); return snapshot() }
        phase = .signedOut
        event = .fenced(generation)
        erasingID = id
        let command = AccountAuthVaultCommand(receipt: .init(kind: .erase, generation: generation, requestID: id), normal: nil)
        // Inspect prior custody only for obligation accounting, NEVER to restore/adopt its account/proof.
        do {
            let prior = try await ports.vault.read()
            if active(generation), erasingID == id {
                if prior.integrity != .complete {
                    if revokeQueue.isEmpty { noteUnknownRemoteObligation() }
                } else if let row = prior.normal, !revokeQueue.contains(where: { $0.matches(row) }) {
                    noteUnknownRemoteObligation()
                }
            }
        } catch {
            if active(generation), erasingID == id, revokeQueue.isEmpty { noteUnknownRemoteObligation() }
        }
        do {
            try await commit(command, ports: ports)
            if erasingID == id { localErase = .verified; durableFence = .verified }
        } catch { /* Offline/no-op/unreadable erasure is not completion. Normal authority stays fenced. */ }
        if erasingID == id { erasingID = nil }
        return snapshot()
    }
    func switchAccount() async -> AccountAuthSnapshot { await signOut() }

    /// Explicit synthetic self-revoke retry only. No transparent proof replay, normal credential API,
    /// durable retention, secure-deletion or policy approval is implemented by this memory compartment.
    func retryRemoteRevocation() async -> AccountAuthSnapshot {
        guard let ports, let proof = revokeQueue.first, revokeID == nil else { return snapshot() }
        let generation = fence.generation
        let id: UInt64
        do { id = try nextID() } catch { return snapshot() }
        revokeID = id
        defer { if revokeID == id { revokeID = nil } }
        do {
            let plan = try AccountAuthTransportPlan.revoke(captured: proof.captured, proof: proof.refresh, requestID: id)
            let start = try now()
            let reply = try await ports.transport.send(plan)
            guard fence.generation == generation, revokeQueue.first?.id == proof.id, revokeID == id else { return snapshot() }
            try AccountAuthWire.decodeRevokeAcknowledgement(reply.validatedBody(for: plan))
            let time = try now()
            guard time >= start, time < start + plan.timeoutSeconds else { throw AccountAuthSourceError.uncertain }
            revokeQueue.removeFirst()
            remoteRevoke = !revokeQueue.isEmpty ? .pending : (unknownRemoteObligation ? .unknown : .confirmed)
        } catch { /* Including verification_pending and 2xx without the exact correlated acknowledgement. */ }
        return snapshot()
    }
}
