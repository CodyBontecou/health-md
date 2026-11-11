import Foundation

/// Display-only copy for ScheduleG. Never changes stored intervals or dates.
enum ScheduleSheetCopy {
    /// Compact chip title for a Today Refresh interval ("30 min", "1 hr", "3 hr"),
    /// formatted by the locale. VoiceOver reads `ExportSchedule.todayRefreshLabel` instead.
    static func refreshChipTitle(minutes: Int, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = minutes < 60 ? [.minute] : [.hour]
        return formatter.string(from: TimeInterval(minutes * 60))
            ?? ExportSchedule.todayRefreshLabel(minutes)
    }

    /// A stepper value such as "3 days", "1 week" or "2 months", pluralized by the locale.
    static func count(_ count: Int, unit: ScheduleIntervalUnit, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        var components = DateComponents()
        switch unit {
        case .day:
            formatter.allowedUnits = [.day]
            components.day = count
        case .week:
            formatter.allowedUnits = [.weekOfMonth]
            components.weekOfMonth = count
        case .month:
            formatter.allowedUnits = [.month]
            components.month = count
        }
        return formatter.string(from: components) ?? "\(count)"
    }

    /// The span of days a pending recovery still holds: "Oct 19", "Oct 19 – 20",
    /// "Sep 30 – Oct 2". The year appears only when the span leaves `now`'s year.
    /// Nil when there are no dates.
    static func pendingRecoveryRange(
        _ dates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        let currentYear = calendar.component(.year, from: now)
        let sameYear = calendar.component(.year, from: start) == currentYear
            && calendar.component(.year, from: end) == currentYear
        let template = sameYear ? "MMMd" : "yMMMd"

        if start == end {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: start)
        }
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateTemplate = template
        return formatter.string(from: start, to: end)
    }

    /// The pending-recovery card body, naming the waiting days when they are known.
    static func pendingRecoveryMessage(range: String?) -> String {
        if let range {
            return String(localized: "A recovery for \(range) is waiting. Discarding keeps your profile, credentials, history and completed files; the schedule resumes at its next run.")
        }
        return String(localized: "A scheduled recovery is waiting. Discarding keeps your profile, credentials, history and completed files; the schedule resumes at its next run.")
    }
}
