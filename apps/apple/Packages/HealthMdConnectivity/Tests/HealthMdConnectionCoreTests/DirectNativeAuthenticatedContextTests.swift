import CryptoKit
import Foundation
import XCTest
@testable import HealthMdConnectionCore

final class DirectNativeAuthenticatedContextTests: XCTestCase {
    func testActualTrustedHandshakeReturnsContextForExactChannelAndCredential() async throws {
        let rig = NativeSessionHandshakeFixture()
        let channel = try await rig.authenticate()
        let context = try XCTUnwrap(channel.clientAuthenticatedContext)
        XCTAssertEqual(context.sourceInstallationID, rig.source)
        XCTAssertEqual(context.hostInstallationID, rig.host)
        XCTAssertNoThrow(try context.requireCurrent(on: channel, sourceInstallationID: rig.source,
                                                    hostInstallationID: rig.host, reconnectSecret: rig.secret))
        XCTAssertEqual(rig.transport.requests.first?.protocolVersion, 1)
        XCTAssertEqual(rig.store.saves, 1) // The existing reconnect writer still executes.
    }

    func testObservedCloseInvalidatesHeldAndCopiedContextPermanently() async throws {
        let rig = NativeSessionHandshakeFixture()
        let channel = try await rig.authenticate()
        let context = try XCTUnwrap(channel.clientAuthenticatedContext)
        let copy = context
        channel.cancel()
        XCTAssertThrowsError(try context.requireCurrent(on: channel))
        XCTAssertThrowsError(try copy.requireCurrent(on: channel))
    }

    func testOrdinaryConstructionAndSameKeyCloneNeverInheritProvenance() async throws {
        let rig = NativeSessionHandshakeFixture()
        let accepted = try await rig.authenticate()
        let clone = DirectSecureChannel(packetConnection: rig.transport, sessionKey: accepted.sessionKey,
            peerInstallationID: accepted.peerInstallationID, peerDisplayName: accepted.peerDisplayName)
        XCTAssertNil(clone.clientAuthenticatedContext)
        let context = try XCTUnwrap(accepted.clientAuthenticatedContext)
        XCTAssertThrowsError(try context.requireCurrent(on: clone))
        XCTAssertThrowsError(try clone.attachClientAuthenticatedContext(context))
        XCTAssertThrowsError(try accepted.attachClientAuthenticatedContext(context))
        XCTAssertNoThrow(try context.requireCurrent(on: accepted))
    }

    func testVerifiedLegacyAndSharedPairingHaveProofButRemainProvisionalTrust() async throws {
        for code in ["123456", "12345678901234567890"] {
            let rig = NativeSessionHandshakeFixture(pairingCode: code)
            let channel = try await rig.authenticate(pairingCode: code)
            let context = try XCTUnwrap(channel.clientAuthenticatedContext)
            XCTAssertNoThrow(try context.requireCurrent(on: channel, sourceInstallationID: rig.source,
                hostInstallationID: rig.host, reconnectSecret: rig.secret))
            let saved = rig.store.loadState(ownerInstallationID: rig.source)
            XCTAssertNil(saved.trustedMac)
            XCTAssertNotNil(saved.provisionalTrustedMac)
            XCTAssertEqual(rig.transport.requests.first?.protocolVersion, code.count == 6 ? 1 : 3)
        }
    }

    func testBadActualServerProofWrongPeerOrCredentialCannotReturnAChannel() async throws {
        for fault in [NativeSessionPacketPeer.Fault.proof, .identity, .credential, .invalidCredentialSize] {
            let rig = NativeSessionHandshakeFixture(fault: fault)
            do { _ = try await rig.authenticate(); XCTFail("Rejected native authentication returned a channel.") }
            catch {}
            XCTAssertEqual(rig.store.saves, 0)
        }
    }

    func testWrongActualPairingCodeIsRejectedWithoutProvenanceOrSave() async throws {
        for code in ["123456", "12345678901234567890"] {
            let rig = NativeSessionHandshakeFixture(pairingCode: code)
            let wrong = String(repeating: "9", count: code.count)
            do { _ = try await rig.authenticate(pairingCode: wrong); XCTFail("Wrong proof returned a channel.") }
            catch {}
            XCTAssertEqual(rig.store.saves, 0)
        }
    }

    func testWrongSourceHostOrCredentialCannotUseRealContext() async throws {
        let rig = NativeSessionHandshakeFixture()
        let channel = try await rig.authenticate()
        let context = try XCTUnwrap(channel.clientAuthenticatedContext)
        XCTAssertThrowsError(try context.requireCurrent(on: channel, sourceInstallationID: rig.host, hostInstallationID: rig.host, reconnectSecret: rig.secret))
        XCTAssertThrowsError(try context.requireCurrent(on: channel, sourceInstallationID: rig.source, hostInstallationID: rig.source, reconnectSecret: rig.secret))
        XCTAssertThrowsError(try context.requireCurrent(on: channel, sourceInstallationID: rig.source, hostInstallationID: rig.host, reconnectSecret: Data(repeating: 0x40, count: 32)))
        XCTAssertThrowsError(try context.requireCurrent(on: channel, sourceInstallationID: rig.source, hostInstallationID: rig.host, reconnectSecret: Data(repeating: 0x39, count: 31)))
        XCTAssertNoThrow(try context.requireCurrent(on: channel, sourceInstallationID: rig.source, hostInstallationID: rig.host, reconnectSecret: rig.secret))
        XCTAssertEqual(String(describing: context), "native_client_authentication")
        XCTAssertEqual(String(reflecting: context), "native_client_authentication")
        XCTAssertEqual(Mirror(reflecting: context).children.count, 0)
    }

    func testObservedTransportFailureCannotReviveAfterSyntheticTransportRestoration() async throws {
        let rig = NativeSessionHandshakeFixture()
        let channel = try await rig.authenticate()
        let context = try XCTUnwrap(channel.clientAuthenticatedContext)
        rig.transport.cancel()
        // Remote/external transport closure isn't claimed until observed by a channel operation.
        do { _ = try await channel.receive(); XCTFail("Expected transport failure.") } catch {}
        rig.transport.restoreForTest()
        XCTAssertTrue(channel.isLocallyTerminal)
        XCTAssertThrowsError(try context.requireCurrent(on: channel))
    }

    func testUnencryptedAndReplayedPacketsRevokeOnlyAfterActualReceiveFailure() async throws {
        let rig = NativeSessionHandshakeFixture()
        let channel = try await rig.authenticate()
        let context = try XCTUnwrap(channel.clientAuthenticatedContext)
        rig.transport.enqueueUnauthenticated()
        do { _ = try await channel.receive(); XCTFail("Expected unauthenticated packet failure.") } catch {}
        XCTAssertThrowsError(try context.requireCurrent(on: channel))
        let second = NativeSessionHandshakeFixture()
        let healthy = try await second.authenticate()
        try second.transport.enqueue(.ping)
        second.transport.duplicateLastPacket()
        _ = try await healthy.receive()
        do { _ = try await healthy.receive(); XCTFail("Expected replay failure.") } catch {}
        XCTAssertThrowsError(try XCTUnwrap(healthy.clientAuthenticatedContext).requireCurrent(on: healthy))
    }

    func testRecoverableLegacyOversizedSendKeepsSocketAndNextSequenceWhileProvenanceRevokes() async throws {
        let rig = NativeSessionHandshakeFixture()
        let channel = try await rig.authenticate()
        let context = try XCTUnwrap(channel.clientAuthenticatedContext)
        let oversized = Data("HMDDIRCT".utf8) + Data(repeating: 0x55, count: HealthMdDirectProtocol.maximumPacketBytes)
        do { try await channel.sendBinaryTransferFrame(oversized); XCTFail("Expected original local packet-size failure.") }
        catch let error as DirectChannelError { XCTAssertEqual(error, .frameTooLarge) }
        XCTAssertThrowsError(try context.requireCurrent(on: channel))
        XCTAssertEqual(rig.transport.cancellations, 0)
        // Legacy allocate-before-send semantics consume sequence0 despite the local failure.
        // The NEW terminal flag must not close/early-reject this old operation or reset sequence.
        try await channel.send(.ping)
        let sent = try XCTUnwrap(rig.transport.outbound.last)
        let opened = try ManualIPSyncSecurity.open(sent, using: channel.sessionKey)
        XCTAssertEqual(Array(opened.prefix(16)), Array("HMDSC001".utf8) + [0, 0, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(String(data: opened.dropFirst(16), encoding: .utf8), "{\"ping\":{}}")
        XCTAssertEqual(rig.transport.cancellations, 0)
        try rig.transport.enqueue(.pong)
        guard case .message(.pong) = try await channel.receive() else { return XCTFail("Legacy receive unexpectedly changed.") }
        XCTAssertThrowsError(try context.requireCurrent(on: channel))
    }

    func testMalformedLegacyPairingCredentialPreservesOldAcceptanceButCannotAttest() async throws {
        let rig = NativeSessionHandshakeFixture(pairingCode: "123456", fault: .invalidCredentialSize)
        let channel = try await rig.authenticate(pairingCode: "123456")
        XCTAssertNil(channel.clientAuthenticatedContext)
        XCTAssertEqual(rig.store.saves, 1)
    }
}


// SYNTHETIC HANDSHAKE HELPERS
// External in-process packet and legacy storage boundaries only. Actual client verification,
// Curve25519/HMAC/AEAD and existing writer operations execute; no fake proof/capsule is supplied.
nonisolated final class NativeSessionHandshakeFixture: @unchecked Sendable {
    let source = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let host = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    let secret = Data(repeating: 0x39, count: 32)
    let store: NativeSessionMemoryTrust
    let transport: NativeSessionPacketPeer
    let client: DirectManualIPClient
    init(pairingCode: String? = nil, fault: NativeSessionPacketPeer.Fault = .none) {
        let trusted = pairingCode == nil ? ManualIPTrustedMac(installationID: host, displayName: "synthetic host",
            host: "synthetic", port: 17647, reconnectSecret: secret, pairedAt: Date(timeIntervalSinceReferenceDate: 12.25)) : nil
        store = NativeSessionMemoryTrust(state: .init(ownerInstallationID: source, trustedMac: trusted))
        transport = NativeSessionPacketPeer(source: source, host: host, secret: secret, pairingCode: pairingCode, fault: fault)
        client = DirectManualIPClient(installationID: source, displayName: "synthetic source", trustStore: store)
    }
    func authenticate(pairingCode: String? = nil) async throws -> DirectSecureChannel {
        try await client.authenticate(transport, host: "synthetic", port: 17647, pairingCode: pairingCode)
    }
}

nonisolated final class NativeSessionMemoryTrust: ManualIPTrustStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ManualIPTrustState
    private var count = 0
    var saves: Int { lock.withLock { count } }
    init(state: ManualIPTrustState) { self.state = state }
    func loadState(ownerInstallationID: UUID) -> ManualIPTrustState { lock.withLock { state } }
    func saveState(_ value: ManualIPTrustState) throws { lock.withLock { state = value; count += 1 } }
}

nonisolated final class NativeSessionPacketPeer: DirectPacketTransport, @unchecked Sendable {
    enum Fault: Sendable { case none, proof, identity, credential, invalidCredentialSize, malformedEncrypted, closed, saveCancellation }
    private let lock = NSLock()
    private let source: UUID
    private let host: UUID
    private let secret: Data
    private let pairingCode: String?
    private let fault: Fault
    private var packets: [ManualIPSyncPacket] = []
    private var recorded: [ManualIPPairingRequest] = []
    private var cancelled = false
    private var key: SymmetricKey?
    private var nextSequence: UInt64 = 0
    private var sent: [ManualIPEncryptedFrame] = []
    private var cancellationCount = 0
    var outbound: [ManualIPEncryptedFrame] { lock.withLock { sent } }
    var cancellations: Int { lock.withLock { cancellationCount } }
    var requests: [ManualIPPairingRequest] { lock.withLock { recorded } }
    init(source: UUID, host: UUID, secret: Data, pairingCode: String?, fault: Fault) {
        self.source = source; self.host = host; self.secret = secret; self.pairingCode = pairingCode; self.fault = fault
    }
    func send(_ packet: ManualIPSyncPacket) async throws {
        try lock.withLock {
            guard !cancelled else { throw DirectChannelError.connectionClosed }
            // Same external packet-size boundary as DirectPacketConnection, not a channel validator.
            guard try JSONEncoder().encode(packet).count <= HealthMdDirectProtocol.maximumPacketBytes else { throw DirectChannelError.frameTooLarge }
            if case .encrypted(let frame) = packet { sent.append(frame); return }
            guard case .pairingRequest(let request) = packet else { return }
            recorded.append(request)
            guard request.clientInstallationID == source else { throw DirectChannelError.authenticationFailed("Synthetic peer rejected identity.") }
            if let pairingCode {
                let valid = request.protocolVersion == 3
                    ? DirectPairingSecurity.sharedPairingVerifierIsValid(request.codeVerifier, pairingCode: pairingCode, clientInstallationID: source, clientPublicKey: request.clientPublicKey, clientNonce: request.clientNonce)
                    : DirectPairingSecurity.pairingVerifierIsValid(request.codeVerifier, pairingCode: pairingCode, clientInstallationID: source, clientPublicKey: request.clientPublicKey, clientNonce: request.clientNonce)
                guard valid else { packets.append(.pairingRejected(.init(reason: "Synthetic proof rejected."))); return }
            } else {
                guard let proof = request.trustedVerifier, request.codeVerifier.isEmpty,
                      DirectPairingSecurity.trustedClientVerifierIsValid(proof, reconnectSecret: secret, clientInstallationID: source, clientPublicKey: request.clientPublicKey, clientNonce: request.clientNonce) else {
                    packets.append(.pairingRejected(.init(reason: "Synthetic proof rejected."))); return
                }
            }
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let publicKey = privateKey.publicKey.rawRepresentation
            let serverNonce = Data(repeating: 0x25, count: 32)
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: request.clientPublicKey))
            let sessionKey = DirectPairingSecurity.sessionKey(sharedSecret: shared, clientNonce: request.clientNonce, serverNonce: serverNonce)
            key = sessionKey
            let responseHost = fault == .identity ? UUID(uuidString: "00000000-0000-4000-8000-000000000099")! : host
            let openedSecret = fault == .credential ? Data(repeating: 0x78, count: 32) : (fault == .invalidCredentialSize ? Data(repeating: 0x39, count: 31) : secret)
            let sealed = try ManualIPSyncSecurity.seal(openedSecret, using: sessionKey)
            let proof: Data
            if let pairingCode {
                if request.protocolVersion == 3 {
                    proof = DirectPairingSecurity.sharedPairingServerVerifier(pairingCode: pairingCode, clientInstallationID: source, clientPublicKey: request.clientPublicKey, clientNonce: request.clientNonce, serverInstallationID: responseHost, serverPublicKey: publicKey, serverNonce: serverNonce, sealedReconnectSecret: sealed)
                } else {
                    proof = DirectPairingSecurity.pairingServerVerifier(pairingCode: pairingCode, clientInstallationID: source, clientPublicKey: request.clientPublicKey, clientNonce: request.clientNonce, serverInstallationID: responseHost, serverPublicKey: publicKey, serverNonce: serverNonce, sealedReconnectSecret: sealed)
                }
            } else {
                proof = DirectPairingSecurity.trustedServerVerifier(reconnectSecret: secret, clientInstallationID: source, clientPublicKey: request.clientPublicKey, clientNonce: request.clientNonce, serverInstallationID: responseHost, serverPublicKey: publicKey, serverNonce: serverNonce)
            }
            packets.append(.pairingResponse(.init(protocolVersion: request.protocolVersion, macName: "synthetic host", serverPublicKey: publicKey,
                serverNonce: serverNonce, macInstallationID: responseHost, authenticationVerifier: fault == .proof ? Data(repeating: 0, count: 32) : proof,
                sealedReconnectSecret: sealed)))
        }
    }
    func receive() async throws -> ManualIPSyncPacket {
        try lock.withLock {
            guard !cancelled, !packets.isEmpty else { throw DirectChannelError.connectionClosed }
            return packets.removeFirst()
        }
    }
    func cancel() { lock.withLock { cancelled = true; cancellationCount += 1 } }
    func restoreForTest() { lock.withLock { cancelled = false } }
    func duplicateLastPacket() { lock.withLock { if let last = packets.last { packets.append(last) } } }
    func enqueue(_ message: DirectMessage) throws {
        try lock.withLock {
            guard let key else { throw DirectChannelError.connectionClosed }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
            var envelope = Data("HMDSC001".utf8); var sequence = nextSequence.bigEndian
            withUnsafeBytes(of: &sequence) { envelope.append(contentsOf: $0) }; nextSequence += 1
            envelope.append(try encoder.encode(message))
            packets.append(.encrypted(try ManualIPSyncSecurity.seal(envelope, using: key)))
        }
    }
    func enqueueUnauthenticated() { lock.withLock { packets.append(.pairingRejected(.init(reason: "Synthetic unencrypted packet."))) } }
}
