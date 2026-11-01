#if os(iOS)
import SwiftUI

/// One automation as the Archive sees it.
struct ArchiveProfile: Identifiable, Equatable {
    let id: UUID
    let name: String
    let destination: String
    let colorIndex: Int
    let entry: ScheduledExportEntry?

    var isPaused: Bool { entry != nil && entry?.isEnabled == false }
    var hasTodayRefresh: Bool { entry?.todayRefreshEnabled == true }
    var isWeekly: Bool { entry?.frequency == .weekly }
}

/// A value snapshot of coverage for rendering. Views never run date math in `body`.
struct ArchiveModel {
    let profiles: [ArchiveProfile]
    let ledger: CoverageLedger
    let now: Date
    let calendar: Calendar
    var activeJobProfileID: UUID?

    func day(_ profile: ArchiveProfile, on date: Date) -> CoverageDay {
        CoverageProjection.day(
            for: date,
            input: CoverageProjection.Input(
                profileID: profile.id,
                entry: profile.entry,
                ledger: ledger,
                now: now,
                calendar: calendar,
                hasActiveJob: profile.id == activeJobProfileID
                    && calendar.isDate(date, inSameDayAs: now)
            )
        )
    }

    func profileDays(on date: Date) -> [ArchiveAggregation.ProfileDay] {
        profiles.map { .init(profileID: $0.id, status: day($0, on: date).status) }
    }

    /// The status of a date under a filter. `nil` means "All".
    func status(on date: Date, filter: UUID?) -> CoverageStatus {
        if let filter, let profile = profiles.first(where: { $0.id == filter }) {
            return day(profile, on: date).status
        }
        return ArchiveAggregation.aggregate(
            profileDays(on: date),
            isToday: calendar.isDate(date, inSameDayAs: now)
        )
    }

    func daysOfMonth(containing month: Date) -> [Date] {
        MonthCalendarGrid<EmptyView>.cells(month: month, calendar: calendar).compactMap { $0 }
    }

    func stats(month: Date, filter: UUID?) -> ArchiveAggregation.Stats {
        let unit = statsUnit(filter: filter)
        let monthStats = ArchiveAggregation.stats(
            days: daysOfMonth(containing: month).map { ($0, status(on: $0, filter: filter)) },
            unit: unit,
            today: now,
            calendar: calendar
        )
        // The streak may cross into earlier months, so it reads its own window.
        let window = (1...Self.streakWindowDays).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: now)
        }
        let streak = ArchiveAggregation.stats(
            days: window.map { ($0, status(on: $0, filter: filter)) },
            unit: unit,
            today: now,
            calendar: calendar
        ).streak
        return .init(
            archivedCount: monthStats.archivedCount,
            gapCount: monthStats.gapCount,
            earliestGap: monthStats.earliestGap,
            streak: streak
        )
    }

    func isWeeklyFilter(_ filter: UUID?) -> Bool {
        profiles.first { $0.id == filter }?.isWeekly == true
    }

    private static let streakWindowDays = 120

    private func statsUnit(filter: UUID?) -> ArchiveAggregation.StatsUnit {
        guard let entry = profiles.first(where: { $0.id == filter })?.entry,
              entry.frequency == .weekly,
              let fire = ScheduleDateMath.latestScheduledOccurrenceDate(
                schedule: entry.dateMathProjection,
                kind: .completedDay,
                now: now,
                calendar: calendar
              ) else { return .days }
        return .weeks(anchorFireDay: fire)
    }
}

/// Localized wording for coverage states.
enum ArchiveCopy {
    static func title(for status: CoverageStatus) -> String {
        switch status {
        case .complete: return String(localized: "Complete")
        case .partial: return String(localized: "Partial")
        case .missing: return String(localized: "Missing")
        case .notDue: return String(localized: "Not due")
        case .paused: return String(localized: "Paused")
        case .inProgress: return String(localized: "Updating")
        }
    }

    static func title(for action: ArchiveAggregation.DayAction) -> String {
        switch action {
        case .open: return String(localized: "Open")
        case .reExport: return String(localized: "Re-export")
        case .retry: return String(localized: "Retry")
        case .backfill: return String(localized: "Backfill")
        case .refresh: return String(localized: "Refresh")
        }
    }

    static func note(for day: CoverageDay, profile: ArchiveProfile) -> String {
        if let refreshes = day.refreshes {
            return String(localized: "\(refreshes.sent) of \(refreshes.attempted) refreshes sent")
        }
        if day.predatesHistory { return String(localized: "Before Health.md kept coverage history.") }
        switch day.status {
        case .paused: return String(localized: "Paused — not counted as a gap.")
        case .notDue: return String(localized: "Not due on this date.")
        case .inProgress: return String(localized: "Still updating today.")
        case .missing, .partial:
            if let raw = day.record?.issueReason, let reason = ExportFailureReason(rawValue: raw) {
                return reason.shortDescription
            }
            return day.status == .missing
                ? String(localized: "No export covered this date.")
                : String(localized: "Some data was skipped.")
        case .complete:
            if day.record?.hadNoData == true { return String(localized: "No data that day") }
            if let files = day.record?.filesWritten, day.record?.filesWrittenIsExact == true {
                return String(localized: "\(files) generated file(s)")
            }
            return String(localized: "Written")
        }
    }

    /// "October 19, missing; issues: Daily missing, Agent feed partial".
    static func tileAccessibility(
        date: Date,
        status: CoverageStatus,
        model: ArchiveModel,
        showsIssues: Bool
    ) -> String {
        let dateText = date.formatted(.dateTime.month(.wide).day())
        let statusText = title(for: status).lowercased()
        guard showsIssues else { return "\(dateText), \(statusText)" }
        let issues = model.profiles.compactMap { profile -> String? in
            let status = model.day(profile, on: date).status
            guard status == .missing || status == .partial else { return nil }
            return "\(profile.name) \(title(for: status).lowercased())"
        }
        guard !issues.isEmpty else { return "\(dateText), \(statusText)" }
        return String(localized: "\(dateText), \(statusText); issues: \(issues.joined(separator: ", "))")
    }
}
#endif
