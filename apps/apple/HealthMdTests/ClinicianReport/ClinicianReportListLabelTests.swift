#if os(iOS)
import XCTest
@testable import HealthMd

/// ClinicianReportG's on-screen labels are UI-only; the PDF keeps the shared report copy.
final class ClinicianReportListLabelTests: XCTestCase {
    func testListUsesBoardWordingWhileReportCopyKeepsContractWording() {
        let copy = ClinicianReportCopy(locale: Locale(identifier: "en"))

        XCTAssertEqual(ClinicianReportView.listLabel(for: .restingHeartRate), "Resting heart rate")
        XCTAssertEqual(ClinicianReportView.listLabel(for: .sleepDuration), "Sleep")
        XCTAssertEqual(ReportMetric.restingHeartRate.displayName(using: copy), "Resting Heart Rate")
        XCTAssertEqual(ReportMetric.sleepDuration.displayName(using: copy), "Sleep Duration")
    }

    func testEveryMetricHasADistinctListLabel() {
        let labels = ReportMetric.allCases.map(ClinicianReportView.listLabel(for:))
        XCTAssertEqual(Set(labels).count, ReportMetric.allCases.count)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }
}
#endif
