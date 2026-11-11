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
}
