import Foundation
import Security

@MainActor
final class WatchExportKeychain: WatchExportStateStore {
    private let service: String

    init(service: String = "com.healthmd.watch.manual-export.v1") { self.service = service }

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
        let status = SecItemCopyMatching(query as CFDictionary, &result)
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
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw WatchExportError.storage }
        } else if status != errSecSuccess {
            throw WatchExportError.storage
        }
    }
}
