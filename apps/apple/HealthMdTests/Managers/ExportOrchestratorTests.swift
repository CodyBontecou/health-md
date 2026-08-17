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

    func testRollupSourceDates_returnsRequestedDaysWhenEnabled() {
        let settings = makeExportSettings(formats: [.markdown])
        let dates = ExportOrchestrator.rollupSourceDates(
            for: [makeDate(2026, 3, 10), makeDate(2026, 3, 15)],
            settings: settings,
            latestAllowedDate: makeDate(2026, 12, 31)
        )

        XCTAssertEqual(dates, [makeDate(2026, 3, 10), makeDate(2026, 3, 15)])
    }

    func testRollupSourceDates_isEmptyWhenDisabled() {
        let settings = makeExportSettings(formats: [.markdown], generateRangeSummary: false)
        let dates = ExportOrchestrator.rollupSourceDates(
            for: [makeDate(2026, 3, 15)],
            settings: settings,
            latestAllowedDate: makeDate(2026, 12, 31)
        )

        XCTAssertTrue(dates.isEmpty)
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

    func testExportResult_cancelledAfterConfirmedDerivedFileIsPartial() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 2,
            failedDateDetails: [],
            formatsPerDate: 0,
            rollupFileCount: 1,
            wasCancelled: true
        )

        XCTAssertEqual(result.totalFilesWritten, 1)
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertTrue(result.localizedGeneratedFileAndDataDayDescription.contains("1 generated file"))
        XCTAssertTrue(result.localizedGeneratedFileAndDataDayDescription.contains("0"))
        XCTAssertTrue(result.localizedGeneratedFileAndDataDayDescription.contains("2"))
    }

    @MainActor
    func testExportDates_foregroundMapsDeviceLockedHealthKitError() async {
        let store = FakeHealthStore()
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = HealthKitFixtures.deviceLockedError
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/DeviceLockedExportVault")
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
        let settings = makeExportSettings(formats: [.markdown], generateRangeSummary: false)
        settings.includeGranularData = false
        var progress: [(Int, Int, String)] = []

        let result = await ExportOrchestrator.exportDatesBackground(
            [firstDate, secondDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings,
            onProgress: { processed, total, date in
                progress.append((processed, total, date))
            }
        )

        XCTAssertEqual(progress.map(\.0), [0, 1, 2])
        XCTAssertEqual(progress.map(\.1), [2, 2, 2])
        XCTAssertEqual(progress.map(\.2), ["2026-03-15", "2026-03-16", "2026-03-16"])
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.completedDateCount, 2)
        XCTAssertEqual(Set(result.completedDates ?? []), Set([firstDate, secondDate]))
        XCTAssertTrue(result.didCompleteAllRequestedDates)
        XCTAssertEqual(result.failedDateDetails.map(\.reason), [.noHealthData, .noHealthData])
    }

    @MainActor
    func testBackgroundExportUsesFrozenSnapshotAndAsyncEnginePlanner() async {
        let date = HealthKitFixtures.referenceDate
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: date)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let planner = RecordingBackgroundAppleExportPlanner()
        let (vaultManager, _) = makeVaultManager(
            vaultPath: "/tmp/ExportOrchestratorFrozenBackgroundVault",
            planner: planner
        )
        let settings = makeExportSettings(formats: [.json], generateRangeSummary: false)
        settings.includeGranularData = false
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: TimeZone.current.identifier
        )

        let result = await ExportOrchestrator.exportDatesBackground(
            [date],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: snapshot.makeAdvancedExportSettings(),
            frozenSettingsSnapshot: snapshot,
            operationSurface: .localVaultWithoutSideEffects
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(planner.calls.count, 1)
        XCTAssertEqual(planner.calls.first?.snapshot, snapshot)
        XCTAssertEqual(planner.calls.first?.surface, .localVaultWithoutSideEffects)
    }

    @MainActor
    func testPinnedBackgroundRangeCommitsDailyAndRollupFromOnePlan() async {
        UserDefaults.standard.set(
            "shadow",
            forKey: AppleExportEnginePolicyResolver.userDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppleExportEnginePolicyResolver.userDefaultsKey
            )
        }
        let date = HealthKitFixtures.referenceDate
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: date)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager(
            vaultPath: "/tmp/ExportOrchestratorPinnedBackgroundRangeVault"
        )
        let settings = makeExportSettings(formats: [.json], generateRangeSummary: true)
        settings.includeGranularData = false
        let timezone = TimeZone(identifier: "UTC")!
        settings.exportTimeZoneOverride = timezone
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: timezone,
            surface: .localVaultRangeWithoutSideEffects
        )
        XCTAssertNotNil(snapshot.appleExportEnginePin)

        let result = await ExportOrchestrator.exportDatesBackground(
            [date],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: snapshot.makeAdvancedExportSettings(),
            frozenSettingsSnapshot: snapshot,
            operationSurface: .localVaultRangeWithoutSideEffects
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.rollupFileCount, 1)
        XCTAssertTrue(fileSystem.files.keys.contains { $0.contains("/Rollups/") })
        XCTAssertTrue(fileSystem.files.keys.contains { $0.hasSuffix("2026-03-15.json") })
    }

    @MainActor
    func testForegroundRangeReusesOneFrozenAuthoritySnapshotAndTimezone() async {
        let firstDate = HealthKitFixtures.referenceDate
        let secondDate = Calendar.current.date(byAdding: .day, value: 1, to: firstDate)!
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: firstDate)
        HealthKitFixtures.populateAllCategories(store, date: secondDate)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let planner = RecordingBackgroundAppleExportPlanner()
        let (vaultManager, _) = makeVaultManager(
            vaultPath: "/tmp/ExportOrchestratorFrozenForegroundVault",
            planner: planner
        )
        let settings = makeExportSettings(formats: [.json], generateRangeSummary: false)
        settings.includeGranularData = false
        settings.exportTimeZoneOverride = TimeZone(identifier: "America/Los_Angeles")!

        let result = await ExportOrchestrator.exportDates(
            [firstDate, secondDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(planner.calls.count, 2)
        XCTAssertEqual(planner.calls[0].snapshot, planner.calls[1].snapshot)
        XCTAssertTrue(planner.calls[0].snapshot.appleExportEngineAuthorityIsFrozen)
        XCTAssertEqual(
            planner.calls[0].snapshot.calendarTimeZoneIdentifier,
            "America/Los_Angeles"
        )
        XCTAssertEqual(
            Set(planner.calls.map(\.surface)),
            [.localVaultRangeWithoutSideEffects]
        )
    }

    @MainActor
    func testForegroundShadowRangeCommitsDailyAndRollupFromOnePlan() async {
        UserDefaults.standard.set(
            "shadow",
            forKey: AppleExportEnginePolicyResolver.userDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppleExportEnginePolicyResolver.userDefaultsKey
            )
        }
        let date = HealthKitFixtures.referenceDate
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: date)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager(
            vaultPath: "/tmp/ExportOrchestratorShadowRollupVault"
        )
        let settings = makeExportSettings(formats: [.json], generateRangeSummary: true)
        settings.includeGranularData = false
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")!

        let result = await ExportOrchestrator.exportDates(
            [date],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.rollupFileCount, 1)
        XCTAssertTrue(fileSystem.files.keys.contains { $0.contains("/Rollups/") })
        XCTAssertTrue(fileSystem.files.keys.contains { $0.hasSuffix("2026-03-15.json") })
    }

    @MainActor
    func testExportDates_multiDayCompletesAndReportsProgressPerDay() async {
        let baseDate = HealthKitFixtures.referenceDate
        let calendar = Calendar.current
        let dates = [0, 1, 2].compactMap {
            calendar.date(byAdding: .day, value: $0, to: baseDate)
        }
        let store = FakeHealthStore()
        for date in dates {
            HealthKitFixtures.populateAllCategories(store, date: date)
        }
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/ExportOrchestratorMultiDayProgressVault")
        let settings = makeExportSettings(formats: [.json], generateRangeSummary: false)
        settings.includeGranularData = false
        var progress: [(processed: Int, total: Int, label: String)] = []

        let result = await ExportOrchestrator.exportDates(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings,
            onProgress: { processed, total, label in
                progress.append((processed, total, label))
            }
        )

        XCTAssertEqual(result.successCount, 3)
        XCTAssertTrue(result.didCompleteAllRequestedDates)
        // Cooperative yields between days must not change onProgress delivery:
        // one call per day plus the terminal completion call.
        XCTAssertEqual(progress.map(\.0), [0, 1, 2, 3])
        XCTAssertTrue(progress.allSatisfy { $0.total == 3 })
        XCTAssertEqual(progress.dropLast().map(\.2), ["2026-03-15", "2026-03-16", "2026-03-17"])
        XCTAssertEqual(progress.last?.processed, 3)
        XCTAssertEqual(progress.last?.label, "2026-03-17")
    }

    @MainActor
    func testExportDates_midLoopCancellationKeepsPartialResults() async {
        let firstDate = HealthKitFixtures.referenceDate
        let calendar = Calendar.current
        let remainingDates = [1, 2].compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDate)
        }
        let dates = [firstDate] + remainingDates
        let store = FakeHealthStore()
        for date in dates {
            HealthKitFixtures.populateAllCategories(store, date: date)
        }
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/ExportOrchestratorMidLoopCancelVault")
        let settings = makeExportSettings(formats: [.json], generateRangeSummary: false)
        settings.includeGranularData = false
        var progressIndexes: [Int] = []

        var exportTask: Task<ExportOrchestrator.ExportResult, Never>?
        let task = Task { @MainActor in
            await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings,
                onProgress: { processed, _, _ in
                    progressIndexes.append(processed)
                    if processed == 1 {
                        exportTask?.cancel()
                    }
                }
            )
        }
        exportTask = task
        let result = await task.value

        // Cancellation lands either in day 1's write (CancellationError) or at
        // day 2's loop check; both paths must preserve day 0's partial output.
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(progressIndexes, [0, 1], "Progress stops at the cancelled day")
        XCTAssertGreaterThanOrEqual(result.successCount, 1)
        XCTAssertLessThanOrEqual(result.successCount, 2)
        XCTAssertEqual(result.completedDates?.first, firstDate)
        XCTAssertEqual(result.completedDates?.count, result.successCount)
    }

    @MainActor
    func testDerivedOutputRetention_releasesLooseDaysAndStripsRollupArchives() {
        let date = HealthKitFixtures.referenceDate
        let end = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        var healthData = HealthData(date: date)
        healthData.healthKitRecordArchive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-15",
                intervalStart: date,
                intervalEnd: end,
                calendarTimeZoneIdentifier: TimeZone.current.identifier
            )
        )

        let looseSettings = makeExportSettings(formats: [.json], generateRangeSummary: false)
        XCTAssertNil(ExportOrchestrator.retainedHealthDataForDerivedOutputs(
            healthData,
            settings: looseSettings
        ))

        let rollupSettings = makeExportSettings(formats: [.json], generateRangeSummary: true)
        let rollupRecord = ExportOrchestrator.retainedHealthDataForDerivedOutputs(
            healthData,
            settings: rollupSettings
        )
        XCTAssertNil(rollupRecord?.healthKitRecordArchive)
        XCTAssertEqual(rollupRecord?.healthKitRecordCaptureStatus, .notRequested)

        let archiveSettings = makeExportSettings(formats: [.json], generateRangeSummary: false)
        archiveSettings.archiveExportFiles = true
        let archiveRecord = ExportOrchestrator.retainedHealthDataForDerivedOutputs(
            healthData,
            settings: archiveSettings
        )
        XCTAssertNil(archiveRecord, "Archive source days are disk-backed instead of retained in memory")
    }

    @MainActor
    func testDerivedOutputRetention_sanitizesGranularDayBeforeRollupRetention() {
        let date = HealthKitFixtures.referenceDate
        var healthData = HealthData(date: date)
        healthData.activity.steps = 12_500
        healthData.heart.heartRateSamples = [
            TimeSample(timestamp: date, value: 72),
            TimeSample(timestamp: date.addingTimeInterval(60), value: 75),
        ]
        healthData.heart.hrvSamples = [
            TimeSample(timestamp: date, value: 42)
        ]
        healthData.vitals.bloodOxygenSamples = [
            TimeSample(timestamp: date, value: 0.97)
        ]
        healthData.sleep.stages = [
            SleepStageSample(
                stage: "deep",
                startDate: date,
                endDate: date.addingTimeInterval(5_400)
            )
        ]

        let rollupSettings = makeExportSettings(formats: [.json])
        let retained = ExportOrchestrator.retainedHealthDataForDerivedOutputs(
            healthData,
            settings: rollupSettings
        )

        // Roll-ups only need daily aggregates; granular time-series must be
        // sanitized before the day is retained for the whole-run window.
        XCTAssertEqual(
            retained?.activity.steps,
            12_500,
            "Aggregate metrics must survive retention for roll-up summaries"
        )
        XCTAssertTrue(retained?.heart.heartRateSamples.isEmpty == true)
        XCTAssertTrue(retained?.heart.hrvSamples.isEmpty == true)
        XCTAssertTrue(retained?.vitals.bloodOxygenSamples.isEmpty == true)
        XCTAssertTrue(retained?.sleep.stages.isEmpty == true)
        XCTAssertNil(retained?.healthKitRecordArchive)
        XCTAssertEqual(retained?.healthKitRecordCaptureStatus, .notRequested)
    }

    @MainActor
    func testExportDates_writesDataDictionaryOncePerRun() async {
        let firstDate = HealthKitFixtures.referenceDate
        let secondDate = Calendar.current.date(byAdding: .day, value: 1, to: firstDate)!
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: firstDate)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager(vaultPath: "/tmp/DictionaryOnceVault")
        let settings = makeExportSettings(formats: [.markdown], generateRangeSummary: true)
        settings.includeGranularData = false

        let result = await ExportOrchestrator.exportDates(
            [firstDate, secondDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(
            fileSystem.writeCounts["/tmp/DictionaryOnceVault/Health/_healthmd_data_dictionary.json"],
            1
        )
    }

    @MainActor
    func testExportDates_archiveModePacksRollupsIntoZip() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOrchestratorArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
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
        let settings = makeExportSettings(formats: [.markdown, .json], generateRangeSummary: true)
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
        XCTAssertEqual(
            vaultManager.lastExportPresentationTarget,
            ExportPresentationTarget(
                fileURL: archiveURL,
                securityScopedRootURL: vaultURL
            )
        )
        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertNotNil(archiveData.range(of: Data("2026-03-15.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Range/2026-03-15_to_2026-03-15.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Range/2026-03-15_to_2026-03-15.json".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Health/Rollups/Range/2026-03-15_to_2026-03-15.md").path
        ))
    }

    @MainActor
    func testExportDates_archiveCancellationIsTerminalAndNotAPartialFailure() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOrchestratorArchiveCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
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
        let settings = makeExportSettings(formats: [.json], generateRangeSummary: false)
        settings.archiveExportFiles = true

        var exportTask: Task<ExportOrchestrator.ExportResult, Never>?
        vaultManager.archiveEntryWillAppendForTesting = {
            exportTask?.cancel()
        }
        let task = Task { @MainActor in
            await ExportOrchestrator.exportDates(
                [HealthKitFixtures.referenceDate],
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings
            )
        }
        exportTask = task
        let result = await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.archiveCount, 0)
        XCTAssertTrue(result.completedDates?.isEmpty == true)
        XCTAssertFalse(result.partialFailures.contains { $0.dataType == "ZIP archive" })
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Health/Health.md Export 2026-03-15.zip").path
        ))
        XCTAssertNil(vaultManager.lastExportPresentationTarget)
    }

    @MainActor
    func testExportDates_dailyNotesOnlyUpdatesNoteWithoutAdditionalFiles() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOrchestratorDailyNotesOnly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
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
        vaultManager.setVaultFolder(vaultURL)
        Self.retainedManagers.append(vaultManager)

        let settings = makeExportSettings(formats: [], generateRangeSummary: true)
        settings.archiveExportFiles = true
        settings.summaryOnlyExport = true
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.formatsPerDate, 0)
        XCTAssertEqual(result.totalFilesWritten, 0)
        XCTAssertEqual(result.dailyNoteUpdateCount, 1)
        XCTAssertEqual(result.dailyNoteSkipCount, 0)
        XCTAssertTrue(result.isFullSuccess)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vaultURL.path), ["Daily"])
    }

    @MainActor
    func testExportDates_dailyNotesOnlyMissingNoteIsTerminalSkip() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOrchestratorDailyNotesOnlySkip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
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
        vaultManager.setVaultFolder(vaultURL)
        Self.retainedManagers.append(vaultManager)

        let settings = makeExportSettings(formats: [], generateRangeSummary: false)
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.createIfMissing = false

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.dailyNoteSkipCount, 1)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .noHealthData)
        XCTAssertEqual(result.completedDates, [HealthKitFixtures.referenceDate])
        XCTAssertTrue(result.didCompleteAllRequestedDates)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: vaultURL.path).isEmpty)
    }

    @MainActor
    func testExportDates_summaryOnlyWritesRollupsWithoutDailyFiles() async throws {
        UserDefaults.standard.set(
            "shadow",
            forKey: AppleExportEnginePolicyResolver.userDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppleExportEnginePolicyResolver.userDefaultsKey
            )
        }
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager(vaultPath: "/tmp/SummaryOnlyVault")
        let settings = makeExportSettings(formats: [.markdown], generateRangeSummary: true)
        settings.summaryOnlyExport = true
        settings.includeGranularData = false
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")!
        var progress: [(processed: Int, total: Int, date: String)] = []

        let result = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings,
            onProgress: { processed, total, date in
                progress.append((processed, total, date))
            }
        )

        XCTAssertEqual(progress.count, 2)
        XCTAssertEqual(progress.first?.processed, 1)
        XCTAssertEqual(progress.last?.processed, 2)
        XCTAssertEqual(progress.last?.date, "summary files")
        XCTAssertTrue(progress.allSatisfy { $0.total == 2 })
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.formatsPerDate, 0)
        XCTAssertEqual(result.rollupFileCount, 1)
        XCTAssertEqual(result.totalFilesWritten, 1)
        XCTAssertTrue(result.isFullSuccess)
        XCTAssertNil(fileSystem.files.first { path, _ in
            path.hasSuffix("/Health/2026-03-15.md")
        }, "Summary-only mode must not write daily aggregate files")

        let rangeSummary = try XCTUnwrap(
            fileSystem.files.first { path, _ in
                path.hasSuffix("/Health/Rollups/Range/2026-03-15_to_2026-03-15.md")
            }?.value,
            "Expected range summary"
        )
        XCTAssertTrue(rangeSummary.contains("schema: healthmd.rollup_summary"))
        XCTAssertTrue(rangeSummary.contains("rollup_period: range"))
        XCTAssertNotNil(fileSystem.files.first { path, _ in
            path.hasSuffix("/Health/_healthmd_data_dictionary.json")
        }, "Summary-only roll-up exports should still write the data dictionary")
        XCTAssertEqual(
            vaultManager.lastExportPresentationTarget,
            ExportPresentationTarget(
                fileURL: URL(fileURLWithPath: "/tmp/SummaryOnlyVault/Health/Rollups/Range/2026-03-15_to_2026-03-15.md"),
                securityScopedRootURL: URL(fileURLWithPath: "/tmp/SummaryOnlyVault")
            )
        )
    }

    @MainActor
    func testExportDates_summaryOnlyNoDataCompletesTerminalDates() async {
        UserDefaults.standard.set(
            "shadow",
            forKey: AppleExportEnginePolicyResolver.userDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppleExportEnginePolicyResolver.userDefaultsKey
            )
        }
        let dates = [
            makeDate(2026, 3, 15),
            makeDate(2026, 3, 16)
        ]
        let store = FakeHealthStore()
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/SummaryOnlyNoDataVault")
        let settings = makeExportSettings(formats: [.markdown], generateRangeSummary: true)
        settings.summaryOnlyExport = true
        settings.includeGranularData = false
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")!

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
    func testExportDates_legacySummaryOnlyProgressIncludesFinalization() async {
        UserDefaults.standard.set(
            "legacy",
            forKey: AppleExportEnginePolicyResolver.userDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppleExportEnginePolicyResolver.userDefaultsKey
            )
        }

        let store = FakeHealthStore()
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, _) = makeVaultManager(vaultPath: "/tmp/LegacySummaryProgressVault")
        let settings = makeExportSettings(formats: [.markdown], generateRangeSummary: true)
        settings.summaryOnlyExport = true
        settings.includeGranularData = false
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")!
        var progress: [(processed: Int, total: Int, label: String)] = []

        _ = await ExportOrchestrator.exportDates(
            [HealthKitFixtures.referenceDate],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings,
            onProgress: { processed, total, label in
                progress.append((processed, total, label))
            }
        )

        XCTAssertEqual(progress.count, 2)
        XCTAssertTrue(progress.allSatisfy { $0.total == 2 })
        XCTAssertEqual(progress.last?.processed, 2)
        XCTAssertEqual(progress.last?.label, "summary files")
    }

    @MainActor
    func testExportDates_summaryOnlyArchivePacksRollupsWithoutDailyFiles() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOrchestratorSummaryOnlyArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
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
        let settings = makeExportSettings(formats: [.markdown, .json], generateRangeSummary: true)
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
        // The range summary filename embeds the daily date, so assert absence of
        // daily entries via the counts above (formatsPerDate 0, rollupFileCount 0)
        // and presence of the range entries only.
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Range/2026-03-15_to_2026-03-15.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Range/2026-03-15_to_2026-03-15.json".utf8)))
    }

    @MainActor
    func testExportDates_partialHealthKitFailure_writesSuccessfulCategoriesAndReturnsWarning() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store, date: HealthKitFixtures.referenceDate)
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = HealthKitFixtures.genericQueryError
        let healthKitManager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        let (vaultManager, fileSystem) = makeVaultManager()
        let settings = makeExportSettings(formats: [.markdown], generateRangeSummary: true)

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

        let rangeSummary = try XCTUnwrap(
            fileSystem.files.first { path, _ in
                path.hasSuffix("/Health/Rollups/Range/2026-03-15_to_2026-03-15.md")
            }?.value,
            "Expected range summary for the successful daily export"
        )
        XCTAssertTrue(rangeSummary.contains("schema: healthmd.rollup_summary"))
        XCTAssertTrue(rangeSummary.contains("days_counted: 1"))
        XCTAssertTrue(rangeSummary.contains("| Steps | `steps` | 12,500 | steps | 1/1 | sum |"))
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
    private func makeVaultManager(
        vaultPath: String = "/tmp/PartialFailureVault",
        planner: (any AppleLooseDailyExportPlanning)? = nil
    ) -> (VaultManager, FakeFileSystem) {
        let defaults = FakeUserDefaults()
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        defaults.storage["obsidianVaultPath"] = vaultPath
        defaults.storage["obsidianVaultName"] = URL(fileURLWithPath: vaultPath).lastPathComponent

        let fileSystem = FakeFileSystem()
        let bookmarkResolver = FakeBookmarkResolver()
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: vaultPath)

        let manager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: planner
        )
        manager.healthSubfolder = "Health"
        Self.retainedManagers.append(manager)

        return (manager, fileSystem)
    }

    @MainActor
    private func makeExportSettings(
        formats: Set<ExportFormat>,
        generateRangeSummary: Bool = true
    ) -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(userDefaults: makeIsolatedDefaults())
        settings.exportFormats = formats
        settings.generateRangeSummary = generateRangeSummary
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

@MainActor
private final class RecordingBackgroundAppleExportPlanner: AppleLooseDailyExportPlanning {
    struct Call {
        let snapshot: ExportSettingsSnapshot
        let surface: AppleExportOperationSurface
    }

    private(set) var calls: [Call] = []

    func plan(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution {
        calls.append(Call(snapshot: settingsSnapshot, surface: surface))
        return .legacy
    }
}
