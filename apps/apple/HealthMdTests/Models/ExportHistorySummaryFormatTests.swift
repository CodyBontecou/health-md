import XCTest
@testable import HealthMd

/// Wording for the Mac menu bar and Mac destination "Last export" and activity rows.
final class ExportHistorySummaryFormatTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testWhenNamesTodayAndYesterdayAndDatesOlderExports() {
        let now = date(2026, 10, 31, 9)
        let today = ExportHistorySummaryFormat.when(date(2026, 10, 31, 7, 30), now: now, calendar: calendar, locale: locale)
        let yesterday = ExportHistorySummaryFormat.when(date(2026, 10, 30, 23, 2), now: now, calendar: calendar, locale: locale)
        let older = ExportHistorySummaryFormat.when(date(2026, 10, 21, 23, 3), now: now, calendar: calendar, locale: locale)

        XCTAssertTrue(today.hasPrefix("Today "), today)
        XCTAssertTrue(today.contains("7:30"), today)
        XCTAssertTrue(yesterday.hasPrefix("Yesterday "), yesterday)
        XCTAssertTrue(older.contains("Oct 21"), older)
    }

    func testShortWhenUsesTimeTodayThenYesterdayThenDate() {
        let now = date(2026, 10, 31, 9)
        XCTAssertTrue(ExportHistorySummaryFormat.shortWhen(date(2026, 10, 31, 8, 5), now: now, calendar: calendar, locale: locale).contains("8:05"))
        XCTAssertEqual(ExportHistorySummaryFormat.shortWhen(date(2026, 10, 30, 8), now: now, calendar: calendar, locale: locale), "Yesterday")
        XCTAssertEqual(ExportHistorySummaryFormat.shortWhen(date(2026, 10, 21, 8), now: now, calendar: calendar, locale: locale), "Oct 21")
    }

    func testDateRangeCollapsesOneDayAndOrdersBounds() {
        XCTAssertEqual(
            ExportHistorySummaryFormat.dateRange(start: date(2026, 10, 30), end: date(2026, 10, 30, 12), calendar: calendar, locale: locale),
            "Oct 30"
        )
        let range = ExportHistorySummaryFormat.dateRange(start: date(2026, 10, 30), end: date(2026, 10, 24), calendar: calendar, locale: locale)
        XCTAssertTrue(range.hasPrefix("Oct 24"), range)
        XCTAssertTrue(range.hasSuffix("30"), range)
    }

    func testFilesAndLineSkipUnknownAndEmptyParts() {
        XCTAssertEqual(ExportHistorySummaryFormat.files(1), "1 file")
        XCTAssertEqual(ExportHistorySummaryFormat.files(3), "3 files")
        XCTAssertNil(ExportHistorySummaryFormat.files(nil))
        XCTAssertEqual(ExportHistorySummaryFormat.line("Today 7:30 AM", nil, "", "Oct 30"), "Today 7:30 AM · Oct 30")
    }

    func testWrittenExportEventReadsAsReceivedRangeFromDevice() {
        let event = SyncEvent(
            peerName: "Cody's iPhone",
            kind: .macExportSucceeded,
            recordCount: 1,
            dateRangeStart: Date(),
            dateRangeEnd: Date()
        )
        XCTAssertTrue(event.activityLine.hasPrefix("Received "), event.activityLine)
        XCTAssertTrue(event.activityLine.contains("from Cody's iPhone"), event.activityLine)
        XCTAssertTrue(event.activityLine.hasSuffix("· 1 file"), event.activityLine)

        let lowerBound = SyncEvent(peerName: "iPhone", kind: .macExportSucceeded, recordCount: 4, recordCountIsLowerBound: true)
        XCTAssertEqual(lowerBound.activityLine, "Received from iPhone")
    }

    // MARK: - MacHistoryG

    func testHistoryWhenJoinsDayAndTime() {
        let value = ExportHistorySummaryFormat.historyWhen(date(2026, 10, 30, 23, 2), calendar: calendar, locale: locale)
        XCTAssertTrue(value.hasPrefix("Oct 30 · "), value)
        XCTAssertTrue(value.contains("11:02"), value)
    }

    func testHistoryStatusNamesCompleteAndCountsFailedDates() {
        let day = date(2026, 10, 22, 23)
        let complete = ExportHistoryEntry(
            timestamp: day, source: .scheduled, success: true,
            dateRangeStart: day, dateRangeEnd: day, successCount: 1, totalCount: 1
        )
        XCTAssertEqual(complete.historyStatusLine, "Complete")
        XCTAssertNil(complete.failedDatesLine)

        let partial = ExportHistoryEntry(
            timestamp: day, source: .macAgent, success: false,
            dateRangeStart: date(2026, 10, 19), dateRangeEnd: date(2026, 10, 21),
            successCount: 1, totalCount: 3,
            failedDateDetails: [
                FailedDateDetail(date: date(2026, 10, 20, 12), reason: .fileWriteError),
                FailedDateDetail(date: date(2026, 10, 21, 12), reason: .fileWriteError)
            ]
        )
        XCTAssertEqual(partial.historyStatusLine, "2 dates failed")
        XCTAssertEqual(partial.historyDetailTitle(calendar: calendar, locale: locale), "Oct 22 · 2 dates failed")
        XCTAssertEqual(partial.failedDatesLine?.components(separatedBy: " · ").count, 2)

        let oneDay = ExportHistoryEntry(
            timestamp: day, source: .manual, success: false,
            dateRangeStart: day, dateRangeEnd: day, successCount: 0, totalCount: 1,
            failedDateDetails: [FailedDateDetail(date: day, reason: .fileWriteError)]
        )
        XCTAssertEqual(oneDay.historyStatusLine, "1 date failed")

        let failedWithoutDates = ExportHistoryEntry(
            timestamp: day, source: .manual, success: false,
            dateRangeStart: day, dateRangeEnd: day, successCount: 0, totalCount: 1
        )
        XCTAssertEqual(failedWithoutDates.historyStatusLine, "Failed")
    }
}
