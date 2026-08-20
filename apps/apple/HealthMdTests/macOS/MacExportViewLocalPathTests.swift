#if os(macOS)
import XCTest
@testable import HealthMd

final class MacExportViewLocalPathTests: XCTestCase {
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
