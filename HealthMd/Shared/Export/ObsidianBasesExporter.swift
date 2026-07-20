import Foundation

// MARK: - Obsidian Bases Export

extension HealthData {
    func toObsidianBases(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        return toObsidianBases(
            snapshot: exportSnapshot(customization: config),
            config: config
        )
    }

    func toObsidianBases(
        snapshot: ExportDataSnapshot,
        config: FormatCustomization
    ) -> String {
        snapshot.frontmatterLines(
            using: config.frontmatterConfig,
            includeWorkoutDetails: true
        ).joined(separator: "\n")
    }
}
