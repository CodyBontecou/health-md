#if DEBUG
import Foundation

/// App Store screenshot coverage (UI tests only, never shipped).
///
/// The boards (`ArchiveGlassDark`, `ArchiveGlassFeed`, `iPadArchiveG`, `DuoInnerArchiveG`)
/// show one finished month with gaps, partial days and a pause. Captures open the month
/// before the current one, so the pattern is keyed to that month's day numbers and never
/// depends on today's date. Days of the current month up to yesterday are written in full,
/// which keeps recent coverage and the widget populated. Every day number used is at most 28, so the pattern
/// fits every month.
enum CoverageScreenshotFixture {
    /// How one automation behaves on the boards, read from its schedule entry.
    enum Kind: Equatable {
        case daily
        case weekly
        case feed
        case paused

        init(entry: ScheduledExportEntry?) {
            guard let entry else { self = .daily; return }
            if !entry.isEnabled { self = .paused }
            else if entry.todayRefreshEnabled { self = .feed }
            else if entry.frequency == .weekly { self = .weekly }
            else { self = .daily }
        }
    }

    /// Board day numbers in the shown month.
    static let dailyMissingDays: Set<Int> = [19, 20]
    static let dailyPartialDays: Set<Int> = [12, 26]
    static let pausedFromDay = 22
    /// The fixture feed refreshes every 3 hours (the closest real option to the board's 2).
    static let feedAttemptsPerDay = 8
    /// Refreshes sent on the days the endpoint failed; other days send all of them.
    static let feedSentByDay: [Int: Int] = [7: 6, 15: 0, 19: 7, 23: 7]

    /// The first day of the month the captures show.
    static func shownMonthStart(now: Date, calendar: Calendar) -> Date? {
        guard let currentMonth = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        return calendar.date(byAdding: .month, value: -1, to: currentMonth)
    }

    static func ledger(profiles: [(id: UUID, kind: Kind)], now: Date, calendar: Calendar) -> CoverageLedger? {
        guard !profiles.isEmpty,
              let start = shownMonthStart(now: now, calendar: calendar),
              let currentMonth = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        let today = calendar.startOfDay(for: now)
        var ledger = CoverageLedger(startedAt: start)
        ledger.didSeedFromHistory = true

        var date = start
        while date < today {
            let shown = date < currentMonth
            let day = calendar.component(.day, from: date)
            let key = CoverageDateKey.key(for: date, calendar: calendar)
            for profile in profiles {
                guard let record = record(kind: profile.kind, day: shown ? day : nil, date: date) else { continue }
                ledger.profiles[profile.id, default: [:]][key] = record
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        for profile in profiles where profile.kind == .paused {
            guard let pausedAt = calendar.date(byAdding: .day, value: pausedFromDay - 1, to: start) else { continue }
            ledger.scheduleEvents[profile.id] = [CoverageScheduleEvent(date: pausedAt, isEnabled: false)]
        }
        return ledger
    }

    /// The record one automation keeps for a date. `day` is nil outside the shown month,
    /// where every active automation wrote in full.
    static func record(kind: Kind, day: Int?, date: Date) -> CoverageDateRecord? {
        var record = CoverageDateRecord(updatedAt: date)
        record.lastWriter = .schedule
        switch kind {
        case .paused:
            // Paused days keep no record, so the projection shows them as paused.
            guard let day, day < pausedFromDay else { return nil }
            record.settledOutcome = .complete
            record.filesWritten = 1
            record.filesWrittenIsExact = true
        case .weekly:
            // The weekly run writes every date of its week.
            record.settledOutcome = .complete
            record.filesWritten = 1
        case .daily:
            if let day, dailyMissingDays.contains(day) {
                record.settledOutcome = .failed
                record.issueReason = ExportFailureReason.backgroundTaskExpired.rawValue
            } else if let day, dailyPartialDays.contains(day) {
                record.settledOutcome = .partial
                record.filesWritten = 1
                record.filesWrittenIsExact = true
            } else {
                record.settledOutcome = .complete
                record.filesWritten = 1
                record.filesWrittenIsExact = true
            }
        case .feed:
            let sent = day.flatMap { feedSentByDay[$0] } ?? feedAttemptsPerDay
            record.sameDayAttempts = feedAttemptsPerDay
            record.sameDaySuccesses = sent
            record.sameDayOutcome = sent == 0 ? .failed : (sent < feedAttemptsPerDay ? .partial : .complete)
            if sent < feedAttemptsPerDay {
                record.issueReason = ExportFailureReason.apiUploadFailed.rawValue
            }
        }
        return record
    }
}
#endif
