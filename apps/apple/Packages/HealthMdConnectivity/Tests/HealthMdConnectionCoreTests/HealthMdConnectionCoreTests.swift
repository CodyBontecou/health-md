import CryptoKit
import Foundation
import HealthMdConnectionCore
import Network
import XCTest

final class HealthMdConnectionCoreTests: XCTestCase {
    func testManualIPPairingProofAndEncryptionRemainCompatible() throws {
        let code = "123 456"
        let clientKey = Curve25519.KeyAgreement.PrivateKey()
        let serverKey = Curve25519.KeyAgreement.PrivateKey()
        let clientNonce = ManualIPSyncSecurity.randomNonce()
        let serverNonce = ManualIPSyncSecurity.randomNonce()
        let clientPublicKey = clientKey.publicKey.rawRepresentation
        let verifier = ManualIPSyncSecurity.pairingVerifier(
            pairingCode: code,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        )
        XCTAssertTrue(ManualIPSyncSecurity.pairingVerifierIsValid(
            verifier,
            pairingCode: "123456",
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        ))
        XCTAssertFalse(ManualIPSyncSecurity.pairingVerifierIsValid(
            verifier,
            pairingCode: "000000",
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        ))

        let sharedSecret = try clientKey.sharedSecretFromKeyAgreement(with: serverKey.publicKey)
        let sessionKey = ManualIPSyncSecurity.sessionKey(
            sharedSecret: sharedSecret,
            clientNonce: clientNonce,
            serverNonce: serverNonce
        )
        let plaintext = Data("healthmd-direct".utf8)
        XCTAssertEqual(
            try ManualIPSyncSecurity.open(
                ManualIPSyncSecurity.seal(plaintext, using: sessionKey),
                using: sessionKey
            ),
            plaintext
        )
    }

    func testDirectPairingProofIsDomainSeparatedFromClassicManualIP() {
        let installationID = UUID()
        let publicKey = Data(repeating: 7, count: 32)
        let nonce = Data(repeating: 9, count: 32)
        let code = "123456"
        let direct = DirectPairingSecurity.pairingVerifier(
            pairingCode: code,
            clientInstallationID: installationID,
            clientPublicKey: publicKey,
            clientNonce: nonce
        )
        let classic = ManualIPSyncSecurity.pairingVerifier(
            pairingCode: code,
            clientPublicKey: publicKey,
            clientNonce: nonce
        )
        XCTAssertNotEqual(direct, classic)
        XCTAssertTrue(DirectPairingSecurity.pairingVerifierIsValid(
            direct,
            pairingCode: code,
            clientInstallationID: installationID,
            clientPublicKey: publicKey,
            clientNonce: nonce
        ))
        XCTAssertFalse(DirectPairingSecurity.pairingVerifierIsValid(
            classic,
            pairingCode: code,
            clientInstallationID: installationID,
            clientPublicKey: publicKey,
            clientNonce: nonce
        ))
    }

    func testDirectMessageRoundTripsAndFingerprintIsDeterministic() throws {
        let request = DirectExportRequest(
            jobID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.987),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-07"),
            responseMode: .rawJSON,
            rawProfile: .healthDataProjection,
            canonicalSelection: DirectCanonicalSelection(
                metricIDs: ["sleep_total"],
                categories: ["Sleep"],
                objectPaths: ["/sleep"]
            )
        )
        let message = DirectMessage.exportRequest(request)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(message)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedMessage = try decoder.decode(DirectMessage.self, from: encoded)
        XCTAssertEqual(decodedMessage, message)
        XCTAssertEqual(request.createdAt.timeIntervalSince1970, 1_700_000_000)
        guard case .exportRequest(let decodedRequest) = decodedMessage else {
            return XCTFail("Expected export request")
        }
        XCTAssertEqual(
            try DirectRequestFingerprint.make(for: request),
            try DirectRequestFingerprint.make(for: decodedRequest)
        )
    }

    func testReadyPacketConnectionSurvivesItsStartupTimeout() async throws {
        let listenerReady = expectation(description: "listener ready")
        let serverReceivedPacket = expectation(description: "server received packet")
        let queue = DispatchQueue(label: "healthmd.connection-timeout-test")
        let listener = try NWListener(using: .tcp)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                listenerReady.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
                data, _, _, _ in
                if data?.isEmpty == false {
                    serverReceivedPacket.fulfill()
                }
            }
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        await fulfillment(of: [listenerReady], timeout: 1)

        let port = try XCTUnwrap(listener.port)
        let networkConnection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: port,
            using: .tcp
        )
        let packetConnection = DirectPacketConnection(
            connection: networkConnection,
            queue: queue
        )
        defer { packetConnection.cancel() }

        try await packetConnection.start(timeout: 0.05)
        try await Task.sleep(nanoseconds: 150_000_000)
        try await packetConnection.send(.pairingRejected(
            ManualIPPairingRejected(reason: "still connected")
        ))
        await fulfillment(of: [serverReceivedPacket], timeout: 1)
    }

    func testDirectSecureChannelRejectsReplayedPacket() async throws {
        let transport = ReplayPacketTransport()
        let channel = DirectSecureChannel(
            packetConnection: transport,
            sessionKey: SymmetricKey(data: Data(repeating: 0x42, count: 32)),
            peerInstallationID: UUID(),
            peerDisplayName: "test"
        )
        try await channel.send(.ping)
        transport.duplicateLastPacket()
        guard case .message(.ping) = try await channel.receive() else {
            return XCTFail("Expected the first authenticated packet")
        }
        do {
            _ = try await channel.receive()
            XCTFail("Expected replay rejection")
        } catch let error as DirectChannelError {
            XCTAssertEqual(error, .replayedPacket)
        }
    }

    func testNearbyContinuousWaitIsCancelledWithoutWaitingForATimeout() async throws {
        let installationID = UUID()
        let state = ManualIPTrustState(
            ownerInstallationID: installationID,
            trustedMac: ManualIPTrustedMac(
                installationID: UUID(),
                displayName: "paired healthmd CLI",
                host: "nearby",
                port: 0,
                reconnectSecret: Data(repeating: 0x5a, count: 32),
                pairedAt: Date()
            )
        )
        let client = DirectNearbyClient(
            installationID: installationID,
            displayName: "test iPhone",
            trustStore: InMemoryDirectTrustStore(state: state)
        )
        let wait = Task {
            try await client.connectWaitingForServer()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        wait.cancel()

        do {
            _ = try await wait.value
            XCTFail("Expected the continuous nearby wait to stop on cancellation")
        } catch let error as DirectChannelError {
            XCTAssertEqual(error, .connectionClosed)
        }
    }

    func testDirectTransferNegotiationAndBinaryFrameAreBounded() throws {
        let negotiation = try XCTUnwrap(
            DirectTransferCapabilities.current.negotiated(with: .current)
        )
        XCTAssertEqual(negotiation.partitionTargetBytes, DirectTransferLimits.preferredPartitionBytes)
        XCTAssertEqual(negotiation.maximumInFlightChunks, 4)

        let payload = Data(repeating: 0xab, count: 4_096)
        let digest = DirectTransferFile.sha256Hex(payload)
        let chunk = try DirectTransferChunk(
            transferID: UUID(),
            sequence: 1,
            data: payload,
            sha256: digest
        )
        let frame = try DirectTransferBinaryFrame.encode(chunk)
        XCTAssertTrue(DirectTransferBinaryFrame.isBinaryFrame(frame))
        let decoded = try DirectTransferBinaryFrame.decode(frame)
        XCTAssertEqual(decoded.version, DirectTransferBinaryFrame.currentVersion)
        XCTAssertEqual(decoded.chunk, chunk)

        XCTAssertThrowsError(try DirectTransferChunk(
            transferID: UUID(),
            sequence: 1,
            data: Data(repeating: 0, count: DirectTransferLimits.chunkBytes + 1),
            sha256: digest
        ))

        let logicalItemBytes = 160 * 1_024 * 1_024 as Int64
        let firstSegment = try DirectTransferItemSegment(
            itemID: "2026-07-01",
            offset: 0,
            itemByteCount: logicalItemBytes,
            isFinalSegment: false
        )
        XCTAssertNoThrow(try DirectTransferPartition(
            index: 0,
            transferID: UUID(),
            sourceDates: ["2026-07-01"],
            byteCount: DirectTransferLimits.preferredPartitionBytes,
            chunkCount: 96,
            sha256: String(repeating: "a", count: 64),
            previousSHA256: nil,
            itemSegment: firstSegment
        ))
        XCTAssertThrowsError(try DirectTransferItemSegment(
            itemID: "2026-07-01",
            offset: logicalItemBytes + 1,
            itemByteCount: logicalItemBytes,
            isFinalSegment: true
        ))
    }
}

private final class InMemoryDirectTrustStore: ManualIPTrustStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ManualIPTrustState

    init(state: ManualIPTrustState) {
        self.state = state
    }

    func loadState(ownerInstallationID: UUID) -> ManualIPTrustState {
        lock.withLock {
            state.ownerInstallationID == ownerInstallationID
                ? state
                : ManualIPTrustState(ownerInstallationID: ownerInstallationID)
        }
    }

    func saveState(_ state: ManualIPTrustState) throws {
        lock.withLock { self.state = state }
    }
}

private final class ReplayPacketTransport: DirectPacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [ManualIPSyncPacket] = []

    func send(_ packet: ManualIPSyncPacket) async throws {
        lock.withLock { packets.append(packet) }
    }

    func receive() async throws -> ManualIPSyncPacket {
        try lock.withLock {
            guard !packets.isEmpty else { throw DirectChannelError.connectionClosed }
            return packets.removeFirst()
        }
    }

    func cancel() {}

    func duplicateLastPacket() {
        lock.lock()
        if let packet = packets.last { packets.append(packet) }
        lock.unlock()
    }
}
