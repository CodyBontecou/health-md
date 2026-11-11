#if os(iOS)
import XCTest
@testable import HealthMd

/// Archive B's readable day reads values only from the written file.
@MainActor
final class ArchiveDayFileTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }()

    private let note = """
    ---
    date: 2026-10-30
    type: health
    sleep_total_hours: 7.4
    hrv_ms: 46
    steps: 9104
    resting_heart_rate: 57
    tags:
      - health
    active_calories: 512
    mindful_minutes: 10
    respiratory_rate: 14.5
    ---

    ## Sleep
    - In bed 23:12 → 06:51
    """

    func testTilesLeadWithTheBoardMetricsInBoardOrder() {
        let tiles = ArchiveDayTiles.tiles(fromMarkdown: note)
        XCTAssertEqual(tiles.map(\.key), [
            "steps", "sleep_total_hours", "resting_heart_rate", "hrv_ms", "active_calories", "mindful_minutes",
        ])
        XCTAssertEqual(tiles[0].value, 9104.formatted(.number.grouping(.automatic)))
        XCTAssertEqual(tiles[1].value, "7h 24m")
        XCTAssertEqual(tiles[2].unit, "bpm")
        XCTAssertEqual(tiles[3].unit, "ms")
    }

    func testRemainingPlacesTakeOtherKnownMetricsInFileOrder() {
        let tiles = ArchiveDayTiles.tiles(fromMarkdown: note, limit: 7)
        XCTAssertEqual(tiles.last?.key, "respiratory_rate")
        // Non-metric fields (date, type, lists) are never tiles.
        XCTAssertFalse(tiles.contains { ["date", "type", "tags"].contains($0.key) })
    }

    func testNoFrontmatterOrAnUnclosedFenceGivesNoTiles() {
        XCTAssertTrue(ArchiveDayTiles.tiles(fromMarkdown: "## Sleep\n- 7h").isEmpty)
        XCTAssertTrue(ArchiveDayTiles.tiles(fromMarkdown: "---\nsteps: 10\n").isEmpty)
        XCTAssertTrue(ArchiveDayTiles.tiles(fromMarkdown: "").isEmpty)
    }

    func testCustomKeyStylesMapBackToTheMetric() {
        XCTAssertEqual(ArchiveDayTiles.canonicalKey("restingHeartRate"), "resting_heart_rate")
        XCTAssertEqual(ArchiveDayTiles.canonicalKey("steps"), "steps")
        let tiles = ArchiveDayTiles.tiles(fromMarkdown: "---\nrestingHeartRate: \"58\"\n---\n")
        XCTAssertEqual(tiles.map(\.key), ["restingHeartRate"])
        XCTAssertEqual(tiles.first?.value, "58")
    }

    func testNonfiniteFileValuesAreNotMetricTiles() {
        for value in ["nan", "NaN", "inf", "-inf", "1e309"] {
            let source = "---\nsleep_total_hours: \(value)\nsteps: \(value)\n---\n"
            XCTAssertTrue(ArchiveDayTiles.tiles(fromMarkdown: source).isEmpty, value)
        }
    }

    func testOversizedHourValuesStayReadableWithoutIntegerConversion() {
        for value in ["1e308", "-1e308", "1e18", "-1e18"] {
            let tiles = ArchiveDayTiles.tiles(fromMarkdown: "---\nsleep_total_hours: \(value)\n---\n")
            XCTAssertEqual(tiles.count, 1)
            XCTAssertEqual(tiles.first?.value, value)
            XCTAssertEqual(tiles.first?.unit, "hours")
        }
    }

    func testFileLinesDropTheTrailingNewline() {
        let file = ArchiveDayFile(fileURL: URL(fileURLWithPath: "/tmp/a.md"), rootURL: nil, source: "a\nb\n", byteCount: 4)
        XCTAssertEqual(file.lines, ["a", "b"])
        XCTAssertFalse(file.isTruncated)
    }

    func testReadingAFileReturnsItsText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDayFileTests-\(UUID()).md")
        try note.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try XCTUnwrap(ArchiveDayFile.read(fileURL: url, rootURL: nil))
        XCTAssertEqual(file.source, note)
        XCTAssertEqual(file.byteCount, note.utf8.count)
    }

    func testWeekHoldsSevenDaysFromTheCalendarsFirstWeekday() {
        let model = ArchiveModel(profiles: [], ledger: CoverageLedger(startedAt: date(1)), now: date(31), calendar: calendar)
        let week = model.week(containing: date(30))
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first.map { calendar.component(.day, from: $0) }, 25)
        XCTAssertEqual(week.last.map { calendar.component(.day, from: $0) }, 31)
    }

    func testNextRunWordsTodayAndTomorrow() {
        let now = date(30, hour: 6)
        XCTAssertTrue(ArchiveNextRun.whenText(date(30, hour: 9), now: now, calendar: calendar).hasPrefix("today at"))
        XCTAssertTrue(ArchiveNextRun.whenText(date(31, hour: 7), now: now, calendar: calendar).hasPrefix("tomorrow at"))
    }

    func testNextRunFollowsTheArchiveFilter() {
        let early = UUID(), late = UUID()
        func profile(_ id: UUID, _ name: String, hour: Int) -> ArchiveProfile {
            ArchiveProfile(
                id: id, name: name, destination: "Vault/Health", colorIndex: 0,
                entry: ScheduledExportEntry(profileID: id, isEnabled: true, frequency: .daily, preferredHour: hour)
            )
        }
        let model = ArchiveModel(
            profiles: [profile(late, "Daily", hour: 9), profile(early, "Agent feed", hour: 6)],
            ledger: CoverageLedger(startedAt: date(1)),
            now: date(30, hour: 12),
            calendar: calendar
        )
        XCTAssertEqual(model.nextRun()?.profile.id, early)
        // Filtered to Daily, the card names Daily's run, not the earliest of all.
        XCTAssertEqual(model.nextRun(filter: late)?.profile.id, late)
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
}
#endif
