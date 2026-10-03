import Foundation
import Security
import XCTest
@testable import HealthMdWatchExport

@MainActor
final class WatchExportKeychainTests: XCTestCase {
    func testKeychainRoundTripStoresDestinationAndPendingTogetherWithoutSynchronization() async throws {
        let service = "com.healthmd.watch-export.test.\(UUID().uuidString)"
        let store = WatchExportKeychain(service: service)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "destination-and-pending"]
        defer { SecItemDelete(query as CFDictionary) }
        XCTAssertEqual(try store.load(), WatchExportState())
        let destination = try WatchExportDestination(endpoint: "https://example.com/watch", bearerToken: "synthetic")
        let pending = WatchPendingUpload(id: UUID(), body: Data("synthetic only".utf8))
        let state = WatchExportState(destination: destination, pending: pending)
        try store.save(state)
        XCTAssertEqual(try WatchExportKeychain(service: service).load(), state)
        var attributeQuery = query
        attributeQuery[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(attributeQuery as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertFalse(attributes[kSecAttrSynchronizable as String] as? Bool ?? false)
        try store.save(WatchExportState(destination: destination))
        XCTAssertNil(try store.load().pending)
        XCTAssertEqual(try store.load().destination, destination)
    }

    func testMalformedKeychainDataFailsClosedInsteadOfErasingState() async throws {
        let service = "com.healthmd.watch-export.test.\(UUID().uuidString)"
        let store = WatchExportKeychain(service: service)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "destination-and-pending"]
        defer { SecItemDelete(query as CFDictionary) }
        var item = query
        item[kSecValueData as String] = Data("not JSON".utf8)
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        XCTAssertThrowsError(try store.load())
    }
}
