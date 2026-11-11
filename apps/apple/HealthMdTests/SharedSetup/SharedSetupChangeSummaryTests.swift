import XCTest
@testable import HealthMd

final class SharedSetupChangeSummaryTests: XCTestCase {
    private typealias Facts = SharedSetupChangeSummary.Facts

    private let base = Facts(
        formats: ["markdown"],
        dateFormat: "iso8601",
        filename: "{date}",
        metricCount: 142,
        dailyNotes: false
    )

    func testIdenticalSetupsProduceNoRows() {
        XCTAssertTrue(SharedSetupChangeSummary(current: base, incoming: base, on: "On", off: "Off").rows.isEmpty)
    }

    func testOnlyChangedFieldsAppearInDesignOrder() {
        var incoming = base
        incoming.metricCount = 156
        incoming.formats = ["json", "markdown"]
        incoming.dailyNotes = true
        let rows = SharedSetupChangeSummary(current: base, incoming: incoming, on: "On", off: "Off").rows
        XCTAssertEqual(rows.map(\.field), [.formats, .metrics, .dailyNotes])
        XCTAssertEqual(rows[1].before, "142")
        XCTAssertEqual(rows[1].after, "156")
        XCTAssertEqual(rows[2].after, "On")
    }

    func testFormatOrderDoesNotReadAsAChange() {
        let first = Facts(formats: ["json", "csv"], dateFormat: "iso8601", filename: "{date}", metricCount: 1, dailyNotes: false)
        let second = Facts(formats: ["csv", "json"], dateFormat: "iso8601", filename: "{date}", metricCount: 1, dailyNotes: false)
        XCTAssertTrue(SharedSetupChangeSummary(current: first, incoming: second, on: "On", off: "Off").rows.isEmpty)
    }

    func testTodayRefreshRowSitsBeforeDailyNotesAndUsesTheLabel() {
        var incoming = base
        incoming.todayRefreshMinutes = 180
        incoming.dailyNotes = true
        let rows = SharedSetupChangeSummary(
            current: base, incoming: incoming, on: "On", off: "Off",
            todayRefreshLabel: { "Every \($0 / 60) h" }
        ).rows
        XCTAssertEqual(rows.map(\.field), [.todayRefresh, .dailyNotes])
        XCTAssertEqual(rows[0].before, "Off")
        XCTAssertEqual(rows[0].after, "Every 3 h")
    }
}
