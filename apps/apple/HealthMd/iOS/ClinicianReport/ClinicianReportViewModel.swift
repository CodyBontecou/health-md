import Combine
import Foundation

@MainActor
final class ClinicianReportViewModel: ObservableObject {
    @Published var configuration: ReportConfiguration
    @Published private(set) var selectedPreset: ReportDateRangePreset = .days30
    @Published private(set) var report: ClinicianReportData?
    @Published private(set) var artifact: ExportArtifactFile?
    @Published private(set) var isLoading = false
    @Published private(set) var isRendering = false
    @Published private(set) var errorMessage: String?

    private let dataSource: AppleClinicianReportDataSource
    private let renderer: ClinicianReportPDFRenderer
    private let timeZone: () -> TimeZone
    private let today: () -> Date
    private var activeTask: Task<Void, Never>?
    private var reportCalendar: Calendar?
    private var generation = UUID()

    init(
        dataSource: AppleClinicianReportDataSource,
        unitPreference: UnitPreference,
        renderer: ClinicianReportPDFRenderer = ClinicianReportPDFRenderer(),
        timeZone: @escaping () -> TimeZone = { .current },
        today: @escaping () -> Date = Date.init
    ) {
        self.dataSource = dataSource
        self.renderer = renderer
        self.timeZone = timeZone
        self.today = today
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone()
        self.configuration = ReportConfiguration(
            dateRange: .preset(.days30, today: today(), calendar: calendar),
            unitPreference: unitPreference
        )
    }

    var canPreview: Bool {
        !configuration.selectedMetrics.isEmpty && !isLoading && !isRendering
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
        updateConfiguration {
            if $0.selectedMetrics.contains(metric) { $0.selectedMetrics.remove(metric) }
            else { $0.selectedMetrics.insert(metric) }
        }
    }

    func setDetailLevel(_ level: ReportDetailLevel) {
        updateConfiguration { $0.detailLevel = level }
    }

    func setDisplayName(_ name: String) {
        updateConfiguration { $0.displayName = name }
    }

    func preview(locale: Locale = .current) {
        guard canPreview else { return }
        cancelOperation(resetOutput: true)
        let token = generation
        let snapshot = configuration
        let zone = timeZone()
        let copy = ClinicianReportCopy(locale: locale)
        isLoading = true
        errorMessage = nil
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let input = try await dataSource.load(configuration: snapshot, timeZone: zone, locale: locale)
                try Task.checkCancellation()
                let generated = ClinicianReportGenerator(locale: locale).generate(input)
                guard token == generation else { return }
                configuration = input.configuration
                reportCalendar = input.calendar
                report = generated
                isLoading = false
                activeTask = nil
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
        guard let report else { return }
        cancelOperation(resetOutput: false)
        let token = generation
        artifact = nil
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
                        pageSize: .forRegion(report.paperRegionCode)
                    )
                }
                let rendered = try await withTaskCancellationHandler {
                    try await renderTask.value
                } onCancel: {
                    renderTask.cancel()
                }
                try Task.checkCancellation()
                guard token == generation else { return }
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
        if resetOutput {
            report = nil
            reportCalendar = nil
            artifact = nil
        }
    }

    deinit {
        activeTask?.cancel()
    }
}
