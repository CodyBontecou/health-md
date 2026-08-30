#if os(macOS)
import XCTest
@testable import HealthMd

final class MacScheduledRangeCaptureTests: XCTestCase {
    private var retainedSettings: [AdvancedExportSettings] = []

    override func tearDown() {
        retainedSettings.removeAll()
        super.tearDown()
    }

    func testNormalModeLegacyAuthorityCaptureGeneratesStandaloneRangeV9Summary() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let selected = record(on: selectedDate)
        let settings = makeSettings(summaryOnly: false)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { requestedDate in
            ownerDate(requestedDate, timeZone: timeZone) == "2026-03-15" ? selected : nil
        }

        XCTAssertEqual(captured.records.map { ownerDate($0.date, timeZone: timeZone) }, [
            "2026-03-15",
        ])
        XCTAssertEqual(captured.dailyOutputOwnerDates, ["2026-03-15"])
        XCTAssertEqual(captured.selectedRecordDates, [selectedDate])
        XCTAssertEqual(captured.selectedRenderableDates, [selectedDate])
        XCTAssertTrue(captured.failures.isEmpty)

        let requestedRange = try HealthRollupRangeRequest(
            ownerDateIdentifiers: ["2026-03-15"],
            calendarTimeZoneIdentifier: timeZone.identifier
        )
        let range = try XCTUnwrap(HealthRollupExporter.makeSummaries(
            from: captured.records,
            requestedRange: requestedRange,
            settings: settings
        ).first { $0.period == .range })
        XCTAssertTrue(HealthRollupExporter.content(for: range, format: .json).contains(
            "\"schema_version\" : 9"
        ))
        XCTAssertEqual(range.daysExpected, 1)
        XCTAssertEqual(range.daysCounted, 1)
    }

    func testSuccessfulEmptyRequestedRecordRemainsInRangeCoverage() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let settings = makeSettings(summaryOnly: false)
        let empty = HealthData(date: selectedDate, timeContext: ExportFixtures.timeContext)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { _ in empty }

        XCTAssertEqual(captured.records.count, 1)
        XCTAssertTrue(captured.dailyOutputOwnerDates.isEmpty)
        XCTAssertEqual(captured.selectedRecordDates, [selectedDate])
        XCTAssertTrue(captured.selectedRenderableDates.isEmpty)
        XCTAssertTrue(captured.failures.isEmpty)
    }

    func testMixedEmptySummaryOnlyCaptureCompletesEveryCapturedDate() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let firstDate = try date(2026, 3, 14, timeZone: timeZone)
        let emptyDate = try date(2026, 3, 15, timeZone: timeZone)
        let settings = makeSettings(summaryOnly: true)
        let first = record(on: firstDate)
        let empty = HealthData(date: emptyDate, timeContext: ExportFixtures.timeContext)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [firstDate, emptyDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: emptyDate
        ) { requestedDate in
            ownerDate(requestedDate, timeZone: timeZone) == "2026-03-14" ? first : empty
        }

        XCTAssertEqual(captured.selectedRecordDates, [firstDate, emptyDate])
        XCTAssertEqual(captured.selectedRenderableDates, [firstDate])
        XCTAssertTrue(captured.dailyOutputOwnerDates.isEmpty)
        XCTAssertTrue(captured.failures.isEmpty)
        let requestedRange = try HealthRollupRangeRequest(
            ownerDateIdentifiers: ["2026-03-14", "2026-03-15"],
            calendarTimeZoneIdentifier: timeZone.identifier
        )
        let range = try XCTUnwrap(HealthRollupExporter.makeSummaries(
            from: captured.records,
            requestedRange: requestedRange,
            settings: settings
        ).first { $0.period == .range })
        XCTAssertEqual(range.daysExpected, 2)
        XCTAssertEqual(range.daysCounted, 2)
    }

    func testSelectedCacheMissRemainsRetryable() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let settings = makeSettings(summaryOnly: false)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { _ in nil }

        XCTAssertTrue(captured.records.isEmpty)
        XCTAssertTrue(captured.dailyOutputOwnerDates.isEmpty)
        XCTAssertTrue(captured.selectedRecordDates.isEmpty)
        XCTAssertEqual(captured.failures.count, 1)
        XCTAssertEqual(captured.failures.first?.reason, .noHealthData)
    }

    func testArchiveResidualRetryReusesCurrentDayAndRecapturesEveryOriginalSource() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let firstDate = try date(2026, 3, 13, timeZone: timeZone)
        let secondDate = try date(2026, 3, 14, timeZone: timeZone)
        let residualDate = try date(2026, 3, 15, timeZone: timeZone)
        let first = record(on: firstDate)
        let second = record(on: secondDate)
        let residual = record(on: residualDate)
        var fetchedOwnerDates: [String] = []

        let sources = MacScheduledRangeCapture.archiveSources(
            originalRequestedDates: [firstDate, secondDate, residualDate],
            reusing: [residual],
            timeZone: timeZone
        ) { requestedDate in
            let requestedOwnerDate = ownerDate(requestedDate, timeZone: timeZone)
            fetchedOwnerDates.append(requestedOwnerDate)
            switch requestedOwnerDate {
            case "2026-03-13": return first
            case "2026-03-14": return second
            default: return nil
            }
        }

        XCTAssertEqual(fetchedOwnerDates, ["2026-03-13", "2026-03-14"])
        XCTAssertEqual(sources?.map { ownerDate($0.date, timeZone: timeZone) }, [
            "2026-03-13", "2026-03-14", "2026-03-15",
        ])
    }

    func testResidualRangeRetryRestoresPreviouslySuccessfulEmptyCachedDay() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let priorDate = try date(2026, 3, 14, timeZone: timeZone)
        let residualDate = try date(2026, 3, 15, timeZone: timeZone)
        let emptyPrior = HealthData(date: priorDate, timeContext: ExportFixtures.timeContext)
        let residual = record(on: residualDate)
        let settings = makeSettings(summaryOnly: false)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [residualDate],
            rollupRequestedDates: [priorDate, residualDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: residualDate
        ) { requestedDate in
            switch ownerDate(requestedDate, timeZone: timeZone) {
            case "2026-03-14": return emptyPrior
            case "2026-03-15": return residual
            default: return nil
            }
        }

        XCTAssertEqual(captured.records.map { ownerDate($0.date, timeZone: timeZone) }, [
            "2026-03-14", "2026-03-15",
        ])
        XCTAssertEqual(captured.selectedRecordDates, [residualDate])
        XCTAssertEqual(captured.selectedRenderableDates, [residualDate])
        XCTAssertTrue(captured.failures.isEmpty)
    }

    func testPinnedAndLegacyScheduledRangesOverLimitFallBackToDailyWithWarning() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = try date(2000, 1, 1, timeZone: timeZone)
        let end = try date(2027, 5, 19, timeZone: timeZone)
        let dates = ExportOrchestrator.dateRange(from: start, to: end, calendar: calendar)
        XCTAssertEqual(dates.count, 10_001)
        let settings = makeSettings(summaryOnly: true)
        let legacySnapshot = ExportSettingsSnapshot.from(
            settings,
            calendarTimeZoneIdentifier: timeZone.identifier
        )
        var pinnedSnapshot = legacySnapshot
        pinnedSnapshot.appleExportEnginePin = try makeSyntheticAppleExportEnginePin(
            calendarTimeZoneIdentifier: timeZone.identifier
        )

        for snapshot in [legacySnapshot, pinnedSnapshot] {
            let availability = ExportOrchestrator.settingsByDisablingUnavailableRangeSummary(
                snapshot,
                requestedDates: dates,
                calendarTimeZone: timeZone
            )
            let effective = availability.snapshot.makeAdvancedExportSettings()
            XCTAssertFalse(effective.generateRangeSummary)
            XCTAssertFalse(effective.summaryOnlyModeEnabled)
            XCTAssertEqual(effective.exportFormats, [.json])
            XCTAssertEqual(availability.warning?.dataType, "Range Summary")
            XCTAssertEqual(
                availability.warning?.errorDescription,
                HealthRollupRangeRequest.dayLimitUnavailableMessage
            )
            XCTAssertEqual(
                availability.snapshot.appleExportEnginePin,
                snapshot.appleExportEnginePin
            )
        }
    }

    func testScheduledResultReconciliationLeavesOnlyUncapturedResidualDate() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDate = try date(2026, 3, 13, timeZone: timeZone)
        let emptyDate = try date(2026, 3, 14, timeZone: timeZone)
        let missingDate = try date(2026, 3, 15, timeZone: timeZone)

        let result = MacLocalExportResultReconciliation.makeResult(
            requestedDates: [firstDate, emptyDate, missingDate],
            successCount: 1,
            failedDateDetails: [
                FailedDateDetail(date: emptyDate, reason: .noHealthData),
                FailedDateDetail(date: missingDate, reason: .noHealthData),
            ],
            partialFailures: [],
            formatsPerDate: 1,
            completedDates: [firstDate, emptyDate],
            summaryOnly: false,
            capturedRequestedDates: [firstDate, emptyDate],
            hasRenderableSummaryData: true,
            calendar: calendar
        )

        XCTAssertEqual(
            result.remainingDates(from: [firstDate, emptyDate, missingDate], calendar: calendar),
            [missingDate]
        )
        XCTAssertEqual(result.completedDates, [firstDate, emptyDate])
        XCTAssertEqual(result.completedDateCount, 2)
    }

    func testArchiveResidualRetryRequiresEveryOriginalSourceBeforeReplacement() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let firstDate = try date(2026, 3, 14, timeZone: timeZone)
        let residualDate = try date(2026, 3, 15, timeZone: timeZone)

        let sources = MacScheduledRangeCapture.archiveSources(
            originalRequestedDates: [firstDate, residualDate],
            reusing: [record(on: residualDate)],
            timeZone: timeZone,
            fetch: { _ in nil }
        )

        XCTAssertNil(sources)
    }

    func testSummaryOnlyRangeCaptureNeverSelectsDailyArtifacts() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let selected = record(on: selectedDate)
        let settings = makeSettings(summaryOnly: true)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { _ in selected }

        XCTAssertEqual(captured.records.count, 1)
        XCTAssertTrue(captured.dailyOutputOwnerDates.isEmpty)
        XCTAssertEqual(captured.selectedRecordDates, [selectedDate])
        XCTAssertTrue(captured.failures.isEmpty)
    }

    private func makeSettings(summaryOnly: Bool) -> AdvancedExportSettings {
        let suite = "MacScheduledRangeCaptureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json]
        settings.generateRangeSummary = true
        settings.summaryOnlyExport = summaryOnly
        settings.includeGranularData = false
        retainedSettings.append(settings)
        return settings
    }

    private func record(on date: Date) -> HealthData {
        let fixture = ExportFixtures.partialDay
        var value = HealthData(date: date, timeContext: fixture.timeContext)
        value.sleep = fixture.sleep
        value.activity = fixture.activity
        return value
    }

    private func ownerDate(_ date: Date, timeZone: TimeZone) -> String {
        HealthKitDailyOwnershipMetadata.ownerDate(
            for: date,
            calendarTimeZoneIdentifier: timeZone.identifier
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        )))
    }
}
#endif
