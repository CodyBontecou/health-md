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

    private func makeSnapshot(
        filenameFormat: String = "health-{date}",
        detailPolicy: AppleExportDetailPolicy = .summary
    ) -> ExportSettingsSnapshot {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.filenameFormat = filenameFormat
        settings.detailPolicy = detailPolicy
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    func testConfigurationRevisionSurvivesReloadAndDoesNotReusePinsWhenSettingsReturn() throws {
        let store = makeStore(), original = makeSnapshot(filenameFormat: "first-{date}")
        let profile = try XCTUnwrap(store.add(name: "Daily", settings: original, target: .localIPhoneFolder))
        let untouched = try XCTUnwrap(store.add(name: "Other", settings: original, target: .localIPhoneFolder))
        let secondStore = makeStore()
        XCTAssertEqual(profile.configurationRevision, 1)
        XCTAssertTrue(secondStore.updateSettings(id: profile.id, settings: makeSnapshot(filenameFormat: "changed-{date}")))
        XCTAssertEqual(secondStore.profile(id: profile.id)?.configurationRevision, 2)
        XCTAssertTrue(store.updateSettings(id: profile.id, settings: original))
        let restored = try XCTUnwrap(makeStore().profile(id: profile.id))
        XCTAssertEqual(restored.settings, original)
        XCTAssertEqual(restored.updatedAt, profile.updatedAt) // The clock is deliberately unchanged.
        XCTAssertEqual(restored.configurationRevision, 3)
        XCTAssertEqual(store.profile(id: untouched.id)?.configurationRevision, 1)
    }

    func testEveryNativeProfileEditAdvancesItsLocalRevisionAndDuplicateStartsFresh() throws {
        let store = makeStore(), snapshot = makeSnapshot()
        let profile = try XCTUnwrap(store.add(name: "Daily", settings: snapshot, target: .localIPhoneFolder))
        let folder = UUID(), endpoint = UUID()
        XCTAssertTrue(store.setFolderBinding(profileID: profile.id, destinationID: folder))
        XCTAssertTrue(store.setAPIEndpointBinding(profileID: profile.id, endpointID: endpoint))
        XCTAssertTrue(store.updateTarget(id: profile.id, target: .connectedMac))
        XCTAssertEqual(store.rename(id: profile.id, to: "Renamed"), "Renamed")
        XCTAssertEqual(store.profile(id: profile.id)?.configurationRevision, 5)
        XCTAssertTrue(store.setFolderBinding(profileID: profile.id, destinationID: folder))
        XCTAssertTrue(store.setAPIEndpointBinding(profileID: profile.id, endpointID: endpoint))
        XCTAssertEqual(store.profile(id: profile.id)?.configurationRevision, 5)
        XCTAssertTrue(store.activate(id: profile.id))
        XCTAssertEqual(store.profile(id: profile.id)?.configurationRevision, 5)
        let duplicate = try XCTUnwrap(store.duplicate(id: profile.id))
        XCTAssertNotEqual(duplicate.id, profile.id)
        XCTAssertEqual(duplicate.configurationRevision, 1)
    }

    func testLegacyProfileRevisionDefaultsWithoutWritingAndMalformedRevisionDoesNotBecomeLegacy() throws {
        let store = makeStore()
        _ = store.add(name: "Legacy", settings: makeSnapshot(), target: .localIPhoneFolder)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "exportProfiles.list"))) as? [[String: Any]])
        rows[0].removeValue(forKey: "configurationRevision")
        let legacy = try JSONSerialization.data(withJSONObject: rows)
        defaults.set(legacy, forKey: "exportProfiles.list")
        let reloaded = makeStore(), profile = try XCTUnwrap(reloaded.profiles.first)
        XCTAssertEqual(profile.configurationRevision, 1)
        XCTAssertEqual(defaults.data(forKey: "exportProfiles.list"), legacy)
        for invalid in [NSNull(), "1", true] as [Any] {
            var malformed = rows[0]; malformed["configurationRevision"] = invalid
            XCTAssertThrowsError(try JSONDecoder().decode(ExportProfile.self, from: JSONSerialization.data(withJSONObject: malformed)))
        }
        XCTAssertTrue(reloaded.updateSettings(id: profile.id, settings: profile.settings))
        XCTAssertEqual(makeStore().profile(id: profile.id)?.configurationRevision, 2)
    }

    func testLoadedStoreCannotOverwriteMalformedPersistedRevisionFromItsCachedProfile() throws {
        let store = makeStore()
        let profile = try XCTUnwrap(store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder))
        let other = try XCTUnwrap(store.add(name: "Other", settings: profile.settings, target: .localIPhoneFolder))
        let cachedProfiles = store.profiles
        let cachedActiveID = store.activeProfileID
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "exportProfiles.list"))) as? [[String: Any]])
        for invalid in [NSNull(), "1", true, "99999999999999999999999999999999999"] as [Any] {
            var row = rows[0]; row["configurationRevision"] = invalid
            let before = try JSONSerialization.data(withJSONObject: [row, rows[1]])
            defaults.set(before, forKey: "exportProfiles.list")
            XCTAssertFalse(store.updateSettings(id: profile.id, settings: profile.settings))
            XCTAssertFalse(store.updateTarget(id: profile.id, target: .connectedMac))
            XCTAssertNil(store.rename(id: profile.id, to: "Changed"))
            XCTAssertFalse(store.setFolderBinding(profileID: profile.id, destinationID: UUID()))
            XCTAssertFalse(store.setAPIEndpointBinding(profileID: profile.id, endpointID: UUID()))
            XCTAssertEqual(defaults.data(forKey: "exportProfiles.list"), before)
            XCTAssertNil(store.add(name: "Unrelated", settings: profile.settings, target: .localIPhoneFolder))
            XCTAssertFalse(store.delete(id: profile.id))
            XCTAssertFalse(store.activate(id: other.id))
            XCTAssertFalse(store.migrateDefaultProfileIfNeeded(settings: profile.settings, target: .connectedMac))
            XCTAssertEqual(store.profiles, cachedProfiles)
            XCTAssertEqual(store.activeProfileID, cachedActiveID)
            XCTAssertEqual(defaults.data(forKey: "exportProfiles.list"), before)
        }
    }

    func testExhaustedConfigurationRevisionRejectsEditsWithoutChangingPersistedProfile() throws {
        let store = makeStore()
        let profile = try XCTUnwrap(store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder))
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "exportProfiles.list"))) as? [[String: Any]])
        rows[0]["configurationRevision"] = Int(Int32.max)
        let before = try JSONSerialization.data(withJSONObject: rows)
        defaults.set(before, forKey: "exportProfiles.list")
        XCTAssertFalse(store.updateSettings(id: profile.id, settings: profile.settings))
        XCTAssertFalse(store.updateTarget(id: profile.id, target: .connectedMac))
        XCTAssertNil(store.rename(id: profile.id, to: "Changed"))
        XCTAssertFalse(store.setFolderBinding(profileID: profile.id, destinationID: UUID()))
        XCTAssertFalse(store.setAPIEndpointBinding(profileID: profile.id, endpointID: UUID()))
        XCTAssertTrue(store.setFolderBinding(profileID: profile.id, destinationID: nil))
        XCTAssertEqual(defaults.data(forKey: "exportProfiles.list"), before)
        XCTAssertEqual(store.profile(id: profile.id)?.configurationRevision, Int(Int32.max))
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

    func testDanglingActiveProfileIDIgnoredOnLoad() throws {
        let store = makeStore()
        let profile = try XCTUnwrap(store.add(
            name: "Weekly",
            settings: makeSnapshot(),
            target: .connectedMac
        ))
        let staleID = profile.id
        // Only one profile exists, so deletion is forbidden; simulate external
        // stale state directly instead.
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
        let sleep = try XCTUnwrap(first.add(name: "Sleep", settings: sleepSnapshot, target: .localIPhoneFolder))
        let weekly = try XCTUnwrap(first.add(name: "Weekly", settings: weeklySnapshot, target: .connectedMac))
        first.activate(id: weekly.id)

        let second = makeStore()

        XCTAssertEqual(second.profiles, [sleep, weekly])
        XCTAssertEqual(second.activeProfileID, weekly.id)
        XCTAssertEqual(second.activeProfile?.name, "Weekly")
    }

    func testProfilePersistsDetailedTimeSeriesWithoutLosslessArchive() throws {
        let first = makeStore()
        let snapshot = makeSnapshot(detailPolicy: .detailedTimeSeries)
        let profile = try XCTUnwrap(first.add(
            name: "Charts",
            settings: snapshot,
            target: .localIPhoneFolder
        ))

        let reloaded = makeStore()
        let persisted = try XCTUnwrap(reloaded.profile(id: profile.id))

        XCTAssertEqual(persisted.settings.detailPolicy, .detailedTimeSeries)
        XCTAssertFalse(persisted.settings.includeGranularData)
    }

    func testProfilePersistsArchiveOnlyPolicyWithoutExposingLegacyLosslessBridge() throws {
        let first = makeStore()
        let snapshot = makeSnapshot(detailPolicy: .archiveOnly)
        let profile = try XCTUnwrap(first.add(
            name: "Canonical archive",
            settings: snapshot,
            target: .localIPhoneFolder
        ))

        let reloaded = makeStore()
        let persisted = try XCTUnwrap(reloaded.profile(id: profile.id))

        XCTAssertEqual(persisted.settings.detailPolicy, .archiveOnly)
        XCTAssertFalse(persisted.settings.includeGranularData)
        XCTAssertEqual(
            AppleExportDetailPreset(policy: persisted.settings.detailPolicy),
            .archiveOnly
        )
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

    func testAddUniquifiesEmptyAndDuplicateNames() throws {
        let store = makeStore()
        let snapshot = makeSnapshot()

        let first = try XCTUnwrap(store.add(name: "Weekly", settings: snapshot, target: .localIPhoneFolder))
        let second = try XCTUnwrap(store.add(name: "Weekly", settings: snapshot, target: .localIPhoneFolder))
        let third = try XCTUnwrap(store.add(name: "   ", settings: snapshot, target: .localIPhoneFolder))

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
        let a = try XCTUnwrap(store.add(name: "Sleep", settings: snapshot, target: .localIPhoneFolder))
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
        let profile = try XCTUnwrap(store.add(
            name: "Workouts",
            settings: makeSnapshot(filenameFormat: "old-{date}"),
            target: .localIPhoneFolder
        ))
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
        let source = try XCTUnwrap(store.add(name: "Sleep", settings: snapshot, target: .localIPhoneFolder))

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
        let first = try XCTUnwrap(store.add(name: "Daily", settings: snapshot, target: .localIPhoneFolder))
        let second = try XCTUnwrap(store.add(name: "Weekly", settings: snapshot, target: .connectedMac))
        store.activate(id: second.id)

        XCTAssertTrue(store.delete(id: second.id))

        XCTAssertEqual(store.activeProfileID, first.id)
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testDeletingLastRemainingProfileIsForbidden() throws {
        let store = makeStore()
        let only = try XCTUnwrap(store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder))

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
        let profile = try XCTUnwrap(store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder))

        XCTAssertFalse(store.activate(id: UUID()))
        XCTAssertTrue(store.activate(id: profile.id))
        XCTAssertEqual(store.activeProfileID, profile.id)
    }

    // MARK: - Name lookup

    func testProfileNamedLookupIsTrimmedAndCaseInsensitive() throws {
        let store = makeStore()
        let profile = try XCTUnwrap(store.add(name: "Weekly Sleep", settings: makeSnapshot(), target: .localIPhoneFolder))

        XCTAssertEqual(store.profile(named: "  weekly sleep ")?.id, profile.id)
        XCTAssertEqual(store.profile(named: "WEEKLY SLEEP")?.id, profile.id)
        XCTAssertNil(store.profile(named: "Weekly"))
        XCTAssertNil(store.profile(named: "   "))
    }
}
