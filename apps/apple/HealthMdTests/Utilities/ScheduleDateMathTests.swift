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

    // MARK: - Legacy Today Refresh characterization (visualizations issue #9)

    func testLegacyRefreshCannotMakeThirtyOrSixtyMinuteBoundaryDue() {
        var schedule = ExportSchedule(
            isEnabled: true, preferredHour: 8,
            todayRefreshEnabled: true, todayRefreshIntervalHours: 1,
            lastTodayRefreshDate: date(2026, 3, 15, 8)
        )
        for now in [date(2026, 3, 15, 8, 30), date(2026, 3, 15, 9)] {
            XCTAssertEqual(ScheduleDateMath.calculateNextRunDate(
                schedule: schedule, kind: .todayRefresh, now: now, calendar: Self.cal
            ), date(2026, 3, 15, 11))
            XCTAssertFalse(ScheduleDateMath.dueScheduledOccurrences(
                schedule: schedule, now: now, calendar: Self.cal
            ).contains { $0.kind == .todayRefresh })
        }
        let boundary = date(2026, 3, 15, 11)
        XCTAssertTrue(ScheduleDateMath.dueScheduledOccurrences(
            schedule: schedule, now: boundary, calendar: Self.cal
        ).contains { $0.kind == .todayRefresh && $0.fireDate == boundary })
        schedule.lastTodayRefreshDate = boundary
        XCTAssertFalse(ScheduleDateMath.dueScheduledOccurrences(
            schedule: schedule, now: boundary, calendar: Self.cal
        ).contains { $0.kind == .todayRefresh })
        XCTAssertEqual(ScheduleDateMath.calculateNextRunDate(
            schedule: schedule, kind: .todayRefresh, now: boundary, calendar: Self.cal
        ), date(2026, 3, 15, 14))
    }

    func testLegacyRefreshSlotsRetainPreferredMinuteAndRestartAtPreferredTimeNextDay() {
        for hours in [3, 6, 12] {
            let schedule = ExportSchedule(
                isEnabled: true, preferredHour: 8, preferredMinute: 15,
                todayRefreshEnabled: true, todayRefreshIntervalHours: hours
            )
            XCTAssertEqual(ScheduleDateMath.calculateNextRunDate(
                schedule: schedule, kind: .todayRefresh,
                now: date(2026, 3, 15, 8, 15), calendar: Self.cal
            ), date(2026, 3, 15, 8 + hours, 15))
            XCTAssertEqual(ScheduleDateMath.calculateNextRunDate(
                schedule: schedule, kind: .todayRefresh,
                now: date(2026, 3, 15, 23, 59), calendar: Self.cal
            ), date(2026, 3, 16, 8, 15))
            XCTAssertNil(ScheduleDateMath.latestScheduledOccurrenceDate(
                schedule: schedule, kind: .todayRefresh,
                now: date(2026, 3, 16, 0, 30), calendar: Self.cal
            ))
        }
    }

    func testLegacyRefreshDSTSlotsAreCivilTimesNotFixedElapsedDurations() throws {
        var calendar = Self.cal
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let schedule = ExportSchedule(
            isEnabled: true, preferredHour: 0, preferredMinute: 30,
            todayRefreshEnabled: true, todayRefreshIntervalHours: 3
        )
        for (month, day, elapsedHours) in [(3, 8, 2), (11, 1, 4)] {
            let start = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: month, day: day, hour: 0, minute: 30
            )))
            let next = try XCTUnwrap(ScheduleDateMath.calculateNextRunDate(
                schedule: schedule, kind: .todayRefresh, now: start, calendar: calendar
            ))
            XCTAssertEqual(calendar.component(.hour, from: next), 3)
            XCTAssertEqual(calendar.component(.minute, from: next), 30)
            XCTAssertEqual(next.timeIntervalSince(start), TimeInterval(elapsedHours * 3_600))
            XCTAssertEqual(ScheduleDateMath.latestScheduledOccurrenceDate(
                schedule: schedule, kind: .todayRefresh, now: next, calendar: calendar
            ), next)
        }
    }

    func testRefreshSelectsTodayWithoutReplacingCompletedLookbackAtDayRollover() {
        let schedule = ExportSchedule(
            isEnabled: true, frequency: .weekly, preferredHour: 8, lookbackDays: 7,
            todayRefreshEnabled: true
        )
        let fire = date(2026, 3, 15, 23)
        XCTAssertEqual(ScheduleDateMath.exportDates(
            for: .todayRefresh, schedule: schedule, fireDate: fire, calendar: Self.cal
        ), [date(2026, 3, 15)])
        let completed = ScheduleDateMath.exportDates(
            for: .completedDay, schedule: schedule, fireDate: fire, calendar: Self.cal
        )
        XCTAssertEqual(completed.count, 7)
        XCTAssertEqual(completed.first, date(2026, 3, 8))
        XCTAssertEqual(completed.last, date(2026, 3, 14))
        // Exact dates are anchored to fire, not a delayed wake after midnight.
        XCTAssertFalse(completed.contains(date(2026, 3, 15)))
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

    func testCatchUpDates_daily_lastExportYesterday_returnsYesterdayDataDay() {
        // A run yesterday at 09:00 exported the day before yesterday. Today's
        // occurrence must still export yesterday's data day.
        let yesterday = date(2026, 3, 14, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lastExportDate: yesterday)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates.count, 1, "Yesterday's data day is still unexported")
        XCTAssertEqual(Self.cal.component(.day, from: dates[0]), 14)
    }

    func testCatchUpDates_daily_lastExportToday_returnsEmpty() {
        // Today's 08:00 run already exported yesterday's data; a later
        // same-day wake-up has nothing to catch up.
        let today = date(2026, 3, 15, 8, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lastExportDate: today)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertTrue(dates.isEmpty, "Today's run already covered yesterday's data")
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

        // The Mar 10 run exported through Mar 9, so catch-up starts at Mar 10
        // (the run day) and runs through yesterday (Mar 14): 5 dates.
        XCTAssertEqual(dates.count, 5)
        XCTAssertEqual(Self.cal.component(.day, from: dates.first!), 10)
        XCTAssertEqual(Self.cal.component(.day, from: dates.last!), 14)
    }

    func testCatchUpDates_weekly_boundedBySeven() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertTrue(dates.count <= 7, "Weekly schedule should not go back more than 7 days")
    }
}
