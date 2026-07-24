import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore
import Network

public struct DirectManualIPServerEndpoint: Equatable, Sendable {
    public let port: UInt16
    public let addresses: [ManualIPNetworkAddress]

    public init(port: UInt16, addresses: [ManualIPNetworkAddress]) {
        self.port = port
        self.addresses = addresses
    }
}

public final class DirectManualIPServer: @unchecked Sendable {
    public let installationID: UUID
    public let displayName: String
    public let port: UInt16

    private let trustStore: any ManualIPTrustStoring
    private let queue = DispatchQueue(label: "com.codybontecou.healthmd.direct-cli.server")
    private let pendingConnections = DirectPendingConnectionQueue()
    private var listener: NWListener?

    public init(
        installationID: UUID,
        displayName: String = Host.current().localizedName ?? "healthmd CLI",
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        trustStore: any ManualIPTrustStoring = DirectClientTrustStore.make()
    ) {
        self.installationID = installationID
        self.displayName = displayName
        self.port = port
        self.trustStore = trustStore
    }

    public func start(timeout: TimeInterval = 10) async throws -> DirectManualIPServerEndpoint {
        guard listener == nil else {
            return DirectManualIPServerEndpoint(port: port, addresses: Self.currentIPv4Addresses())
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw DirectChannelError.connectionFailed("The direct CLI port is invalid.")
        }
        let listener = try NWListener(using: .tcp, on: nwPort)
        self.listener = listener
        listener.newConnectionHandler = { [pendingConnections] connection in
            Task { await pendingConnections.push(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = DirectListenerStartGate(continuation: continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish(.success(()))
                case .failed(let error):
                    gate.finish(.failure(DirectChannelError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    gate.finish(.failure(DirectChannelError.connectionClosed))
                default:
                    break
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                gate.finish(.failure(DirectChannelError.timedOut))
            }
        }
        return DirectManualIPServerEndpoint(port: port, addresses: Self.currentIPv4Addresses())
    }

    public func acceptAuthenticatedClient(
        pairingCode: String? = nil,
        pairingCodeExpiresAt: Date? = nil,
        timeout: TimeInterval = 60,
        maximumAttempts: Int = 5
    ) async throws -> DirectSecureChannel {
        let deadline = Date().addingTimeInterval(timeout)
        var lastFailure: Error = DirectChannelError.timedOut
        for _ in 0..<maximumAttempts {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw DirectChannelError.timedOut }
            let connection = try await pendingConnections.next(timeout: remaining)
            let packetConnection = DirectPacketConnection(
                connection: connection,
                queue: queue,
                maximumPacketBytes: HealthMdDirectProtocol.maximumPacketBytes
            )
            do {
                try await packetConnection.start(timeout: min(10, remaining))
                return try await authenticate(
                    packetConnection,
                    pairingCode: pairingCode,
                    pairingCodeExpiresAt: pairingCodeExpiresAt
                )
            } catch {
                lastFailure = error
                let reason = error.localizedDescription
                try? await packetConnection.send(.pairingRejected(
                    ManualIPPairingRejected(reason: reason)
                ))
                packetConnection.cancel()
            }
        }
        throw lastFailure
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        Task { await pendingConnections.finish() }
    }

    public func trustedClients() -> [ManualIPTrustedClient] {
        trustStore.loadState(ownerInstallationID: installationID).trustedClients
    }

    public func forgetClient(installationID clientID: UUID) throws {
        var state = trustStore.loadState(ownerInstallationID: installationID)
        state.trustedClients.removeAll { $0.installationID == clientID }
        try trustStore.saveState(state)
    }

    func authenticate(
        _ packetConnection: any DirectPacketTransport,
        pairingCode: String?,
        pairingCodeExpiresAt: Date?
    ) async throws -> DirectSecureChannel {
        guard case .pairingRequest(let request) = try await packetConnection.receive(),
              request.protocolVersion == DirectPairingSecurity.protocolVersion,
              let clientInstallationID = request.clientInstallationID else {
            throw DirectChannelError.authenticationFailed("The iPhone direct CLI handshake is incompatible.")
        }

        var trustState = trustStore.loadState(ownerInstallationID: installationID)
        let existing = trustState.trustedClient(installationID: clientInstallationID)
        let isTrustedReconnect: Bool
        let reconnectSecret: Data
        let normalizedCode = pairingCode.map(ManualIPSyncSecurity.normalizedPairingCode)

        if let existing,
           let trustedVerifier = request.trustedVerifier,
           DirectPairingSecurity.trustedClientVerifierIsValid(
                trustedVerifier,
                reconnectSecret: existing.reconnectSecret,
                clientInstallationID: clientInstallationID,
                clientPublicKey: request.clientPublicKey,
                clientNonce: request.clientNonce
           ) {
            isTrustedReconnect = true
            reconnectSecret = existing.reconnectSecret
        } else if let normalizedCode,
                  !normalizedCode.isEmpty,
                  pairingCodeExpiresAt.map({ $0 > Date() }) ?? true,
                  DirectPairingSecurity.pairingVerifierIsValid(
                    request.codeVerifier,
                    pairingCode: normalizedCode,
                    clientInstallationID: clientInstallationID,
                    clientPublicKey: request.clientPublicKey,
                    clientNonce: request.clientNonce
                  ) {
            isTrustedReconnect = false
            reconnectSecret = ManualIPSyncSecurity.randomNonce(
                byteCount: DirectPairingSecurity.reconnectSecretByteCount
            )
        } else {
            throw DirectChannelError.authenticationFailed("The direct CLI pairing code or saved credential is invalid.")
        }

        let clientPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: request.clientPublicKey
        )
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let serverPublicKey = privateKey.publicKey.rawRepresentation
        let serverNonce = ManualIPSyncSecurity.randomNonce()
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: clientPublicKey)
        let sessionKey = DirectPairingSecurity.sessionKey(
            sharedSecret: sharedSecret,
            clientNonce: request.clientNonce,
            serverNonce: serverNonce
        )
        let sealedReconnectSecret = try ManualIPSyncSecurity.seal(
            reconnectSecret,
            using: sessionKey
        )
        let verifier: Data
        if isTrustedReconnect {
            verifier = DirectPairingSecurity.trustedServerVerifier(
                reconnectSecret: reconnectSecret,
                clientInstallationID: clientInstallationID,
                clientPublicKey: request.clientPublicKey,
                clientNonce: request.clientNonce,
                serverInstallationID: installationID,
                serverPublicKey: serverPublicKey,
                serverNonce: serverNonce
            )
        } else {
            guard let normalizedCode else {
                throw DirectChannelError.authenticationFailed("The direct CLI pairing code is missing.")
            }
            verifier = DirectPairingSecurity.pairingServerVerifier(
                pairingCode: normalizedCode,
                clientInstallationID: clientInstallationID,
                clientPublicKey: request.clientPublicKey,
                clientNonce: request.clientNonce,
                serverInstallationID: installationID,
                serverPublicKey: serverPublicKey,
                serverNonce: serverNonce,
                sealedReconnectSecret: sealedReconnectSecret
            )
        }

        let now = Date()
        trustState.saveTrustedClient(ManualIPTrustedClient(
            installationID: clientInstallationID,
            displayName: request.deviceName,
            reconnectSecret: reconnectSecret,
            pairedAt: existing?.pairedAt ?? now,
            lastConnectedAt: now
        ))
        try trustStore.saveState(trustState)
        try await packetConnection.send(.pairingResponse(ManualIPPairingResponse(
            protocolVersion: DirectPairingSecurity.protocolVersion,
            macName: displayName,
            serverPublicKey: serverPublicKey,
            serverNonce: serverNonce,
            macInstallationID: installationID,
            authenticationVerifier: verifier,
            sealedReconnectSecret: sealedReconnectSecret
        )))
        return DirectSecureChannel(
            packetConnection: packetConnection,
            sessionKey: sessionKey,
            peerInstallationID: clientInstallationID,
            peerDisplayName: request.deviceName
        )
    }

    public static func currentIPv4Addresses() -> [ManualIPNetworkAddress] {
        var results: [ManualIPNetworkAddress] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let raw = current.pointee.ifa_addr,
                  raw.pointee.sa_family == UInt8(AF_INET) else { continue }
            var address = sockaddr_in()
            memcpy(&address, raw, MemoryLayout<sockaddr_in>.size)
            let hostOrder = UInt32(bigEndian: address.sin_addr.s_addr)
            let firstOctet = (hostOrder >> 24) & 0xff
            let secondOctet = (hostOrder >> 16) & 0xff
            guard firstOctet != 127, firstOctet != 169 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sinAddress = address.sin_addr
            guard inet_ntop(AF_INET, &sinAddress, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }
            let candidate = ManualIPNetworkAddress(
                interfaceName: String(cString: current.pointee.ifa_name),
                address: String(cString: buffer),
                isLikelyTailscale: firstOctet == 100 && (64...127).contains(Int(secondOctet))
            )
            if !results.contains(candidate) { results.append(candidate) }
        }
        return results.sorted {
            if $0.isLikelyTailscale != $1.isLikelyTailscale {
                return $0.isLikelyTailscale && !$1.isLikelyTailscale
            }
            return $0.address < $1.address
        }
    }
}

private final class DirectListenerStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

private actor DirectPendingConnectionQueue {
    private var buffered: [NWConnection] = []
    private let maximumBufferedConnections = 4
    private var waiters: [UUID: CheckedContinuation<NWConnection, Error>] = [:]
    private var isFinished = false

    func push(_ connection: NWConnection) {
        guard !isFinished else { connection.cancel(); return }
        if let key = waiters.keys.first, let continuation = waiters.removeValue(forKey: key) {
            continuation.resume(returning: connection)
        } else if buffered.count < maximumBufferedConnections {
            buffered.append(connection)
        } else {
            connection.cancel()
        }
    }

    func next(timeout: TimeInterval) async throws -> NWConnection {
        if !buffered.isEmpty { return buffered.removeFirst() }
        if isFinished { throw DirectChannelError.connectionClosed }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                    self.expire(id)
                }
            }
        } onCancel: {
            Task { await self.expire(id) }
        }
    }

    func finish() {
        isFinished = true
        buffered.forEach { $0.cancel() }
        buffered.removeAll()
        let current = waiters.values
        waiters.removeAll()
        current.forEach { $0.resume(throwing: DirectChannelError.connectionClosed) }
    }

    private func expire(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: DirectChannelError.timedOut)
    }
}
