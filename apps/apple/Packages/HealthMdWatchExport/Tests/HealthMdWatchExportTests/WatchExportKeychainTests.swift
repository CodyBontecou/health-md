import Foundation
import Security
import XCTest
@testable import HealthMdWatchExport

@MainActor
private final class RecordingKeychain: WatchExportKeychainClient {
    var copyStatus: OSStatus = errSecItemNotFound
    var updateStatus: OSStatus = errSecItemNotFound
    var addStatus: OSStatus = errSecSuccess
    var updates: [[String: Any]] = []
    var additions: [[String: Any]] = []
    func copy(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus { copyStatus }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        updates.append(attributes as! [String: Any])
        return updateStatus
    }
    func add(_ item: CFDictionary) -> OSStatus {
        additions.append(item as! [String: Any])
        return addStatus
    }
}

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
        // The macOS file-based Keychain does not expose iOS/watchOS accessibility
        // attributes. Actual Watch lock behavior remains a physical-device gate;
        // test the production policy arguments separately below, not via a skip.
        XCTAssertFalse(attributes[kSecAttrSynchronizable as String] as? Bool ?? false)
        try store.save(WatchExportState(destination: destination))
        XCTAssertNil(try store.load().pending)
        XCTAssertEqual(try store.load().destination, destination)
    }

    func testProductionWritesRequestUnlockedDeviceOnlyPolicyAndNeverAddAfterUpdateFailure() async throws {
        let client = RecordingKeychain()
        let store = WatchExportKeychain(service: "synthetic-test", client: client)
        try store.save(WatchExportState())
        let update = try XCTUnwrap(client.updates.last)
        let add = try XCTUnwrap(client.additions.last)
        XCTAssertEqual(update[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(add[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(add[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(add[kSecAttrAccount as String] as? String, "destination-and-pending")
        XCTAssertNotNil(add[kSecValueData as String] as? Data)
        client.updateStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.save(WatchExportState()))
        XCTAssertEqual(client.additions.count, 1, "A locked/read-error item must not be replaced")
        client.copyStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.load())
        client.updateStatus = errSecItemNotFound
        client.addStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.save(WatchExportState()))
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
