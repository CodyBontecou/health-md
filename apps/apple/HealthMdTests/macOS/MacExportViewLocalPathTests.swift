#if os(macOS)
import XCTest
@testable import HealthMd

@MainActor
final class MacExportViewLocalPathTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: VaultManager owns nested ObservableObjects;
    // process-lifetime retention avoids the known macOS 26 / Swift 6 deinit crash.
    private static var retainedManagers: [VaultManager] = []
    private var retainedSettings: [AdvancedExportSettings] = []

    override func tearDown() {
        retainedSettings.removeAll()
        super.tearDown()
    }

    func testManualRangeOverLimitDisablesSummaryOnlyButKeepsDailyFormatsAndWarning() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = try date(2000, 1, 1, calendar: calendar)
        let end = try date(2027, 5, 19, calendar: calendar)
        let dates = ExportOrchestrator.dateRange(from: start, to: end, calendar: calendar)
        XCTAssertEqual(dates.count, 10_001)

        let settings = makeSettings()
        settings.generateRangeSummary = true
        settings.summaryOnlyExport = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            calendarTimeZoneIdentifier: timeZone.identifier
        )

        let availability = ExportOrchestrator.settingsByDisablingUnavailableRangeSummary(
            snapshot,
            requestedDates: dates,
            calendarTimeZone: timeZone
        )
        let effectiveSettings = availability.snapshot.makeAdvancedExportSettings()

        XCTAssertFalse(effectiveSettings.generateRangeSummary)
        XCTAssertFalse(effectiveSettings.summaryOnlyModeEnabled)
        XCTAssertEqual(effectiveSettings.exportFormats, [.json])
        XCTAssertEqual(availability.warning?.dataType, "Range Summary")
        XCTAssertEqual(
            availability.warning?.errorDescription,
            HealthRollupRangeRequest.dayLimitUnavailableMessage
        )
    }

    func testManualArchiveCommitContainsConfiguredDailyV8AndRangeV9Artifacts() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacManualArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeVaultManager(vaultURL: vaultURL)
        let settings = makeSettings()
        settings.exportFormats = [.markdown, .json]
        settings.archiveExportFiles = true
        settings.generateRangeSummary = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, calendar: utcCalendar())
        let record = record(on: selectedDate)
        let archiveURL = vaultURL.appendingPathComponent("Health.md Export 2026-03-15.zip")
        try Data("stale archive".utf8).write(to: archiveURL)

        let output = try await MacManualRangeDerivedOutputCommitter.commit(
            requestedDates: [selectedDate],
            capturedHealthData: [record],
            rollupHealthData: [record],
            settings: settings,
            timeZone: settings.exportTimeZoneOverride!,
            fetchHealthData: { _ in record },
            vaultManager: manager
        )

        XCTAssertEqual(output, .init(rollupFileCount: 0, archiveCount: 1))
        let listing = try unzip(arguments: ["-Z1", archiveURL.path])
        XCTAssertTrue(listing.contains("2026-03-15.md\n"), listing)
        XCTAssertTrue(listing.contains("2026-03-15.json\n"), listing)
        let rangeJSONPath = "Rollups/Range/2026-03-15_to_2026-03-15.json"
        XCTAssertTrue(listing.contains("\(rangeJSONPath)\n"), listing)
        let dailyJSON = try unzip(arguments: ["-p", archiveURL.path, "2026-03-15.json"])
        let rangeJSON = try unzip(arguments: ["-p", archiveURL.path, rangeJSONPath])
        XCTAssertTrue(dailyJSON.contains("\"schema_version\" : 8") || dailyJSON.contains("\"schema_version\":8"), dailyJSON)
        XCTAssertTrue(rangeJSON.contains("\"schema_version\" : 9") || rangeJSON.contains("\"schema_version\":9"), rangeJSON)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("2026-03-15.json").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent(rangeJSONPath).path
        ))
    }

    func testManualArchiveRequiresEveryImmutableOriginalDayAndPreservesExistingZip() async throws {
        let vaultURL = try temporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeVaultManager(vaultURL: vaultURL)
        let settings = makeSettings()
        settings.archiveExportFiles = true
        settings.generateRangeSummary = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let firstDate = try date(2026, 3, 14, calendar: utcCalendar())
        let finalDate = try date(2026, 3, 15, calendar: utcCalendar())
        let finalRecord = record(on: finalDate)
        let archiveURL = vaultURL.appendingPathComponent("Health.md Export 2026-03-14_to_2026-03-15.zip")
        let existingArchive = Data("existing archive remains authoritative".utf8)
        try existingArchive.write(to: archiveURL)

        do {
            _ = try await MacManualRangeDerivedOutputCommitter.commit(
                requestedDates: [firstDate, finalDate],
                capturedHealthData: [finalRecord],
                rollupHealthData: [finalRecord],
                settings: settings,
                timeZone: settings.exportTimeZoneOverride!,
                fetchHealthData: { _ in nil },
                vaultManager: manager
            )
            XCTFail("An incomplete immutable range must not report archive success")
        } catch {
            XCTAssertEqual(try Data(contentsOf: archiveURL), existingArchive)
        }
        XCTAssertNil(manager.lastExportPresentationTarget)
    }

    func testSummaryOnlyCancellationAtDerivedBoundaryWritesNoRollup() async throws {
        let vaultURL = try temporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeVaultManager(vaultURL: vaultURL)
        let settings = makeSettings()
        settings.generateRangeSummary = true
        settings.summaryOnlyExport = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, calendar: utcCalendar())
        let record = record(on: selectedDate)

        let task = Task { @MainActor in
            try await MacManualRangeDerivedOutputCommitter.commit(
                requestedDates: [selectedDate],
                capturedHealthData: [record],
                rollupHealthData: [record],
                settings: settings,
                timeZone: settings.exportTimeZoneOverride!,
                fetchHealthData: { _ in record },
                vaultManager: manager
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation at the summary-only commit boundary")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Rollups").path
        ))
        XCTAssertNil(manager.lastExportPresentationTarget)
    }

    func testFinalNormalDayCancellationAtDerivedBoundaryWritesNoRollup() async throws {
        let vaultURL = try temporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeVaultManager(vaultURL: vaultURL)
        let settings = makeSettings()
        settings.generateRangeSummary = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, calendar: utcCalendar())
        let record = record(on: selectedDate)

        let task = Task { @MainActor in
            try await MacManualRangeDerivedOutputCommitter.commit(
                requestedDates: [selectedDate],
                capturedHealthData: [record],
                rollupHealthData: [record],
                settings: settings,
                timeZone: settings.exportTimeZoneOverride!,
                fetchHealthData: { _ in record },
                vaultManager: manager
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation after the final normal-day write boundary")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Rollups").path
        ))
        XCTAssertNil(manager.lastExportPresentationTarget)
    }

    func testManualDailyCancellationAfterPublicationRetainsCommittedAccounting() async throws {
        let vaultURL = try temporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeVaultManager(vaultURL: vaultURL)
        let settings = makeSettings()
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, calendar: utcCalendar())
        let record = record(on: selectedDate)
        var exportTask: Task<MacManualDailyOutputCommitter.Result, Error>?
        manager.dailyExportDidCommitForTesting = { exportTask?.cancel() }

        let task = Task { @MainActor in
            try await MacManualDailyOutputCommitter.commit(
                record,
                settings: settings,
                vaultManager: manager
            )
        }
        exportTask = task
        let committed = try await task.value

        XCTAssertTrue(task.isCancelled, "Cancellation must arrive after the daily commit")
        XCTAssertTrue(committed.didSucceed)
        XCTAssertNil(committed.failedDateDetail)
        XCTAssertEqual(committed.writeResult.totalGeneratedFileCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("2026-03-15.json").path
        ))
    }

    func testArchiveCancellationDuringAssemblyDoesNotPublishDerivedArtifact() async throws {
        let vaultURL = try temporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeVaultManager(vaultURL: vaultURL)
        let settings = makeSettings()
        settings.archiveExportFiles = true
        settings.generateRangeSummary = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, calendar: utcCalendar())
        let record = record(on: selectedDate)
        var exportTask: Task<MacManualRangeDerivedOutputCommitter.Result, Error>?
        manager.archiveEntryWillAppendForTesting = { exportTask?.cancel() }

        let task = Task { @MainActor in
            try await MacManualRangeDerivedOutputCommitter.commit(
                requestedDates: [selectedDate],
                capturedHealthData: [record],
                rollupHealthData: [record],
                settings: settings,
                timeZone: settings.exportTimeZoneOverride!,
                fetchHealthData: { _ in record },
                vaultManager: manager
            )
        }
        exportTask = task
        do {
            _ = try await task.value
            XCTFail("Expected archive cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Health.md Export 2026-03-15.zip").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Rollups").path
        ))
        XCTAssertNil(manager.lastExportPresentationTarget)
    }

    func testArchiveCancellationAfterPublicationReturnsCommittedSuccessAndPresentsArtifact() async throws {
        let vaultURL = try temporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeVaultManager(vaultURL: vaultURL)
        let settings = makeSettings()
        settings.archiveExportFiles = true
        settings.generateRangeSummary = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, calendar: utcCalendar())
        let record = record(on: selectedDate)
        let archiveURL = vaultURL.appendingPathComponent("Health.md Export 2026-03-15.zip")
        var exportTask: Task<MacManualRangeDerivedOutputCommitter.Result, Error>?
        manager.archiveDidPublishForTesting = { exportTask?.cancel() }

        let task = Task { @MainActor in
            try await MacManualRangeDerivedOutputCommitter.commit(
                requestedDates: [selectedDate],
                capturedHealthData: [record],
                rollupHealthData: [record],
                settings: settings,
                timeZone: settings.exportTimeZoneOverride!,
                fetchHealthData: { _ in record },
                vaultManager: manager
            )
        }
        exportTask = task
        let result = try await task.value

        XCTAssertTrue(task.isCancelled, "Cancellation must arrive after the atomic publication")
        XCTAssertEqual(result, .init(rollupFileCount: 0, archiveCount: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(
            manager.lastExportPresentationTarget,
            ExportPresentationTarget(
                fileURL: archiveURL,
                securityScopedRootURL: vaultURL
            )
        )
    }

    func testManualAllEmptySummaryOnlyMarksEveryRequestedDateTerminalExactlyOnce() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = try date(2026, 3, 14, calendar: calendar)
        let second = try date(2026, 3, 15, calendar: calendar)

        let result = MacLocalExportResultReconciliation.makeResult(
            requestedDates: [first, second],
            successCount: 0,
            failedDateDetails: [],
            partialFailures: [],
            formatsPerDate: 0,
            rollupFileCount: 0,
            completedDates: [],
            summaryOnly: true,
            capturedRequestedDates: [first, second, first],
            hasRenderableSummaryData: false,
            calendar: calendar
        )

        XCTAssertEqual(result.failedDateDetails.count, 2)
        XCTAssertEqual(result.failedDateDetails.map(\.reason), [.noHealthData, .noHealthData])
        XCTAssertEqual(
            Set(result.failedDateDetails.map { calendar.startOfDay(for: $0.date) }),
            Set([calendar.startOfDay(for: first), calendar.startOfDay(for: second)])
        )
        XCTAssertEqual(result.completedDates, [first, second])
        XCTAssertTrue(result.didCompleteAllRequestedDates)
        XCTAssertEqual(result.remainingDates(from: [first, second], calendar: calendar), [])
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suite = "MacExportViewLocalPathTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        retainedSettings.append(settings)
        return settings
    }

    private func makeVaultManager(vaultURL: URL) -> VaultManager {
        let resolver = FakeBookmarkResolver()
        resolver.accessGranted = true
        let manager = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: resolver
        )
        manager.healthSubfolder = ""
        manager.setVaultFolder(vaultURL)
        Self.retainedManagers.append(manager)
        return manager
    }

    private func record(on date: Date) -> HealthData {
        let fixture = ExportFixtures.fullDay
        var record = HealthData(date: date, timeContext: fixture.timeContext)
        record.sleep = fixture.sleep
        record.activity = fixture.activity
        record.heart = fixture.heart
        return record
    }

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return calendar
    }

    private func temporaryVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacManualRangeBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func unzip(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MacExportViewLocalPathTests.unzip",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey:
                    String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unzip failed"]
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
#endif
