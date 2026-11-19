import XCTest
@testable import HealthMd

/// Upgrading from 3.5, which saved one named API endpoint per keystroke of the
/// URL field. The first 4.0 coordinator launch removes those rows once and
/// never touches an endpoint anything references.
@MainActor
final class APIEndpointKeystrokeCleanupTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: same as ExportProfileCoordinatorTests;
    // nested ObservableObject stores abort on release on the iOS 26.2 runtime.
    private static var retainedInstances: [AnyObject] = []

    private struct Fixture: Decodable {
        let apiExportEndpointURL: String
        let boundEndpointID: UUID
        let apiEndpoints: [SavedAPIEndpoint]
    }

    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var keychain: FakeKeychainStore!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "APIEndpointKeystrokeCleanupTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        keychain = FakeKeychainStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        keychain = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Upgrade/apple-3.5-keystroke-api-endpoints.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private static func tokenKey(_ id: UUID) -> String {
        "exportProfileDestinations.apiToken.\(id.uuidString)"
    }

    private func snapshot() -> ExportSettingsSnapshot {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedInstances.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    /// Writes 3.5-era state the way 3.5 left it: the legacy profile list (no v2
    /// envelope) with "Default" bound to `boundEndpointID` on the API target and
    /// an active local-folder profile, the per-keystroke endpoint rows, the live
    /// Settings URL, and Keychain tokens for the given rows.
    private func seed35State(
        endpoints: [SavedAPIEndpoint],
        boundEndpointID: UUID?,
        liveURL: String,
        tokens: [UUID: String]
    ) throws {
        let settings = snapshot()
        let defaultProfile = ExportProfile(
            name: "Default",
            settings: settings,
            target: .apiEndpoint,
            apiEndpointID: boundEndpointID,
            isMigrationDefault: true
        )
        let folderProfile = ExportProfile(name: "QA Folder", settings: settings, target: .localIPhoneFolder)
        defaults.set(
            try ExportProfilePersistence.encode([defaultProfile, folderProfile], envelope: false),
            forKey: ExportProfilePersistence.legacyListKey
        )
        defaults.set(folderProfile.id.uuidString, forKey: ExportProfilePersistence.legacyActiveIDKey)
        defaults.set(try JSONEncoder().encode(endpoints), forKey: "exportProfileDestinations.apiEndpoints")
        defaults.set(liveURL, forKey: APIExportSettings.endpointURLStorageKey)
        for (id, token) in tokens { keychain.writeString(key: Self.tokenKey(id), value: token) }
    }

    private func launchCoordinator() -> ExportProfileCoordinator {
        let vaultManager = VaultManager(
            defaults: SystemUserDefaults(defaults: defaults),
            bookmarkResolver: PathMappingBookmarkResolver(),
            identityProbe: FakeVaultFolderIdentityProbe()
        )
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let coordinator = ExportProfileCoordinator(
            profileStore: ExportProfileStore(userDefaults: defaults),
            destinationStore: ProfileDestinationStore(userDefaults: defaults, keychain: keychain),
            scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults),
            settings: settings,
            vaultManager: vaultManager,
            apiExportSettings: APIExportSettings(userDefaults: defaults, keychain: keychain),
            initialTarget: .localIPhoneFolder
        )
        Self.retainedInstances.append(contentsOf: [coordinator, vaultManager, settings] as [AnyObject])
        return coordinator
    }

    private func persistedEndpoints() throws -> [SavedAPIEndpoint] {
        let data = try XCTUnwrap(defaults.data(forKey: "exportProfileDestinations.apiEndpoints"))
        return try JSONDecoder().decode([SavedAPIEndpoint].self, from: data)
    }

    // MARK: - Upgrade from the 3.5 capture

    func testUpgradeFrom35KeepsOnlyTheBoundEndpointAndItsToken() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.apiEndpoints.count, 53)
        let stray = UUID()
        try seed35State(
            endpoints: fixture.apiEndpoints,
            boundEndpointID: fixture.boundEndpointID,
            liveURL: fixture.apiExportEndpointURL,
            tokens: [fixture.boundEndpointID: "synthetic-token"]
        )
        // A prefix row that somehow carries a token loses it with the row; a
        // token key for an unknown id and the legacy Settings token stay.
        let prefixRow = try XCTUnwrap(fixture.apiEndpoints.first { $0.endpointURLString == "https://example.invalid" })
        keychain.writeString(key: Self.tokenKey(prefixRow.id), value: "prefix-token")
        keychain.writeString(key: Self.tokenKey(stray), value: "unrelated")
        keychain.writeString(key: "apiExport.bearerToken", value: "synthetic-token")

        let coordinator = launchCoordinator()

        let remaining = coordinator.destinationStore.apiEndpoints
        XCTAssertEqual(remaining.map(\.id), [fixture.boundEndpointID])
        XCTAssertEqual(remaining.first?.endpointURLString, "https://example.invalid/healthmd")
        XCTAssertEqual(try persistedEndpoints().map(\.id), [fixture.boundEndpointID])
        XCTAssertEqual(coordinator.destinationStore.token(for: fixture.boundEndpointID), "synthetic-token")
        XCTAssertNil(keychain.readString(key: Self.tokenKey(prefixRow.id)))
        XCTAssertEqual(keychain.readString(key: Self.tokenKey(stray)), "unrelated")
        XCTAssertEqual(keychain.readString(key: "apiExport.bearerToken"), "synthetic-token")

        let defaultProfile = try XCTUnwrap(coordinator.profileStore.profiles.first { $0.name == "Default" })
        XCTAssertEqual(defaultProfile.apiEndpointID, fixture.boundEndpointID)
        XCTAssertEqual(
            defaults.integer(forKey: APIEndpointKeystrokeCleanup.versionKey),
            APIEndpointKeystrokeCleanup.currentVersion
        )
    }

    func testSecondLaunchChangesNothing() throws {
        let fixture = try loadFixture()
        try seed35State(
            endpoints: fixture.apiEndpoints,
            boundEndpointID: fixture.boundEndpointID,
            liveURL: fixture.apiExportEndpointURL,
            tokens: [fixture.boundEndpointID: "synthetic-token"]
        )
        _ = launchCoordinator()
        XCTAssertEqual(try persistedEndpoints().count, 1)

        // A prefix-shaped row saved after the cleanup survives later launches:
        // the versioned flag keeps the cleanup from running again.
        let store = ProfileDestinationStore(userDefaults: defaults, keychain: keychain)
        let later = store.upsertAPIEndpoint(
            name: "https://example.invalid/healthm",
            endpointURLString: "https://example.invalid/healthm",
            bearerToken: "later-token"
        )
        let afterFirst = try XCTUnwrap(defaults.data(forKey: "exportProfileDestinations.apiEndpoints"))
        let keychainAfterFirst = keychain.stringStorage
        XCTAssertNil(store.removeKeystrokeAPIEndpointsIfNeeded(referencedEndpointIDs: [], liveEndpointURLString: ""))
        _ = launchCoordinator()
        XCTAssertNotNil(try persistedEndpoints().first { $0.id == later.id })

        XCTAssertEqual(defaults.data(forKey: "exportProfileDestinations.apiEndpoints"), afterFirst)
        XCTAssertEqual(keychain.stringStorage, keychainAfterFirst)
    }

    func testPlanIsIdempotentOnItsOwnResult() throws {
        let fixture = try loadFixture()
        let rows = fixture.apiEndpoints.map {
            APIEndpointKeystrokeCleanup.Row(
                id: $0.id, name: $0.name, endpointURLString: $0.endpointURLString,
                token: $0.id == fixture.boundEndpointID ? "t" : nil, createdAt: $0.createdAt
            )
        }
        let protected: Set<UUID> = [fixture.boundEndpointID]
        let removed = APIEndpointKeystrokeCleanup.removableIDs(in: rows, protectedIDs: protected)
        XCTAssertEqual(removed.count, 52)
        let kept = rows.filter { !removed.contains($0.id) }
        XCTAssertTrue(APIEndpointKeystrokeCleanup.removableIDs(in: kept, protectedIDs: protected).isEmpty)
    }

    // MARK: - What is kept

    func testUnreferencedDistinctEndpointIsKept() throws {
        let fixture = try loadFixture()
        let other = SavedAPIEndpoint(name: "https://other.example.invalid/ingest", endpointURLString: "https://other.example.invalid/ingest")
        let named = SavedAPIEndpoint(name: "Staging", endpointURLString: "https://example.invalid/staging")
        try seed35State(
            endpoints: fixture.apiEndpoints + [other, named],
            boundEndpointID: fixture.boundEndpointID,
            liveURL: fixture.apiExportEndpointURL,
            tokens: [other.id: "other-token"]
        )

        let coordinator = launchCoordinator()

        XCTAssertEqual(
            Set(coordinator.destinationStore.apiEndpoints.map(\.id)),
            [fixture.boundEndpointID, other.id, named.id]
        )
        XCTAssertEqual(coordinator.destinationStore.token(for: other.id), "other-token")
    }

    func testReferencedPrefixAndLiveSettingsEndpointAreKept() throws {
        let fixture = try loadFixture()
        let byURL = Dictionary(uniqueKeysWithValues: fixture.apiEndpoints.map { ($0.endpointURLString, $0.id) })
        let referencedPrefix = try XCTUnwrap(byURL["https://example.invalid/heal"])
        let livePrefix = try XCTUnwrap(byURL["https://example.invalid/he"])
        let pendingPrefix = try XCTUnwrap(byURL["https://example.invalid/h"])
        try seed35State(
            endpoints: fixture.apiEndpoints,
            boundEndpointID: referencedPrefix,
            liveURL: "https://EXAMPLE.invalid/he",
            tokens: [:]
        )
        // A pending export still names one row by id.
        defaults.set(
            Data(#"[{"apiDestinationIdentity":{"bindingID":"\#(pendingPrefix.uuidString)"}}]"#.utf8),
            forKey: "pendingExportRequests"
        )

        let coordinator = launchCoordinator()
        let ids = Set(coordinator.destinationStore.apiEndpoints.map(\.id))

        // Every protected row stays. The rows typed one character at a time
        // past the bound "…/heal" are its tail and go, as do the shorter prefixes.
        XCTAssertEqual(ids, [referencedPrefix, livePrefix, pendingPrefix])
    }

    func testExactDuplicateOfAKeptEndpointIsRemovedButADifferentTokenIsKept() {
        let kept = APIEndpointKeystrokeCleanup.Row(
            id: UUID(), name: "Home", endpointURLString: "https://home.example.invalid/hook",
            token: "a", createdAt: Date(timeIntervalSince1970: 1)
        )
        let duplicate = APIEndpointKeystrokeCleanup.Row(
            id: UUID(), name: "Home copy", endpointURLString: "https://HOME.example.invalid/hook ",
            token: "a", createdAt: Date(timeIntervalSince1970: 2)
        )
        let otherToken = APIEndpointKeystrokeCleanup.Row(
            id: UUID(), name: "Home other", endpointURLString: "https://home.example.invalid/hook",
            token: "b", createdAt: Date(timeIntervalSince1970: 3)
        )

        let removed = APIEndpointKeystrokeCleanup.removableIDs(
            in: [duplicate, kept, otherToken], protectedIDs: [kept.id]
        )

        XCTAssertEqual(removed, [duplicate.id])
    }

    func testUserNamedPrefixAndTokenedTailAreKept() {
        let anchor = APIEndpointKeystrokeCleanup.Row(
            id: UUID(), name: "Main", endpointURLString: "https://a.example.invalid/x",
            token: nil, createdAt: Date()
        )
        let namedPrefix = APIEndpointKeystrokeCleanup.Row(
            id: UUID(), name: "Root", endpointURLString: "https://a.example.invalid",
            token: nil, createdAt: Date()
        )
        let tokenedTail = APIEndpointKeystrokeCleanup.Row(
            id: UUID(), name: "https://a.example.invalid/xy", endpointURLString: "https://a.example.invalid/xy",
            token: "t", createdAt: Date()
        )
        let gappedTail = APIEndpointKeystrokeCleanup.Row(
            id: UUID(), name: "https://a.example.invalid/x/long", endpointURLString: "https://a.example.invalid/x/long",
            token: nil, createdAt: Date()
        )

        let removed = APIEndpointKeystrokeCleanup.removableIDs(
            in: [anchor, namedPrefix, tokenedTail, gappedTail], protectedIDs: [anchor.id]
        )

        XCTAssertTrue(removed.isEmpty)
    }

    func testUnreadableProfileRecordDefersTheCleanup() throws {
        let fixture = try loadFixture()
        try seed35State(
            endpoints: fixture.apiEndpoints,
            boundEndpointID: fixture.boundEndpointID,
            liveURL: fixture.apiExportEndpointURL,
            tokens: [:]
        )
        defaults.set(Data("not json".utf8), forKey: ExportProfilePersistence.legacyListKey)

        let coordinator = launchCoordinator()

        XCTAssertEqual(coordinator.destinationStore.apiEndpoints.count, 53)
        XCTAssertEqual(defaults.integer(forKey: APIEndpointKeystrokeCleanup.versionKey), 0)
    }
}
