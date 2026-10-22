import Foundation

// Disabled source interface. No account authority, OS custody or sync opt-in is implied.
nonisolated enum AccountAuthFailure: String, Error, Sendable, CaseIterable {
    case unavailable, invalidRequest = "invalid_request", invalidGrant = "invalid_grant"
    case unauthorized, forbidden, notFound = "not_found", rateLimited = "rate_limited"
    case verificationPending = "verification_pending", reuseFamilyRevoked = "reuse_family_revoked"
}

nonisolated enum AccountAuthSourceError: Error, Sendable {
    case unavailable, malformed, busy, stale, entropy, uncertain, exhausted
}

nonisolated struct AccountAuthSecret: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    enum Kind: String, Sendable { case code = "hmd_acode_", access = "hmd_nac_", refresh = "hmd_nrf_" }
    let kind: Kind
    private let value: String

    init(_ value: String, kind: Kind) throws {
        guard value.hasPrefix(kind.rawValue),
              AccountAuthPKCE.isReference(String(value.dropFirst(kind.rawValue.count))) else {
            throw AccountAuthSourceError.malformed
        }
        self.value = value
        self.kind = kind
    }

    // Only the closed source codec/transport/vault seam may consume these bytes.
    func wireValue() -> String { value }
    var description: String { "[account-auth secret redacted]" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

nonisolated struct AccountAuthNamespace: Sendable, Equatable {
    let issuer: String
    let environment: String
    let accountID: String
}

nonisolated struct AccountAuthSession: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    let tokenType: String
    let access: AccountAuthSecret
    let expiresIn: UInt64
    let refresh: AccountAuthSecret
    let sessionID: String
    let scope: String
    let namespace: AccountAuthNamespace
    let audience: String
    let clientID: String
    let installationID: String
    let serverGeneration: UInt64
    var description: String { "[account-auth parsed session redacted; not authority]" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

nonisolated enum AccountAuthPhase: String, Sendable {
    case unavailable, freshAuthenticationRequired, preparing, awaitingCallback, exchanging
    case signedIn, refreshing, cancelled, denied, expired, revoked, uncertain, signedOut, exhausted
}
nonisolated enum AccountAuthVerification: String, Sendable { case notAttempted, verified, uncertain }
nonisolated enum AccountAuthRemoteRevoke: String, Sendable { case notRequested, pending, confirmed, unknown }
nonisolated enum AccountAuthEvent: Sendable, Equatable {
    case none, fenced(UInt64), sessionAvailable(AccountAuthNamespace, UInt64)
}

/// Nonsecret only. There is deliberately no credential/config/health capability getter.
nonisolated struct AccountAuthSnapshot: Sendable, Equatable {
    let phase: AccountAuthPhase
    let namespace: AccountAuthNamespace?
    let localGeneration: UInt64
    let localErase: AccountAuthVerification
    let durableFence: AccountAuthVerification
    let remoteRevoke: AccountAuthRemoteRevoke
    let event: AccountAuthEvent
    let refreshInFlight: Bool
    let refreshCallers: Int
    let profileSyncEnabled: Bool = false
}

nonisolated enum AccountAuthOutcome: Sendable, Equatable {
    case installed, denied, superseded, unavailable, busy, uncertain, exhausted
    case failure(AccountAuthFailure)
}
