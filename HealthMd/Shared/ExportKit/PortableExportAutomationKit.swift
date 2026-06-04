import Foundation

// MARK: - Portable Export Automation

enum PortableExportScheduleFrequency: String, Codable, Equatable {
    case daily
    case weekly
}

struct PortableExportSchedule: Codable, Equatable {
    var isEnabled: Bool
    var frequency: PortableExportScheduleFrequency
    var preferredHour: Int
    var preferredMinute: Int
    var lookbackDays: Int
    var lastExportDate: Date?
    var timezoneIdentifier: String

    init(
        isEnabled: Bool,
        frequency: PortableExportScheduleFrequency,
        preferredHour: Int,
        preferredMinute: Int,
        lookbackDays: Int,
        lastExportDate: Date?,
        timezoneIdentifier: String
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.lookbackDays = lookbackDays
        self.lastExportDate = lastExportDate
        self.timezoneIdentifier = timezoneIdentifier
    }
}

struct PortableExportScheduleRegistration: Codable, Equatable {
    let installationID: String
    let appID: String
    let apnsToken: String
    let timezoneIdentifier: String
    let schedule: PortableExportSchedule
}

protocol PortableExportScheduleServerClient: AnyObject {
    func registerSchedule(_ registration: PortableExportScheduleRegistration) async throws
    func unregisterSchedule(installationID: String, appID: String) async throws
}

struct PortableExportScheduleSyncer {
    let server: any PortableExportScheduleServerClient

    func sync(
        schedule: PortableExportSchedule,
        installationID: String,
        appID: String,
        apnsToken: String
    ) async throws {
        if schedule.isEnabled {
            try await server.registerSchedule(PortableExportScheduleRegistration(
                installationID: installationID,
                appID: appID,
                apnsToken: apnsToken,
                timezoneIdentifier: schedule.timezoneIdentifier,
                schedule: schedule
            ))
        } else {
            try await server.unregisterSchedule(installationID: installationID, appID: appID)
        }
    }
}

// MARK: - Pending Export Retry

enum PortablePendingExportReason: Codable, Equatable {
    case dataProtected
    case destinationUnavailable
    case quotaBlocked
    case noData
    case exportFailed
    case unknown(String)

    static func from(_ result: PortableExportRunResult) -> PortablePendingExportReason {
        guard let first = result.failures.first else { return .exportFailed }
        switch first.category {
        case .dataProtected:
            return .dataProtected
        case .destinationUnavailable:
            return .destinationUnavailable
        case .quotaBlocked:
            return .quotaBlocked
        case .noData:
            return .noData
        case .renderFailed, .writeFailed, .missingRenderer, .pluginFailed:
            return .exportFailed
        case .cancelled:
            return .unknown("cancelled")
        case .unknown:
            return .unknown(first.message)
        }
    }
}

struct PortablePendingExportRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let dates: [Date]
    let source: PortableExportTriggerSource
    let reason: PortablePendingExportReason
    let createdAt: Date
    let scheduledFireDate: Date?
    let notificationUserInfo: [String: String]

    init(
        id: UUID = UUID(),
        dates: [Date],
        source: PortableExportTriggerSource,
        reason: PortablePendingExportReason,
        createdAt: Date,
        scheduledFireDate: Date?,
        notificationUserInfo: [String: String]? = nil
    ) {
        self.id = id
        self.dates = dates
        self.source = source
        self.reason = reason
        self.createdAt = createdAt
        self.scheduledFireDate = scheduledFireDate
        self.notificationUserInfo = notificationUserInfo ?? PortableNotificationTapRouter.userInfo(forPendingExportID: id)
    }
}

protocol PortablePendingExportStoring: AnyObject {
    func upsert(_ request: PortablePendingExportRequest) throws
    func load(id: UUID) throws -> PortablePendingExportRequest?
    func delete(id: UUID) throws
}

final class InMemoryPortablePendingExportStore: PortablePendingExportStoring {
    private var requests: [UUID: PortablePendingExportRequest] = [:]

    func upsert(_ request: PortablePendingExportRequest) throws {
        requests[request.id] = request
    }

    func load(id: UUID) throws -> PortablePendingExportRequest? {
        requests[id]
    }

    func delete(id: UUID) throws {
        requests.removeValue(forKey: id)
    }
}

protocol PortableExportNotificationScheduling: AnyObject {
    func schedulePendingExportNotification(for request: PortablePendingExportRequest) async throws
}

enum PortableNotificationTapRouter {
    static let kindKey = "kind"
    static let pendingExportKind = "pending_export_retry"
    static let pendingExportIDKey = "pendingExportID"

    static func userInfo(forPendingExportID id: UUID) -> [String: String] {
        [
            kindKey: pendingExportKind,
            pendingExportIDKey: id.uuidString
        ]
    }

    static func pendingExportID(from userInfo: [String: String]) -> UUID? {
        guard userInfo[kindKey] == pendingExportKind,
              let rawID = userInfo[pendingExportIDKey] else {
            return nil
        }
        return UUID(uuidString: rawID)
    }

    static func pendingExportID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let kind = userInfo[kindKey] as? String,
              kind == pendingExportKind,
              let rawID = userInfo[pendingExportIDKey] as? String else {
            return nil
        }
        return UUID(uuidString: rawID)
    }
}

enum PortableAutomationOutcome {
    case success(PortableExportRunResult)
    case pendingCreated(PortablePendingExportRequest)
    case ignored(String)
    case failed(String)
}

struct PortableBackgroundExportRunner {
    let pendingStore: any PortablePendingExportStoring
    let notificationScheduler: any PortableExportNotificationScheduling
    let now: () -> Date

    init(
        pendingStore: any PortablePendingExportStoring,
        notificationScheduler: any PortableExportNotificationScheduling,
        now: @escaping () -> Date = Date.init
    ) {
        self.pendingStore = pendingStore
        self.notificationScheduler = notificationScheduler
        self.now = now
    }

    func runScheduledExport(
        dates: [Date],
        scheduledFireDate: Date?,
        export: () async -> PortableExportRunResult
    ) async -> PortableAutomationOutcome {
        let result = await export()
        guard !result.isFullSuccess else {
            return .success(result)
        }

        let request = PortablePendingExportRequest(
            dates: dates,
            source: result.trigger,
            reason: PortablePendingExportReason.from(result),
            createdAt: now(),
            scheduledFireDate: scheduledFireDate
        )

        do {
            try pendingStore.upsert(request)
            try await notificationScheduler.schedulePendingExportNotification(for: request)
            return .pendingCreated(request)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

struct PortablePendingExportRetryCoordinator {
    let pendingStore: any PortablePendingExportStoring
    let notificationScheduler: any PortableExportNotificationScheduling

    init(
        pendingStore: any PortablePendingExportStoring,
        notificationScheduler: any PortableExportNotificationScheduling
    ) {
        self.pendingStore = pendingStore
        self.notificationScheduler = notificationScheduler
    }

    func handleNotificationTap(
        userInfo: [String: String],
        retry: (PortablePendingExportRequest) async -> PortableExportRunResult
    ) async -> PortableAutomationOutcome {
        guard let id = PortableNotificationTapRouter.pendingExportID(from: userInfo) else {
            return .ignored("Notification is not a pending export retry")
        }

        do {
            guard let request = try pendingStore.load(id: id) else {
                return .ignored("Pending export request was not found")
            }

            let result = await retry(request)
            if result.isFullSuccess {
                try pendingStore.delete(id: id)
                return .success(result)
            }

            // Keep the original request around and remind the user again if the
            // foreground retry still cannot complete.
            try pendingStore.upsert(request)
            try await notificationScheduler.schedulePendingExportNotification(for: request)
            return .pendingCreated(request)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func handleNotificationTap(
        userInfo: [AnyHashable: Any],
        retry: (PortablePendingExportRequest) async -> PortableExportRunResult
    ) async -> PortableAutomationOutcome {
        guard let id = PortableNotificationTapRouter.pendingExportID(from: userInfo) else {
            return .ignored("Notification is not a pending export retry")
        }
        return await handleNotificationTap(
            userInfo: PortableNotificationTapRouter.userInfo(forPendingExportID: id),
            retry: retry
        )
    }
}
