#if os(iOS)
import Combine
import Foundation
import UserNotifications

/// The optional weekly Archive reminder from NotificationsG. It carries a count only, never
/// health values. It does not ask for permission, so it stays silent unless notifications
/// are already allowed. Each refresh replaces the pending copy, so reminders cannot stack.
enum WeeklyGapNotification {
    static let identifier = "healthmd.archive.weekly-gaps"
    /// userInfo key naming what a tap on this notification opens.
    static let actionKey = "healthmd.notification.action"
    /// Value of `actionKey`: open the Archive and backfill this week's gaps.
    static let backfillAction = "archive-backfill"

    static var userInfo: [AnyHashable: Any] { [actionKey: backfillAction] }

    /// True when a tapped notification's payload asks for the Archive backfill.
    static func isBackfillTap(userInfo: [AnyHashable: Any]) -> Bool {
        userInfo[actionKey] as? String == backfillAction
    }

    /// The days the reminder counts (the seven before today) from the oldest gap to the
    /// newest, so one export covers them all. Nil when the week has no gap left.
    static func backfillRange(
        today: Date,
        calendar: Calendar,
        isGap: (Date) -> Bool
    ) -> (start: Date, end: Date)? {
        let start = calendar.startOfDay(for: today)
        let gaps = (1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }.filter(isGap)
        guard let oldest = gaps.min(), let newest = gaps.max() else { return nil }
        return (oldest, newest)
    }

    static func body(gapCount: Int) -> String {
        gapCount == 1
            ? String(localized: "Archive has 1 gap this week. Tap to backfill.")
            : String(localized: "Archive has \(gapCount) gaps this week. Tap to backfill.")
    }

    /// Sunday morning, which the system resolves to the next occurrence.
    static var trigger: DateComponents {
        var components = DateComponents()
        components.weekday = 1
        components.hour = 9
        return components
    }

    static func refresh(
        gapCount: Int,
        add: (UNNotificationRequest) -> Void,
        remove: ([String]) -> Void
    ) {
        remove([identifier])
        guard gapCount > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Health.md"
        content.body = body(gapCount: gapCount)
        content.userInfo = userInfo
        add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
        ))
    }

    static func refresh(gapCount: Int) {
        let center = UNUserNotificationCenter.current()
        refresh(
            gapCount: gapCount,
            add: { center.add($0) },
            remove: { center.removePendingNotificationRequests(withIdentifiers: $0) }
        )
    }
}

/// Carries a tapped weekly gap notification from the app delegate to the glass shell,
/// which may not exist yet on a cold launch. The shell consumes it once.
@MainActor
final class WeeklyGapBackfillRouter: ObservableObject {
    static let shared = WeeklyGapBackfillRouter()

    @Published private(set) var pendingRequest: UUID?

    func requestBackfill() {
        pendingRequest = UUID()
    }

    /// Returns true once per request, then clears it.
    func consume() -> Bool {
        guard pendingRequest != nil else { return false }
        pendingRequest = nil
        return true
    }
}
#endif
