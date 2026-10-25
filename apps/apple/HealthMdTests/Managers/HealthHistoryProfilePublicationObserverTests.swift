import Combine
import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class HealthHistoryProfilePublicationObserverTests: XCTestCase {
    func testProductionCoordinatorRedundantFlushAndRenameDuringProviderAwaitAllowCapture() async throws {
        try await check(mutation: "flush")
    }

    func testProductionCoordinatorSameSettingsProfileSwitchDuringProviderAwaitRejectsCapture() async throws {
        try await check(mutation: "switch")
    }

    func testProductionCoordinatorObservedProfileABARejectsCaptureDespiteFinalIdentityEquality() async throws {
        try await check(mutation: "aba")
    }

    func testProductionStoreMeaningfulSettingsUpdateDuringProviderAwaitRejectsCapture() async throws {
        try await check(mutation: "settings")
    }

    func testUnboundObserverDoesNotRetainOldLifecycleOrInvalidateNewOwner() {
        let suite = "HistoryPublicationLifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExportProfileStore(userDefaults: defaults)
        let snapshot = ExportSettingsSnapshot.from(AdvancedExportSettings())
        let first = store.add(name: "First", settings: snapshot, target: .localIPhoneFolder)
        let second = store.add(name: "Second", settings: snapshot, target: .localIPhoneFolder)
        let observer = HealthHistoryProfilePublicationObserver()
        var oldEvents = 0
        observer.bind(store) { oldEvents += 1 }
        observer.unbind()
        XCTAssertTrue(store.activate(id: second.id))
        XCTAssertEqual(oldEvents, 0)
        var newEvents = 0
        observer.bind(store) { newEvents += 1 }
        XCTAssertEqual(newEvents, 0, "Fresh binding establishes its initial baseline without cancelling a new owner")
        XCTAssertTrue(store.activate(id: first.id))
        XCTAssertEqual(newEvents, 1)
        observer.unbind()
    }

    private func check(mutation: String) async throws {
        let suite = "HistoryProfilePublication.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainStore()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.metricSelection.deselectAll()
        settings.metricSelection.toggleMetric("steps")
        let vault = VaultManager(defaults: SystemUserDefaults(defaults: defaults),
            fileSystem: FakeFileSystem(), bookmarkResolver: FakeBookmarkResolver(),
            identityProbe: FakeVaultFolderIdentityProbe())
        let profiles = ExportProfileCoordinator(profileStore: ExportProfileStore(userDefaults: defaults),
            destinationStore: ProfileDestinationStore(userDefaults: defaults, keychain: keychain),
            scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults), settings: settings,
            vaultManager: vault, apiExportSettings: APIExportSettings(userDefaults: defaults, keychain: keychain),
            initialTarget: .localIPhoneFolder)
        let first = try XCTUnwrap(profiles.profileStore.activeProfile)
        let second = profiles.profileStore.add(name: "Same settings", settings: first.settings, target: first.target)
        XCTAssertEqual(first.settings, second.settings)
        let coordinator = HealthHistoryAssessmentCoordinator()
        let observer = HealthHistoryProfilePublicationObserver()
        var meaningfulEvents = 0
        observer.bind(profiles.profileStore) { meaningfulEvents += 1; coordinator.invalidate() }
        defer { observer.unbind() }
        var broadPublications = 0
        let broad = profiles.profileStore.objectWillChange.sink { broadPublications += 1 }
        defer { broad.cancel() }
        // The actual production preflight before freezing the request is retained.
        profiles.flushEdits()
        let baseline = meaningfulEvents
        let store = FakeHealthStore()
        let sut = HealthKitManager(store: store, userDefaults: defaults)
        let scope = HealthHistoryScope(metricIDs: ["steps"], startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400), timeZoneIdentifier: "UTC",
            allAvailable: false, profileID: first.id, rangeSemantics: .ownerDates)
        let entered = expectation(description: "actual provider suspended")
        let finished = expectation(description: "profile publication gate finished")
        let gate = HistoryTestSuspension(entered: entered)
        store.historySuspension = { await gate.wait() }
        let worker = HealthHistoryAssessmentWorker()
        var captures = 0
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            let result = await coordinator.assess(scope: scope, isCurrent: {
                profiles.profileStore.activeProfileID == scope.profileID
            }, operation: {
                await worker.assess(notCompleted: sut.historyAssessmentNotCompleted(scope: scope)) {
                    await sut.assessHistoryAccess(scope: scope)
                }
            })
            if result != nil { captures += 1 }
        }
        defer { gate.resume(); task.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        switch mutation {
        case "switch": XCTAssertTrue(profiles.activate(profileID: second.id))
        case "aba":
            XCTAssertTrue(profiles.activate(profileID: second.id))
            XCTAssertTrue(profiles.activate(profileID: first.id))
            XCTAssertEqual(profiles.profileStore.activeProfileID, first.id)
        case "settings":
            var updated = first.settings
            updated.includeMetadata.toggle()
            XCTAssertTrue(profiles.profileStore.updateSettings(id: first.id, settings: updated))
        default:
            profiles.flushEdits() // Same snapshot, real timestamp/list publication.
            XCTAssertNotNil(profiles.profileStore.rename(id: first.id, to: "Renamed"))
            XCTAssertEqual(meaningfulEvents, baseline)
        }
        XCTAssertGreaterThan(broadPublications, 0, "The redundant positive really publishes through the old failing broad path")
        if mutation != "flush" { XCTAssertGreaterThan(meaningfulEvents, baseline) }
        gate.resume()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(captures, mutation == "flush" ? 1 : 0)
        XCTAssertEqual(store.historyRequestedIdentifiers, [HKQuantityTypeIdentifier.stepCount.rawValue])
    }
}
