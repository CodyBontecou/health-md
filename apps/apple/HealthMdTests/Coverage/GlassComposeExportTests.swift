#if os(iOS)
import XCTest
@testable import HealthMd

final class GlassComposeExportTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ value: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: value, hour: hour))!
    }

    // MARK: Composer preview

    func testTomorrowsRunWritesToday() {
        let target = ComposerPreviewPlan.target(nextRun: day(31, hour: 7), includesToday: false, now: day(30, hour: 20), calendar: calendar)
        XCTAssertEqual(target, .init(date: day(30), kind: .tomorrow))
    }

    func testLaterRunNeverPreviewsTheFuture() {
        let target = ComposerPreviewPlan.target(nextRun: day(28, hour: 8).addingTimeInterval(7 * 86_400), includesToday: true, now: day(30, hour: 9), calendar: calendar)
        XCTAssertEqual(target, .init(date: day(30), kind: .nextRun))
    }

    func testUnscheduledProfilePreviewsYesterday() {
        let target = ComposerPreviewPlan.target(nextRun: nil, includesToday: false, now: day(30, hour: 9), calendar: calendar)
        XCTAssertEqual(target, .init(date: day(29), kind: .yesterday))
    }

    func testLinesAreNumberedAndFencesAreMuted() {
        let result = ComposerPreviewPlan.lines(of: "---\ndate: 2026-10-30\nsteps: 8412\n---\n", limit: 3)
        XCTAssertEqual(result.lines.map(\.number), [1, 2, 3])
        XCTAssertEqual(result.lines.map(\.isMeta), [true, true, false])
        XCTAssertTrue(result.isTruncated)
        XCTAssertFalse(ComposerPreviewPlan.lines(of: "{\n}\n", limit: 3).isTruncated)
    }

    // MARK: Automation rows

    func testScheduleAndFormatLabels() {
        XCTAssertEqual(AutomationFacts.scheduleShortLabel(nil), String(localized: "Off"))
        XCTAssertEqual(AutomationFacts.formatsShortLabel([.obsidianBases, .markdown]), "MD · Bases")
        XCTAssertEqual(AutomationFacts.formatStyleLabel(.from(FormatCustomization())), String(localized: "Standard"))
    }

    // MARK: Export result

    func testResultRowsListShortRunsAndCollapseLongOnes() {
        let rows = ExportResultDays.rows(start: day(24), end: day(30), failed: [(day(28, hour: 9), "Locked")], calendar: calendar)
        XCTAssertEqual(rows, [
            .complete(start: day(30), end: day(30)),
            .complete(start: day(29), end: day(29)),
            .failed(date: day(28), reason: "Locked"),
            .complete(start: day(24), end: day(27))
        ])
    }


}
#endif
