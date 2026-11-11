import Foundation

/// Short "last export" wording for the Mac boards (MacMenuBarG, MacHomeG):
/// "Today 11:02 PM · Oct 30 · 1 file".
enum ExportHistorySummaryFormat {
    /// "Today 11:02 PM", "Yesterday 9:15 AM", or "Oct 21, 9:15 AM" for older exports.
    static func when(_ timestamp: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = timeFormatter(calendar: calendar, locale: locale).string(from: timestamp)
        if calendar.isDate(timestamp, inSameDayAs: now) {
            return String(localized: "Today \(time)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(timestamp, inSameDayAs: yesterday) {
            return String(localized: "Yesterday \(time)")
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        return formatter.string(from: timestamp)
    }

    /// MacHomeG activity column: the time for today, "Yesterday", otherwise "Oct 21".
    static func shortWhen(_ timestamp: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(timestamp, inSameDayAs: now) {
            return timeFormatter(calendar: calendar, locale: locale).string(from: timestamp)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(timestamp, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return dateRange(start: timestamp, end: timestamp, calendar: calendar, locale: locale)
    }

    /// "Oct 30" for one day, "Oct 24 – 30" for a range.
    static func dateRange(start: Date, end: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let lower = min(start, end)
        let upper = max(start, end)
        if calendar.isDate(lower, inSameDayAs: upper) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: lower)
        }
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateTemplate = "MMMd"
        return formatter.string(from: lower, to: upper)
    }

    /// "1 file" / "3 files"; `nil` when the count is unknown.
    static func files(_ count: Int?) -> String? {
        guard let count else { return nil }
        return count == 1 ? String(localized: "1 file") : String(localized: "\(count) files")
    }

    /// Joins the non-empty parts with " · ".
    static func line(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func timeFormatter(calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

extension ExportHistoryEntry {
    /// MacMenuBarG's "Last export" value: when, the exported days and the file count.
    var lastExportMenuLine: String {
        ExportHistorySummaryFormat.line(
            ExportHistorySummaryFormat.when(timestamp),
            ExportHistorySummaryFormat.dateRange(start: dateRangeStart, end: dateRangeEnd),
            isFullSuccess ? ExportHistorySummaryFormat.files(fileCount) : localizedStatusDescription
        )
    }
}

extension ExportHistoryEntry {
    /// MacHomeG's "Last export" value: when and the file count.
    var lastExportHomeLine: String {
        ExportHistorySummaryFormat.line(
            ExportHistorySummaryFormat.when(timestamp),
            isFullSuccess ? ExportHistorySummaryFormat.files(fileCount) : localizedStatusDescription
        )
    }
}

extension SyncEvent {
    /// MacHomeG activity text: "Received Oct 30 from iPhone · 1 file" for a written export,
    /// otherwise the event summary with its days and device.
    var activityLine: String {
        let range: String? = {
            guard let dateRangeStart, let dateRangeEnd else { return nil }
            return ExportHistorySummaryFormat.dateRange(start: dateRangeStart, end: dateRangeEnd)
        }()
        switch kind {
        case .macExportSucceeded:
            let received = range.map { String(localized: "Received \($0) from \(peerName)") }
                ?? String(localized: "Received from \(peerName)")
            let files = recordCountIsLowerBound == true ? nil : ExportHistorySummaryFormat.files(recordCount)
            return ExportHistorySummaryFormat.line(received, files)
        default:
            return ExportHistorySummaryFormat.line(summaryDescription, range, peerName)
        }
    }
}

extension ExportHistorySummaryFormat {
    /// MacHistoryG row: "Oct 30 · 11:02 PM".
    static func historyWhen(_ timestamp: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        line(
            dateRange(start: timestamp, end: timestamp, calendar: calendar, locale: locale),
            timeFormatter(calendar: calendar, locale: locale).string(from: timestamp)
        )
    }

    /// "1 date failed" / "2 dates failed".
    static func failedDates(_ count: Int) -> String {
        count == 1 ? String(localized: "1 date failed") : String(localized: "\(count) dates failed")
    }
}

extension ExportHistoryEntry {
    /// MacHistoryG status: "Complete", "2 dates failed" when failed dates were recorded,
    /// otherwise the short partial/failed status.
    var historyStatusLine: String {
        if isFullSuccess { return String(localized: "Complete") }
        if !failedDateDetails.isEmpty {
            return ExportHistorySummaryFormat.failedDates(failedDateDetails.count)
        }
        return localizedShortStatusDescription
    }

    /// MacHistoryG detail title: "Oct 22 · 2 dates failed".
    func historyDetailTitle(calendar: Calendar = .current, locale: Locale = .current) -> String {
        ExportHistorySummaryFormat.line(
            ExportHistorySummaryFormat.dateRange(start: timestamp, end: timestamp, calendar: calendar, locale: locale),
            historyStatusLine
        )
    }

    /// MacHistoryG failed dates on one line: "2026-10-20 · 2026-10-21".
    var failedDatesLine: String? {
        let dates = failedDateDetails.map(\.dateString)
        return dates.isEmpty ? nil : dates.joined(separator: " · ")
    }
}
