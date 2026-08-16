import XCTest
@testable import HealthMd

final class ExportProfileStoreTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings and nested
    // ObservableObjects use Combine subscriptions; existing tests retain them
    // to avoid platform-specific deinit crashes while the process tears down.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var fixedNow: Date!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ExportProfileStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        fixedNow = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStore() -> ExportProfileStore {
        ExportProfileStore(userDefaults: defaults, now: { self.fixedNow })
    }

    private func makeSnapshot(filenameFormat: String = "health-{date}") -> ExportSettingsSnapshot {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.filenameFormat = filenameFormat
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    // MARK: - Legacy mode

    func testEmptyStoreStartsInLegacyMode() {
        let store = makeStore()

        XCTAssertFalse(store.hasProfiles)
        XCTAssertNil(store.activeProfile)
        XCTAssertNil(store.activeProfileID)
        XCTAssertNil(store.profile(named: "Default"))
    }

    func testCorruptedOrEmptyPersistedDataFallsBackToLegacyMode() {
        defaults.set(Data("not json".utf8), forKey: "exportProfiles.list")

        let store = makeStore()

        XCTAssertFalse(store.hasProfiles)
        XCTAssertNil(store.activeProfile)
    }

    func testDanglingActiveProfileIDIgnoredOnLoad() {
        let store = makeStore()
        let profile = store.add(
            name: "Weekly",
            settings: makeSnapshot(),
            target: .connectedMac
        )
        let staleID = profile.id
        store.delete(id: profile.id)

        // Simulate external stale state: a saved active id with no list entry.
        defaults.set(staleID.uuidString, forKey: "exportProfiles.activeProfileID")
        defaults.set(Data("garbage".utf8), forKey: "exportProfiles.list")

        let reloaded = makeStore()
        XCTAssertFalse(reloaded.hasProfiles)
        XCTAssertNil(reloaded.activeProfile)
    }

    // MARK: - Migration

    func testMigrationCreatesDefaultProfileOnce() throws {
        let store = makeStore()
        let snapshot = makeSnapshot(filenameFormat: "migrated-{date}")

        let created = store.migrateDefaultProfileIfNeeded(
            settings: snapshot,
            target: .localIPhoneFolder
        )

        XCTAssertTrue(created)
        XCTAssertEqual(store.profiles.count, 1)

        let profile = try XCTUnwrap(store.activeProfile)
        XCTAssertEqual(profile.name, ExportProfileStore.defaultProfileName)
        XCTAssertTrue(profile.isMigrationDefault)
        XCTAssertEqual(profile.target, .localIPhoneFolder)
        XCTAssertEqual(profile.settings, snapshot)

        let secondCall = store.migrateDefaultProfileIfNeeded(
            settings: makeSnapshot(filenameFormat: "other-{date}"),
            target: .apiEndpoint
        )
        XCTAssertFalse(secondCall)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeProfile?.settings, snapshot)
    }

    // MARK: - Persistence round trip

    func testProfilesPersistAcrossStoreInstances() throws {
        let first = makeStore()
        let sleepSnapshot = makeSnapshot(filenameFormat: "sleep-{date}")
        let weeklySnapshot = makeSnapshot(filenameFormat: "week-{date}")
        let sleep = first.add(name: "Sleep", settings: sleepSnapshot, target: .localIPhoneFolder)
        let weekly = first.add(name: "Weekly", settings: weeklySnapshot, target: .connectedMac)
        first.activate(id: weekly.id)

        let second = makeStore()

        XCTAssertEqual(second.profiles, [sleep, weekly])
        XCTAssertEqual(second.activeProfileID, weekly.id)
        XCTAssertEqual(second.activeProfile?.name, "Weekly")
    }

    func testProfileCodableRoundTripPreservesSnapshot() throws {
        let snapshot = makeSnapshot()
        let profile = ExportProfile(
            name: "Round Trip",
            settings: snapshot,
            target: .apiEndpoint,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            isMigrationDefault: false
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ExportProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.settings, snapshot)
    }

    // MARK: - CRUD

    func testAddUniquifiesEmptyAndDuplicateNames() {
        let store = makeStore()
        let snapshot = makeSnapshot()

        let first = store.add(name: "Weekly", settings: snapshot, target: .localIPhoneFolder)
        let second = store.add(name: "Weekly", settings: snapshot, target: .localIPhoneFolder)
        let third = store.add(name: "   ", settings: snapshot, target: .localIPhoneFolder)

        XCTAssertEqual(first.name, "Weekly")
        XCTAssertEqual(second.name, "Weekly 2")
        XCTAssertFalse(third.name.isEmpty)
        XCTAssertEqual(Set([first.name, second.name, third.name]).count, 3)

        // First add becomes active automatically.
        XCTAssertEqual(store.activeProfileID, first.id)
    }

    func testRenameTrimsAndUniquifies() throws {
        let store = makeStore()
        let snapshot = makeSnapshot()
        let a = store.add(name: "Sleep", settings: snapshot, target: .localIPhoneFolder)
        store.add(name: "Weekly", settings: snapshot, target: .localIPhoneFolder)

        // Renaming to your own trimmed name is a no-op that keeps the name unique.
        XCTAssertEqual(store.rename(id: a.id, to: "  Sleep "), "Sleep")

        // Renaming onto another profile's name is suffixed.
        XCTAssertEqual(store.rename(id: a.id, to: "Weekly"), "Weekly 2")

        XCTAssertNil(store.rename(id: a.id, to: "  "))
        XCTAssertNil(store.rename(id: UUID(), to: "Anything"))
        XCTAssertEqual(store.profile(id: a.id)?.name, "Weekly 2")
    }

    func testUpdateSettingsAndTargetBumpTimestamp() throws {
        let store = ExportProfileStore(userDefaults: defaults, now: { self.fixedNow })
        let profile = store.add(
            name: "Workouts",
            settings: makeSnapshot(filenameFormat: "old-{date}"),
            target: .localIPhoneFolder
        )
        XCTAssertEqual(store.profile(id: profile.id)?.updatedAt, fixedNow)

        let later = fixedNow.addingTimeInterval(3_600)
        let laterStore = ExportProfileStore(userDefaults: defaults, now: { later })
        let updatedSnapshot = makeSnapshot(filenameFormat: "new-{date}")

        XCTAssertTrue(laterStore.updateSettings(id: profile.id, settings: updatedSnapshot))
        XCTAssertTrue(laterStore.updateTarget(id: profile.id, target: .apiEndpoint))

        let reloaded = makeStore()
        let updated = try XCTUnwrap(reloaded.profile(id: profile.id))
        XCTAssertEqual(updated.settings, updatedSnapshot)
        XCTAssertEqual(updated.target, .apiEndpoint)
        XCTAssertEqual(updated.updatedAt, later)

        XCTAssertFalse(laterStore.updateSettings(id: UUID(), settings: updatedSnapshot))
        XCTAssertFalse(laterStore.updateTarget(id: UUID(), target: .apiEndpoint))
    }

    func testDuplicateCopiesSettingsWithFreshIdentity() throws {
        let store = makeStore()
        let snapshot = makeSnapshot()
        let source = store.add(name: "Sleep", settings: snapshot, target: .localIPhoneFolder)

        let copy = try XCTUnwrap(store.duplicate(id: source.id))

        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.name, "Sleep 2")
        XCTAssertEqual(copy.settings, source.settings)
        XCTAssertEqual(copy.target, source.target)
        XCTAssertFalse(copy.isMigrationDefault)
        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertNil(store.duplicate(id: UUID()))
    }

    func testDeleteActiveFallsBackToRemainingProfile() throws {
        let store = makeStore()
        let snapshot = makeSnapshot()
        let first = store.add(name: "Daily", settings: snapshot, target: .localIPhoneFolder)
        let second = store.add(name: "Weekly", settings: snapshot, target: .connectedMac)
        store.activate(id: second.id)

        store.delete(id: second.id)

        XCTAssertEqual(store.activeProfileID, first.id)
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testDeleteLastProfileReturnsToLegacyMode() throws {
        let store = makeStore()
        let only = store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder)

        store.delete(id: only.id)

        XCTAssertFalse(store.hasProfiles)
        XCTAssertNil(store.activeProfileID)
        XCTAssertNil(store.activeProfile)
    }

    func testActivateRejectsUnknownIDs() throws {
        let store = makeStore()
        let profile = store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder)

        XCTAssertFalse(store.activate(id: UUID()))
        XCTAssertTrue(store.activate(id: profile.id))
        XCTAssertEqual(store.activeProfileID, profile.id)
    }

    // MARK: - Name lookup

    func testProfileNamedLookupIsTrimmedAndCaseInsensitive() throws {
        let store = makeStore()
        let profile = store.add(name: "Weekly Sleep", settings: makeSnapshot(), target: .localIPhoneFolder)

        XCTAssertEqual(store.profile(named: "  weekly sleep ")?.id, profile.id)
        XCTAssertEqual(store.profile(named: "WEEKLY SLEEP")?.id, profile.id)
        XCTAssertNil(store.profile(named: "Weekly"))
        XCTAssertNil(store.profile(named: "   "))
    }
}
