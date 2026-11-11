import Foundation

/// What the running moment shows, derived from the export's progress callback. Pure.
struct ExportMomentProgress: Equatable {
    /// Days already written.
    let completed: Int
    let total: Int
    /// The day being written, when known.
    let currentDay: Date?

    /// The local exporter reports "Exporting yyyy-MM-dd... (done/total)". Other targets
    /// only report a fraction, so the counter falls back to the selected range.
    static func make(
        message: String,
        progress: Double,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> ExportMomentProgress {
        if let parsed = parse(message, calendar: calendar) {
            // A capture/transfer phase or an intermediate status message can run
            // ahead of overall progress. Never turn that into a full progress bar.
            let done = min(max(parsed.done, 0), completedDays(progress: progress, total: parsed.total))
            return ExportMomentProgress(completed: done, total: parsed.total, currentDay: parsed.day)
        }
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let total = max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)
        let done = completedDays(progress: progress, total: total)
        let current = done < total ? calendar.date(byAdding: .day, value: done, to: first) : nil
        return ExportMomentProgress(completed: done, total: total, currentDay: current)
    }

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    private static func completedDays(progress: Double, total: Int) -> Int {
        guard progress.isFinite else { return 0 }
        let fraction = min(max(progress, 0), 1)
        return fraction == 1 ? total : Int((fraction * Double(total)).rounded(.down))
    }

    private static func parse(_ message: String, calendar: Calendar) -> (day: Date?, done: Int, total: Int)? {
        guard message.hasPrefix("Exporting "),
              let open = message.lastIndex(of: "("),
              let close = message.lastIndex(of: ")"),
              open < close else { return nil }
        let counts = message[message.index(after: open)..<close].split(separator: "/")
        guard counts.count == 2, let done = Int(counts[0]), let total = Int(counts[1]), total > 0 else { return nil }
        let dayText = message.dropFirst("Exporting ".count).prefix(10)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.date(from: String(dayText)), done, total)
    }
}

/// The done line under the crystal: "Oct 24 – 30 · 14 files · daily notes updated".
enum ExportMomentSummary {
    static func title(_ entry: ExportHistoryEntry) -> String {
        entry.successCount == 1
            ? String(localized: "1 day written")
            : String(localized: "\(entry.successCount) days written")
    }

    static func subtitle(_ entry: ExportHistoryEntry) -> String {
        var parts = [rangeText(entry.dateRangeStart, entry.dateRangeEnd)]
        if let files = entry.fileCount {
            parts.append(files == 1 ? String(localized: "1 file") : String(localized: "\(files) files"))
        }
        if entry.dailyNoteUpdateCount > 0 {
            parts.append(String(localized: "daily notes updated"))
        }
        return parts.joined(separator: " · ")
    }

    static func rangeText(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.month(.abbreviated).day())
        }
        let lower = min(start, end)
        let upper = max(start, end)
        return (lower..<upper).formatted(.interval.month(.abbreviated).day())
    }
}
