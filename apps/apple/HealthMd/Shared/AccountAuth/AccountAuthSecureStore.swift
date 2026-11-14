import Foundation

/// Process-local fence. The NSLock guards ONLY its two fields and synchronous commit critical sections.
/// A future durable adapter must hold this permit across its ACTUAL authoritative commit, not just staging.
nonisolated final class AccountAuthCommitFence: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    private var open = true
    init(generation: UInt64 = 0) { value = generation }
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func isCurrent(_ expected: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return open && value == expected
    }
    @discardableResult func advance(minimum: UInt64 = 0) throws -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        value = max(value, minimum)
        guard value < UInt64.max else { open = false; throw AccountAuthSourceError.exhausted }
        value += 1
        open = true
        return value
    }
    func close(_ expected: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if value == expected { open = false }
    }
    func atAuthoritativeCommit<T>(_ expected: UInt64, _ commit: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !Task.isCancelled, open && value == expected else { throw AccountAuthSourceError.stale }
        return try commit() // No await/staging/commit gap is permitted inside an adapter.
    }
}

nonisolated struct AccountAuthStoredRecord: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    let captured: AccountAuthCapture
    let session: AccountAuthSession
    let localGeneration: UInt64
    /// Conservative request-start bound, NEVER the response/commit arrival time.
    let leaseStart: UInt64
    let requestID: UInt64
    var description: String { "[account-auth vault record redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func validate() throws {
        let s = session, r = captured.registration
        guard s.namespace.issuer == r.issuer, s.namespace.environment == r.environment,
              AccountAuthWire.opaqueAccountID(s.namespace.accountID), s.audience == r.audience,
              s.clientID == r.clientID, s.installationID == captured.installationID,
              s.scope == captured.scope, (1...300).contains(s.expiresIn),
              s.serverGeneration <= AccountAuthWire.maximumSafeInteger,
              AccountAuthPKCE.isReference(s.sessionID), s.tokenType == "Bearer",
              s.access.kind == .access, s.refresh.kind == .refresh,
              leaseStart <= AccountAuthWire.maximumSafeInteger - 300 else { throw AccountAuthSourceError.malformed }
    }
    func validateTemporal(at time: UInt64, commitNotAfter: UInt64) throws {
        try validate()
        guard time >= leaseStart, time < leaseStart + session.expiresIn, time < commitNotAfter,
              commitNotAfter > leaseStart, commitNotAfter <= AccountAuthWire.maximumSafeInteger else {
            throw AccountAuthSourceError.uncertain
        }
    }
}
nonisolated struct AccountAuthVaultReceipt: Sendable, Equatable {
    enum Kind: Sendable { case prepare, install, erase }
    let kind: Kind
    let generation: UInt64
    let requestID: UInt64
}
nonisolated struct AccountAuthVaultSnapshot: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    enum Integrity: Sendable { case complete, corrupt }
    let integrity: Integrity
    let durableGeneration: UInt64
    let normal: AccountAuthStoredRecord?
    let receipt: AccountAuthVaultReceipt?
    var description: String { "[account-auth vault snapshot redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
nonisolated struct AccountAuthVaultCommand: Sendable {
    let receipt: AccountAuthVaultReceipt
    let normal: AccountAuthStoredRecord?
    let leaseClock: (any AccountAuthClock)?
    let commitNotAfter: UInt64?
    init(receipt: AccountAuthVaultReceipt, normal: AccountAuthStoredRecord?,
         leaseClock: (any AccountAuthClock)? = nil, commitNotAfter: UInt64? = nil) {
        self.receipt = receipt; self.normal = normal
        self.leaseClock = leaseClock; self.commitNotAfter = commitNotAfter
    }
    func validateTemporal() throws {
        if receipt.kind == .install {
            guard let normal, let leaseClock, let commitNotAfter else { throw AccountAuthSourceError.malformed }
            try normal.validateTemporal(at: leaseClock.seconds(), commitNotAfter: commitNotAfter)
        }
    }
}

nonisolated protocol AccountAuthVault: Sendable {
    /// Linearizable synchronous commit under fence.atAuthoritativeCommit, including the fresh
    /// command.validateTemporal clock check at the ACTUAL write, or complete rollback.
    /// A lost reply MAY throw. Never retry this operation or invoke the permit over a staged snapshot.
    func transact(_ command: AccountAuthVaultCommand, fence: AccountAuthCommitFence) async throws
    /// Fresh, complete authoritative read; no cached optimistic postconditions/change counts.
    func read() async throws -> AccountAuthVaultSnapshot
}

/// Actual synthetic memory transaction implementation; NOT durable/Keychain/backup/OS evidence.
/// Must be explicitly injected. No default coordinator/app factory constructs it.
actor AccountAuthSyntheticVault: AccountAuthVault {
    private var state: AccountAuthVaultSnapshot
    init(syntheticSeed: AccountAuthVaultSnapshot? = nil) {
        state = syntheticSeed ?? AccountAuthVaultSnapshot(integrity: .complete, durableGeneration: 0, normal: nil, receipt: nil)
    }
    func read() -> AccountAuthVaultSnapshot { state }
    func transact(_ command: AccountAuthVaultCommand, fence: AccountAuthCommitFence) throws {
        try fence.atAuthoritativeCommit(command.receipt.generation) {
            guard command.receipt.generation >= state.durableGeneration else { throw AccountAuthSourceError.stale }
            if command.receipt.kind == .install {
                guard state.durableGeneration == command.receipt.generation, let normal = command.normal,
                      normal.localGeneration == command.receipt.generation,
                      normal.requestID == command.receipt.requestID else { throw AccountAuthSourceError.malformed }
                try command.validateTemporal() // Fresh clock at the actual synchronous custody commit.
            } else if command.normal != nil { throw AccountAuthSourceError.malformed }
            // All fields + operation receipt change together at the actual memory commit seam.
            state = AccountAuthVaultSnapshot(integrity: .complete, durableGeneration: command.receipt.generation,
                normal: command.normal, receipt: command.receipt)
        }
    }
}
