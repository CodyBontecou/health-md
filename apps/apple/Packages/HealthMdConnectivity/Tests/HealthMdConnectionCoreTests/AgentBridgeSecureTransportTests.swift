import CryptoKit
import Foundation
import Network
import XCTest
@testable import HealthMdConnectionCore

/// Actual native loopback sockets, deployed packet framing, CryptoKit AEAD and sequence checks.
/// The synthetic owner callback is not pairing/consent or installed source qualification.
final class AgentBridgeSecureTransportTests: XCTestCase {
    private func negotiation(_ versions: [Int] = [1, 3, 4]) throws -> AgentBridgeNegotiation {
        try .init(localVersions: versions, remoteVersions: versions, deployedBaseVersion: 1)
    }
    private func request() throws -> AgentBridgeEnvelope {
        let peer = AgentBridgePeer(sourceInstallationID: try id(1), hostInstallationID: try id(2), platform: .apple)
        return try .init(payload: .discoveryRequest(.init(requestID: try id(100), peer: peer)))
    }
    private func id(_ value: Int) throws -> AgentBridgeUUID { try .init(String(format: "00000000-0000-4000-8000-%012x", value)) }

    func testActualSocketsMixBridgeAndLegacyWithTheSameSequence() async throws {
        let pair = try await pair(); defer { pair.close() }
        let fence = WireFence(), neg = try negotiation(), expected = try request()
        try await pair.sender.sendAgentBridge(expected, negotiation: neg, authorize: { try fence.requireCurrent() })
        let first = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg, authorize: { try fence.requireCurrent() })
        XCTAssertEqual(first, .agent(expected))
        try await pair.sender.send(.ping)
        let second = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg, authorize: { try fence.requireCurrent() })
        XCTAssertEqual(second, .base(.ping))
        try await pair.sender.sendAgentBridge(expected, negotiation: neg, authorize: { try fence.requireCurrent() })
        let third = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg, authorize: { try fence.requireCurrent() })
        XCTAssertEqual(third, .agent(expected))
        XCTAssertNil(pair.sender.clientAuthenticatedContext) // Transport is never authenticated native authority.
    }

    func testGuardedBaseAndMaximumChunkShareUnchangedBridgeSequence() async throws {
        let pair = try await pair(); defer { pair.close() }
        let fence = WireFence(), neg = try negotiation(), expected = try request()
        let data = Data(repeating: 0xab, count: DirectTransferLimits.chunkBytes)
        let chunk = try DirectTransferChunk(transferID: UUID(), sequence: 1, data: data, sha256: DirectTransferFile.sha256Hex(data))
        try await pair.sender.sendAgentBridge(expected, negotiation: neg) { try fence.requireCurrent() }
        let first = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg) { try fence.requireCurrent() }
        XCTAssertEqual(first, .agent(expected))
        try await pair.sender.sendBaseForAgentBridge(.ping, negotiation: neg) { try fence.requireCurrent() }
        let second = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg) { try fence.requireCurrent() }
        XCTAssertEqual(second, .base(.ping))
        // Receive concurrently: maximum binary payloads can fill a native socket buffer.
        async let received = pair.receiver.receiveAllowingAgentBridge(negotiation: neg) { try fence.requireCurrent() }
        try await pair.sender.sendTransferChunkForAgentBridge(chunk, negotiation: neg) { try fence.requireCurrent() }
        let third = try await received
        XCTAssertEqual(third, .binaryTransferFrame(try DirectTransferBinaryFrame.encode(chunk)))
        try await pair.sender.send(.ping)
        let fourth = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg) { try fence.requireCurrent() }
        XCTAssertEqual(fourth, .base(.ping))
        XCTAssertGreaterThan(fence.checks, 64, "Maximum chunks must use repeated bounded owner fences")
    }

    func testGuardedChunkRevocationStopsPartialPacketAndCannotRevive() async throws {
        let pair = try await pair(); defer { pair.close() }
        let data = Data(repeating: 0xab, count: 96 * 1024)
        let chunk = try DirectTransferChunk(transferID: UUID(), sequence: 1, data: data, sha256: DirectTransferFile.sha256Hex(data))
        let fence = WireFence(failAt: 4), neg = try negotiation()
        do { try await pair.sender.sendTransferChunkForAgentBridge(chunk, negotiation: neg) { try fence.requireCurrent() }; XCTFail("Expected partial chunk denial") }
        catch { }
        let partial = try await readUntilClosed(pair.server.connection)
        XCTAssertEqual(fence.checks, 4); XCTAssertFalse(partial.isEmpty)
        XCTAssertLessThanOrEqual(partial.count, 16 * 1024)
        XCTAssertTrue(pair.sender.isLocallyTerminal)
        let restored = WireFence()
        do { try await pair.sender.sendBaseForAgentBridge(.ping, negotiation: neg) { try restored.requireCurrent() }; XCTFail("No revival") }
        catch { }
        XCTAssertEqual(restored.checks, 0)
    }

    func testGuardedChunkRejectsIncorrectDigestBeforeOwnerOrSequence() async throws {
        let pair = try await pair(); defer { pair.close() }
        let fence = WireFence(), neg = try negotiation()
        let chunk = try DirectTransferChunk(transferID: UUID(), sequence: 1, data: Data([1]), sha256: String(repeating: "0", count: 64))
        do { try await pair.sender.sendTransferChunkForAgentBridge(chunk, negotiation: neg) { try fence.requireCurrent() }; XCTFail("Expected digest denial") }
        catch { XCTAssertEqual(error as? DirectTransferError, .invalidDigest) }
        XCTAssertEqual(fence.checks, 0); XCTAssertFalse(pair.sender.isLocallyTerminal)
        try await pair.sender.sendBaseForAgentBridge(.ping, negotiation: neg) { try fence.requireCurrent() }
        let value = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg) { try fence.requireCurrent() }
        XCTAssertEqual(value, .base(.ping))
    }

    func testUnnegotiatedOrUnguardedTransportCannotProbeOrConsumeIO() async throws {
        let transport = UnguardedWirePeer()
        let channel = DirectSecureChannel(packetConnection: transport, sessionKey: SymmetricKey(data: Data(repeating: 7, count: 32)), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let fence = WireFence()
        do { try await channel.sendAgentBridge(request(), negotiation: negotiation([1, 3]), authorize: { try fence.requireCurrent() }); XCTFail("Expected unsupported peer") } catch { }
        do { _ = try await channel.receiveAllowingAgentBridge(negotiation: negotiation([1]), authorize: { try fence.requireCurrent() }); XCTFail("Expected no probe") } catch { }
        do { try await channel.sendAgentBridge(request(), negotiation: negotiation(), authorize: { try fence.requireCurrent() }); XCTFail("No unguarded fallback") } catch { }
        do { try await channel.sendBaseForAgentBridge(.ping, negotiation: negotiation([1]), authorize: { try fence.requireCurrent() }); XCTFail("Unsupported base route") } catch { }
        do { try await channel.sendBaseForAgentBridge(.ping, negotiation: negotiation(), authorize: { try fence.requireCurrent() }); XCTFail("No unguarded base fallback") } catch { }
        let bytes = Data([1])
        let chunk = try DirectTransferChunk(transferID: UUID(), sequence: 1, data: bytes, sha256: DirectTransferFile.sha256Hex(bytes))
        do { try await channel.sendTransferChunkForAgentBridge(chunk, negotiation: negotiation([1]), authorize: { try fence.requireCurrent() }); XCTFail("Unsupported chunk route") } catch { }
        do { try await channel.sendTransferChunkForAgentBridge(chunk, negotiation: negotiation(), authorize: { try fence.requireCurrent() }); XCTFail("No unguarded chunk fallback") } catch { }
        XCTAssertEqual(fence.checks, 0)
        XCTAssertEqual(transport.io, 0)
        XCTAssertFalse(channel.isLocallyTerminal)
    }

    func testRevocationAfterFirstBoundedWriteClosesPartialPacketWithoutRetry() async throws {
        let pair = try await pair(); defer { pair.close() }
        let packet = ManualIPSyncPacket.pairingRejected(.init(reason: String(repeating: "x", count: 96 * 1_024)))
        let fullSize = try JSONEncoder().encode(packet).count + 8
        let fence = WireFence(failAt: 3)
        do { try await pair.client.sendGuarded(packet, authorize: { try fence.requireCurrent() }); XCTFail("Expected partial write rejection") } catch { }
        let received = try await readUntilClosed(pair.server.connection)
        XCTAssertEqual(fence.checks, 3)
        XCTAssertLessThanOrEqual(received.count, 16 * 1_024)
        XCTAssertLessThan(received.count, fullSize)
    }

    func testReturnSideRevocationPermanentlyAbandonsBridgeChannel() async throws {
        let pair = try await pair(); defer { pair.close() }
        let neg = try negotiation(), expected = try request()
        try await pair.sender.sendAgentBridge(expected, negotiation: neg, authorize: { try WireFence().requireCurrent() })
        let fence = WireFence(failAt: 2)
        do { _ = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg, authorize: { try fence.requireCurrent() }); XCTFail("Expected return fence") } catch { }
        XCTAssertTrue(pair.receiver.isLocallyTerminal)
        let restored = WireFence()
        do { _ = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg, authorize: { try restored.requireCurrent() }); XCTFail("Stopped channel cannot revive") } catch { }
        XCTAssertEqual(restored.checks, 0)
    }

    func testMalformedV4CannotFallThroughPermissiveLegacyDecoder() async throws {
        for raw in [#"{"protocol_version":4,"ping":{}}"#, #"{"protocol_version":4,"protocol_version":1,"ping":{}}"#, #"{"ping":{},"unknown":{}}"#] {
            let pair = try await pair(); defer { pair.close() }
            try await pair.client.send(encrypted(Data(raw.utf8), sequence: 0, key: pair.key))
            let fence = WireFence()
            do { _ = try await pair.receiver.receiveAllowingAgentBridge(negotiation: negotiation(), authorize: { try fence.requireCurrent() }); XCTFail("Expected strict rejection") } catch { }
            XCTAssertTrue(pair.receiver.isLocallyTerminal)
            XCTAssertEqual(fence.checks, 1)
        }
    }

    func testBridgeStillRejectsReplayedAuthenticatedSequence() async throws {
        let pair = try await pair(); defer { pair.close() }
        let expected = try request(), neg = try negotiation()
        let packet = try encrypted(neg.encode(expected), sequence: 0, key: pair.key)
        try await pair.client.send(packet)
        let first = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg, authorize: { try WireFence().requireCurrent() })
        XCTAssertEqual(first, .agent(expected))
        try await pair.client.send(packet)
        do { _ = try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg, authorize: { try WireFence().requireCurrent() }); XCTFail("Expected replay rejection") } catch { }
        XCTAssertTrue(pair.receiver.isLocallyTerminal)
    }

    func testCancellationInterruptsPendingReceiveAndNeverRevives() async throws {
        let pair = try await pair(); defer { pair.close() }
        let entered = expectation(description: "native receive admitted")
        let neg = try negotiation()
        let task = Task { try await pair.receiver.receiveAllowingAgentBridge(negotiation: neg) { entered.fulfill() } }
        await fulfillment(of: [entered], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected canceled receive") } catch { }
        XCTAssertTrue(pair.receiver.isLocallyTerminal)
    }

    private func encrypted(_ bytes: Data, sequence: UInt64, key: SymmetricKey) throws -> ManualIPSyncPacket {
        var payload = Data("HMDSC001".utf8), value = sequence.bigEndian
        withUnsafeBytes(of: &value) { payload.append(contentsOf: $0) }
        payload.append(bytes)
        return .encrypted(try ManualIPSyncSecurity.seal(payload, using: key))
    }
    private func pair() async throws -> WirePair {
        let queue = DispatchQueue(label: "healthmd.bridge.loopback")
        let listener = try NWListener(using: .tcp)
        let ready = expectation(description: "loopback ready"), accepted = expectation(description: "accepted loopback")
        let box = WireAccepted()
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            let packet = DirectPacketConnection(connection: connection, queue: queue)
            box.set(Task { try await packet.start(timeout: 3); return packet })
            accepted.fulfill()
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 3)
        let client = DirectPacketConnection(connection: NWConnection(host: "127.0.0.1", port: try XCTUnwrap(listener.port), using: .tcp), queue: queue)
        do {
            try await client.start(timeout: 3)
            await fulfillment(of: [accepted], timeout: 3)
            let server = try await XCTUnwrap(box.value).value
            let key = SymmetricKey(data: Data(repeating: 0x51, count: 32))
            return WirePair(listener: listener, client: client, server: server, key: key)
        } catch { listener.cancel(); client.cancel(); throw error }
    }
    private func readUntilClosed(_ connection: NWConnection) async throws -> Data {
        var result = Data()
        while true {
            let value: (Data, Bool) = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { data, _, complete, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (data ?? Data(), complete)) }
                }
            }
            result.append(value.0)
            if value.1 { return result }
            guard result.count <= 2 * 1_024 * 1_024 else { throw DirectChannelError.frameTooLarge }
        }
    }
}

private struct WirePair: Sendable {
    let listener: NWListener
    let client: DirectPacketConnection
    let server: DirectPacketConnection
    let key: SymmetricKey
    var sender: DirectSecureChannel { senderStorage }
    var receiver: DirectSecureChannel { receiverStorage }
    private let senderStorage: DirectSecureChannel
    private let receiverStorage: DirectSecureChannel
    init(listener: NWListener, client: DirectPacketConnection, server: DirectPacketConnection, key: SymmetricKey) {
        self.listener = listener; self.client = client; self.server = server; self.key = key
        senderStorage = DirectSecureChannel(packetConnection: client, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic host")
        receiverStorage = DirectSecureChannel(packetConnection: server, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic source")
    }
    func close() { sender.cancel(); receiver.cancel(); listener.cancel() }
}
private final class WireAccepted: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<DirectPacketConnection, Error>?
    var value: Task<DirectPacketConnection, Error>? { lock.withLock { task } }
    func set(_ value: Task<DirectPacketConnection, Error>) { lock.withLock { task = value } }
}
private final class WireFence: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let failAt: Int?
    var checks: Int { lock.withLock { count } }
    init(failAt: Int? = nil) { self.failAt = failAt }
    func requireCurrent() throws { try lock.withLock { count += 1; if count == failAt { throw DirectChannelError.connectionClosed } } }
}
private final class UnguardedWirePeer: DirectPacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var io: Int { lock.withLock { count } }
    func send(_ packet: ManualIPSyncPacket) async throws { lock.withLock { count += 1 } }
    func receive() async throws -> ManualIPSyncPacket { lock.withLock { count += 1 }; return .pairingRejected(.init(reason: "unused")) }
    func cancel() { }
}
