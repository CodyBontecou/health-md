#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class SchedulingManagerPendingExportsTests: XCTestCase {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testPerformPendingExportWithRequestIDExportsStoredDatesAndClearsOnSuccess() async throws {
        let request = pendingRequest(
            id: "11111111-1111-1111-1111-111111111111",
            dates: [
                date(year: 2026, month: 5, day: 12),
                date(year: 2026, month: 5, day: 14)
            ],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let manager = makeManager(store: store, notificationScheduler: notificationScheduler) { dates, source in
            runs.append(PendingExportRun(dates: dates, source: source))
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(runs, [PendingExportRun(dates: request.dates, source: .scheduled)])
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertTrue(notificationScheduler.canceledRequestIDs.contains(request.id))
        XCTAssertEqual(manager.notificationExportResult?.status, .success(daysExported: 2))
    }

    func testPerformPendingExportPartialSuccessKeepsRequestAndDoesNotAdvanceSchedule() async throws {
        let request = pendingRequest(
            id: "abababab-abab-abab-abab-abababababab",
            dates: [
                date(year: 2026, month: 5, day: 12),
                date(year: 2026, month: 5, day: 13)
            ],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            lookbackDays: 2
        )
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler,
            schedule: schedule
        ) { dates, _ in
            ExportOrchestrator.ExportResult(
                successCount: 1,
                totalCount: dates.count,
                failedDateDetails: [
                    FailedDateDetail(date: dates[1], reason: .fileWriteError)
                ]
            )
        }

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertFalse(notificationScheduler.canceledRequestIDs.contains(request.id))
        XCTAssertNil(manager.schedule.lastExportDate)
        XCTAssertEqual(
            manager.notificationExportResult?.status,
            .partialSuccess(exported: 1, total: 2)
        )
    }

    func testPerformPendingExportReportedNoDataClearsRequestAndAdvancesSchedule() async throws {
        let request = pendingRequest(
            id: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd",
            dates: [
                date(year: 2026, month: 5, day: 12),
                date(year: 2026, month: 5, day: 13)
            ],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler
        ) { dates, _ in
            ExportOrchestrator.ExportResult(
                successCount: 1,
                totalCount: dates.count,
                failedDateDetails: [
                    FailedDateDetail(date: dates[1], reason: .noHealthData)
                ],
                completedDateCount: dates.count
            )
        }

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertTrue(notificationScheduler.canceledRequestIDs.contains(request.id))
        XCTAssertNotNil(manager.schedule.lastExportDate)
        XCTAssertEqual(
            manager.notificationExportResult?.status,
            .partialSuccess(exported: 1, total: 2)
        )
    }

    func testPerformPendingExportWithMissingRequestIsNoOp() async throws {
        let store = TestPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let manager = makeManager(store: store, notificationScheduler: notificationScheduler) { dates, source in
            runs.append(PendingExportRun(dates: dates, source: source))
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.performPendingExport(
            requestId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: .scheduled
        )

        XCTAssertEqual(runs, [])
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertNil(manager.notificationExportResult)
    }

    func testAppActiveDrainRunsAllPendingScheduledRequestsWhenScheduleEnabled() async throws {
        let first = pendingRequest(
            id: "33333333-3333-3333-3333-333333333333",
            dates: [date(year: 2026, month: 5, day: 10)],
            source: .scheduled,
            createdAt: date(year: 2026, month: 5, day: 11, hour: 8)
        )
        let second = pendingRequest(
            id: "44444444-4444-4444-4444-444444444444",
            dates: [
                date(year: 2026, month: 5, day: 12),
                date(year: 2026, month: 5, day: 13)
            ],
            source: .scheduled,
            createdAt: date(year: 2026, month: 5, day: 14, hour: 8)
        )
        let store = TestPendingExportStore(requests: [second, first])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let manager = makeManager(store: store, notificationScheduler: notificationScheduler) { dates, source in
            runs.append(PendingExportRun(dates: dates, source: source))
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        XCTAssertEqual(runs, [
            PendingExportRun(dates: first.dates, source: .scheduled),
            PendingExportRun(dates: second.dates, source: .scheduled)
        ])
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertTrue(notificationScheduler.canceledRequestIDs.contains(first.id))
        XCTAssertTrue(notificationScheduler.canceledRequestIDs.contains(second.id))
    }

    func testAppActiveDrainSkipsFutureScheduledFallbackRequest() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let request = pendingRequest(
            id: "99999999-9999-9999-9999-999999999999",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled,
            scheduledFireDate: fireDate
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler,
            now: date(year: 2026, month: 5, day: 17, hour: 12)
        ) { dates, source in
            runs.append(PendingExportRun(dates: dates, source: source))
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        XCTAssertEqual(runs, [])
        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertFalse(notificationScheduler.canceledRequestIDs.contains(request.id))
    }

    func testAppActiveDrainDiscardsScheduledRequestBeforeCurrentEnablePeriod() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let request = pendingRequest(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled,
            scheduledFireDate: fireDate
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            enabledAt: date(year: 2026, month: 5, day: 18, hour: 12)
        )
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler,
            schedule: schedule,
            now: date(year: 2026, month: 5, day: 18, hour: 13)
        ) { dates, source in
            runs.append(PendingExportRun(dates: dates, source: source))
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        XCTAssertEqual(runs, [])
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertTrue(notificationScheduler.canceledRequestIDs.contains(request.id))
    }

    func testAppActiveDrainSkipsScheduledRequestsWhenScheduleDisabledButHonorsShortcutRequests() async throws {
        let scheduled = pendingRequest(
            id: "55555555-5555-5555-5555-555555555555",
            dates: [date(year: 2026, month: 5, day: 10)],
            source: .scheduled
        )
        let shortcut = pendingRequest(
            id: "66666666-6666-6666-6666-666666666666",
            dates: [date(year: 2026, month: 5, day: 11)],
            source: .shortcut
        )
        let store = TestPendingExportStore(requests: [scheduled, shortcut])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler,
            schedule: ExportSchedule(isEnabled: false)
        ) { dates, source in
            runs.append(PendingExportRun(dates: dates, source: source))
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        XCTAssertEqual(runs, [PendingExportRun(dates: shortcut.dates, source: .shortcut)])
        XCTAssertEqual(try store.loadAll(), [scheduled])
        XCTAssertFalse(notificationScheduler.canceledRequestIDs.contains(scheduled.id))
        XCTAssertTrue(notificationScheduler.canceledRequestIDs.contains(shortcut.id))
    }

    func testDeviceLockedDrainAttemptKeepsRequestAndRecoveryNotification() async throws {
        let request = pendingRequest(
            id: "77777777-7777-7777-7777-777777777777",
            dates: [date(year: 2026, month: 5, day: 10)],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let manager = makeManager(store: store, notificationScheduler: notificationScheduler) { dates, _ in
            ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: [
                    FailedDateDetail(date: dates[0], reason: .deviceLocked)
                ]
            )
        }

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertEqual(notificationScheduler.immediateRequests[request.id], request)
        XCTAssertFalse(notificationScheduler.canceledRequestIDs.contains(request.id))
        XCTAssertEqual(manager.notificationExportResult?.status, .failure(reason: ExportFailureReason.deviceLocked.shortDescription))
    }

    func testNotificationTapDoesNotDoubleRunRequestAlreadyBeingDrained() async throws {
        let request = pendingRequest(
            id: "88888888-8888-8888-8888-888888888888",
            dates: [date(year: 2026, month: 5, day: 10)],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        var continuation: CheckedContinuation<Void, Never>?
        let manager = makeManager(store: store, notificationScheduler: notificationScheduler) { dates, source in
            runs.append(PendingExportRun(dates: dates, source: source))
            if runs.count == 1 {
                await withCheckedContinuation { pendingContinuation in
                    continuation = pendingContinuation
                }
            }
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        let drainTask = Task { @MainActor in
            await manager.drainPendingExportsIfNeeded(trigger: .appActive)
        }

        for _ in 0..<10 where continuation == nil {
            await Task.yield()
        }
        guard let pendingContinuation = continuation else {
            XCTFail("Expected pending export runner to suspend")
            return
        }

        let tapTask = Task { @MainActor in
            await manager.performPendingExport(requestId: request.id, source: .scheduled)
        }
        await Task.yield()

        XCTAssertEqual(runs, [PendingExportRun(dates: request.dates, source: .scheduled)])

        pendingContinuation.resume()
        await drainTask.value
        await tapTask.value

        XCTAssertEqual(runs, [PendingExportRun(dates: request.dates, source: .scheduled)])
        XCTAssertEqual(try store.loadAll(), [])
    }

    func testSilentPushScheduledExportUsesScheduleTargetAndPersistsItWhenDeviceLocked() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = TestPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            preferredMinute: 0,
            target: .apiEndpoint,
            lookbackDays: 1,
            enabledAt: date(year: 2026, month: 5, day: 17, hour: 8)
        )
        let manager = SchedulingManager(
            pendingExportStore: store,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: schedule,
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false,
            scheduledTargetExportRunner: { dates, target in
                runs.append(PendingExportRun(dates: dates, source: .scheduled, target: target))
                return ExportOrchestrator.ExportResult(
                    successCount: 0,
                    totalCount: dates.count,
                    failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .deviceLocked) }
                )
            },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 8, minute: 1) }
        )

        await manager.performSilentPushExport(fireDate: fireDate)

        let expectedDates = ScheduleDateMath.scheduledExportDates(schedule: schedule, fireDate: fireDate)
        XCTAssertEqual(runs, [PendingExportRun(dates: expectedDates, source: .scheduled, target: .apiEndpoint)])
        let request = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(request.exportTarget, .apiEndpoint)
        XCTAssertEqual(notificationScheduler.immediateRequests[request.id]?.exportTarget, .apiEndpoint)
    }

    func testSilentPushPartialBatchKeepsRequestAndDoesNotAdvanceCompletedDayMarker() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 8)
        let store = TestPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            preferredMinute: 0,
            target: .apiEndpoint,
            lookbackDays: 10,
            enabledAt: date(year: 2026, month: 5, day: 17, hour: 8)
        )
        let manager = SchedulingManager(
            pendingExportStore: store,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: schedule,
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false,
            scheduledTargetExportRunner: { dates, _ in
                ExportOrchestrator.ExportResult(
                    successCount: 7,
                    totalCount: dates.count,
                    failedDateDetails: dates.dropFirst(7).map {
                        FailedDateDetail(date: $0, reason: .fileWriteError)
                    }
                )
            },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 8, minute: 1) }
        )

        await manager.performSilentPushExport(fireDate: fireDate)

        let request = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(request.exportTarget, .apiEndpoint)
        XCTAssertEqual(request.dates.count, 10)
        XCTAssertNil(manager.schedule.lastExportDate)
    }

    func testSilentPushPartialTodayRefreshDoesNotAdvanceRefreshMarker() async throws {
        let fireDate = date(year: 2026, month: 5, day: 18, hour: 9)
        let store = TestPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            target: .apiEndpoint,
            todayRefreshEnabled: true,
            todayRefreshIntervalHours: 3,
            enabledAt: date(year: 2026, month: 5, day: 17, hour: 8)
        )
        let manager = SchedulingManager(
            pendingExportStore: store,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: schedule,
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false,
            scheduledTargetExportRunner: { dates, _ in
                ExportOrchestrator.ExportResult(
                    successCount: 1,
                    totalCount: 2,
                    failedDateDetails: [
                        FailedDateDetail(date: dates[0], reason: .fileWriteError)
                    ]
                )
            },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 9, minute: 1) }
        )

        await manager.performSilentPushExport(fireDate: fireDate, kind: .todayRefresh)

        let request = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(request.scheduledKind, .todayRefresh)
        XCTAssertNil(manager.schedule.lastTodayRefreshDate)
    }

    func testPendingScheduledExportRetriesOriginalTargetEvenIfScheduleTargetChanged() async throws {
        let request = pendingRequest(
            id: "12121212-1212-1212-1212-121212121212",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled,
            exportTarget: .connectedMac
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            target: .apiEndpoint,
            enabledAt: date(year: 2026, month: 5, day: 17, hour: 8)
        )
        let manager = SchedulingManager(
            pendingExportStore: store,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: schedule,
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false,
            scheduledTargetExportRunner: { dates, target in
                runs.append(PendingExportRun(dates: dates, source: .scheduled, target: target))
                return ExportOrchestrator.ExportResult(
                    successCount: dates.count,
                    totalCount: dates.count,
                    failedDateDetails: []
                )
            },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 9) }
        )

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(runs, [PendingExportRun(dates: request.dates, source: .scheduled, target: .connectedMac)])
        XCTAssertEqual(try store.loadAll(), [])
    }

    private func makeManager(
        store: TestPendingExportStore,
        notificationScheduler: InspectableExportNotificationScheduler,
        schedule: ExportSchedule? = nil,
        now: Date? = nil,
        exportRunner: @MainActor @escaping ([Date], PendingExportSource) async -> ExportOrchestrator.ExportResult
    ) -> SchedulingManager {
        let resolvedSchedule = schedule ?? ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let resolvedNow = now ?? date(year: 2026, month: 5, day: 18, hour: 9)
        return SchedulingManager(
            pendingExportStore: store,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: resolvedSchedule,
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false,
            shortcutExportRunner: { dates in
                let result = await exportRunner(dates, .shortcut)
                return self.shortcutOutcome(from: result)
            },
            scheduledPendingExportRunner: { dates in
                await exportRunner(dates, .scheduled)
            },
            now: { resolvedNow }
        )
    }

    private func shortcutOutcome(from result: ExportOrchestrator.ExportResult) -> ExportIntentRunner.Outcome {
        if result.successCount > 0 {
            if result.isFullSuccess {
                return .success(daysExported: result.successCount, formatsPerDate: result.formatsPerDate)
            }
            return .partial(
                exported: result.successCount,
                total: result.totalCount,
                formatsPerDate: result.formatsPerDate,
                reason: result.primaryFailureReason?.shortDescription ?? "Some days had no data"
            )
        }

        return .failure(reason: result.primaryFailureReason?.shortDescription ?? "Unknown error")
    }

    private func pendingRequest(
        id: String,
        dates: [Date],
        source: PendingExportSource,
        createdAt: Date? = nil,
        scheduledFireDate: Date? = nil,
        exportTarget: ExportTargetSelection? = nil
    ) -> PendingExportRequest {
        PendingExportRequest(
            id: UUID(uuidString: id)!,
            dates: dates,
            source: source,
            scheduledFireDate: source == .scheduled ? (scheduledFireDate ?? date(year: 2026, month: 5, day: 18, hour: 8)) : nil,
            createdAt: createdAt ?? date(year: 2026, month: 5, day: 18, hour: 9),
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            exportTarget: exportTarget,
            calendar: Self.calendar
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

private struct PendingExportRun: Equatable {
    let dates: [Date]
    let source: PendingExportSource
    let target: ExportTargetSelection

    init(
        dates: [Date],
        source: PendingExportSource,
        target: ExportTargetSelection = .localIPhoneFolder
    ) {
        self.dates = dates
        self.source = source
        self.target = target
    }
}

private final class TestPendingExportStore: PendingExportStoring {
    private var requests: [PendingExportRequest]

    init(requests: [PendingExportRequest] = []) {
        self.requests = requests
    }

    func loadAll() throws -> [PendingExportRequest] {
        requests.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
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
#endif
