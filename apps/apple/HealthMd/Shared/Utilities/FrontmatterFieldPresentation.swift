import Foundation

/// UI copy only. YAML keys and user values are opaque text, never localization keys.
nonisolated struct FrontmatterFieldPresentation: Sendable {
    let originalKey: String
    let customKey: String
    let renamed: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let detail: String

    init(originalKey: String, customKey: String, isEnabled: Bool,
         bundle: Bundle = .main, locale: Locale = .current) {
        self.originalKey = originalKey
        self.customKey = customKey
        renamed = customKey != originalKey && !customKey.isEmpty
        accessibilityLabel = renamed
            ? String(localized: "\(originalKey) renamed to \(customKey)", bundle: bundle, locale: locale)
            : originalKey
        accessibilityValue = isEnabled
            ? String(localized: "Enabled", bundle: bundle, locale: locale)
            : String(localized: "Disabled", bundle: bundle, locale: locale)
        accessibilityHint = isEnabled
            ? String(localized: "Double tap to disable this field", bundle: bundle, locale: locale)
            : String(localized: "Double tap to enable this field", bundle: bundle, locale: locale)
        if renamed {
            detail = String(localized: "Renamed to \(customKey)", bundle: bundle, locale: locale)
        } else {
            detail = isEnabled
                ? String(localized: "Included in frontmatter", bundle: bundle, locale: locale)
                : String(localized: "Not exported", bundle: bundle, locale: locale)
        }
    }

    /// Only an absent value gets explanatory UI copy; nonempty input stays byte-for-byte intact.
    static func customValue(_ value: String, bundle: Bundle = .main, locale: Locale = .current) -> String {
        value.isEmpty ? String(localized: "Empty Value", bundle: bundle, locale: locale) : value
    }
}
