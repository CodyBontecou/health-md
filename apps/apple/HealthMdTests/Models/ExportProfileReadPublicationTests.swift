import Combine
import XCTest
@testable import HealthMd

/// Profile detail observes the store and calls profile(id:) from its body and
/// navigation title. Reloading equal persisted state must not invalidate that
/// same body again; genuine external changes must still refresh the store.
final class ExportProfileReadPublicationTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: the snapshot fixture uses the same
    // nested ObservableObjects as other profile tests; retain them to avoid
    // older-runtime back-deployed deinit crashes unrelated to these reads.
    private static var retainedSettings: [AdvancedExportSettings] = []
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ExportProfileReadPublicationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func snapshot() -> ExportSettingsSnapshot {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    private func migratedStore() throws -> ExportProfileStore {
        let store = ExportProfileStore(userDefaults: defaults)
        XCTAssertTrue(store.migrateDefaultProfileIfNeeded(settings: snapshot(), target: .localIPhoneFolder))
        return store
    }

    private func assertQuietReads(
        _ store: ExportProfileStore,
        id: UUID?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = defaults.dictionaryRepresentation() as NSDictionary
        var changes = 0
        var profilePublications = 0
        var activePublications = 0
        var unknownPublications = 0
        let subscriptions = [
            store.objectWillChange.sink { changes += 1 },
            store.$profiles.dropFirst().sink { _ in profilePublications += 1 },
            store.$activeProfileID.dropFirst().sink { _ in activePublications += 1 },
            store.$unknownProfileRecordCount.dropFirst().sink { _ in unknownPublications += 1 }
        ]
        withExtendedLifetime(subscriptions) {
            for _ in 0..<3 {
                // The actual detail call pattern: body lookup, then title lookup.
                _ = store.profile(id: id)
                _ = store.profile(id: id)?.name
                _ = store.activeProfile
                _ = store.profile(named: "Default")
            }
        }
        XCTAssertEqual(changes, 0, "Unchanged detail reads must not invalidate their observed store", file: file, line: line)
        XCTAssertEqual(profilePublications, 0, file: file, line: line)
        XCTAssertEqual(activePublications, 0, file: file, line: line)
        XCTAssertEqual(unknownPublications, 0, file: file, line: line)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before, "Inspection must not write defaults", file: file, line: line)
    }

    func testMigratedDefaultDetailReadsDoNotPublishUnchangedState() throws {
        let store = try migratedStore()
        let id = try XCTUnwrap(store.activeProfileID)
        assertQuietReads(store, id: id)
        XCTAssertEqual(store.profile(id: id)?.name, ExportProfileStore.defaultProfileName)
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testEmptyLegacyReadsDoNotPublish() {
        let store = ExportProfileStore(userDefaults: defaults)
        assertQuietReads(store, id: nil)
        XCTAssertFalse(store.hasProfiles)
        XCTAssertNil(store.activeProfile)
    }

    func testUnreadableEnvelopeReadsStayQuietAndFailClosedOverValidLegacyState() throws {
        let legacy = ExportProfile(name: "Legacy", settings: snapshot(), target: .connectedMac)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: ExportProfilePersistence.legacyListKey)
        defaults.set(legacy.id.uuidString, forKey: ExportProfilePersistence.legacyActiveIDKey)
        for unreadable: Any in [Data("not json".utf8), "wrong type", Data("{\"version\":99,\"records\":[]}".utf8)] {
            defaults.set(unreadable, forKey: ExportProfilePersistence.envelopeKey)
            let store = ExportProfileStore(userDefaults: defaults)
            assertQuietReads(store, id: legacy.id)
            XCTAssertTrue(store.hasProfiles, "Unreadable authority must not become legacy fallback")
            XCTAssertTrue(store.profiles.isEmpty)
            XCTAssertNil(store.activeProfileID)
            XCTAssertEqual(store.unknownProfileRecordCount, 1)
            let migrationSnapshot = snapshot()
            let before = defaults.dictionaryRepresentation() as NSDictionary
            XCTAssertFalse(store.migrateDefaultProfileIfNeeded(settings: migrationSnapshot, target: .localIPhoneFolder))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
    }

    func testOpaqueRecordsRemainQuietAndPreserved() throws {
        let store = try migratedStore()
        let known = try XCTUnwrap(store.activeProfile)
        let opaque = Data("{\"target\":\"future_destination\",\"futureAuthority\":\"synthetic\"}".utf8)
        defaults.set(
            try ExportProfilePersistence.encode([known], opaque: [opaque], envelope: true),
            forKey: ExportProfilePersistence.envelopeKey
        )
        var unknownCounts: [Int] = []
        let subscription = store.$unknownProfileRecordCount.dropFirst().sink { unknownCounts.append($0) }
        withExtendedLifetime(subscription) {
            XCTAssertEqual(store.profile(id: known.id), known)
        }
        XCTAssertEqual(unknownCounts, [1], "An externally added opaque record must still be published")
        assertQuietReads(store, id: known.id)
        XCTAssertEqual(store.profiles, [known])
        XCTAssertEqual(store.unknownProfileRecordCount, 1)
        XCTAssertTrue(store.hasProfiles)
    }

    func testExternalProfileAndActivationChangesPublishThenSettle() throws {
        let observer = try migratedStore()
        let writer = ExportProfileStore(userDefaults: defaults)
        let other = writer.add(name: "Other", settings: snapshot(), target: .connectedMac)
        XCTAssertTrue(writer.activate(id: other.id))
        var changes = 0
        let subscription = observer.objectWillChange.sink { changes += 1 }
        withExtendedLifetime(subscription) {
            XCTAssertEqual(observer.activeProfile, other, "Reload must see the writer's latest profile and active ID")
            XCTAssertGreaterThan(changes, 0, "Do not suppress real changes to silence the view loop")
        }
        XCTAssertEqual(observer.profiles.count, 2)
        assertQuietReads(observer, id: other.id)

        changes = 0
        XCTAssertTrue(writer.rename(id: other.id, to: "Renamed") != nil)
        withExtendedLifetime(subscription) {
            XCTAssertEqual(observer.profile(named: "Renamed")?.id, other.id)
            XCTAssertGreaterThan(changes, 0)
        }
        assertQuietReads(observer, id: other.id)
    }

    func testExternalCorruptionClearsStaleAuthorityPublishesThenSettles() throws {
        let store = try migratedStore()
        let id = try XCTUnwrap(store.activeProfileID)
        defaults.set("wrong type", forKey: ExportProfilePersistence.envelopeKey)
        var changes = 0
        let subscription = store.objectWillChange.sink { changes += 1 }
        withExtendedLifetime(subscription) {
            XCTAssertNil(store.profile(id: id))
            XCTAssertGreaterThan(changes, 0)
        }
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertNil(store.activeProfileID)
        XCTAssertEqual(store.unknownProfileRecordCount, 1)
        XCTAssertTrue(store.hasProfiles)
        assertQuietReads(store, id: id)
    }

    func testExternalRemovalClearsStaleProfilePublishesThenSettles() throws {
        let store = try migratedStore()
        let id = try XCTUnwrap(store.activeProfileID)
        defaults.removeObject(forKey: ExportProfilePersistence.envelopeKey)
        defaults.removeObject(forKey: ExportProfilePersistence.activeIDKey)
        var changes = 0
        let subscription = store.objectWillChange.sink { changes += 1 }
        withExtendedLifetime(subscription) {
            XCTAssertNil(store.profile(id: id))
            XCTAssertGreaterThan(changes, 0)
        }
        XCTAssertFalse(store.hasProfiles)
        XCTAssertNil(store.activeProfileID)
        XCTAssertEqual(store.unknownProfileRecordCount, 0)
        assertQuietReads(store, id: id)
    }

    func testDanglingExternalActiveIDPublishesNilOnceThenSettles() throws {
        let store = try migratedStore()
        let id = try XCTUnwrap(store.activeProfileID)
        defaults.set(UUID().uuidString, forKey: ExportProfilePersistence.activeIDKey)
        var activeIDs: [UUID?] = []
        let subscription = store.$activeProfileID.dropFirst().sink { activeIDs.append($0) }
        withExtendedLifetime(subscription) {
            XCTAssertNil(store.activeProfile)
        }
        XCTAssertEqual(activeIDs, [nil])
        XCTAssertEqual(store.profiles.count, 1)
        assertQuietReads(store, id: id)
    }
}
