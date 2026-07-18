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

    func testRollupSourceDates_expandsToFullWeeklyWindow() {
        let selectedDate = makeDate(2026, 3, 15)
        let dates = ExportOrchestrator.rollupSourceDates(
            for: [selectedDate],
            periods: [.weekly],
            latestAllowedDate: makeDate(2026, 12, 31)
        )

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.first, makeDate(2026, 3, 9))
        XCTAssertEqual(dates.last, makeDate(2026, 3, 15))
    }

    func testRollupSourceDates_expandsToFullMonthlyWindow() {
        let selectedDate = makeDate(2026, 3, 15)
        let dates = ExportOrchestrator.rollupSourceDates(
            for: [selectedDate],
            periods: [.monthly],
            latestAllowedDate: makeDate(2026, 12, 31)
        )

        XCTAssertEqual(dates.count, 31)
        XCTAssertEqual(dates.first, makeDate(2026, 3, 1))
        XCTAssertEqual(dates.last, makeDate(2026, 3, 31))
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

    func testExportResult_reportedFailureMetadataCanCompleteRequestWithoutFullSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 2,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .noHealthData)
            ],
            completedDateCount: 2
        )

        XCTAssertTrue(result.didCompleteAllRequestedDates)
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
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
        let vaultManager = VaultManager()
        let settings = AdvancedExportSettings(userDefaults: makeIsolatedDefaults())
        Self.retainedManagers.append(vaultManager)
        Self.retainedSettings.append(settings)

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
    func testExportDatesBackground_marksNoDataDatesComplete() async {
        let firstDate = HealthKitFixtures.referenceDate
        let secondDate = Calendar.current.date(byAdding: .day, value: 1, to: firstDate)!
        let store = FakeHealthStore()
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/ExportOrchestratorCompletionVault")
        let settings = makeExportSettings(formats: [.markdown], rollupPeriods: [])
        settings.includeGranularData = false

        let result = await ExportOrchestrator.exportDatesBackground(
            [firstDate, secondDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.completedDateCount, 2)
        XCTAssertEqual(Set(result.completedDates ?? []), Set([firstDate, secondDate]))
        XCTAssertTrue(result.didCompleteAllRequestedDates)
        XCTAssertEqual(result.failedDateDetails.map(\.reason), [.noHealthData, .noHealthData])
    }

    @MainActor
    func testExportDates_archiveModePacksRollupsIntoZip() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOrchestratorArchiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let bookmarkResolver = FakeBookmarkResolver()
        bookmarkResolver.accessGranted = true
        let vaultManager = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        vaultManager.healthSubfolder = "Health"
        vaultManager.setVaultFolder(vaultURL)
        Self.retainedManagers.append(vaultManager)
        let settings = makeExportSettings(formats: [.markdown, .json], rollupPeriods: [.weekly])
        settings.archiveExportFiles = true

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.rollupFileCount, 0)
        XCTAssertEqual(result.archiveCount, 1)
        XCTAssertEqual(result.totalFilesWritten, 1)
        let archiveURL = vaultURL.appendingPathComponent("Health/Health.md Export 2026-03-15.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertNotNil(archiveData.range(of: Data("2026-03-15.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Weekly/2026-W11.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Weekly/2026-W11.json".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Health/Rollups/Weekly/2026-W11.md").path
        ))
    }

    @MainActor
    func testExportDates_summaryOnlyWritesRollupsWithoutDailyFiles() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager(vaultPath: "/tmp/SummaryOnlyVault")
        let settings = makeExportSettings(formats: [.markdown], rollupPeriods: [.monthly])
        settings.summaryOnlyExport = true

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.formatsPerDate, 0)
        XCTAssertEqual(result.rollupFileCount, 1)
        XCTAssertEqual(result.totalFilesWritten, 1)
        XCTAssertTrue(result.isFullSuccess)
        XCTAssertNil(fileSystem.files.first { path, _ in
            path.hasSuffix("/Health/2026-03-15.md")
        }, "Summary-only mode must not write daily aggregate files")

        let monthlyRollup = try XCTUnwrap(
            fileSystem.files.first { path, _ in
                path.hasSuffix("/Health/Rollups/Monthly/2026-03.md")
            }?.value,
            "Expected monthly roll-up summary"
        )
        XCTAssertTrue(monthlyRollup.contains("schema: healthmd.rollup_summary"))
        XCTAssertTrue(monthlyRollup.contains("rollup_period: monthly"))
        XCTAssertNotNil(fileSystem.files.first { path, _ in
            path.hasSuffix("/Health/_healthmd_data_dictionary.json")
        }, "Summary-only roll-up exports should still write the data dictionary")
    }

    @MainActor
    func testExportDates_summaryOnlyNoDataCompletesTerminalDates() async {
        let dates = [
            makeDate(2026, 3, 15),
            makeDate(2026, 3, 16)
        ]
        let store = FakeHealthStore()
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/SummaryOnlyNoDataVault")
        let settings = makeExportSettings(formats: [.markdown], rollupPeriods: [.monthly])
        settings.summaryOnlyExport = true
        settings.includeGranularData = false

        let result = await ExportOrchestrator.exportDates(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.map(\.reason), [.noHealthData])
        XCTAssertEqual(Set(result.completedDates ?? []), Set(dates))
        XCTAssertTrue(result.didCompleteAllRequestedDates)
    }

    @MainActor
    func testExportDates_summaryOnlyArchivePacksRollupsWithoutDailyFiles() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOrchestratorSummaryOnlyArchiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let bookmarkResolver = FakeBookmarkResolver()
        bookmarkResolver.accessGranted = true
        let vaultManager = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        vaultManager.healthSubfolder = "Health"
        vaultManager.setVaultFolder(vaultURL)
        Self.retainedManagers.append(vaultManager)
        let settings = makeExportSettings(formats: [.markdown, .json], rollupPeriods: [.weekly])
        settings.summaryOnlyExport = true
        settings.archiveExportFiles = true

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.formatsPerDate, 0)
        XCTAssertEqual(result.rollupFileCount, 0)
        XCTAssertEqual(result.archiveCount, 1)
        XCTAssertEqual(result.totalFilesWritten, 1)
        let archiveURL = vaultURL.appendingPathComponent("Health/Health.md Export 2026-03-15.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertNil(archiveData.range(of: Data("2026-03-15.md".utf8)))
        XCTAssertNil(archiveData.range(of: Data("2026-03-15.json".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Weekly/2026-W11.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Weekly/2026-W11.json".utf8)))
    }

    @MainActor
    func testExportDates_partialHealthKitFailure_writesSuccessfulCategoriesAndReturnsWarning() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = HealthKitFixtures.genericQueryError
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager()
        let settings = makeExportSettings(formats: [.markdown], rollupPeriods: [.weekly])

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.rollupFileCount, 1)
        XCTAssertEqual(result.totalFilesWritten, 2)
        XCTAssertTrue(result.failedDateDetails.isEmpty)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFullSuccess)

        let failure = try XCTUnwrap(result.partialFailures.first)
        XCTAssertEqual(failure.dataType, "sleep")
        XCTAssertTrue(failure.summary.contains("Query failed"))
        XCTAssertTrue(result.partialFailureSummary.contains("Warning"))
        XCTAssertTrue(result.partialFailureSummary.contains("sleep"))

        let aggregateOutput = try XCTUnwrap(
            fileSystem.files.first { path, _ in
                path.hasSuffix("/Health/2026-03-15.md")
            }?.value,
            "Expected the aggregate Markdown export"
        )
        XCTAssertTrue(aggregateOutput.contains("Steps"), "Activity data should still export after a sleep fetch failure")
        XCTAssertTrue(aggregateOutput.contains("12,500"), "Successful activity values should be written to the export file")
        XCTAssertTrue(aggregateOutput.contains("Heart"), "Heart data should still export after a sleep fetch failure")
        XCTAssertTrue(aggregateOutput.contains("Average HR"), "Successful heart values should be written to the export file")

        let weeklyRollup = try XCTUnwrap(
            fileSystem.files.first { path, _ in
                path.hasSuffix("/Health/Rollups/Weekly/2026-W11.md")
            }?.value,
            "Expected weekly roll-up summary for the successful daily export"
        )
        XCTAssertTrue(weeklyRollup.contains("schema: healthmd.rollup_summary"))
        XCTAssertTrue(weeklyRollup.contains("days_counted: 7"))
        XCTAssertTrue(weeklyRollup.contains("| Steps | `steps` | 87,500 | steps | 7/7 | sum |"))
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
    private func makeExportSettings(
        formats: Set<ExportFormat>,
        rollupPeriods: Set<HealthRollupPeriod> = [.weekly, .monthly, .yearly]
    ) -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(userDefaults: makeIsolatedDefaults())
        settings.exportFormats = formats
        settings.generateWeeklyRollups = rollupPeriods.contains(.weekly)
        settings.generateMonthlyRollups = rollupPeriods.contains(.monthly)
        settings.generateYearlyRollups = rollupPeriods.contains(.yearly)
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
