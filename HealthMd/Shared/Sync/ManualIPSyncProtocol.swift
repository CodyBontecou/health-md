import CryptoKit
import Foundation
import Security

// MARK: - Manual IP / Tailscale Sync Protocol

/// Shared constants and helpers for the opt-in manual IP/Tailscale transport.
///
/// The pairing code is never sent over the wire. The iPhone proves it knows the
/// code with an HMAC over its ephemeral Curve25519 public key + nonce. After the
/// Mac verifies the code, both sides derive a per-connection symmetric key and
/// encrypt all `SyncMessage` frames with ChaChaPoly.
enum ManualIPSyncSecurity {
    static let protocolVersion = 1
    static let defaultPort: UInt16 = 17_646
    static let maxFrameSize = 100 * 1_024 * 1_024
    static let pairingCodeLifetime: TimeInterval = 10 * 60

    private static let verifierDomain = Data("HealthMd.ManualIP.PairingVerifier.v1".utf8)
    private static let sessionKeyDomain = Data("HealthMd.ManualIP.SessionKey.v1".utf8)

    static func normalizedPairingCode(_ code: String) -> String {
        code.filter(\.isNumber)
    }

    static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    static func randomNonce(byteCount: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        return Data((0..<byteCount).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }

    static func pairingVerifier(
        pairingCode: String,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Data {
        let normalizedCode = normalizedPairingCode(pairingCode)
        let codeHash = SHA256.hash(data: Data("HealthMd.ManualIP.Code.\(normalizedCode)".utf8))
        let key = SymmetricKey(data: Data(codeHash))
        var payload = verifierDomain
        payload.append(clientPublicKey)
        payload.append(clientNonce)
        let code = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(code)
    }

    static func pairingVerifierIsValid(
        _ verifier: Data,
        pairingCode: String,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Bool {
        timingSafeCompare(
            verifier,
            pairingVerifier(
                pairingCode: pairingCode,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce
            )
        )
    }

    static func sessionKey(
        sharedSecret: SharedSecret,
        clientNonce: Data,
        serverNonce: Data
    ) -> SymmetricKey {
        let secretData = sharedSecret.withUnsafeBytes { Data($0) }
        var payload = sessionKeyDomain
        payload.append(secretData)
        payload.append(clientNonce)
        payload.append(serverNonce)
        let hash = SHA256.hash(data: payload)
        return SymmetricKey(data: Data(hash))
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> ManualIPEncryptedFrame {
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
        return ManualIPEncryptedFrame(
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    static func open(_ frame: ManualIPEncryptedFrame, using key: SymmetricKey) throws -> Data {
        let nonce = try ChaChaPoly.Nonce(data: frame.nonce)
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: frame.ciphertext,
            tag: frame.tag
        )
        return try ChaChaPoly.open(sealedBox, using: key)
    }

    static func timingSafeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }
}

struct ManualIPPairingRequest: Codable, Equatable {
    let protocolVersion: Int
    let deviceName: String
    let clientPublicKey: Data
    let clientNonce: Data
    let codeVerifier: Data

    init(
        protocolVersion: Int = ManualIPSyncSecurity.protocolVersion,
        deviceName: String,
        clientPublicKey: Data,
        clientNonce: Data,
        codeVerifier: Data
    ) {
        self.protocolVersion = protocolVersion
        self.deviceName = deviceName
        self.clientPublicKey = clientPublicKey
        self.clientNonce = clientNonce
        self.codeVerifier = codeVerifier
    }
}

struct ManualIPPairingResponse: Codable, Equatable {
    let protocolVersion: Int
    let macName: String
    let serverPublicKey: Data
    let serverNonce: Data

    init(
        protocolVersion: Int = ManualIPSyncSecurity.protocolVersion,
        macName: String,
        serverPublicKey: Data,
        serverNonce: Data
    ) {
        self.protocolVersion = protocolVersion
        self.macName = macName
        self.serverPublicKey = serverPublicKey
        self.serverNonce = serverNonce
    }
}

struct ManualIPPairingRejected: Codable, Equatable {
    let reason: String
}

struct ManualIPEncryptedFrame: Codable, Equatable {
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

enum ManualIPSyncPacket: Codable, Equatable {
    case pairingRequest(ManualIPPairingRequest)
    case pairingResponse(ManualIPPairingResponse)
    case pairingRejected(ManualIPPairingRejected)
    case encrypted(ManualIPEncryptedFrame)
}

struct ManualIPNetworkAddress: Identifiable, Equatable {
    var id: String { "\(interfaceName)-\(address)" }
    let interfaceName: String
    let address: String
    let isLikelyTailscale: Bool

    var displayName: String {
        isLikelyTailscale ? "\(address) · Tailscale" : "\(address) · \(interfaceName)"
    }
}

extension Data {
    mutating func appendManualIPLengthPrefix(_ length: Int) {
        var bigEndianLength = UInt64(length).bigEndian
        Swift.withUnsafeBytes(of: &bigEndianLength) { rawBuffer in
            append(contentsOf: rawBuffer)
        }
    }

    func manualIPLengthPrefix() -> Int? {
        guard count >= 8 else { return nil }
        let value = prefix(8).reduce(UInt64(0)) { partialResult, byte in
            (partialResult << 8) | UInt64(byte)
        }
        guard value <= UInt64(Int.max) else { return nil }
        return Int(value)
    }
}
