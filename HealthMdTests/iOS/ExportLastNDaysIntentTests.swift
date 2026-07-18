#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class ExportLastNDaysIntentTests: XCTestCase {
    func testExportDates_defaultEndsYesterdayAndExcludesToday() {
        let dates = ExportLastNDaysIntent.exportDates(
            days: ExportLastNDaysIntent.defaultDays,
            now: date(2026, 5, 11, hour: 15),
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.first, date(2026, 5, 4))
        XCTAssertEqual(dates.last, date(2026, 5, 10))
        XCTAssertFalse(dates.contains(date(2026, 5, 11)))
    }

    func testExportDates_clampsBelowRangeToOneDay() {
        let dates = ExportLastNDaysIntent.exportDates(
            days: 0,
            now: date(2026, 5, 11, hour: 15),
            calendar: calendar
        )

        XCTAssertEqual(dates, [date(2026, 5, 10)])
    }

    func testExportDates_allowsMultiYearCorpus() {
        let dates = ExportLastNDaysIntent.exportDates(
            days: 999,
            now: date(2026, 5, 11, hour: 15),
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 999)
        XCTAssertEqual(dates.first, date(2023, 8, 16))
        XCTAssertEqual(dates.last, date(2026, 5, 10))
    }

    func testInitClampsOnlyBelowOneForShortcutRuntime() {
        XCTAssertEqual(ExportLastNDaysIntent(days: -20).days, 1)
        XCTAssertEqual(ExportLastNDaysIntent(days: 500).days, 500)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}

@MainActor
final class ExportIntentRunnerTests: XCTestCase {
    func testLockedShortcutExportCreatesPendingRequestForExactDates() async throws {
        let requestedDates = [
            date(2026, 5, 12, hour: 13),
            date(2026, 5, 10, hour: 7)
        ]
        let harness = RunnerHarness(
            result: ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: requestedDates.count,
                failedDateDetails: requestedDates.map {
                    FailedDateDetail(date: $0, reason: .deviceLocked)
                }
            )
        )

        let outcome = await ExportIntentRunner.run(
            dates: requestedDates,
            dependencies: harness.dependencies
        )

        guard case .pending(let reason) = outcome else {
            return XCTFail("Expected pending outcome, got \(outcome)")
        }
        XCTAssertEqual(reason, ExportFailureReason.deviceLocked.shortDescription)

        let pendingRequests = try harness.pendingStore.loadAll()
        XCTAssertEqual(pendingRequests.count, 1)
        let request = try XCTUnwrap(pendingRequests.first)
        XCTAssertEqual(request.source, .shortcut)
        XCTAssertNil(request.scheduledFireDate)
        XCTAssertEqual(request.dates, [
            calendar.startOfDay(for: requestedDates[1]),
            calendar.startOfDay(for: requestedDates[0])
        ])
        XCTAssertEqual(harness.notificationScheduler.immediateRequests[request.id], request)
    }

    func testLockedShortcutExportReturnsPendingDialogCopy() {
        XCTAssertEqual(
            ExportIntentRunner.dialog(for: .pending(reason: "Device locked")),
            "Pending. Unlock your phone and tap the Health.md notification to export."
        )
    }

    func testLockedShortcutExportDoesNotConsumeQuotaOrUpdateSchedule() async {
        let yesterday = date(2026, 5, 17)
        let harness = RunnerHarness(
            result: ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 1,
                failedDateDetails: [FailedDateDetail(date: yesterday, reason: .deviceLocked)]
            ),
            now: date(2026, 5, 18, hour: 9)
        )

        _ = await ExportIntentRunner.run(dates: [yesterday], dependencies: harness.dependencies)

        XCTAssertEqual(harness.recordExportUseCount, 0)
        XCTAssertEqual(harness.trackExportSucceededCount, 0)
        XCTAssertEqual(harness.updateScheduleLastExportCount, 0)
        XCTAssertTrue(harness.recordedResults.isEmpty)
    }

    func testSuccessfulShortcutPathStillRecordsQuotaAnalyticsAndSchedule() async {
        let yesterday = date(2026, 5, 17)
        let harness = RunnerHarness(
            result: ExportOrchestrator.ExportResult(
                successCount: 1,
                totalCount: 1,
                failedDateDetails: [],
                formatsPerDate: 1
            ),
            now: date(2026, 5, 18, hour: 9)
        )

        let outcome = await ExportIntentRunner.run(dates: [yesterday], dependencies: harness.dependencies)

        guard case .success(let daysExported, let formatsPerDate) = outcome else {
            return XCTFail("Expected success outcome, got \(outcome)")
        }
        XCTAssertEqual(daysExported, 1)
        XCTAssertEqual(formatsPerDate, 1)
        XCTAssertEqual(harness.recordedResults.count, 1)
        XCTAssertEqual(harness.recordExportUseCount, 1)
        XCTAssertEqual(harness.trackExportSucceededCount, 1)
        XCTAssertEqual(harness.updateScheduleLastExportCount, 1)
        XCTAssertTrue((try? harness.pendingStore.loadAll().isEmpty) ?? false)
    }

    func testShortcutPendingNotificationRetriesStoredDatesWhenScheduleIsDisabled() async throws {
        let requestedDates = [
            date(2026, 5, 10, hour: 7),
            date(2026, 5, 12, hour: 13)
        ]
        let request = PendingExportRequest(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            dates: requestedDates,
            source: .shortcut,
            createdAt: date(2026, 5, 13, hour: 9),
            calendar: calendar
        )
        let pendingStore = SpyPendingExportStore(requests: [request])
        let notificationScheduler = InspectableExportNotificationScheduler()
        let timestamp = date(2026, 5, 18, hour: 10)
        var retriedDates: [Date] = []

        let manager = SchedulingManager(
            pendingExportStore: pendingStore,
            exportNotificationScheduler: notificationScheduler,
            initialSchedule: ExportSchedule(isEnabled: false, lookbackDays: 30),
            shortcutExportRunner: { dates in
                retriedDates = dates
                return .success(daysExported: dates.count, formatsPerDate: 1)
            },
            now: { timestamp }
        )

        await manager.performNotificationTriggeredExport(payload: PendingExportNotificationPayload(request: request))

        XCTAssertEqual(retriedDates, request.dates)
        XCTAssertEqual(try pendingStore.loadAll(), [])
        XCTAssertEqual(notificationScheduler.canceledRequestIDs, [request.id])
        XCTAssertEqual(manager.notificationExportResult?.status, .success(daysExported: request.dates.count))
        XCTAssertEqual(manager.notificationExportResult?.timestamp, timestamp)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    private final class RunnerHarness {
        let pendingStore = SpyPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        var recordedResults: [ExportOrchestrator.ExportResult] = []
        var recordExportUseCount = 0
        var trackExportSucceededCount = 0
        var updateScheduleLastExportCount = 0

        private let result: ExportOrchestrator.ExportResult
        private let now: Date

        init(result: ExportOrchestrator.ExportResult, now: Date = Date()) {
            self.result = result
            self.now = now
        }

        private var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar
        }

        var dependencies: ExportIntentRunner.Dependencies {
            ExportIntentRunner.Dependencies(
                refreshPurchaseStatus: {},
                canExport: { true },
                trackExportBlockedByQuota: {},
                hasVaultAccess: { true },
                refreshVaultAccess: {},
                startVaultAccess: {},
                stopVaultAccess: {},
                targetLabel: { "iPhone: TestVault" },
                makeSettings: { AdvancedExportSettings() },
                exportDatesBackground: { [result] _, _ in result },
                recordResult: { [weak self] result, _, _, _, _ in
                    self?.recordedResults.append(result)
                },
                recordExportUse: { [weak self] in
                    self?.recordExportUseCount += 1
                },
                trackExportSucceeded: { [weak self] _ in
                    self?.trackExportSucceededCount += 1
                },
                updateScheduleLastExport: { [weak self] in
                    self?.updateScheduleLastExportCount += 1
                },
                pendingExportStore: pendingStore,
                exportNotificationScheduler: notificationScheduler,
                now: { [now] in now },
                calendar: calendar
            )
        }
    }

    private final class SpyPendingExportStore: PendingExportStoring {
        private var requests: [PendingExportRequest]

        init(requests: [PendingExportRequest] = []) {
            self.requests = requests
        }

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
}
#endif
