import UserNotifications
import XCTest
@testable import HealthMd
import ExportAutomationKit
import ExportKit

final class ExportNotificationSchedulerTests: XCTestCase {
    func testSchedulingPendingRequestCreatesNotificationWithStableIdentifier() async throws {
        let center = FakeUserNotificationCenter()
        let scheduler = UserNotificationExportScheduler(notificationCenter: center)
        let request = pendingRequest(id: "11111111-1111-1111-1111-111111111111")

        try await scheduler.schedulePendingExportNotification(for: request)

        XCTAssertEqual(center.pendingRequests.count, 1)
        let notification = try XCTUnwrap(center.pendingRequests["healthmd.pending-export.11111111-1111-1111-1111-111111111111"])
        XCTAssertTrue(notification.trigger is UNTimeIntervalNotificationTrigger)
    }

    func testSchedulingSamePendingRequestAgainReplacesDuplicate() async throws {
        let center = FakeUserNotificationCenter()
        let scheduler = UserNotificationExportScheduler(notificationCenter: center)
        let request = pendingRequest(id: "22222222-2222-2222-2222-222222222222")

        try await scheduler.schedulePendingExportNotification(for: request)
        try await scheduler.schedulePendingExportNotification(for: request)

        XCTAssertEqual(center.pendingRequests.count, 1)
        XCTAssertTrue(center.removedPendingIdentifiers.contains(
            "healthmd.pending-export.22222222-2222-2222-2222-222222222222"
        ))
    }

    func testCancelingCompletedRequestRemovesMatchingNotificationOnly() async throws {
        let center = FakeUserNotificationCenter()
        let scheduler = UserNotificationExportScheduler(notificationCenter: center)
        let completed = pendingRequest(id: "33333333-3333-3333-3333-333333333333")
        let stillPending = pendingRequest(id: "44444444-4444-4444-4444-444444444444")

        try await scheduler.schedulePendingExportNotification(for: completed)
        try await scheduler.schedulePendingExportNotification(for: stillPending)

        scheduler.cancelPendingExportNotification(id: completed.id)

        XCTAssertNil(center.pendingRequests["healthmd.pending-export.33333333-3333-3333-3333-333333333333"])
        XCTAssertNotNil(center.pendingRequests["healthmd.pending-export.44444444-4444-4444-4444-444444444444"])
        XCTAssertEqual(center.removedDeliveredIdentifiers, [
            "healthmd.pending-export.33333333-3333-3333-3333-333333333333"
        ])
    }

    func testNotificationContentIncludesPendingRequestMetadata() async throws {
        let center = FakeUserNotificationCenter()
        let scheduler = UserNotificationExportScheduler(notificationCenter: center)
        let request = pendingRequest(
            id: "55555555-5555-5555-5555-555555555555",
            reason: .protectedDataUnavailable
        )

        try await scheduler.sendImmediatePendingExportNotification(for: request)

        let notification = try XCTUnwrap(center.pendingRequests["healthmd.pending-export.55555555-5555-5555-5555-555555555555"])
        let payload = try XCTUnwrap(PendingExportNotificationPayload(userInfo: notification.content.userInfo))
        XCTAssertNil(notification.trigger)
        XCTAssertEqual(notification.content.categoryIdentifier, ExportNotificationCategories.pendingExport)
        XCTAssertEqual(payload.requestID, request.id)
        XCTAssertEqual(payload.source, request.source)
        XCTAssertEqual(payload.reason, request.reason)
        XCTAssertEqual(
            notification.content.userInfo[ExportNotificationUserInfoKey.type] as? String,
            ExportNotificationType.pendingExport.rawValue
        )
        XCTAssertEqual(
            notification.content.userInfo[ExportNotificationUserInfoKey.pendingExportRequestID] as? String,
            "55555555-5555-5555-5555-555555555555"
        )
        XCTAssertEqual(
            notification.content.userInfo[ExportNotificationUserInfoKey.pendingExportSource] as? String,
            PendingExportSource.scheduled.rawValue
        )
        XCTAssertEqual(
            notification.content.userInfo[ExportNotificationUserInfoKey.pendingExportReason] as? String,
            PendingExportReason.protectedDataUnavailable.rawValue
        )
    }

    func testNotificationTapRouterParsesValidPendingExportPayload() throws {
        let request = pendingRequest(id: "66666666-6666-6666-6666-666666666666")
        let route = ExportPendingNotificationTapRouter.pendingExport.route(
            identifier: ExportNotificationIdentifiers.pendingExport(for: request),
            userInfo: anyHashableUserInfo(PendingExportNotificationPayload(request: request).userInfo)
        )

        XCTAssertEqual(route, .pendingExport(AutomationPendingExportNotificationPayload(request: request)))
    }

    func testNotificationTapRouterRejectsMissingPendingExportRequestID() throws {
        let request = pendingRequest(id: "77777777-7777-7777-7777-777777777777")
        var userInfo = PendingExportNotificationPayload(request: request).userInfo
        userInfo.removeValue(forKey: ExportNotificationUserInfoKey.pendingExportRequestID)

        let route = ExportPendingNotificationTapRouter.pendingExport.route(
            identifier: ExportNotificationIdentifiers.pendingExport(for: request),
            userInfo: anyHashableUserInfo(userInfo)
        )

        XCTAssertNil(route)
    }

    func testNotificationTapRouterRoutesLegacyReminderIdentifier() throws {
        let route = ExportPendingNotificationTapRouter.pendingExport.route(
            identifier: "com.codybontecou.healthmd.export.reminder.legacy",
            userInfo: [:]
        )

        XCTAssertEqual(route, .legacyScheduledExportReminder)
    }

    func testGenericFallbackPlannerBuildsStableScheduledNotificationPlan() throws {
        let request = pendingRequest(id: "88888888-8888-8888-8888-888888888888")
        let planner = AutomationPendingExportFallbackNotificationPlanner(
            configuration: ExportPendingNotificationConfiguration.pendingExport,
            fallbackDelay: 60,
            now: { Date(timeIntervalSince1970: 1_779_580_830) }
        )

        let plan = planner.scheduledNotificationPlan(for: request)

        XCTAssertEqual(plan.identifier, "healthmd.pending-export.88888888-8888-8888-8888-888888888888")
        XCTAssertEqual(plan.triggerInterval, 30)
        XCTAssertEqual(plan.categoryIdentifier, ExportNotificationCategories.pendingExport)
        XCTAssertEqual(plan.userInfo[ExportNotificationUserInfoKey.pendingExportRequestID], request.id.uuidString.lowercased())
        XCTAssertEqual(plan.userInfo[ExportNotificationUserInfoKey.pendingExportSource], PendingExportSource.scheduled.rawValue)
    }

    func testScheduledExportDocsRecordServerVisibleApnsDecision() throws {
        let docsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/features/scheduled-exports.md")
        let docs = try String(contentsOf: docsURL, encoding: .utf8)

        XCTAssertTrue(docs.contains("## Server-visible APNs fallback decision"))
        XCTAssertTrue(docs.contains("Decision: no server-visible APNs alert"))
        XCTAssertTrue(docs.contains("client pending request plus local notification fallback"))
        XCTAssertTrue(docs.contains("avoid duplicate notifications"))
    }

    private func anyHashableUserInfo(_ userInfo: [String: String]) -> [AnyHashable: Any] {
        userInfo.reduce(into: [AnyHashable: Any]()) { result, pair in
            result[pair.key] = pair.value
        }
    }

    private func pendingRequest(
        id: String,
        reason: PendingExportReason? = nil
    ) -> PendingExportRequest {
        PendingExportRequest(
            id: UUID(uuidString: id)!,
            dates: [Date(timeIntervalSince1970: 1_779_494_400)],
            source: .scheduled,
            reason: reason,
            scheduledFireDate: Date(timeIntervalSince1970: 1_779_580_800),
            createdAt: Date(timeIntervalSince1970: 1_779_490_000)
        )
    }
}

private final class FakeUserNotificationCenter: UserNotificationCentering {
    private(set) var pendingRequests: [String: UNNotificationRequest] = [:]
    private(set) var removedPendingIdentifiers: [String] = []
    private(set) var removedDeliveredIdentifiers: [String] = []

    func add(_ request: UNNotificationRequest) async throws {
        pendingRequests[request.identifier] = request
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(contentsOf: identifiers)
        for identifier in identifiers {
            pendingRequests.removeValue(forKey: identifier)
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }
}
