import Foundation

// MARK: - Roll-up Markdown Exporter

extension RollupDataSnapshot {
    func toRollupMarkdown() -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("schema: \(HealthRollupExportSchema.identifier)")
        lines.append("schema_version: \(HealthMdExportSchema.version)")
        lines.append("type: health_rollup")
        lines.append("rollup_period: \(period.rawValue)")
        lines.append("period_id: \(periodID)")
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
                lines.append("  \(unit.key): \(unit.unit)")
            }
        }

        lines.append("---")
        lines.append("")
        lines.append("# \(window.title)")
        lines.append("")
        lines.append("Generated from \(daysCounted) HealthKit daily aggregate snapshot\(daysCounted == 1 ? "" : "s") in this \(period.displayName.lowercased()) period.")
        lines.append("")
        lines.append("## Coverage")
        lines.append("")
        lines.append("- **Period:** \(HealthRollupDateFormatting.dayString(window.startDate)) → \(HealthRollupDateFormatting.dayString(window.endDate))")
        lines.append("- **Days counted:** \(daysCounted) / \(daysExpected) (\(HealthRollupFormatting.number(coveragePercent))%)")
        lines.append("- **Missing days:** \(max(0, daysExpected - daysCounted))")
        lines.append("- **Rule source:** `_healthmd_data_dictionary.json` schema v\(HealthMdExportSchema.version)")

        if !sourceDates.isEmpty {
            lines.append("- **Source dates:** \(sourceDates.sorted().map { HealthRollupDateFormatting.dayString($0) }.joined(separator: ", "))")
        }

        for category in categoryNames {
            let categoryMetrics = metrics
                .filter { $0.category == category }
                .sorted { lhs, rhs in
                    if lhs.displayName == rhs.displayName { return lhs.key < rhs.key }
                    return lhs.displayName < rhs.displayName
                }
            guard !categoryMetrics.isEmpty else { continue }

            lines.append("")
            lines.append("## \(category)")
            lines.append("")
            lines.append("| Metric | Key | Value | Unit | Days | Rule |")
            lines.append("|---|---:|---:|---|---:|---|")
            for metric in categoryMetrics {
                lines.append("| \(HealthRollupFormatting.tableEscaped(metric.displayName)) | `\(metric.key)` | \(HealthRollupFormatting.tableEscaped(metric.primaryValue)) | \(HealthRollupFormatting.tableEscaped(metric.unit)) | \(metric.daysCounted)/\(daysExpected) | \(metric.rule) |")
            }

            let statisticRows = categoryMetrics.flatMap { metric in
                metric.statistics.map { (metric: metric, statistic: $0) }
            }
            if !statisticRows.isEmpty {
                lines.append("")
                lines.append("<details>")
                lines.append("<summary>\(category) statistics</summary>")
                lines.append("")
                lines.append("| Key | Statistic | Value |")
                lines.append("|---|---:|---:|")
                for row in statisticRows {
                    lines.append("| `\(row.metric.key)` | \(HealthRollupFormatting.tableEscaped(row.statistic.name)) | \(HealthRollupFormatting.tableEscaped(row.statistic.value)) |")
                }
                lines.append("")
                lines.append("</details>")
            }
        }

        lines.append("")
        lines.append("## Roll-up notes")
        lines.append("")
        lines.append("- Missing daily values are ignored and reported through the days-counted columns.")
        lines.append("- Daily averages divide by days with data, not by calendar days.")
        lines.append("- Weighted workout metrics use daily workout duration when available, then fall back to unweighted daily values.")
        lines.append("- Summary files are derived artifacts and can be regenerated from HealthKit daily aggregates plus the data dictionary.")

        return lines.joined(separator: "\n") + "\n"
    }
}
