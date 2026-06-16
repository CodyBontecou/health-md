import Foundation

// MARK: - Roll-up JSON Exporter

extension RollupDataSnapshot {
    func toRollupJSON() -> String {
        let metricsPayload = metrics.map { metric -> [String: Any] in
            var payload: [String: Any] = [
                "key": metric.key,
                "canonical_key": metric.canonicalKey,
                "display_name": metric.displayName,
                "category": metric.category,
                "unit": metric.unit,
                "rule": metric.rule,
                "primary_value": metric.primaryValue,
                "days_counted": metric.daysCounted,
                "statistics": metric.statistics.map { ["name": $0.name, "value": $0.value] }
            ]
            if let notes = metric.notes {
                payload["notes"] = notes
            }
            return payload
        }

        let categoriesPayload = Dictionary(grouping: metricsPayload) { metric in
            metric["category"] as? String ?? "Other"
        }

        let payload: [String: Any] = [
            "schema": HealthRollupExportSchema.identifier,
            "schema_version": HealthMdExportSchema.version,
            "type": "health_rollup",
            "rollup_period": period.rawValue,
            "period_id": periodID,
            "start_date": HealthRollupDateFormatting.dayString(window.startDate),
            "end_date": HealthRollupDateFormatting.dayString(window.endDate),
            "days_expected": daysExpected,
            "days_counted": daysCounted,
            "coverage_percent": coveragePercent,
            "source_schema": HealthMdExportSchema.identifier,
            "source_schema_version": HealthMdExportSchema.version,
            "rollup_rules_version": HealthMdExportSchema.version,
            "generated_at": HealthRollupDateFormatting.timestampString(generatedAt),
            "source_dates": sourceDates.sorted().map { HealthRollupDateFormatting.dayString($0) },
            "units": Dictionary(uniqueKeysWithValues: units),
            "metrics": metricsPayload,
            "categories": categoriesPayload
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString + "\n"
        }

        return "{}\n"
    }
}
