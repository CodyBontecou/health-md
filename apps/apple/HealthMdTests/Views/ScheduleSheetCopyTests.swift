#if os(iOS)
import Foundation
import SwiftUI
import XCTest
@testable import HealthMd

/// ScheduleG copy and the board-specific calendar sizing.
@MainActor
final class ScheduleSheetCopyTests: XCTestCase {
    private nonisolated let locale = Locale(identifier: "en_US")
    private nonisolated let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Interval formatters insert thin/narrow spaces around the dash; compare on plain spaces.
    private func plain(_ text: String?) -> String? {
        text.map { String($0.unicodeScalars.map { $0.properties.isWhitespace ? " " : Character($0) }) }
    }

    // MARK: - Refresh chips

    func testRefreshChipTitlesCoverEveryIntervalOption() {
        let titles = ExportSchedule.todayRefreshMinuteOptions.map {
            ScheduleSheetCopy.refreshChipTitle(minutes: $0, locale: locale)
        }
        XCTAssertEqual(titles, ["30 min", "1 hr", "3 hr", "6 hr", "12 hr"])
    }

    // MARK: - Stepper counts

    func testCountPluralizesByUnit() {
        XCTAssertEqual(ScheduleSheetCopy.count(1, unit: .day, locale: locale), "1 day")
        XCTAssertEqual(ScheduleSheetCopy.count(3, unit: .day, locale: locale), "3 days")
        XCTAssertEqual(ScheduleSheetCopy.count(1, unit: .week, locale: locale), "1 week")
        XCTAssertEqual(ScheduleSheetCopy.count(2, unit: .month, locale: locale), "2 months")
    }

    // MARK: - Pending recovery range

    func testPendingRecoveryRangeIsNilWithoutDates() {
        XCTAssertNil(ScheduleSheetCopy.pendingRecoveryRange([], calendar: calendar, locale: locale))
    }

    func testPendingRecoveryRangeNamesASingleDay() {
        let range = ScheduleSheetCopy.pendingRecoveryRange(
            [date(2026, 10, 19, hour: 9)],
            now: date(2026, 11, 1),
            calendar: calendar,
            locale: locale
        )
        XCTAssertEqual(range, "Oct 19")
    }

    func testPendingRecoveryRangeSpansEarliestToLatestRegardlessOfOrder() {
        let range = ScheduleSheetCopy.pendingRecoveryRange(
            [date(2026, 10, 20), date(2026, 10, 19, hour: 23), date(2026, 10, 20, hour: 6)],
            now: date(2026, 11, 1),
            calendar: calendar,
            locale: locale
        )
        XCTAssertEqual(plain(range), "Oct 19 – 20")
    }

    func testPendingRecoveryRangeAcrossMonthsAndYears() {
        XCTAssertEqual(
            plain(ScheduleSheetCopy.pendingRecoveryRange(
                [date(2026, 9, 30), date(2026, 10, 2)],
                now: date(2026, 11, 1), calendar: calendar, locale: locale
            )),
            "Sep 30 – Oct 2"
        )
        let lastYear = ScheduleSheetCopy.pendingRecoveryRange(
            [date(2025, 12, 31), date(2026, 1, 1)],
            now: date(2026, 1, 2), calendar: calendar, locale: locale
        )
        XCTAssertTrue(lastYear?.contains("2025") == true, "a span leaving this year names the year: \(lastYear ?? "nil")")
    }

    func testPendingRecoveryMessageFallsBackWhenDaysAreUnknown() {
        XCTAssertTrue(ScheduleSheetCopy.pendingRecoveryMessage(range: "Oct 19").contains("Oct 19"))
        XCTAssertFalse(ScheduleSheetCopy.pendingRecoveryMessage(range: nil).isEmpty)
    }

    // MARK: - Calendar density

    func testCalendarDensityFollowsTheArchiveBoards() {
        XCTAssertEqual(CalendarDensity.resolve(isPad: false, isRegularWidth: false), .standard)
        XCTAssertEqual(CalendarDensity.resolve(isPad: true, isRegularWidth: false), .standard, "iPad split view keeps phone tiles")
        XCTAssertEqual(CalendarDensity.resolve(isPad: false, isRegularWidth: true), .wide)
        XCTAssertEqual(CalendarDensity.resolve(isPad: true, isRegularWidth: true), .pad)

        XCTAssertEqual(CalendarDensity.standard.tileHeight, 44)
        XCTAssertEqual(CalendarDensity.wide.tileHeight, 56)
        XCTAssertEqual(CalendarDensity.pad.tileHeight, 64)
        XCTAssertTrue(CalendarDensity.pad.usesShortWeekdaySymbols)
        XCTAssertFalse(CalendarDensity.wide.usesShortWeekdaySymbols)
    }

    func testWeekdaySymbolsHonourFirstWeekdayInBothWidths() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        XCTAssertEqual(MonthCalendarGrid<EmptyView>.weekdaySymbols(calendar: calendar, short: true).first, "Sun")
        XCTAssertEqual(MonthCalendarGrid<EmptyView>.weekdaySymbols(calendar: mondayFirst, short: true).first, "Mon")
        XCTAssertEqual(MonthCalendarGrid<EmptyView>.weekdaySymbols(calendar: mondayFirst).first, "M")
    }
}
#endif
