import XCTest
@testable import HealthMd

@MainActor
final class ProfileDestinationStoreTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: MainActor-isolated deinits take the
    // back-deployed task path on older runtimes (CI's iOS 26.2 simulator)
    // where nested store release aborts; retain for the process lifetime.
    private static var retainedStores: [AnyObject] = []
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var keychain: FakeKeychainStore!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ProfileDestinationStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        keychain = FakeKeychainStore()
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        keychain = nil
        super.tearDown()
    }

    private func makeStore() -> ProfileDestinationStore {
        let store = ProfileDestinationStore(userDefaults: defaults, keychain: keychain)
        Self.retainedStores.append(store)
        return store
    }

    // MARK: - Vault destinations

    func testVaultUpsertCreatesThenUpdatesSamePath() {
        let store = makeStore()

        let first = store.upsertVault(
            name: "Vault",
            standardizedPath: "/Users/x/Health",
            bookmarkData: Data("bookmark-1".utf8)
        )
        XCTAssertEqual(store.vaults.count, 1)

        // Same path, identical payload: no duplicate row, no churn.
        let same = store.upsertVault(
            name: "Vault",
            standardizedPath: "/Users/x/Health",
            bookmarkData: Data("bookmark-1".utf8)
        )
        XCTAssertEqual(same.id, first.id)
        XCTAssertEqual(store.vaults.count, 1)

        // Same path, refreshed bookmark: row updated in place.
        let refreshed = store.upsertVault(
            name: "Vault Renamed",
            standardizedPath: "/Users/x/Health",
            bookmarkData: Data("bookmark-2".utf8)
        )
        XCTAssertEqual(refreshed.id, first.id)
        XCTAssertEqual(store.vaults.count, 1)
        XCTAssertEqual(refreshed.bookmarkData, Data("bookmark-2".utf8))
        XCTAssertEqual(refreshed.name, "Vault Renamed")

        // Different path: new row.
        _ = store.upsertVault(
            name: "Weekly Vault",
            standardizedPath: "/Users/x/WeeklyHealth",
            bookmarkData: Data("bookmark-3".utf8)
        )
        XCTAssertEqual(store.vaults.count, 2)
        XCTAssertNotNil(store.vault(standardizedPath: "/Users/x/WeeklyHealth"))
    }

    func testVaultDestinationsPersistAcrossStoreInstances() {
        let first = makeStore()
        _ = first.upsertVault(
            name: "Vault",
            standardizedPath: "/Users/x/Health",
            bookmarkData: Data("bookmark".utf8)
        )

        let second = makeStore()
        XCTAssertEqual(second.vaults, first.vaults)
        XCTAssertNil(second.vault(id: UUID()))
    }

    func testCorruptedVaultDataStartsEmpty() {
        defaults.set(Data("not json".utf8), forKey: "exportProfileDestinations.vaults")
        let store = makeStore()
        XCTAssertTrue(store.vaults.isEmpty)
    }

    func testDeleteVaultRemovesRowAndKeepsOthers() throws {
        let store = makeStore()
        let a = store.upsertVault(name: "A", standardizedPath: "/a", bookmarkData: Data("a".utf8))
        let b = store.upsertVault(name: "B", standardizedPath: "/b", bookmarkData: Data("b".utf8))

        store.deleteVault(id: a.id)

        XCTAssertNil(store.vault(id: a.id))
        XCTAssertNotNil(store.vault(id: b.id))
        XCTAssertEqual(makeStore().vaults.map(\.id), [b.id])
    }

    // MARK: - API endpoints

    func testAPIEndpointUpsertSharesByURLAndStoresTokenInKeychain() {
        let store = makeStore()

        let first = store.upsertAPIEndpoint(
            name: "https://api.example.com",
            endpointURLString: "https://api.example.com",
            bearerToken: "token-one"
        )
        XCTAssertEqual(store.apiEndpoints.count, 1)
        XCTAssertEqual(store.token(for: first.id), "token-one")

        // Same URL with different casing/whitespace: same row, token replaced.
        let again = store.upsertAPIEndpoint(
            name: "https://api.example.com",
            endpointURLString: "  HTTPS://API.EXAMPLE.COM ",
            bearerToken: "token-two"
        )
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(store.apiEndpoints.count, 1)
        XCTAssertEqual(store.token(for: first.id), "token-two")

        // Clearing the token removes the Keychain entry.
        store.setToken("", for: first.id)
        XCTAssertNil(store.token(for: first.id))
    }

    func testAPIEndpointDeleteRemovesRowAndToken() {
        let store = makeStore()
        let endpoint = store.upsertAPIEndpoint(
            name: "https://api.example.com",
            endpointURLString: "https://api.example.com",
            bearerToken: "secret"
        )

        store.deleteAPIEndpoint(id: endpoint.id)

        XCTAssertTrue(store.apiEndpoints.isEmpty)
        XCTAssertNil(store.token(for: endpoint.id))
        XCTAssertNil(makeStore().apiEndpoint(id: endpoint.id))
    }

    func testAPIEndpointsPersistAcrossStoreInstances() {
        let first = makeStore()
        let endpoint = first.upsertAPIEndpoint(
            name: "https://api.example.com",
            endpointURLString: "https://api.example.com",
            bearerToken: "secret"
        )

        let second = makeStore()
        XCTAssertEqual(second.apiEndpoints.map(\.id), [endpoint.id])
        // Keychain-backed token follows the id.
        XCTAssertEqual(second.token(for: endpoint.id), "secret")
    }
}
