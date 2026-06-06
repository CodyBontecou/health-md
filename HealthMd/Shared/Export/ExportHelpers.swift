import Foundation

// MARK: - Shared Export Formatting Helpers

extension ExportDataSnapshot {
    /// Builds the shared YAML frontmatter lines used by Markdown and Obsidian Bases exports.
    /// Metric fields are included only when the snapshot has a value and the user's
    /// Frontmatter Fields configuration has that canonical field enabled.
    func frontmatterLines(using config: FrontmatterConfiguration) -> [String] {
        var lines: [String] = ["---"]

        if config.includeDate {
            lines.append("\(config.customDateKey): \(dateString)")
        }
        if config.includeType {
            lines.append("\(config.customTypeKey): \(config.customTypeValue)")
        }

        // Custom static fields (with fixed values)
        for (key, value) in config.customFields.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }

        // Placeholder fields (empty values for manual entry)
        for key in config.placeholderFields.sorted() {
            lines.append("\(key): ")
        }

        // Health metric fields selected in Format Customization > Frontmatter Fields.
        for key in frontmatterMetrics.keys.sorted() {
            guard config.isFieldEnabled(key), let value = frontmatterMetrics[key] else { continue }
            let outputKey = config.outputKey(for: key) ?? key
            lines.append("\(outputKey): \(value)")
        }

        lines.append("---")
        lines.append("")  // Trailing newline when joined with \n
        return lines
    }
}

extension HealthData {
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    func formatDurationShort(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
    
    func valenceDescription(_ valence: Double) -> String {
        switch valence {
        case -1.0 ..< -0.6:
            return "Very Unpleasant"
        case -0.6 ..< -0.2:
            return "Unpleasant"
        case -0.2 ..< 0.2:
            return "Neutral"
        case 0.2 ..< 0.6:
            return "Pleasant"
        case 0.6 ... 1.0:
            return "Very Pleasant"
        default:
            return "Unknown"
        }
    }
}
