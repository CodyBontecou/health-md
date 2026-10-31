import Foundation

/// Gate for the Liquid Glass experience. Off by default in every build configuration.
/// DEBUG builds can opt in with the launch argument `-NewExperienceEnabled YES`.
enum NewExperienceFeature {
    static let flagKey = "NEW_EXPERIENCE_ENABLED"
    static let debugOverrideKey = "NewExperienceEnabled"

    static var isEnabled: Bool {
        isEnabled(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            debugOverride: debugOverride
        )
    }

    static func isEnabled(infoDictionary: [String: Any], debugOverride: Bool? = nil) -> Bool {
        debugOverride ?? isTruthy(infoDictionary[flagKey])
    }

    private static var debugOverride: Bool? {
        #if DEBUG
        UserDefaults.standard.object(forKey: debugOverrideKey) as? Bool
        #else
        nil
        #endif
    }

    private static func isTruthy(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        guard let value = value as? String else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return true
        default: return false
        }
    }
}
