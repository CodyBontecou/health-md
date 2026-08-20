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
    /// Defuses a still-armed fallback notification without removing an
    /// already-delivered copy, which can remain the user's durable recovery
    /// surface while a run is in flight.
    func cancelArmedPendingExportNotification(id: PendingExportRequest.ID)
    /// The delay between a scheduled fire date and its fallback notification.
    /// Bulk cancellation uses it to classify pre-marker requests whose
    /// fallback window has not yet closed as still-armed.
    var fallbackDelay: TimeInterval { get }
}

extension ExportNotificationScheduling {
    func cancelArmedPendingExportNotification(id: PendingExportRequest.ID) {
        cancelPendingExportNotification(id: id)
    }
}

protocol UserNotificationCentering: AnyObject {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

final class SystemUserNotificationCenterAdapter: UserNotificationCentering {
    // Avoid the crashing isolated-deinit executor hop on older iOS runtimes
    // (swiftlang/swift#85663).
    nonisolated deinit {}
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
    /// Recovery fallback delay from an occurrence's fire date. Shared so bulk
    /// cancellation can distinguish an armed (not yet fired) fallback from a
    /// preserved retry request whose fallback window already passed.
    static let standardFallbackDelay: TimeInterval = 60

    private let notificationCenter: UserNotificationCentering
    let fallbackDelay: TimeInterval
    private let now: () -> Date

    init(
        notificationCenter: UserNotificationCentering = SystemUserNotificationCenterAdapter(),
        fallbackDelay: TimeInterval = UserNotificationExportScheduler.standardFallbackDelay,
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

    func cancelArmedPendingExportNotification(id: PendingExportRequest.ID) {
        // Pending-only: a delivered copy stays visible as the recovery surface
        // if the run that defused the timer ends without re-arming one.
        let identifier = ExportNotificationIdentifiers.pendingExport(id: id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func pendingExportContent(for request: PendingExportRequest) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        if let profileName = request.profileName {
            content.title = String(
                localized: "Health Export Needs Attention — \(profileName)",
                comment: "Pending export recovery notification title with export profile name"
            )
        } else {
            content.title = String(localized: "Health Export Needs Attention", comment: "Pending export recovery notification title")
        }
        content.body = String(localized: "Open Health.md and tap to retry the remaining health export dates.", comment: "Pending export recovery notification body")
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
    /// Requests whose armed fallback timer was defused without removing a
    /// delivered copy (see `cancelArmedPendingExportNotification`).
    private(set) var armedCanceledRequestIDs: [PendingExportRequest.ID] = []
    /// Historical log of every scheduled pending request, never removed by
    /// cancellation. Assertions that must survive the pre-run fallback cancel
    /// read this instead of `scheduledRequests`.
    private(set) var allScheduledRequests: [PendingExportRequest] = []

    var fallbackDelay: TimeInterval { UserNotificationExportScheduler.standardFallbackDelay }

    func schedulePendingExportNotification(for request: PendingExportRequest) async throws {
        scheduledRequests[request.id] = request
        allScheduledRequests.append(request)
    }

    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws {
        immediateRequests[request.id] = request
    }

    func cancelPendingExportNotification(id: PendingExportRequest.ID) {
        scheduledRequests.removeValue(forKey: id)
        immediateRequests.removeValue(forKey: id)
        canceledRequestIDs.append(id)
    }

    func cancelArmedPendingExportNotification(id: PendingExportRequest.ID) {
        armedCanceledRequestIDs.append(id)
    }
}
