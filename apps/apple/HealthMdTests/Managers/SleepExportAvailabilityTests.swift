import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class SleepExportAvailabilityTests: XCTestCase {
    func testActualFetchUsesOneNightContextAcrossPreferenceMutationAndConcurrentOperation() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let night = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
        let wake = calendar.date(byAdding: .day, value: 1, to: night)!
        let start = calendar.date(bySettingHour: 23, minute: 45, second: 0, of: night)!
        let end = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: wake)!
        let store = FakeHealthStore()
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, startDate: start, endDate: end)
        ]
        let defaults = UserDefaults(suiteName: "SleepExportAvailabilityTests.\(UUID())")!
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.enabledMetrics = ["sleep_total", "sleep_bedtime", "sleep_wake", "sleep_core"]
        let context = AppleSleepCaptureContext.resolve(timeZone: calendar.timeZone, attribution: manager.sleepDayAttribution)
        try await AppleSleepCaptureContext.pinned.withValue(context) {
            let first = try await manager.fetchHealthData(for: night, detailPolicy: .summary, metricSelection: selection)
            manager.setSleepDayAttribution(.morningEnds)
            await Task.yield()
            let second = try await manager.fetchHealthData(for: wake, detailPolicy: .summary, metricSelection: selection)
            XCTAssertEqual(first.sleep.totalDuration + second.sleep.totalDuration, 465 * 60, accuracy: 0.001)
            XCTAssertEqual(first.sleep.sessionStart, start)
            XCTAssertNil(second.sleep.sessionStart)
            XCTAssertEqual(first.timeContext.calendarTimeZoneIdentifier, context.calendarTimeZoneIdentifier)
            XCTAssertEqual(second.timeContext, first.timeContext)

            // An independent concurrent operation must see its OWN morning
            // context and reject it, not borrow this task's available night pin.
            let other = Task.detached { @MainActor in
                do {
                    _ = try await manager.fetchHealthData(for: wake, detailPolicy: .summary, metricSelection: selection)
                    XCTFail("Concurrent new work must not inherit another operation's pin")
                } catch {
                    XCTAssertEqual(error as? AppleSleepCaptureContext.AvailabilityError, .unapprovedAttribution)
                }
            }
            await other.value
        }
        // Reverse mutation: a persisted unavailable context must remain
        // unavailable even when the current preference becomes night-begins.
        let saved = AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .morningEnds)
        manager.setSleepDayAttribution(.nightBegins)
        do {
            _ = try await manager.fetchHealthData(for: wake, detailPolicy: .summary, metricSelection: selection, captureContext: saved)
            XCTFail("Do not coerce persisted ownership")
        } catch {
            XCTAssertEqual(error as? AppleSleepCaptureContext.AvailabilityError, .unapprovedAttribution)
        }
    }

    func testPendingStorePreservesStandaloneCaptureAuthorityAndMissingLegacyJobsWithoutCoercion() throws {
        let changes: [(SleepDayAttribution?, SleepDayAttribution)] = [(.nightBegins, .morningEnds), (.morningEnds, .nightBegins), (nil, .nightBegins)]
        for (saved, current) in changes {
            let defaults = UserDefaults(suiteName: "PendingSleepContextTests.\(UUID())")!
            let context = saved.map { AppleSleepCaptureContext(timeZone: TimeZone(identifier: "UTC")!, sleepDayAttribution: $0) }
            let request = PendingExportRequest(dates: [Date()], source: .shortcut, sleepCaptureContext: context)
            try PendingExportStore(userDefaults: defaults).upsert(request)
            let original = defaults.data(forKey: PendingExportStore.storageKey)
            let healthManager = HealthKitManager(store: FakeHealthStore(), userDefaults: defaults)
            healthManager.setSleepDayAttribution(current)
            let recovered = try XCTUnwrap(PendingExportStore(userDefaults: defaults).loadAll().first)
            if saved == .nightBegins {
                XCTAssertEqual(try recovered.recoveredSleepCaptureContext(), context)
            } else {
                XCTAssertThrowsError(try recovered.recoveredSleepCaptureContext())
            }
            XCTAssertEqual(recovered.replacingResidualDates(recovered.dates, attemptedAt: Date()).sleepCaptureContext, context)
            XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), original)
            XCTAssertEqual(healthManager.sleepDayAttribution, current)
        }
    }

    func testWireSnapshotKeepsHistoricalBytesWhileOnlyJournalEncodingRetainsSleepAuthority() throws {
        let settings = AdvancedExportSettings(userDefaults: UserDefaults(suiteName: "SleepWireSnapshotTests.\(UUID())")!)
        var snapshot = ExportSettingsSnapshot.from(settings)
        let wire = JSONEncoder()
        wire.outputFormatting = [.sortedKeys]
        let historicalBytes = try wire.encode(snapshot)
        snapshot.sleepCaptureContext = AppleSleepCaptureContext(timeZone: TimeZone(identifier: "UTC")!, sleepDayAttribution: .nightBegins)
        XCTAssertEqual(try wire.encode(snapshot), historicalBytes)
        snapshot.sleepCaptureContext = AppleSleepCaptureContext(timeZone: TimeZone(identifier: "UTC")!, sleepDayAttribution: .morningEnds)
        XCTAssertEqual(try wire.encode(snapshot), historicalBytes, "No portable/wire adoption of an unapproved context")
        wire.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        let saved = try wire.encode(snapshot)
        let recovered = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: saved)
        XCTAssertEqual(recovered.sleepCaptureContext, snapshot.sleepCaptureContext)
        XCTAssertThrowsError(try recovered.sleepCaptureContext?.requireShippedProfile())
    }

    func testSnapshotRecoveryKeepsOriginalAuthorityAndRefusesMissingAuthorityWithoutWrites() throws {
        let settings = AdvancedExportSettings(userDefaults: UserDefaults(suiteName: "SleepSnapshotTests.\(UUID())")!)
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: TimeZone(identifier: "America/Los_Angeles")!, sleepDayAttribution: .morningEnds)
        let snapshot = ExportSettingsSnapshot.from(settings)
        let encoder = JSONEncoder()
        encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(snapshot)
        let restored = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: bytes)
        XCTAssertEqual(try encoder.encode(restored), bytes)
        let manager = HealthKitManager(store: FakeHealthStore(), userDefaults: UserDefaults(suiteName: "SleepRecoveryTests.\(UUID())")!)
        manager.setSleepDayAttribution(.nightBegins)
        XCTAssertThrowsError(try manager.resolveSleepCaptureContext(settings: restored.makeAdvancedExportSettings())) {
            XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .unapprovedAttribution)
        }
        var legacy = restored
        legacy.sleepCaptureContext = nil
        let legacyBytes = try encoder.encode(legacy)
        let recoveredLegacy = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: legacyBytes)
        XCTAssertNil(recoveredLegacy.sleepCaptureContext)
        XCTAssertThrowsError(try manager.resolveSleepCaptureContext(settings: recoveredLegacy.makeAdvancedExportSettings())) {
            XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .missingDurableAttribution)
        }
        XCTAssertEqual(try encoder.encode(recoveredLegacy), legacyBytes)
    }
}

extension HealthKitManager {
    /// Preserve the original proposed-mode arithmetic assertions at the real
    /// native sleep projection seam. This test-only value is never rendered or
    /// written; the full daily capture now fails closed for unapproved profiles.
    func fetchUnapprovedSleepProjection(for date: Date, detailPolicy: AppleExportDetailPolicy = .summary,
        includeGranularData: Bool = false, metricSelection: MetricSelectionState? = nil,
        timeZone: TimeZone? = nil) async throws -> HealthData {
        let zone = timeZone ?? .current
        let attribution = sleepDayAttribution
        let sleep = try await fetchSleepProjection(for: date, attribution: attribution, timeZone: zone,
            includeDetailedTimeSeries: includeGranularData || detailPolicy.includesSelectedTimeSeries)
        return HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: attribution), sleep: sleep)
    }
}
