import Foundation
import MultipeerConnectivity

public final class DirectNearbyClient: @unchecked Sendable {
    public let installationID: UUID
    public let displayName: String
    private let trustStore: any ManualIPTrustStoring
    private let messageCanonicalizer: any DirectMessageCanonicalizing

    public init(
        installationID: UUID,
        displayName: String,
        trustStore: any ManualIPTrustStoring,
        messageCanonicalizer: any DirectMessageCanonicalizing = NativeDirectMessageCanonicalizer()
    ) {
        self.installationID = installationID
        self.displayName = displayName
        self.trustStore = trustStore
        self.messageCanonicalizer = messageCanonicalizer
    }

    public func savedServer() -> ManualIPTrustedMac? {
        trustStore.loadState(ownerInstallationID: installationID).trustedMac
    }

    public func forgetServer() throws {
        var state = trustStore.loadState(ownerInstallationID: installationID)
        state.trustedMac = nil
        state.provisionalTrustedMac = nil
        try trustStore.saveState(state)
    }

    public func commitProvisionalServer() throws {
        var state = trustStore.loadState(ownerInstallationID: installationID)
        guard let provisionalTrustedMac = state.provisionalTrustedMac else {
            throw ManualIPTrustStoreError.missingProvisionalTrust
        }
        state.trustedMac = provisionalTrustedMac
        state.provisionalTrustedMac = nil
        try trustStore.saveState(state)
    }

    public func discardProvisionalServer() throws {
        var state = trustStore.loadState(ownerInstallationID: installationID)
        guard state.provisionalTrustedMac != nil else { return }
        state.provisionalTrustedMac = nil
        try trustStore.saveState(state)
    }

    public func connect(
        pairingCode: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> DirectSecureChannel {
        try await connectInternal(pairingCode: pairingCode, timeout: timeout)
    }

    /// Browse continuously until the paired server appears or the task is
    /// cancelled. This is used by an enabled foreground iPhone so availability
    /// does not churn through a visible timed reconnect loop.
    public func connectWaitingForServer(
        pairingCode: String? = nil
    ) async throws -> DirectSecureChannel {
        try await connectInternal(pairingCode: pairingCode, timeout: nil)
    }

    private func connectInternal(
        pairingCode: String?,
        timeout: TimeInterval?
    ) async throws -> DirectSecureChannel {
        let normalizedCode = pairingCode.map(
            ManualIPSyncSecurity.normalizedPairingCode
        ).flatMap { $0.isEmpty ? nil : $0 }
        let trustedID = trustStore
            .loadState(ownerInstallationID: installationID)
            .trustedMac?.installationID
        let peer = MCPeerID(displayName: Self.peerDisplayName(displayName, installationID: installationID))
        let session = MCSession(
            peer: peer,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        let awaiter = DirectNearbyConnectionAwaiter(
            session: session,
            expectedInstallationID: normalizedCode == nil ? trustedID : nil
        )
        let browser = MCNearbyServiceBrowser(
            peer: peer,
            serviceType: HealthMdDirectProtocol.serviceType
        )
        browser.delegate = awaiter
        awaiter.browser = browser
        browser.startBrowsingForPeers()
        return try await withTaskCancellationHandler {
            defer { browser.stopBrowsingForPeers() }
            try Task.checkCancellation()
            let remote = try await awaiter.wait(timeout: timeout)
            try Task.checkCancellation()
            let packetConnection = DirectMultipeerPacketConnection(
                session: session,
                remotePeer: remote
            )
            do {
                return try await DirectManualIPClient(
                    installationID: installationID,
                    displayName: displayName,
                    trustStore: trustStore,
                    messageCanonicalizer: messageCanonicalizer
                ).authenticate(
                    packetConnection,
                    host: "nearby",
                    port: 0,
                    pairingCode: normalizedCode
                )
            } catch {
                packetConnection.cancel()
                throw error
            }
        } onCancel: {
            browser.stopBrowsingForPeers()
            session.disconnect()
            awaiter.cancel()
        }
    }

    private static func peerDisplayName(_ name: String, installationID: UUID) -> String {
        let suffix = installationID.uuidString.prefix(8)
        let maximumNameBytes = 48
        let clipped = String(decoding: name.utf8.prefix(maximumNameBytes), as: UTF8.self)
        return "\(clipped)-\(suffix)"
    }
}

private final class DirectNearbyConnectionAwaiter: NSObject, MCNearbyServiceBrowserDelegate, MCSessionDelegate, @unchecked Sendable {
    let session: MCSession
    let expectedInstallationID: UUID?
    weak var browser: MCNearbyServiceBrowser?

    private let lock = NSLock()
    private var continuation: CheckedContinuation<MCPeerID, Error>?
    private var connectedPeer: MCPeerID?
    private var terminalError: Error?
    private var invited = false

    init(session: MCSession, expectedInstallationID: UUID?) {
        self.session = session
        self.expectedInstallationID = expectedInstallationID
        super.init()
        session.delegate = self
    }

    func wait(timeout: TimeInterval?) async throws -> MCPeerID {
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, self.finish(.failure(DirectChannelError.timedOut)) else { return }
                self.session.disconnect()
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let connectedPeer {
                lock.unlock()
                continuation.resume(returning: connectedPeer)
            } else if let terminalError {
                lock.unlock()
                continuation.resume(throwing: terminalError)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard let value = info?["installation_id"],
              let installationID = UUID(uuidString: value),
              expectedInstallationID == nil || expectedInstallationID == installationID else { return }
        lock.lock()
        guard !invited else { lock.unlock(); return }
        invited = true
        lock.unlock()
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        finish(.failure(DirectChannelError.connectionFailed(error.localizedDescription)))
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: finish(.success(peerID))
        case .notConnected:
            lock.lock()
            let shouldFail = invited && connectedPeer == nil
            lock.unlock()
            if shouldFail {
                finish(.failure(DirectChannelError.connectionClosed))
            }
        case .connecting: break
        @unknown default: break
        }
    }

    func cancel() {
        finish(.failure(DirectChannelError.connectionClosed))
    }

    @discardableResult
    private func finish(_ result: Result<MCPeerID, Error>) -> Bool {
        lock.lock()
        guard connectedPeer == nil, terminalError == nil else {
            lock.unlock()
            return false
        }
        let pending = continuation
        continuation = nil
        switch result {
        case .success(let peer): connectedPeer = peer
        case .failure(let error): terminalError = error
        }
        lock.unlock()
        pending?.resume(with: result)
        return true
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) { certificateHandler(true) }
}
