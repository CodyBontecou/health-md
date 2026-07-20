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
            return isCompletedDayOccurrence(
                schedule: schedule,
                fireDate: fireDate,
                calendar: calendar
            )
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
        if schedule.frequency == .custom {
            return nextCustomCompletedDayRunDate(schedule: schedule, now: now, calendar: calendar)
        }
        if schedule.frequency == .weekly {
            return nextWeeklyCompletedDayRunDate(schedule: schedule, now: now, calendar: calendar)
        }

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
        case .weekly, .custom:
            return nil
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
        if schedule.frequency == .custom {
            return latestCustomCompletedDayOccurrenceDate(schedule: schedule, now: now, calendar: calendar)
        }
        if schedule.frequency == .weekly {
            return latestWeeklyCompletedDayOccurrenceDate(schedule: schedule, now: now, calendar: calendar)
        }

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
        case .weekly, .custom:
            return nil
        }
    }

    private static func nextWeeklyCompletedDayRunDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        let currentWeekday = isoWeekday(for: today, calendar: calendar)
        let targetWeekday = clampedISOWeekday(schedule.weekday)
        var daysForward = (targetWeekday - currentWeekday + 7) % 7

        guard var candidateDay = calendar.date(byAdding: .day, value: daysForward, to: today),
              var candidate = preferredTime(on: candidateDay, schedule: schedule, calendar: calendar)
        else { return nil }

        if candidate <= now {
            daysForward += 7
            guard let nextDay = calendar.date(byAdding: .day, value: daysForward, to: today),
                  let next = preferredTime(on: nextDay, schedule: schedule, calendar: calendar)
            else { return nil }
            candidateDay = nextDay
            candidate = next
        }

        return candidateDay >= today ? candidate : nil
    }

    private static func latestWeeklyCompletedDayOccurrenceDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        let currentWeekday = isoWeekday(for: today, calendar: calendar)
        let targetWeekday = clampedISOWeekday(schedule.weekday)
        var daysBackward = (currentWeekday - targetWeekday + 7) % 7

        guard var candidateDay = calendar.date(byAdding: .day, value: -daysBackward, to: today),
              var candidate = preferredTime(on: candidateDay, schedule: schedule, calendar: calendar)
        else { return nil }

        if candidate > now {
            daysBackward += 7
            guard let previousDay = calendar.date(byAdding: .day, value: -daysBackward, to: today),
                  let previous = preferredTime(on: previousDay, schedule: schedule, calendar: calendar)
            else { return nil }
            candidateDay = previousDay
            candidate = previous
        }

        return candidateDay <= today ? candidate : nil
    }

    private static func nextCustomCompletedDayRunDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let interval = ExportSchedule.clampedCustomInterval(schedule.customInterval)

        switch schedule.customUnit {
        case .day, .week:
            let dayStride = interval * (schedule.customUnit == .week ? 7 : 1)
            let anchorDay = calendar.startOfDay(for: schedule.customAnchorDate)
            let today = calendar.startOfDay(for: now)

            let candidateDay: Date
            if today < anchorDay {
                candidateDay = anchorDay
            } else {
                let elapsedDays = calendar.dateComponents([.day], from: anchorDay, to: today).day ?? 0
                let elapsedIntervals = elapsedDays / dayStride
                guard let day = calendar.date(
                    byAdding: .day,
                    value: elapsedIntervals * dayStride,
                    to: anchorDay
                ) else { return nil }
                candidateDay = day
            }

            guard let candidate = preferredTime(on: candidateDay, schedule: schedule, calendar: calendar) else {
                return nil
            }
            if candidate > now { return candidate }

            guard let nextDay = calendar.date(byAdding: .day, value: dayStride, to: candidateDay) else {
                return nil
            }
            return preferredTime(on: nextDay, schedule: schedule, calendar: calendar)

        case .month:
            guard let anchorMonth = startOfMonth(for: schedule.customAnchorDate, calendar: calendar),
                  let currentMonth = startOfMonth(for: now, calendar: calendar)
            else { return nil }

            let elapsedMonths = calendar.dateComponents([.month], from: anchorMonth, to: currentMonth).month ?? 0
            let candidateOffset = elapsedMonths < 0 ? 0 : (elapsedMonths / interval) * interval
            guard let candidate = customMonthOccurrence(
                schedule: schedule,
                monthOffset: candidateOffset,
                calendar: calendar
            ) else { return nil }

            if candidate > now { return candidate }
            return customMonthOccurrence(
                schedule: schedule,
                monthOffset: candidateOffset + interval,
                calendar: calendar
            )
        }
    }

    private static func latestCustomCompletedDayOccurrenceDate(
        schedule: ExportSchedule,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let interval = ExportSchedule.clampedCustomInterval(schedule.customInterval)

        switch schedule.customUnit {
        case .day, .week:
            let dayStride = interval * (schedule.customUnit == .week ? 7 : 1)
            let anchorDay = calendar.startOfDay(for: schedule.customAnchorDate)
            let today = calendar.startOfDay(for: now)
            guard today >= anchorDay else { return nil }

            let elapsedDays = calendar.dateComponents([.day], from: anchorDay, to: today).day ?? 0
            var offset = (elapsedDays / dayStride) * dayStride
            guard var candidateDay = calendar.date(byAdding: .day, value: offset, to: anchorDay),
                  var candidate = preferredTime(on: candidateDay, schedule: schedule, calendar: calendar)
            else { return nil }

            if candidate > now {
                offset -= dayStride
                guard offset >= 0,
                      let previousDay = calendar.date(byAdding: .day, value: offset, to: anchorDay),
                      let previous = preferredTime(on: previousDay, schedule: schedule, calendar: calendar)
                else { return nil }
                candidateDay = previousDay
                candidate = previous
            }

            return candidateDay >= anchorDay ? candidate : nil

        case .month:
            guard let anchorMonth = startOfMonth(for: schedule.customAnchorDate, calendar: calendar),
                  let currentMonth = startOfMonth(for: now, calendar: calendar)
            else { return nil }

            let elapsedMonths = calendar.dateComponents([.month], from: anchorMonth, to: currentMonth).month ?? 0
            guard elapsedMonths >= 0 else { return nil }

            var candidateOffset = (elapsedMonths / interval) * interval
            guard var candidate = customMonthOccurrence(
                schedule: schedule,
                monthOffset: candidateOffset,
                calendar: calendar
            ) else { return nil }

            if candidate > now {
                candidateOffset -= interval
                guard candidateOffset >= 0,
                      let previous = customMonthOccurrence(
                        schedule: schedule,
                        monthOffset: candidateOffset,
                        calendar: calendar
                      )
                else { return nil }
                candidate = previous
            }

            return candidate
        }
    }

    private static func isCompletedDayOccurrence(
        schedule: ExportSchedule,
        fireDate: Date,
        calendar: Calendar
    ) -> Bool {
        switch schedule.frequency {
        case .daily:
            return true
        case .weekly:
            return isoWeekday(for: fireDate, calendar: calendar) == clampedISOWeekday(schedule.weekday)
        case .custom:
            break
        }

        let interval = ExportSchedule.clampedCustomInterval(schedule.customInterval)
        let anchorDay = calendar.startOfDay(for: schedule.customAnchorDate)
        let fireDay = calendar.startOfDay(for: fireDate)
        guard fireDay >= anchorDay else { return false }

        switch schedule.customUnit {
        case .day, .week:
            let dayStride = interval * (schedule.customUnit == .week ? 7 : 1)
            guard let elapsedDays = calendar.dateComponents([.day], from: anchorDay, to: fireDay).day else {
                return false
            }
            return elapsedDays.isMultiple(of: dayStride)

        case .month:
            guard let anchorMonth = startOfMonth(for: anchorDay, calendar: calendar),
                  let fireMonth = startOfMonth(for: fireDay, calendar: calendar),
                  let elapsedMonths = calendar.dateComponents([.month], from: anchorMonth, to: fireMonth).month,
                  elapsedMonths >= 0,
                  elapsedMonths.isMultiple(of: interval),
                  let occurrence = customMonthOccurrence(
                    schedule: schedule,
                    monthOffset: elapsedMonths,
                    calendar: calendar
                  )
            else { return false }
            return calendar.isDate(occurrence, inSameDayAs: fireDate)
        }
    }

    private static func clampedISOWeekday(_ weekday: Int) -> Int {
        min(max(weekday, 1), 7)
    }

    private static func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        let calendarWeekday = calendar.component(.weekday, from: date)
        return calendarWeekday == 1 ? 7 : calendarWeekday - 1
    }

    private static func customMonthOccurrence(
        schedule: ExportSchedule,
        monthOffset: Int,
        calendar: Calendar
    ) -> Date? {
        guard monthOffset >= 0,
              let anchorMonth = startOfMonth(for: schedule.customAnchorDate, calendar: calendar),
              let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: anchorMonth),
              let validDays = calendar.range(of: .day, in: .month, for: targetMonth)
        else { return nil }

        let anchorDay = calendar.component(.day, from: schedule.customAnchorDate)
        let targetDay = min(anchorDay, validDays.count)
        var components = calendar.dateComponents([.era, .year, .month], from: targetMonth)
        components.day = targetDay
        components.hour = schedule.preferredHour
        components.minute = schedule.preferredMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.era, .year, .month], from: date)
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private static func preferredTime(
        on day: Date,
        schedule: ExportSchedule,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.hour = schedule.preferredHour
        components.minute = schedule.preferredMinute
        components.second = 0
        return calendar.date(from: components)
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
