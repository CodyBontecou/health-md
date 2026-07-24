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

    func testDirectScopeSelectorsRejectAmbiguousDuplicateAndUnknownFields() throws {
        let decoder = JSONDecoder()
        for json in [
            #"{"type":"all_available","metric_ids":["steps"]}"#,
            #"{"type":"explicit","metric_ids":["steps","steps"]}"#,
            #"{"type":"explicit","metric_ids":["steps"],"profile":"removed"}"#
        ] {
            XCTAssertThrowsError(try decoder.decode(
                HealthMdMetricSelection.self,
                from: Data(json.utf8)
            ))
        }
        for json in [
            #"{"type":"all_available","source_ids":["apple_health"]}"#,
            #"{"type":"explicit","source_ids":["apple_health","apple_health"]}"#,
            #"{"type":"explicit","provider_ids":["oura","oura"]}"#,
            #"{"type":"explicit","source_ids":[],"credential":"removed"}"#
        ] {
            XCTAssertThrowsError(try decoder.decode(
                HealthMdSourceSelection.self,
                from: Data(json.utf8)
            ))
        }
        for json in [
            #"{"type":"all_available","range":{"start_date":"2026-01-01","end_date":"2026-01-02"}}"#,
            #"{"type":"exact","range":{"start_date":"2026-01-01","end_date":"2026-01-02","extra":true}}"#
        ] {
            XCTAssertThrowsError(try decoder.decode(
                HealthMdDateSelection.self,
                from: Data(json.utf8)
            ))
        }
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

    func testSleepSessionsUseStableBoundariesClassificationAndFixedWindow() throws {
        let stages = [
            SleepStageSample(stage: "core", startDate: iso("2026-07-01T20:00:00Z"), endDate: iso("2026-07-01T20:45:00Z")),
            SleepStageSample(stage: "inBed", startDate: iso("2026-07-02T05:00:00Z"), endDate: iso("2026-07-02T13:00:00Z")),
            SleepStageSample(stage: "deep", startDate: iso("2026-07-02T05:00:00Z"), endDate: iso("2026-07-02T07:00:00Z")),
            SleepStageSample(stage: "core", startDate: iso("2026-07-02T07:00:00Z"), endDate: iso("2026-07-02T09:00:00Z")),
            SleepStageSample(stage: "rem", startDate: iso("2026-07-02T09:00:00Z"), endDate: iso("2026-07-02T11:00:00Z")),
            SleepStageSample(stage: "core", startDate: iso("2026-07-02T11:00:00Z"), endDate: iso("2026-07-02T13:00:00Z"))
        ]
        let derived = try HealthMdSleepSessionQuery.contextSessions(
            sleep: SleepData(
                sessionStart: stages.first?.startDate,
                sessionEnd: stages.last?.endDate,
                stages: stages
            ),
            ownerDate: "2026-07-01",
            ownerIntervalStart: iso("2026-07-01T07:00:00Z"),
            calendarTimeZone: "America/Los_Angeles",
            evidenceIDs: ["sleep-evidence"]
        )
        let repeated = try HealthMdSleepSessionQuery.contextSessions(
            sleep: SleepData(stages: stages),
            ownerDate: "2026-07-01",
            ownerIntervalStart: iso("2026-07-01T07:00:00Z"),
            calendarTimeZone: "America/Los_Angeles",
            evidenceIDs: ["sleep-evidence"]
        )
        XCTAssertEqual(derived.map(\.sessionID), repeated.map(\.sessionID))
        XCTAssertEqual(derived.map(\.classification), [.nap, .overnight])

        let source = source("sleep")
        let sleepReference = HealthMdEvidenceReference(
            evidenceID: "sleep-evidence",
            locator: .summaryKey(ownerDate: "2026-07-01", key: "sleep_total_hours"),
            source: source
        )
        let heartReference = HealthMdEvidenceReference(
            evidenceID: "heart-evidence",
            locator: .canonicalUUID(
                ownerDate: "2026-07-02",
                uuid: "00000000-0000-0000-0000-000000000001"
            ),
            source: source,
            sourceID: HealthMdEvidenceSourceIDs.appleHealth
        )
        let heartEvidence = HealthMdContextEvidence(
            reference: heartReference,
            value: .unknown(type: "canonical_healthkit_record", value: .object([
                "start": .string("2026-07-02T08:00:00.000000000Z"),
                "end": .string("2026-07-02T08:00:00.000000000Z")
            ])),
            metricIDs: ["heart_rate"]
        )
        let owner = day(
            "2026-07-01",
            intervalStart: iso("2026-07-01T07:00:00Z"),
            intervalEnd: iso("2026-07-02T07:00:00Z"),
            timeZone: "America/Los_Angeles",
            sleepSessions: derived,
            evidence: [.init(reference: sleepReference)]
        )
        let adjacent = day(
            "2026-07-02",
            intervalStart: iso("2026-07-02T07:00:00Z"),
            intervalEnd: iso("2026-07-03T07:00:00Z"),
            timeZone: "America/Los_Angeles",
            evidence: [heartEvidence]
        )
        let evaluator = try HealthMdQueryEvaluator(days: [owner, adjacent], cursorKey: cursorKey)
        let request = HealthMdQueryRequest(
            metrics: .explicit([
                "sleep_total", "sleep_deep", "sleep_core", "sleep_rem",
                "sleep_awake", "sleep_in_bed", "heart_rate"
            ]),
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            operation: .sleepSessionListing(
                window: .init(durationSeconds: 4 * 3_600),
                includeNaps: false
            )
        )
        let roundTripped = try HealthMdQueryCanonicalSerializer.decode(
            HealthMdQueryRequest.self,
            from: HealthMdQueryCanonicalSerializer.data(for: request)
        )
        XCTAssertEqual(roundTripped.operation, request.operation)
        guard case .explicit(let roundTrippedMetrics) = roundTripped.metrics else {
            return XCTFail("Expected explicit metrics")
        }
        XCTAssertEqual(Set(roundTrippedMetrics), Set([
            "sleep_total", "sleep_deep", "sleep_core", "sleep_rem",
            "sleep_awake", "sleep_in_bed", "heart_rate"
        ]))
        let response = try evaluator.evaluate(
            request,
            evidenceScope: .init(allowedMetricIDs: [
                "sleep_total", "sleep_deep", "sleep_core", "sleep_rem",
                "sleep_awake", "sleep_in_bed", "heart_rate"
            ])
        )
        XCTAssertEqual(response.items.count, 1)
        guard case .sleepSession(let session) = try XCTUnwrap(response.items.first) else {
            return XCTFail("Expected sleep session")
        }
        XCTAssertEqual(session.classification, .overnight)
        XCTAssertEqual(session.localStart, "2026-07-01T22:00:00-07:00")
        XCTAssertEqual(session.localEnd, "2026-07-02T06:00:00-07:00")
        XCTAssertEqual(session.calendarDates, ["2026-07-01", "2026-07-02"])
        XCTAssertEqual(session.elapsedDurationSeconds, 4 * 3_600)
        XCTAssertEqual(session.observedDurationSeconds, 4 * 3_600)
        XCTAssertEqual(session.untrackedDurationSeconds, 0)
        XCTAssertEqual(session.stageDurationsSeconds["deep"], 2 * 3_600)
        XCTAssertEqual(session.stageDurationsSeconds["core"], 2 * 3_600)
        XCTAssertEqual(session.physiology.first?.metricID, "heart_rate")
        XCTAssertEqual(session.physiology.first?.sampleCount, 1)
        XCTAssertEqual(response.metadata?["excluded_nap_count"], .integer(1))
        XCTAssertEqual(
            response.metadata?["adjacent_owner_dates_considered"],
            .array([.string("2026-07-02")])
        )
        XCTAssertTrue(response.limitations.contains { $0.code == "factual_observations_only" })
    }

    func testSleepSessionTotalsAreAuthorizedAndOverlapSafe() throws {
        let start = iso("2026-07-01T22:00:00Z")
        let end = iso("2026-07-02T05:00:00Z")
        let owner = day(
            "2026-07-01",
            intervalStart: iso("2026-07-01T12:00:00Z"),
            intervalEnd: iso("2026-07-02T12:00:00Z")
        )
        let aggregate = HealthMdContextSleepSession(
            sessionID: "sleep:aggregate",
            start: start,
            end: end,
            classification: .overnight,
            completeness: .aggregated,
            aggregateStageDurations: ["asleep_total": 6 * 3_600]
        )
        let aggregateResult = try XCTUnwrap(HealthMdSleepSessionQuery.result(
            session: aggregate,
            ownerDay: owner,
            relatedDays: [owner],
            window: nil,
            authorizedSleepMetricIDs: ["sleep_total"],
            physiologyMetricIDs: [],
            authorizedEvidence: []
        ))
        XCTAssertEqual(aggregateResult.asleepDurationSeconds, 6 * 3_600)
        XCTAssertEqual(aggregateResult.observedDurationSeconds, 0)
        XCTAssertEqual(aggregateResult.untrackedDurationSeconds, 7 * 3_600)

        let overlapping = HealthMdContextSleepSession(
            sessionID: "sleep:overlap",
            start: start,
            end: start.addingTimeInterval(3 * 3_600),
            classification: .overnight,
            completeness: .complete,
            stageIntervals: [
                .init(stage: "deep", start: start, end: start.addingTimeInterval(2 * 3_600)),
                .init(
                    stage: "core",
                    start: start.addingTimeInterval(3_600),
                    end: start.addingTimeInterval(3 * 3_600)
                )
            ]
        )
        let overlapResult = try XCTUnwrap(HealthMdSleepSessionQuery.result(
            session: overlapping,
            ownerDay: owner,
            relatedDays: [owner],
            window: nil,
            authorizedSleepMetricIDs: ["sleep_total", "sleep_deep", "sleep_core"],
            physiologyMetricIDs: [],
            authorizedEvidence: []
        ))
        XCTAssertEqual(overlapResult.asleepDurationSeconds, 3 * 3_600)
        XCTAssertEqual(overlapResult.stageDurationsSeconds["deep"], 2 * 3_600)
        XCTAssertEqual(overlapResult.stageDurationsSeconds["core"], 2 * 3_600)
        XCTAssertTrue(overlapResult.limitations.contains {
            $0.code == "overlapping_sleep_stage_sources"
        })

        let totalOnly = try XCTUnwrap(HealthMdSleepSessionQuery.result(
            session: overlapping,
            ownerDay: owner,
            relatedDays: [owner],
            window: nil,
            authorizedSleepMetricIDs: ["sleep_total"],
            physiologyMetricIDs: [],
            authorizedEvidence: []
        ))
        XCTAssertTrue(totalOnly.stageDurationsSeconds.isEmpty)
        XCTAssertEqual(totalOnly.asleepDurationSeconds, 3 * 3_600)
    }

    func testWorkoutSleepAlignmentIsDeterministicFactualAndExplicitAboutExclusions() throws {
        let previousStart = iso("2026-07-01T22:00:00Z")
        let previousEnd = iso("2026-07-02T06:00:00Z")
        let workoutStart = iso("2026-07-02T17:00:00Z")
        let workoutEnd = iso("2026-07-02T18:00:00Z")
        let followingStart = iso("2026-07-02T23:00:00Z")
        let followingEnd = iso("2026-07-03T07:00:00Z")
        let previous = HealthMdContextSleepSession(
            sessionID: "sleep:previous",
            start: previousStart,
            end: previousEnd,
            classification: .overnight,
            completeness: .complete,
            stageIntervals: [
                .init(stage: "core", start: previousStart, end: previousEnd)
            ]
        )
        let following = HealthMdContextSleepSession(
            sessionID: "sleep:following",
            start: followingStart,
            end: followingEnd,
            classification: .overnight,
            completeness: .complete,
            stageIntervals: [
                .init(stage: "core", start: followingStart, end: followingEnd)
            ]
        )
        let running = HealthMdContextWorkout(
            workoutID: "workout:running",
            activity: "running",
            start: workoutStart,
            end: workoutEnd
        )
        let cycling = HealthMdContextWorkout(
            workoutID: "workout:cycling",
            activity: "cycling",
            start: workoutStart.addingTimeInterval(600),
            end: workoutEnd.addingTimeInterval(600)
        )
        let evaluator = try HealthMdQueryEvaluator(days: [
            day(
                "2026-07-01",
                intervalStart: iso("2026-07-01T00:00:00Z"),
                intervalEnd: iso("2026-07-02T00:00:00Z"),
                sleepSessions: [previous]
            ),
            day(
                "2026-07-02",
                intervalStart: iso("2026-07-02T00:00:00Z"),
                intervalEnd: iso("2026-07-03T00:00:00Z"),
                workouts: [running, cycling],
                sleepSessions: [following]
            )
        ], cursorKey: cursorKey)
        let request = HealthMdQueryRequest(
            metrics: .explicit(["workouts", "sleep_total"]),
            dates: .exact(.init(startDate: "2026-07-02", endDate: "2026-07-02")),
            operation: .workoutSleepAlignment(
                window: .init(durationSeconds: 4 * 3_600),
                workoutActivity: "running",
                includeNaps: false
            )
        )
        let scope = HealthMdEvidenceScope(
            allowedMetricIDs: ["workouts", "sleep_total"],
            allowsWorkouts: true
        )
        let first = try evaluator.evaluate(request, evidenceScope: scope)
        let second = try evaluator.evaluate(request, evidenceScope: scope)
        XCTAssertEqual(first.items, second.items)
        XCTAssertEqual(first.items.count, 1)
        guard case .workoutSleepAlignment(let alignment) = try XCTUnwrap(first.items.first) else {
            return XCTFail("Expected workout/sleep alignment")
        }
        XCTAssertEqual(alignment.workout.workoutID, "workout:running")
        XCTAssertEqual(alignment.precedingSleep?.sessionID, "sleep:previous")
        XCTAssertEqual(alignment.followingSleep?.sessionID, "sleep:following")
        XCTAssertEqual(alignment.precedingSleep?.elapsedDurationSeconds, 4 * 3_600)
        XCTAssertEqual(alignment.followingSleep?.elapsedDurationSeconds, 4 * 3_600)
        XCTAssertEqual(alignment.secondsFromPrecedingSleep, 11 * 3_600)
        XCTAssertEqual(alignment.secondsUntilFollowingSleep, 5 * 3_600)
        XCTAssertEqual(alignment.status, .complete)
        XCTAssertTrue(alignment.limitations.contains { $0.code == "temporal_alignment_only" })
        XCTAssertEqual(first.metadata?["activity_excluded_workout_count"], .integer(1))
        let text = try HealthMdQueryCanonicalSerializer.string(for: alignment).lowercased()
        XCTAssertFalse(text.contains("improved"))
        XCTAssertFalse(text.contains("worsened"))
        XCTAssertFalse(text.contains("you should"))
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
        sleepSessions: [HealthMdContextSleepSession] = [],
        evidence: [HealthMdContextEvidence] = []
    ) -> HealthMdCompactContextDay {
        .init(ownerDate: ownerDate, intervalStart: intervalStart, intervalEnd: intervalEnd, calendarTimeZone: timeZone, source: source("source-\(ownerDate)"), status: status, metrics: metrics, workouts: workouts, sleepSessions: sleepSessions, evidence: evidence)
    }

    private func iso(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
