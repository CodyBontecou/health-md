#if os(iOS)
import SwiftUI

/// One automation as the Archive sees it.
struct ArchiveProfile: Identifiable, Equatable {
    let id: UUID
    let name: String
    let destination: String
    let colorIndex: Int
    let entry: ScheduledExportEntry?
    /// Where this automation writes each date; nil falls back to `destination`.
    var outputPath: ArchiveOutputPath?
    /// When the current pause began, if the ledger recorded it.
    var pausedSince: Date?
    /// The automation's sentence, for the selected-automation card.
    var sentence: String?
    /// Its files sit in a folder this device can read (not on a Mac or an endpoint).
    var writesFilesOnDevice = false

    var isPaused: Bool { entry != nil && entry?.isEnabled == false }
    /// Has an enabled schedule; on-demand automations (no entry) are neither running nor paused.
    var isScheduled: Bool { entry?.isEnabled == true }
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

    /// The day row's path line: the dated file, the endpoint, or the destination.
    func pathLine(_ profile: ArchiveProfile, day: CoverageDay) -> String {
        profile.outputPath?.display(on: day.date, status: day.status) ?? profile.destination
    }

    /// The day row's action. "Open" needs the date's own file on this device, so
    /// endpoints, Mac folders and daily-note-only output offer none.
    func action(_ profile: ArchiveProfile, day: CoverageDay) -> ArchiveAggregation.DayRowAction? {
        guard let action = ArchiveAggregation.action(for: day.status, hasTodayRefresh: profile.hasTodayRefresh) else {
            return nil
        }
        if action.action == .open, !canOpen(profile, on: day.date) { return nil }
        return action
    }

    func canOpen(_ profile: ArchiveProfile, on date: Date) -> Bool {
        profile.writesFilesOnDevice && profile.outputPath?.relativeFilePath(on: date) != nil
    }

    func profileDays(on date: Date) -> [ArchiveAggregation.ProfileDay] {
        profiles.map { .init(profileID: $0.id, status: day($0, on: date).status) }
    }

    /// Missing dates among the last 7 completed days, under the "All" rules.
    var weeklyGapCount: Int {
        let today = calendar.startOfDay(for: now)
        return (1...7).filter { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return status(on: date, filter: nil) == .missing
        }.count
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
        ArchiveAggregation.stats(
            days: daysOfMonth(containing: month).map { ($0, status(on: $0, filter: filter)) },
            unit: statsUnit(filter: filter),
            today: now,
            calendar: calendar
        )
    }

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

    static func note(
        for day: CoverageDay,
        profile: ArchiveProfile,
        calendar: Calendar = .current
    ) -> String {
        if let refreshes = day.refreshes {
            let sent = String(localized: "\(refreshes.sent) of \(refreshes.attempted) refreshes sent")
            // A finished day that missed refreshes says why, e.g. "· API upload failed".
            guard refreshes.sent < refreshes.attempted, day.status != .inProgress,
                  let raw = day.record?.issueReason,
                  let reason = ExportFailureReason(rawValue: raw) else { return sent }
            return String(localized: "\(sent) · \(reason.shortDescription)")
        }
        if day.predatesHistory { return String(localized: "Before Health.md kept coverage history.") }
        if let weekly = weeklyNote(for: day, profile: profile, calendar: calendar) { return weekly }
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

    /// Weekly automations write one file per week: name the week, or the run that will cover it.
    static func weeklyNote(for day: CoverageDay, profile: ArchiveProfile, calendar: Calendar) -> String? {
        guard let entry = profile.entry, entry.frequency == .weekly else { return nil }
        switch day.status {
        case .notDue:
            // A short look-back leaves some weekdays to no file; those keep the plain note.
            guard let covered = ArchiveWeekly.coveredRange(
                for: day.date,
                isoWeekday: entry.weekday,
                lookbackDays: entry.lookbackDays,
                calendar: calendar
            ), covered.contains(calendar.startOfDay(for: day.date)) else { return nil }
            let weekday = ArchiveWeekly.weekdayName(isoWeekday: entry.weekday, calendar: calendar)
            return String(localized: "Not due — covered by \(weekday)’s file.")
        case .complete where day.record?.hadNoData != true:
            guard let range = ArchiveWeekly.coveredRange(
                for: day.date,
                isoWeekday: entry.weekday,
                lookbackDays: entry.lookbackDays,
                calendar: calendar
            ) else { return nil }
            let text = (range.lowerBound..<range.upperBound)
                .formatted(.interval.month(.abbreviated).day())
            return String(localized: "Week of \(text)")
        default:
            return nil
        }
    }

    /// "Mac archive is paused since Oct 22. Days while paused are not counted as gaps."
    static func pausedNote(_ profile: ArchiveProfile) -> String {
        guard let since = profile.pausedSince else {
            return String(localized: "\(profile.name) is paused. Days while paused are not counted as gaps.")
        }
        let date = since.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "\(profile.name) is paused since \(date). Days while paused are not counted as gaps.")
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
