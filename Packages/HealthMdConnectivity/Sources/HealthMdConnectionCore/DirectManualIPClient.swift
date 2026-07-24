import CryptoKit
import Foundation
import Network

public final class DirectManualIPClient: @unchecked Sendable {
    public let installationID: UUID
    public let displayName: String
    private let trustStore: any ManualIPTrustStoring
    private let queue = DispatchQueue(label: "com.codybontecou.healthmd.direct-cli.client")

    public init(
        installationID: UUID,
        displayName: String,
        trustStore: any ManualIPTrustStoring
    ) {
        self.installationID = installationID
        self.displayName = displayName
        self.trustStore = trustStore
    }

    public func connect(
        host: String,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        pairingCode: String? = nil,
        timeout: TimeInterval = 10
    ) async throws -> DirectSecureChannel {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty,
              let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw DirectChannelError.connectionFailed("The direct CLI host or port is invalid.")
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(normalizedHost),
            port: endpointPort,
            using: .tcp
        )
        let packetConnection = DirectPacketConnection(
            connection: connection,
            queue: queue,
            maximumPacketBytes: HealthMdDirectProtocol.maximumPacketBytes
        )
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await packetConnection.start(timeout: timeout)
                try Task.checkCancellation()
                return try await authenticate(
                    packetConnection,
                    host: normalizedHost,
                    port: port,
                    pairingCode: pairingCode
                )
            } catch {
                packetConnection.cancel()
                throw error
            }
        } onCancel: {
            packetConnection.cancel()
        }
    }

    public func savedServer() -> ManualIPTrustedMac? {
        trustStore.loadState(ownerInstallationID: installationID).trustedMac
    }

    public func forgetServer() throws {
        var state = trustStore.loadState(ownerInstallationID: installationID)
        state.trustedMac = nil
        try trustStore.saveState(state)
    }

    func authenticate(
        _ packetConnection: any DirectPacketTransport,
        host: String,
        port: UInt16,
        pairingCode: String?
    ) async throws -> DirectSecureChannel {
        let normalizedCode = pairingCode.map(ManualIPSyncSecurity.normalizedPairingCode)
        let state = trustStore.loadState(ownerInstallationID: installationID)
        let trustedServer = normalizedCode?.isEmpty == false ? nil : state.trustedMac
        guard trustedServer != nil || normalizedCode?.isEmpty == false else {
            throw DirectChannelError.authenticationFailed("Enter the pairing code shown by the healthmd CLI.")
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let clientNonce = ManualIPSyncSecurity.randomNonce()
        let codeVerifier: Data
        let trustedVerifier: Data?
        if let trustedServer {
            codeVerifier = Data()
            trustedVerifier = DirectPairingSecurity.trustedClientVerifier(
                reconnectSecret: trustedServer.reconnectSecret,
                clientInstallationID: installationID,
                clientPublicKey: publicKey,
                clientNonce: clientNonce
            )
        } else if let normalizedCode {
            codeVerifier = DirectPairingSecurity.pairingVerifier(
                pairingCode: normalizedCode,
                clientInstallationID: installationID,
                clientPublicKey: publicKey,
                clientNonce: clientNonce
            )
            trustedVerifier = nil
        } else {
            throw DirectChannelError.authenticationFailed("The direct CLI pairing code is missing.")
        }

        try await packetConnection.send(.pairingRequest(ManualIPPairingRequest(
            protocolVersion: DirectPairingSecurity.protocolVersion,
            deviceName: displayName,
            clientPublicKey: publicKey,
            clientNonce: clientNonce,
            codeVerifier: codeVerifier,
            clientInstallationID: installationID,
            trustedVerifier: trustedVerifier
        )))
        let packet = try await packetConnection.receive()
        if case .pairingRejected(let rejection) = packet {
            throw DirectChannelError.authenticationFailed(rejection.reason)
        }
        guard case .pairingResponse(let response) = packet,
              response.protocolVersion == DirectPairingSecurity.protocolVersion,
              let serverInstallationID = response.macInstallationID,
              let verifier = response.authenticationVerifier,
              let sealedReconnectSecret = response.sealedReconnectSecret else {
            throw DirectChannelError.authenticationFailed("The direct CLI returned an incompatible handshake.")
        }

        let serverPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: response.serverPublicKey
        )
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        let sessionKey = DirectPairingSecurity.sessionKey(
            sharedSecret: sharedSecret,
            clientNonce: clientNonce,
            serverNonce: response.serverNonce
        )
        let reconnectSecret = try ManualIPSyncSecurity.open(
            sealedReconnectSecret,
            using: sessionKey
        )

        let expectedVerifier: Data
        if let trustedServer {
            guard trustedServer.installationID == serverInstallationID,
                  ManualIPSyncSecurity.timingSafeCompare(
                    trustedServer.reconnectSecret,
                    reconnectSecret
                  ) else {
                throw DirectChannelError.authenticationFailed("The direct CLI identity changed; forget it and pair again.")
            }
            expectedVerifier = DirectPairingSecurity.trustedServerVerifier(
                reconnectSecret: trustedServer.reconnectSecret,
                clientInstallationID: installationID,
                clientPublicKey: publicKey,
                clientNonce: clientNonce,
                serverInstallationID: serverInstallationID,
                serverPublicKey: response.serverPublicKey,
                serverNonce: response.serverNonce
            )
        } else if let normalizedCode {
            expectedVerifier = DirectPairingSecurity.pairingServerVerifier(
                pairingCode: normalizedCode,
                clientInstallationID: installationID,
                clientPublicKey: publicKey,
                clientNonce: clientNonce,
                serverInstallationID: serverInstallationID,
                serverPublicKey: response.serverPublicKey,
                serverNonce: response.serverNonce,
                sealedReconnectSecret: sealedReconnectSecret
            )
        } else {
            throw DirectChannelError.authenticationFailed("The direct CLI pairing state was lost.")
        }
        guard DirectPairingSecurity.serverVerifierIsValid(verifier, expected: expectedVerifier) else {
            throw DirectChannelError.authenticationFailed("The direct CLI could not be authenticated.")
        }

        var updated = state
        updated.trustedMac = ManualIPTrustedMac(
            installationID: serverInstallationID,
            displayName: response.macName,
            host: host,
            port: port,
            reconnectSecret: reconnectSecret,
            pairedAt: trustedServer?.pairedAt ?? Date()
        )
        try trustStore.saveState(updated)
        return DirectSecureChannel(
            packetConnection: packetConnection,
            sessionKey: sessionKey,
            peerInstallationID: serverInstallationID,
            peerDisplayName: response.macName
        )
    }
}
