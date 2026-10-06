import HealthKit
import XCTest
@testable import HealthMd

@MainActor
final class NativeExportDateRangeResolverTests: XCTestCase {
    private typealias Resolver = NativeExportDateRangeResolver
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let earliestDate = Date(timeIntervalSince1970: 1_500_000_000)
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    func testAllTimeUsesOnlySelectedMetricsAndNormalizesInExportTimeZone() async throws {
        let store = FakeHealthStore()
        let stepType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        let heartType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        store.earliestSampleDates[stepType.identifier] = earliestDate
        store.earliestSampleDates[heartType.identifier] = .distantPast
        store.authorizedHistoryBoundaries[heartType.identifier] = referenceDate
        store.errorsForEarliestSampleDates[heartType.identifier] = HealthKitFixtures.genericQueryError
        let request = makeRequest(timeZone: TimeZone(secondsFromGMT: -8 * 3_600)!)

        let range = try await resolve(request, store: store)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = request.timeZone
        XCTAssertEqual(range.startDate, calendar.startOfDay(for: earliestDate))
        XCTAssertEqual(range.endDate, calendar.startOfDay(for: referenceDate))
        XCTAssertEqual(store.queriedEarliestSampleTypeIdentifiers, [stepType.identifier])
        XCTAssertEqual(store.historyAuthorizationReadTypes, [stepType])
    }

    func testLimitedUnknownAndUnavailableHistoryRejectAllTime() async throws {
        for state in [HealthHistoryAuthorizationState.limitedHistory, .unknown, .apiUnavailable] {
            let store = FakeHealthStore()
            let stepType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
            store.earliestSampleDates[stepType.identifier] = earliestDate
            switch state {
            case .limitedHistory:
                store.authorizedHistoryBoundaries[stepType.identifier] = referenceDate
            case .unknown:
                store.errorForAuthorizedHistoryBoundaries = HealthKitFixtures.genericQueryError
            case .apiUnavailable:
                store.historyAuthorizationBoundariesSupported = false
            case .fullHistory:
                XCTFail("Not a rejection fixture")
            }

            do {
                _ = try await resolve(makeRequest(), store: store)
                XCTFail("All Time must reject \(state)")
            } catch {
                XCTAssertEqual(error as? Resolver.ResolutionError,
                               state == .limitedHistory ? .limitedHistory : .unverifiedHistory)
            }
        }
    }

    func testFullHistoryWithUnassessedMetricsStillRejectsAllTime() {
        let discovery = makeDiscovery(unassessedMetricIDs: ["medication_dose_events"])
        XCTAssertTrue(discovery.isComplete)
        XCTAssertFalse(discovery.supportsUnqualifiedFullHistoryClaim)
        assertRejected(discovery, as: .unverifiedHistory)
    }

    func testPartialEarliestDiscoveryCannotExportTheSuccessfulSiblingRange() async throws {
        let store = FakeHealthStore()
        let stepType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        let heartType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        store.earliestSampleDates[stepType.identifier] = earliestDate
        store.errorsForEarliestSampleDates[heartType.identifier] = HealthKitFixtures.genericQueryError

        do {
            _ = try await resolve(makeRequest(metricIDs: ["steps", "heart_rate"]), store: store)
            XCTFail("A best-effort earliest date must not qualify All Time")
        } catch {
            XCTAssertEqual(error as? Resolver.ResolutionError, .incompleteDiscovery)
        }
    }

    func testUnknownSelectedMetricRejectsOtherwiseCompleteDiscovery() async throws {
        let store = FakeHealthStore()
        let stepType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        store.earliestSampleDates[stepType.identifier] = earliestDate

        do {
            _ = try await resolve(makeRequest(metricIDs: ["steps", "future_metric"]), store: store)
            XCTFail("Every selected metric must be discoverable")
        } catch {
            XCTAssertEqual(error as? Resolver.ResolutionError, .incompleteDiscovery)
        }
    }

    func testEmptyReadableStoreDoesNotFallBackToTodayAsAllTime() async {
        do {
            _ = try await resolve(makeRequest(), store: FakeHealthStore())
            XCTFail("No readable history is not a resolved All Time range")
        } catch {
            XCTAssertEqual(error as? Resolver.ResolutionError, .noHealthData)
        }
    }

    func testIncompleteAndFutureDatedDiscoveriesRejectAllTime() {
        assertRejected(makeDiscovery(failedTypeIdentifiers: ["synthetic.type"]), as: .incompleteDiscovery)
        assertRejected(makeDiscovery(unresolvedMetricIDs: ["future_metric"]), as: .incompleteDiscovery)
        assertRejected(makeDiscovery(earliestDate: referenceDate.addingTimeInterval(86_400)), as: .incompleteDiscovery)
    }

    func testExplicitRangesRemainUnchangedWithoutHistoryOrDiscoveryChecks() async throws {
        for preset in [ExportDateRangePreset.today, .yesterday, .custom] {
            let store = FakeHealthStore()
            store.historyAuthorizationBoundariesSupported = false
            store.errorForAuthorizedHistoryBoundaries = HealthKitFixtures.genericQueryError
            let request = makeRequest(preset: preset)

            let range = try await resolve(request, store: store)

            XCTAssertEqual(range, ExportDateRange(
                startDate: request.selection.startDate,
                endDate: request.selection.endDate
            ))
            XCTAssertTrue(store.queriedEarliestSampleTypeIdentifiers.isEmpty)
            XCTAssertTrue(store.historyAuthorizationReadTypes.isEmpty)
        }
    }

    func testMetricPresetDateAndTimeZoneChangesWhileDiscoveringRejectStaleResult() async throws {
        let original = makeRequest()
        let changedRequests = [
            makeRequest(metricIDs: ["heart_rate"]),
            makeRequest(preset: .custom),
            Resolver.Request(
                selection: ExportDateRangeSelection(
                    preset: .allTime,
                    startDate: earliestDate,
                    endDate: referenceDate
                ),
                enabledMetricIDs: original.enabledMetricIDs,
                timeZone: timeZone
            ),
            makeRequest(timeZone: TimeZone(secondsFromGMT: 3_600)!)
        ]
        for changed in changedRequests {
            var current = original
            let store = FakeHealthStore()
            store.earliestSampleDateQuery = { _ in
                await Task.yield()
                current = changed
                return self.earliestDate
            }
            let manager = makeManager(store)

            do {
                _ = try await Resolver.resolve(
                    original,
                    using: manager,
                    currentRequest: { current },
                    referenceDate: referenceDate
                )
                XCTFail("A result for a changed request must not authorize an export")
            } catch {
                XCTAssertEqual(error as? Resolver.ResolutionError, .selectionChanged)
            }
        }
    }

    func testEveryAdmissionRechecksAuthorizationEvenForSavedAllTimeDates() async throws {
        let store = FakeHealthStore()
        let stepType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        store.earliestSampleDates[stepType.identifier] = earliestDate
        let manager = makeManager(store)
        let request = makeRequest()
        let range = try await Resolver.resolve(request, using: manager, currentRequest: { request },
                                               referenceDate: referenceDate)
        let restored = Resolver.Request(
            selection: ExportDateRangeSelection(preset: .allTime, startDate: range.startDate, endDate: range.endDate),
            enabledMetricIDs: request.enabledMetricIDs,
            timeZone: request.timeZone
        )
        store.authorizedHistoryBoundaries[stepType.identifier] = referenceDate

        do {
            _ = try await Resolver.resolve(restored, using: manager, currentRequest: { restored },
                                           referenceDate: referenceDate)
            XCTFail("Persisted dates must not bypass current history authorization")
        } catch {
            XCTAssertEqual(error as? Resolver.ResolutionError, .limitedHistory)
        }
        XCTAssertEqual(store.queriedEarliestSampleTypeIdentifiers.count, 2)
    }

    func testCancellationDuringDiscoveryCannotAdmitAnExport() async {
        let store = FakeHealthStore()
        store.earliestSampleDateQuery = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return self.earliestDate
        }
        let manager = makeManager(store)
        let request = makeRequest()
        let task = Task {
            try await Resolver.resolve(request, using: manager, currentRequest: { request },
                                       referenceDate: referenceDate)
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled resolution must not authorize an export")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func makeRequest(
        preset: ExportDateRangePreset = .allTime,
        metricIDs: Set<String> = ["steps"],
        timeZone: TimeZone? = nil
    ) -> Resolver.Request {
        Resolver.Request(
            selection: ExportDateRangeSelection(preset: preset, startDate: referenceDate, endDate: referenceDate),
            enabledMetricIDs: metricIDs,
            timeZone: timeZone ?? self.timeZone
        )
    }

    private func makeManager(_ store: FakeHealthStore) -> HealthKitManager {
        let suite = "NativeExportDateRangeResolverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return HealthKitManager(store: store, userDefaults: defaults)
    }

    private func resolve(_ request: Resolver.Request, store: FakeHealthStore) async throws -> ExportDateRange {
        try await Resolver.resolve(request, using: makeManager(store), currentRequest: { request },
                                   referenceDate: referenceDate)
    }

    private func makeDiscovery(
        earliestDate: Date? = nil,
        failedTypeIdentifiers: [String] = [],
        unresolvedMetricIDs: [String] = [],
        unassessedMetricIDs: [String] = []
    ) -> HealthKitEarliestDataDiscovery {
        HealthKitEarliestDataDiscovery(
            earliestDate: earliestDate ?? self.earliestDate,
            queriedTypeIdentifiers: ["synthetic.type"],
            snapshotOnlyTypeIdentifiers: [],
            failedTypeIdentifiers: failedTypeIdentifiers,
            unresolvedMetricIDs: unresolvedMetricIDs,
            historyAuthorization: HealthHistoryAuthorizationAssessment(
                state: .fullHistory,
                unassessedMetricIDs: unassessedMetricIDs,
                message: "Synthetic history assessment"
            )
        )
    }

    private func assertRejected(_ discovery: HealthKitEarliestDataDiscovery,
                                as expected: Resolver.ResolutionError,
                                file: StaticString = #filePath, line: UInt = #line) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        XCTAssertThrowsError(try Resolver.allTimeRange(from: discovery, referenceDate: referenceDate,
                                                      calendar: calendar), file: file, line: line) { error in
            XCTAssertEqual(error as? Resolver.ResolutionError, expected, file: file, line: line)
        }
    }
}
