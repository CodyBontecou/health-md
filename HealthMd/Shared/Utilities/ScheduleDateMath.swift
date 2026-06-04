import Foundation

/// Health.md compatibility facade for generic ExportAutomationKit schedule math.
///
/// Keep this type so existing app code and tests do not change shape while the
/// reusable implementation lives in `AutomationScheduleDateMath`.
enum ScheduleDateMath {

    /// Calculate the next scheduled run date given the current time and schedule.
    /// Returns the next occurrence of preferredHour:preferredMinute. If that time
    /// hasn't passed today, returns today at that time. Otherwise advances by the
    /// schedule's frequency interval (1 day for daily, 7 days for weekly).
    static func calculateNextRunDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        AutomationScheduleDateMath.calculateNextRunDate(
            schedule: schedule.automationSchedule(timeZone: calendar.timeZone),
            now: now,
            calendar: calendar
        )
    }

    /// Determine which dates need catch-up exports. Returns data days that have
    /// not been exported yet, bounded by the configured lookback and yesterday.
    static func catchUpDatesNeeded(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        AutomationScheduleDateMath.catchUpDatesNeeded(
            schedule: schedule.automationSchedule(timeZone: calendar.timeZone),
            now: now,
            calendar: calendar
        )
    }

    /// Returns the data days covered by one scheduled export occurrence.
    /// The scheduled fire date is the run day, so the export window is the
    /// configured lookback ending with the prior calendar day.
    static func scheduledExportDates(
        schedule: ExportSchedule,
        fireDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        AutomationScheduleDateMath.scheduledExportDates(
            schedule: schedule.automationSchedule(timeZone: calendar.timeZone),
            fireDate: fireDate,
            calendar: calendar
        )
    }

    /// Returns the scheduled occurrence that should be considered due at `now`.
    /// If today's preferred time has not arrived, this returns the previous
    /// frequency interval. BGTaskScheduler does not tell us the exact fire date,
    /// so this gives background and HealthKit triggers a stable occurrence key.
    static func latestScheduledOccurrenceDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        AutomationScheduleDateMath.latestScheduledOccurrenceDate(
            schedule: schedule.automationSchedule(timeZone: calendar.timeZone),
            now: now,
            calendar: calendar
        )
    }
}
