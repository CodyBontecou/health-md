import Foundation
import MultipeerConnectivity

/// Message-boundary transport for nearby direct sessions. MCSession encryption
/// is required, then the ordinary direct channel adds its authenticated
/// application-layer encryption and replay counters.
public final class DirectMultipeerPacketConnection: NSObject, DirectPacketTransport, MCSessionDelegate, @unchecked Sendable {
    public let session: MCSession
    public let remotePeer: MCPeerID

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let inbox = DirectMultipeerInbox()

    public init(
        session: MCSession,
        remotePeer: MCPeerID,
        initialPackets: [Data] = []
    ) {
        self.session = session
        self.remotePeer = remotePeer
        super.init()
        session.delegate = self
        for packet in initialPackets where !inbox.push(packet) {
            session.disconnect()
            break
        }
    }

    public func enqueueReceivedPacket(_ data: Data) {
        guard data.count <= HealthMdDirectProtocol.maximumPacketBytes else {
            inbox.finish(.failure(DirectChannelError.frameTooLarge))
            return
        }
        if !inbox.push(data) {
            session.disconnect()
        }
    }

    public func send(_ packet: ManualIPSyncPacket) async throws {
        let data = try encoder.encode(packet)
        guard data.count <= HealthMdDirectProtocol.maximumPacketBytes,
              session.connectedPeers.contains(remotePeer) else {
            throw DirectChannelError.connectionClosed
        }
        do {
            try session.send(data, toPeers: [remotePeer], with: .reliable)
        } catch {
            throw DirectChannelError.connectionFailed(error.localizedDescription)
        }
    }

    public func receive() async throws -> ManualIPSyncPacket {
        let data = try await inbox.next()
        do {
            return try decoder.decode(ManualIPSyncPacket.self, from: data)
        } catch {
            throw DirectChannelError.malformedPacket
        }
    }

    public func cancel() {
        session.disconnect()
        inbox.finish(.failure(DirectChannelError.connectionClosed))
    }

    public func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        if peerID == remotePeer, state == .notConnected {
            inbox.finish(.failure(DirectChannelError.connectionClosed))
        }
    }

    public func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        guard peerID == remotePeer else { return }
        enqueueReceivedPacket(data)
    }

    public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}

    public func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }
}

private final class DirectMultipeerInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffered: [Data] = []
    private var waiter: CheckedContinuation<Data, Error>?
    private var terminalError: Error?
    private var bufferedBytes = 0
    private let maximumBufferedPackets = 8
    private let maximumBufferedBytes = 16 * 1_024 * 1_024

    func next() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !buffered.isEmpty {
                let data = buffered.removeFirst()
                bufferedBytes -= data.count
                lock.unlock()
                continuation.resume(returning: data)
            } else if let terminalError {
                lock.unlock()
                continuation.resume(throwing: terminalError)
            } else if waiter != nil {
                lock.unlock()
                continuation.resume(throwing: DirectChannelError.malformedPacket)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    @discardableResult
    func push(_ data: Data) -> Bool {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: data)
            return true
        } else if terminalError == nil,
                  buffered.count < maximumBufferedPackets,
                  bufferedBytes + data.count <= maximumBufferedBytes {
            buffered.append(data)
            bufferedBytes += data.count
            lock.unlock()
            return true
        } else {
            if terminalError == nil { terminalError = DirectChannelError.frameTooLarge }
            let pending = waiter
            waiter = nil
            lock.unlock()
            pending?.resume(throwing: DirectChannelError.frameTooLarge)
            return false
        }
    }

    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let pending = waiter
        waiter = nil
        if case .failure(let error) = result { terminalError = error }
        lock.unlock()
        pending?.resume(with: result)
    }
}
