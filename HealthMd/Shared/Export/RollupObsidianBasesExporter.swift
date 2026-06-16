import Foundation

// MARK: - Roll-up Obsidian Bases Exporter

extension RollupDataSnapshot {
    /// Obsidian Bases are Markdown files that primarily expose structured YAML
    /// frontmatter. Keep the body intentionally small; Bases users query the
    /// frontmatter fields.
    func toRollupObsidianBases() -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("schema: \(HealthRollupExportSchema.identifier)")
        lines.append("schema_version: \(HealthMdExportSchema.version)")
        lines.append("type: health_rollup")
        lines.append("rollup_period: \(period.rawValue)")
        lines.append("period_id: \(HealthRollupFormatting.yamlQuoted(periodID))")
        lines.append("title: \(HealthRollupFormatting.yamlQuoted(window.title))")
        lines.append("start_date: \(HealthRollupDateFormatting.dayString(window.startDate))")
        lines.append("end_date: \(HealthRollupDateFormatting.dayString(window.endDate))")
        lines.append("days_expected: \(daysExpected)")
        lines.append("days_counted: \(daysCounted)")
        lines.append("coverage_percent: \(HealthRollupFormatting.number(coveragePercent))")
        lines.append("source_schema: \(HealthMdExportSchema.identifier)")
        lines.append("source_schema_version: \(HealthMdExportSchema.version)")
        lines.append("rollup_rules_version: \(HealthMdExportSchema.version)")
        lines.append("generated_at: \(HealthRollupDateFormatting.timestampString(generatedAt))")

        if !sourceDates.isEmpty {
            lines.append("source_dates:")
            for date in sourceDates.sorted() {
                lines.append("  - \(HealthRollupDateFormatting.dayString(date))")
            }
        }

        if !units.isEmpty {
            lines.append("units:")
            for unit in units {
                lines.append("  \(unit.key): \(HealthRollupFormatting.yamlQuoted(unit.unit))")
            }
        }

        lines.append("rollup_metrics:")
        for metric in metrics.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(metric.key):")
            lines.append("    value: \(HealthRollupFormatting.yamlQuoted(metric.primaryValue))")
            lines.append("    unit: \(HealthRollupFormatting.yamlQuoted(metric.unit))")
            lines.append("    category: \(HealthRollupFormatting.yamlQuoted(metric.category))")
            lines.append("    display_name: \(HealthRollupFormatting.yamlQuoted(metric.displayName))")
            lines.append("    canonical_key: \(metric.canonicalKey)")
            lines.append("    rule: \(metric.rule)")
            lines.append("    days_counted: \(metric.daysCounted)")
            if !metric.statistics.isEmpty {
                lines.append("    statistics:")
                for statistic in metric.statistics {
                    lines.append("      \(statistic.name): \(HealthRollupFormatting.yamlQuoted(statistic.value))")
                }
            }
            if let notes = metric.notes {
                lines.append("    notes: \(HealthRollupFormatting.yamlQuoted(notes))")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(window.title)")
        lines.append("")
        lines.append("Structured roll-up summary for Obsidian Bases. Query `rollup_metrics` and top-level period fields from the YAML frontmatter.")
        return lines.joined(separator: "\n") + "\n"
    }
}
