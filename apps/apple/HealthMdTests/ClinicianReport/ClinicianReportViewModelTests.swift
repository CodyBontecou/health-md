#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class ClinicianReportViewModelTests: XCTestCase {
    func testMetricSelectionShortcutsUseRecommendedDefaults() {
        let viewModel = ClinicianReportViewModel(
            dataSource: AppleClinicianReportDataSource(fetch: { _, _, _ in HealthData(date: Date()) }),
            unitPreference: .metric,
            defaults: FakeUserDefaults()
        )
        XCTAssertEqual(viewModel.configuration.selectedMetrics, ReportMetric.recommended)
        viewModel.selectAllMetrics()
        XCTAssertEqual(viewModel.configuration.selectedMetrics, Set(ReportMetric.allCases))
        viewModel.clearMetrics()
        XCTAssertTrue(viewModel.configuration.selectedMetrics.isEmpty)
        XCTAssertFalse(viewModel.canGenerateReport)
        viewModel.selectRecommendedMetrics()
        XCTAssertEqual(viewModel.configuration.selectedMetrics, ReportMetric.recommended)
    }

    func testMetricSelectionPersistsAcrossReportSessions() {
        let defaults = FakeUserDefaults()
        func makeViewModel() -> ClinicianReportViewModel {
            ClinicianReportViewModel(
                dataSource: AppleClinicianReportDataSource(fetch: { _, _, _ in HealthData(date: Date()) }),
                unitPreference: .metric,
                defaults: defaults
            )
        }

        let first = makeViewModel()
        first.toggleMetric(.bloodPressure)
        first.toggleMetric(.steps)
        let customSelection = ReportMetric.recommended
            .subtracting([.bloodPressure])
            .union([.steps])
        XCTAssertEqual(makeViewModel().configuration.selectedMetrics, customSelection)

        let allSelected = makeViewModel()
        allSelected.selectAllMetrics()
        XCTAssertEqual(makeViewModel().configuration.selectedMetrics, Set(ReportMetric.allCases))

        let empty = makeViewModel()
        empty.clearMetrics()
        let restoredEmpty = makeViewModel()
        XCTAssertTrue(restoredEmpty.configuration.selectedMetrics.isEmpty)
        XCTAssertFalse(restoredEmpty.canGenerateReport)

        restoredEmpty.selectRecommendedMetrics()
        XCTAssertEqual(makeViewModel().configuration.selectedMetrics, ReportMetric.recommended)
    }

    func testChangingConfigurationPreventsStaleReportFromWinning() async throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        var call = 0
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            call += 1
            if call == 1 { try await Task.sleep(for: .milliseconds(250)) }
            return HealthData(date: date, activity: ActivityData(steps: call == 1 ? 1 : 2), healthKitRecordCaptureStatus: .complete)
        }, now: { today })
        let viewModel = ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { today }
        )
        viewModel.configuration.selectedMetrics = [.steps]
        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await Task.yield()
        viewModel.selectPreset(.days7)
        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(viewModel.configuration.dateRange.inclusiveDayCount(calendar: calendar), 7)
        XCTAssertEqual(viewModel.report?.sections.first?.facts.first { $0.label == "Total" }?.value, "14 steps")
    }

    func testCancelStopsLoadingState() async {
        let zone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let source = AppleClinicianReportDataSource(fetch: { _, _, _ in
            try await Task.sleep(for: .seconds(30))
            return HealthData(date: now)
        }, now: { now })
        let viewModel = ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { now }
        )
        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await Task.yield()
        XCTAssertTrue(viewModel.isLoading)
        viewModel.cancel()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRendering)
        XCTAssertEqual(viewModel.preparationProgress, 0)
        XCTAssertEqual(viewModel.renderingProgress, 0)
    }

    func testGenerateReportCreatesPreviewAndPDF() async throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            HealthData(
                date: date,
                activity: ActivityData(steps: 1_234),
                healthKitRecordCaptureStatus: .complete
            )
        }, now: { today })
        let viewModel = ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { today }
        )
        viewModel.configuration.dateRange = .init(startDate: today, endDate: today)
        viewModel.configuration.selectedMetrics = [.steps]

        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        for _ in 0..<100 where viewModel.artifact == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(viewModel.report)
        XCTAssertNotNil(viewModel.artifact)
        XCTAssertEqual(viewModel.renderingProgress, 1)

        viewModel.editConfiguration()
        XCTAssertNil(viewModel.report)
        XCTAssertNil(viewModel.artifact)
        XCTAssertEqual(viewModel.configuration.selectedMetrics, [.steps])
    }

    func testAllEmptyReportSkipsPDFGeneration() async throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_767_225_600)
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            HealthData(date: date, healthKitRecordCaptureStatus: .complete)
        }, now: { today })
        let viewModel = ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { today }
        )
        viewModel.configuration.dateRange = .init(startDate: today, endDate: today)
        viewModel.configuration.selectedMetrics = [.bloodGlucose]

        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        for _ in 0..<100 where viewModel.report == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(viewModel.report)
        XCTAssertFalse(viewModel.canGeneratePDF)
        viewModel.generatePDF()
        await Task.yield()
        XCTAssertFalse(viewModel.isRendering)
        XCTAssertNil(viewModel.artifact)
    }
}
#endif
