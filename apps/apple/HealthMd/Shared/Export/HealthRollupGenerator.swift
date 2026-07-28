import Foundation

// MARK: - Health Roll-up Generator

/// Builds period snapshots from daily HealthData aggregate snapshots by applying
/// the current export schema roll-up rules in HealthMetricDataDictionary.
enum HealthRollupGenerator {
    static func generate(
        from healthData: [HealthData],
        settings: AdvancedExportSettings,
        periods: [HealthRollupPeriod],
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> [RollupDataSnapshot] {
        let customization = settings.formatCustomization
        let dictionaryEntries = HealthMetricDataDictionary.entries(using: customization)
            .filter { customization.frontmatterConfig.isFieldEnabled($0.canonicalKey) }
        guard !dictionaryEntries.isEmpty else { return [] }

        let filteredInputs = healthData
            .map { $0.filtered(by: settings.metricSelection) }
            .map { RollupInputDay(snapshot: $0.exportSnapshot(customization: customization)) }
            .sorted { $0.date < $1.date }

        guard !filteredInputs.isEmpty else { return [] }

        var snapshots: [RollupDataSnapshot] = []
        for period in periods {
            let grouped = Dictionary(grouping: filteredInputs) { input in
                HealthRollupPeriodWindow.window(containing: input.date, period: period, calendar: calendar)
            }

            for window in grouped.keys.sorted(by: { lhs, rhs in
                if lhs.startDate == rhs.startDate { return lhs.period.rawValue < rhs.period.rawValue }
                return lhs.startDate < rhs.startDate
            }) {
                let days = grouped[window] ?? []
                let metrics = buildMetricSummaries(
                    for: days,
                    dictionaryEntries: dictionaryEntries
                )
                guard !metrics.isEmpty else { continue }

                snapshots.append(
                    RollupDataSnapshot(
                        window: window,
                        generatedAt: generatedAt,
                        sourceDates: days.map(\.date),
                        metrics: metrics
                    )
                )
            }
        }

        return snapshots.sorted { lhs, rhs in
            if lhs.window.startDate == rhs.window.startDate {
                return periodSortIndex(lhs.period) < periodSortIndex(rhs.period)
            }
            return lhs.window.startDate < rhs.window.startDate
        }
    }

    private static func buildMetricSummaries(
        for days: [RollupInputDay],
        dictionaryEntries: [HealthMetricDataDictionaryEntry]
    ) -> [HealthRollupMetricSummary] {
        dictionaryEntries.compactMap { entry in
            let values = days.compactMap { day -> DailyMetricValue? in
                guard let raw = day.snapshot.frontmatterMetrics[entry.canonicalKey] else { return nil }
                return DailyMetricValue(
                    date: day.date,
                    snapshot: day.snapshot,
                    rawValue: raw,
                    numericValue: HealthRollupFormatting.numericValue(from: raw)
                )
            }
            guard !values.isEmpty else { return nil }
            return summarize(entry: entry, values: values)
        }
        .sorted { lhs, rhs in
            if lhs.category == rhs.category {
                if lhs.displayName == rhs.displayName { return lhs.key < rhs.key }
                return lhs.displayName < rhs.displayName
            }
            return lhs.category < rhs.category
        }
    }

    private static func summarize(
        entry: HealthMetricDataDictionaryEntry,
        values: [DailyMetricValue]
    ) -> HealthRollupMetricSummary? {
        switch entry.rollup.primary {
        case "sum":
            return numericSummary(entry: entry, values: values, primaryStatistic: "sum")
        case "average":
            return numericSummary(entry: entry, values: values, primaryStatistic: "average_of_daily_values")
        case "weighted_average":
            return weightedAverageSummary(entry: entry, values: values)
        case "minimum":
            return numericSummary(entry: entry, values: values, primaryStatistic: "minimum")
        case "maximum":
            return numericSummary(entry: entry, values: values, primaryStatistic: "maximum")
        case "latest":
            return latestSummary(entry: entry, values: values)
        case "union":
            return unionSummary(entry: entry, values: values)
        case "histogram":
            return histogramSummary(entry: entry, values: values)
        case "time_of_day":
            return timeOfDaySummary(entry: entry, values: values)
        default:
            if values.contains(where: { $0.numericValue != nil }) {
                return numericSummary(entry: entry, values: values, primaryStatistic: entry.rollup.primary)
            }
            return latestSummary(entry: entry, values: values)
        }
    }

    private static func numericSummary(
        entry: HealthMetricDataDictionaryEntry,
        values: [DailyMetricValue],
        primaryStatistic: String
    ) -> HealthRollupMetricSummary? {
        let numericValues = values.compactMap(\.numericValue)
        guard !numericValues.isEmpty else { return latestSummary(entry: entry, values: values) }

        let sum = numericValues.reduce(0, +)
        let average = sum / Double(numericValues.count)
        let minValue = numericValues.min() ?? 0
        let maxValue = numericValues.max() ?? 0
        let latest = latestNumericValue(from: values)

        let stats: [String: String] = [
            "sum": HealthRollupFormatting.number(sum),
            "daily_average": HealthRollupFormatting.number(average),
            "average_of_daily_values": HealthRollupFormatting.number(average),
            "minimum": HealthRollupFormatting.number(minValue),
            "minimum_daily_value": HealthRollupFormatting.number(minValue),
            "maximum": HealthRollupFormatting.number(maxValue),
            "maximum_daily_value": HealthRollupFormatting.number(maxValue),
            "latest": latest.map { HealthRollupFormatting.number($0) } ?? "",
            "days_counted": "\(numericValues.count)"
        ]

        let primaryValue: String
        switch primaryStatistic {
        case "sum": primaryValue = HealthRollupFormatting.number(sum)
        case "average", "average_of_daily_values", "daily_average": primaryValue = HealthRollupFormatting.number(average)
        case "minimum", "minimum_daily_value": primaryValue = HealthRollupFormatting.number(minValue)
        case "maximum", "maximum_daily_value": primaryValue = HealthRollupFormatting.number(maxValue)
        case "latest": primaryValue = latest.map { HealthRollupFormatting.number($0) } ?? HealthRollupFormatting.number(average)
        default: primaryValue = HealthRollupFormatting.number(average)
        }

        return metricSummary(
            entry: entry,
            valuesCount: numericValues.count,
            primaryValue: primaryValue,
            statistics: statistics(for: entry, available: stats)
        )
    }

    private static func weightedAverageSummary(
        entry: HealthMetricDataDictionaryEntry,
        values: [DailyMetricValue]
    ) -> HealthRollupMetricSummary? {
        let numericPairs = values.compactMap { value -> (value: Double, weight: Double)? in
            guard let numeric = value.numericValue else { return nil }
            let rawWeight = value.snapshot.frontmatterMetrics["workout_minutes"]
            let weight = rawWeight.flatMap { HealthRollupFormatting.numericValue(from: $0) } ?? 1
            return (numeric, max(0, weight))
        }
        guard !numericPairs.isEmpty else { return latestSummary(entry: entry, values: values) }

        let totalWeight = numericPairs.reduce(0.0) { $0 + $1.weight }
        let weightedAverage: Double
        if totalWeight > 0 {
            weightedAverage = numericPairs.reduce(0.0) { $0 + $1.value * $1.weight } / totalWeight
        } else {
            weightedAverage = numericPairs.reduce(0.0) { $0 + $1.value } / Double(numericPairs.count)
        }

        let numericValues = numericPairs.map(\.value)
        let minValue = numericValues.min() ?? weightedAverage
        let maxValue = numericValues.max() ?? weightedAverage
        let latest = latestNumericValue(from: values)
        let stats: [String: String] = [
            "weighted_average": HealthRollupFormatting.number(weightedAverage),
            "average_of_daily_values": HealthRollupFormatting.number(numericValues.reduce(0, +) / Double(numericValues.count)),
            "minimum_daily_value": HealthRollupFormatting.number(minValue),
            "maximum_daily_value": HealthRollupFormatting.number(maxValue),
            "latest": latest.map { HealthRollupFormatting.number($0) } ?? "",
            "days_counted": "\(numericValues.count)"
        ]

        return metricSummary(
            entry: entry,
            valuesCount: numericValues.count,
            primaryValue: HealthRollupFormatting.number(weightedAverage),
            statistics: statistics(for: entry, available: stats)
        )
    }

    private static func latestSummary(
        entry: HealthMetricDataDictionaryEntry,
        values: [DailyMetricValue]
    ) -> HealthRollupMetricSummary? {
        guard let latest = values.max(by: { $0.date < $1.date }) else { return nil }

        if values.contains(where: { $0.numericValue != nil }) {
            let numericValues = values.compactMap(\.numericValue)
            let average = numericValues.reduce(0, +) / Double(max(1, numericValues.count))
            let stats: [String: String] = [
                "latest": latest.numericValue.map { HealthRollupFormatting.number($0) } ?? latest.rawValue,
                "minimum_daily_value": numericValues.min().map { HealthRollupFormatting.number($0) } ?? "",
                "maximum_daily_value": numericValues.max().map { HealthRollupFormatting.number($0) } ?? "",
                "average_of_daily_values": HealthRollupFormatting.number(average),
                "days_counted": "\(values.count)"
            ]
            return metricSummary(
                entry: entry,
                valuesCount: values.count,
                primaryValue: latest.numericValue.map { HealthRollupFormatting.number($0) } ?? latest.rawValue,
                statistics: statistics(for: entry, available: stats)
            )
        }

        let stats: [String: String] = [
            "latest": latest.rawValue,
            "days_counted": "\(values.count)"
        ]
        return metricSummary(
            entry: entry,
            valuesCount: values.count,
            primaryValue: latest.rawValue,
            statistics: statistics(for: entry, available: stats)
        )
    }

    private static func unionSummary(
        entry: HealthMetricDataDictionaryEntry,
        values: [DailyMetricValue]
    ) -> HealthRollupMetricSummary? {
        var counts: [String: Int] = [:]
        for value in values {
            for item in HealthRollupFormatting.listValues(from: value.rawValue) {
                counts[item, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return latestSummary(entry: entry, values: values) }

        let union = counts.keys.sorted()
        let countsString = counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
        let stats: [String: String] = [
            "union": "[\(union.joined(separator: ", "))]",
            "value_counts": countsString,
            "days_counted": "\(values.count)"
        ]
        return metricSummary(
            entry: entry,
            valuesCount: values.count,
            primaryValue: "[\(union.joined(separator: ", "))]",
            statistics: statistics(for: entry, available: stats)
        )
    }

    private static func histogramSummary(
        entry: HealthMetricDataDictionaryEntry,
        values: [DailyMetricValue]
    ) -> HealthRollupMetricSummary? {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value.rawValue, default: 0] += 1
        }
        guard let latest = values.max(by: { $0.date < $1.date }) else { return nil }
        let countsString = counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
        let stats: [String: String] = [
            "latest": latest.rawValue,
            "value_counts": countsString,
            "days_counted": "\(values.count)"
        ]
        return metricSummary(
            entry: entry,
            valuesCount: values.count,
            primaryValue: latest.rawValue,
            statistics: statistics(for: entry, available: stats)
        )
    }

    private static func timeOfDaySummary(
        entry: HealthMetricDataDictionaryEntry,
        values: [DailyMetricValue]
    ) -> HealthRollupMetricSummary? {
        let minutes = values.compactMap { HealthRollupFormatting.minutesFromMidnight(from: $0.rawValue) }
        guard !minutes.isEmpty else { return latestSummary(entry: entry, values: values) }
        let earliest = minutes.min() ?? 0
        let latest = minutes.max() ?? 0
        let average = Int((Double(minutes.reduce(0, +)) / Double(minutes.count)).rounded())
        let stats: [String: String] = [
            "earliest_time": HealthRollupFormatting.timeString(minutes: earliest),
            "latest_time": HealthRollupFormatting.timeString(minutes: latest),
            "average_time_of_day": HealthRollupFormatting.timeString(minutes: average),
            "days_counted": "\(minutes.count)"
        ]
        return metricSummary(
            entry: entry,
            valuesCount: minutes.count,
            primaryValue: HealthRollupFormatting.timeString(minutes: average),
            statistics: statistics(for: entry, available: stats)
        )
    }

    private static func metricSummary(
        entry: HealthMetricDataDictionaryEntry,
        valuesCount: Int,
        primaryValue: String,
        statistics: [HealthRollupStatistic]
    ) -> HealthRollupMetricSummary {
        HealthRollupMetricSummary(
            key: entry.key,
            canonicalKey: entry.canonicalKey,
            displayName: entry.displayName,
            category: entry.category,
            unit: entry.unit,
            rule: entry.rollup.primary,
            primaryValue: primaryValue,
            daysCounted: valuesCount,
            statistics: statistics,
            notes: entry.rollup.notes
        )
    }

    private static func statistics(
        for entry: HealthMetricDataDictionaryEntry,
        available: [String: String]
    ) -> [HealthRollupStatistic] {
        entry.rollup.statistics.compactMap { name in
            guard let value = available[name], !value.isEmpty else { return nil }
            return HealthRollupStatistic(name: name, value: value)
        }
    }

    private static func latestNumericValue(from values: [DailyMetricValue]) -> Double? {
        values
            .filter { $0.numericValue != nil }
            .max(by: { $0.date < $1.date })?
            .numericValue
    }

    private static func periodSortIndex(_ period: HealthRollupPeriod) -> Int {
        switch period {
        case .weekly: return 0
        case .monthly: return 1
        case .yearly: return 2
        }
    }
}

private struct RollupInputDay {
    let snapshot: ExportDataSnapshot

    var date: Date { snapshot.date }
}

private struct DailyMetricValue {
    let date: Date
    let snapshot: ExportDataSnapshot
    let rawValue: String
    let numericValue: Double?
}
