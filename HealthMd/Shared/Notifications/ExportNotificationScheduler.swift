import Foundation
import UserNotifications

enum ExportNotificationType: String {
    case pendingExport = "pending-export"
}

enum ExportNotificationUserInfoKey {
    static let type = "healthmd.notification.type"
    static let pendingExportRequestID = "healthmd.pendingExport.requestID"
    static let pendingExportSource = "healthmd.pendingExport.source"
    static let pendingExportReason = "healthmd.pendingExport.reason"
}

enum ExportNotificationCategories {
    static let pendingExport = "healthmd.pending-export.retry"
}

enum ExportNotificationIdentifiers {
    static let pendingExportPrefix = "healthmd.pending-export."
    static let identifierFactory = AutomationPendingExportNotificationIdentifierFactory(prefix: pendingExportPrefix)

    static func pendingExport(id: PendingExportRequest.ID) -> String {
        identifierFactory.pendingExport(id: id)
    }

    static func pendingExport(for request: PendingExportRequest) -> String {
        identifierFactory.pendingExport(for: request)
    }
}

enum ExportPendingNotificationConfiguration {
    static let pendingExport = AutomationPendingExportNotificationConfiguration(
        identifierPrefix: ExportNotificationIdentifiers.pendingExportPrefix,
        typeValue: ExportNotificationType.pendingExport.rawValue,
        typeUserInfoKey: ExportNotificationUserInfoKey.type,
        requestIDUserInfoKey: ExportNotificationUserInfoKey.pendingExportRequestID,
        sourceUserInfoKey: ExportNotificationUserInfoKey.pendingExportSource,
        reasonUserInfoKey: ExportNotificationUserInfoKey.pendingExportReason,
        categoryIdentifier: ExportNotificationCategories.pendingExport
    )
}

struct PendingExportNotificationPayload: Equatable {
    let requestID: PendingExportRequest.ID
    let source: PendingExportSource
    let reason: PendingExportReason?

    init(
        requestID: PendingExportRequest.ID,
        source: PendingExportSource,
        reason: PendingExportReason? = nil
    ) {
        self.requestID = requestID
        self.source = source
        self.reason = reason
    }

    init(request: PendingExportRequest) {
        self.init(payload: AutomationPendingExportNotificationPayload(request: request))
    }

    init(payload: AutomationPendingExportNotificationPayload) {
        self.requestID = payload.requestID
        self.source = payload.source
        self.reason = payload.reason
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let payload = AutomationPendingExportNotificationPayload(
            userInfo: userInfo,
            configuration: ExportPendingNotificationConfiguration.pendingExport
        ) else {
            return nil
        }

        self.init(payload: payload)
    }

    var userInfo: [String: String] {
        AutomationPendingExportNotificationPayload(
            requestID: requestID,
            source: source,
            reason: reason
        ).userInfo(configuration: ExportPendingNotificationConfiguration.pendingExport)
    }
}

enum ExportPendingNotificationTapRouter {
    static let pendingExport = AutomationPendingExportNotificationTapRouter(
        configuration: ExportPendingNotificationConfiguration.pendingExport,
        isLegacyScheduledExportReminderIdentifier: { identifier in
            identifier.contains("export.reminder")
        }
    )
}

protocol ExportNotificationScheduling: AutomationPendingExportNotificationScheduling {}

protocol UserNotificationCentering: AnyObject {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

final class SystemUserNotificationCenterAdapter: UserNotificationCentering {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

struct UserNotificationExportScheduler: ExportNotificationScheduling {
    private let notificationCenter: UserNotificationCentering
    private let planner: AutomationPendingExportFallbackNotificationPlanner

    init(
        notificationCenter: UserNotificationCentering = SystemUserNotificationCenterAdapter(),
        fallbackDelay: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.planner = AutomationPendingExportFallbackNotificationPlanner(
            configuration: ExportPendingNotificationConfiguration.pendingExport,
            fallbackDelay: fallbackDelay,
            now: now
        )
    }

    func schedulePendingExportNotification(for request: PendingExportRequest) async throws {
        let plan = planner.scheduledNotificationPlan(for: request)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [plan.identifier])
        let notificationRequest = UNNotificationRequest(
            identifier: plan.identifier,
            content: pendingExportContent(for: plan),
            trigger: scheduledTrigger(for: plan)
        )
        try await notificationCenter.add(notificationRequest)
    }

    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws {
        let plan = planner.immediateNotificationPlan(for: request)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [plan.identifier])
        let notificationRequest = UNNotificationRequest(
            identifier: plan.identifier,
            content: pendingExportContent(for: plan),
            trigger: nil
        )
        try await notificationCenter.add(notificationRequest)
    }

    func cancelPendingExportNotification(id: PendingExportRequest.ID) {
        let identifier = planner.identifier(for: id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func pendingExportContent(for plan: AutomationPendingExportNotificationPlan) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Health Export Needs Attention", comment: "Pending export recovery notification title")
        content.body = String(localized: "Unlock Health.md and tap to retry your health export.", comment: "Pending export recovery notification body")
        content.sound = .default
        content.categoryIdentifier = plan.categoryIdentifier
        content.threadIdentifier = plan.threadIdentifier
        content.userInfo = plan.userInfo
        return content
    }

    private func scheduledTrigger(for plan: AutomationPendingExportNotificationPlan) -> UNNotificationTrigger? {
        guard let interval = plan.triggerInterval else {
            return nil
        }
        return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    }
}

final class InspectableExportNotificationScheduler: ExportNotificationScheduling {
    private(set) var scheduledRequests: [PendingExportRequest.ID: PendingExportRequest] = [:]
    private(set) var immediateRequests: [PendingExportRequest.ID: PendingExportRequest] = [:]
    private(set) var canceledRequestIDs: [PendingExportRequest.ID] = []

    func schedulePendingExportNotification(for request: PendingExportRequest) async throws {
        scheduledRequests[request.id] = request
    }

    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws {
        immediateRequests[request.id] = request
    }

    func cancelPendingExportNotification(id: PendingExportRequest.ID) {
        scheduledRequests.removeValue(forKey: id)
        immediateRequests.removeValue(forKey: id)
        canceledRequestIDs.append(id)
    }
}
