import Foundation

// MARK: - Obsidian Bases Export

extension HealthData {
    func toObsidianBases(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let dateString = config.dateFormat.format(date: date)
        let fmConfig = config.frontmatterConfig
        let converter = config.unitConverter

        var frontmatter: [String] = []
        frontmatter.append("---")
        
        // Core fields
        if fmConfig.includeDate {
            frontmatter.append("\(fmConfig.customDateKey): \(dateString)")
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
        
        // All health metrics from the canonical shared dictionary.
        // Adding a metric to HealthMetricsDictionary automatically surfaces it here.
        let metrics = allMetricsDictionary(using: converter, timeFormat: config.timeFormat)
        for key in metrics.keys.sorted() {
            guard fmConfig.isFieldEnabled(key) else { continue }
            let outputKey = fmConfig.outputKey(for: key) ?? key
            frontmatter.append("\(outputKey): \(metrics[key]!)")
        }

        frontmatter.append("---")
        frontmatter.append("")  // Trailing newline

        return frontmatter.joined(separator: "\n")
    }
}
