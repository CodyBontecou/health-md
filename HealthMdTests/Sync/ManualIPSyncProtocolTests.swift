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
            codeVerifier: Data([7, 8, 9])
        )
        let packet = ManualIPSyncPacket.pairingRequest(request)

        let data = try JSONEncoder().encode(packet)
        let decoded = try JSONDecoder().decode(ManualIPSyncPacket.self, from: data)

        XCTAssertEqual(decoded, packet)
    }
}
