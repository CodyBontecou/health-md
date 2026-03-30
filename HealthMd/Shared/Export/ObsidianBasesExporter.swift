import Foundation

// MARK: - Obsidian Bases Export

extension HealthData {
    func toObsidianBases(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let snapshot = exportSnapshot(customization: config)
        let fmConfig = config.frontmatterConfig

        var frontmatter: [String] = []
        frontmatter.append("---")

        // Core fields
        if fmConfig.includeDate {
            frontmatter.append("\(fmConfig.customDateKey): \(snapshot.dateString)")
        }
        if fmConfig.includeType {
            frontmatter.append("\(fmConfig.customTypeKey): \(fmConfig.customTypeValue)")
        }

        // Custom static fields (with fixed values)
        for (key, value) in fmConfig.customFields.sorted(by: { $0.key < $1.key }) {
            frontmatter.append("\(key): \(value)")
        }

        // Placeholder fields (empty values for manual entry)
        for key in fmConfig.placeholderFields.sorted() {
            frontmatter.append("\(key): ")
        }

        // Canonical metric values are extracted once in ExportDataSnapshot.
        for key in snapshot.frontmatterMetrics.keys.sorted() {
            guard fmConfig.isFieldEnabled(key) else { continue }
            let outputKey = fmConfig.outputKey(for: key) ?? key
            frontmatter.append("\(outputKey): \(snapshot.frontmatterMetrics[key]!)")
        }

        frontmatter.append("---")
        frontmatter.append("")  // Trailing newline

        return frontmatter.joined(separator: "\n")
    }
}
