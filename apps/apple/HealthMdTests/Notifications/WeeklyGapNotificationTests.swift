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

    func testBodyCarriesOnlyTheGapCount() {
        XCTAssertTrue(WeeklyGapNotification.body(gapCount: 1).contains("1 gap"))
        XCTAssertTrue(WeeklyGapNotification.body(gapCount: 3).contains("3 gaps"))
    }
}
