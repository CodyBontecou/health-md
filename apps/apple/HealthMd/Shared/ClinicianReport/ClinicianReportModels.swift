import Foundation

/// Ephemeral report configuration. This is intentionally not Codable or persisted.
nonisolated struct ReportConfiguration: Equatable {
    var dateRange: ReportDateRange
    var selectedMetrics: Set<ReportMetric>
    var detailLevel: ReportDetailLevel
    var unitPreference: UnitPreference
    var displayName: String

    init(
        dateRange: ReportDateRange = .preset(.days30),
        selectedMetrics: Set<ReportMetric> = Set(ReportMetric.allCases),
        detailLevel: ReportDetailLevel = .summary,
        unitPreference: UnitPreference = .metric,
        displayName: String = ""
    ) {
        self.dateRange = dateRange
        self.selectedMetrics = selectedMetrics
        self.detailLevel = detailLevel
        self.unitPreference = unitPreference
        self.displayName = displayName
    }
}

nonisolated enum ReportDateRangePreset: String, CaseIterable, Identifiable {
    case days7
    case days30
    case days90
    case custom

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .days90: return 90
        case .custom: return nil
        }
    }

    func title(using copy: ClinicianReportCopy) -> String {
        switch self {
        case .days7: return copy.string(.days_7)
        case .days30: return copy.string(.days_30)
        case .days90: return copy.string(.days_90)
        case .custom: return copy.string(.custom)
        }
    }

    var title: String { title(using: ClinicianReportCopy()) }
}

nonisolated struct ReportDateRange: Equatable {
    let startDate: Date
    let endDate: Date

    static func preset(
        _ preset: ReportDateRangePreset,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> ReportDateRange {
        precondition(preset != .custom)
        let todayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -(preset.dayCount! - 1), to: todayStart)!
        return ReportDateRange(startDate: start, endDate: todayStart)
    }

    static func normalized(
        start: Date,
        end: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> ReportDateRange {
        let todayStart = calendar.startOfDay(for: today)
        let first = min(calendar.startOfDay(for: start), todayStart)
        let last = min(calendar.startOfDay(for: end), todayStart)
        return ReportDateRange(startDate: min(first, last), endDate: max(first, last))
    }

    func normalized(today: Date = Date(), calendar: Calendar) -> ReportDateRange {
        .normalized(start: startDate, end: endDate, today: today, calendar: calendar)
    }

    func dates(calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        let final = calendar.startOfDay(for: endDate)
        while cursor <= final {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    func interval(calendar: Calendar) -> Range<Date> {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        return start..<end
    }

    func inclusiveDayCount(calendar: Calendar) -> Int {
        dates(calendar: calendar).count
    }
}

nonisolated enum ReportDetailLevel: String, CaseIterable, Identifiable {
    case summary
    case summaryAndReadings
    var id: String { rawValue }
}

nonisolated enum ReportMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bloodPressure
    case restingHeartRate
    case heartRate
    case weight
    case bloodGlucose
    case oxygenSaturation
    case respiratoryRate
    case bodyTemperature
    case sleepDuration
    case steps
    case workouts

    var id: String { rawValue }

    func displayName(using copy: ClinicianReportCopy) -> String {
        switch self {
        case .bloodPressure: return copy.string(.metric_blood_pressure)
        case .restingHeartRate: return copy.string(.metric_resting_heart_rate)
        case .heartRate: return copy.string(.metric_heart_rate)
        case .weight: return copy.string(.metric_weight)
        case .bloodGlucose: return copy.string(.metric_blood_glucose)
        case .oxygenSaturation: return copy.string(.metric_oxygen_saturation)
        case .respiratoryRate: return copy.string(.metric_respiratory_rate)
        case .bodyTemperature: return copy.string(.metric_body_temperature)
        case .sleepDuration: return copy.string(.metric_sleep_duration)
        case .steps: return copy.string(.metric_steps)
        case .workouts: return copy.string(.metric_workouts)
        }
    }

    var displayName: String { displayName(using: ClinicianReportCopy()) }
}

nonisolated struct ReportSource: Equatable {
    let label: String
    let isManualEntry: Bool

    init(label: String, isManualEntry: Bool = false) {
        self.label = label
        self.isManualEntry = isManualEntry
    }

    func displayLabel(using copy: ClinicianReportCopy) -> String {
        guard isManualEntry else { return label }
        let manualEntry = copy.string(.manual_entry)
        guard !label.localizedCaseInsensitiveContains(manualEntry) else { return label }
        return label.isEmpty ? manualEntry : copy.format(.manual_entry_source, label)
    }

    var displayLabel: String { displayLabel(using: ClinicianReportCopy()) }
}

nonisolated struct ScalarReportObservation: Equatable {
    let metric: ReportMetric
    let timestamp: Date
    let value: Double
    let stableID: String?
    let source: ReportSource?

    init(metric: ReportMetric, timestamp: Date, value: Double, stableID: String? = nil, source: ReportSource? = nil) {
        self.metric = metric
        self.timestamp = timestamp
        self.value = value
        self.stableID = stableID
        self.source = source
    }
}

nonisolated struct BloodPressureReportObservation: Equatable {
    let timestamp: Date
    let systolic: Double
    let diastolic: Double
    let stableID: String?
    let source: ReportSource?
}

nonisolated struct DailyReportValue: Equatable {
    let metric: ReportMetric
    let date: Date
    let value: Double
    let timestamp: Date?
    let stableID: String?
    let source: ReportSource?

    init(metric: ReportMetric, date: Date, value: Double, timestamp: Date? = nil, stableID: String? = nil, source: ReportSource? = nil) {
        self.metric = metric
        self.date = date
        self.value = value
        self.timestamp = timestamp
        self.stableID = stableID
        self.source = source
    }
}

nonisolated struct SleepReportObservation: Equatable {
    let date: Date
    let durationMinutes: Double
    let stableID: String?
    let source: ReportSource?
}

nonisolated struct WorkoutReportObservation: Equatable {
    let timestamp: Date
    let type: WorkoutType
    let durationMinutes: Double
    let stableID: String?
    let source: ReportSource?
}

nonisolated struct ClinicianReportInput: Equatable {
    let configuration: ReportConfiguration
    let calendar: Calendar
    let generatedAt: Date
    var scalarObservations: [ScalarReportObservation] = []
    var bloodPressureObservations: [BloodPressureReportObservation] = []
    var dailyValues: [DailyReportValue] = []
    var sleepObservations: [SleepReportObservation] = []
    var workoutObservations: [WorkoutReportObservation] = []
    var warnings: [String] = []
}

nonisolated struct ReportFact: Equatable, Sendable {
    let label: String
    let value: String
}

nonisolated struct ReportTable: Equatable, Sendable {
    let title: String
    let columns: [String]
    let rows: [[String]]
}

nonisolated struct MetricReportSummary: Equatable, Identifiable, Sendable {
    let metric: ReportMetric
    let facts: [ReportFact]
    let sources: [String]
    let coverageDisclosure: String?
    let noDataMessage: String?
    let table: ReportTable?
    var localizedTitle: String = ""
    var sourcesDisclosure: String? = nil
    var detailReadingsDescription: String? = nil
    var id: ReportMetric { metric }
}

nonisolated enum ReportCompleteness: Equatable, Sendable {
    case complete
    case partial
}

nonisolated struct ClinicianReportData: Equatable, Sendable {
    let title: String
    let displayName: String?
    let dateRangeLabel: String
    let generatedLabel: String
    let timeZoneLabel: String
    let sections: [MetricReportSummary]
    let warnings: [String]
    let completeness: ReportCompleteness
    let disclaimer: String
    let attribution: String
    let practiceLine: String?
    var languageTag: String = "en"
    /// Region captured with the report locale solely for native Letter/A4 selection.
    var paperRegionCode: String? = nil
    var pdfSubject: String = ""
    var pdfKeywords: [String] = []
    var metadataPeriodLabel: String = ""
    var metadataGeneratedLabel: String = ""
    var metadataTimeZoneLabel: String = ""
    var metadataPatientLabel: String = ""
    var availabilityNoteTitle: String = ""
    var aboutTitle: String = ""
    var pageFooterTemplate: String = ""
}
