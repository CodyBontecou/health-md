import Foundation
import XCTest
#if os(iOS)
import HealthMdConnectionCore
#endif
@testable import HealthMd

nonisolated enum HistoryQueryFixtures {
    static let peer = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let source = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let cursorKey = Data("history-query-test-key".utf8)

    static func request(operation: HealthMdQueryOperation = .metricSeries, maxItems: Int = 1,
                        maxBytes: Int = 1_048_576, cursor: String? = nil, metricIDs: [String] = ["steps"]) -> HealthMdQueryRequest {
        .init(metrics: .explicit(metricIDs), dates: .allAvailable, operation: operation,
              page: .init(maxItems: maxItems, maxBytes: maxBytes, cursor: cursor))
    }

    static func snapshot(query: HealthMdQueryRequest? = nil, timeZone: TimeZone? = nil,
                         empty: Bool = false, assessmentID: UUID = UUID(), captureID: UUID = UUID(),
                         access: HealthHistoryAccess = .unknown, peer: UUID = HistoryQueryFixtures.peer,
                         ownerCount: Int = 2) throws -> HealthHistoryQueryCapture {
        let query = query ?? request()
        let timeZone = timeZone ?? TimeZone(identifier: "America/Los_Angeles")!
        let metricIDs: Set<String>
        switch query.metrics {
        case .explicit(let ids): metricIDs = Set(ids)
        case .allAvailable: metricIDs = ["steps", "sleep_total", "workouts"]
        }
        let owners = Array(["2026-01-01", "2026-01-02", "2026-01-03"].prefix(ownerCount))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = owners.map { owner -> HealthMdCompactContextDay in
            let start = formatter.date(from: owner)!
            return .init(ownerDate: owner, intervalStart: start,
                intervalEnd: calendar.date(byAdding: .day, value: 1, to: start)!,
                calendarTimeZone: timeZone.identifier,
                source: .init(schema: "healthmd.health_data", schemaVersion: 7, digest: "fixture-\(owner)"),
                status: empty ? .completeEmpty : .available,
                metrics: empty ? [] : [.init(observationID: "steps:\(owner)", metricID: "steps", displayName: "Steps", value: .count(1), status: .available)])
        }
        let allAvailable: Bool
        let start: Date
        let end: Date
        switch query.dates {
        case .allAvailable: allAvailable = true; start = .distantPast; end = .distantFuture
        case .exact(let range): allAvailable = false; start = formatter.date(from: range.startDate)!; end = formatter.date(from: range.endDate)!
        }
        let scope = HealthHistoryScope(metricIDs: metricIDs, startDate: start, endDate: end,
            timeZoneIdentifier: timeZone.identifier, allAvailable: allAvailable, profileID: nil, rangeSemantics: .ownerDates)
        let assessment = HealthHistoryAssessment(id: assessmentID, assessedAt: Date(timeIntervalSince1970: 1_800_000_000.1234567),
            scope: scope, types: metricIDs.sorted().map { metricID in
                .init(id: metricID == "steps" ? "HKQuantityTypeIdentifierStepCount" : "metric:\(metricID)", directMetricIDs: [metricID], dependencyMetricIDs: [], dependencyReasons: [], access: metricID == "steps" ? access : .unassessed(reason: "synthetic_ineligible_type"))
            },
            evidenceSource: "synthetic_ui_fixture")
        return try HealthHistoryQueryCapture(days: days, metricIDs: metricIDs, query: query, assessment: assessment,
            timeZone: timeZone, ownerDates: owners, peerInstallationID: peer, sourceInstallationID: source,
            captureID: captureID, capturedAt: Date(timeIntervalSince1970: 1_800_000_001.7654321))
    }
}

final class HealthHistoryQueryCaptureTests: XCTestCase {
    func testReceiptPreservesExactBoundaryAndCaptureBytesWithoutFullHistoryState() throws {
        let boundary = Date(timeIntervalSince1970: 1_700_000_000.1234567)
        let snapshot = try HistoryQueryFixtures.snapshot(access: .limited(sampleEndBoundary: boundary))
        let encoded = try HealthMdQueryCanonicalSerializer.data(for: snapshot.receipt)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let rows = try XCTUnwrap(object["types"] as? [[String: Any]])
        let instant = try XCTUnwrap(rows.first?["sample_end_boundary"] as? String)
        let canonical = try JSONDecoder().decode(String.self, from: HealthMdQueryCanonicalSerializer.data(for: boundary))
        XCTAssertEqual(instant, canonical)
        XCTAssertEqual(object["boundary_semantics"] as? String, "sample_end_instant")
        XCTAssertEqual(object["calendar_identifier"] as? String, "gregorian")
        XCTAssertEqual(object["time_zone_identifier"] as? String, "America/Los_Angeles")
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("full_history"))
        XCTAssertEqual(snapshot.datasetDigest, try HealthMdQueryCanonicalSerializer.sha256(of: snapshot.days))
        XCTAssertEqual(snapshot.days.map(\.ownerDate), ["2026-01-01", "2026-01-02"])
    }

    func testEveryOperationEmptyAndPacketKeepsReceiptSeparateFromCoverageAndPacketMetadata() throws {
        let operations: [HealthMdQueryOperation] = [
            .metricSeries, .coverage, .workoutListing, .sourceRecordListing,
            .sleepSessionListing(window: nil, includeNaps: true),
            .workoutSleepAlignment(window: .init(durationSeconds: 3_600), workoutActivity: nil, includeNaps: true),
            .periodComparison(first: .init(startDate: "2026-01-01", endDate: "2026-01-01"),
                second: .init(startDate: "2026-01-02", endDate: "2026-01-02"), aggregations: [.init(metricID: "steps", kind: .count)]),
            .derivePacket(kind: .doctorVisit, detailIDs: [])
        ]
        for empty in [false, true] {
            for operation in operations {
                let query = HistoryQueryFixtures.request(operation: operation, maxItems: 100, metricIDs: ["steps", "sleep_total", "workouts"])
                let snapshot = try HistoryQueryFixtures.snapshot(query: query, empty: empty)
                let scope = HealthMdEvidenceScope(allowedMetricIDs: snapshot.metricIDs, allowsWorkouts: true, allowsEvidenceValues: true)
                let evaluator = try HealthMdQueryEvaluator(days: snapshot.days, cursorKey: HistoryQueryFixtures.cursorKey, cursorBinding: snapshot.cursorBinding)
                let generatedAt = Date(timeIntervalSince1970: 1)
                let original = try evaluator.evaluateBounded(query, evidenceScope: scope, generatedAt: generatedAt)
                let response = try evaluator.evaluateBounded(query, evidenceScope: scope, generatedAt: generatedAt,
                    responseMetadata: snapshot.metadata, responseLimitations: snapshot.limitations)
                XCTAssertEqual(response.metadata?["history_assessment"], snapshot.receipt)
                XCTAssertEqual(response.coverage, original.coverage)
                XCTAssertEqual(response.items, original.items)
                XCTAssertEqual(response.packet?.metadata, original.packet?.metadata)
                if let packet = response.packet {
                    let packetMetadata = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(packet.metadata)) as? [String: Any])
                    XCTAssertNil(packetMetadata["history_assessment"])
                    XCTAssertEqual(Set(packetMetadata.keys), ["generated_at", "producer"])
                }
                for (key, value) in original.metadata ?? [:] { XCTAssertEqual(response.metadata?[key], value) }
                XCTAssertTrue(response.limitations.contains { $0.code == "history_assessment_observation" })
            }
        }
    }

    func testSameDaysDifferentReceiptCaptureOrPeerRejectsOldCursor() throws {
        let query = HistoryQueryFixtures.request()
        let first = try HistoryQueryFixtures.snapshot(query: query)
        let firstEvaluator = try HealthMdQueryEvaluator(days: first.days, cursorKey: HistoryQueryFixtures.cursorKey, cursorBinding: first.cursorBinding)
        let cursor = try XCTUnwrap(firstEvaluator.evaluateBounded(query, responseMetadata: first.metadata).nextCursor)
        let continued = HistoryQueryFixtures.request(cursor: cursor)
        XCTAssertEqual(try firstEvaluator.evaluateBounded(continued).items.count, 1)
        let replacements = [
            try HistoryQueryFixtures.snapshot(captureID: first.captureID, access: .apiUnavailable),
            try HistoryQueryFixtures.snapshot(assessmentID: first.captureID),
            try HistoryQueryFixtures.snapshot(peer: UUID())
        ]
        for replacement in replacements {
            XCTAssertEqual(replacement.datasetDigest, first.datasetDigest)
            XCTAssertNotEqual(replacement.cursorBinding, first.cursorBinding)
            let evaluator = try HealthMdQueryEvaluator(days: replacement.days, cursorKey: HistoryQueryFixtures.cursorKey, cursorBinding: replacement.cursorBinding)
            XCTAssertThrowsError(try evaluator.evaluateBounded(continued)) { error in
                XCTAssertEqual(error as? HealthMdQueryContractError, .cursorDoesNotMatchQuery)
            }
        }
    }

    func testReceiptIsIncludedBeforeByteFitAndOversizeNeverMakesZeroProgressCursor() throws {
        // Both one/two-item candidates must retain a next cursor. A terminal
        // two-day page can be SMALLER than a one-day page plus its signed cursor;
        // that initial fixture did not actually force item fitting.
        let snapshot = try HistoryQueryFixtures.snapshot(ownerCount: 3)
        let evaluator = try HealthMdQueryEvaluator(days: snapshot.days, cursorKey: HistoryQueryFixtures.cursorKey, cursorBinding: snapshot.cursorBinding)
        let one = try evaluator.evaluateBounded(HistoryQueryFixtures.request(), responseMetadata: snapshot.metadata, responseLimitations: snapshot.limitations)
        let limit = try HealthMdQueryCanonicalSerializer.data(for: one).count + 8
        let bounded = try evaluator.evaluateBounded(HistoryQueryFixtures.request(maxItems: 2, maxBytes: limit),
            responseMetadata: snapshot.metadata, responseLimitations: snapshot.limitations)
        XCTAssertEqual(bounded.items.count, 1)
        XCTAssertNotNil(bounded.nextCursor)
        XCTAssertEqual(bounded.metadata?["history_assessment"], snapshot.receipt)
        XCTAssertLessThanOrEqual(try HealthMdQueryCanonicalSerializer.data(for: bounded).count, limit)
        for operation in [HealthMdQueryOperation.metricSeries, .coverage, .derivePacket(kind: .doctorVisit, detailIDs: [])] {
            XCTAssertThrowsError(try evaluator.evaluateBounded(HistoryQueryFixtures.request(operation: operation, maxBytes: 128),
                evidenceScope: .init(allowedMetricIDs: ["steps"]), responseMetadata: snapshot.metadata, responseLimitations: snapshot.limitations)) { error in
                XCTAssertEqual(error as? HealthMdQueryContractError, .singleItemExceedsPageBytes)
            }
        }
    }

    func testConstructorRejectsCalendarOwnerPlanScopeAndUnboundedRowsWithoutTruncation() throws {
        let fixture = try HistoryQueryFixtures.snapshot()
        let scope = HealthHistoryScope(metricIDs: ["steps"], startDate: .distantPast, endDate: .distantFuture,
            timeZoneIdentifier: fixture.timeZoneIdentifier, allAvailable: true, profileID: nil, rangeSemantics: .ownerDates)
        let row = HealthHistoryTypeAssessment(id: "HKQuantityTypeIdentifierStepCount", directMetricIDs: ["steps"], dependencyMetricIDs: [], dependencyReasons: [], access: .unknown)
        func make(_ scope: HealthHistoryScope, rows: [HealthHistoryTypeAssessment] = [row], owners: [String] = ["2026-01-01", "2026-01-02"]) throws -> HealthHistoryQueryCapture {
            let assessment = HealthHistoryAssessment(id: UUID(), assessedAt: Date(), scope: scope, types: rows)
            return try HealthHistoryQueryCapture(days: fixture.days, metricIDs: ["steps"], query: HistoryQueryFixtures.request(), assessment: assessment,
                timeZone: TimeZone(identifier: fixture.timeZoneIdentifier)!, ownerDates: owners,
                peerInstallationID: HistoryQueryFixtures.peer, sourceInstallationID: HistoryQueryFixtures.source)
        }
        XCTAssertThrowsError(try make(scope, owners: ["2026-01-01"]))
        let wrongCalendar = HealthHistoryScope(metricIDs: ["steps"], startDate: .distantPast, endDate: .distantFuture,
            timeZoneIdentifier: "Pacific/Apia", allAvailable: true, profileID: nil, rangeSemantics: .ownerDates)
        XCTAssertThrowsError(try make(wrongCalendar))
        XCTAssertThrowsError(try make(scope, rows: []))
        XCTAssertThrowsError(try make(scope, rows: Array(repeating: row, count: 513))) { error in
            XCTAssertEqual(error as? HealthMdQueryContractError, .singleItemExceedsPageBytes)
        }
    }

    func testConstructorRejectsProviderOnlyMismatchedLogicalDatesAndOwnerPlan() throws {
        let snapshot = try HistoryQueryFixtures.snapshot()
        let wrongDates = HealthMdQueryRequest(metrics: .explicit(["steps"]), dates: .exact(.init(startDate: "2026-01-01", endDate: "2026-01-01")), operation: .metricSeries)
        XCTAssertThrowsError(try HistoryQueryFixtures.snapshot(query: wrongDates))
        let providerOnly = HealthMdQueryRequest(metrics: .explicit(["steps"]), sources: .explicit(sourceIDs: ["provider_native"], providerIDs: ["whoop"]), dates: .allAvailable, operation: .metricSeries)
        XCTAssertThrowsError(try HistoryQueryFixtures.snapshot(query: providerOnly))
        XCTAssertEqual(snapshot.logicalDates, .allAvailable)
        let exact = HealthMdQueryRequest(metrics: .explicit(["steps"]), dates: .exact(.init(startDate: "2026-01-01", endDate: "2026-01-02")), operation: .metricSeries)
        XCTAssertNoThrow(try HistoryQueryFixtures.snapshot(query: exact))
    }
}

#if os(iOS)
@MainActor
final class IPhoneHistoryQueryCoordinatorTests: XCTestCase {
    func testProductionCaptureContinuationReconnectFreezesReceiptTimeZoneWithoutReassessment() async throws {
        let cache = IPhoneDirectQueryCaptureCache()
        let coordinator = IPhoneDirectQueryCoordinator(captureCache: cache)
        let query = HistoryQueryFixtures.request()
        let key = try coordinator.captureKey(for: query, detailLevel: .summary, peerInstallationID: HistoryQueryFixtures.peer)
        var captures = 0
        var currentTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let firstLease = coordinator.beginRequestLease()
        let initial = try await coordinator.snapshotForQuery(query, key: key, lease: firstLease) {
            captures += 1
            return try HistoryQueryFixtures.snapshot(timeZone: currentTimeZone)
        }
        let first = try coordinator.responseForQuery(query, snapshot: initial, key: key, cursorKey: HistoryQueryFixtures.cursorKey, lease: firstLease)
        currentTimeZone = TimeZone(identifier: "Pacific/Apia")!
        let page2 = HistoryQueryFixtures.request(cursor: try XCTUnwrap(first.nextCursor))
        let reconnectKey = try coordinator.captureKey(for: page2, detailLevel: .summary, peerInstallationID: HistoryQueryFixtures.peer)
        XCTAssertEqual(reconnectKey, key)
        let reconnectLease = coordinator.beginRequestLease()
        let continued = try await coordinator.snapshotForQuery(page2, key: reconnectKey, lease: reconnectLease) {
            captures += 1
            return try HistoryQueryFixtures.snapshot(timeZone: currentTimeZone)
        }
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(continued.captureID, initial.captureID)
        XCTAssertEqual(continued.receipt, initial.receipt)
        XCTAssertEqual(continued.timeZoneIdentifier, "America/Los_Angeles")
        let last = try coordinator.responseForQuery(page2, snapshot: continued, key: key, cursorKey: HistoryQueryFixtures.cursorKey, lease: reconnectLease)
        XCTAssertEqual(last.metadata?["history_assessment"], first.metadata?["history_assessment"])
        XCTAssertTrue(cache.isEmpty)
        do {
            _ = try await coordinator.snapshotForQuery(page2, key: key, lease: reconnectLease) { captures += 1; return initial }
            XCTFail("Terminal snapshot must not be recaptured")
        } catch { XCTAssertEqual(captures, 1) }
    }

    func testProductionCacheBackgroundExpiryWrongPeerAndSelectionFailWithoutRecapture() async throws {
        let cache = IPhoneDirectQueryCaptureCache(lifetime: 0.02)
        let coordinator = IPhoneDirectQueryCoordinator(captureCache: cache)
        let initial = try HistoryQueryFixtures.snapshot()
        let first = HistoryQueryFixtures.request()
        let key = try coordinator.captureKey(for: first, detailLevel: .summary, peerInstallationID: HistoryQueryFixtures.peer)
        let continued = HistoryQueryFixtures.request(cursor: "opaque")
        for mode in ["wrong_peer", "selection", "detail", "background", "expiry"] {
            cache.store(key: key, snapshot: initial)
            var lookup = key
            switch mode {
            case "wrong_peer": lookup = try coordinator.captureKey(for: first, detailLevel: .summary, peerInstallationID: UUID())
            case "selection":
                let changed = HealthMdQueryRequest(metrics: .explicit(["sleep_total"]), dates: .allAvailable, operation: .metricSeries)
                lookup = try coordinator.captureKey(for: changed, detailLevel: .summary, peerInstallationID: HistoryQueryFixtures.peer)
            case "detail": lookup = try coordinator.captureKey(for: first, detailLevel: .lossless, peerInstallationID: HistoryQueryFixtures.peer)
            case "background": coordinator.clearCachedContext()
            default: try await Task.sleep(nanoseconds: 200_000_000)
            }
            do {
                _ = try await coordinator.snapshotForQuery(continued, key: lookup, lease: coordinator.beginRequestLease()) { XCTFail("Must not reassess/recapture"); return initial }
                XCTFail("Unavailable/mismatched snapshot must fail closed")
            } catch {}
        }
        XCTAssertTrue(cache.isEmpty)
    }

    func testSuspendedClearResumeCannotResurrectCacheAndObsoleteCleanupCannotEvictNewLease() async throws {
        let cache = IPhoneDirectQueryCaptureCache()
        let coordinator = IPhoneDirectQueryCoordinator(captureCache: cache)
        let query = HistoryQueryFixtures.request()
        let key = try coordinator.captureKey(for: query, detailLevel: .summary, peerInstallationID: HistoryQueryFixtures.peer)
        let staleSnapshot = try HistoryQueryFixtures.snapshot()
        let oldLease = coordinator.beginRequestLease()
        let entered = expectation(description: "capture suspended")
        let rejected = expectation(description: "obsolete capture rejected")
        let gate = HistoryTestSuspension(entered: entered)
        let task = Task { @MainActor in
            do {
                _ = try await coordinator.snapshotForQuery(query, key: key, lease: oldLease) {
                    await gate.wait()
                    return staleSnapshot
                }
                XCTFail("Lifecycle-invalid capture cannot return/publish")
            } catch { XCTAssertTrue(error is CancellationError) }
            rejected.fulfill()
        }
        defer { gate.resume(); task.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        coordinator.clearCachedContext()
        let newLease = coordinator.beginRequestLease()
        let fresh = try HistoryQueryFixtures.snapshot()
        let current = try await coordinator.snapshotForQuery(query, key: key, lease: newLease) { fresh }
        coordinator.finishRequestLease(oldLease)
        let response = try coordinator.responseForQuery(query, snapshot: current, key: key,
            cursorKey: HistoryQueryFixtures.cursorKey, lease: newLease)
        XCTAssertNotNil(response.nextCursor)
        gate.resume()
        await fulfillment(of: [rejected], timeout: 1)
        XCTAssertEqual(cache.continuation(for: key)?.captureID, fresh.captureID)
        XCTAssertThrowsError(try coordinator.responseForQuery(query, snapshot: staleSnapshot, key: key,
            cursorKey: HistoryQueryFixtures.cursorKey, lease: oldLease))
        XCTAssertEqual(cache.continuation(for: key)?.captureID, fresh.captureID)
        coordinator.clearCachedContext()
        XCTAssertThrowsError(try coordinator.responseForQuery(query, snapshot: current, key: key,
            cursorKey: HistoryQueryFixtures.cursorKey, lease: newLease))
        XCTAssertTrue(cache.isEmpty, "Invalidation after snapshot return must also prevent publication")
    }
}
#endif
