import Foundation
import Security

/// Durable credential issued after a pairing-code connection. The short-lived
/// pairing code is never persisted; this random secret authenticates later
/// connections to the same Mac instead.
public struct ManualIPTrustedMac: Codable, Equatable, Sendable {
    public let installationID: UUID
    public let displayName: String
    public var host: String
    public var port: UInt16
    public let reconnectSecret: Data
    public let pairedAt: Date

    public init(
        installationID: UUID,
        displayName: String,
        host: String,
        port: UInt16,
        reconnectSecret: Data,
        pairedAt: Date
    ) {
        self.installationID = installationID
        self.displayName = displayName
        self.host = host
        self.port = port
        self.reconnectSecret = reconnectSecret
        self.pairedAt = pairedAt
    }
}

/// A paired iPhone that the Mac may accept without another pairing code.
public struct ManualIPTrustedClient: Codable, Equatable, Sendable {
    public let installationID: UUID
    public var displayName: String
    public let reconnectSecret: Data
    public let pairedAt: Date
    public var lastConnectedAt: Date

    public init(
        installationID: UUID,
        displayName: String,
        reconnectSecret: Data,
        pairedAt: Date,
        lastConnectedAt: Date
    ) {
        self.installationID = installationID
        self.displayName = displayName
        self.reconnectSecret = reconnectSecret
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
    }
}

public struct ManualIPTrustState: Codable, Equatable, Sendable {
    public let ownerInstallationID: UUID
    public var trustedMac: ManualIPTrustedMac?
    public var provisionalTrustedMac: ManualIPTrustedMac?
    public var trustedClients: [ManualIPTrustedClient]

    public init(
        ownerInstallationID: UUID,
        trustedMac: ManualIPTrustedMac? = nil,
        provisionalTrustedMac: ManualIPTrustedMac? = nil,
        trustedClients: [ManualIPTrustedClient] = []
    ) {
        self.ownerInstallationID = ownerInstallationID
        self.trustedMac = trustedMac
        self.provisionalTrustedMac = provisionalTrustedMac
        self.trustedClients = trustedClients
    }

    public func trustedClient(installationID: UUID) -> ManualIPTrustedClient? {
        trustedClients.first { $0.installationID == installationID }
    }

    public mutating func saveTrustedClient(_ client: ManualIPTrustedClient) {
        trustedClients.removeAll { $0.installationID == client.installationID }
        trustedClients.append(client)
    }
}

public enum ManualIPTrustStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidKeychainItem
    case missingProvisionalTrust

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain returned status \(status)."
        case .invalidKeychainItem:
            return "The saved manual IP connection is invalid."
        case .missingProvisionalTrust:
            return "The provisional direct CLI pairing credential is unavailable."
        }
    }
}

public protocol ManualIPTrustStoring: AnyObject {
    func loadState(ownerInstallationID: UUID) -> ManualIPTrustState
    func saveState(_ state: ManualIPTrustState) throws
}

/// Stores manual-IP reconnect credentials in the local Keychain. Host and port
/// are not secret, but keeping the complete record together prevents a reusable
/// credential from ever being written to UserDefaults.
public final class ManualIPTrustStore: ManualIPTrustStoring {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        service: String = "com.codybontecou.obsidianhealth.manual-ip-trust",
        account: String = "trust-state-v1"
    ) {
        self.service = service
        self.account = account
    }

    public func loadState(ownerInstallationID: UUID) -> ManualIPTrustState {
        do {
            guard let data = try loadData() else {
                return ManualIPTrustState(ownerInstallationID: ownerInstallationID)
            }
            let state = try decoder.decode(ManualIPTrustState.self, from: data)
            guard state.ownerInstallationID == ownerInstallationID else {
                let resetState = ManualIPTrustState(ownerInstallationID: ownerInstallationID)
                try? saveState(resetState)
                return resetState
            }
            return state
        } catch {
            // Corrupt or inaccessible credentials must never silently establish
            // trust. Reset to an unpaired state and require a fresh code.
            let resetState = ManualIPTrustState(ownerInstallationID: ownerInstallationID)
            try? saveState(resetState)
            return resetState
        }
    }

    public func saveState(_ state: ManualIPTrustState) throws {
        let data = try encoder.encode(state)
        let updateAttributes: [CFString: Any] = [
            kSecValueData: data
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ManualIPTrustStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ManualIPTrustStoreError.keychain(addStatus)
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false
        ]
    }

    private func loadData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ManualIPTrustStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw ManualIPTrustStoreError.invalidKeychainItem
        }
        return data
    }
}
