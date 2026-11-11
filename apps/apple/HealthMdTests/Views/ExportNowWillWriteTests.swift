#if os(iOS)
import XCTest
@testable import HealthMd

/// ExportNowG's "Will write" line.
@MainActor
final class ExportNowWillWriteTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func summary(
        days: Int,
        formats: Int = 2,
        summaryOnly: Bool = false,
        dailyNotesOnly: Bool = false,
        notes: Bool = false
    ) -> String {
        ExportNowWillWrite.summary(
            dayCount: days,
            formatCount: formats,
            summaryOnly: summaryOnly,
            dailyNotesOnly: dailyNotesOnly,
            updatesDailyNotes: notes,
            rangeText: "Oct 24 – 30",
            locale: locale
        )
    }

    func testFilesAndDaysStayAnEstimate() {
        XCTAssertEqual(summary(days: 7), "About 14 files · 7 days")
        XCTAssertEqual(summary(days: 1, formats: 1), "About 1 file · 1 day")
    }

    func testDailyNotesAppearOnlyWhenTheProfileUpdatesThem() {
        XCTAssertEqual(summary(days: 7, notes: true), "About 14 files · 7 days · daily notes updated")
        XCTAssertFalse(summary(days: 7, notes: false).contains("daily notes"))
    }

    func testDailyNotesOnlyWritesNoExportFiles() {
        XCTAssertEqual(summary(days: 7, dailyNotesOnly: true), "7 days · daily notes updated")
    }

    func testRangeSummaryOnlyIsOneFile() {
        XCTAssertEqual(summary(days: 7, summaryOnly: true, notes: true), "1 range summary for Oct 24 – 30")
    }

    /// The sheet's presets are completed days ending yesterday, independent of saved settings.
    func testRangePresetsEndYesterday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9)))
        let day = { (d: Int) in calendar.date(from: DateComponents(year: 2026, month: 10, day: d))! }

        let yesterday = try XCTUnwrap(ExportNowRange.yesterday.dates(now: now, calendar: calendar))
        XCTAssertEqual(yesterday.start, day(30))
        XCTAssertEqual(yesterday.end, day(30))
        let week = try XCTUnwrap(ExportNowRange.last7.dates(now: now, calendar: calendar))
        XCTAssertEqual(week.start, day(24))
        XCTAssertEqual(week.end, day(30))
        XCTAssertNil(ExportNowRange.custom.dates(now: now, calendar: calendar))
    }
}
#endif
