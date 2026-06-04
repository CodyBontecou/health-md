import XCTest
@testable import HealthMd

final class PortableExportAutomationTests: XCTestCase {
    func testScheduleSyncerRegistersOnlyScheduleMetadataWithServer() async throws {
        let server = SpyScheduleServerClient()
        let schedule = PortableExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            preferredMinute: 30,
            lookbackDays: 1,
            lastExportDate: nil,
            timezoneIdentifier: "America/Chicago"
        )
        let syncer = PortableExportScheduleSyncer(server: server)

        try await syncer.sync(
            schedule: schedule,
            installationID: "install-1",
            appID: "com.example.exports",
            apnsToken: "token-123"
        )

        XCTAssertEqual(server.registrations.count, 1)
        let registration = try XCTUnwrap(server.registrations.first)
        XCTAssertEqual(registration.installationID, "install-1")
        XCTAssertEqual(registration.appID, "com.example.exports")
        XCTAssertEqual(registration.apnsToken, "token-123")
        XCTAssertEqual(registration.timezoneIdentifier, "America/Chicago")
        XCTAssertEqual(registration.schedule.frequency, .daily)
    }

    func testBackgroundRunnerCreatesPendingRequestAndNotificationWhenExportNeedsForegroundRetry() async throws {
        let pendingStore = InMemoryPortablePendingExportStore()
        let notifier = SpyPortableExportNotificationScheduler()
        let runner = PortableBackgroundExportRunner(
            pendingStore: pendingStore,
            notificationScheduler: notifier,
            now: { Date(timeIntervalSince1970: 1000) }
        )
        let date = Date(timeIntervalSince1970: 500)
        let failure = PortableExportFailure(
            recordID: nil,
            date: date,
            category: .dataProtected,
            message: "Data is protected while the device is locked."
        )

        let outcome = await runner.runScheduledExport(
            dates: [date],
            scheduledFireDate: date,
            export: {
                PortableExportRunResult(
                    successfulRecordCount: 0,
                    totalRecordCount: 1,
                    filesWritten: 0,
                    failures: [failure],
                    trigger: .silentPush
                )
            }
        )

        guard case .pendingCreated(let request) = outcome else {
            return XCTFail("Expected pendingCreated, got \(outcome)")
        }
        XCTAssertEqual(request.reason, .dataProtected)
        XCTAssertEqual(request.source, .silentPush)
        XCTAssertEqual(request.dates, [date])
        XCTAssertEqual(request.notificationUserInfo[PortableNotificationTapRouter.kindKey], PortableNotificationTapRouter.pendingExportKind)
        XCTAssertEqual(request.notificationUserInfo[PortableNotificationTapRouter.pendingExportIDKey], request.id.uuidString)
        XCTAssertEqual(try pendingStore.load(id: request.id), request)
        XCTAssertEqual(notifier.scheduledPendingRequests, [request])
    }

    func testNotificationTapRetryClearsPendingRequestOnSuccess() async throws {
        let pendingStore = InMemoryPortablePendingExportStore()
        let notifier = SpyPortableExportNotificationScheduler()
        let request = PortablePendingExportRequest(
            id: UUID(),
            dates: [Date(timeIntervalSince1970: 500)],
            source: .silentPush,
            reason: .dataProtected,
            createdAt: Date(timeIntervalSince1970: 1000),
            scheduledFireDate: Date(timeIntervalSince1970: 500)
        )
        try pendingStore.upsert(request)
        let coordinator = PortablePendingExportRetryCoordinator(
            pendingStore: pendingStore,
            notificationScheduler: notifier
        )

        let outcome = await coordinator.handleNotificationTap(
            userInfo: request.notificationUserInfo,
            retry: { pending in
                XCTAssertEqual(pending, request)
                return PortableExportRunResult(
                    successfulRecordCount: 1,
                    totalRecordCount: 1,
                    filesWritten: 2,
                    failures: [],
                    trigger: .notificationTap
                )
            }
        )

        guard case .success(let result) = outcome else {
            return XCTFail("Expected success, got \(outcome)")
        }
        XCTAssertEqual(result.filesWritten, 2)
        XCTAssertNil(try pendingStore.load(id: request.id))
        XCTAssertTrue(notifier.scheduledPendingRequests.isEmpty)
    }
}

private final class SpyScheduleServerClient: PortableExportScheduleServerClient {
    var registrations: [PortableExportScheduleRegistration] = []
    var unregistrations: [(installationID: String, appID: String)] = []

    func registerSchedule(_ registration: PortableExportScheduleRegistration) async throws {
        registrations.append(registration)
    }

    func unregisterSchedule(installationID: String, appID: String) async throws {
        unregistrations.append((installationID, appID))
    }
}

private final class SpyPortableExportNotificationScheduler: PortableExportNotificationScheduling {
    var scheduledPendingRequests: [PortablePendingExportRequest] = []

    func schedulePendingExportNotification(for request: PortablePendingExportRequest) async throws {
        scheduledPendingRequests.append(request)
    }
}
