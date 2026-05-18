import Foundation
import UserNotifications

enum ExportNotificationType: String {
    case pendingExport = "pending-export"
}

enum ExportNotificationUserInfoKey {
    static let type = "healthmd.notification.type"
    static let pendingExportRequestID = "healthmd.pendingExport.requestID"
    static let pendingExportSource = "healthmd.pendingExport.source"
}

enum ExportNotificationCategories {
    static let pendingExport = "healthmd.pending-export.retry"
}

enum ExportNotificationIdentifiers {
    static let pendingExportPrefix = "healthmd.pending-export."

    static func pendingExport(id: PendingExportRequest.ID) -> String {
        pendingExportPrefix + id.uuidString.lowercased()
    }

    static func pendingExport(for request: PendingExportRequest) -> String {
        pendingExport(id: request.id)
    }
}

struct PendingExportNotificationPayload: Equatable {
    let requestID: PendingExportRequest.ID
    let source: PendingExportSource

    init(request: PendingExportRequest) {
        self.requestID = request.id
        self.source = request.source
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard userInfo[ExportNotificationUserInfoKey.type] as? String == ExportNotificationType.pendingExport.rawValue,
              let requestIDString = userInfo[ExportNotificationUserInfoKey.pendingExportRequestID] as? String,
              let requestID = UUID(uuidString: requestIDString),
              let sourceString = userInfo[ExportNotificationUserInfoKey.pendingExportSource] as? String,
              let source = PendingExportSource(rawValue: sourceString)
        else {
            return nil
        }

        self.requestID = requestID
        self.source = source
    }

    var userInfo: [String: String] {
        [
            ExportNotificationUserInfoKey.type: ExportNotificationType.pendingExport.rawValue,
            ExportNotificationUserInfoKey.pendingExportRequestID: requestID.uuidString.lowercased(),
            ExportNotificationUserInfoKey.pendingExportSource: source.rawValue
        ]
    }
}

protocol ExportNotificationScheduling {
    func schedulePendingExportNotification(for request: PendingExportRequest) async throws
    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws
    func cancelPendingExportNotification(id: PendingExportRequest.ID)
}

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
    private let fallbackDelay: TimeInterval
    private let now: () -> Date

    init(
        notificationCenter: UserNotificationCentering = SystemUserNotificationCenterAdapter(),
        fallbackDelay: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.fallbackDelay = fallbackDelay
        self.now = now
    }

    func schedulePendingExportNotification(for request: PendingExportRequest) async throws {
        let identifier = ExportNotificationIdentifiers.pendingExport(for: request)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        let notificationRequest = UNNotificationRequest(
            identifier: identifier,
            content: pendingExportContent(for: request),
            trigger: scheduledTrigger(for: request)
        )
        try await notificationCenter.add(notificationRequest)
    }

    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws {
        let identifier = ExportNotificationIdentifiers.pendingExport(for: request)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        let notificationRequest = UNNotificationRequest(
            identifier: identifier,
            content: pendingExportContent(for: request),
            trigger: nil
        )
        try await notificationCenter.add(notificationRequest)
    }

    func cancelPendingExportNotification(id: PendingExportRequest.ID) {
        let identifier = ExportNotificationIdentifiers.pendingExport(id: id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func pendingExportContent(for request: PendingExportRequest) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Health Export Needs Attention", comment: "Pending export recovery notification title")
        content.body = String(localized: "Unlock Health.md and tap to retry your health export.", comment: "Pending export recovery notification body")
        content.sound = .default
        content.categoryIdentifier = ExportNotificationCategories.pendingExport
        content.threadIdentifier = ExportNotificationCategories.pendingExport
        content.userInfo = PendingExportNotificationPayload(request: request).userInfo
        return content
    }

    private func scheduledTrigger(for request: PendingExportRequest) -> UNNotificationTrigger? {
        guard let scheduledFireDate = request.scheduledFireDate else {
            return nil
        }

        let fallbackDate = scheduledFireDate.addingTimeInterval(fallbackDelay)
        let interval = max(1, fallbackDate.timeIntervalSince(now()))
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
