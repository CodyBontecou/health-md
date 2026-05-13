import XCTest
@testable import HealthMd

final class ExportDateRangePresetTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testTodayResolvesToCurrentCalendarDay() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 13, hour: 15, minute: 45)
        let manualStart = makeDate(year: 2026, month: 5, day: 1, hour: 9)
        let manualEnd = makeDate(year: 2026, month: 5, day: 3, hour: 20)

        let range = ExportDateRangePreset.today.resolvedRange(
            referenceDate: referenceDate,
            currentStartDate: manualStart,
            currentEndDate: manualEnd,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, calendar.startOfDay(for: referenceDate))
        XCTAssertEqual(range?.endDate, calendar.startOfDay(for: referenceDate))
    }

    func testYesterdayResolvesToPreviousCalendarDay() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 13, hour: 15, minute: 45)
        let expectedYesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: referenceDate)
        )!

        let range = ExportDateRangePreset.yesterday.resolvedRange(
            referenceDate: referenceDate,
            currentStartDate: referenceDate,
            currentEndDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, expectedYesterday)
        XCTAssertEqual(range?.endDate, expectedYesterday)
    }

    func testCustomPreservesManuallySelectedRange() {
        let manualStart = makeDate(year: 2026, month: 4, day: 20, hour: 8, minute: 30)
        let manualEnd = makeDate(year: 2026, month: 4, day: 22, hour: 21, minute: 15)

        let range = ExportDateRangePreset.custom.resolvedRange(
            referenceDate: makeDate(year: 2026, month: 5, day: 13),
            currentStartDate: manualStart,
            currentEndDate: manualEnd,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, manualStart)
        XCTAssertEqual(range?.endDate, manualEnd)
    }

    func testAllTimeResolvesFromEarliestAvailableDateThroughProvidedEndDate() {
        let earliest = makeDate(year: 2024, month: 1, day: 5, hour: 10)
        let latest = makeDate(year: 2026, month: 5, day: 12, hour: 18)

        let range = ExportDateRangePreset.allTime.resolvedRange(
            referenceDate: makeDate(year: 2026, month: 5, day: 13),
            currentStartDate: latest,
            currentEndDate: latest,
            allTimeStartDate: earliest,
            allTimeEndDate: latest,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, calendar.startOfDay(for: earliest))
        XCTAssertEqual(range?.endDate, calendar.startOfDay(for: latest))
    }

    func testAllTimeWithoutAvailableDataReturnsNil() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 13)

        let range = ExportDateRangePreset.allTime.resolvedRange(
            referenceDate: referenceDate,
            currentStartDate: referenceDate,
            currentEndDate: referenceDate,
            calendar: calendar
        )

        XCTAssertNil(range)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
