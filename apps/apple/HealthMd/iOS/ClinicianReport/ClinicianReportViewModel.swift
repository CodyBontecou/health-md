import Combine
import Foundation

@MainActor
final class ClinicianReportViewModel: ObservableObject {
    private static let selectedMetricsDefaultsKey = "clinicianReport.selectedMetrics.v1"

    @Published var configuration: ReportConfiguration
    @Published private(set) var selectedPreset: ReportDateRangePreset = .days30
    @Published private(set) var report: ClinicianReportData?
    @Published private(set) var artifact: ExportArtifactFile?
    @Published private(set) var isLoading = false
    @Published private(set) var isRendering = false
    @Published private(set) var preparationProgress = 0.0
    @Published private(set) var renderingProgress = 0.0
    @Published private(set) var errorMessage: String?

    private let dataSource: AppleClinicianReportDataSource
    private let renderer: ClinicianReportPDFRenderer
    private let defaults: UserDefaultsStoring
    private let timeZone: () -> TimeZone
    private let today: () -> Date
    private var activeTask: Task<Void, Never>?
    private var reportCalendar: Calendar?
    private var generation = UUID()

    init(
        dataSource: AppleClinicianReportDataSource,
        unitPreference: UnitPreference,
        renderer: ClinicianReportPDFRenderer = ClinicianReportPDFRenderer(),
        defaults: UserDefaultsStoring = SystemUserDefaults(),
        timeZone: @escaping () -> TimeZone = { .current },
        today: @escaping () -> Date = Date.init
    ) {
        self.dataSource = dataSource
        self.renderer = renderer
        self.defaults = defaults
        self.timeZone = timeZone
        self.today = today
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone()
        self.configuration = ReportConfiguration(
            dateRange: .preset(.days30, today: today(), calendar: calendar),
            selectedMetrics: Self.restoredSelectedMetrics(from: defaults) ?? ReportMetric.recommended,
            unitPreference: unitPreference
        )
    }

    var canGenerateReport: Bool {
        !configuration.selectedMetrics.isEmpty && !isLoading && !isRendering
    }

    var canGeneratePDF: Bool {
        report?.hasReportableData == true && !isLoading && !isRendering
    }

    func selectPreset(_ preset: ReportDateRangePreset) {
        selectedPreset = preset
        guard preset != .custom else {
            invalidateOutput()
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone()
        updateConfiguration { $0.dateRange = .preset(preset, today: today(), calendar: calendar) }
    }

    func setCustomRange(start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone()
        selectedPreset = .custom
        updateConfiguration {
            $0.dateRange = .normalized(start: start, end: end, today: today(), calendar: calendar)
        }
    }

    func toggleMetric(_ metric: ReportMetric) {
        updateMetricSelection {
            if $0.contains(metric) { $0.remove(metric) }
            else { $0.insert(metric) }
        }
    }

    func selectRecommendedMetrics() {
        updateMetricSelection { $0 = ReportMetric.recommended }
    }

    func selectAllMetrics() {
        updateMetricSelection { $0 = Set(ReportMetric.allCases) }
    }

    func clearMetrics() {
        updateMetricSelection { $0.removeAll() }
    }

    func setDetailLevel(_ level: ReportDetailLevel) {
        updateConfiguration { $0.detailLevel = level }
    }

    func setDisplayName(_ name: String) {
        updateConfiguration { $0.displayName = name }
    }

    func editConfiguration() {
        invalidateOutput()
    }

    func generateReport(locale: Locale = .current) {
        guard canGenerateReport else { return }
        cancelOperation(resetOutput: true)
        let token = generation
        let snapshot = configuration
        let zone = timeZone()
        let copy = ClinicianReportCopy(locale: locale)
        isLoading = true
        preparationProgress = 0
        errorMessage = nil
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let input = try await dataSource.load(
                    configuration: snapshot,
                    timeZone: zone,
                    locale: locale
                ) { [weak self] completedDays, totalDays in
                    guard let self, token == generation else { return }
                    preparationProgress = totalDays > 0
                        ? min(max(Double(completedDays) / Double(totalDays), 0), 1)
                        : 1
                }
                try Task.checkCancellation()
                let generated = ClinicianReportGenerator(locale: locale).generate(input)
                guard token == generation else { return }
                preparationProgress = 1
                configuration = input.configuration
                reportCalendar = input.calendar
                report = generated
                isLoading = false
                activeTask = nil
                if generated.hasReportableData {
                    generatePDF()
                }
            } catch is CancellationError {
                guard token == generation else { return }
                isLoading = false
                activeTask = nil
            } catch {
                guard token == generation else { return }
                isLoading = false
                errorMessage = copy.string(.error_prepare_apple)
                activeTask = nil
            }
        }
    }

    func generatePDF() {
        guard canGeneratePDF, let report else { return }
        cancelOperation(resetOutput: false)
        let token = generation
        artifact = nil
        renderingProgress = 0
        let range = configuration.dateRange
        let calendar: Calendar
        if let reportCalendar {
            calendar = reportCalendar
        } else {
            var fallback = Calendar(identifier: .gregorian)
            fallback.timeZone = timeZone()
            calendar = fallback
        }
        isRendering = true
        errorMessage = nil
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let renderer = self.renderer
                let renderTask = Task.detached(priority: .userInitiated) {
                    try renderer.renderArtifact(
                        report: report,
                        startDate: range.startDate,
                        endDate: range.endDate,
                        calendar: calendar,
                        pageSize: .forRegion(report.paperRegionCode),
                        progress: { value in
                            Task { @MainActor [weak self] in
                                guard let self, token == generation, isRendering else { return }
                                renderingProgress = max(renderingProgress, min(max(value, 0), 1))
                            }
                        }
                    )
                }
                let rendered = try await withTaskCancellationHandler {
                    try await renderTask.value
                } onCancel: {
                    renderTask.cancel()
                }
                try Task.checkCancellation()
                guard token == generation else { return }
                renderingProgress = 1
                artifact = rendered
                isRendering = false
                activeTask = nil
            } catch is CancellationError {
                guard token == generation else { return }
                isRendering = false
                activeTask = nil
            } catch {
                guard token == generation else { return }
                isRendering = false
                errorMessage = ClinicianReportCopy(locale: Locale(identifier: report.languageTag)).string(.error_pdf)
                activeTask = nil
            }
        }
    }

    func cancel() {
        cancelOperation(resetOutput: false)
        isLoading = false
        isRendering = false
    }

    private func updateConfiguration(_ change: (inout ReportConfiguration) -> Void) {
        cancelOperation(resetOutput: true)
        change(&configuration)
        errorMessage = nil
    }

    private func updateMetricSelection(_ change: (inout Set<ReportMetric>) -> Void) {
        updateConfiguration { change(&$0.selectedMetrics) }
        persistSelectedMetrics()
    }

    private func persistSelectedMetrics() {
        let rawValues = configuration.selectedMetrics.map(\.rawValue).sorted()
        guard let data = try? JSONEncoder().encode(rawValues) else { return }
        defaults.set(data, forKey: Self.selectedMetricsDefaultsKey)
    }

    private static func restoredSelectedMetrics(from defaults: UserDefaultsStoring) -> Set<ReportMetric>? {
        guard let data = defaults.data(forKey: selectedMetricsDefaultsKey),
              let rawValues = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        if rawValues.isEmpty { return [] }
        let metrics = Set(rawValues.compactMap(ReportMetric.init(rawValue:)))
        return metrics.isEmpty ? nil : metrics
    }

    private func invalidateOutput() {
        cancelOperation(resetOutput: true)
        errorMessage = nil
    }

    private func cancelOperation(resetOutput: Bool) {
        activeTask?.cancel()
        activeTask = nil
        generation = UUID()
        isLoading = false
        isRendering = false
        preparationProgress = 0
        renderingProgress = 0
        if resetOutput {
            report = nil
            reportCalendar = nil
            artifact = nil
        }
    }

    // Final ownership makes task cancellation safe without a main-actor hop. Avoid
    // Swift 6.2+'s broken isolated-deinit path for synchronously released iOS VMs
    // (swiftlang/swift#85663).
    nonisolated deinit {
        activeTask?.cancel()
    }
}
