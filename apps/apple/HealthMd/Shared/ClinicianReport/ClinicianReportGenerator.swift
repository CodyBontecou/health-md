import Foundation

nonisolated struct ClinicianReportGenerator {
    var locale: Locale = .current

    private var copy: ClinicianReportCopy { ClinicianReportCopy(locale: locale) }
    private var formattingLocale: Locale { copy.locale }

    func generate(_ input: ClinicianReportInput) -> ClinicianReportData {
        let configuration = input.configuration
        let range = configuration.dateRange
        let sections = ReportMetric.allCases
            .filter(configuration.selectedMetrics.contains)
            .map { section(for: $0, input: input) }
        let availableCount = sections.filter { $0.noDataMessage == nil }.count
        let unavailableNames = sections
            .filter { $0.noDataMessage != nil }
            .map(\.localizedTitle)
        let warnings = summarizedWarnings(input.warnings)
        return ClinicianReportData(
            title: copy.string(.title),
            displayName: configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            dateRangeLabel: "\(date(range.startDate, calendar: input.calendar)) – \(date(range.endDate, calendar: input.calendar))",
            generatedLabel: dateTime(input.generatedAt, calendar: input.calendar),
            timeZoneLabel: timeZoneLabel(input.calendar.timeZone, at: input.generatedAt),
            sections: sections,
            completeness: warnings.isEmpty ? .complete : .partial,
            disclaimer: copy.string(.disclaimer),
            attribution: copy.string(.attribution),
            practiceLine: copy.practiceLine,
            languageTag: copy.languageTag,
            paperRegionCode: copy.paperRegionCode,
            pdfSubject: copy.string(.entry_subtitle),
            pdfKeywords: [copy.string(.title), copy.string(.document_title), "Health.md"],
            metadataPeriodLabel: copy.string(.metadata_period),
            metadataGeneratedLabel: copy.string(.metadata_generated),
            metadataTimeZoneLabel: copy.string(.metadata_timezone),
            metadataPatientLabel: copy.string(.metadata_patient),
            aboutTitle: copy.string(.about),
            pageFooterTemplate: copy.string(.page_footer),
            warnings: warnings,
            detailLevel: configuration.detailLevel,
            availabilityNoteTitle: copy.string(.availability_note),
            availabilityColumnLabel: copy.string(.fact_days_with_data),
            summaryTableTitle: copy.string(.metrics),
            summaryColumnLabel: copy.string(.summary),
            availabilityOverview: copy.format(.data_available_count, "\(availableCount)", "\(sections.count)"),
            noReportableDataMessage: copy.string(.no_reportable_data),
            unavailableMeasurementsSummary: unavailableNames.isEmpty
                ? nil
                : copy.format(.unavailable_measurements, unavailableNames.joined(separator: ", "))
        )
    }

    private func section(for metric: ReportMetric, input: ClinicianReportInput) -> MetricReportSummary {
        switch metric {
        case .bloodPressure: return bloodPressure(input)
        case .restingHeartRate, .weight, .steps: return daily(metric, input)
        case .heartRate, .bloodGlucose, .oxygenSaturation, .respiratoryRate, .bodyTemperature:
            return scalar(metric, input)
        case .sleepDuration: return sleep(input)
        case .workouts: return workouts(input)
        }
    }

    private func bloodPressure(_ input: ClinicianReportInput) -> MetricReportSummary {
        let interval = input.configuration.dateRange.interval(calendar: input.calendar)
        let values = dedupe(input.bloodPressureObservations.filter { interval.contains($0.timestamp) }) { $0.stableID }
            .sorted { $0.timestamp < $1.timestamp }
        guard let latest = values.last else { return empty(.bloodPressure, input: input) }
        let days = Set(values.map { input.calendar.startOfDay(for: $0.timestamp) }).count
        let systolic = values.map(\.systolic)
        let diastolic = values.map(\.diastolic)
        let facts = [
            ReportFact(label: copy.string(.fact_readings), value: "\(values.count)"),
            ReportFact(label: copy.string(.fact_average), value: "\(whole(systolic.average))/\(whole(diastolic.average)) mmHg"),
            ReportFact(label: copy.string(.fact_range), value: "\(whole(systolic.min()!))–\(whole(systolic.max()!)) / \(whole(diastolic.min()!))–\(whole(diastolic.max()!)) mmHg"),
            ReportFact(
                label: copy.string(.fact_most_recent),
                value: copy.format(
                    .value_on_date,
                    "\(whole(latest.systolic))/\(whole(latest.diastolic)) mmHg",
                    dateTime(latest.timestamp, calendar: input.calendar)
                )
            )
        ]
        let table = input.configuration.detailLevel == .summaryAndReadings ? ReportTable(
            title: copy.string(.table_blood_pressure),
            columns: [copy.string(.column_date), copy.string(.column_time), copy.string(.column_systolic), copy.string(.column_diastolic)],
            rows: values.map {
                [date($0.timestamp, calendar: input.calendar), time($0.timestamp, calendar: input.calendar), "\(whole($0.systolic)) mmHg", "\(whole($0.diastolic)) mmHg"]
            }
        ) : nil
        return summary(.bloodPressure, facts: facts, days: days, input: input, table: table)
    }

    private struct ScalarValue {
        let date: Date
        let timestamp: Date?
        let value: Double
        let stableID: String?
    }

    private func scalar(_ metric: ReportMetric, _ input: ClinicianReportInput) -> MetricReportSummary {
        let interval = input.configuration.dateRange.interval(calendar: input.calendar)
        let exact = input.scalarObservations
            .filter { $0.metric == metric && interval.contains($0.timestamp) }
            .map { ScalarValue(date: input.calendar.startOfDay(for: $0.timestamp), timestamp: $0.timestamp, value: $0.value, stableID: $0.stableID) }
        let range = input.configuration.dateRange
        let dailyValues = input.dailyValues
            .filter { $0.metric == metric && $0.date >= range.startDate && $0.date <= range.endDate }
            .map { ScalarValue(date: input.calendar.startOfDay(for: $0.date), timestamp: $0.timestamp, value: $0.value, stableID: $0.stableID) }
        let values = dedupe(exact + dailyValues) { $0.stableID }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return ($0.timestamp ?? $0.date) < ($1.timestamp ?? $1.date)
        }
        guard let latest = values.last else { return empty(metric, input: input) }
        let days = Set(values.map(\.date)).count
        func formatted(_ value: Double) -> String { "\(formatValue(value, metric: metric, input: input)) \(unit(metric, input: input))" }
        let latestLabel = latest.timestamp.map { dateTime($0, calendar: input.calendar) } ?? date(latest.date, calendar: input.calendar)
        let facts = [
            ReportFact(label: copy.string(dailyValues.isEmpty ? .fact_readings : .fact_available_values), value: "\(values.count)"),
            ReportFact(label: copy.string(.fact_median), value: formatted(median(values.map(\.value)))),
            ReportFact(label: copy.string(.fact_range), value: "\(formatted(values.map(\.value).min()!))–\(formatted(values.map(\.value).max()!))"),
            ReportFact(label: copy.string(.fact_most_recent), value: copy.format(.value_on_date, formatted(latest.value), latestLabel))
        ]
        let table = input.configuration.detailLevel == .summaryAndReadings ? ReportTable(
            title: copy.format(.table_metric_readings, metric.displayName(using: copy)),
            columns: [copy.string(.column_date), copy.string(.column_time), copy.string(.column_value)],
            rows: values.map { [date($0.date, calendar: input.calendar), $0.timestamp.map { time($0, calendar: input.calendar) } ?? "", formatted($0.value)] }
        ) : nil
        return summary(metric, facts: facts, days: days, input: input, table: table)
    }

    private func daily(_ metric: ReportMetric, _ input: ClinicianReportInput) -> MetricReportSummary {
        let range = input.configuration.dateRange
        let values = dedupe(input.dailyValues.filter { $0.metric == metric && $0.date >= range.startDate && $0.date <= range.endDate }) { $0.stableID }
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return ($0.timestamp ?? $0.date) < ($1.timestamp ?? $1.date)
            }
        guard let first = values.first, let latest = values.last else { return empty(metric, input: input) }
        let days = Set(values.map { input.calendar.startOfDay(for: $0.date) }).count
        let converter = UnitConverter(preference: input.configuration.unitPreference)
        let facts: [ReportFact]
        switch metric {
        case .restingHeartRate:
            let numbers = values.map(\.value)
            facts = [
                ReportFact(label: copy.string(.fact_median), value: "\(one(median(numbers))) bpm"),
                ReportFact(label: copy.string(.fact_range), value: "\(one(numbers.min()!))–\(one(numbers.max()!)) bpm"),
                ReportFact(label: copy.string(.fact_most_recent), value: copy.format(.value_on_date, "\(one(latest.value)) bpm", date(latest.date, calendar: input.calendar)))
            ]
        case .weight:
            let change = converter.convertWeight(latest.value - first.value)
            facts = [
                ReportFact(label: copy.string(.fact_daily_values), value: "\(values.count)"),
                ReportFact(label: copy.string(.fact_first), value: copy.format(.value_on_date, formatWeight(first.value, converter: converter), date(first.date, calendar: input.calendar))),
                ReportFact(label: copy.string(.fact_most_recent), value: copy.format(.value_on_date, formatWeight(latest.value, converter: converter), date(latest.date, calendar: input.calendar))),
                ReportFact(label: copy.string(.fact_change), value: "\(change > 0 ? "+" : "")\(one(change)) \(converter.weightUnit())")
            ]
        case .steps:
            facts = [
                ReportFact(label: copy.string(.fact_total), value: copy.format(.step_total, whole(values.map(\.value).reduce(0, +)))),
                ReportFact(label: copy.string(.fact_average_data_days), value: copy.format(.step_average, whole(values.map(\.value).average)))
            ]
        default:
            facts = []
        }
        let table: ReportTable?
        if input.configuration.detailLevel == .summaryAndReadings {
            let valueLabel = metric == .weight ? copy.string(.column_weight) : metric == .steps ? copy.string(.column_steps) : copy.string(.column_value)
            let columns = [copy.string(.column_date), valueLabel]
            let rows = values.map { value -> [String] in
                let formatted = metric == .weight ? formatWeight(value.value, converter: converter) : metric == .steps ? copy.format(.step_total, whole(value.value)) : one(value.value)
                return [date(value.date, calendar: input.calendar), formatted]
            }
            table = ReportTable(title: copy.format(.table_metric_readings, metric.displayName(using: copy)), columns: columns, rows: rows)
        } else {
            table = nil
        }
        return summary(metric, facts: facts, days: days, input: input, table: table)
    }

    private func sleep(_ input: ClinicianReportInput) -> MetricReportSummary {
        let range = input.configuration.dateRange
        let values = dedupe(input.sleepObservations.filter { $0.date >= range.startDate && $0.date <= range.endDate }) { $0.stableID }
            .sorted { $0.date < $1.date }
        guard !values.isEmpty else { return empty(.sleepDuration, input: input) }
        let days = Set(values.map { input.calendar.startOfDay(for: $0.date) }).count
        let facts = [
            ReportFact(label: copy.string(.fact_median_sleep), value: duration(median(values.map(\.durationMinutes))))
        ]
        let table = input.configuration.detailLevel == .summaryAndReadings ? ReportTable(
            title: copy.string(.table_sleep),
            columns: [copy.string(.column_night), copy.string(.column_duration)],
            rows: values.map { [date($0.date, calendar: input.calendar), duration($0.durationMinutes)] }
        ) : nil
        return summary(.sleepDuration, facts: facts, days: days, input: input, table: table)
    }

    private func workouts(_ input: ClinicianReportInput) -> MetricReportSummary {
        let interval = input.configuration.dateRange.interval(calendar: input.calendar)
        let values = dedupe(input.workoutObservations.filter { interval.contains($0.timestamp) }) { $0.stableID }
            .sorted { $0.timestamp < $1.timestamp }
        guard !values.isEmpty else { return empty(.workouts, input: input) }
        let days = Set(values.map { input.calendar.startOfDay(for: $0.timestamp) }).count
        let grouped = Dictionary(grouping: values, by: \.type)
        let breakdown = grouped.keys
            .map { (type: $0, label: copy.workoutType($0)) }
            .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
            .map { copy.format(.workout_breakdown_item, $0.label, "\(grouped[$0.type]!.count)") }
            .joined(separator: ", ")
        let facts = [
            ReportFact(label: copy.string(.fact_sessions), value: "\(values.count)"),
            ReportFact(label: copy.string(.fact_total_duration), value: duration(values.map(\.durationMinutes).reduce(0, +))),
            ReportFact(label: copy.string(.fact_workout_type), value: breakdown)
        ]
        let table = input.configuration.detailLevel == .summaryAndReadings ? ReportTable(
            title: copy.string(.table_workouts),
            columns: [copy.string(.column_date), copy.string(.column_time), copy.string(.column_type), copy.string(.column_duration)],
            rows: values.map { [date($0.timestamp, calendar: input.calendar), time($0.timestamp, calendar: input.calendar), copy.workoutType($0.type), duration($0.durationMinutes)] }
        ) : nil
        return summary(.workouts, facts: facts, days: days, input: input, table: table)
    }

    private func summary(_ metric: ReportMetric, facts: [ReportFact], days: Int, input: ClinicianReportInput, table: ReportTable?) -> MetricReportSummary {
        let expected = input.configuration.dateRange.inclusiveDayCount(calendar: input.calendar)
        return MetricReportSummary(
            metric: metric,
            facts: facts,
            availabilitySummary: availabilitySummary(metric: metric, days: days, expected: expected),
            noDataMessage: nil,
            table: table,
            localizedTitle: metric.displayName(using: copy),
            detailReadingsDescription: table.map { copy.format(.detail_readings_count, "\($0.rows.count)") }
        )
    }

    private func empty(_ metric: ReportMetric, input: ClinicianReportInput) -> MetricReportSummary {
        let expected = input.configuration.dateRange.inclusiveDayCount(calendar: input.calendar)
        return MetricReportSummary(
            metric: metric,
            facts: [],
            availabilitySummary: availabilitySummary(metric: metric, days: 0, expected: expected),
            noDataMessage: copy.string(.no_data),
            table: nil,
            localizedTitle: metric.displayName(using: copy)
        )
    }

    private func availabilitySummary(metric: ReportMetric, days: Int, expected: Int) -> String {
        let label = copy.string(metric == .sleepDuration ? .fact_nights_with_data : .fact_days_with_data)
        return "\(label): \(days)/\(expected)"
    }

    private func dedupe<T>(_ values: [T], stableID: (T) -> String?) -> [T] {
        var seen = Set<String>()
        return values.filter { value in
            guard let id = stableID(value) else { return true }
            return seen.insert(id).inserted
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func summarizedWarnings(_ values: [String]) -> [String] {
        let warnings = unique(values)
        guard warnings.count > 4 else { return warnings }

        let summaryFallback = copy.string(.warning_apple_summary_fallback)
        return unique([
            copy.string(.warning_read_failure),
            warnings.contains(summaryFallback) ? summaryFallback : nil
        ].compactMap { $0 })
    }

    private func timeZoneLabel(_ timeZone: TimeZone, at date: Date) -> String {
        let name = timeZone.localizedName(for: .generic, locale: formattingLocale)
            ?? timeZone.localizedName(for: .standard, locale: formattingLocale)
            ?? timeZone.identifier.replacingOccurrences(of: "_", with: " ")
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "−" : "+"
        let absolute = abs(seconds)
        let offset = String(format: "GMT%@%02d:%02d", sign, absolute / 3_600, (absolute % 3_600) / 60)
        return seconds == 0 ? name : "\(name) (\(offset))"
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func duration(_ minutes: Double) -> String {
        let rounded = max(0, Int(minutes.rounded()))
        let hours = rounded / 60
        let remainder = rounded % 60
        if hours == 0 { return copy.format(.duration_minutes, "\(remainder)") }
        let hourText = copy.format(.duration_hours, "\(hours)")
        if remainder == 0 { return hourText }
        return copy.format(.duration_hours_minutes, hourText, copy.format(.duration_minutes, "\(remainder)"))
    }

    private func formatValue(_ value: Double, metric: ReportMetric, input: ClinicianReportInput) -> String {
        switch metric {
        case .oxygenSaturation: one(value * 100)
        case .bodyTemperature: one(UnitConverter(preference: input.configuration.unitPreference).convertTemperature(value))
        default: one(value)
        }
    }

    private func unit(_ metric: ReportMetric, input: ClinicianReportInput) -> String {
        switch metric {
        case .heartRate, .restingHeartRate: return "bpm"
        case .bloodGlucose: return "mg/dL"
        case .oxygenSaturation: return "%"
        case .respiratoryRate: return copy.string(.unit_respiratory_rate)
        case .bodyTemperature: return UnitConverter(preference: input.configuration.unitPreference).temperatureUnit()
        default: return ""
        }
    }

    private func formatWeight(_ kilograms: Double, converter: UnitConverter) -> String {
        "\(one(converter.convertWeight(kilograms))) \(converter.weightUnit())"
    }

    private func one(_ value: Double) -> String { String(format: "%.1f", locale: formattingLocale, value) }
    private func whole(_ value: Double) -> String { String(format: "%.0f", locale: formattingLocale, value) }

    private func formatter(_ dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style, calendar: Calendar) -> DateFormatter {
        let key = "healthmd.clinician-report.\(formattingLocale.identifier).\(calendar.timeZone.identifier).\(dateStyle.rawValue).\(timeStyle.rawValue)"
        if let cached = Thread.current.threadDictionary[key] as? DateFormatter { return cached }
        let formatter = DateFormatter()
        formatter.locale = formattingLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }

    private func date(_ value: Date, calendar: Calendar) -> String { formatter(.medium, timeStyle: .none, calendar: calendar).string(from: value) }
    private func time(_ value: Date, calendar: Calendar) -> String { formatter(.none, timeStyle: .short, calendar: calendar).string(from: value) }
    private func dateTime(_ value: Date, calendar: Calendar) -> String { formatter(.medium, timeStyle: .short, calendar: calendar).string(from: value) }
}

nonisolated private extension Array where Element == Double {
    var average: Double { reduce(0, +) / Double(count) }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
