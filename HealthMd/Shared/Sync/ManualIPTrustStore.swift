import Foundation
import Security

/// Durable credential issued after a pairing-code connection. The short-lived
/// pairing code is never persisted; this random secret authenticates later
/// connections to the same Mac instead.
struct ManualIPTrustedMac: Codable, Equatable {
    let installationID: UUID
    let displayName: String
    var host: String
    var port: UInt16
    let reconnectSecret: Data
    let pairedAt: Date
}

/// A paired iPhone that the Mac may accept without another pairing code.
struct ManualIPTrustedClient: Codable, Equatable {
    let installationID: UUID
    var displayName: String
    let reconnectSecret: Data
    let pairedAt: Date
    var lastConnectedAt: Date
}

struct ManualIPTrustState: Codable, Equatable {
    let ownerInstallationID: UUID
    var trustedMac: ManualIPTrustedMac?
    var trustedClients: [ManualIPTrustedClient]

    init(
        ownerInstallationID: UUID,
        trustedMac: ManualIPTrustedMac? = nil,
        trustedClients: [ManualIPTrustedClient] = []
    ) {
        self.ownerInstallationID = ownerInstallationID
        self.trustedMac = trustedMac
        self.trustedClients = trustedClients
    }

    func trustedClient(installationID: UUID) -> ManualIPTrustedClient? {
        trustedClients.first { $0.installationID == installationID }
    }

    mutating func saveTrustedClient(_ client: ManualIPTrustedClient) {
        trustedClients.removeAll { $0.installationID == client.installationID }
        trustedClients.append(client)
    }
}

enum ManualIPTrustStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidKeychainItem

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain returned status \(status)."
        case .invalidKeychainItem:
            return "The saved manual IP connection is invalid."
        }
    }
}

/// Stores manual-IP reconnect credentials in the local Keychain. Host and port
/// are not secret, but keeping the complete record together prevents a reusable
/// credential from ever being written to UserDefaults.
final class ManualIPTrustStore {
    private let service = "com.codybontecou.obsidianhealth.manual-ip-trust"
    private let account = "trust-state-v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadState(ownerInstallationID: UUID) -> ManualIPTrustState {
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

    func saveState(_ state: ManualIPTrustState) throws {
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
