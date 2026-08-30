import CryptoKit
import Foundation

/// Domain-separated authentication for the opt-in direct CLI channel.
/// It deliberately does not accept credentials issued for the classic Mac-app
/// manual-IP transport even though both channels share the same packet framing.
public enum DirectPairingSecurity {
    public static let protocolVersion = 1
    public static let pairingCodeLifetime: TimeInterval = 10 * 60
    public static let reconnectSecretByteCount = 32

    /// TCP keepalive bounds for the direct CLI channel. A silently dead peer must fail
    /// within a bounded window instead of leaving a half-open socket that blocks the
    /// reconnect loop. These mirror the Rust listener-side socket options.
    public static let tcpKeepaliveIdleSeconds = 10
    public static let tcpKeepaliveIntervalSeconds = 5
    public static let tcpKeepaliveCount = 3

    private static let pairingDomain = Data("HealthMd.DirectCLI.PairingVerifier.v1".utf8)
    private static let sessionDomain = Data("HealthMd.DirectCLI.SessionKey.v1".utf8)
    private static let trustedClientDomain = Data("HealthMd.DirectCLI.TrustedClient.v1".utf8)
    private static let pairingServerDomain = Data("HealthMd.DirectCLI.PairingServer.v1".utf8)
    private static let trustedServerDomain = Data("HealthMd.DirectCLI.TrustedServer.v1".utf8)

    public static func pairingVerifier(
        pairingCode: String,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Data {
        var payload = pairingDomain
        append(Data(clientInstallationID.uuidString.lowercased().utf8), to: &payload)
        append(clientPublicKey, to: &payload)
        append(clientNonce, to: &payload)
        return authenticationCode(payload, keyData: pairingCodeKey(pairingCode))
    }

    public static func pairingVerifierIsValid(
        _ verifier: Data,
        pairingCode: String,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Bool {
        ManualIPSyncSecurity.timingSafeCompare(
            verifier,
            pairingVerifier(
                pairingCode: pairingCode,
                clientInstallationID: clientInstallationID,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce
            )
        )
    }

    public static func trustedClientVerifier(
        reconnectSecret: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Data {
        var payload = trustedClientDomain
        append(Data(clientInstallationID.uuidString.lowercased().utf8), to: &payload)
        append(clientPublicKey, to: &payload)
        append(clientNonce, to: &payload)
        return authenticationCode(payload, keyData: reconnectSecret)
    }

    public static func trustedClientVerifierIsValid(
        _ verifier: Data,
        reconnectSecret: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data
    ) -> Bool {
        ManualIPSyncSecurity.timingSafeCompare(
            verifier,
            trustedClientVerifier(
                reconnectSecret: reconnectSecret,
                clientInstallationID: clientInstallationID,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce
            )
        )
    }

    public static func pairingServerVerifier(
        pairingCode: String,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        serverInstallationID: UUID,
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
            serverInstallationID: serverInstallationID,
            serverPublicKey: serverPublicKey,
            serverNonce: serverNonce,
            sealedReconnectSecret: sealedReconnectSecret
        )
    }

    public static func trustedServerVerifier(
        reconnectSecret: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        serverInstallationID: UUID,
        serverPublicKey: Data,
        serverNonce: Data
    ) -> Data {
        serverVerifier(
            domain: trustedServerDomain,
            keyData: reconnectSecret,
            clientInstallationID: clientInstallationID,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            serverInstallationID: serverInstallationID,
            serverPublicKey: serverPublicKey,
            serverNonce: serverNonce,
            sealedReconnectSecret: nil
        )
    }

    public static func serverVerifierIsValid(
        _ verifier: Data,
        expected: Data
    ) -> Bool {
        ManualIPSyncSecurity.timingSafeCompare(verifier, expected)
    }

    public static func sessionKey(
        sharedSecret: SharedSecret,
        clientNonce: Data,
        serverNonce: Data
    ) -> SymmetricKey {
        var payload = sessionDomain
        payload.append(sharedSecret.withUnsafeBytes { Data($0) })
        append(clientNonce, to: &payload)
        append(serverNonce, to: &payload)
        return SymmetricKey(data: Data(SHA256.hash(data: payload)))
    }

    private static func pairingCodeKey(_ code: String) -> Data {
        let normalized = ManualIPSyncSecurity.normalizedPairingCode(code)
        return Data(SHA256.hash(data: Data("HealthMd.DirectCLI.Code.\(normalized)".utf8)))
    }

    private static func authenticationCode(_ payload: Data, keyData: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: payload,
            using: SymmetricKey(data: keyData)
        ))
    }

    private static func serverVerifier(
        domain: Data,
        keyData: Data,
        clientInstallationID: UUID,
        clientPublicKey: Data,
        clientNonce: Data,
        serverInstallationID: UUID,
        serverPublicKey: Data,
        serverNonce: Data,
        sealedReconnectSecret: ManualIPEncryptedFrame?
    ) -> Data {
        var payload = domain
        append(Data(clientInstallationID.uuidString.lowercased().utf8), to: &payload)
        append(clientPublicKey, to: &payload)
        append(clientNonce, to: &payload)
        append(Data(serverInstallationID.uuidString.lowercased().utf8), to: &payload)
        append(serverPublicKey, to: &payload)
        append(serverNonce, to: &payload)
        if let sealedReconnectSecret {
            payload.append(1)
            append(sealedReconnectSecret.nonce, to: &payload)
            append(sealedReconnectSecret.ciphertext, to: &payload)
            append(sealedReconnectSecret.tag, to: &payload)
        } else {
            payload.append(0)
        }
        return authenticationCode(payload, keyData: keyData)
    }

    private static func append(_ field: Data, to payload: inout Data) {
        payload.appendManualIPLengthPrefix(field.count)
        payload.append(field)
    }
}
