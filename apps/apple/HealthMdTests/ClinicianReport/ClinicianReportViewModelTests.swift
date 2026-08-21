#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
private final class ClinicianReportAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class ClinicianReportViewModelTests: XCTestCase {
    // ClinicianReportViewModel is an ObservableObject. Keep test instances alive through
    // process exit to avoid the Xcode 26 simulator runtime deinit bug documented in
    // docs/testing/lifecycle-audit.md.
    func testMetricSelectionShortcutsUseRecommendedDefaults() {
        let viewModel = LifecycleHarness.retain(ClinicianReportViewModel(
            dataSource: AppleClinicianReportDataSource(fetch: { _, _, _ in HealthData(date: Date()) }),
            unitPreference: .metric,
            defaults: FakeUserDefaults()
        ))
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
            LifecycleHarness.retain(ClinicianReportViewModel(
                dataSource: AppleClinicianReportDataSource(fetch: { _, _, _ in HealthData(date: Date()) }),
                unitPreference: .metric,
                defaults: defaults
            ))
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

    func testBusyPreparationRejectsEveryConfigurationMutationAndCompletesOriginalSnapshot() async {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        let fetchStarted = expectation(description: "report fetch started")
        let gate = ClinicianReportAsyncGate()
        defer { gate.open() }
        var fetchCount = 0
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            fetchCount += 1
            fetchStarted.fulfill()
            await gate.wait()
            return HealthData(
                date: date,
                activity: ActivityData(steps: 1_234),
                healthKitRecordCaptureStatus: .complete
            )
        }, now: { today })
        let defaults = FakeUserDefaults()
        let viewModel = LifecycleHarness.retain(ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: defaults,
            timeZone: { zone },
            today: { today }
        ))
        viewModel.setCustomRange(start: today, end: today)
        viewModel.clearMetrics()
        viewModel.toggleMetric(.steps)
        viewModel.setDisplayName("Original")
        let originalConfiguration = viewModel.configuration
        let originalPreset = viewModel.selectedPreset

        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await fulfillment(of: [fetchStarted], timeout: 2)

        XCTAssertTrue(viewModel.isBusy)
        XCTAssertFalse(viewModel.isConfigurationEditable)
        let earlier = calendar.date(byAdding: .day, value: -3, to: today)!
        viewModel.selectPreset(.days7)
        viewModel.setCustomRange(start: earlier, end: earlier)
        viewModel.toggleMetric(.heartRate)
        viewModel.selectRecommendedMetrics()
        viewModel.selectAllMetrics()
        viewModel.clearMetrics()
        viewModel.setDetailLevel(.summaryAndReadings)
        viewModel.setDisplayName("Queued mutation")
        viewModel.editConfiguration()
        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        viewModel.generatePDF()

        XCTAssertEqual(fetchCount, 1)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.isBusy)
        XCTAssertFalse(viewModel.isConfigurationEditable)
        XCTAssertEqual(viewModel.configuration, originalConfiguration)
        XCTAssertEqual(viewModel.selectedPreset, originalPreset)

        let restored = LifecycleHarness.retain(ClinicianReportViewModel(
            dataSource: AppleClinicianReportDataSource(fetch: { _, _, _ in HealthData(date: today) }),
            unitPreference: .metric,
            defaults: defaults,
            timeZone: { zone },
            today: { today }
        ))
        XCTAssertEqual(restored.configuration.selectedMetrics, [.steps])

        gate.open()
        await waitUntil("the original report and PDF finish") {
            viewModel.artifact != nil && !viewModel.isBusy
        }

        XCTAssertEqual(viewModel.configuration, originalConfiguration)
        XCTAssertEqual(viewModel.report?.displayName, "Original")
        XCTAssertEqual(viewModel.report?.detailLevel, .summary)
        XCTAssertEqual(viewModel.report?.sections.map(\.metric), [.steps])
        XCTAssertTrue(viewModel.isConfigurationEditable)
    }

    func testChangingConfigurationPreventsStaleReportFromWinning() async {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        let firstStarted = expectation(description: "first report fetch started")
        let firstGate = ClinicianReportAsyncGate()
        defer { firstGate.open() }
        var call = 0
        var firstReturned = false
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            call += 1
            let currentCall = call
            if currentCall == 1 {
                firstStarted.fulfill()
                await firstGate.wait()
                firstReturned = true
            }
            return HealthData(
                date: date,
                activity: ActivityData(steps: currentCall),
                healthKitRecordCaptureStatus: .complete
            )
        }, now: { today })
        let viewModel = LifecycleHarness.retain(ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { today }
        ))
        viewModel.setCustomRange(start: today, end: today)
        viewModel.clearMetrics()
        viewModel.toggleMetric(.steps)
        viewModel.setDisplayName("First")

        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await fulfillment(of: [firstStarted], timeout: 2)
        viewModel.cancel()
        XCTAssertTrue(viewModel.isConfigurationEditable)
        viewModel.setDisplayName("Replacement")
        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await waitUntil("the replacement report finishes") {
            viewModel.report?.displayName == "Replacement" && !viewModel.isBusy
        }
        XCTAssertEqual(
            viewModel.report?.sections.first?.facts.first { $0.label == "Total" }?.value,
            "2 steps"
        )

        firstGate.open()
        await waitUntil("the cancelled stale read returns") { firstReturned }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.report?.displayName, "Replacement")
        XCTAssertEqual(
            viewModel.report?.sections.first?.facts.first { $0.label == "Total" }?.value,
            "2 steps"
        )
    }

    func testCancelStopsLoadingState() async {
        let zone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let source = AppleClinicianReportDataSource(fetch: { _, _, _ in
            try await Task.sleep(for: .seconds(30))
            return HealthData(date: now)
        }, now: { now })
        let viewModel = LifecycleHarness.retain(ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { now }
        ))
        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await Task.yield()
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.isConfigurationEditable)
        viewModel.cancel()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRendering)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertTrue(viewModel.isConfigurationEditable)
        XCTAssertEqual(viewModel.preparationProgress, 0)
        XCTAssertEqual(viewModel.renderingProgress, 0)
    }

    func testGenerateReportCreatesPreviewAndPDF() async {
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
        let viewModel = LifecycleHarness.retain(ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { today }
        ))
        viewModel.setCustomRange(start: today, end: today)
        viewModel.clearMetrics()
        viewModel.toggleMetric(.steps)

        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await waitUntil("the report PDF finishes") { viewModel.artifact != nil }
        XCTAssertNotNil(viewModel.report)
        XCTAssertNotNil(viewModel.artifact)
        XCTAssertEqual(viewModel.renderingProgress, 1)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertTrue(viewModel.isConfigurationEditable)

        viewModel.editConfiguration()
        XCTAssertNil(viewModel.report)
        XCTAssertNil(viewModel.artifact)
        XCTAssertEqual(viewModel.configuration.selectedMetrics, [.steps])
    }

    func testAllEmptyReportSkipsPDFGeneration() async {
        let zone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_767_225_600)
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            HealthData(date: date, healthKitRecordCaptureStatus: .complete)
        }, now: { today })
        let viewModel = LifecycleHarness.retain(ClinicianReportViewModel(
            dataSource: source,
            unitPreference: .metric,
            defaults: FakeUserDefaults(),
            timeZone: { zone },
            today: { today }
        ))
        viewModel.setCustomRange(start: today, end: today)
        viewModel.clearMetrics()
        viewModel.toggleMetric(.bloodGlucose)

        viewModel.generateReport(locale: Locale(identifier: "en_US"))
        await waitUntil("the empty report finishes") { viewModel.report != nil }

        XCTAssertNotNil(viewModel.report)
        XCTAssertFalse(viewModel.canGeneratePDF)
        viewModel.generatePDF()
        await Task.yield()
        XCTAssertFalse(viewModel.isRendering)
        XCTAssertNil(viewModel.artifact)
        XCTAssertTrue(viewModel.isConfigurationEditable)
    }

    private func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }
}
#endif
