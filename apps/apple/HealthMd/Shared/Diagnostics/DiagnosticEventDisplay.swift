import Foundation

/// Compact one-line presentation of a recorded event for the Diagnostics event list.
/// Shows only what the event already carries after filtering; adds nothing.
nonisolated enum DiagnosticEventDisplay {
    /// Fixed-width severity tag, e.g. `INFO`, `WARN`.
    static func severityLabel(_ severity: String) -> String {
        switch severity {
        case "warning": return "WARN"
        case "error": return "ERROR"
        default: return severity.uppercased()
        }
    }

    /// Warnings and errors are tinted so they stand out in the list.
    static func needsAttention(_ severity: String) -> Bool {
        severity == "warning" || severity == "error"
    }

    /// `event.id key=value …` with fields in a stable (sorted) order.
    static func summary(eventID: String, fields: [String: DiagnosticValue]) -> String {
        let parts = fields.keys.sorted().compactMap { key -> String? in
            switch fields[key] {
            case .text(let value): return "\(key)=\(value)"
            case .integer(let value): return "\(key)=\(value)"
            case .boolean(let value): return "\(key)=\(value)"
            case .invalid, .none: return nil
            }
        }
        return ([eventID] + parts).joined(separator: " ")
    }

    /// Time of day for events from today, otherwise the short date.
    static func timeLabel(_ timestamp: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = DiagnosticRecorder.parseTimestamp(timestamp) else { return "—" }
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone))
        }
        return date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
    }
}
