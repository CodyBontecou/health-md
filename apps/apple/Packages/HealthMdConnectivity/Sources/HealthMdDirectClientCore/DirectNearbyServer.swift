import Foundation
import HealthMdConnectionCore
import MultipeerConnectivity

public struct DirectNearbyServerEndpoint: Equatable, Sendable {
    public let serviceType: String
    public let displayName: String

    public init(serviceType: String, displayName: String) {
        self.serviceType = serviceType
        self.displayName = displayName
    }
}

public final class DirectNearbyServer: @unchecked Sendable {
    public let installationID: UUID
    public let displayName: String

    private let trustStore: any ManualIPTrustStoring
    private let peerID: MCPeerID
    private let queue = DirectNearbyPacketQueue()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var delegate: DirectNearbyAdvertiserDelegate?
    private lazy var authenticator = DirectManualIPServer(
        installationID: installationID,
        displayName: displayName,
        port: HealthMdDirectProtocol.defaultManualIPPort,
        trustStore: trustStore
    )

    public init(
        installationID: UUID,
        displayName: String = "healthmd CLI",
        trustStore: any ManualIPTrustStoring
    ) {
        self.installationID = installationID
        self.displayName = displayName
        self.trustStore = trustStore
        self.peerID = MCPeerID(displayName: Self.peerDisplayName(displayName, installationID: installationID))
    }

    public func start() throws -> DirectNearbyServerEndpoint {
        guard advertiser == nil else {
            throw DirectChannelError.connectionFailed("The nearby direct listener is already running.")
        }
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["installation_id": installationID.uuidString.lowercased()],
            serviceType: HealthMdDirectProtocol.serviceType
        )
        let delegate = DirectNearbyAdvertiserDelegate(localPeer: peerID, queue: queue)
        advertiser.delegate = delegate
        self.advertiser = advertiser
        self.delegate = delegate
        advertiser.startAdvertisingPeer()
        return DirectNearbyServerEndpoint(
            serviceType: HealthMdDirectProtocol.serviceType,
            displayName: peerID.displayName
        )
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        delegate?.cancelAll()
        delegate = nil
        queue.finish(DirectChannelError.connectionClosed)
    }

    public func acceptAuthenticatedClient(
        pairingCode: String? = nil,
        pairingCodeExpiresAt: Date? = nil,
        timeout: TimeInterval = 120,
        maximumAttempts: Int = 8
    ) async throws -> DirectSecureChannel {
        guard advertiser != nil else {
            throw DirectChannelError.connectionFailed("The nearby direct listener is not running.")
        }
        let deadline = Date().addingTimeInterval(timeout)
        var attempts = 0
        var lastError: Error?
        while attempts < maximumAttempts, deadline > Date() {
            attempts += 1
            let packet = try await queue.next(timeout: max(0.1, deadline.timeIntervalSinceNow))
            do {
                return try await authenticator.authenticate(
                    packet,
                    pairingCode: pairingCode,
                    pairingCodeExpiresAt: pairingCodeExpiresAt
                )
            } catch {
                packet.cancel()
                lastError = error
            }
        }
        throw lastError ?? DirectChannelError.timedOut
    }

    public func trustedClients() -> [ManualIPTrustedClient] {
        authenticator.trustedClients()
    }

    private static func peerDisplayName(_ name: String, installationID: UUID) -> String {
        let clipped = String(decoding: name.utf8.prefix(48), as: UTF8.self)
        return "\(clipped)-\(installationID.uuidString.prefix(8))"
    }
}

private final class DirectNearbyAdvertiserDelegate: NSObject, MCNearbyServiceAdvertiserDelegate, @unchecked Sendable {
    let localPeer: MCPeerID
    let queue: DirectNearbyPacketQueue
    private let lock = NSLock()
    private var sessions: [ObjectIdentifier: MCSession] = [:]
    private var waiters: [ObjectIdentifier: DirectNearbyServerSessionDelegate] = [:]

    init(localPeer: MCPeerID, queue: DirectNearbyPacketQueue) {
        self.localPeer = localPeer
        self.queue = queue
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        lock.lock()
        let canAccept = sessions.count < 2
        lock.unlock()
        guard canAccept else {
            invitationHandler(false, nil)
            return
        }
        let session = MCSession(
            peer: localPeer,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        let waiter = DirectNearbyServerSessionDelegate(
            session: session,
            expectedPeer: peerID,
            queue: queue,
            onFinish: { [weak self, weak session] in
                guard let self, let session else { return }
                let key = ObjectIdentifier(session)
                self.lock.lock()
                self.sessions.removeValue(forKey: key)
                self.waiters.removeValue(forKey: key)
                self.lock.unlock()
            }
        )
        session.delegate = waiter
        let key = ObjectIdentifier(session)
        lock.lock()
        guard sessions.count < 2 else {
            lock.unlock()
            session.disconnect()
            invitationHandler(false, nil)
            return
        }
        sessions[key] = session
        waiters[key] = waiter
        lock.unlock()
        invitationHandler(true, session)
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        queue.finish(DirectChannelError.connectionFailed(error.localizedDescription))
    }

    func cancelAll() {
        lock.lock()
        let active = Array(sessions.values)
        sessions.removeAll()
        waiters.removeAll()
        lock.unlock()
        active.forEach { $0.disconnect() }
    }
}

private final class DirectNearbyServerSessionDelegate: NSObject, MCSessionDelegate, @unchecked Sendable {
    let session: MCSession
    let expectedPeer: MCPeerID
    let queue: DirectNearbyPacketQueue
    let onFinish: () -> Void
    private let lock = NSLock()
    private var handedOff = false
    private var bufferedPackets: [Data] = []
    private var packetConnection: DirectMultipeerPacketConnection?

    init(
        session: MCSession,
        expectedPeer: MCPeerID,
        queue: DirectNearbyPacketQueue,
        onFinish: @escaping () -> Void
    ) {
        self.session = session
        self.expectedPeer = expectedPeer
        self.queue = queue
        self.onFinish = onFinish
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard peerID == expectedPeer else { return }
        switch state {
        case .connected:
            lock.lock()
            guard !handedOff else { lock.unlock(); return }
            let packet = DirectMultipeerPacketConnection(
                session: session,
                remotePeer: peerID,
                initialPackets: bufferedPackets
            )
            bufferedPackets.removeAll()
            packetConnection = packet
            handedOff = true
            lock.unlock()
            queue.push(packet)
            onFinish()
        case .notConnected:
            lock.lock()
            let shouldFinish = !handedOff
            lock.unlock()
            if shouldFinish { onFinish() }
        case .connecting: break
        @unknown default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard peerID == expectedPeer else { return }
        lock.lock()
        if let packetConnection {
            lock.unlock()
            packetConnection.enqueueReceivedPacket(data)
        } else if data.count <= HealthMdDirectProtocol.maximumPacketBytes,
                  bufferedPackets.count < 4,
                  bufferedPackets.reduce(0, { $0 + $1.count }) + data.count <= 4 * 1_024 * 1_024 {
            bufferedPackets.append(data)
            lock.unlock()
        } else {
            lock.unlock()
            session.disconnect()
            onFinish()
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) { certificateHandler(true) }
}

private final class DirectNearbyPacketQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var buffered: [DirectMultipeerPacketConnection] = []
    private var waiter: (id: UUID, continuation: CheckedContinuation<DirectMultipeerPacketConnection, Error>)?
    private var terminalError: Error?
    private let maximumBufferedConnections = 2

    func next(timeout: TimeInterval) async throws -> DirectMultipeerPacketConnection {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !buffered.isEmpty {
                let value = buffered.removeFirst()
                lock.unlock()
                continuation.resume(returning: value)
            } else if let terminalError {
                lock.unlock()
                continuation.resume(throwing: terminalError)
            } else if waiter != nil {
                lock.unlock()
                continuation.resume(throwing: DirectChannelError.malformedPacket)
            } else {
                waiter = (id, continuation)
                lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.expire(id)
                }
            }
        }
    }

    func push(_ value: DirectMultipeerPacketConnection) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.continuation.resume(returning: value)
        } else if terminalError == nil, buffered.count < maximumBufferedConnections {
            buffered.append(value)
            lock.unlock()
        } else {
            lock.unlock()
            value.cancel()
        }
    }

    func finish(_ error: Error) {
        lock.lock()
        let pending = waiter?.continuation
        waiter = nil
        let queued = buffered
        buffered.removeAll()
        terminalError = error
        lock.unlock()
        queued.forEach { $0.cancel() }
        pending?.resume(throwing: error)
    }

    private func expire(_ id: UUID) {
        lock.lock()
        guard waiter?.id == id else { lock.unlock(); return }
        let pending = waiter?.continuation
        waiter = nil
        lock.unlock()
        pending?.resume(throwing: DirectChannelError.timedOut)
    }
}
