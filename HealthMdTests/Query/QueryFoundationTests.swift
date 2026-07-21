import XCTest
@testable import HealthMd

final class QueryFoundationTests: XCTestCase {
    private let cursorKey = Data("test-only-cursor-key".utf8)

    func testCanonicalBytesAreStableAndRejectNonFiniteValues() throws {
        let value = HealthMdQueryValue.array([
            .quantity(value: 12.5, unit: "km"), .duration(seconds: 60), .count(3),
            .string("x"), .category(.init(identifier: "asleep", display: "Asleep", rawValue: 2)),
            .boolean(true), .timestamp(Date(timeIntervalSince1970: 1_700_000_000.125)),
            .date("2026-03-08"), .unknown(type: "future_value", value: .object(["z": .integer(1)]))
        ])
        let first = try HealthMdQueryCanonicalSerializer.data(for: value)
        let second = try HealthMdQueryCanonicalSerializer.data(for: value)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try HealthMdQueryCanonicalSerializer.decode(HealthMdQueryValue.self, from: first), value)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), #"{"type":"array","value":[{"type":"quantity","unit":"km","value":12.5},{"seconds":60,"type":"duration"},{"type":"count","value":3},{"type":"string","value":"x"},{"display":"Asleep","identifier":"asleep","raw_value":2,"type":"category"},{"type":"boolean","value":true},{"type":"timestamp","value":"2023-11-14T22:13:20.125000000Z"},{"type":"date","value":"2026-03-08"},{"type":"future_value","value":{"z":1}}]}"#)
        XCTAssertThrowsError(try HealthMdQueryCanonicalSerializer.data(for: HealthMdQueryValue.quantity(value: .nan, unit: "x")))
        XCTAssertThrowsError(try HealthMdQueryCanonicalSerializer.data(for: HealthMdQueryValue.duration(seconds: .infinity)))
    }

    func testPacketIDIsPermutationInvariantAndExcludesVolatileMetadata() throws {
        let sourceA = source("b")
        let sourceB = source("a")
        let evidenceA = reference(id: "e2", day: "2026-01-01", source: sourceA)
        let evidenceB = reference(id: "e1", day: "2026-01-01", source: sourceA)
        let facts = [
            HealthMdPacketFact(factID: "b", label: "Steps", value: .count(4), evidence: [evidenceA, evidenceB]),
            HealthMdPacketFact(factID: "a", label: "Sleep", value: .duration(seconds: 8), evidence: [])
        ]
        let coverage = HealthMdCoverage(requestedRange: nil, availableRange: nil, status: .available, daysConsidered: 1, daysWithValues: 1)
        let limitations = [HealthMdLimitation(code: "z", message: "Z"), .init(code: "a", message: "A")]
        let first = try HealthMdQueryCanonicalSerializer.makePacket(
            kind: .dailyWellness, range: nil, facts: facts, coverage: coverage,
            sources: [sourceA, sourceB], limitations: limitations,
            metadata: .init(generatedAt: Date(timeIntervalSince1970: 1))
        )
        let second = try HealthMdQueryCanonicalSerializer.makePacket(
            kind: .dailyWellness, range: nil, facts: facts.reversed(), coverage: coverage,
            sources: [sourceB, sourceA], limitations: limitations.reversed(),
            metadata: .init(generatedAt: Date(timeIntervalSince1970: 999))
        )
        let permutedWithSameMetadata = try HealthMdQueryCanonicalSerializer.makePacket(
            kind: .dailyWellness, range: nil, facts: facts.reversed(), coverage: coverage,
            sources: [sourceB, sourceA], limitations: limitations.reversed(),
            metadata: .init(generatedAt: Date(timeIntervalSince1970: 1))
        )
        XCTAssertEqual(first.packetID, second.packetID)
        XCTAssertEqual(try HealthMdQueryCanonicalSerializer.data(for: first), try HealthMdQueryCanonicalSerializer.data(for: permutedWithSameMetadata))
        XCTAssertNotEqual(try HealthMdQueryCanonicalSerializer.data(for: first), try HealthMdQueryCanonicalSerializer.data(for: second))
    }

    func testAllMetricsAndFullHistoryAreCompletelyReachableThroughCursorPaging() throws {
        let days = (0..<20).map { index in
            day("2026-01-\(String(format: "%02d", index + 1))", metrics: [
                metric("dynamic_\(index % 3)", id: "m-\(index)", value: .count(Int64(index)))
            ])
        }
        let evaluator = try HealthMdQueryEvaluator(days: days, cursorKey: cursorKey)
        var cursor: String?
        var items: [HealthMdQueryItem] = []
        repeat {
            let response = try evaluator.evaluate(.init(
                metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries,
                page: .init(maxItems: 3, maxBytes: 700, cursor: cursor)
            ))
            XCTAssertLessThanOrEqual(response.items.count, 3)
            items.append(contentsOf: response.items)
            cursor = response.nextCursor
        } while cursor != nil
        XCTAssertEqual(items.count, 20)
        let points: [HealthMdMetricPoint] = items.compactMap { item in
            guard case .metric(let value) = item else { return nil }
            return value
        }
        XCTAssertEqual(Set(points.map(\.metricID)), Set(["dynamic_0", "dynamic_1", "dynamic_2"]))
        XCTAssertEqual(points.first?.ownerDate, "2026-01-01")
        XCTAssertEqual(points.last?.ownerDate, "2026-01-20")
    }

    func testQueryResponsesAreVersionedAndPageBoundsRemainContinuable() throws {
        let evaluator = try HealthMdQueryEvaluator(
            days: [day("2026-01-01", metrics: [metric("steps", id: "1")])],
            cursorKey: cursorKey
        )
        let response = try evaluator.evaluate(.init(
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries
        ))
        XCTAssertEqual(response.schema, HealthMdQuerySchemas.queryResponse)
        XCTAssertEqual(response.schemaVersion, 1)

        XCTAssertThrowsError(try evaluator.evaluate(.init(
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries,
            page: .init(maxItems: HealthMdPageControls.maximumItems + 1, maxBytes: 1_000)
        )))
        XCTAssertThrowsError(try evaluator.evaluate(.init(
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries,
            page: .init(maxItems: 1, maxBytes: HealthMdPageControls.maximumBytes + 1)
        )))
    }

    func testInvalidCalendarDatesFailInsteadOfLexicallySelectingData() throws {
        let evaluator = try HealthMdQueryEvaluator(
            days: [day("2026-02-01", metrics: [metric("steps", id: "1")])],
            cursorKey: cursorKey
        )

        XCTAssertThrowsError(try evaluator.evaluate(.init(
            metrics: .allAvailable,
            dates: .exact(.init(startDate: "2026-02-30", endDate: "2026-02-30")),
            operation: .metricSeries
        )))
    }

    func testCursorCompletenessTamperingAndQueryBinding() throws {
        let evaluator = try HealthMdQueryEvaluator(days: [day("2026-01-01", metrics: [metric("a", id: "1"), metric("b", id: "2")])], cursorKey: cursorKey)
        let request = HealthMdQueryRequest(metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries, page: .init(maxItems: 1, maxBytes: 10_000))
        let first = try evaluator.evaluate(request)
        let cursor = try XCTUnwrap(first.nextCursor)
        let second = try evaluator.evaluate(.init(metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries, page: .init(maxItems: 1, maxBytes: 10_000, cursor: cursor)))
        XCTAssertEqual(second.items.count, 1)
        var tampered = cursor
        tampered.replaceSubrange(tampered.index(before: tampered.endIndex)..., with: tampered.last == "A" ? "B" : "A")
        XCTAssertThrowsError(try evaluator.evaluate(.init(metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries, page: .init(maxItems: 1, maxBytes: 10_000, cursor: tampered))))
        XCTAssertThrowsError(try evaluator.evaluate(.init(metrics: .explicit(["a"]), dates: .allAvailable, operation: .metricSeries, page: .init(maxItems: 1, maxBytes: 10_000, cursor: cursor))))
    }

    func testMissingnessAndCompleteEmptyRemainDistinctFromZero() throws {
        let unavailable: [HealthMdAvailabilityStatus] = [.partial, .unsupported, .skipped, .cancelled, .notRequested, .legacyUnavailable, .redacted, .notSynchronized]
        let metrics = unavailable.enumerated().map { metric("m\($0.offset)", id: "x\($0.offset)", value: nil, status: $0.element) }
        let evaluator = try HealthMdQueryEvaluator(days: [day("2026-02-01", metrics: metrics), day("2026-02-02", status: .completeEmpty)], cursorKey: cursorKey)
        let response = try evaluator.evaluate(.init(metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries, page: .init(maxItems: 100, maxBytes: 100_000)))
        let points = response.items.compactMap { if case .metric(let value) = $0 { return value }; return nil }
        XCTAssertEqual(points.count, unavailable.count)
        XCTAssertTrue(points.allSatisfy { $0.value == nil })
        XCTAssertEqual(Set(points.map(\.status)), Set(unavailable))
        XCTAssertEqual(response.coverage.status, .partial)

        let emptyEvaluator = try HealthMdQueryEvaluator(days: [day("2026-02-02", status: .completeEmpty)], cursorKey: cursorKey)
        let empty = try emptyEvaluator.evaluate(.init(metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries))
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertEqual(empty.coverage.status, .completeEmpty)
        XCTAssertEqual(empty.coverage.daysWithValues, 0)
    }

    func testComparisonDoesNotDoubleCountDuplicateObservationsOrWorkouts() throws {
        let duplicate = metric("steps", id: "same", value: .count(10))
        let workout = HealthMdContextWorkout(workoutID: "uuid-1", activity: "running", start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20))
        let days = [
            day("2026-03-01", metrics: [duplicate, duplicate], workouts: [workout]),
            day("2026-03-02", metrics: [metric("steps", id: "next", value: .count(20))], workouts: [workout])
        ]
        let evaluator = try HealthMdQueryEvaluator(days: days, cursorKey: cursorKey)
        let comparison = try evaluator.evaluate(.init(
            metrics: .explicit(["steps"]), dates: .allAvailable,
            operation: .periodComparison(
                first: .init(startDate: "2026-03-01", endDate: "2026-03-01"),
                second: .init(startDate: "2026-03-02", endDate: "2026-03-02"),
                aggregations: [.init(metricID: "steps", kind: .sum)]
            )
        ))
        guard case .comparison(let value) = try XCTUnwrap(comparison.items.first) else { return XCTFail("Missing comparison") }
        XCTAssertEqual(value.firstValue, .count(10))
        XCTAssertEqual(value.secondValue, .count(20))
        XCTAssertEqual(value.direction, .increased)

        let workouts = try evaluator.evaluate(.init(metrics: .allAvailable, dates: .allAvailable, operation: .workoutListing))
        XCTAssertEqual(workouts.items.count, 1)
    }

    func testEvidenceResolutionRequiresMatchingLocatorAndSource() throws {
        let source = source("digest")
        let ref = reference(id: "evidence", day: "2026-04-01", source: source)
        let context = day("2026-04-01", evidence: [.init(reference: ref, value: .count(2))])
        XCTAssertTrue(HealthMdEvidenceResolver.allResolve([ref], in: [context]))
        let wrongLocator = HealthMdEvidenceReference(evidenceID: "evidence", locator: .warning(ownerDate: "2026-04-01", code: "x"), source: source)
        XCTAssertFalse(HealthMdEvidenceResolver.allResolve([wrongLocator], in: [context]))
        let wrongSource = reference(id: "evidence", day: "2026-04-01", source: self.source("other"))
        XCTAssertFalse(HealthMdEvidenceResolver.allResolve([wrongSource], in: [context]))
    }

    func testExactOwnerDatesRespectStoredTimezoneBoundaries() throws {
        let la = day(
            "2026-03-08", intervalStart: iso("2026-03-08T08:00:00Z"), intervalEnd: iso("2026-03-09T07:00:00Z"),
            timeZone: "America/Los_Angeles", metrics: [metric("steps", id: "la")]
        )
        let tokyo = day(
            "2026-03-09", intervalStart: iso("2026-03-08T15:00:00Z"), intervalEnd: iso("2026-03-09T15:00:00Z"),
            timeZone: "Asia/Tokyo", metrics: [metric("steps", id: "tokyo")]
        )
        let evaluator = try HealthMdQueryEvaluator(days: [tokyo, la], cursorKey: cursorKey)
        let first = try evaluator.evaluate(.init(metrics: .allAvailable, dates: .exact(.init(startDate: "2026-03-08", endDate: "2026-03-08")), operation: .metricSeries))
        XCTAssertEqual(first.items.count, 1)
        guard case .metric(let point) = try XCTUnwrap(first.items.first) else { return XCTFail() }
        XCTAssertEqual(point.ownerDate, "2026-03-08")
        XCTAssertEqual(la.intervalEnd.timeIntervalSince(la.intervalStart), 23 * 3600)
    }

    func testZeroBaselineHasNoInfinitePercentAndUsesNeutralDirection() throws {
        let evaluator = try HealthMdQueryEvaluator(days: [
            day("2026-05-01", metrics: [metric("steps", id: "a", value: .count(0))]),
            day("2026-05-02", metrics: [metric("steps", id: "b", value: .count(5))])
        ], cursorKey: cursorKey)
        let response = try evaluator.evaluate(.init(metrics: .explicit(["steps"]), dates: .allAvailable, operation: .periodComparison(
            first: .init(startDate: "2026-05-01", endDate: "2026-05-01"), second: .init(startDate: "2026-05-02", endDate: "2026-05-02"),
            aggregations: [.init(metricID: "steps", kind: .sum)]
        )))
        guard case .comparison(let comparison) = try XCTUnwrap(response.items.first) else { return XCTFail() }
        XCTAssertNil(comparison.percentChange)
        XCTAssertEqual(comparison.direction, .increased)
        XCTAssertTrue(comparison.limitations.contains { $0.code == "zero_baseline" })
        XCTAssertFalse(try HealthMdQueryCanonicalSerializer.string(for: response).contains("Infinity"))
    }

    func testPacketDerivationsEnforceScopeAndUseMedicalSafetyWording() throws {
        let source = source("packet")
        let ref = reference(id: "ev", day: "2026-06-01", source: source)
        let evaluator = try HealthMdQueryEvaluator(days: [day("2026-06-01", metrics: [metric("resting_hr", id: "hr", value: .quantity(value: 60, unit: "bpm"), evidenceIDs: ["ev"])], evidence: [.init(reference: ref)])], cursorKey: cursorKey)
        let deniedRequest = HealthMdQueryRequest(metrics: .explicit(["resting_hr"]), dates: .allAvailable, operation: .derivePacket(kind: .doctorVisit, detailIDs: []))
        XCTAssertThrowsError(try evaluator.evaluate(deniedRequest, evidenceScope: .init(allowedMetricIDs: [])))

        for kind in HealthMdPacketKind.allCases {
            let request = HealthMdQueryRequest(metrics: .explicit(["resting_hr"]), dates: .allAvailable, operation: .derivePacket(kind: kind, detailIDs: []))
            let response = try evaluator.evaluate(request, evidenceScope: .init(allowedMetricIDs: ["resting_hr"]), generatedAt: Date(timeIntervalSince1970: 1))
            let packet = try XCTUnwrap(response.packet)
            XCTAssertEqual(packet.kind, kind)
            XCTAssertEqual(packet.facts.count, 1)
            let text = try HealthMdQueryCanonicalSerializer.string(for: packet).lowercased()
            XCTAssertTrue(text.contains("does not diagnose"))
            XCTAssertFalse(text.contains("better"))
            XCTAssertFalse(text.contains("worse"))
            XCTAssertFalse(text.contains("you should"))
            XCTAssertTrue(HealthMdEvidenceResolver.allResolve(packet.facts.flatMap(\.evidence), in: [day("2026-06-01", evidence: [.init(reference: ref)])]))
        }
    }

    // MARK: Fixtures

    private func source(_ digest: String) -> HealthMdSourceDescriptor {
        .init(schema: "healthmd.health_data", schemaVersion: 7, digest: digest)
    }

    private func reference(id: String, day: String, source: HealthMdSourceDescriptor) -> HealthMdEvidenceReference {
        .init(evidenceID: id, locator: .summaryKey(ownerDate: day, key: "steps"), source: source)
    }

    private func metric(_ id: String, id observationID: String, value: HealthMdQueryValue? = .count(1), status: HealthMdAvailabilityStatus = .available, evidenceIDs: [String] = []) -> HealthMdContextMetric {
        .init(observationID: observationID, metricID: id, displayName: id, value: value, status: status, evidenceIDs: evidenceIDs)
    }

    private func day(
        _ ownerDate: String,
        intervalStart: Date = Date(timeIntervalSince1970: 0),
        intervalEnd: Date = Date(timeIntervalSince1970: 86_400),
        timeZone: String = "UTC",
        status: HealthMdAvailabilityStatus = .available,
        metrics: [HealthMdContextMetric] = [],
        workouts: [HealthMdContextWorkout] = [],
        evidence: [HealthMdContextEvidence] = []
    ) -> HealthMdCompactContextDay {
        .init(ownerDate: ownerDate, intervalStart: intervalStart, intervalEnd: intervalEnd, calendarTimeZone: timeZone, source: source("source-\(ownerDate)"), status: status, metrics: metrics, workouts: workouts, evidence: evidence)
    }

    private func iso(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
