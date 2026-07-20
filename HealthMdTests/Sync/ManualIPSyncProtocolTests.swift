import CryptoKit
import XCTest
@testable import HealthMd

final class ManualIPSyncProtocolTests: XCTestCase {

    func testPairingVerifierDoesNotRequireSendingCode() {
        let code = "123456"
        let clientKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let nonce = ManualIPSyncSecurity.randomNonce()

        let verifier = ManualIPSyncSecurity.pairingVerifier(
            pairingCode: code,
            clientPublicKey: clientKey,
            clientNonce: nonce
        )

        XCTAssertTrue(ManualIPSyncSecurity.pairingVerifierIsValid(
            verifier,
            pairingCode: code,
            clientPublicKey: clientKey,
            clientNonce: nonce
        ))
        XCTAssertFalse(ManualIPSyncSecurity.pairingVerifierIsValid(
            verifier,
            pairingCode: "000000",
            clientPublicKey: clientKey,
            clientNonce: nonce
        ))
    }

    func testPairingVerifierRetainsLegacyWireVector() {
        let verifier = ManualIPSyncSecurity.pairingVerifier(
            pairingCode: "123456",
            clientPublicKey: Data([1, 2, 3]),
            clientNonce: Data([4, 5, 6])
        )
        let hex = verifier.map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(
            hex,
            "cc2d36da19c1b3b14121ab22d29b0b5c69d2e73bda4a62d766468e780da8ebc4"
        )
    }

    func testPairingDerivesSameSessionKeyAndEncryptsSyncMessage() throws {
        let clientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let serverPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let clientNonce = ManualIPSyncSecurity.randomNonce()
        let serverNonce = ManualIPSyncSecurity.randomNonce()

        let clientSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(with: serverPrivateKey.publicKey)
        let serverSecret = try serverPrivateKey.sharedSecretFromKeyAgreement(with: clientPrivateKey.publicKey)
        let clientKey = ManualIPSyncSecurity.sessionKey(
            sharedSecret: clientSecret,
            clientNonce: clientNonce,
            serverNonce: serverNonce
        )
        let serverKey = ManualIPSyncSecurity.sessionKey(
            sharedSecret: serverSecret,
            clientNonce: clientNonce,
            serverNonce: serverNonce
        )

        let message = SyncMessage.hello(.current(platform: .iOS))
        let encoded = try JSONEncoder().encode(message)
        let sealed = try ManualIPSyncSecurity.seal(encoded, using: clientKey)
        let opened = try ManualIPSyncSecurity.open(sealed, using: serverKey)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: opened)

        guard case .hello(let capabilities) = decoded else {
            return XCTFail("Expected hello message")
        }
        XCTAssertEqual(capabilities.platform, .iOS)
        XCTAssertTrue(capabilities.supportsManualIPSync)
    }

    func testManualIPPacketCodableRoundTrip() throws {
        let request = ManualIPPairingRequest(
            deviceName: "iPhone",
            clientPublicKey: Data([1, 2, 3]),
            clientNonce: Data([4, 5, 6]),
            codeVerifier: Data([7, 8, 9]),
            clientInstallationID: UUID(),
            trustedVerifier: Data([10, 11, 12])
        )
        let packet = ManualIPSyncPacket.pairingRequest(request)

        let data = try JSONEncoder().encode(packet)
        let decoded = try JSONDecoder().decode(ManualIPSyncPacket.self, from: data)

        XCTAssertEqual(decoded, packet)
    }

    func testLegacyPairingResponseDecodesWithoutDurableTrustFields() throws {
        struct LegacyResponse: Encodable {
            let protocolVersion = ManualIPSyncSecurity.legacyProtocolVersion
            let macName = "Mac"
            let serverPublicKey = Data([1, 2, 3])
            let serverNonce = Data([4, 5, 6])
        }

        let data = try JSONEncoder().encode(LegacyResponse())
        let response = try JSONDecoder().decode(ManualIPPairingResponse.self, from: data)

        XCTAssertEqual(response.protocolVersion, ManualIPSyncSecurity.legacyProtocolVersion)
        XCTAssertNil(response.macInstallationID)
        XCTAssertNil(response.authenticationVerifier)
        XCTAssertNil(response.sealedReconnectSecret)
    }

    func testPairingServerProofBindsReconnectCredentialAndBothPeers() {
        let clientID = UUID()
        let macID = UUID()
        let sealedSecret = ManualIPEncryptedFrame(
            nonce: Data([1, 2]),
            ciphertext: Data([3, 4]),
            tag: Data([5, 6])
        )
        let verifier = ManualIPSyncSecurity.pairingServerVerifier(
            pairingCode: "123456",
            clientInstallationID: clientID,
            clientPublicKey: Data([7, 8]),
            clientNonce: Data([9, 10]),
            macInstallationID: macID,
            serverPublicKey: Data([11, 12]),
            serverNonce: Data([13, 14]),
            sealedReconnectSecret: sealedSecret
        )

        XCTAssertTrue(ManualIPSyncSecurity.pairingServerVerifierIsValid(
            verifier,
            pairingCode: "123456",
            clientInstallationID: clientID,
            clientPublicKey: Data([7, 8]),
            clientNonce: Data([9, 10]),
            macInstallationID: macID,
            serverPublicKey: Data([11, 12]),
            serverNonce: Data([13, 14]),
            sealedReconnectSecret: sealedSecret
        ))
        XCTAssertFalse(ManualIPSyncSecurity.pairingServerVerifierIsValid(
            verifier,
            pairingCode: "123456",
            clientInstallationID: clientID,
            clientPublicKey: Data([7, 8]),
            clientNonce: Data([9, 10]),
            macInstallationID: UUID(),
            serverPublicKey: Data([11, 12]),
            serverNonce: Data([13, 14]),
            sealedReconnectSecret: sealedSecret
        ))
    }

    func testTrustedReconnectMutuallyAuthenticatesFreshHandshake() {
        let reconnectSecret = Data(repeating: 42, count: ManualIPSyncSecurity.reconnectSecretByteCount)
        let clientID = UUID()
        let macID = UUID()
        let clientPublicKey = Data([1, 2, 3])
        let clientNonce = Data([4, 5, 6])
        let serverPublicKey = Data([7, 8, 9])
        let serverNonce = Data([10, 11, 12])

        let clientVerifier = ManualIPSyncSecurity.trustedClientVerifier(
            reconnectSecret: reconnectSecret,
            clientInstallationID: clientID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        )
        XCTAssertTrue(ManualIPSyncSecurity.trustedClientVerifierIsValid(
            clientVerifier,
            reconnectSecret: reconnectSecret,
            clientInstallationID: clientID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        ))

        let serverVerifier = ManualIPSyncSecurity.trustedServerVerifier(
            reconnectSecret: reconnectSecret,
            clientInstallationID: clientID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            macInstallationID: macID,
            serverPublicKey: serverPublicKey,
            serverNonce: serverNonce
        )
        XCTAssertTrue(ManualIPSyncSecurity.trustedServerVerifierIsValid(
            serverVerifier,
            reconnectSecret: reconnectSecret,
            clientInstallationID: clientID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            macInstallationID: macID,
            serverPublicKey: serverPublicKey,
            serverNonce: serverNonce
        ))
        XCTAssertFalse(ManualIPSyncSecurity.trustedServerVerifierIsValid(
            serverVerifier,
            reconnectSecret: reconnectSecret,
            clientInstallationID: clientID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            macInstallationID: macID,
            serverPublicKey: serverPublicKey,
            serverNonce: Data([99])
        ))
    }

    func testTrustStateCodableRoundTripPreservesReconnectCredential() throws {
        let ownerID = UUID()
        let macID = UUID()
        let state = ManualIPTrustState(
            ownerInstallationID: ownerID,
            trustedMac: ManualIPTrustedMac(
                installationID: macID,
                displayName: "MacBook",
                host: "100.64.0.1",
                port: 17_646,
                reconnectSecret: Data(repeating: 7, count: ManualIPSyncSecurity.reconnectSecretByteCount),
                pairedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ManualIPTrustState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    func testTrustStateReplacesClientWithSameInstallationID() {
        let ownerID = UUID()
        let clientID = UUID()
        var state = ManualIPTrustState(ownerInstallationID: ownerID)
        state.saveTrustedClient(ManualIPTrustedClient(
            installationID: clientID,
            displayName: "Old Name",
            reconnectSecret: Data([1]),
            pairedAt: .distantPast,
            lastConnectedAt: .distantPast
        ))
        state.saveTrustedClient(ManualIPTrustedClient(
            installationID: clientID,
            displayName: "New Name",
            reconnectSecret: Data([2]),
            pairedAt: .distantPast,
            lastConnectedAt: .distantFuture
        ))

        XCTAssertEqual(state.trustedClients.count, 1)
        XCTAssertEqual(state.trustedClient(installationID: clientID)?.displayName, "New Name")
        XCTAssertEqual(state.trustedClient(installationID: clientID)?.reconnectSecret, Data([2]))
    }
}
