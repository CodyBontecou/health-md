import Foundation

/// Archive calendar rules from `ArchiveGlass*` `renderVals()` and HANDOFF §3. Results are
/// enums and IDs, so the presentation layer owns every localized string.
enum ArchiveAggregation {
    static let maximumIssueDots = 3

    struct ProfileDay: Equatable {
        let profileID: UUID
        let status: CoverageStatus
    }

    struct IssueDot: Equatable {
        let profileID: UUID
        /// Filled for partial, hollow ring for missing.
        let isFilled: Bool
    }

    struct IssueDots: Equatable {
        let dots: [IssueDot]
        let hasOverflow: Bool
    }

    enum DayAction: Equatable {
        case open, reExport, retry, backfill, refresh
    }

    struct DayRowAction: Equatable {
        let action: DayAction
        /// Accent styling for actions that fix something.
        let isProminent: Bool
    }

    struct Stats: Equatable {
        let archivedCount: Int
        let gapCount: Int
        let earliestGap: Date?
        let streak: Int
    }

    enum StatsUnit {
        case days
        /// Groups days into schedule weeks, each ending on the day before `fireDay`.
        case weeks(anchorFireDay: Date)
    }

    // MARK: - "All"

    /// Over profiles due for the date: missing > partial > complete. Today is
    /// `inProgress`, and a date nothing was due on is `notDue`.
    static func aggregate(_ days: [ProfileDay], isToday: Bool) -> CoverageStatus {
        if isToday { return .inProgress }
        let due = days.map(\.status).filter(isDue)
        if due.isEmpty { return .notDue }
        if due.contains(.missing) { return .missing }
        if due.contains(.partial) { return .partial }
        return .complete
    }

    /// One dot per profile with trouble, capped, in the caller's profile order.
    static func issueDots(_ days: [ProfileDay]) -> IssueDots {
        let dots = days.compactMap { day -> IssueDot? in
            switch day.status {
            case .partial: return IssueDot(profileID: day.profileID, isFilled: true)
            case .missing: return IssueDot(profileID: day.profileID, isFilled: false)
            case .complete, .notDue, .paused, .inProgress: return nil
            }
        }
        return IssueDots(
            dots: Array(dots.prefix(maximumIssueDots)),
            hasOverflow: dots.count > maximumIssueDots
        )
    }

    /// "x of y on track" over due profiles. An update in progress counts as on track.
    static func onTrack(_ days: [ProfileDay]) -> (onTrack: Int, due: Int) {
        let due = days.map(\.status).filter(isDue)
        return (due.filter { $0 == .complete || $0 == .inProgress }.count, due.count)
    }

    static func action(for status: CoverageStatus, hasTodayRefresh: Bool) -> DayRowAction? {
        switch status {
        case .complete: return DayRowAction(action: .open, isProminent: false)
        case .partial: return DayRowAction(action: hasTodayRefresh ? .retry : .reExport, isProminent: true)
        case .missing: return DayRowAction(action: .backfill, isProminent: true)
        case .inProgress: return DayRowAction(action: .refresh, isProminent: false)
        case .notDue, .paused: return nil
        }
    }

    // MARK: - Stats

    /// Days archived = complete + partial. The streak runs back from the latest past
    /// date, skips not-due and paused dates, and stops at the first gap. Today is excluded.
    static func stats(
        days: [(date: Date, status: CoverageStatus)],
        unit: StatsUnit = .days,
        today: Date,
        calendar: Calendar
    ) -> Stats {
        let todayStart = calendar.startOfDay(for: today)
        let past = days.filter { calendar.startOfDay(for: $0.date) < todayStart }
        let periods: [(date: Date, status: CoverageStatus)]
        switch unit {
        case .days:
            periods = past
        case .weeks(let anchorFireDay):
            periods = weekPeriods(past, anchorFireDay: anchorFireDay, calendar: calendar)
        }

        var archived = 0
        var gaps = 0
        var earliestGap: Date?
        var streak = 0
        var streakIsOpen = true

        for period in periods.sorted(by: { $0.date > $1.date }) {
            switch period.status {
            case .complete, .partial:
                archived += 1
                if streakIsOpen { streak += 1 }
            case .missing:
                gaps += 1
                streakIsOpen = false
                earliestGap = period.date
            case .notDue, .paused, .inProgress:
                break
            }
        }
        return Stats(archivedCount: archived, gapCount: gaps, earliestGap: earliestGap, streak: streak)
    }

    private static func isDue(_ status: CoverageStatus) -> Bool {
        status != .notDue && status != .paused
    }

    /// Rolls days into one status per schedule week. The worst due status wins, and a
    /// week's date is its earliest missing day, so a gap tap lands on a real gap.
    private static func weekPeriods(
        _ days: [(date: Date, status: CoverageStatus)],
        anchorFireDay: Date,
        calendar: Calendar
    ) -> [(date: Date, status: CoverageStatus)] {
        let anchor = calendar.startOfDay(for: anchorFireDay)
        let grouped = Dictionary(grouping: days) { day -> Int in
            let elapsed = calendar.dateComponents(
                [.day],
                from: anchor,
                to: calendar.startOfDay(for: day.date)
            ).day ?? 0
            return Int((Double(elapsed) / 7).rounded(.down))
        }
        return grouped.values.map { week in
            let status = aggregate(
                week.map { ProfileDay(profileID: UUID(), status: $0.status) },
                isToday: false
            )
            let dates = status == .missing
                ? week.filter { $0.status == .missing }.map(\.date)
                : week.map(\.date)
            return (dates.min() ?? anchor, status)
        }
    }
}
