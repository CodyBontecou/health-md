#if os(macOS)
import XCTest
@testable import HealthMd

final class MacScheduledRangeCaptureTests: XCTestCase {
    private var retainedSettings: [AdvancedExportSettings] = []

    override func tearDown() {
        retainedSettings.removeAll()
        super.tearDown()
    }

    func testRollupCaptureIncludesSourceRecordsButOnlySelectedDailyOutput() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let sourceDate = try date(2026, 3, 9, timeZone: timeZone)
        let selected = record(on: selectedDate)
        let source = record(on: sourceDate)
        let recordsByOwnerDate = [
            "2026-03-09": source,
            "2026-03-15": selected,
        ]
        let settings = makeSettings(summaryOnly: false)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { requestedDate in
            recordsByOwnerDate[ownerDate(requestedDate, timeZone: timeZone)]
        }

        XCTAssertEqual(captured.records.map { ownerDate($0.date, timeZone: timeZone) }, [
            "2026-03-15",
        ])
        XCTAssertEqual(captured.dailyOutputOwnerDates, ["2026-03-15"])
        XCTAssertEqual(captured.selectedRecordDates, [selectedDate])
        XCTAssertTrue(captured.failures.isEmpty)
    }

    func testEmptySupportingCacheRecordRemainsInRollupCoverage() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let sourceDate = try date(2026, 3, 9, timeZone: timeZone)
        let selected = record(on: selectedDate)
        let emptySource = HealthData(
            date: sourceDate,
            timeContext: ExportFixtures.timeContext
        )
        let recordsByOwnerDate = [
            "2026-03-09": emptySource,
            "2026-03-15": selected,
        ]
        let settings = makeSettings(summaryOnly: false)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { requestedDate in
            recordsByOwnerDate[ownerDate(requestedDate, timeZone: timeZone)]
        }

        XCTAssertEqual(captured.records.map { ownerDate($0.date, timeZone: timeZone) }, [
            "2026-03-15",
        ])
        XCTAssertEqual(captured.dailyOutputOwnerDates, ["2026-03-15"])
        XCTAssertTrue(captured.failures.isEmpty)
    }

    func testSelectedCacheMissRemainsRetryableWhileUnselectedMissesAreSilent() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let sourceDate = try date(2026, 3, 9, timeZone: timeZone)
        let source = record(on: sourceDate)
        let settings = makeSettings(summaryOnly: false)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { requestedDate in
            ownerDate(requestedDate, timeZone: timeZone) == "2026-03-09" ? source : nil
        }

        XCTAssertEqual(captured.records.count, 0)
        XCTAssertTrue(captured.dailyOutputOwnerDates.isEmpty)
        XCTAssertTrue(captured.selectedRecordDates.isEmpty)
        XCTAssertEqual(captured.failures.count, 1)
        XCTAssertEqual(captured.failures.first?.reason, .noHealthData)
        XCTAssertEqual(
            captured.failures.first.map { ownerDate($0.date, timeZone: timeZone) },
            "2026-03-15"
        )
    }

    func testSummaryOnlyCaptureNeverSelectsDailyArtifacts() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let selectedDate = try date(2026, 3, 15, timeZone: timeZone)
        let selected = record(on: selectedDate)
        let settings = makeSettings(summaryOnly: true)

        let captured = MacScheduledRangeCapture.capture(
            selectedDates: [selectedDate],
            settings: settings,
            timeZone: timeZone,
            latestAllowedDate: selectedDate
        ) { requestedDate in
            ownerDate(requestedDate, timeZone: timeZone) == "2026-03-15" ? selected : nil
        }

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
