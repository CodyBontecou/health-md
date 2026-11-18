#if os(iOS)
import Foundation
import StoreKit
import UserNotifications

/// The reminder onboarding promises in its trial timeline ("Day 5 · Reminder before
/// you're charged"). It fires two days before a renewing free trial ends, which is
/// Day 5 of the seven-day trial. Every refresh replaces the pending copy, and it is
/// removed when the trial ends, converts, or renewal is turned off.
enum TrialReminderNotification {
    static let identifier = "healthmd.trial.billing-reminder"
    static let leadTime: TimeInterval = 2 * 86_400

    /// The active trial a reminder is about.
    struct Trial: Equatable {
        let expirationDate: Date
        let willAutoRenew: Bool
        let displayPrice: String?
    }

    /// When the reminder fires, or nil when there is nothing left to remind about.
    /// A trial that is already inside the lead time is reminded within a minute,
    /// so a late purchase or a restored install still hears about the charge.
    static func fireDate(for trial: Trial?, now: Date = Date()) -> Date? {
        guard let trial, trial.willAutoRenew, trial.expirationDate > now.addingTimeInterval(3_600) else {
            return nil
        }
        return max(trial.expirationDate.addingTimeInterval(-leadTime), now.addingTimeInterval(60))
    }

    static func body(for trial: Trial, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.locale = locale
        let date = trial.expirationDate.formatted(style)
        if let price = trial.displayPrice {
            return String(localized: "Your free trial ends \(date). You’ll be billed \(price) unless you cancel in Settings before then.")
        }
        return String(localized: "Your free trial ends \(date). Your subscription starts then unless you cancel in Settings before then.")
    }

    static func refresh(
        trial: Trial?,
        now: Date = Date(),
        add: (UNNotificationRequest) -> Void,
        remove: ([String]) -> Void
    ) {
        remove([identifier])
        guard let trial, let fireDate = fireDate(for: trial, now: now) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Health.md trial ending soon")
        content.body = body(for: trial)
        content.sound = .default
        add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSince(now)), repeats: false)
        ))
    }

    static func refresh(trial: Trial?) {
        guard !TestMode.suppressesRuntimeServices else { return }
        let center = UNUserNotificationCenter.current()
        refresh(
            trial: trial,
            add: { center.add($0) },
            remove: { center.removePendingNotificationRequests(withIdentifiers: $0) }
        )
    }

    /// Asks for notification permission once, right after a trial starts, because the
    /// reminder is part of what the trial promised. A decided permission is left alone.
    static func requestPermissionIfUndetermined() async {
        guard !TestMode.suppressesRuntimeServices else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// True when the transaction is a subscription currently in its introductory offer.
    static func isIntroductoryOffer(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory
        }
        return transaction.offerType == .introductory
    }

    /// The renewing trial among current entitlements, if any.
    static func currentTrial(displayPrice: @Sendable (String) -> String?) async -> Trial? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil,
                  isIntroductoryOffer(transaction),
                  let expiration = transaction.expirationDate else { continue }
            var willAutoRenew = true
            if let status = await transaction.subscriptionStatus,
               case .verified(let renewal) = status.renewalInfo {
                willAutoRenew = renewal.willAutoRenew
            }
            return Trial(
                expirationDate: expiration,
                willAutoRenew: willAutoRenew,
                displayPrice: displayPrice(transaction.productID)
            )
        }
        return nil
    }
}
#endif
