import XCTest
@testable import HealthMd

/// Onboarding v2's saved API endpoints: edits are in place (shared by every
/// automation bound to the id), URLs stay unique, and the token follows the row.
@MainActor
final class SavedAPIEndpointEditingTests: XCTestCase {
    private func makeStore() -> ProfileDestinationStore {
        let defaults = UserDefaults(suiteName: "SavedAPIEndpointEditingTests.\(UUID().uuidString)")!
        return ProfileDestinationStore(userDefaults: defaults, keychain: FakeKeychainStore())
    }

    func testUpdateEditsTheSameRowSoEveryBoundAutomationSeesIt() {
        let store = makeStore()
        let endpoint = store.upsertAPIEndpoint(name: "Home server", endpointURLString: "https://api.example.com/health", bearerToken: "one")

        XCTAssertTrue(store.updateAPIEndpoint(id: endpoint.id, name: "Home", endpointURLString: "https://api.example.com/v2", bearerToken: "two"))

        XCTAssertEqual(store.apiEndpoints.count, 1)
        XCTAssertEqual(store.apiEndpoint(id: endpoint.id)?.name, "Home")
        XCTAssertEqual(store.apiEndpoint(id: endpoint.id)?.endpointURLString, "https://api.example.com/v2")
        XCTAssertEqual(store.token(for: endpoint.id), "two")
    }

    func testUpdateRejectsAURLOwnedByAnotherEndpoint() {
        let store = makeStore()
        let first = store.upsertAPIEndpoint(name: "A", endpointURLString: "https://a.example.com", bearerToken: nil)
        _ = store.upsertAPIEndpoint(name: "B", endpointURLString: "https://b.example.com", bearerToken: nil)

        XCTAssertFalse(store.updateAPIEndpoint(id: first.id, name: "A", endpointURLString: "https://B.example.com", bearerToken: nil))
        XCTAssertEqual(store.apiEndpoint(id: first.id)?.endpointURLString, "https://a.example.com")
    }

    func testNilTokenKeepsAndEmptyTokenRemovesTheStoredToken() {
        let store = makeStore()
        let endpoint = store.upsertAPIEndpoint(name: "A", endpointURLString: "https://a.example.com", bearerToken: "secret")

        store.updateAPIEndpoint(id: endpoint.id, name: "A", endpointURLString: "https://a.example.com", bearerToken: nil)
        XCTAssertEqual(store.token(for: endpoint.id), "secret")

        store.updateAPIEndpoint(id: endpoint.id, name: "A", endpointURLString: "https://a.example.com", bearerToken: "")
        XCTAssertNil(store.token(for: endpoint.id))
    }

    func testUnknownIDAndEmptyNameAreHandled() {
        let store = makeStore()
        XCTAssertFalse(store.updateAPIEndpoint(id: UUID(), name: "X", endpointURLString: "https://x.example.com", bearerToken: nil))
        let endpoint = store.upsertAPIEndpoint(name: "Keep", endpointURLString: "https://k.example.com", bearerToken: nil)
        store.updateAPIEndpoint(id: endpoint.id, name: "  ", endpointURLString: "https://k.example.com", bearerToken: nil)
        XCTAssertEqual(store.apiEndpoint(id: endpoint.id)?.name, "Keep")
    }
}
