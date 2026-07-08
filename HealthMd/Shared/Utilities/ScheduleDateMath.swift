import Foundation

/// Pure date-math utilities extracted from SchedulingManager (iOS+macOS).
/// Stateless and deterministic — all external state is passed in.
enum ScheduleDateMath {
    struct DueScheduledOccurrence: Equatable {
        let kind: ScheduledExportKind
        let fireDate: Date
    }

    /// Calculate the next scheduled run date given the current time and schedule.
    static func calculateNextRunDate(
        schedule: ExportSchedule,
        kind: ScheduledExportKind = .completedDay,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch kind {
        case .completedDay:
            return nextCompletedDayRunDate(schedule: schedule, now: now, calendar: calendar)
        case .todayRefresh:
            return nextTodayRefreshRunDate(schedule: schedule, now: now, calendar: calendar)
        }
    }

    static func nextScheduledOccurrences(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar = .current
    ) -> [DueScheduledOccurrence] {
        ScheduledExportKind.allCases.compactMap { kind in
            calculateNextRunDate(schedule: schedule, kind: kind, now: now, calendar: calendar)
                .map { DueScheduledOccurrence(kind: kind, fireDate: $0) }
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    static func dueScheduledOccurrences(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar = .current
    ) -> [DueScheduledOccurrence] {
        ScheduledExportKind.allCases.compactMap { kind in
            guard let fireDate = latestScheduledOccurrenceDate(schedule: schedule, kind: kind, now: now, calendar: calendar),
                  shouldRunScheduledOccurrence(schedule: schedule, kind: kind, fireDate: fireDate, now: now, calendar: calendar)
            else { return nil }
            return DueScheduledOccurrence(kind: kind, fireDate: fireDate)
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    /// Returns whether a scheduled occurrence is eligible to run now.
    /// Occurrences in the future are not due, and occurrences at/before the
    /// current schedule's enable timestamp predate the user's opt-in.
    static func shouldRunScheduledOccurrence(
        schedule: ExportSchedule,
        kind: ScheduledExportKind = .completedDay,
        fireDate: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard schedule.isEnabled else { return false }
        guard fireDate <= now else { return false }

        if let enabledAt = schedule.enabledAt, fireDate <= enabledAt {
            return false
        }

        switch kind {
        case .completedDay:
            return true
        case .todayRefresh:
            guard schedule.todayRefreshEnabled else { return false }
            guard calendar.isDate(fireDate, inSameDayAs: now) else { return false }
            if let lastTodayRefreshDate = schedule.lastTodayRefreshDate, lastTodayRefreshDate >= fireDate {
                return false
            }
            return true
        }
    }

    /// Determine which dates need catch-up exports. Returns an array of dates
    /// (representing data days) that haven't been exported yet, bounded by:
    /// - The schedule's configured lookback window
    /// - The day after the last export's data day
    /// - Yesterday (today's data isn't complete yet)
    static func catchUpDatesNeeded(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }

        // Oldest date to look back to
        let lookbackDays = ExportSchedule.clampedLookbackDays(schedule.lookbackDays)
        guard let oldestDate = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return [] }

        // Determine the start of the catch-up range
        let startDate: Date
        if let lastExport = schedule.lastExportDate {
            // Last export ran on `lastExport` and exported data for the day before.
            // So the next data day to export is `lastExportDay` itself (the day the export ran).
            let lastExportDay = calendar.startOfDay(for: lastExport)

            // If we already exported yesterday's data (lastExportDay >= yesterday),
            // there's nothing to catch up.
            if lastExportDay >= yesterday {
                return []
            }

            // Start from the day after lastExportDay, bounded by the lookback window
            if let dayAfter = calendar.date(byAdding: .day, value: 1, to: lastExportDay) {
                startDate = max(dayAfter, oldestDate)
            } else {
                startDate = oldestDate
            }
        } else {
            startDate = oldestDate
        }

        // Build the list of dates from startDate through yesterday
        var dates: [Date] = []
        var current = startDate
        while current <= yesterday {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates
    }

    /// Returns the data days covered by one completed-day scheduled occurrence.
    /// The scheduled fire date is the run day, so the export window is the
    /// configured lookback ending with the prior calendar day.
    static func scheduledExportDates(
        schedule: ExportSchedule,
        fireDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        completedDayExportDates(schedule: schedule, fireDate: fireDate, calendar: calendar)
    }

    static func exportDates(
        for kind: ScheduledExportKind,
        schedule: ExportSchedule,
        fireDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        switch kind {
        case .completedDay:
            return completedDayExportDates(schedule: schedule, fireDate: fireDate, calendar: calendar)
        case .todayRefresh:
            return [calendar.startOfDay(for: fireDate)]
        }
    }

    /// Returns the scheduled occurrence that should be considered due at `now`.
    /// If today's preferred time has not arrived, this returns the previous
    /// frequency interval. BGTaskScheduler does not tell us the exact fire date,
    /// so this gives background and HealthKit triggers a stable occurrence key.
    static func latestScheduledOccurrenceDate(
        schedule: ExportSchedule,
        kind: ScheduledExportKind = .completedDay,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch kind {
        case .completedDay:
            return latestCompletedDayOccurrenceDate(schedule: schedule, now: now, calendar: calendar)
        case .todayRefresh:
            return latestTodayRefreshOccurrenceDate(schedule: schedule, now: now, calendar: calendar)
        }
    }

    private static func nextCompletedDayRunDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        var todayAtPreferred = calendar.dateComponents([.year, .month, .day], from: now)
        todayAtPreferred.hour = schedule.preferredHour
        todayAtPreferred.minute = schedule.preferredMinute
        todayAtPreferred.second = 0

        guard let scheduled = calendar.date(from: todayAtPreferred) else { return nil }

        if scheduled > now {
            return scheduled
        }

        // Preferred time already passed — advance by frequency
        switch schedule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: scheduled)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: scheduled)
        }
    }

    private static func nextTodayRefreshRunDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard schedule.isEnabled, schedule.todayRefreshEnabled else { return nil }

        let interval = ExportSchedule.clampedTodayRefreshIntervalHours(schedule.todayRefreshIntervalHours)
        let today = calendar.startOfDay(for: now)
        var hour = schedule.preferredHour

        while hour < 24 {
            var components = calendar.dateComponents([.year, .month, .day], from: today)
            components.hour = hour
            components.minute = schedule.preferredMinute
            components.second = 0
            if let candidate = calendar.date(from: components), candidate > now {
                return candidate
            }
            hour += interval
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        var tomorrowAtPreferred = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        tomorrowAtPreferred.hour = schedule.preferredHour
        tomorrowAtPreferred.minute = schedule.preferredMinute
        tomorrowAtPreferred.second = 0
        return calendar.date(from: tomorrowAtPreferred)
    }

    private static func completedDayExportDates(
        schedule: ExportSchedule,
        fireDate: Date,
        calendar: Calendar
    ) -> [Date] {
        let fireDay = calendar.startOfDay(for: fireDate)
        let lookbackDays = ExportSchedule.clampedLookbackDays(schedule.lookbackDays)

        guard let startDate = calendar.date(byAdding: .day, value: -lookbackDays, to: fireDay),
              let endDate = calendar.date(byAdding: .day, value: -1, to: fireDay)
        else {
            return []
        }

        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    private static func latestCompletedDayOccurrenceDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = schedule.preferredHour
        components.minute = schedule.preferredMinute
        components.second = 0

        guard let todayAtPreferredTime = calendar.date(from: components) else { return nil }

        if todayAtPreferredTime <= now {
            return todayAtPreferredTime
        }

        switch schedule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: -1, to: todayAtPreferredTime)
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: todayAtPreferredTime)
        }
    }

    private static func latestTodayRefreshOccurrenceDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard schedule.isEnabled, schedule.todayRefreshEnabled else { return nil }

        let interval = ExportSchedule.clampedTodayRefreshIntervalHours(schedule.todayRefreshIntervalHours)
        let today = calendar.startOfDay(for: now)
        var latest: Date?
        var hour = schedule.preferredHour

        while hour < 24 {
            var components = calendar.dateComponents([.year, .month, .day], from: today)
            components.hour = hour
            components.minute = schedule.preferredMinute
            components.second = 0
            if let candidate = calendar.date(from: components), candidate <= now {
                latest = candidate
            }
            hour += interval
        }

        return latest
    }
}
