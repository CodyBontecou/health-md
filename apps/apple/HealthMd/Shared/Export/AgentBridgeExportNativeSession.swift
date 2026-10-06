import Foundation
import HealthMdConnectionCore

/// Native identity/liveness ONLY, not consent, configuration, delegation or extension negotiation.
/// A closed controller epoch AND core proof are mandatory; IDs, trust or a Boolean cannot mint them.
/// All checks sample local/SDK boundaries, not global store/lifecycle/socket atomicity or remote close.
nonisolated final class AgentBridgeExportNativeSession: AgentBridgeExportNativeSessionChecking, @unchecked Sendable {
    private let ownership: IPhoneDirectCLIAuthenticatedSession
    private let proof: DirectClientAuthenticatedContext
    private let original: AgentBridgeExportNativeTrustSnapshot
    private let nativeTrust: AgentBridgeExportNativeTrust
    private let protectedData: @Sendable () -> Bool
    private let foreground: @MainActor @Sendable () -> Bool
    private let expectedPeer: AgentBridgePeer
    private let lock = NSLock()
    private var revoked = false

    private init(ownership: IPhoneDirectCLIAuthenticatedSession, proof: DirectClientAuthenticatedContext,
                 original: AgentBridgeExportNativeTrustSnapshot, nativeTrust: AgentBridgeExportNativeTrust,
                 protectedData: @escaping @Sendable () -> Bool,
                 foreground: @escaping @MainActor @Sendable () -> Bool) throws {
        self.ownership = ownership
        self.proof = proof
        self.original = original // ORIGINAL full raw legacy snapshot, never renewed or rebound.
        self.nativeTrust = nativeTrust
        self.protectedData = protectedData
        self.foreground = foreground
        expectedPeer = try .init(sourceInstallationID: AgentBridgeUUID(proof.sourceInstallationID.uuidString.lowercased()),
                                 hostInstallationID: AgentBridgeUUID(proof.hostInstallationID.uuidString.lowercased()), platform: .apple)
    }

    static func authenticatedPeer(
        ownership: IPhoneDirectCLIAuthenticatedSession,
        nativeTrust: AgentBridgeExportNativeTrust,
        protectedData: @escaping @Sendable () -> Bool,
        foreground: @escaping @MainActor @Sendable () -> Bool
    ) throws -> AgentBridgeExportAuthenticatedPeer {
        do {
            // Reject unsupported/unproven channels BEFORE any private SDK lookup.
            let channel = ownership.channel
            try ownership.requireCurrent()
            guard let proof = channel.clientAuthenticatedContext,
                  proof.sourceInstallationID == ownership.sourceInstallationID,
                  proof.hostInstallationID == channel.peerInstallationID else { throw AgentBridgeValidationError.permissionRequired }
            try proof.requireCurrent(on: channel)
            let active = try sampleForeground(foreground, ownership: ownership)
            let available = protectedData()
            try ownership.requireCurrent()
            try proof.requireCurrent(on: channel)
            guard active, try sampleForeground(foreground, ownership: ownership), available else { throw AgentBridgeValidationError.permissionRequired }
            guard let original = try nativeTrust.loadExistingTrust(ownerInstallationID: proof.sourceInstallationID) else {
                throw AgentBridgeValidationError.permissionRequired
            }
            try ownership.requireCurrent()
            try proof.requireCurrent(on: channel, sourceInstallationID: original.ownerInstallationID,
                                     hostInstallationID: original.trustedMacInstallationID, reconnectSecret: original.reconnectSecret)
            let session = try AgentBridgeExportNativeSession(ownership: ownership, proof: proof, original: original,
                                                             nativeTrust: nativeTrust, protectedData: protectedData, foreground: foreground)
            let peer = try AgentBridgeExportAuthenticatedPeer(nativeSourceInstallationID: proof.sourceInstallationID,
                authenticatedHostInstallationID: proof.hostInstallationID, currentNativeSession: session)
            try peer.requireCurrent() // Fresh current trust/availability after initial lookup and at return.
            return peer
        } catch { throw AgentBridgeValidationError.permissionRequired }
    }

    func requireCurrent(peer: AgentBridgePeer) throws {
        do {
            try checkAvailability(peer: peer)
            try nativeTrust.requireCurrent(original: original, nativeSourceInstallationID: proof.sourceInstallationID,
                authenticatedHostInstallationID: proof.hostInstallationID, originalReconnectSecret: original.reconnectSecret)
            try checkAvailability(peer: peer)
            // A second fresh sample also fences backing-trust changes during the intervening SDK
            // availability callback. Neither sample claims a transaction with the OS/store.
            try nativeTrust.requireCurrent(original: original, nativeSourceInstallationID: proof.sourceInstallationID,
                authenticatedHostInstallationID: proof.hostInstallationID, originalReconnectSecret: original.reconnectSecret)
            try checkAvailability(peer: peer)
            try checkLocal(peer: peer)
        } catch {
            lock.withLock { revoked = true }
            throw AgentBridgeValidationError.permissionRequired
        }
    }

    private func checkAvailability(peer: AgentBridgePeer) throws {
        try checkLocal(peer: peer)
        let active = try Self.sampleForeground(foreground, ownership: ownership)
        try checkLocal(peer: peer)
        let available = protectedData() // SDK fact only, no prompt/unlock or authority issuance.
        try checkLocal(peer: peer)
        let stillActive = try Self.sampleForeground(foreground, ownership: ownership)
        try checkLocal(peer: peer)
        guard active, stillActive, available else { throw AgentBridgeValidationError.permissionRequired }
    }

    /// The synchronous session interface cannot hop to MainActor. Task.immediate is the SDK's
    /// CHECKED actor-preserving synchronous-start boundary: no assumeIsolated/actor erasure.
    /// Older OS or unsupported caller thread/executor reject before private lookup. A queued or
    /// late result is never accepted and is cancelled; this grants no background eligibility.
    private static func sampleForeground(_ read: @escaping @MainActor @Sendable () -> Bool,
                                         ownership: IPhoneDirectCLIAuthenticatedSession) throws -> Bool {
        guard Thread.isMainThread else { throw AgentBridgeValidationError.permissionRequired }
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, *) {
            let result = AgentBridgeNativeForegroundSample()
            let task = Task.immediate { @MainActor in
                guard !Task.isCancelled else { return }
                result.record(ownership.currentOwnerIsAvailable() && read())
            }
            defer { task.cancel() }
            guard let value = result.finish() else { throw AgentBridgeValidationError.permissionRequired }
            return value
        }
        throw AgentBridgeValidationError.permissionRequired
    }

    private func checkLocal(peer: AgentBridgePeer) throws {
        guard lock.withLock({ !revoked }), peer == expectedPeer else { throw AgentBridgeValidationError.permissionRequired }
        try ownership.requireCurrent()
        guard ownership.channel.clientAuthenticatedContext === proof else { throw AgentBridgeValidationError.permissionRequired }
        try proof.requireCurrent(on: ownership.channel, sourceInstallationID: original.ownerInstallationID,
                                 hostInstallationID: original.trustedMacInstallationID, reconnectSecret: original.reconnectSecret)
        guard lock.withLock({ !revoked }) else { throw AgentBridgeValidationError.permissionRequired }
    }
}

nonisolated private final class AgentBridgeNativeForegroundSample: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    private var finished = false
    func record(_ value: Bool) { lock.withLock { if !finished { self.value = value } } }
    func finish() -> Bool? { lock.withLock { finished = true; return value } }
}
