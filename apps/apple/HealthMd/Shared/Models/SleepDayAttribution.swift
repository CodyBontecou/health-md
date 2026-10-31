//
//  SleepDayAttribution.swift
//  Health.md
//
//  Issue #104: which daily note owns a sleep session that spans midnight.
//

import Foundation

/// Which daily note owns a sleep session.
///
/// Cross-platform mode switch (issue #104). Both platforms persist the same
/// raw values and default to `nightBegins`.
///
/// - `nightBegins`: the shipped noon-to-noon journaling window clips summary
///   intervals at its boundaries. It remains the default so existing exports
///   never change silently.
/// - `morningEnds`: wake-up-date ownership of the whole session through the
///   explicit successor export profile.
nonisolated enum SleepDayAttribution: String, CaseIterable, Codable, Sendable, Equatable {
    case nightBegins = "night_begins"
    case morningEnds = "morning_ends"

    /// Capture still requires a matching immutable profile and engine authority.
    var isAvailableForShippedProfiles: Bool { true }

    var localizedDisplayName: String {
        switch self {
        case .nightBegins: return String(localized: "Night begins")
        case .morningEnds: return String(localized: "Morning ends")
        }
    }

    var localizedDescription: String {
        switch self {
        case .nightBegins:
            return String(localized: "Sleep uses the daily note's noon-to-noon window. This is the default and matches previous exports.")
        case .morningEnds:
            guard isAvailableForShippedProfiles else {
                return String(localized: "Morning ends is unavailable for current export profiles. Choose Night begins for a new export.")
            }
            return String(localized: "Assigns the whole sleep session to the date you wake up, using the export’s time zone.")
        }
    }
}
