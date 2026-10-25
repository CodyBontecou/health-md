import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class HealthHistoryTabletSelectionTests: XCTestCase {
    func testActualVaultChangeDuringProviderAwaitRejectsCapture() async throws {
        try await checkSelection(changeDestination: true)
    }

    func testCurrentActualVaultAndSettingsDuringProviderAwaitPermitFrozenCapture() async throws {
        try await checkSelection(changeDestination: false)
    }

    private func checkSelection(changeDestination: Bool) async throws {
        let vault = VaultManager(defaults: FakeUserDefaults(), fileSystem: FakeFileSystem(),
                                 bookmarkResolver: FakeBookmarkResolver(), identityProbe: FakeVaultFolderIdentityProbe())
        XCTAssertTrue(vault.setVaultFolder(URL(fileURLWithPath: "/tmp/history-tablet-destination-a")))
        let settings = ExportSettingsSnapshot.from(AdvancedExportSettings(), appleExportEngineAuthorityIsFrozen: false).makeAdvancedExportSettings()
        settings.metricSelection.deselectAll()
        settings.metricSelection.toggleMetric("steps")
        settings.exportTimeZoneOverride = TimeZone(identifier: "America/Los_Angeles")
        let requestScope = HealthHistoryScope(metricIDs: ["steps"], startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400), timeZoneIdentifier: "America/Los_Angeles",
            allAvailable: false, profileID: UUID(), rangeSemantics: .ownerDates)
        func currentSelection() -> HealthHistoryExecutionSelection {
            HealthHistoryExecutionSelection(scope: requestScope,
                settings: ExportSettingsSnapshot.from(settings, appleExportEngineAuthorityIsFrozen: false),
                target: .localIPhoneFolder, preset: .custom, localDestinationURL: vault.vaultURL)
        }
        let selected = currentSelection()
        let store = FakeHealthStore()
        let sut = HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "TabletHistoryManagerTests")!)
        let entered = expectation(description: "actual history provider suspended")
        let finished = expectation(description: "selection gate finished")
        let gate = HistoryTestSuspension(entered: entered)
        store.historySuspension = { await gate.wait() }
        let coordinator = HealthHistoryAssessmentCoordinator()
        let worker = HealthHistoryAssessmentWorker()
        var captures = 0
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            let result = await coordinator.assess(scope: selected.scope, isCurrent: {
                selected == currentSelection()
            }, operation: {
                await worker.assess(notCompleted: sut.historyAssessmentNotCompleted(scope: selected.scope)) {
                    await sut.assessHistoryAccess(scope: selected.scope)
                }
            })
            if result != nil {
                captures += 1
                let frozen = selected.makeCaptureSettings()
                XCTAssertEqual(frozen.metricSelection.enabledMetrics, ["steps"])
                XCTAssertEqual(frozen.exportTimeZoneOverride?.identifier, requestScope.timeZoneIdentifier)
                XCTAssertEqual(selected.scope.startDate, requestScope.startDate)
                XCTAssertEqual(selected.scope.endDate, requestScope.endDate)
                XCTAssertEqual(selected.scope.profileID, requestScope.profileID)
                XCTAssertFalse(selected.settings.appleExportEngineAuthorityIsFrozen)
            }
        }
        defer { gate.resume(); task.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        if changeDestination {
            XCTAssertTrue(vault.setVaultFolder(URL(fileURLWithPath: "/tmp/history-tablet-destination-b")))
        }
        gate.resume()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(captures, changeDestination ? 0 : 1)
        XCTAssertEqual(store.historyRequestedIdentifiers, [HKQuantityTypeIdentifier.stepCount.rawValue])
    }
}
