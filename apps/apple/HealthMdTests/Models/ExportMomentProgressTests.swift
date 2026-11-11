import XCTest
@testable import HealthMd

@MainActor
final class ExportMomentProgressTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: value))!
    }

    private func progress(_ message: String, fraction: Double) -> ExportMomentProgress {
        ExportMomentProgress.make(message: message, progress: fraction,
                                  start: day(24), end: day(30), calendar: calendar)
    }

    func testLocalExporterProgressUsesTheOwnerDayCalendar() {
        let value = progress("Exporting 2026-10-29... (5/7)", fraction: 5.0 / 7)
        XCTAssertEqual(value.completed, 5)
        XCTAssertEqual(value.total, 7)
        XCTAssertEqual(value.currentDay, day(29))
    }

    func testIntermediateMessageCannotFillTheBarBeforeTheBatchCompletes() {
        let value = progress("Exporting 2026-10-29... (2/2)", fraction: 0.5)
        XCTAssertEqual(value.completed, 1)
        XCTAssertEqual(value.total, 2)
        XCTAssertEqual(value.fraction, 0.5)
    }

    func testPhasedProgressDoesNotUseTheCaptureCountAsOverallCompletion() {
        let value = progress("Exporting 2026-10-29... (5/7)", fraction: 0.25)
        XCTAssertEqual(value.completed, 1)
        XCTAssertLessThan(value.fraction, 1)
    }

    func testCompletionAndMalformedCountsStayWithinBounds() {
        XCTAssertEqual(progress("Exporting 2026-10-30... (7/7)", fraction: 1).completed, 7)
        XCTAssertEqual(progress("Exporting 2026-10-30... (99/7)", fraction: 2).completed, 7)
        XCTAssertEqual(progress("Exporting 2026-10-30... (-1/7)", fraction: 0.5).completed, 0)
    }

    func testUnknownMessageFallsBackToTheSelectedRange() {
        let value = progress("Preparing API export…", fraction: 0.5)
        XCTAssertEqual(value.total, 7)
        XCTAssertEqual(value.completed, 3)
        XCTAssertEqual(value.currentDay, day(27))
    }

    func testNonfiniteProgressDoesNotCrashEitherPresentationPath() {
        for fraction in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(progress("Exporting 2026-10-30... (7/7)", fraction: fraction).completed, 0)
            XCTAssertEqual(progress("Preparing API export…", fraction: fraction).completed, 0)
        }
    }
}
