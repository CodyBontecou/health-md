//
//  ScheduleDateMathTests.swift
//  HealthMdTests
//
//  Tests for pure scheduling date math extracted from SchedulingManager.
//  Cross-platform — no system scheduler dependencies.
//

import XCTest
@testable import HealthMd

final class ScheduleDateMathTests: XCTestCase {

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Self.cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - calculateNextRunDate

    func testNextRunDate_daily_beforePreferredTime_returnsToday() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 14, preferredMinute: 0)
        let now = date(2026, 3, 15, 10, 0) // 10:00, preferred is 14:00

        let next = ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertNotNil(next)
        let comps = Self.cal.dateComponents([.year, .month, .day, .hour], from: next!)
        XCTAssertEqual(comps.day, 15, "Should return today since preferred time hasn't passed")
        XCTAssertEqual(comps.hour, 14)
    }

    func testNextRunDate_daily_afterPreferredTime_returnsTomorrow() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, preferredMinute: 0)
        let now = date(2026, 3, 15, 10, 0) // 10:00, preferred is 08:00

        let next = ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertNotNil(next)
        let comps = Self.cal.dateComponents([.day], from: next!)
        XCTAssertEqual(comps.day, 16, "Should return tomorrow since preferred time has passed")
    }

    func testNextRunDate_weekly_afterPreferredTime_returnsNextWeek() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8, preferredMinute: 0)
        let now = date(2026, 3, 15, 10, 0) // 10:00 Sunday

        let next = ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertNotNil(next)
        let comps = Self.cal.dateComponents([.day], from: next!)
        XCTAssertEqual(comps.day, 22, "Should return 7 days later for weekly")
    }

    // MARK: - catchUpDatesNeeded

    func testCatchUpDates_daily_noLastExport_returnsYesterday() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates.count, 1, "Should have one catch-up date (yesterday)")
        let comps = Self.cal.dateComponents([.day], from: dates[0])
        XCTAssertEqual(comps.day, 14)
    }

    func testCatchUpDates_daily_lastExportYesterday_returnsEmpty() {
        let yesterday = date(2026, 3, 14, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lastExportDate: yesterday)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertTrue(dates.isEmpty, "Yesterday already exported — nothing to catch up")
    }

    func testCatchUpDates_daily_missedDays_clippedToYesterday() {
        // Daily schedule only looks back 1 day (yesterday).
        // Even if we missed 3 days, catch-up only returns yesterday.
        let threeDaysAgo = date(2026, 3, 11, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lastExportDate: threeDaysAgo)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        // Daily lookback clips to yesterday only
        XCTAssertEqual(dates.count, 1, "Daily catch-up should only return yesterday")
        let comps = Self.cal.dateComponents([.day], from: dates[0])
        XCTAssertEqual(comps.day, 14, "Should be Mar 14 (yesterday)")
    }

    func testCatchUpDates_weekly_missedDays_returnsMultiple() {
        // Weekly schedule looks back 7 days, so it can catch up multiple missed days
        let fiveDaysAgo = date(2026, 3, 10, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8, lastExportDate: fiveDaysAgo)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        // lastExportDay = Mar 10, dayAfter = Mar 11. oldestDate = Mar 8.
        // max(Mar 11, Mar 8) = Mar 11. Range: Mar 11..Mar 14 = 4 dates
        XCTAssertTrue(dates.count >= 2, "Weekly catch-up should return multiple missed dates")
    }

    func testCatchUpDates_weekly_boundedBySeven() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertTrue(dates.count <= 7, "Weekly schedule should not go back more than 7 days")
    }
}
