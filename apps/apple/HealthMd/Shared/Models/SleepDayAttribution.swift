//
//  SleepDayAttribution.swift
//  Health.md
//
//  Issue #104: which daily note owns a sleep session that spans midnight.
//

import Foundation

/// Which daily note owns a sleep session.
///
/// Shared cross-platform setting (issue #104). Both platforms persist the same
/// raw values, default to `nightBegins`, and keep the whole session in a single
/// note; only the owning calendar date differs.
///
/// - `nightBegins`: the note for the calendar date the session starts owns it.
///   This is the shipped noon-to-noon journaling behavior and remains the
///   default so existing exports never change silently.
/// - `morningEnds`: the note for the wake-up date (the calendar date of the
///   session end) owns the whole session, matching the Health Connect UI.
nonisolated enum SleepDayAttribution: String, CaseIterable, Codable, Sendable, Equatable {
    case nightBegins = "night_begins"
    case morningEnds = "morning_ends"

    var localizedDisplayName: String {
        switch self {
        case .nightBegins: return String(localized: "Night begins")
        case .morningEnds: return String(localized: "Morning ends")
        }
    }

    var localizedDescription: String {
        switch self {
        case .nightBegins:
            return String(localized: "Each sleep session belongs to the daily note for the night it starts. This is the default and matches previous exports.")
        case .morningEnds:
            return String(localized: "Each sleep session belongs to the daily note for the morning it ends, matching the Health Connect app. A session from 11:45 PM to 7:30 AM appears in the wake-up day's note.")
        }
    }
}
