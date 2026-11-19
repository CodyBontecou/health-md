import Foundation

/// Editor validation uses the same path grammar as portable setups. Invalid drafts must
/// never replace the last saved settings, even when their output is currently disabled.
enum AutomationOutputPathValidation {
    static func invalidReason(folders: [String], filename: String) -> String? {
        for folder in folders {
            guard (try? SharedSetupV2Validation.validateRelativePath(folder)) != nil else {
                return String(localized: "Enter a folder inside your vault, such as Daily.")
            }
        }
        guard !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? SharedSetupV2Validation.validateFilename(filename)) != nil else {
            return String(localized: "Enter a filename such as {date}, without slashes or percent signs.")
        }
        return nil
    }

    /// A daily note's filename pattern may hold folders ("{year}/{month}/{date}"): 3.x wrote
    /// such patterns, the path planner keeps them (dropping empty segments, so a leading "/"
    /// is harmless), and the folder field takes no date tokens. Every segment must still be
    /// a safe name, so the note never leaves the vault.
    static func isValidDailyNoteFilenamePattern(_ pattern: String) -> Bool {
        let segments = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { (try? SharedSetupValidation.validateFilename($0)) != nil }
    }
}
