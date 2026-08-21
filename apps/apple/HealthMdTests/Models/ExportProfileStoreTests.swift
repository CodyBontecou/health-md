import XCTest
@testable import HealthMd

final class ExportProfileStoreTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings and nested
    // ObservableObjects use Combine subscriptions; existing tests retain them
    // to avoid platform-specific deinit crashes while the process tears down.
    private static var retainedSettings: [AdvancedExportSettings] = []
    // STATIC RETENTION JUSTIFICATION: MainActor-isolated deinits take the
    // back-deployed task path on older runtimes (CI's iOS 26.2 simulator)
    // where nested store release aborts; retain for the process lifetime.
    private static var retainedStores: [AnyObject] = []

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
        let store = ExportProfileStore(userDefaults: defaults, now: { self.fixedNow })
        Self.retainedStores.append(store)
        return store
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

    func testCorruptedPersistedDataFailsClosedInsteadOfEnteringLegacyMode() {
        defaults.set(Data("not json".utf8), forKey: "exportProfiles.list")

        let store = makeStore()

        XCTAssertTrue(store.hasProfiles)
        XCTAssertNil(store.activeProfile)
        XCTAssertEqual(store.unknownProfileRecordCount, 1)
        XCTAssertFalse(store.migrateDefaultProfileIfNeeded(
            settings: makeSnapshot(),
            target: .localIPhoneFolder
        ))
    }

    func testDanglingActiveProfileIDIgnoredOnLoad() {
        let store = makeStore()
        let profile = store.add(
            name: "Weekly",
            settings: makeSnapshot(),
            target: .connectedMac
        )
        let staleID = profile.id
        // Only one profile exists, so deletion is forbidden; simulate external
        // stale state directly instead.
        defaults.set(staleID.uuidString, forKey: "exportProfiles.v2.activeProfileID")
        defaults.set(Data("garbage".utf8), forKey: "exportProfiles.v2.envelope")

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.hasProfiles)
        XCTAssertNil(reloaded.activeProfile)
        XCTAssertEqual(reloaded.unknownProfileRecordCount, 1)
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

    func testProfilePersistencePreservesUnknownRecordWithoutErasingKnownProfile() throws {
        let known = ExportProfile(
            name: "Known",
            settings: makeSnapshot(),
            target: .googleDrive,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let knownObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(known))
        let unknown: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Future",
            "target": "future_destination",
            "version": 99
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: [knownObject, unknown]),
            forKey: "exportProfiles.list"
        )

        let store = makeStore()
        XCTAssertEqual(store.profiles, [known])
        XCTAssertEqual(store.unknownProfileRecordCount, 1)
        _ = store.rename(id: known.id, to: "Renamed")

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.profiles.map(\.name), ["Renamed"])
        XCTAssertEqual(reloaded.unknownProfileRecordCount, 1)
    }

    func testOpaqueOnlyProfileStateBlocksLegacyModeAndDefaultMigration() throws {
        defaults.set(
            try JSONSerialization.data(withJSONObject: [[
                "id": UUID().uuidString,
                "name": "Future",
                "target": "future_destination",
                "version": 99
            ]]),
            forKey: "exportProfiles.list"
        )

        let store = makeStore()
        XCTAssertTrue(store.hasProfiles)
        XCTAssertNil(store.activeProfile)
        XCTAssertEqual(store.unknownProfileRecordCount, 1)
        XCTAssertFalse(store.migrateDefaultProfileIfNeeded(
            settings: makeSnapshot(),
            target: .localIPhoneFolder
        ))
        XCTAssertEqual(makeStore().unknownProfileRecordCount, 1)
    }

    func testDriveProfileUsesV2EnvelopeAndLeavesLegacyPayloadUntouched() throws {
        let legacy = ExportProfile(
            name: "Legacy",
            settings: makeSnapshot(),
            target: .localIPhoneFolder,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let legacyData = try JSONEncoder().encode([legacy])
        defaults.set(legacyData, forKey: "exportProfiles.list")
        defaults.set(legacy.id.uuidString, forKey: "exportProfiles.activeProfileID")

        let store = makeStore()
        let drive = store.add(
            name: "Drive",
            settings: makeSnapshot(),
            target: .googleDrive,
            googleDriveDestinationID: UUID()
        )

        XCTAssertEqual(defaults.data(forKey: "exportProfiles.list"), legacyData)
        let envelopeData = try XCTUnwrap(defaults.data(forKey: "exportProfiles.v2.envelope"))
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: envelopeData) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 2)
        XCTAssertEqual((envelope["records"] as? [Any])?.count, 2)
        XCTAssertEqual(makeStore().profile(id: drive.id)?.target, .googleDrive)
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
        Self.retainedStores.append(store)
        let profile = store.add(
            name: "Workouts",
            settings: makeSnapshot(filenameFormat: "old-{date}"),
            target: .localIPhoneFolder
        )
        XCTAssertEqual(store.profile(id: profile.id)?.updatedAt, fixedNow)

        let later = fixedNow.addingTimeInterval(3_600)
        let laterStore = ExportProfileStore(userDefaults: defaults, now: { later })
        Self.retainedStores.append(laterStore)
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

        XCTAssertTrue(store.delete(id: second.id))

        XCTAssertEqual(store.activeProfileID, first.id)
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testDeletingLastRemainingProfileIsForbidden() throws {
        let store = makeStore()
        let only = store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder)

        XCTAssertFalse(store.delete(id: only.id))

        XCTAssertTrue(store.hasProfiles)
        XCTAssertEqual(store.activeProfileID, only.id)
        XCTAssertNotNil(store.activeProfile)

        // Unknown ids never delete anything.
        XCTAssertFalse(store.delete(id: UUID()))
        XCTAssertEqual(store.profiles.count, 1)
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
