#if os(iOS)
import Foundation
import UserNotifications

/// The optional weekly Archive reminder from NotificationsG. It carries a count only, never
/// health values. It does not ask for permission, so it stays silent unless notifications
/// are already allowed. Each refresh replaces the pending copy, so reminders cannot stack.
enum WeeklyGapNotification {
    static let identifier = "healthmd.archive.weekly-gaps"

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
#endif
