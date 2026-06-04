import Foundation
import UserNotifications
import ExportAutomationKit

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

protocol UserNotificationCentering: AutomationUserNotificationCentering {}

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
    private let scheduler: AutomationUserNotificationPendingExportScheduler

    init(
        notificationCenter: UserNotificationCentering = SystemUserNotificationCenterAdapter(),
        fallbackDelay: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = AutomationUserNotificationPendingExportScheduler(
            configuration: ExportPendingNotificationConfiguration.pendingExport,
            notificationCenter: notificationCenter,
            fallbackDelay: fallbackDelay,
            now: now,
            contentConfiguration: AutomationPendingExportNotificationContentConfiguration(
                title: String(localized: "Health Export Needs Attention", comment: "Pending export recovery notification title"),
                body: String(localized: "Unlock Health.md and tap to retry your health export.", comment: "Pending export recovery notification body")
            )
        )
    }

    func schedulePendingExportNotification(for request: PendingExportRequest) async throws {
        try await scheduler.schedulePendingExportNotification(for: request)
    }

    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws {
        try await scheduler.sendImmediatePendingExportNotification(for: request)
    }

    func cancelPendingExportNotification(id: PendingExportRequest.ID) {
        scheduler.cancelPendingExportNotification(id: id)
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
