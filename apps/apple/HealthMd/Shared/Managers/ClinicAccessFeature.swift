import Foundation

/// Hides every clinic access entry point until the feature launches. Set the build setting
/// `CLINIC_ACCESS_ENABLED = YES` to show it; unset or any other value keeps it hidden.
/// Existing sponsorship sessions keep working either way: only the ways in are hidden.
enum ClinicAccessFeature {
    static var isEnabled: Bool { isEnabled(infoDictionary: Bundle.main.infoDictionary ?? [:]) }

    static func isEnabled(infoDictionary: [String: Any]) -> Bool {
        guard let value = infoDictionary["ClinicAccessEnabled"] as? String else { return false }
        return ["yes", "true", "1"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
