import Foundation
import HealthMdConnectionCore

public struct DirectServerEndpoint: Equatable, Sendable {
    public let transport: DirectTransportKind
    public let port: UInt16?
    public let addresses: [ManualIPNetworkAddress]
    public let serviceType: String?
    public let displayName: String?

    public init(
        transport: DirectTransportKind,
        port: UInt16? = nil,
        addresses: [ManualIPNetworkAddress] = [],
        serviceType: String? = nil,
        displayName: String? = nil
    ) {
        self.transport = transport
        self.port = port
        self.addresses = addresses
        self.serviceType = serviceType
        self.displayName = displayName
    }
}

enum DirectServerListener {
    case manualIP(DirectManualIPServer)
    case nearby(DirectNearbyServer)

    func start() async throws -> DirectServerEndpoint {
        switch self {
        case .manualIP(let server):
            let endpoint = try await server.start()
            return DirectServerEndpoint(
                transport: .manualIP,
                port: endpoint.port,
                addresses: endpoint.addresses
            )
        case .nearby(let server):
            let endpoint = try server.start()
            return DirectServerEndpoint(
                transport: .nearby,
                serviceType: endpoint.serviceType,
                displayName: endpoint.displayName
            )
        }
    }

    func stop() {
        switch self {
        case .manualIP(let server): server.stop()
        case .nearby(let server): server.stop()
        }
    }

    func acceptAuthenticatedClient(
        pairingCode: String? = nil,
        pairingCodeExpiresAt: Date? = nil,
        timeout: TimeInterval,
        maximumAttempts: Int = 8
    ) async throws -> DirectSecureChannel {
        switch self {
        case .manualIP(let server):
            return try await server.acceptAuthenticatedClient(
                pairingCode: pairingCode,
                pairingCodeExpiresAt: pairingCodeExpiresAt,
                timeout: timeout,
                maximumAttempts: maximumAttempts
            )
        case .nearby(let server):
            return try await server.acceptAuthenticatedClient(
                pairingCode: pairingCode,
                pairingCodeExpiresAt: pairingCodeExpiresAt,
                timeout: timeout,
                maximumAttempts: maximumAttempts
            )
        }
    }

    func trustedClients() -> [ManualIPTrustedClient] {
        switch self {
        case .manualIP(let server): return server.trustedClients()
        case .nearby(let server): return server.trustedClients()
        }
    }
}
