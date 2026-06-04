//
//  ExportOrchestratorTests.swift
//  HealthMdTests
//
//  TDD tests for ExportOrchestrator date range generation and ExportResult
//  computed properties.
//

import XCTest
import HealthKit
@testable import HealthMd
import ExportKit

final class ExportOrchestratorTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: VaultManager and AdvancedExportSettings are
    // ObservableObjects with nested observable properties. Static retention avoids
    // macOS 26 / Swift 6 deinit crash. See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [VaultManager] = []
    private static var retainedSettings: [AdvancedExportSettings] = []

    // MARK: - dateRange

    func testDateRange_singleDay() {
        let date = makeDate(2026, 3, 15)
        let range = ExportOrchestrator.dateRange(from: date, to: date)
        XCTAssertEqual(range.count, 1)
    }

    func testDateRange_threeDays() {
        let start = makeDate(2026, 3, 15)
        let end = makeDate(2026, 3, 17)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertEqual(range.count, 3)
    }

    func testDateRange_crossesMonthBoundary() {
        let start = makeDate(2026, 3, 30)
        let end = makeDate(2026, 4, 2)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertEqual(range.count, 4) // Mar 30, 31, Apr 1, 2
    }

    func testDateRange_endBeforeStart_returnsEmpty() {
        let start = makeDate(2026, 3, 15)
        let end = makeDate(2026, 3, 14)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertTrue(range.isEmpty)
    }

    func testDateRange_datesAreStartOfDay() {
        // Even if we pass mid-day dates, the range should normalize to start of day
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 15
        comps.hour = 14; comps.minute = 30
        let midDay = calendar.date(from: comps)!

        let range = ExportOrchestrator.dateRange(from: midDay, to: midDay)
        XCTAssertEqual(range.count, 1)
        let resultComps = calendar.dateComponents([.hour, .minute], from: range[0])
        XCTAssertEqual(resultComps.hour, 0)
        XCTAssertEqual(resultComps.minute, 0)
    }

    func testDateRange_fullWeek() {
        let start = makeDate(2026, 3, 1)
        let end = makeDate(2026, 3, 7)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertEqual(range.count, 7)
    }

    // MARK: - ExportResult computed properties

    func testExportResult_fullSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 5,
            totalCount: 5,
            failedDateDetails: []
        )
        XCTAssertTrue(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertNil(result.primaryFailureReason)
    }

    func testExportResult_partialSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 3,
            totalCount: 5,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .noHealthData)
            ]
        )
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .noHealthData)
    }

    func testExportResult_partialMetricFailures_warnWithoutFailedDates() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [],
            partialFailures: [
                ExportPartialFailure(
                    date: makeDate(2026, 3, 15),
                    dataType: "workouts",
                    dateRangeDescription: "2026-03-15 00:00:00 - 2026-03-15 23:59:59",
                    errorDescription: "HealthKit query failed"
                )
            ]
        )

        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertTrue(result.partialFailureSummary.contains("workouts"))
        XCTAssertTrue(result.partialFailureSummary.contains("2026-03-15"))
    }

    func testExportResult_totalFailure() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 5,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .accessDenied)
            ]
        )
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .accessDenied)
    }

    @MainActor
    func testExportDates_foregroundMapsDeviceLockedHealthKitError() async {
        let store = FakeHealthStore()
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = HealthKitFixtures.deviceLockedError
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/DeviceLockedVault")
        let settings = makeExportSettings(formats: [.markdown])

        let result = await ExportOrchestrator.exportDates(
            [makeDate(2026, 3, 15)],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .deviceLocked)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .deviceLocked)
    }

    @MainActor
    func testExportDates_partialHealthKitFailure_writesSuccessfulCategoriesAndReturnsWarning() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = HealthKitFixtures.genericQueryError
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager()
        let settings = makeExportSettings(formats: [.markdown])

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.totalCount, 1)
        XCTAssertTrue(result.failedDateDetails.isEmpty)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFullSuccess)

        let failure = try XCTUnwrap(result.partialFailures.first)
        XCTAssertEqual(failure.dataType, "sleep")
        XCTAssertTrue(failure.summary.contains("Query failed"))
        XCTAssertTrue(result.partialFailureSummary.contains("Warning"))
        XCTAssertTrue(result.partialFailureSummary.contains("sleep"))

        let output = try XCTUnwrap(fileSystem.files.values.first)
        XCTAssertTrue(output.contains("Steps"), "Activity data should still export after a sleep fetch failure")
        XCTAssertTrue(output.contains("12,500"), "Successful activity values should be written to the export file")
        XCTAssertTrue(output.contains("Heart"), "Heart data should still export after a sleep fetch failure")
        XCTAssertTrue(output.contains("Average HR"), "Successful heart values should be written to the export file")
    }

    @MainActor
    func testExportDates_noVaultSelectedMapsGenericPreflightToExistingFailureReason() async {
        let store = FakeHealthStore()
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let vaultManager = VaultManager(defaults: FakeUserDefaults(), fileSystem: FakeFileSystem(), bookmarkResolver: FakeBookmarkResolver())
        let settings = makeExportSettings(formats: [.markdown])
        Self.retainedManagers.append(vaultManager)

        let result = await ExportOrchestrator.exportDates(
            [makeDate(2026, 3, 15)],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .noVaultSelected)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .noVaultSelected)
    }

    @MainActor
    func testExportDates_noFormatsSelectedPreservesUnknownFailureWithDetails() async {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager()
        let settings = makeExportSettings(formats: [])

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .unknown)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .unknown)
        XCTAssertEqual(result.failedDateDetails.first?.errorDetails, "At least one export format must be selected")
        XCTAssertEqual(result.formatsPerDate, 0)
    }

    @MainActor
    func testExportDates_noHealthDataMapsGenericNoDataToExistingFailureReason() async {
        let store = FakeHealthStore()
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager()
        let settings = makeExportSettings(formats: [.markdown])

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .noHealthData)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .noHealthData)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testExportResult_cancelled_withSomeSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 2,
            totalCount: 5,
            failedDateDetails: [],
            wasCancelled: true
        )
        XCTAssertFalse(result.isFullSuccess) // cancelled, so not full success
        XCTAssertTrue(result.isPartialSuccess) // has some success + cancelled
    }

    func testExportResult_cancelled_noSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 5,
            failedDateDetails: [],
            wasCancelled: true
        )
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertTrue(result.isFailure)
    }

    func testExportResult_zeroTotal() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 0,
            failedDateDetails: []
        )
        XCTAssertFalse(result.isFullSuccess) // totalCount must be > 0
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure) // totalCount must be > 0
    }

    // MARK: - Helpers

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)!
    }

    @MainActor
    private func makeVaultManager(vaultPath: String = "/tmp/PartialFailureVault") -> (VaultManager, FakeFileSystem) {
        let defaults = FakeUserDefaults()
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)

        let fileSystem = FakeFileSystem()
        let bookmarkResolver = FakeBookmarkResolver()
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: vaultPath)

        let manager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver
        )
        manager.healthSubfolder = "Health"
        Self.retainedManagers.append(manager)

        return (manager, fileSystem)
    }

    @MainActor
    private func makeExportSettings(formats: Set<ExportFormat>) -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(userDefaults: makeIsolatedDefaults())
        settings.exportFormats = formats
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ExportOrchestratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
