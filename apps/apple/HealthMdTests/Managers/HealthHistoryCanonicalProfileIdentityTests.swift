import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class HealthHistoryCanonicalProfileIdentityTests: XCTestCase {
    func testSeparateStoreSameSettingsSwitchDuringActualProviderAwaitRejectsCapture() async throws {
        try await check(mutation: "switch")
    }

    func testSeparateStoreProfileDeletionDuringActualProviderAwaitRejectsCapture() async throws {
        try await check(mutation: "delete")
    }

    func testRemovedPersistedIdentityDuringActualProviderAwaitRejectsCaptureDespiteCachedRawID() async throws {
        try await check(mutation: "remove_identity")
    }

    func testUnchangedSeparateStoreIdentityDuringActualProviderAwaitAllowsCapture() async throws {
        try await check(mutation: "unchanged")
    }

    private func check(mutation: String) async throws {
        let suite = "HistoryCanonicalProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ExportSettingsSnapshot.from(AdvancedExportSettings(), appleExportEngineAuthorityIsFrozen: false)
        let writer = ExportProfileStore(userDefaults: defaults)
        let first = writer.add(name: "First", settings: settings, target: .localIPhoneFolder)
        let second = writer.add(name: "Same settings", settings: settings, target: .localIPhoneFolder)
        let observedStore = ExportProfileStore(userDefaults: defaults)
        XCTAssertEqual(first.settings, second.settings)
        XCTAssertEqual(observedStore.activeProfileID, first.id)
        let currentID = HealthHistoryCanonicalProfileIdentity.read(userDefaults: defaults)
        XCTAssertEqual(currentID, first.id)
        let scope = HealthHistoryScope(metricIDs: ["steps"], startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400), timeZoneIdentifier: "UTC",
            allAvailable: false, profileID: currentID, rangeSemantics: .ownerDates)
        let store = FakeHealthStore()
        let sut = HealthKitManager(store: store, userDefaults: defaults)
        let entered = expectation(description: "actual provider suspended")
        let finished = expectation(description: "canonical identity gate returned")
        let gate = HistoryTestSuspension(entered: entered)
        store.historySuspension = { await gate.wait() }
        let coordinator = HealthHistoryAssessmentCoordinator()
        let worker = HealthHistoryAssessmentWorker()
        var captures = 0
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            let result = await coordinator.assess(scope: scope, isCurrent: {
                scope.profileID == HealthHistoryCanonicalProfileIdentity.read(userDefaults: defaults)
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
        case "switch": XCTAssertTrue(writer.activate(id: second.id))
        case "delete": XCTAssertTrue(writer.delete(id: first.id))
        case "remove_identity": defaults.removeObject(forKey: "exportProfiles.activeProfileID")
        default: break
        }
        XCTAssertEqual(observedStore.activeProfileID, first.id, "Other stores do not publish through this cached instance")
        let fresh = HealthHistoryCanonicalProfileIdentity.read(userDefaults: defaults)
        XCTAssertEqual(fresh, mutation == "remove_identity" ? nil : mutation == "unchanged" ? first.id : second.id)
        gate.resume()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(captures, mutation == "unchanged" ? 1 : 0)
        XCTAssertEqual(store.historyRequestedIdentifiers, [HKQuantityTypeIdentifier.stepCount.rawValue])
        // Final equality is not an external ABA/history-generation test. Existing
        // coordinator revision controls remain separate and unchanged.
    }
}
