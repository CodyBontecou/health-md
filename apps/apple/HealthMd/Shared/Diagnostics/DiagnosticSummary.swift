import Foundation

/// A short, non-PHI digest of recorded diagnostics for a feedback report: counts and
/// the event IDs of recent warnings/errors. Event fields are never included, so no
/// peer names, paths, endpoints, credentials or health values can appear.
nonisolated enum DiagnosticSummary {
    static let windowHours = 24
    static let recentIssueLimit = 10

    static func text(events: [DiagnosticEvent], recordingEnabled: Bool) -> String {
        let warnings = events.filter { $0.severity == "warning" }
        let errors = events.filter { $0.severity == "error" }
        var lines = [
            "--- Diagnostics summary (last \(windowHours) hours) ---",
            "Recording: \(recordingEnabled ? "on" : "off")",
            "Events: \(events.count) · warnings: \(warnings.count) · errors: \(errors.count)"
        ]
        let issues = events
            .filter { DiagnosticEventDisplay.needsAttention($0.severity) }
            .suffix(recentIssueLimit)
        if !issues.isEmpty {
            lines.append("Recent warnings and errors:")
            lines += issues.map {
                "\($0.timestamp) \(DiagnosticEventDisplay.severityLabel($0.severity)) \($0.event_id.rawValue)"
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Reads the recorder without private context. Call off the main thread.
    static func current(now: Date = Date()) -> String {
        let recorder = DiagnosticRecorder.shared
        let snapshot = recorder.snapshot(
            includePrivate: false,
            since: now.addingTimeInterval(-Double(windowHours) * 3600)
        )
        return text(events: snapshot.events, recordingEnabled: recorder.settings.enabled)
    }
}
