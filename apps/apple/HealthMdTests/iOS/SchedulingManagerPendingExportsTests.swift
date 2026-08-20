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
        XCTAssertEqual(manager.schedule.lastExportDate, request.scheduledFireDate)
        XCTAssertEqual(manager.notificationExportResult?.status, .success(daysExported: 2))
    }

    func testNotificationTriggeredPendingExportShowsActivityBeforeRunnerStarts() async throws {
        let request = pendingRequest(
            id: "12121212-1212-1212-1212-121212121212",
            dates: [date(year: 2026, month: 5, day: 12)],
            source: .scheduled,
            exportTarget: .localIPhoneFolder
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let tracker = NotificationExportActivityTracker.shared
        tracker.clear()
        defer { tracker.clear() }
        var observedStart: NotificationExportActivityTracker.Snapshot?
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler
        ) { dates, _ in
            observedStart = tracker.snapshot
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(observedStart?.operationID, request.id)
        XCTAssertEqual(observedStart?.source, .scheduled)
        XCTAssertEqual(observedStart?.targetLabel, "Local iPhone Folder")
        XCTAssertEqual(observedStart?.phase, .preparing)
        XCTAssertEqual(tracker.snapshot?.phase, .completed)
        XCTAssertTrue(manager.notificationExportResult.map(tracker.handles) ?? false)
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
        var runs: [[Date]] = []
        var remainingQuota = 1
        var recordedQuotaJobIDs: Set<UUID> = []
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler,
            schedule: schedule,
            quotaAccess: { jobID in
                remainingQuota > 0 || jobID.map(recordedQuotaJobIDs.contains) == true
            },
            quotaRecorder: { jobID in
                guard let jobID, recordedQuotaJobIDs.insert(jobID).inserted else { return }
                remainingQuota -= 1
            }
        ) { dates, _ in
            runs.append(dates)
            if dates.count == 2 {
                return ExportOrchestrator.ExportResult(
                    successCount: 1,
                    totalCount: dates.count,
                    failedDateDetails: [
                        FailedDateDetail(date: dates[1], reason: .fileWriteError)
                    ],
                    completedDates: [dates[0]]
                )
            }
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: [],
                completedDates: dates
            )
        }

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        let retryRequest = try XCTUnwrap(try store.loadAll().first)
        let normalizedRetryDate = Calendar.current.startOfDay(for: request.dates[1])
        XCTAssertEqual(retryRequest.dates, [normalizedRetryDate])
        XCTAssertEqual(notificationScheduler.immediateRequests[request.id], retryRequest)
        XCTAssertFalse(notificationScheduler.canceledRequestIDs.contains(request.id))
        XCTAssertNil(manager.schedule.lastExportDate)
        XCTAssertEqual(
            manager.notificationExportResult?.status,
            .partialSuccess(exported: 1, total: 2)
        )
        XCTAssertEqual(remainingQuota, 0)
        XCTAssertEqual(recordedQuotaJobIDs, [request.id])

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(runs, [request.dates, [normalizedRetryDate]])
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertNotNil(manager.schedule.lastExportDate)
        XCTAssertEqual(remainingQuota, 0, "Retrying the same scheduled request must not consume another export")
        XCTAssertEqual(recordedQuotaJobIDs, [request.id])
    }

    func testPendingScheduledExportWaitsWhenFreeQuotaIsExhausted() async throws {
        let request = pendingRequest(
            id: "acacacac-acac-acac-acac-acacacacacac",
            dates: [date(year: 2026, month: 5, day: 12)],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        var exportRunCount = 0
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler,
            quotaAccess: { _ in false },
            quotaRecorder: { _ in XCTFail("A blocked scheduled export must not consume quota") }
        ) { dates, _ in
            exportRunCount += 1
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(exportRunCount, 0)
        let preserved = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(preserved.id, request.id)
        XCTAssertEqual(preserved.dates, request.dates)
        XCTAssertNotNil(preserved.attemptedAt, "the blocked attempt marks the request as a preserved retry")
        XCTAssertNil(manager.schedule.lastExportDate)
        guard case .failure(let reason) = manager.notificationExportResult?.status else {
            XCTFail("Expected an export-limit failure")
            return
        }
        XCTAssertTrue(reason.contains("Free export limit reached"))
        XCTAssertTrue(history.history.isEmpty, "Quota checks should not create duplicate export-history failures")
    }

    func testChangedScheduledDestinationFailsAllDatesWithoutRunningExportOrAdvancingSchedule() async throws {
        let request = pendingRequest(
            id: "bcbcbcbc-bcbc-bcbc-bcbc-bcbcbcbcbcbc",
            dates: [
                date(year: 2026, month: 5, day: 12),
                date(year: 2026, month: 5, day: 13)
            ],
            source: .scheduled,
            exportTarget: .localIPhoneFolder
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var exportWorkCount = 0
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let manager = SchedulingManager(
            pendingExportStore: store,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8),
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false,
            scheduledPendingExportRunner: { dates in
                exportWorkCount += 1
                return ExportOrchestrator.ExportResult(
                    successCount: dates.count,
                    totalCount: dates.count,
                    failedDateDetails: []
                )
            },
            scheduledLocalDestinationPreflight: { dates in
                ExportOrchestrator.ExportResult(
                    successCount: 0,
                    totalCount: dates.count,
                    failedDateDetails: dates.map {
                        FailedDateDetail(
                            date: $0,
                            reason: .accessDenied,
                            errorDetails: VaultManager.destinationChangedMessage
                        )
                    }
                )
            },
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 9) }
        )

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(exportWorkCount, 0)
        let preserved = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(preserved.id, request.id)
        XCTAssertEqual(preserved.dates, request.dates)
        XCTAssertNotNil(preserved.attemptedAt)
        XCTAssertNil(manager.schedule.lastExportDate)
        XCTAssertEqual(
            manager.notificationExportResult?.status,
            .failure(reason: VaultManager.destinationChangedMessage)
        )
        let historyEntry = try XCTUnwrap(history.history.first)
        XCTAssertEqual(historyEntry.failureReason, .accessDenied)
        XCTAssertEqual(historyEntry.failedDateDetails.count, request.dates.count)
        XCTAssertEqual(
            historyEntry.failedDateDetails.first?.errorDetails,
            VaultManager.destinationChangedMessage
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
                completedDates: dates
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

    func testNotificationTapWithAllSchedulingOffStillReportsSchedulingDisabled() async throws {
        // No profile entries and the legacy schedule off: the pending
        // notification is genuinely stale, so the tap keeps the honest
        // "Scheduling is disabled" failure instead of running anything.
        let request = pendingRequest(
            id: "16161616-1616-1616-1616-161616161616",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
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

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertEqual(runs, [])
        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertEqual(
            manager.notificationExportResult?.status,
            .failure(reason: String(localized: "Scheduling is disabled", comment: "Error message when scheduling is disabled"))
        )
    }

    /// The armed +60s fallback is defused the moment a pending run starts (no
    /// mid-run "Needs Attention"), without removing a delivered copy, and a
    /// device-locked completion re-arms the retry notification.
    func testPendingRunDefusesArmedFallbackButKeepsDeliveredRetrySurface() async throws {
        let request = pendingRequest(
            id: "17171717-1717-1717-1717-171717171717",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        // The fallback is armed (pending) for this request.
        try await notificationScheduler.schedulePendingExportNotification(for: request)
        XCTAssertTrue(notificationScheduler.scheduledRequests[request.id] != nil)

        var observedArmedCancels: [PendingExportRequest.ID] = []
        var continuation: CheckedContinuation<Void, Never>?
        let manager = makeManager(store: store, notificationScheduler: notificationScheduler) { dates, _ in
            observedArmedCancels = notificationScheduler.armedCanceledRequestIDs
            await withCheckedContinuation { pending in
                continuation = pending
            }
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .deviceLocked) }
            )
        }

        let runTask = Task { @MainActor in
            await manager.performPendingExport(requestId: request.id, source: .scheduled)
        }
        for _ in 0..<10 where continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(continuation, "pending run should suspend inside the runner")

        XCTAssertTrue(
            observedArmedCancels.contains(request.id),
            "the armed fallback timer is defused at run start"
        )
        XCTAssertFalse(
            notificationScheduler.canceledRequestIDs.contains(request.id),
            "a delivered copy must survive as the recovery surface"
        )

        continuation?.resume()
        await runTask.value

        XCTAssertNotNil(
            notificationScheduler.immediateRequests[request.id],
            "device-locked completion re-arms the stable-ID retry notification"
        )
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

        let preserved = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(preserved.id, request.id)
        XCTAssertEqual(preserved.dates, request.dates)
        XCTAssertNotNil(preserved.attemptedAt)
        let immediate = try XCTUnwrap(notificationScheduler.immediateRequests[request.id])
        XCTAssertEqual(immediate.id, request.id)
        XCTAssertEqual(immediate.dates, request.dates)
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

    func testAppActiveDrainOwnsActivityBannerInsteadOfBareAlert() async throws {
        let request = pendingRequest(
            id: "14141414-1414-1414-1414-141414141414",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let tracker = NotificationExportActivityTracker.shared
        tracker.clear()
        defer { tracker.clear() }
        var observedStart: NotificationExportActivityTracker.Snapshot?
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler
        ) { dates, _ in
            observedStart = tracker.snapshot
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: [
                    FailedDateDetail(date: dates[0], reason: .healthKitError)
                ]
            )
        }

        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        // A plain app-active drain (no notification tap involved) must still
        // begin the activity banner so a failed result surfaces in the banner
        // instead of an unexpected bare alert.
        XCTAssertEqual(observedStart?.operationID, request.id)
        XCTAssertEqual(observedStart?.source, .scheduled)
        XCTAssertEqual(tracker.snapshot?.phase, .failed)
        XCTAssertTrue(
            manager.notificationExportResult.map(tracker.handles) ?? false,
            "the banner must own the drain result so ContentView suppresses its alert"
        )
    }

    func testColdLaunchDrainOutrunsNotificationTapWithoutBareAlertOrDoubleRun() async throws {
        let request = pendingRequest(
            id: "15151515-1515-1515-1515-151515151515",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let tracker = NotificationExportActivityTracker.shared
        tracker.clear()
        defer { tracker.clear() }
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

        // Cold launch interleave: applicationDidBecomeActive's app-active
        // drain resumes before the notification tap response is delivered.
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
        XCTAssertEqual(
            tracker.snapshot?.operationID,
            request.id,
            "the drain must begin the activity banner even though the tap has not arrived"
        )

        // The notification tap handler runs while the drain still holds the
        // in-flight guards: it must no-op instead of double-running.
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
        XCTAssertEqual(tracker.snapshot?.phase, .completed)
        XCTAssertTrue(
            manager.notificationExportResult.map(tracker.handles) ?? false,
            "the banner must own the drain result so the tap does not surface a bare alert"
        )
    }

    func testCustomSilentPushWithoutFireDateIsRejected() async throws {
        let store = TestPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runs: [PendingExportRun] = []
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .day,
            customAnchorDate: date(year: 2026, month: 5, day: 17),
            preferredHour: 8,
            enabledAt: date(year: 2026, month: 5, day: 16, hour: 8)
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
                    failedDateDetails: [],
                    completedDates: dates
                )
            },
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 8, minute: 1) }
        )

        await manager.performSilentPushExport(fireDate: nil)

        XCTAssertTrue(runs.isEmpty)
        XCTAssertTrue(try store.loadAll().isEmpty)
        XCTAssertNil(manager.schedule.lastExportDate)
    }

    func testDelayedCustomSilentPushAdvancesLogicalOccurrenceMarker() async throws {
        let fireDate = date(year: 2026, month: 5, day: 17, hour: 8)
        let store = TestPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .day,
            customAnchorDate: fireDate,
            preferredHour: 8,
            enabledAt: date(year: 2026, month: 5, day: 16, hour: 8)
        )
        let manager = SchedulingManager(
            pendingExportStore: store,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: schedule,
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false,
            scheduledTargetExportRunner: { dates, _ in
                ExportOrchestrator.ExportResult(
                    successCount: dates.count,
                    totalCount: dates.count,
                    failedDateDetails: [],
                    completedDates: dates
                )
            },
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 8, minute: 1) }
        )

        await manager.performSilentPushExport(fireDate: fireDate)

        XCTAssertEqual(manager.schedule.lastExportDate, fireDate)
        XCTAssertTrue(try store.loadAll().isEmpty)
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
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
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
                    },
                    completedDates: Array(dates.prefix(7))
                )
            },
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 8, minute: 1) }
        )

        await manager.performSilentPushExport(fireDate: fireDate)

        let request = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(request.exportTarget, .apiEndpoint)
        XCTAssertEqual(request.dates.count, 3)
        XCTAssertEqual(request.dates, Array(ScheduleDateMath.scheduledExportDates(
            schedule: schedule,
            fireDate: fireDate
        ).suffix(3)))
        XCTAssertEqual(notificationScheduler.immediateRequests[request.id], request)
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
                    ],
                    completedDates: []
                )
            },
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 9, minute: 1) }
        )

        await manager.performSilentPushExport(fireDate: fireDate, kind: .todayRefresh)

        let request = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(request.scheduledKind, .todayRefresh)
        XCTAssertEqual(request.dates.count, 1)
        XCTAssertEqual(notificationScheduler.immediateRequests[request.id], request)
        XCTAssertNil(manager.schedule.lastTodayRefreshDate)
    }

    func testRecoveredConnectedMacCompletionConsumesQuotaOnceAndClearsPendingRequest() async throws {
        let exportDate = date(year: 2026, month: 5, day: 17)
        let request = pendingRequest(
            id: "14141414-1414-1414-1414-141414141414",
            dates: [exportDate],
            source: .scheduled,
            exportTarget: .connectedMac
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        var recordedQuotaJobIDs: [UUID] = []
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler,
            quotaRecorder: { jobID in
                if let jobID { recordedQuotaJobIDs.append(jobID) }
            }
        ) { dates, _ in
            XCTFail("Recovered completion should not rerun HealthKit export work")
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }
        let payload = MacExportResultPayload(
            jobID: request.id,
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            externalRecordFileCount: 0,
            dailyNoteUpdateCount: 0,
            dailyNoteSkipCount: 0,
            failedDateDetails: [],
            completedDates: [exportDate],
            destinationDisplayName: "Mac Vault",
            destinationPathForDisplay: nil,
            completedAt: date(year: 2026, month: 5, day: 18, hour: 9)
        )

        let handled = await manager.completeRecoveredScheduledMacExport(with: payload)

        XCTAssertTrue(handled)
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertEqual(recordedQuotaJobIDs, [request.id])
        XCTAssertEqual(manager.schedule.lastExportDate, request.scheduledFireDate)

        let replayHandled = await manager.completeRecoveredScheduledMacExport(with: payload)
        XCTAssertFalse(replayHandled)
        XCTAssertEqual(recordedQuotaJobIDs, [request.id])
    }

    func testScheduledExportDependencyWaitResumesAfterAppServicesAreConfigured() async {
        let store = TestPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        let manager = makeManager(
            store: store,
            notificationScheduler: notificationScheduler
        ) { dates, _ in
            ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: []
            )
        }
        var didResume = false

        let waitTask = Task { @MainActor in
            await manager.waitForScheduledExportDependencies()
            didResume = true
        }
        await Task.yield()

        XCTAssertFalse(didResume)

        let syncService = SyncService()
        manager.configureScheduledExportDependencies(
            syncService: syncService,
            externalIntegrations: nil
        )
        await waitTask.value

        XCTAssertTrue(didResume)
    }

    func testPendingConnectedMacExportWaitsForColdLaunchHandshakeThenResumes() async throws {
        let tracker = NotificationExportActivityTracker.shared
        tracker.clear()
        defer { tracker.clear() }
        let request = pendingRequest(
            id: "13131313-1313-1313-1313-131313131313",
            dates: [date(year: 2026, month: 5, day: 17)],
            source: .scheduled,
            exportTarget: .connectedMac
        )
        let store = TestPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            target: .connectedMac,
            enabledAt: date(year: 2026, month: 5, day: 17, hour: 8)
        )
        var runs: [PendingExportRun] = []
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
                    failedDateDetails: [],
                    completedDates: dates
                )
            },
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 9) }
        )
        let syncService = SyncService()
        manager.configureScheduledExportDependencies(
            syncService: syncService,
            externalIntegrations: nil
        )

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertTrue(runs.isEmpty)
        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertNil(manager.notificationExportResult)
        XCTAssertNil(tracker.snapshot)

        configureReadyConnectedMac(syncService)
        await manager.resumePendingConnectedMacExportsIfReady()

        XCTAssertEqual(runs, [
            PendingExportRun(dates: request.dates, source: .scheduled, target: .connectedMac)
        ])
        XCTAssertTrue(try store.loadAll().isEmpty)
        XCTAssertEqual(manager.notificationExportResult?.status, .success(daysExported: 1))
        XCTAssertEqual(tracker.snapshot?.operationID, request.id)
        XCTAssertEqual(tracker.snapshot?.targetLabel, "Mac Vault")
        XCTAssertEqual(tracker.snapshot?.phase, .completed)
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
            scheduledExportQuotaAccess: { _ in true },
            scheduledExportQuotaRecorder: { _ in },
            now: { self.date(year: 2026, month: 5, day: 18, hour: 9) }
        )
        let syncService = SyncService()
        configureReadyConnectedMac(syncService)
        manager.configureScheduledExportDependencies(
            syncService: syncService,
            externalIntegrations: nil
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
        quotaAccess: @MainActor @escaping (UUID?) -> Bool = { _ in true },
        quotaRecorder: @MainActor @escaping (UUID?) throws -> Void = { _ in },
        exportRunner: @MainActor @escaping ([Date], PendingExportSource) async -> ExportOrchestrator.ExportResult
    ) -> SchedulingManager {
        let resolvedSchedule = schedule ?? ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let resolvedNow = now ?? date(year: 2026, month: 5, day: 18, hour: 9)
        // Hermetic entry store: the test host container's standard defaults can
        // carry enabled scheduled entries from unrelated device testing, which
        // would flip `hasEnabledProfileEntries` and change disabled-schedule
        // semantics under test.
        let entrySuiteName = "SchedulingManagerPendingExportsTests.entries.\(UUID().uuidString)"
        let entryDefaults = UserDefaults(suiteName: entrySuiteName)
        entryDefaults?.removePersistentDomain(forName: entrySuiteName)
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
            scheduledExportQuotaAccess: quotaAccess,
            scheduledExportQuotaRecorder: quotaRecorder,
            now: { resolvedNow },
            scheduledEntryStore: ScheduledExportEntryStore(userDefaults: entryDefaults ?? .standard)
        )
    }

    private func configureReadyConnectedMac(_ syncService: SyncService) {
        syncService.connectionState = .connected
        syncService.remoteCapabilities = .current(platform: .macOS)
        syncService.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Mac Vault",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: .current(platform: .macOS)
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
