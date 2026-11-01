import Foundation

/// One date resolved for one profile.
struct CoverageDay: Equatable {
    let date: Date
    let status: CoverageStatus
    let record: CoverageDateRecord?
    /// Due by cadence but older than any known history, so it is not a gap.
    var predatesHistory = false
    /// `k of n refreshes sent`, for profiles with Today Refresh. `n` counts recorded attempts.
    var refreshes: (sent: Int, attempted: Int)?

    static func == (lhs: CoverageDay, rhs: CoverageDay) -> Bool {
        lhs.date == rhs.date && lhs.status == rhs.status && lhs.record == rhs.record
            && lhs.predatesHistory == rhs.predatesHistory
            && lhs.refreshes?.sent == rhs.refreshes?.sent
            && lhs.refreshes?.attempted == rhs.refreshes?.attempted
    }
}

/// Pure projection: ledger + schedule + clock → status per date.
enum CoverageProjection {
    struct Input {
        let profileID: UUID
        let entry: ScheduledExportEntry?
        let ledger: CoverageLedger
        let now: Date
        let calendar: Calendar
        var hasActiveJob = false
    }

    static func day(for date: Date, input: Input) -> CoverageDay {
        let calendar = input.calendar
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: input.now)
        let key = CoverageDateKey.key(for: day, calendar: calendar)
        let record = input.ledger.profiles[input.profileID]?[key]
        let events = input.ledger.scheduleEvents[input.profileID] ?? []
        let isPaused = isPaused(on: day, events: events, calendar: calendar)
        let feedRefreshes = refreshCounts(record: record, entry: input.entry)

        func result(_ status: CoverageStatus, predatesHistory: Bool = false) -> CoverageDay {
            CoverageDay(
                date: day,
                status: status,
                record: record,
                predatesHistory: predatesHistory,
                refreshes: feedRefreshes
            )
        }

        guard day <= today else { return result(.notDue) }

        if day == today {
            if input.hasActiveJob { return result(.inProgress) }
            if isPaused { return result(.paused) }
            if let entry = input.entry, entry.isEnabled,
               entry.todayRefreshEnabled || entry.frequency == .daily {
                return result(.inProgress)
            }
        }

        // Written output always shows, including a manual export during a pause.
        if let outcome = writtenOutcome(record: record, entry: input.entry), outcome > .failed {
            return result(outcome == .complete ? .complete : .partial)
        }
        if isPaused { return result(.paused) }
        if day == today { return result(.notDue) }
        if record?.bestOutcome == .failed { return result(.missing) }

        guard let entry = input.entry,
              hasFiredOccurrence(covering: day, entry: entry, events: events, input: input) else {
            return result(.notDue)
        }

        return day < historyStart(for: input)
            ? result(.notDue, predatesHistory: true)
            : result(.missing)
    }

    static func days(from start: Date, through end: Date, input: Input) -> [CoverageDay] {
        var days: [CoverageDay] = []
        var current = input.calendar.startOfDay(for: start)
        let last = input.calendar.startOfDay(for: end)
        while current <= last {
            days.append(day(for: current, input: input))
            guard let next = input.calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    // MARK: - Rules

    /// With Today Refresh, a date is judged on how many refreshes landed, unless a
    /// later run wrote it in full. Without it, any complete run covers the date.
    private static func writtenOutcome(
        record: CoverageDateRecord?,
        entry: ScheduledExportEntry?
    ) -> CoverageOutcome? {
        guard let record else { return nil }
        guard entry?.todayRefreshEnabled == true,
              record.sameDayAttempts > 0,
              record.settledOutcome != .complete else {
            return record.bestOutcome
        }
        if record.sameDaySuccesses == 0 { return record.settledOutcome ?? .failed }
        return record.sameDaySuccesses < record.sameDayAttempts ? .partial : .complete
    }

    private static func refreshCounts(
        record: CoverageDateRecord?,
        entry: ScheduledExportEntry?
    ) -> (sent: Int, attempted: Int)? {
        guard entry?.todayRefreshEnabled == true,
              let record, record.sameDayAttempts > 0 else { return nil }
        return (record.sameDaySuccesses, record.sameDayAttempts)
    }

    private static func isPaused(
        on day: Date,
        events: [CoverageScheduleEvent],
        calendar: Calendar
    ) -> Bool {
        events.last { calendar.startOfDay(for: $0.date) <= day }?.isEnabled == false
    }

    /// True when a completed-day occurrence that covers `day` has fired while the
    /// schedule was enabled. Until then the date is `notDue`, which also covers the
    /// days of a week whose run has not happened yet.
    private static func hasFiredOccurrence(
        covering day: Date,
        entry: ScheduledExportEntry,
        events: [CoverageScheduleEvent],
        input: Input
    ) -> Bool {
        let calendar = input.calendar
        var schedule = entry.dateMathProjection
        // Assignment order matters: enabling stamps `enabledAt`. The timeline below
        // decides enablement, and only cadence is asked of the date math.
        schedule.isEnabled = true
        schedule.enabledAt = nil

        let lookback = ExportSchedule.clampedLookbackDays(schedule.lookbackDays)
        guard lookback > 0 else { return false }
        for offset in 1...lookback {
            guard let fireDay = calendar.date(byAdding: .day, value: offset, to: day),
                  let fireDate = calendar.date(
                    bySettingHour: entry.preferredHour,
                    minute: entry.preferredMinute,
                    second: 0,
                    of: fireDay
                  ) else { continue }
            guard fireDate <= input.now else { return false }
            if wasEnabled(at: fireDate, entry: entry, events: events),
               ScheduleDateMath.shouldRunScheduledOccurrence(
                schedule: schedule,
                kind: .completedDay,
                fireDate: fireDate,
                now: input.now,
                calendar: calendar
               ) {
                return true
            }
        }
        return false
    }

    private static func wasEnabled(
        at date: Date,
        entry: ScheduledExportEntry,
        events: [CoverageScheduleEvent]
    ) -> Bool {
        if entry.isEnabled, let enabledAt = entry.enabledAt, date > enabledAt { return true }
        if let last = events.last(where: { $0.date <= date }) { return last.isEnabled }
        // Before the first event the schedule held the opposite state.
        if let first = events.first { return !first.isEnabled }
        return entry.isEnabled && entry.enabledAt == nil
    }

    private static func historyStart(for input: Input) -> Date {
        let calendar = input.calendar
        let started = calendar.startOfDay(for: input.ledger.startedAt)
        guard let earliestKey = input.ledger.profiles[input.profileID]?.keys.min() else {
            return started
        }
        return min(started, date(fromKey: earliestKey, calendar: calendar) ?? started)
    }

    private static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
