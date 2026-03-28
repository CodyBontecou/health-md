import Foundation

/// Pure date-math utilities extracted from SchedulingManager (iOS+macOS).
/// Stateless and deterministic — all external state is passed in.
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

    /// Determine which dates need catch-up exports. Returns an array of dates
    /// (representing data days) that haven't been exported yet, bounded by:
    /// - The lookback window (1 day for daily, 7 for weekly)
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
        let lookbackDays = schedule.frequency == .weekly ? 7 : 1
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
}
