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
public enum ManualIPSyncSecurity {
    public static let legacyProtocolVersion = 1
    public static let protocolVersion = 2
    public static let defaultPort: UInt16 = 17_646
    public static let maxFrameSize = 100 * 1_024 * 1_024
    public static let pairingCodeLifetime: TimeInterval = 10 * 60
    public static let reconnectSecretByteCount = 32

    private static let verifierDomain = Data("HealthMd.ManualIP.PairingVerifier.v1".utf8)
    private static let sessionKeyDomain = Data("HealthMd.ManualIP.SessionKey.v1".utf8)
    private static let trustedClientDomain = Data("HealthMd.ManualIP.TrustedClient.v1".utf8)
    private static let pairingServerDomain = Data("HealthMd.ManualIP.PairingServer.v1".utf8)
    private static let trustedServerDomain = Data("HealthMd.ManualIP.TrustedServer.v1".utf8)

    public static func normalizedPairingCode(_ code: String) -> String {
        code.filter(\.isNumber)
    }

    public static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    public static func randomNonce(byteCount: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        return Data((0..<byteCount).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }

    public static func pairingVerifier(
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

    public static func pairingVerifierIsValid(
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
    public static func trustedClientVerifier(
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

    public static func trustedClientVerifierIsValid(
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
    public static func pairingServerVerifier(
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

    public static func pairingServerVerifierIsValid(
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
    public static func trustedServerVerifier(
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

    public static func trustedServerVerifierIsValid(
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

    public static func sessionKey(
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

    public static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> ManualIPEncryptedFrame {
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
        return ManualIPEncryptedFrame(
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    public static func open(_ frame: ManualIPEncryptedFrame, using key: SymmetricKey) throws -> Data {
        let nonce = try ChaChaPoly.Nonce(data: frame.nonce)
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: frame.ciphertext,
            tag: frame.tag
        )
        return try ChaChaPoly.open(sealedBox, using: key)
    }

    public static func timingSafeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
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

public struct ManualIPPairingRequest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let deviceName: String
    public let clientPublicKey: Data
    public let clientNonce: Data
    public let codeVerifier: Data
    /// Present for current pairing clients and every trusted reconnect.
    public let clientInstallationID: UUID?
    /// Present only when reconnecting with a previously issued secret.
    public let trustedVerifier: Data?

    public init(
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

public struct ManualIPPairingResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let macName: String
    public let serverPublicKey: Data
    public let serverNonce: Data
    /// Current peers use these fields to authenticate the Mac and save a random
    /// reconnect credential. They remain optional for protocol-v1 compatibility.
    public let macInstallationID: UUID?
    public let authenticationVerifier: Data?
    public let sealedReconnectSecret: ManualIPEncryptedFrame?

    public init(
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

public struct ManualIPPairingRejected: Codable, Equatable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public struct ManualIPEncryptedFrame: Codable, Equatable, Sendable {
    public let nonce: Data
    public let ciphertext: Data
    public let tag: Data

    public init(nonce: Data, ciphertext: Data, tag: Data) {
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public enum ManualIPSyncPacket: Codable, Equatable, Sendable {
    case pairingRequest(ManualIPPairingRequest)
    case pairingResponse(ManualIPPairingResponse)
    case pairingRejected(ManualIPPairingRejected)
    case encrypted(ManualIPEncryptedFrame)
}

public struct ManualIPNetworkAddress: Identifiable, Equatable, Sendable {
    public var id: String { "\(interfaceName)-\(address)" }
    public let interfaceName: String
    public let address: String
    public let isLikelyTailscale: Bool

    public init(interfaceName: String, address: String, isLikelyTailscale: Bool) {
        self.interfaceName = interfaceName
        self.address = address
        self.isLikelyTailscale = isLikelyTailscale
    }

    public var displayName: String {
        isLikelyTailscale ? "\(address) · Tailscale" : "\(address) · \(interfaceName)"
    }
}

public extension Data {
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
