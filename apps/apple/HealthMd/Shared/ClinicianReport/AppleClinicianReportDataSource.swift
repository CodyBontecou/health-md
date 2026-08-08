import Foundation

@MainActor
final class AppleClinicianReportDataSource {
    typealias Fetch = (_ date: Date, _ selection: MetricSelectionState, _ timeZone: TimeZone) async throws -> HealthData

    private let fetch: Fetch
    private let now: () -> Date
    private let sourceAdapter: AppleClinicianReportSourceAdapter

    init(
        fetch: @escaping Fetch,
        now: @escaping () -> Date = Date.init,
        sourceAdapter: AppleClinicianReportSourceAdapter = AppleClinicianReportSourceAdapter()
    ) {
        self.fetch = fetch
        self.now = now
        self.sourceAdapter = sourceAdapter
    }

    convenience init(healthKitManager: HealthKitManager, now: @escaping () -> Date = Date.init) {
        self.init(fetch: { date, selection, timeZone in
            try await healthKitManager.fetchHealthData(
                for: date,
                includeGranularData: true,
                metricSelection: selection,
                timeZone: timeZone
            )
        }, now: now)
    }

    func load(
        configuration: ReportConfiguration,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) async throws -> ClinicianReportInput {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let generationDate = now()
        let normalizedRange = configuration.dateRange.normalized(today: generationDate, calendar: calendar)
        let normalizedConfiguration = ReportConfiguration(
            dateRange: normalizedRange,
            selectedMetrics: configuration.selectedMetrics,
            detailLevel: configuration.detailLevel,
            unitPreference: configuration.unitPreference,
            displayName: configuration.displayName
        )
        let selection = Self.metricSelection(for: normalizedConfiguration.selectedMetrics)
        let copy = ClinicianReportCopy(locale: locale)
        var input = ClinicianReportInput(
            configuration: normalizedConfiguration,
            calendar: calendar,
            generatedAt: generationDate
        )

        for date in normalizedRange.dates(calendar: calendar) {
            try Task.checkCancellation()
            do {
                let healthData = try await fetch(date, selection, timeZone)
                try Task.checkCancellation()
                let day = sourceAdapter.adapt(
                    healthData,
                    configuration: normalizedConfiguration,
                    calendar: calendar,
                    copy: copy
                )
                try Task.checkCancellation()
                input.scalarObservations.append(contentsOf: day.scalars)
                input.bloodPressureObservations.append(contentsOf: day.bloodPressure)
                input.dailyValues.append(contentsOf: day.daily)
                input.sleepObservations.append(contentsOf: day.sleep)
                input.workoutObservations.append(contentsOf: day.workouts)
                input.warnings.append(contentsOf: day.warnings)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                input.warnings.append(copy.format(
                    .warning_apple_read_failure_date,
                    Self.isoDate(date, calendar: calendar)
                ))
            }
        }
        input.warnings = input.warnings.uniqued()
        return input
    }

    static func metricSelection(for metrics: Set<ReportMetric>) -> MetricSelectionState {
        let selection = MetricSelectionState()
        selection.deselectAll()
        var ids = Set<String>()
        for metric in metrics {
            switch metric {
            case .bloodPressure:
                ids.formUnion(["blood_pressure_systolic", "blood_pressure_diastolic"])
            case .restingHeartRate: ids.insert("resting_heart_rate")
            case .heartRate: ids.insert("heart_rate_avg")
            case .weight: ids.insert("weight")
            case .bloodGlucose: ids.insert("blood_glucose")
            case .oxygenSaturation: ids.insert("blood_oxygen")
            case .respiratoryRate: ids.insert("respiratory_rate")
            case .bodyTemperature: ids.insert("body_temperature")
            case .sleepDuration: ids.insert("sleep_total")
            case .steps: ids.insert("steps")
            case .workouts: ids.insert("workouts")
            }
        }
        selection.enabledMetrics = ids.intersection(HealthMetrics.availableMetricIDsInCurrentBuild)
        selection.enabledCategories = Set(
            HealthMetrics.availableInCurrentBuild
                .filter { selection.enabledMetrics.contains($0.id) }
                .map { $0.category.rawValue }
        )
        return selection
    }

    private static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
