import XCTest
@testable import HealthMd

#if os(macOS)
final class EncryptedHealthContextQueryExecutorTests: XCTestCase {
    func testMultiThousandDayAndDenseDayPaginationHasNoLossOrDuplicates() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"])
        let dates = ownerDates(count: 2_001)
        try await store.upsert(dates.enumerated().map { index, date in
            day(date, metrics: [metric("steps", id: "day-\(index)", value: .count(Int64(index)))])
        })

        let history = try await collectItems(
            executor: executor,
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries,
            maxItems: 73
        )
        let historyIDs = history.compactMap { item -> String? in
            guard case .metric(let point) = item else { return nil }
            return "\(point.ownerDate)|\(point.metricID)|\(point.value!)"
        }
        XCTAssertEqual(historyIDs.count, 2_001)
        XCTAssertEqual(Set(historyIDs).count, 2_001)

        let denseDate = dates.last!
        let dense = (0..<2_505).map {
            metric("steps", id: String(format: "dense-%04d", $0), value: .count(Int64($0)))
        }
        try await store.upsert(day(denseDate, metrics: dense))
        let denseItems = try await collectItems(
            executor: executor,
            metrics: .allAvailable,
            dates: .exact(.init(startDate: denseDate, endDate: denseDate)),
            operation: .metricSeries,
            maxItems: 91
        )
        XCTAssertEqual(denseItems.count, 2_505)
    }

    func testCursorTamperingAndMutationFailClosedAndSingleOversizeItemFails() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"], allowsEvidenceValues: true)
        let evidence = contextEvidence(
            id: "large",
            day: "2026-01-01",
            sourceID: HealthMdEvidenceSourceIDs.appleHealth,
            value: .string(String(repeating: "x", count: 2_000)),
            metricIDs: ["steps"]
        )
        try await store.upsert(day(
            "2026-01-01",
            metrics: [metric("steps", id: "a"), metric("steps", id: "b")],
            evidence: [evidence]
        ))
        let firstRequest = HealthMdQueryRequest(
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries,
            page: .init(maxItems: 1, maxBytes: 50_000)
        )
        let first = try await executor.execute(firstRequest, detailLevel: .summary)
        let cursor = try XCTUnwrap(first.nextCursor)

        var tampered = cursor
        let index = tampered.index(tampered.startIndex, offsetBy: tampered.count / 2)
        tampered.replaceSubrange(index...index, with: tampered[index] == "A" ? "B" : "A")
        await XCTAssertThrowsQueryError(.invalidCursor) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .allAvailable,
                    dates: .allAvailable,
                    operation: .metricSeries,
                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: tampered)
                ),
                detailLevel: .summary
            )
        }

        await XCTAssertThrowsQueryError(.cursorDoesNotMatchQuery) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .allAvailable,
                    dates: .allAvailable,
                    operation: .metricSeries,
                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: cursor)
                ),
                detailLevel: .summary,
                evidenceScope: .init(allowedMetricIDs: [])
            )
        }

        try await store.upsert(day("2026-01-02", metrics: [metric("steps", id: "c")]))
        await XCTAssertThrowsQueryError(.staleCursor) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .allAvailable,
                    dates: .allAvailable,
                    operation: .metricSeries,
                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: cursor)
                ),
                detailLevel: .summary
            )
        }

        await XCTAssertThrowsQueryError(.singleItemExceedsPageBytes) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .allAvailable,
                    dates: .exact(.init(startDate: "2026-01-01", endDate: "2026-01-01")),
                    operation: .sourceRecordListing,
                    page: .init(maxItems: 10, maxBytes: 200)
                ),
                detailLevel: .lossless
            )
        }
    }

    func testAppleAndProviderEvidenceValuesArePagedAndFilterableWithBackwardSourceDefault() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"], allowsEvidenceValues: true)
        let source = HealthMdSourceDescriptor(schema: "healthmd.health_data", schemaVersion: 7, digest: "source")
        let apple = HealthMdContextEvidence(
            reference: .init(
                evidenceID: "apple",
                locator: .canonicalUUID(ownerDate: "2026-02-01", uuid: "00000000-0000-0000-0000-000000000001"),
                source: source,
                sourceID: HealthMdEvidenceSourceIDs.appleHealth
            ),
            value: .unknown(type: "canonical_healthkit_record", value: .object(["uuid": .string("00000000-0000-0000-0000-000000000001")])),
            metricIDs: ["steps"]
        )
        let provider = HealthMdContextEvidence(
            reference: .init(
                evidenceID: "provider",
                locator: .externalIdentity(ownerDate: "2026-02-01", identifier: "provider:oura:record"),
                source: source,
                sourceID: HealthMdEvidenceSourceIDs.providerNative,
                providerID: "oura"
            ),
            value: .unknown(type: "external_provider_payload", value: .object(["provider": .string("oura"), "raw": .integer(7)]))
        )
        try await store.upsert(day("2026-02-01", evidence: [apple, provider]))

        let all = try await collectItems(
            executor: executor,
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .sourceRecordListing,
            maxItems: 1,
            detailLevel: .lossless
        )
        let values = all.compactMap { item -> HealthMdContextEvidence? in
            guard case .evidence(let evidence) = item else { return nil }
            return evidence
        }
        XCTAssertEqual(values.map { $0.reference.evidenceID }, ["apple", "provider"])
        XCTAssertNotNil(values[0].value)
        XCTAssertNotNil(values[1].value)

        let providerOnly = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .allAvailable,
                sources: .explicit(sourceIDs: [], providerIDs: ["oura"]),
                dates: .allAvailable,
                operation: .sourceRecordListing,
                page: .init(maxItems: 10, maxBytes: 100_000)
            ),
            detailLevel: .lossless
        )
        XCTAssertEqual(providerOnly.items.count, 1)
        guard case .evidence(let selected) = try XCTUnwrap(providerOnly.items.first) else {
            return XCTFail("Expected provider evidence")
        }
        XCTAssertEqual(selected.reference.providerID, "oura")

        let legacyJSON = #"{"schema":"healthmd.query_request","schema_version":1,"metrics":{"type":"all_available"},"dates":{"type":"all_available"},"operation":{"type":"metric_series"},"page":{"max_items":10,"max_bytes":10000}}"#
        let decoded = try HealthMdQueryCanonicalSerializer.decode(
            HealthMdQueryRequest.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(decoded.sources, .allAvailable)
    }

    func testComparisonPacketAndMissingnessRemainExactAndNeutral() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"])
        try await store.upsert([
            day("2026-03-01", metrics: [metric("steps", id: "zero", value: .count(0))]),
            day("2026-03-02", metrics: [metric("steps", id: "five", value: .count(5))]),
            day("2026-03-03", status: .partial, metrics: [metric("steps", id: "missing", value: nil, status: .partial)])
        ])

        let comparisonResponse = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["steps"]),
                dates: .allAvailable,
                operation: .periodComparison(
                    first: .init(startDate: "2026-03-01", endDate: "2026-03-01"),
                    second: .init(startDate: "2026-03-02", endDate: "2026-03-02"),
                    aggregations: [.init(metricID: "steps", kind: .sum)]
                )
            ),
            detailLevel: .summary
        )
        guard case .comparison(let comparison) = try XCTUnwrap(comparisonResponse.items.first) else {
            return XCTFail("Expected comparison")
        }
        XCTAssertEqual(comparison.firstValue, .count(0))
        XCTAssertEqual(comparison.secondValue, .count(5))
        XCTAssertNil(comparison.percentChange)
        XCTAssertEqual(comparison.direction, .increased)

        let packetResponse = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["steps"]),
                dates: .allAvailable,
                operation: .derivePacket(kind: .doctorVisit, detailIDs: []),
                page: .init(maxItems: 10, maxBytes: 100_000)
            ),
            detailLevel: .summary
        )
        let packet = try XCTUnwrap(packetResponse.packet)
        XCTAssertEqual(packet.facts.count, 2)
        XCTAssertTrue(packet.limitations.contains { $0.code == "factual_observations_only" })
        XCTAssertFalse(try HealthMdQueryCanonicalSerializer.string(for: packet).lowercased().contains("you should"))

        let series = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["steps"]),
                dates: .allAvailable,
                operation: .metricSeries,
                page: .init(maxItems: 10, maxBytes: 100_000)
            ),
            detailLevel: .summary
        )
        let missing = series.items.compactMap { item -> HealthMdMetricPoint? in
            guard case .metric(let point) = item, point.ownerDate == "2026-03-03" else { return nil }
            return point
        }
        XCTAssertEqual(missing.first?.value, nil)
        XCTAssertEqual(missing.first?.status, .partial)
        XCTAssertEqual(series.coverage.missing.last?.status, .partial)
    }

    func testRequestedScopeCompletionSeparatesUnrelatedSkippedBranches() async throws {
        let (store, executor) = try makeSystem(metrics: ["sleep_total", "heart_rate", "workouts"])
        let source = HealthMdSourceDescriptor(
            schema: "healthmd.health_data",
            schemaVersion: 7,
            digest: "scope-source"
        )
        let skipped = HealthMdContextEvidence(
            reference: .init(
                evidenceID: "workout-kit-skip",
                locator: .queryManifest(
                    ownerDate: "2026-07-01",
                    identifier: "WorkoutKitScheduledWorkoutPlan"
                ),
                source: source,
                sourceID: HealthMdEvidenceSourceIDs.appleHealth
            ),
            value: .unknown(type: "healthkit_query_result", value: .object([
                "status": .string("skipped"),
                "metric_ids": .array([.string("workouts")])
            ])),
            note: "Scheduled workout plans are unavailable in this runtime.",
            metricIDs: ["workouts"]
        )
        try await store.upsert(day(
            "2026-07-01",
            status: .partial,
            metrics: [
                metric("sleep_total", id: "sleep", value: .duration(seconds: 28_800)),
                metric("heart_rate", id: "heart", value: nil, status: .failed)
            ],
            workouts: [HealthMdContextWorkout(
                workoutID: "workout",
                activity: "running",
                start: Date(timeIntervalSince1970: 1),
                end: Date(timeIntervalSince1970: 2)
            )],
            evidence: [skipped]
        ))

        let sleepOnlyValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            metricIDs: ["sleep_total"]
        )
        let sleepOnly = try XCTUnwrap(sleepOnlyValue)
        XCTAssertEqual(sleepOnly.status, .success)
        XCTAssertEqual(sleepOnly.completeMetricDays, 1)
        XCTAssertEqual(sleepOnly.incompleteMetricDays, 0)
        XCTAssertEqual(sleepOnly.unrelatedSkips.count, 1)
        XCTAssertEqual(
            sleepOnly.unrelatedSkips.first?.identifier,
            "WorkoutKitScheduledWorkoutPlan"
        )

        let mixedValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-02")),
            metricIDs: ["sleep_total"]
        )
        let mixed = try XCTUnwrap(mixedValue)
        XCTAssertEqual(mixed.status, .partialSuccess)
        XCTAssertEqual(mixed.completeMetricDays, 1)
        XCTAssertEqual(mixed.incompleteMetricDays, 1)
        XCTAssertEqual(mixed.statusCounts["not_synchronized"], 1)

        let coverage = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["sleep_total", "heart_rate"]),
                dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
                operation: .coverage
            ),
            detailLevel: .summary
        )
        XCTAssertEqual(
            coverage.coverage.status,
            .partial,
            "A workout or complete sleep value must not mask a failed requested heart metric."
        )
        XCTAssertEqual(
            coverage.metadata?["requested_scope_status"],
            .string("partial_success")
        )

        let missingDateCoverage = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["sleep_total"]),
                dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-02")),
                operation: .coverage
            ),
            detailLevel: .summary
        )
        XCTAssertEqual(
            missingDateCoverage.metadata?["requested_scope_status"],
            .string("partial_success"),
            "A missing requested owner date must prevent cache reuse."
        )
    }

    func testRequestedScopeCompletionRequiresCurrentMutationAndRequestedSource() async throws {
        let (store, executor) = try makeSystem(metrics: ["sleep_total"])
        let appleEvidence = contextEvidence(
            id: "apple-sleep",
            day: "2026-07-01",
            sourceID: HealthMdEvidenceSourceIDs.appleHealth,
            value: .duration(seconds: 28_800),
            metricIDs: ["sleep_total"]
        )
        let appleDay = day(
            "2026-07-01",
            metrics: [metric(
                "sleep_total",
                id: "sleep",
                value: .duration(seconds: 28_800),
                evidenceIDs: [appleEvidence.reference.evidenceID]
            )],
            evidence: [appleEvidence]
        )
        try await store.upsert(appleDay)
        let baselineValue = try await executor.queryStoreBaseline()
        let baseline = try XCTUnwrap(baselineValue)

        let staleValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            metricIDs: ["sleep_total"],
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            changedSince: baseline
        )
        let stale = try XCTUnwrap(staleValue)
        XCTAssertEqual(stale.status, .failure)
        XCTAssertEqual(stale.statusCounts["not_synchronized"], 1)

        try await store.upsert(appleDay)
        let freshValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            metricIDs: ["sleep_total"],
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            changedSince: baseline
        )
        let fresh = try XCTUnwrap(freshValue)
        XCTAssertEqual(fresh.status, .success)

        let wrongSourceValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            metricIDs: ["sleep_total"],
            sources: .explicit(sourceIDs: [], providerIDs: ["whoop"]),
            changedSince: baseline
        )
        let wrongSource = try XCTUnwrap(wrongSourceValue)
        XCTAssertEqual(wrongSource.status, .failure)
    }

    @MainActor
    func testRequestedScopeCompletionAcceptsFreshAppleSummaryCompleteEmpty() async throws {
        let (store, executor) = try makeSystem(metrics: ["sleep_total"])
        let date = ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!
        let projected = try HealthMdQueryContextProjector.project(
            HealthData(
                date: date,
                timeContext: .init(calendarTimeZoneIdentifier: "UTC"),
                healthKitRecordCaptureStatus: .notRequested
            ),
            options: .init(enabledMetricIDs: ["sleep_total"])
        )
        try await store.upsert(projected)

        let completionValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            metricIDs: ["sleep_total"],
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: [])
        )
        let completion = try XCTUnwrap(completionValue)
        XCTAssertEqual(completion.status, .success)
        XCTAssertEqual(completion.completeMetricDays, 1)
        XCTAssertEqual(completion.statusCounts["complete_empty"], 1)
    }

    func testRequestedScopeCompletionRequiresEveryMetricSourceAndProviderDay() async throws {
        let (store, executor) = try makeSystem(metrics: ["sleep_total"])
        let appleEvidence = contextEvidence(
            id: "apple-sleep",
            day: "2026-07-01",
            sourceID: HealthMdEvidenceSourceIDs.appleHealth,
            value: .duration(seconds: 28_800),
            metricIDs: ["sleep_total"]
        )
        let providerEvidence = HealthMdContextEvidence(
            reference: .init(
                evidenceID: "whoop-fetch",
                locator: .queryManifest(
                    ownerDate: "2026-07-01",
                    identifier: "provider_daily_fetch:whoop"
                ),
                source: appleEvidence.reference.source,
                sourceID: HealthMdEvidenceSourceIDs.providerNative,
                providerID: "whoop"
            ),
            value: .unknown(type: "external_provider_fetch_result", value: .object([
                "status": .string("available"),
                "metric_ids": .array([.string("sleep_total")]),
                "payload_count": .integer(1),
                "warning_count": .integer(0)
            ])),
            metricIDs: ["sleep_total"]
        )
        try await store.upsert(day(
            "2026-07-01",
            metrics: [metric(
                "sleep_total",
                id: "sleep",
                value: .duration(seconds: 28_800),
                evidenceIDs: [appleEvidence.reference.evidenceID]
            )],
            evidence: [appleEvidence, providerEvidence]
        ))

        let completeValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            metricIDs: ["sleep_total"],
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: ["whoop"])
        )
        let complete = try XCTUnwrap(completeValue)
        XCTAssertEqual(complete.status, .success)
        XCTAssertEqual(complete.metricDaysConsidered, 2)
        XCTAssertEqual(complete.completeMetricDays, 2)

        let missingProviderValue = try await executor.requestedScopeCompletion(
            dates: .exact(.init(startDate: "2026-07-01", endDate: "2026-07-01")),
            metricIDs: ["sleep_total"],
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: ["oura"])
        )
        let missingProvider = try XCTUnwrap(missingProviderValue)
        XCTAssertEqual(missingProvider.status, .partialSuccess)
        XCTAssertEqual(missingProvider.completeMetricDays, 1)
        XCTAssertEqual(missingProvider.incompleteMetricDays, 1)
        XCTAssertEqual(missingProvider.statusCounts["not_synchronized"], 1)
    }

    func testEncryptedWorkoutSleepAlignmentUsesNearestSessionsAndActivityFilter() async throws {
        let (store, executor) = try makeSystem(metrics: ["workouts", "sleep_total"])
        let formatter = ISO8601DateFormatter()
        let previousStart = formatter.date(from: "2026-07-01T22:00:00Z")!
        let previousEnd = formatter.date(from: "2026-07-02T06:00:00Z")!
        let workoutStart = formatter.date(from: "2026-07-02T17:00:00Z")!
        let workoutEnd = formatter.date(from: "2026-07-02T18:00:00Z")!
        let followingStart = formatter.date(from: "2026-07-02T23:00:00Z")!
        let followingEnd = formatter.date(from: "2026-07-03T07:00:00Z")!
        let previous = HealthMdContextSleepSession(
            sessionID: "sleep:previous",
            start: previousStart,
            end: previousEnd,
            classification: .overnight,
            completeness: .complete,
            stageIntervals: [.init(stage: "core", start: previousStart, end: previousEnd)]
        )
        let following = HealthMdContextSleepSession(
            sessionID: "sleep:following",
            start: followingStart,
            end: followingEnd,
            classification: .overnight,
            completeness: .complete,
            stageIntervals: [.init(stage: "core", start: followingStart, end: followingEnd)]
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
        try await store.upsert([
            day("2026-07-01", sleepSessions: [previous]),
            day("2026-07-02", workouts: [running, cycling], sleepSessions: [following]),
            day("2026-07-03")
        ])
        let response = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["workouts", "sleep_total"]),
                dates: .exact(.init(startDate: "2026-07-02", endDate: "2026-07-02")),
                operation: .workoutSleepAlignment(
                    window: .init(durationSeconds: 4 * 3_600),
                    workoutActivity: "running",
                    includeNaps: false
                ),
                page: .init(maxItems: 10, maxBytes: 100_000)
            ),
            detailLevel: .lossless
        )
        XCTAssertEqual(response.items.count, 1)
        guard case .workoutSleepAlignment(let alignment) = try XCTUnwrap(response.items.first) else {
            return XCTFail("Expected alignment")
        }
        XCTAssertEqual(alignment.precedingSleep?.sessionID, "sleep:previous")
        XCTAssertEqual(alignment.followingSleep?.sessionID, "sleep:following")
        XCTAssertEqual(alignment.status, .complete)
        XCTAssertEqual(response.metadata?["activity_excluded_workout_count"], .integer(1))
        XCTAssertTrue(response.limitations.contains { $0.code == "temporal_alignment_only" })
    }

    func testSleepSessionPagingUsesAdjacentDaysAndFailsClosedWithoutSleepScope() async throws {
        let (store, executor) = try makeSystem(metrics: [
            "sleep_total", "sleep_deep", "sleep_core", "heart_rate"
        ])
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let overnight = HealthMdContextSleepSession(
            sessionID: "sleep:overnight",
            start: start,
            end: start.addingTimeInterval(8 * 3_600),
            classification: .overnight,
            completeness: .complete,
            stageIntervals: [
                .init(stage: "deep", start: start, end: start.addingTimeInterval(2 * 3_600)),
                .init(stage: "core", start: start.addingTimeInterval(2 * 3_600), end: start.addingTimeInterval(8 * 3_600))
            ]
        )
        let nap = HealthMdContextSleepSession(
            sessionID: "sleep:nap",
            start: start.addingTimeInterval(-6 * 3_600),
            end: start.addingTimeInterval(-5 * 3_600),
            classification: .nap,
            completeness: .complete,
            stageIntervals: [
                .init(
                    stage: "core",
                    start: start.addingTimeInterval(-6 * 3_600),
                    end: start.addingTimeInterval(-5 * 3_600)
                )
            ]
        )
        try await store.upsert([
            day("2026-05-27", sleepSessions: [nap, overnight]),
            day("2026-05-28")
        ])

        let items = try await collectItems(
            executor: executor,
            metrics: .explicit(["sleep_total", "sleep_deep", "sleep_core", "heart_rate"]),
            dates: .exact(.init(startDate: "2026-05-27", endDate: "2026-05-27")),
            operation: .sleepSessionListing(
                window: .init(durationSeconds: 4 * 3_600),
                includeNaps: false
            ),
            maxItems: 1
        )
        XCTAssertEqual(items.count, 1)
        guard case .sleepSession(let session) = try XCTUnwrap(items.first) else {
            return XCTFail("Expected sleep session")
        }
        XCTAssertEqual(session.sessionID, "sleep:overnight")
        XCTAssertEqual(session.elapsedDurationSeconds, 4 * 3_600)
        XCTAssertEqual(session.stageDurationsSeconds["deep"], 2 * 3_600)
        XCTAssertEqual(session.stageDurationsSeconds["core"], 2 * 3_600)
        XCTAssertEqual(session.physiology.first?.metricID, "heart_rate")
        XCTAssertEqual(session.physiology.first?.status, .completeEmpty)

        await XCTAssertThrowsQueryError(.scopeViolation("sleep_sessions")) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .explicit(["steps"]),
                    dates: .allAvailable,
                    operation: .sleepSessionListing(window: nil, includeNaps: true)
                ),
                detailLevel: .summary,
                evidenceScope: .init(allowedMetricIDs: ["steps"])
            )
        }
    }

    // MARK: - Helpers

    private func makeSystem(
        metrics: Set<String>,
        allowsEvidenceValues: Bool = false
    ) throws -> (EncryptedHealthContextStore, EncryptedHealthContextQueryExecutor) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptedQueryExecutorTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let provider = InMemoryHealthContextEncryptionKeyProvider(keyData: Data(repeating: 0x8a, count: 32))
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: provider)
        let executor = EncryptedHealthContextQueryExecutor(
            store: store,
            evidenceScope: .init(
                allowedMetricIDs: metrics,
                allowedDetailIDs: ["duration"],
                allowsWorkouts: true,
                allowsEvidenceValues: allowsEvidenceValues
            ),
            now: { Date(timeIntervalSince1970: 1) }
        )
        return (store, executor)
    }

    private func collectItems(
        executor: EncryptedHealthContextQueryExecutor,
        metrics: HealthMdMetricSelection,
        dates: HealthMdDateSelection,
        operation: HealthMdQueryOperation,
        maxItems: Int,
        detailLevel: HealthMdQueryDetailLevel = .summary
    ) async throws -> [HealthMdQueryItem] {
        var cursor: String?
        var result: [HealthMdQueryItem] = []
        repeat {
            let response = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: metrics,
                    dates: dates,
                    operation: operation,
                    page: .init(maxItems: maxItems, maxBytes: HealthMdPageControls.maximumBytes, cursor: cursor)
                ),
                detailLevel: detailLevel
            )
            XCTAssertLessThanOrEqual(response.items.count, maxItems)
            result.append(contentsOf: response.items)
            cursor = response.nextCursor
        } while cursor != nil
        return result
    }

    private func day(
        _ ownerDate: String,
        status: HealthMdAvailabilityStatus = .available,
        metrics: [HealthMdContextMetric] = [],
        workouts: [HealthMdContextWorkout] = [],
        sleepSessions: [HealthMdContextSleepSession] = [],
        evidence: [HealthMdContextEvidence] = []
    ) -> HealthMdCompactContextDay {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return .init(
            ownerDate: ownerDate,
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZone: "UTC",
            source: .init(schema: "healthmd.health_data", schemaVersion: 7, digest: "source-\(ownerDate)"),
            status: status,
            metrics: metrics,
            workouts: workouts,
            sleepSessions: sleepSessions,
            evidence: evidence
        )
    }

    private func metric(
        _ metricID: String,
        id: String,
        value: HealthMdQueryValue? = .count(1),
        status: HealthMdAvailabilityStatus = .available,
        evidenceIDs: [String] = []
    ) -> HealthMdContextMetric {
        .init(
            observationID: id,
            metricID: metricID,
            displayName: metricID,
            value: value,
            status: status,
            evidenceIDs: evidenceIDs
        )
    }

    private func contextEvidence(
        id: String,
        day: String,
        sourceID: String,
        value: HealthMdQueryValue,
        metricIDs: [String]
    ) -> HealthMdContextEvidence {
        .init(
            reference: .init(
                evidenceID: id,
                locator: .summaryKey(ownerDate: day, key: id),
                source: .init(schema: "healthmd.health_data", schemaVersion: 7, digest: "source-\(day)"),
                sourceID: sourceID
            ),
            value: value,
            metricIDs: metricIDs
        )
    }

    private func ownerDates(count: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<count).map {
            formatter.string(from: calendar.date(byAdding: .day, value: $0, to: start)!)
        }
    }

    private func XCTAssertThrowsQueryError(
        _ expected: HealthMdQueryContractError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as HealthMdQueryContractError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
#endif
