import Foundation

// MARK: - Roll-up CSV Exporter

extension RollupDataSnapshot {
    func toRollupCSV() -> String {
        var rows: [[String]] = [[
            "Period",
            "Period ID",
            "Start Date",
            "End Date",
            "Days Expected",
            "Days Counted",
            "Coverage Percent",
            "Category",
            "Metric",
            "Key",
            "Canonical Key",
            "Primary Value",
            "Unit",
            "Metric Days Counted",
            "Rule",
            "Statistic",
            "Statistic Value",
            "Notes"
        ]]

        for metric in metrics {
            let common = commonCSVColumns(for: metric)
            rows.append(common + ["primary", metric.primaryValue, metric.notes ?? ""])
            for statistic in metric.statistics {
                rows.append(common + [statistic.name, statistic.value, metric.notes ?? ""])
            }
        }

        return rows.map { row in
            row.map(Self.csvEscaped).joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private func commonCSVColumns(for metric: HealthRollupMetricSummary) -> [String] {
        [
            period.rawValue,
            periodID,
            HealthRollupDateFormatting.dayString(window.startDate),
            HealthRollupDateFormatting.dayString(window.endDate),
            "\(daysExpected)",
            "\(daysCounted)",
            HealthRollupFormatting.number(coveragePercent),
            metric.category,
            metric.displayName,
            metric.key,
            metric.canonicalKey,
            metric.primaryValue,
            metric.unit,
            "\(metric.daysCounted)",
            metric.rule
        ]
    }

    nonisolated private static func csvEscaped(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\n") || value.contains("\r") || value.contains("\"")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}
