#if DEBUG
import XCTest
@testable import HealthMd

/// The App Store capture month must show the boards' gaps whatever today's date is.
@MainActor
final class CoverageScreenshotFixtureTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, month: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testShownMonthIsThePreviousMonthOnItsFirstAndLastDay() {
        for now in [date(1, month: 11, hour: 0), date(30, month: 11, hour: 23)] {
            XCTAssertEqual(CoverageScreenshotFixture.shownMonthStart(now: now, calendar: calendar), date(1, month: 10, hour: 0))
        }
    }

    func testBoardStatesAppearInTheShownMonthIndependentOfToday() throws {
        let daily = ScheduledExportEntry(profileID: UUID(), isEnabled: true, preferredHour: 7, preferredMinute: 30)
        let feed = ScheduledExportEntry(
            profileID: UUID(), isEnabled: true, includeToday: true,
            todayRefreshEnabled: true, todayRefreshIntervalHours: 3
        )
        let paused = ScheduledExportEntry(profileID: UUID(), isEnabled: false, preferredHour: 23)
        let entries = [daily, feed, paused]

        for now in [date(1, month: 11, hour: 1), date(17, month: 11), date(30, month: 11, hour: 22)] {
            let ledger = try XCTUnwrap(CoverageScreenshotFixture.ledger(
                profiles: entries.map { (id: $0.profileID, kind: CoverageScreenshotFixture.Kind(entry: $0)) },
                now: now,
                calendar: calendar
            ))
            func status(_ entry: ScheduledExportEntry, _ day: Int) -> CoverageStatus {
                CoverageProjection.day(
                    for: date(day, month: 10),
                    input: .init(profileID: entry.profileID, entry: entry, ledger: ledger, now: now, calendar: calendar)
                ).status
            }
            XCTAssertEqual(status(daily, 19), .missing)
            XCTAssertEqual(status(daily, 20), .missing)
            XCTAssertEqual(status(daily, 12), .partial)
            XCTAssertEqual(status(daily, 5), .complete)
            XCTAssertEqual(status(feed, 15), .missing)
            XCTAssertEqual(status(feed, 7), .partial)
            XCTAssertEqual(status(feed, 8), .complete)
            XCTAssertEqual(status(paused, 21), .complete)
            XCTAssertEqual(status(paused, 22), .paused)
            XCTAssertEqual(status(paused, 31), .paused)
        }
    }

    func testKindFollowsTheScheduleEntry() {
        let id = UUID()
        XCTAssertEqual(CoverageScreenshotFixture.Kind(entry: nil), .daily)
        XCTAssertEqual(CoverageScreenshotFixture.Kind(entry: .init(profileID: id, isEnabled: false)), .paused)
        XCTAssertEqual(
            CoverageScreenshotFixture.Kind(entry: .init(profileID: id, isEnabled: true, todayRefreshEnabled: true)),
            .feed
        )
        XCTAssertEqual(CoverageScreenshotFixture.Kind(entry: .init(profileID: id, isEnabled: true, frequency: .weekly)), .weekly)
    }
}
#endif
