import Foundation
import Security

@MainActor
protocol WatchExportKeychainClient {
    func copy(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ item: CFDictionary) -> OSStatus
}

@MainActor
struct WatchExportSystemKeychain: WatchExportKeychainClient {
    func copy(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus { SecItemCopyMatching(query, &result) }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { SecItemUpdate(query, attributes) }
    func add(_ item: CFDictionary) -> OSStatus { SecItemAdd(item, nil) }
}

@MainActor
final class WatchExportKeychain: WatchExportStateStore {
    private let service: String
    private let client: any WatchExportKeychainClient

    init(service: String = "com.healthmd.watch.manual-export.v1", client: (any WatchExportKeychainClient)? = nil) {
        self.service = service
        self.client = client ?? WatchExportSystemKeychain()
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "destination-and-pending",
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> WatchExportState {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = client.copy(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return WatchExportState() }
        guard status == errSecSuccess, let data = result as? Data,
              data.count <= 128 * 1024,
              let state = try? JSONDecoder().decode(WatchExportState.self, from: data) else {
            throw WatchExportError.storage
        }
        return state
    }

    func save(_ state: WatchExportState) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= 128 * 1024 else { throw WatchExportError.storage }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = client.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard client.add(item as CFDictionary) == errSecSuccess else { throw WatchExportError.storage }
        } else if status != errSecSuccess {
            throw WatchExportError.storage
        }
    }
}
