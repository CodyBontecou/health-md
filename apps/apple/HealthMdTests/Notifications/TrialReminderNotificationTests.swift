#if os(iOS)
import UserNotifications
import XCTest
@testable import HealthMd

final class TrialReminderNotificationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func trial(endsIn days: Double, renews: Bool = true, price: String? = "$29.99") -> TrialReminderNotification.Trial {
        .init(expirationDate: now.addingTimeInterval(days * day), willAutoRenew: renews, displayPrice: price)
    }

    private func refresh(_ trial: TrialReminderNotification.Trial?) -> (added: [UNNotificationRequest], removed: [String]) {
        var added: [UNNotificationRequest] = []
        var removed: [String] = []
        TrialReminderNotification.refresh(trial: trial, now: now, add: { added.append($0) }, remove: { removed += $0 })
        return (added, removed)
    }

    func testANewSevenDayTrialIsRemindedOnDayFive() {
        XCTAssertEqual(TrialReminderNotification.fireDate(for: trial(endsIn: 7), now: now), now.addingTimeInterval(5 * day))
    }

    func testATrialInsideTheLeadTimeIsRemindedRightAway() {
        XCTAssertEqual(TrialReminderNotification.fireDate(for: trial(endsIn: 1), now: now), now.addingTimeInterval(60))
    }

    func testNoReminderWithoutARenewingTrialOrWhenItIsAboutToEnd() {
        XCTAssertNil(TrialReminderNotification.fireDate(for: nil, now: now))
        XCTAssertNil(TrialReminderNotification.fireDate(for: trial(endsIn: 7, renews: false), now: now))
        XCTAssertNil(TrialReminderNotification.fireDate(for: trial(endsIn: 0.02), now: now))
    }

    func testRefreshReplacesThePendingReminder() throws {
        let result = refresh(trial(endsIn: 7))
        XCTAssertEqual(result.removed, [TrialReminderNotification.identifier])
        XCTAssertEqual(result.added.count, 1)
        let request = try XCTUnwrap(result.added.first)
        XCTAssertEqual(request.identifier, TrialReminderNotification.identifier)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 5 * day, accuracy: 1)
        XCTAssertFalse(trigger.repeats)
        XCTAssertTrue(request.content.body.contains("$29.99"))
    }

    func testCancellingRenewalRemovesTheReminder() {
        let result = refresh(trial(endsIn: 4, renews: false))
        XCTAssertEqual(result.removed, [TrialReminderNotification.identifier])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertTrue(refresh(nil).added.isEmpty)
    }

    func testBodyNamesTheEndDateAndFallsBackWithoutAPrice() {
        let locale = Locale(identifier: "en_US")
        let withPrice = TrialReminderNotification.body(for: trial(endsIn: 7), locale: locale)
        XCTAssertTrue(withPrice.contains("$29.99"), withPrice)
        let noPrice = TrialReminderNotification.body(for: trial(endsIn: 7, price: nil), locale: locale)
        XCTAssertTrue(noPrice.contains("cancel in Settings"), noPrice)
        XCTAssertFalse(noPrice.contains("$"), noPrice)
    }
}
#endif
