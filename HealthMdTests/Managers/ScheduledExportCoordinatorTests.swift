import XCTest
@testable import HealthMd

final class ScheduledExportCoordinatorTests: XCTestCase {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testPreparePendingScheduledExport_dailyScheduleUsesYesterdayOnly() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)

        let request = try await coordinator.preparePendingScheduledExport(
            schedule: schedule,
            fireDate: fireDate
        )

        XCTAssertEqual(request.dates, [
            date(year: 2026, month: 5, day: 17)
        ])
        XCTAssertEqual(request.source, .scheduled)
        XCTAssertEqual(request.scheduledFireDate, fireDate)
        XCTAssertEqual(request.exportTarget, .localIPhoneFolder)
        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertEqual(scheduler.scheduledRequests[request.id], request)
    }

    func testPreparePendingScheduledExport_weeklyCustomLookbackUsesCompleteWindowEndingYesterday() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            lookbackDays: 5
        )

        let request = try await coordinator.preparePendingScheduledExport(
            schedule: schedule,
            fireDate: fireDate
        )

        XCTAssertEqual(request.dates, [
            date(year: 2026, month: 5, day: 13),
            date(year: 2026, month: 5, day: 14),
            date(year: 2026, month: 5, day: 15),
            date(year: 2026, month: 5, day: 16),
            date(year: 2026, month: 5, day: 17)
        ])
        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertEqual(scheduler.scheduledRequests[request.id], request)
    }

    func testPreparePendingScheduledExport_snapshotsAPITarget() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            target: .apiEndpoint
        )

        let request = try await coordinator.preparePendingScheduledExport(
            schedule: schedule,
            fireDate: fireDate
        )

        XCTAssertEqual(request.exportTarget, .apiEndpoint)
        XCTAssertEqual(scheduler.scheduledRequests[request.id]?.exportTarget, .apiEndpoint)
    }

    func testCompletePendingScheduledExport_successClearsRequestAndCancelsNotification() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let request = try await coordinator.preparePendingScheduledExport(schedule: schedule, fireDate: fireDate)
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: []
        )

        let completion = try await coordinator.completePendingScheduledExport(request, result: result)

        XCTAssertEqual(completion, .clearedAfterSuccess)
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertTrue(scheduler.canceledRequestIDs.contains(request.id))
        XCTAssertNil(scheduler.scheduledRequests[request.id])
        XCTAssertNil(scheduler.immediateRequests[request.id])
    }

    func testCompletePendingScheduledExport_partialSuccessKeepsRequestForRetry() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            lookbackDays: 2
        )
        let request = try await coordinator.preparePendingScheduledExport(schedule: schedule, fireDate: fireDate)
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 2,
            failedDateDetails: [
                FailedDateDetail(date: request.dates[1], reason: .fileWriteError)
            ]
        )

        let completion = try await coordinator.completePendingScheduledExport(request, result: result)

        XCTAssertEqual(completion, .preservedPartialSuccess)
        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertFalse(scheduler.canceledRequestIDs.contains(request.id))
    }

    func testCompletePendingScheduledExport_reportedNoDataClearsCompletedRequest() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            lookbackDays: 2
        )
        let request = try await coordinator.preparePendingScheduledExport(schedule: schedule, fireDate: fireDate)
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 2,
            failedDateDetails: [
                FailedDateDetail(date: request.dates[1], reason: .noHealthData)
            ],
            completedDateCount: 2
        )

        let completion = try await coordinator.completePendingScheduledExport(request, result: result)

        XCTAssertEqual(completion, .clearedAfterSuccess)
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertTrue(scheduler.canceledRequestIDs.contains(request.id))
    }

    func testCompletePendingScheduledExport_deviceLockedKeepsRequestAndSendsImmediateNotification() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let request = try await coordinator.preparePendingScheduledExport(schedule: schedule, fireDate: fireDate)
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 1,
            failedDateDetails: [
                FailedDateDetail(date: request.dates[0], reason: .deviceLocked)
            ]
        )

        try await coordinator.completePendingScheduledExport(request, result: result)

        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertEqual(scheduler.immediateRequests[request.id], request)
        XCTAssertFalse(scheduler.canceledRequestIDs.contains(request.id))
    }

    func testCompletePendingScheduledExport_nonLockFailureKeepsRequestWithoutImmediateRecoveryNotification() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let request = try await coordinator.preparePendingScheduledExport(schedule: schedule, fireDate: fireDate)
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 1,
            failedDateDetails: [
                FailedDateDetail(date: request.dates[0], reason: .healthKitError)
            ]
        )

        try await coordinator.completePendingScheduledExport(request, result: result)

        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertNil(scheduler.immediateRequests[request.id])
        XCTAssertFalse(scheduler.canceledRequestIDs.contains(request.id))
    }

    func testPreparePendingScheduledExport_duplicateSameOccurrenceDoesNotCreateDuplicateRequest() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)

        let first = try await coordinator.preparePendingScheduledExport(schedule: schedule, fireDate: fireDate)
        let second = try await coordinator.preparePendingScheduledExport(schedule: schedule, fireDate: fireDate)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try store.loadAll(), [second])
        XCTAssertEqual(scheduler.scheduledRequests.count, 1)
        XCTAssertEqual(scheduler.scheduledRequests[second.id], second)
    }

    private func makeCoordinator(
        store: InMemoryPendingExportStore,
        scheduler: InspectableExportNotificationScheduler,
        now: Date
    ) -> ScheduledExportCoordinator {
        var nextID = 0
        let ids = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        ]

        return ScheduledExportCoordinator(
            pendingExportStore: store,
            exportNotificationScheduler: scheduler,
            calendar: Self.calendar,
            now: { now },
            makeID: {
                defer { nextID += 1 }
                return ids[nextID]
            }
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(
            timeZone: Self.calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

private final class InMemoryPendingExportStore: PendingExportStoring {
    private var requests: [PendingExportRequest] = []

    func loadAll() throws -> [PendingExportRequest] {
        requests
    }

    func upsert(_ request: PendingExportRequest) throws {
        requests.removeAll { $0.id == request.id }
        requests.append(request)
    }

    func remove(id: PendingExportRequest.ID) throws {
        requests.removeAll { $0.id == id }
    }

    func clearCompletedRequests(ids: Set<PendingExportRequest.ID>) throws {
        requests.removeAll { ids.contains($0.id) }
    }

    func notificationIdentifier(for request: PendingExportRequest) -> String {
        ExportNotificationIdentifiers.pendingExport(for: request)
    }
}
