#if os(macOS)
import XCTest
@testable import HealthMd

final class MacScheduledRangeCaptureTests: XCTestCase {
    private var retainedSettings: [AdvancedExportSettings] = []

    override func tearDown() {
        retainedSettings.removeAll()
        super.tearDown()
    }

    func testRangeV9CaptureUsesOnlyImmutableRequestedSourceDates() throws {
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
        XCTAssertTrue(captured.failures.isEmpty)
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
        XCTAssertTrue(captured.selectedRecordDates.isEmpty)
        XCTAssertEqual(captured.failures.map(\.reason), [.noHealthData])
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
