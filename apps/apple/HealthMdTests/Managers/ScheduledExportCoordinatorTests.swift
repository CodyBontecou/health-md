import XCTest
@testable import HealthMd

final class ScheduledExportCoordinatorTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation state that
    // is unsafe during test teardown on some macOS runtimes. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []
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
        let pin = try makeSyntheticAppleExportEnginePin()
        let frozenSnapshot = makeFrozenSnapshot(pin: pin)
        let request = try await coordinator.preparePendingScheduledExport(
            schedule: schedule,
            fireDate: fireDate,
            makeSettingsSnapshot: { frozenSnapshot }
        )
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 2,
            failedDateDetails: [
                FailedDateDetail(date: request.dates[1], reason: .fileWriteError)
            ],
            completedDates: [request.dates[0]]
        )

        let completion = try await coordinator.completePendingScheduledExport(request, result: result)
        let retryRequest = try XCTUnwrap(try store.loadAll().first)

        XCTAssertEqual(completion, .preservedPartialSuccess)
        XCTAssertEqual(retryRequest.id, request.id)
        XCTAssertEqual(retryRequest.dates, [request.dates[1]])
        XCTAssertEqual(retryRequest.originalRequestedDates, request.dates)
        XCTAssertEqual(
            retryRequest.originalCalendarTimeZoneIdentifier,
            request.originalCalendarTimeZoneIdentifier
        )
        XCTAssertEqual(retryRequest.exportTarget, request.exportTarget)
        XCTAssertEqual(retryRequest.settingsSnapshot, frozenSnapshot)
        XCTAssertEqual(retryRequest.settingsSnapshot?.appleExportEnginePin, pin)
        XCTAssertEqual(scheduler.immediateRequests[request.id], retryRequest)
        XCTAssertFalse(scheduler.canceledRequestIDs.contains(request.id))

        var resumeSnapshotFactoryCalled = false
        let preparedAgain = try await coordinator.preparePendingScheduledExport(
            schedule: schedule,
            fireDate: fireDate,
            makeSettingsSnapshot: {
                resumeSnapshotFactoryCalled = true
                return nil
            }
        )
        XCTAssertFalse(resumeSnapshotFactoryCalled, "Resume must not resolve mutable settings or engine flags")
        XCTAssertEqual(preparedAgain, retryRequest, "Same-occurrence preparation must not re-expand completed dates")
    }

    func testResidualRetryAndRelaunchPreserveFrozenOriginalOwnerDatesByteForByte() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = InMemoryPendingExportStore()
        let scheduler = InspectableExportNotificationScheduler()
        let coordinator = makeCoordinator(store: store, scheduler: scheduler, now: fireDate)
        let snapshot = makeFrozenSnapshot(pin: try makeSyntheticAppleExportEnginePin())
        let request = try await coordinator.preparePendingScheduledExport(
            schedule: ExportSchedule(
                isEnabled: true,
                frequency: .weekly,
                preferredHour: 8,
                lookbackDays: 2
            ),
            fireDate: fireDate,
            makeSettingsSnapshot: { snapshot }
        )
        let originalBytes = try JSONEncoder().encode(request.originalRequestedDates)
        let completion = try await coordinator.completePendingScheduledExport(
            request,
            result: ExportOrchestrator.ExportResult(
                successCount: 1,
                totalCount: 2,
                failedDateDetails: [
                    FailedDateDetail(date: request.dates[1], reason: .fileWriteError)
                ],
                completedDates: [request.dates[0]]
            )
        )
        let retry = try XCTUnwrap(try store.loadAll().first)
        let relaunched = try JSONDecoder().decode(
            PendingExportRequest.self,
            from: JSONEncoder().encode(retry)
        )
        let frozenTimeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let identifiers = relaunched.originalRequestedDates.map {
            HealthRollupDateFormatting.dayString($0, timeZone: frozenTimeZone)
        }

        XCTAssertEqual(completion, .preservedPartialSuccess)
        XCTAssertEqual(try JSONEncoder().encode(retry.originalRequestedDates), originalBytes)
        XCTAssertEqual(try JSONEncoder().encode(relaunched.originalRequestedDates), originalBytes)
        XCTAssertEqual(identifiers, ["2026-05-16", "2026-05-17"])
        XCTAssertEqual(relaunched.originalCalendarTimeZoneIdentifier, frozenTimeZone.identifier)
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
            completedDates: request.dates
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

        // The preserved retry is marked attempted (fireDate is the injected
        // coordinator clock) so bulk fallback cancellation cannot destroy it.
        let expectedRetry = request.markingAttempted(at: fireDate)
        XCTAssertEqual(try store.loadAll(), [expectedRetry])
        XCTAssertEqual(scheduler.immediateRequests[request.id], expectedRetry)
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

        XCTAssertEqual(try store.loadAll(), [request.markingAttempted(at: fireDate)])
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

    private func makeFrozenSnapshot(pin: AppleExportEnginePin) -> ExportSettingsSnapshot {
        let suiteName = "ScheduledExportCoordinatorTests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(
            settings,
            appleExportEnginePin: pin,
            calendarTimeZoneIdentifier: "America/Los_Angeles"
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

final class InMemoryPendingExportStore: PendingExportStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [PendingExportRequest] = []

    func loadAll() throws -> [PendingExportRequest] {
        lock.withLock { requests }
    }

    func upsert(_ request: PendingExportRequest) throws {
        lock.withLock {
            requests.removeAll { $0.id == request.id }
            requests.append(request)
        }
    }

    func remove(id: PendingExportRequest.ID) throws {
        lock.withLock {
            requests.removeAll { $0.id == id }
        }
    }

    func clearCompletedRequests(ids: Set<PendingExportRequest.ID>) throws {
        lock.withLock {
            requests.removeAll { ids.contains($0.id) }
        }
    }

    func notificationIdentifier(for request: PendingExportRequest) -> String {
        ExportNotificationIdentifiers.pendingExport(for: request)
    }
}
