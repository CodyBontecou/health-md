#if os(iOS)
import UserNotifications
import XCTest
@testable import HealthMd

final class WeeklyGapNotificationTests: XCTestCase {
    private func refresh(_ gaps: Int) -> (added: [UNNotificationRequest], removed: [String]) {
        var added: [UNNotificationRequest] = []
        var removed: [String] = []
        WeeklyGapNotification.refresh(gapCount: gaps, add: { added.append($0) }, remove: { removed += $0 })
        return (added, removed)
    }

    func testNoGapsClearsThePendingReminderAndAddsNothing() {
        let result = refresh(0)
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(result.removed, [WeeklyGapNotification.identifier])
    }

    func testGapsReplaceThePendingReminderInsteadOfStacking() throws {
        let result = refresh(2)
        XCTAssertEqual(result.removed, [WeeklyGapNotification.identifier])
        let request = try XCTUnwrap(result.added.first)
        XCTAssertEqual(result.added.count, 1)
        XCTAssertEqual(request.identifier, WeeklyGapNotification.identifier)
        XCTAssertFalse((request.trigger as? UNCalendarNotificationTrigger)?.repeats ?? true)
    }

    func testReminderCarriesTheBackfillPayload() throws {
        let request = try XCTUnwrap(refresh(2).added.first)
        XCTAssertTrue(WeeklyGapNotification.isBackfillTap(userInfo: request.content.userInfo))
    }

    func testPayloadParsingRejectsOtherNotifications() {
        XCTAssertFalse(WeeklyGapNotification.isBackfillTap(userInfo: [:]))
        XCTAssertFalse(WeeklyGapNotification.isBackfillTap(userInfo: ["type": "scheduled-export"]))
        XCTAssertFalse(WeeklyGapNotification.isBackfillTap(userInfo: [WeeklyGapNotification.actionKey: "other"]))
        XCTAssertFalse(WeeklyGapNotification.isBackfillTap(userInfo: [WeeklyGapNotification.actionKey: 1]))
        XCTAssertTrue(WeeklyGapNotification.isBackfillTap(userInfo: [
            WeeklyGapNotification.actionKey: WeeklyGapNotification.backfillAction
        ]))
    }

    func testBackfillRangeSpansTheWeeksGaps() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9)))
        let day: (Int) -> Date = { calendar.date(from: DateComponents(year: 2026, month: 10, day: $0))! }
        let gaps: Set<Date> = [day(27), day(30)]
        let range = try XCTUnwrap(WeeklyGapNotification.backfillRange(today: today, calendar: calendar) { gaps.contains($0) })
        XCTAssertEqual(range.start, day(27))
        XCTAssertEqual(range.end, day(30))
        // Today and days older than a week are not part of the reminder.
        XCTAssertNil(WeeklyGapNotification.backfillRange(today: today, calendar: calendar) {
            $0 == calendar.startOfDay(for: today) || $0 < day(25)
        })
    }

    @MainActor
    func testRouterDeliversEachTapOnce() {
        let router = WeeklyGapBackfillRouter()
        XCTAssertFalse(router.consume())
        router.requestBackfill()
        XCTAssertTrue(router.consume())
        XCTAssertFalse(router.consume())
    }

    func testBodyCarriesOnlyTheGapCount() {
        XCTAssertTrue(WeeklyGapNotification.body(gapCount: 1).contains("1 gap"))
        XCTAssertTrue(WeeklyGapNotification.body(gapCount: 3).contains("3 gaps"))
    }
}
#endif
