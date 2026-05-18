import UserNotifications
import XCTest
@testable import HealthMd

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
        let request = pendingRequest(id: "55555555-5555-5555-5555-555555555555")

        try await scheduler.sendImmediatePendingExportNotification(for: request)

        let notification = try XCTUnwrap(center.pendingRequests["healthmd.pending-export.55555555-5555-5555-5555-555555555555"])
        let payload = try XCTUnwrap(PendingExportNotificationPayload(userInfo: notification.content.userInfo))
        XCTAssertNil(notification.trigger)
        XCTAssertEqual(notification.content.categoryIdentifier, ExportNotificationCategories.pendingExport)
        XCTAssertEqual(payload.requestID, request.id)
        XCTAssertEqual(payload.source, request.source)
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

    private func pendingRequest(id: String) -> PendingExportRequest {
        PendingExportRequest(
            id: UUID(uuidString: id)!,
            dates: [Date(timeIntervalSince1970: 1_779_494_400)],
            source: .scheduled,
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
