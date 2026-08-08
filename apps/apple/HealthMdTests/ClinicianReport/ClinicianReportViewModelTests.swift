#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class ClinicianReportViewModelTests: XCTestCase {
    func testChangingConfigurationPreventsStalePreviewFromWinning() async throws {
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
            timeZone: { zone },
            today: { today }
        )
        viewModel.configuration.selectedMetrics = [.steps]
        viewModel.preview(locale: Locale(identifier: "en_US"))
        await Task.yield()
        viewModel.selectPreset(.days7)
        viewModel.preview(locale: Locale(identifier: "en_US"))
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
        let viewModel = ClinicianReportViewModel(dataSource: source, unitPreference: .metric, timeZone: { zone }, today: { now })
        viewModel.preview(locale: Locale(identifier: "en_US"))
        await Task.yield()
        XCTAssertTrue(viewModel.isLoading)
        viewModel.cancel()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRendering)
    }
}
#endif
