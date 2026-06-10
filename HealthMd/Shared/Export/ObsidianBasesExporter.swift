import Foundation

// MARK: - Obsidian Bases Export

extension HealthData {
    func toObsidianBases(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let snapshot = exportSnapshot(customization: config)
        return snapshot.frontmatterLines(
            using: config.frontmatterConfig,
            includeWorkoutDetails: true
        ).joined(separator: "\n")
    }
}
