import XCTest
@testable import HealthMd

final class ClinicianReportPresetTests: XCTestCase {
    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return calendar
    }

    func testPresetsMatchTheDesign() {
        XCTAssertEqual(ReportDateRangePreset.allCases, [.days30, .days90, .months6, .custom])
    }

    func testSixMonthsFollowsTheCalendarAndEndsToday() throws {
        let calendar = try calendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30)))
        let range = ReportDateRange.preset(.months6, today: today, calendar: calendar)
        XCTAssertEqual(range.endDate, today)
        XCTAssertEqual(range.startDate, calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
    }

    func testDayPresetsKeepTheirInclusiveCounts() throws {
        let calendar = try calendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30)))
        let range = ReportDateRange.preset(.days30, today: today, calendar: calendar)
        XCTAssertEqual(range.startDate, calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
    }
}
