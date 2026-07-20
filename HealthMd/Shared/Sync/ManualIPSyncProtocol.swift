import CryptoKit
import Foundation
import Security

// MARK: - Manual IP / Tailscale Sync Protocol

/// Shared constants and helpers for the opt-in manual IP/Tailscale transport.
///
/// The pairing code is never sent over the wire or persisted. The iPhone proves
/// it knows the code with an HMAC over its ephemeral Curve25519 public key and
/// nonce. Current peers then exchange a random reconnect secret inside the
/// encrypted session so later app launches can authenticate without the code.
enum ManualIPSyncSecurity {
    static let legacyProtocolVersion = 1
    static let protocolVersion = 2
    static let defaultPort: UInt16 = 17_646
    static let maxFrameSize = 100 * 1_024 * 1_024
    static let pairingCodeLifetime: TimeInterval = 10 * 60
    static let reconnectSecretByteCount = 32

    private static let verifierDomain = Data("HealthMd.ManualIP.PairingVerifier.v1".utf8)
    private static let sessionKeyDomain = Data("HealthMd.ManualIP.SessionKey.v1".utf8)
    private static let trustedClientDomain = Data("HealthMd.ManualIP.TrustedClient.v1".utf8)
    private static let pairingServerDomain = Data("HealthMd.ManualIP.PairingServer.v1".utf8)
    private static let trustedServerDomain = Data("HealthMd.ManualIP.TrustedServer.v1".utf8)

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
        // Keep the v1 byte layout for code verification so an updated Mac can
        // still accept a legacy iPhone. Protocol v2 adds server authentication
        // separately; changing this verifier would strand mixed-version peers.
        var payload = verifierDomain
        payload.append(clientPublicKey)
        payload.append(clientNonce)
        return authenticationCode(for: payload, keyData: pairingCodeKey(pairingCode))
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

    /// Proves that a reconnecting iPhone still has the random credential issued
    /// during its pairing-code connection.
    static func trustedClientVerifier(
        reconnectSecret: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Data {
        var payload = trustedClientDomain
        appendField(Data(clientInstallationID.uuidString.lowercased().utf8), to: &payload)
        appendField(clientPublicKey, to: &payload)
        appendField(clientNonce, to: &payload)
        return authenticationCode(for: payload, keyData: reconnectSecret)
    }

    static func trustedClientVerifierIsValid(
        _ verifier: Data,
        reconnectSecret: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Bool {
        timingSafeCompare(
            verifier,
            trustedClientVerifier(
                reconnectSecret: reconnectSecret,
                clientInstallationID: clientInstallationID,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce
            )
        )
    }

    /// Authenticates the Mac and binds its ephemeral key to the original pairing
    /// code before the iPhone saves the reconnect credential.
    static func pairingServerVerifier(
        pairingCode: String,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        macInstallationID: UUID,
        serverPublicKey: Data,
        serverNonce: Data,
        sealedReconnectSecret: ManualIPEncryptedFrame
    ) -> Data {
        serverVerifier(
            domain: pairingServerDomain,
            keyData: pairingCodeKey(pairingCode),
            clientInstallationID: clientInstallationID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            macInstallationID: macInstallationID,
            serverPublicKey: serverPublicKey,
            serverNonce: serverNonce,
            sealedReconnectSecret: sealedReconnectSecret
        )
    }

    static func pairingServerVerifierIsValid(
        _ verifier: Data,
        pairingCode: String,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        macInstallationID: UUID,
        serverPublicKey: Data,
        serverNonce: Data,
        sealedReconnectSecret: ManualIPEncryptedFrame
    ) -> Bool {
        timingSafeCompare(
            verifier,
            pairingServerVerifier(
                pairingCode: pairingCode,
                clientInstallationID: clientInstallationID,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce,
                macInstallationID: macInstallationID,
                serverPublicKey: serverPublicKey,
                serverNonce: serverNonce,
                sealedReconnectSecret: sealedReconnectSecret
            )
        )
    }

    /// Authenticates the Mac during a saved-connection handshake. The proof binds
    /// both installations and both sides' fresh key-agreement material.
    static func trustedServerVerifier(
        reconnectSecret: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        macInstallationID: UUID,
        serverPublicKey: Data,
        serverNonce: Data
    ) -> Data {
        serverVerifier(
            domain: trustedServerDomain,
            keyData: reconnectSecret,
            clientInstallationID: clientInstallationID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            macInstallationID: macInstallationID,
            serverPublicKey: serverPublicKey,
            serverNonce: serverNonce,
            sealedReconnectSecret: nil
        )
    }

    static func trustedServerVerifierIsValid(
        _ verifier: Data,
        reconnectSecret: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        macInstallationID: UUID,
        serverPublicKey: Data,
        serverNonce: Data
    ) -> Bool {
        timingSafeCompare(
            verifier,
            trustedServerVerifier(
                reconnectSecret: reconnectSecret,
                clientInstallationID: clientInstallationID,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce,
                macInstallationID: macInstallationID,
                serverPublicKey: serverPublicKey,
                serverNonce: serverNonce
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

    private static func pairingCodeKey(_ pairingCode: String) -> Data {
        let normalizedCode = normalizedPairingCode(pairingCode)
        return Data(SHA256.hash(data: Data("HealthMd.ManualIP.Code.\(normalizedCode)".utf8)))
    }

    private static func authenticationCode(for payload: Data, keyData: Data) -> Data {
        let key = SymmetricKey(data: keyData)
        return Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
    }

    private static func serverVerifier(
        domain: Data,
        keyData: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        macInstallationID: UUID,
        serverPublicKey: Data,
        serverNonce: Data,
        sealedReconnectSecret: ManualIPEncryptedFrame?
    ) -> Data {
        var payload = domain
        appendField(Data(clientInstallationID.uuidString.lowercased().utf8), to: &payload)
        appendField(clientPublicKey, to: &payload)
        appendField(clientNonce, to: &payload)
        appendField(Data(macInstallationID.uuidString.lowercased().utf8), to: &payload)
        appendField(serverPublicKey, to: &payload)
        appendField(serverNonce, to: &payload)
        if let sealedReconnectSecret {
            payload.append(1)
            appendField(sealedReconnectSecret.nonce, to: &payload)
            appendField(sealedReconnectSecret.ciphertext, to: &payload)
            appendField(sealedReconnectSecret.tag, to: &payload)
        } else {
            payload.append(0)
        }
        return authenticationCode(for: payload, keyData: keyData)
    }

    private static func appendField(_ field: Data, to payload: inout Data) {
        payload.appendManualIPLengthPrefix(field.count)
        payload.append(field)
    }
}

struct ManualIPPairingRequest: Codable, Equatable {
    let protocolVersion: Int
    let deviceName: String
    let clientPublicKey: Data
    let clientNonce: Data
    let codeVerifier: Data
    /// Present for current pairing clients and every trusted reconnect.
    let clientInstallationID: UUID?
    /// Present only when reconnecting with a previously issued secret.
    let trustedVerifier: Data?

    init(
        protocolVersion: Int = ManualIPSyncSecurity.protocolVersion,
        deviceName: String,
        clientPublicKey: Data,
        clientNonce: Data,
        codeVerifier: Data,
        clientInstallationID: UUID? = nil,
        trustedVerifier: Data? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.deviceName = deviceName
        self.clientPublicKey = clientPublicKey
        self.clientNonce = clientNonce
        self.codeVerifier = codeVerifier
        self.clientInstallationID = clientInstallationID
        self.trustedVerifier = trustedVerifier
    }
}

struct ManualIPPairingResponse: Codable, Equatable {
    let protocolVersion: Int
    let macName: String
    let serverPublicKey: Data
    let serverNonce: Data
    /// Current peers use these fields to authenticate the Mac and save a random
    /// reconnect credential. They remain optional for protocol-v1 compatibility.
    let macInstallationID: UUID?
    let authenticationVerifier: Data?
    let sealedReconnectSecret: ManualIPEncryptedFrame?

    init(
        protocolVersion: Int = ManualIPSyncSecurity.protocolVersion,
        macName: String,
        serverPublicKey: Data,
        serverNonce: Data,
        macInstallationID: UUID? = nil,
        authenticationVerifier: Data? = nil,
        sealedReconnectSecret: ManualIPEncryptedFrame? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.macName = macName
        self.serverPublicKey = serverPublicKey
        self.serverNonce = serverNonce
        self.macInstallationID = macInstallationID
        self.authenticationVerifier = authenticationVerifier
        self.sealedReconnectSecret = sealedReconnectSecret
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
