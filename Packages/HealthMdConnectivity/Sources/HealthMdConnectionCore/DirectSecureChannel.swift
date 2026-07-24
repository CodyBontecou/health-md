import CryptoKit
import Foundation
import Network

public enum DirectChannelError: LocalizedError, Equatable {
    case connectionFailed(String)
    case connectionClosed
    case frameTooLarge
    case malformedPacket
    case expectedEncryptedPacket
    case decodeFailed
    case timedOut
    case authenticationFailed(String)
    case replayedPacket

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message): return message
        case .connectionClosed: return "The direct iPhone connection closed."
        case .frameTooLarge: return "The direct iPhone frame exceeded the bounded limit."
        case .malformedPacket: return "The direct iPhone packet was malformed."
        case .expectedEncryptedPacket: return "The direct iPhone channel received an unauthenticated packet."
        case .decodeFailed: return "The direct iPhone message could not be decoded."
        case .timedOut: return "The direct iPhone connection timed out."
        case .authenticationFailed(let message): return message
        case .replayedPacket: return "The direct iPhone channel rejected a replayed or out-of-order packet."
        }
    }
}

public protocol DirectPacketTransport: AnyObject, Sendable {
    func send(_ packet: ManualIPSyncPacket) async throws
    func receive() async throws -> ManualIPSyncPacket
    func cancel()
}

public final class DirectPacketConnection: DirectPacketTransport, @unchecked Sendable {
    public let connection: NWConnection
    private let queue: DispatchQueue
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maximumPacketBytes: Int

    public init(
        connection: NWConnection,
        queue: DispatchQueue,
        maximumPacketBytes: Int = ManualIPSyncSecurity.maxFrameSize
    ) {
        self.connection = connection
        self.queue = queue
        self.maximumPacketBytes = min(maximumPacketBytes, ManualIPSyncSecurity.maxFrameSize)
    }

    public func start(timeout: TimeInterval = 10) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = DirectConnectionStartGate(continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish(.success(()))
                case .failed(let error):
                    gate.finish(.failure(DirectChannelError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    gate.finish(.failure(DirectChannelError.connectionClosed))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                gate.finish(.failure(DirectChannelError.timedOut))
                self.connection.cancel()
            }
        }
    }

    public func cancel() {
        connection.cancel()
    }

    public func send(_ packet: ManualIPSyncPacket) async throws {
        let payload = try encoder.encode(packet)
        guard payload.count <= maximumPacketBytes else {
            throw DirectChannelError.frameTooLarge
        }
        var framed = Data()
        framed.reserveCapacity(8 + payload.count)
        framed.appendManualIPLengthPrefix(payload.count)
        framed.append(payload)
        try await sendBytes(framed)
    }

    public func receive() async throws -> ManualIPSyncPacket {
        let lengthData = try await receiveExactly(8)
        guard let length = lengthData.manualIPLengthPrefix(),
              length > 0,
              length <= maximumPacketBytes else {
            throw DirectChannelError.frameTooLarge
        }
        let payload = try await receiveExactly(length)
        do {
            return try decoder.decode(ManualIPSyncPacket.self, from: payload)
        } catch {
            throw DirectChannelError.malformedPacket
        }
    }

    private func sendBytes(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: DirectChannelError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func receiveExactly(_ byteCount: Int) async throws -> Data {
        var result = Data()
        result.reserveCapacity(byteCount)
        while result.count < byteCount {
            let remaining = byteCount - result.count
            let next = try await receiveBytes(maximumLength: remaining)
            guard !next.isEmpty else { throw DirectChannelError.connectionClosed }
            result.append(next)
        }
        return result
    }

    private func receiveBytes(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: maximumLength
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: DirectChannelError.connectionFailed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: DirectChannelError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

private final class DirectConnectionStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

public enum DirectSecurePayload: Equatable, Sendable {
    case message(DirectMessage)
    case binaryTransferFrame(Data)
}

public final class DirectSecureChannel: @unchecked Sendable {
    public let packetConnection: any DirectPacketTransport
    public let sessionKey: SymmetricKey
    public let peerInstallationID: UUID
    public let peerDisplayName: String

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
    private let sequenceLock = NSLock()
    private let sendGate = DirectAsyncGate()
    private let receiveGate = DirectAsyncGate()
    private var nextSendSequence: UInt64 = 0
    private var nextReceiveSequence: UInt64 = 0
    private static let envelopeMagic = Data("HMDSC001".utf8)

    public init(
        packetConnection: any DirectPacketTransport,
        sessionKey: SymmetricKey,
        peerInstallationID: UUID,
        peerDisplayName: String
    ) {
        self.packetConnection = packetConnection
        self.sessionKey = sessionKey
        self.peerInstallationID = peerInstallationID
        self.peerDisplayName = peerDisplayName
    }

    public func send(_ message: DirectMessage) async throws {
        try await sendEncrypted(encoder.encode(message))
    }

    public func sendBinaryTransferFrame(_ frame: Data) async throws {
        guard DirectTransferBinaryFrame.isBinaryFrame(frame) else {
            throw DirectChannelError.malformedPacket
        }
        try await sendEncrypted(frame)
    }

    public func receive() async throws -> DirectSecurePayload {
        try await receiveGate.perform { [self] in
            guard case .encrypted(let frame) = try await packetConnection.receive() else {
                throw DirectChannelError.expectedEncryptedPacket
            }
            let sealedPlaintext = try ManualIPSyncSecurity.open(frame, using: sessionKey)
            let plaintext = try openSequencedEnvelope(sealedPlaintext)
            if DirectTransferBinaryFrame.isBinaryFrame(plaintext) {
                return .binaryTransferFrame(plaintext)
            }
            do {
                return .message(try decoder.decode(DirectMessage.self, from: plaintext))
            } catch {
                throw DirectChannelError.decodeFailed
            }
        }
    }

    public func cancel() {
        packetConnection.cancel()
    }

    private func sendEncrypted(_ plaintext: Data) async throws {
        try await sendGate.perform { [self] in
            let sequence = sequenceLock.withLock {
                let value = nextSendSequence
                nextSendSequence &+= 1
                return value
            }

            var envelope = Self.envelopeMagic
            var bigEndianSequence = sequence.bigEndian
            withUnsafeBytes(of: &bigEndianSequence) { envelope.append(contentsOf: $0) }
            envelope.append(plaintext)
            let sealed = try ManualIPSyncSecurity.seal(envelope, using: sessionKey)
            try await packetConnection.send(.encrypted(sealed))
        }
    }

    private func openSequencedEnvelope(_ envelope: Data) throws -> Data {
        let headerBytes = Self.envelopeMagic.count + MemoryLayout<UInt64>.size
        guard envelope.count >= headerBytes,
              envelope.prefix(Self.envelopeMagic.count) == Self.envelopeMagic else {
            throw DirectChannelError.malformedPacket
        }
        let sequenceData = envelope.dropFirst(Self.envelopeMagic.count).prefix(MemoryLayout<UInt64>.size)
        var bigEndianSequence: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &bigEndianSequence) { sequenceData.copyBytes(to: $0) }
        let sequence = UInt64(bigEndian: bigEndianSequence)

        sequenceLock.lock()
        guard sequence == nextReceiveSequence else {
            sequenceLock.unlock()
            throw DirectChannelError.replayedPacket
        }
        nextReceiveSequence &+= 1
        sequenceLock.unlock()
        return Data(envelope.dropFirst(headerBytes))
    }
}

private actor DirectAsyncGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
