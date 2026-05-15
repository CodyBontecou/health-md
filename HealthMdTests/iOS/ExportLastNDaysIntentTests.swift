#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class ExportLastNDaysIntentTests: XCTestCase {
    func testExportDates_defaultEndsYesterdayAndExcludesToday() {
        let dates = ExportLastNDaysIntent.exportDates(
            days: ExportLastNDaysIntent.defaultDays,
            now: date(2026, 5, 11, hour: 15),
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.first, date(2026, 5, 4))
        XCTAssertEqual(dates.last, date(2026, 5, 10))
        XCTAssertFalse(dates.contains(date(2026, 5, 11)))
    }

    func testExportDates_clampsBelowRangeToOneDay() {
        let dates = ExportLastNDaysIntent.exportDates(
            days: 0,
            now: date(2026, 5, 11, hour: 15),
            calendar: calendar
        )

        XCTAssertEqual(dates, [date(2026, 5, 10)])
    }

    func testExportDates_clampsAboveRangeToThreeHundredSixtySixDays() {
        let dates = ExportLastNDaysIntent.exportDates(
            days: 999,
            now: date(2026, 5, 11, hour: 15),
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 366)
        XCTAssertEqual(dates.first, date(2025, 5, 10))
        XCTAssertEqual(dates.last, date(2026, 5, 10))
    }

    func testInitClampsStoredParameterForShortcutRuntime() {
        XCTAssertEqual(ExportLastNDaysIntent(days: -20).days, 1)
        XCTAssertEqual(ExportLastNDaysIntent(days: 500).days, 366)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
#endif
