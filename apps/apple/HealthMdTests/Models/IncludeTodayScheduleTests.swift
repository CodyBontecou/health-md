import XCTest
@testable import HealthMd

final class IncludeTodayScheduleTests: XCTestCase {
    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)))
    }

    func testOffByDefaultKeepsTheWindowEndingYesterday() throws {
        let calendar = try utcCalendar()
        let schedule = ExportSchedule(frequency: .daily, lookbackDays: 3)
        XCTAssertFalse(schedule.includeToday)
        XCTAssertEqual(
            ScheduleDateMath.scheduledExportDates(
                schedule: schedule,
                fireDate: try date(10, hour: 8, in: calendar),
                calendar: calendar
            ),
            [try date(7, in: calendar), try date(8, in: calendar), try date(9, in: calendar)]
        )
    }

    func testOnSlidesTheWindowWithoutChangingItsSize() throws {
        let calendar = try utcCalendar()
        var schedule = ExportSchedule(frequency: .daily, lookbackDays: 3)
        schedule.includeToday = true
        XCTAssertEqual(
            ScheduleDateMath.scheduledExportDates(
                schedule: schedule,
                fireDate: try date(10, hour: 8, in: calendar),
                calendar: calendar
            ),
            [try date(8, in: calendar), try date(9, in: calendar), try date(10, in: calendar)]
        )
    }

    func testCatchUpStaysOnCompletedDays() throws {
        let calendar = try utcCalendar()
        var schedule = ExportSchedule(frequency: .daily, lookbackDays: 3)
        schedule.includeToday = true
        let dates = ScheduleDateMath.catchUpDatesNeeded(
            schedule: schedule,
            now: try date(10, hour: 8, in: calendar),
            calendar: calendar
        )
        XCTAssertFalse(dates.contains(try date(10, in: calendar)), "A partial today is never a catch-up date.")
    }

    func testScheduleRoundTripsAndOlderDataDecodesAsOff() throws {
        var schedule = ExportSchedule(frequency: .daily, lookbackDays: 2)
        schedule.includeToday = true
        let data = try JSONEncoder().encode(schedule)
        XCTAssertTrue(try JSONDecoder().decode(ExportSchedule.self, from: data).includeToday)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "includeToday")
        let older = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(try JSONDecoder().decode(ExportSchedule.self, from: older).includeToday)
    }

    func testEntryCarriesTheSettingIntoDateMathAndDecodesOlderDataAsOff() throws {
        var entry = ScheduledExportEntry(profileID: UUID(), isEnabled: true, frequency: .daily)
        XCTAssertFalse(entry.dateMathProjection.includeToday)
        entry.includeToday = true
        XCTAssertTrue(entry.dateMathProjection.includeToday)

        let data = try JSONEncoder().encode(entry)
        XCTAssertTrue(try JSONDecoder().decode(ScheduledExportEntry.self, from: data).includeToday)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "includeToday")
        let older = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(try JSONDecoder().decode(ScheduledExportEntry.self, from: older).includeToday)
    }
}
