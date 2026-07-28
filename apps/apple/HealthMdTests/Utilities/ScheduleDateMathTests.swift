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

    func testNextRunDate_weekly_usesConfiguredISOWeekday() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            preferredMinute: 0,
            weekday: 1
        )
        let now = date(2026, 3, 15, 10, 0) // Sunday; configured day is Monday

        let next = ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(next, date(2026, 3, 16, 8))
    }

    func testLatestOccurrence_weekly_remainsOnConfiguredWeekday() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            weekday: 1
        )

        let latest = ScheduleDateMath.latestScheduledOccurrenceDate(
            schedule: schedule,
            now: date(2026, 3, 18, 10),
            calendar: Self.cal
        )

        XCTAssertEqual(latest, date(2026, 3, 16, 8))
    }

    func testNextRunDate_customEveryOtherDay_skipsOffCadenceDay() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .day,
            customAnchorDate: date(2026, 3, 1),
            preferredHour: 8
        )

        let next = ScheduleDateMath.calculateNextRunDate(
            schedule: schedule,
            now: date(2026, 3, 2, 7),
            calendar: Self.cal
        )

        XCTAssertEqual(next, date(2026, 3, 3, 8))
    }

    func testNextRunDate_customMonthly_clampsShortMonthAndRestoresAnchorDay() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 1,
            customUnit: .month,
            customAnchorDate: date(2026, 1, 31),
            preferredHour: 8
        )

        let february = ScheduleDateMath.calculateNextRunDate(
            schedule: schedule,
            now: date(2026, 2, 1, 9),
            calendar: Self.cal
        )
        let march = ScheduleDateMath.calculateNextRunDate(
            schedule: schedule,
            now: date(2026, 2, 28, 9),
            calendar: Self.cal
        )

        XCTAssertEqual(february, date(2026, 2, 28, 8))
        XCTAssertEqual(march, date(2026, 3, 31, 8))
    }

    func testLatestOccurrence_customEveryOtherDay_returnsPriorCadenceDay() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .day,
            customAnchorDate: date(2026, 3, 1),
            preferredHour: 8
        )

        let latest = ScheduleDateMath.latestScheduledOccurrenceDate(
            schedule: schedule,
            now: date(2026, 3, 2, 10),
            calendar: Self.cal
        )

        XCTAssertEqual(latest, date(2026, 3, 1, 8))
    }

    func testLatestOccurrence_customFutureAnchor_returnsNil() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 1,
            customUnit: .month,
            customAnchorDate: date(2026, 4, 15),
            preferredHour: 8
        )

        XCTAssertNil(ScheduleDateMath.latestScheduledOccurrenceDate(
            schedule: schedule,
            now: date(2026, 3, 15, 10),
            calendar: Self.cal
        ))
    }

    // MARK: - shouldRunScheduledOccurrence

    func testShouldRunScheduledOccurrence_skipsFutureOccurrence() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let now = date(2026, 3, 15, 7, 0)
        let fireDate = date(2026, 3, 15, 8, 0)

        XCTAssertFalse(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: fireDate,
            now: now,
            calendar: Self.cal
        ))
    }

    func testShouldRunScheduledOccurrence_skipsOccurrenceBeforeCurrentEnablePeriod() {
        let enabledAt = date(2026, 3, 15, 12, 0)
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            enabledAt: enabledAt
        )
        let fireDate = date(2026, 3, 15, 8, 0)
        let now = date(2026, 3, 15, 13, 0)

        XCTAssertFalse(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: fireDate,
            now: now,
            calendar: Self.cal
        ))
    }

    func testShouldRunScheduledOccurrence_allowsOccurrenceAfterCurrentEnablePeriod() {
        let enabledAt = date(2026, 3, 15, 7, 0)
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            enabledAt: enabledAt
        )
        let fireDate = date(2026, 3, 15, 8, 0)
        let now = date(2026, 3, 15, 9, 0)

        XCTAssertTrue(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: fireDate,
            now: now,
            calendar: Self.cal
        ))
    }

    func testShouldRunScheduledOccurrence_weeklyRejectsWrongWeekday() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            weekday: 1
        )

        XCTAssertFalse(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: date(2026, 3, 17, 8),
            now: date(2026, 3, 17, 9),
            calendar: Self.cal
        ))
        XCTAssertTrue(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: date(2026, 3, 16, 8),
            now: date(2026, 3, 16, 9),
            calendar: Self.cal
        ))
    }

    func testShouldRunScheduledOccurrence_customRejectsDailyWakeUpOffCadence() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .day,
            customAnchorDate: date(2026, 3, 1),
            preferredHour: 8
        )

        XCTAssertFalse(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: date(2026, 3, 2, 8),
            now: date(2026, 3, 2, 9),
            calendar: Self.cal
        ))
        XCTAssertTrue(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: date(2026, 3, 3, 8),
            now: date(2026, 3, 3, 9),
            calendar: Self.cal
        ))
    }

    func testShouldRunScheduledOccurrence_customMonthlyAllowsClampedMonthEnd() {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 1,
            customUnit: .month,
            customAnchorDate: date(2026, 1, 31),
            preferredHour: 8
        )

        XCTAssertTrue(ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: date(2026, 2, 28, 8),
            now: date(2026, 2, 28, 9),
            calendar: Self.cal
        ))
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

    func testCatchUpDates_dailyCustomLookback_returnsConfiguredWindow() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lookbackDays: 3)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(Self.cal.component(.day, from: dates[0]), 12)
        XCTAssertEqual(Self.cal.component(.day, from: dates[2]), 14)
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
