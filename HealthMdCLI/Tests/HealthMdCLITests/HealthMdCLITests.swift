import Foundation
import XCTest
@testable import healthmd

final class HealthMdCLITests: XCTestCase {
    func testDownloadedStrictRawHeadersRequireDigestAndRequestedRange() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-stream-test-\(UUID().uuidString).json")
        let response: [String: Any] = [
            "status": "partial_success",
            "raw_result": [
                "schema": "healthmd.raw_result",
                "schema_version": 1,
                "profile": "canonical_source_records_v1",
                "created_at": "2026-01-03T00:00:00Z",
                "source_device_name": "iPhone",
                "date_range": ["start": "2026-01-01", "end": "2026-01-02"],
                "total_requested_days": 2,
                "days": [
                    ["date": "2026-01-01", "status": "failed"],
                    ["date": "2026-01-02", "status": "failed"]
                ],
                "capture_summary": ["retained_day_count": 0, "missing_day_count": 0],
                "missing_dates": []
            ]
        ]
        try JSONSerialization.data(withJSONObject: response).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try sha256OfFile(url)
        let result = DownloadedHTTPResult(
            statusCode: 200,
            fileURL: url,
            headers: [
                "x-healthmd-export-status": "partial_success",
                "x-healthmd-raw-schema": "healthmd.raw_result/1",
                "x-healthmd-raw-validated": "1",
                "x-healthmd-body-sha256": digest,
                "x-healthmd-raw-date-start": "2026-01-01",
                "x-healthmd-raw-date-end": "2026-01-02",
                "x-healthmd-raw-total-days": "2"
            ]
        )
        XCTAssertTrue(result.isValidatedStrictRawResponse)
        XCTAssertTrue(result.bodyDigestIsValid)
        XCTAssertTrue(result.matchesRequestedRange(start: "2026-01-01", end: "2026-01-02", totalDays: 2))
        XCTAssertFalse(result.matchesRequestedRange(start: "2026-01-01", end: "2026-01-03", totalDays: 3))
        XCTAssertEqual(
            try streamingStrictRawValidationIssues(
                fileURL: url,
                expectedDates: ["2026-01-01", "2026-01-02"]
            ),
            []
        )

        try Data("{\"status\":\"success\"}".utf8).write(to: url, options: .atomic)
        XCTAssertFalse(
            try streamingStrictRawValidationIssues(fileURL: url, expectedDates: ["2026-01-01"]).isEmpty
        )
    }

    func testStreamingStrictRawValidatorRejectsAmbiguousAndMalformedJSON() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-adversarial-stream-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let valid = """
        {"status":"partial_success","raw_result":{"schema":"healthmd.raw_result","schema_version":1,"profile":"canonical_source_records_v1","created_at":"2026-01-02T00:00:00Z","source_device_name":"iPhone","date_range":{"start":"2026-01-01","end":"2026-01-01"},"total_requested_days":1,"days":[{"date":"2026-01-01","status":"failed"}],"capture_summary":{"retained_day_count":0,"missing_day_count":0},"missing_dates":[]}}
        """
        let expectedDates = ["2026-01-01"]

        try Data(valid.utf8).write(to: url)
        XCTAssertEqual(try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates), [])

        let missingIdentity = valid
            .replacingOccurrences(of: "\"created_at\":\"2026-01-02T00:00:00Z\",", with: "")
            .replacingOccurrences(of: "\"source_device_name\":\"iPhone\",", with: "")
        try Data(missingIdentity.utf8).write(to: url)
        let identityIssues = try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates)
        XCTAssertTrue(identityIssues.contains("raw_result_created_at_missing"))
        XCTAssertTrue(identityIssues.contains("raw_result_source_device_name_missing"))

        let duplicateSchema = valid.replacingOccurrences(
            of: "\"schema\":\"healthmd.raw_result\"",
            with: "\"schema\":\"wrong\",\"schema\":\"healthmd.raw_result\""
        )
        try Data(duplicateSchema.utf8).write(to: url)
        XCTAssertThrowsError(try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates))

        let malformedNumber = valid.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":01")
        try Data(malformedNumber.utf8).write(to: url)
        XCTAssertThrowsError(try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates))

        let oversizedSchema = valid.replacingOccurrences(
            of: "healthmd.raw_result",
            with: String(repeating: "x", count: 9_000)
        )
        try Data(oversizedSchema.utf8).write(to: url)
        XCTAssertThrowsError(try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates))

        let deeplyNested = String(valid.dropLast())
            + ",\"ignored\":" + String(repeating: "[", count: 300)
            + "null" + String(repeating: "]", count: 300) + "}"
        try Data(deeplyNested.utf8).write(to: url)
        XCTAssertThrowsError(try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates))

        var invalidUTF8 = Data(String(valid.dropLast()).utf8)
        invalidUTF8.append(Data(",\"ignored\":\"".utf8))
        invalidUTF8.append(0xff)
        invalidUTF8.append(Data("\"}".utf8))
        try invalidUTF8.write(to: url)
        XCTAssertThrowsError(try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates))

        let largeIgnoredValue = String(valid.dropLast())
            + ",\"ignored\":\"" + String(repeating: "z", count: 2 * 1_024 * 1_024) + "\"}"
        try Data(largeIgnoredValue.utf8).write(to: url)
        XCTAssertEqual(try streamingStrictRawValidationIssues(fileURL: url, expectedDates: expectedDates), [])
    }

    func testDurableJobCommandsParseUUIDTimeoutOutputAndPartialPolicy() throws {
        let jobID = UUID()
        guard case .status(let parsedStatusID) = try parse([
            "status", "--job", jobID.uuidString
        ]).command else { return XCTFail("Expected job status command") }
        XCTAssertEqual(parsedStatusID, jobID)

        guard case .resume(let parsedResumeID, let options) = try parse([
            "resume", jobID.uuidString, "--timeout", "120", "--output", "/tmp/result.json", "--allow-partial"
        ]).command else { return XCTFail("Expected resume command") }
        XCTAssertEqual(parsedResumeID, jobID)
        XCTAssertEqual(options.timeout, 120)
        XCTAssertEqual(options.outputPath, "/tmp/result.json")
        XCTAssertTrue(options.allowPartial)

        guard case .cancel(let parsedCancelID) = try parse([
            "cancel", jobID.uuidString
        ]).command else { return XCTFail("Expected cancel command") }
        XCTAssertEqual(parsedCancelID, jobID)
        XCTAssertThrowsError(try parse(["resume", "not-a-uuid"]))
        XCTAssertThrowsError(try parseResumeOptions(["--timeout", "901"]))
    }

    func testCLIBaseURLIsCanonicalAndRestrictedToHTTPLoopback() throws {
        XCTAssertEqual(
            try parse(["--base-url", "http://LOCALHOST:17645/", "status"]).baseURL,
            "http://localhost:17645"
        )
        XCTAssertEqual(
            try parse(["--base-url", "http://[::1]:17645", "status"]).baseURL,
            "http://[::1]:17645"
        )
        for value in [
            "https://127.0.0.1:17645",
            "http://example.com:17645",
            "http://user:secret@127.0.0.1:17645",
            "http://127.0.0.1:17645/path",
            "http://127.0.0.1:17645?query=1"
        ] {
            XCTAssertThrowsError(try parse(["--base-url", value, "status"]), value)
        }
    }

    func testDoctorParsesAndBuildsMachineReadableReadinessEnvelope() throws {
        guard case .doctor = try parse(["doctor"]).command else {
            return XCTFail("Expected doctor command")
        }
        guard case .doctor = try parse(["doctor", "--json"]).command else {
            return XCTFail("Expected explicit JSON doctor command")
        }
        XCTAssertThrowsError(try parse(["doctor", "unexpected"]))

        let publicStatus: [String: Any] = [
            "mac_app": "running",
            "iphone": ["connected": false]
        ]
        let checks = publicDoctorChecks(publicStatus)
        XCTAssertEqual(checks.first?["code"] as? String, "mac_app")
        XCTAssertEqual(checks.first?["status"] as? String, "ready")
        XCTAssertTrue(checks.contains {
            $0["code"] as? String == "iphone_connection"
                && $0["status"] as? String == "warning"
                && $0["blocking"] as? Bool == false
        })

        let envelope = makeCLIDoctorEnvelope(
            status: "action_required",
            publicStatus: publicStatus,
            localReadiness: nil,
            checks: checks,
            nextActions: [["code": "connect_iphone_for_fresh_data"]]
        )
        XCTAssertEqual(envelope["schema"] as? String, "healthmd.cli_doctor")
        XCTAssertEqual(envelope["schema_version"] as? Int, 1)
        XCTAssertEqual(envelope["status"] as? String, "action_required")
        XCTAssertTrue(envelope["local_readiness"] is NSNull)
    }

    func testLowLevelAgentCommandsUseDirectBodiesAndLocalJobs() throws {
        let body = "{\"request\":{\"schema\":\"healthmd.query_request\"}}"
        let parsed = try parse(["agent", "query", "--json", body])
        guard case .agent(.query(let data)) = parsed.command else {
            return XCTFail("Expected agent query command")
        }
        XCTAssertNotNil(
            (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["request"]
        )

        let jobID = UUID()
        guard case .agent(.jobResume(let parsedID, let timeout)) = try parse([
            "agent", "job", "resume", jobID.uuidString, "--timeout", "120"
        ]).command else { return XCTFail("Expected local job resume") }
        XCTAssertEqual(parsedID, jobID)
        XCTAssertEqual(timeout, 120)

        XCTAssertThrowsError(try parse(["--token", "obsolete", "status"]))
        XCTAssertThrowsError(try parse(["agent", "pair"]))
        XCTAssertThrowsError(try parse(["agent", "profiles"]))
        XCTAssertThrowsError(try parseAgentCommand(["query"]))
        XCTAssertThrowsError(try parseAgentCommand(["query", "--json", "[]"]))
        XCTAssertThrowsError(try parseAgentCommand(["job", "status", "not-a-uuid"]))
    }

    func testHighLevelMetricCommandsParseScopesDatesAndOutputPolicy() throws {
        guard case .metrics(let metricsOptions) = try parse([
            "metrics", "list", "--category", "Sleep"
        ]).command else { return XCTFail("Expected metrics command") }
        XCTAssertEqual(metricsOptions.category, "Sleep")

        guard case .query(let options) = try parse([
            "query",
            "--metric", "sleep_total",
            "--category", "Sleep",
            "--from", "2026-07-21",
            "--to", "2026-07-22",
            "--detail", "lossless",
            "--timeout", "120",
            "--allow-partial",
            "--output", "/tmp/sleep-query.json",
            "--iphone"
        ]).command else { return XCTFail("Expected query command") }
        XCTAssertEqual(options.metricIDs, ["sleep_total"])
        XCTAssertEqual(options.categories, ["Sleep"])
        XCTAssertEqual(options.fromDate, "2026-07-21")
        XCTAssertEqual(options.toDate, "2026-07-22")
        XCTAssertEqual(options.detail, .lossless)
        XCTAssertEqual(options.timeout, 120)
        XCTAssertTrue(options.allowPartial)
        XCTAssertEqual(options.outputPath, "/tmp/sleep-query.json")
        XCTAssertFalse(options.cached)

        XCTAssertThrowsError(try parse(["query", "--metric", "sleep_total"]))
        XCTAssertThrowsError(try parse([
            "query", "--metric", "sleep_total", "--yesterday", "--all"
        ]))
        XCTAssertThrowsError(try parse([
            "query", "--metric", "sleep_total", "--from", "2026-07-21"
        ]))
        XCTAssertThrowsError(try parse([
            "query", "--metric", "sleep_total", "--yesterday", "--timeout", "901"
        ]))
    }

    func testTypedWorkoutCoverageComparisonAndTrainingCommandsBuildOperations() throws {
        guard case .query(let sleep) = try parse([
            "sleep", "sessions", "--last-nights", "14",
            "--window", "first:4h", "--physiology-metric", "heart_rate",
            "--cached"
        ]).command else { return XCTFail("Expected sleep session query") }
        let sleepStageMetrics = Set([
            "sleep_total", "sleep_bedtime", "sleep_wake", "sleep_deep",
            "sleep_rem", "sleep_core", "sleep_awake", "sleep_in_bed"
        ])
        XCTAssertEqual(Set(sleep.metricIDs), sleepStageMetrics.union(["heart_rate"]))
        XCTAssertEqual(sleep.lastDays, 14)
        XCTAssertEqual(sleep.detail, .lossless)
        XCTAssertTrue(sleep.cached)
        XCTAssertEqual(
            sleep.operation,
            .sleepSessions(windowSeconds: 14_400, includeNaps: false)
        )
        let sleepBody = makeMetricQueryRequestBody(
            dates: ["type": "all_available"],
            metricIDs: sleep.metricIDs,
            detail: sleep.detail,
            operation: sleep.operation
        )
        let sleepRequest = try XCTUnwrap(sleepBody["request"] as? [String: Any])
        let sleepOperation = try XCTUnwrap(sleepRequest["operation"] as? [String: Any])
        XCTAssertEqual(sleepOperation["type"] as? String, "sleep_session_listing")
        XCTAssertEqual(
            (sleepOperation["window"] as? [String: Any])?["duration_seconds"] as? Double,
            14_400
        )
        XCTAssertThrowsError(try parse([
            "sleep", "sessions", "--last-nights", "14", "--window", "rolling:4h"
        ]))

        guard case .query(let alignment) = try parse([
            "training", "align", "--last", "14", "--workout", "running",
            "--sleep-window", "first:4h", "--physiology-metric", "heart_rate"
        ]).command else { return XCTFail("Expected workout/sleep alignment") }
        XCTAssertEqual(
            Set(alignment.metricIDs),
            sleepStageMetrics.union(["workouts", "heart_rate"])
        )
        XCTAssertEqual(alignment.detail, .lossless)
        XCTAssertEqual(
            alignment.operation,
            .workoutSleepAlignment(
                windowSeconds: 14_400,
                workoutActivity: "running",
                includeNaps: false
            )
        )
        let alignmentBody = makeMetricQueryRequestBody(
            dates: ["type": "all_available"],
            metricIDs: alignment.metricIDs,
            detail: alignment.detail,
            operation: alignment.operation
        )
        let alignmentRequest = try XCTUnwrap(alignmentBody["request"] as? [String: Any])
        let alignmentOperation = try XCTUnwrap(alignmentRequest["operation"] as? [String: Any])
        XCTAssertEqual(alignmentOperation["type"] as? String, "workout_sleep_alignment")
        XCTAssertEqual(alignmentOperation["workout_activity"] as? String, "running")

        guard case .query(let workouts) = try parse([
            "workouts", "--last", "14", "--cached"
        ]).command else { return XCTFail("Expected workouts query") }
        XCTAssertEqual(workouts.metricIDs, ["workouts"])
        XCTAssertEqual(workouts.lastDays, 14)
        XCTAssertTrue(workouts.cached)
        XCTAssertEqual(workouts.operation, .workoutListing)

        guard case .query(let coverage) = try parse([
            "coverage", "--category", "Sleep", "--yesterday"
        ]).command else { return XCTFail("Expected coverage query") }
        XCTAssertEqual(coverage.categories, ["Sleep"])
        XCTAssertEqual(coverage.operation, .coverage)

        guard case .query(let comparison) = try parse([
            "compare",
            "--metric", "steps:sum",
            "--metric", "resting_heart_rate:average",
            "--first-from", "2026-07-01", "--first-to", "2026-07-07",
            "--second-from", "2026-07-08", "--second-to", "2026-07-14",
            "--cached"
        ]).command else { return XCTFail("Expected comparison query") }
        XCTAssertEqual(comparison.fromDate, "2026-07-01")
        XCTAssertEqual(comparison.toDate, "2026-07-14")
        XCTAssertEqual(Set(comparison.metricIDs), Set(["steps", "resting_heart_rate"]))
        guard case .periodComparison(
            let firstStart, let firstEnd, let secondStart, let secondEnd, let aggregations
        ) = comparison.operation else { return XCTFail("Expected period comparison operation") }
        XCTAssertEqual([firstStart, firstEnd], ["2026-07-01", "2026-07-07"])
        XCTAssertEqual([secondStart, secondEnd], ["2026-07-08", "2026-07-14"])
        XCTAssertEqual(aggregations.map(\.metricID), ["resting_heart_rate", "steps"])

        guard case .query(let evidence) = try parse([
            "evidence", "training",
            "--category", "Sleep",
            "--workout-detail", "distance",
            "--workout-detail", "power_average",
            "--last", "14"
        ]).command else { return XCTFail("Expected training evidence query") }
        XCTAssertTrue(evidence.metricIDs.contains("workouts"))
        XCTAssertEqual(evidence.categories, ["Sleep"])
        XCTAssertEqual(evidence.detail, .lossless)
        XCTAssertEqual(
            evidence.operation,
            .trainingEvidence(detailIDs: ["distance", "power_average"])
        )

        let body = makeMetricQueryRequestBody(
            dates: ["type": "all_available"],
            metricIDs: comparison.metricIDs,
            detail: comparison.detail,
            operation: comparison.operation
        )
        let request = try XCTUnwrap(body["request"] as? [String: Any])
        let operation = try XCTUnwrap(request["operation"] as? [String: Any])
        XCTAssertEqual(operation["type"] as? String, "period_comparison")
        XCTAssertEqual((operation["aggregations"] as? [[String: String]])?.count, 2)

        XCTAssertThrowsError(try parse([
            "compare", "--metric", "steps:guessed",
            "--first-from", "2026-07-01", "--first-to", "2026-07-07",
            "--second-from", "2026-07-08", "--second-to", "2026-07-14"
        ]))
        XCTAssertThrowsError(try parse([
            "compare", "--metric", "steps:sum", "--metric", "steps:average",
            "--first-from", "2026-07-01", "--first-to", "2026-07-07",
            "--second-from", "2026-07-08", "--second-to", "2026-07-14"
        ]))
    }

    func testMetricCatalogFilteringAndSelectionExpansionAreDeterministic() throws {
        let catalog: [String: Any] = [
            "schema": "healthmd.metric_catalog",
            "schema_version": 1,
            "metrics": [
                ["id": "steps", "name": "Steps", "category": "Activity"],
                ["id": "sleep_total", "name": "Total Sleep", "category": "Sleep"],
                ["id": "sleep_deep", "name": "Deep Sleep", "category": "Sleep"]
            ]
        ]
        let filtered = try XCTUnwrap(filteredMetricCatalog(catalog, category: "sleep"))
        let filteredMetrics = try XCTUnwrap(filtered["metrics"] as? [[String: Any]])
        XCTAssertEqual(filteredMetrics.compactMap { $0["id"] as? String }, ["sleep_total", "sleep_deep"])
        XCTAssertNil(filteredMetricCatalog(catalog, category: "Unknown"))

        let resolved = resolveRequestedMetricIDs(
            catalog,
            directMetricIDs: ["steps", "sleep_total", "steps"],
            categories: ["SLEEP"]
        )
        XCTAssertEqual(resolved.metricIDs, ["sleep_deep", "sleep_total", "steps"])
        XCTAssertNil(resolved.failure)

        let unknown = resolveRequestedMetricIDs(
            catalog,
            directMetricIDs: ["future_metric"],
            categories: ["Recovery"]
        )
        XCTAssertNil(unknown.metricIDs)
        XCTAssertEqual(unknown.failure?["code"] as? String, "unknown_metric_selection")
    }

    func testMetricQueryRequiresRenamedRequestScopedContextCapability() {
        XCTAssertTrue(supportsRequestScopedContextAcquisition([
            "request_scoped_context_acquisition": true
        ]))
        XCTAssertFalse(supportsRequestScopedContextAcquisition([
            "scoped_fresh_acquisition": true
        ]))
        XCTAssertFalse(supportsRequestScopedContextAcquisition([:]))
    }

    func testMetricQueryBuildsNarrowRefreshAndTypedQueryBodies() throws {
        let options = try parseMetricQueryOptions([
            "--metric", "sleep_total",
            "--from", "2026-07-21",
            "--to", "2026-07-22"
        ])
        let dates = try resolveMetricQueryDateSelection(options)
        XCTAssertEqual(dates["type"] as? String, "exact")
        let range = try XCTUnwrap(dates["range"] as? [String: String])
        XCTAssertEqual(range["start_date"], "2026-07-21")
        XCTAssertEqual(range["end_date"], "2026-07-22")

        let refresh = makeMetricRefreshRequestBody(
            dates: dates,
            metricIDs: ["sleep_deep", "sleep_total"],
            detail: .summary,
            timeout: 300
        )
        XCTAssertNil(refresh["grant_id"])
        XCTAssertNil(refresh["profile"])
        XCTAssertEqual(refresh["detail_level"] as? String, "summary")
        XCTAssertEqual(
            (refresh["metrics"] as? [String: Any])?["metric_ids"] as? [String],
            ["sleep_deep", "sleep_total"]
        )
        let refreshSources = try XCTUnwrap(refresh["sources"] as? [String: Any])
        XCTAssertEqual(refreshSources["source_ids"] as? [String], ["apple_health"])

        let query = makeMetricQueryRequestBody(
            dates: dates,
            metricIDs: ["sleep_total"],
            detail: .lossless
        )
        XCTAssertNil(query["grant_id"])
        XCTAssertNil(query["profile"])
        XCTAssertEqual(query["detail_level"] as? String, "lossless")
        let request = try XCTUnwrap(query["request"] as? [String: Any])
        XCTAssertEqual(
            (request["operation"] as? [String: Any])?["type"] as? String,
            "source_record_listing"
        )
        XCTAssertEqual((request["page"] as? [String: Any])?["max_items"] as? Int, 1_000)
    }

    func testMetricQueryBodiesCarryCompleteRequestScopeDirectly() throws {
        let body = makeMetricRefreshRequestBody(
            dates: ["type": "all_available"],
            metricIDs: ["sleep_total"],
            detail: .summary,
            timeout: 300
        )
        XCTAssertNotNil(body["dates"])
        XCTAssertNotNil(body["metrics"])
        XCTAssertNotNil(body["sources"])
        XCTAssertNil(body["grant_id"])
        XCTAssertNil(body["profile"])
    }

    func testMetricQueryResponseValidationRequiresV1AndPreservesPagination() {
        let response: [String: Any] = [
            "schema": "healthmd.query_response",
            "schema_version": 1,
            "items": [],
            "coverage": [:],
            "sources": [],
            "evidence": [],
            "limitations": [],
            "next_cursor": "opaque-cursor"
        ]
        XCTAssertTrue(isValidMetricQueryResponse(response))
        XCTAssertEqual(metricQueryNextCursor(response), "opaque-cursor")

        var wrongVersion = response
        wrongVersion["schema_version"] = 2
        XCTAssertFalse(isValidMetricQueryResponse(wrongVersion))
        var missingCursor = response
        missingCursor.removeValue(forKey: "next_cursor")
        XCTAssertFalse(isValidMetricQueryResponse(missingCursor))
    }

    func testMetricQueryEnvelopeAndPartialExitPolicy() {
        let envelope = makeMetricQueryEnvelope(
            status: "partial_success",
            requestedMetricIDs: ["sleep_total"],
            acquisition: ["status": "partial_success"],
            query: ["schema": "healthmd.query_response"],
            error: nil,
            operation: "sleep_session_listing",
            requestedScopeStatus: "success",
            corpusStatus: "partial_success",
            unrelatedSkips: [["identifier": "WorkoutKitScheduledWorkoutPlan"]]
        )
        XCTAssertEqual(envelope["schema"] as? String, "healthmd.cli_metric_query")
        XCTAssertEqual(envelope["status"] as? String, "partial_success")
        XCTAssertEqual(envelope["operation"] as? String, "sleep_session_listing")
        XCTAssertEqual(envelope["requested_scope_status"] as? String, "success")
        XCTAssertEqual(envelope["corpus_status"] as? String, "partial_success")
        XCTAssertEqual((envelope["unrelated_skips"] as? [Any])?.count, 1)
        XCTAssertEqual(requestedScopeStatus(forCoverageStatus: "available"), "success")
        XCTAssertEqual(requestedScopeStatus(forCoverageStatus: "complete_empty"), "success")
        XCTAssertEqual(requestedScopeStatus(forCoverageStatus: "partial"), "partial_success")
        XCTAssertEqual(requestedScopeStatus(forCoverageStatus: "not_synchronized"), "failure")
        XCTAssertEqual(requestedScopeStatus(forQueryPages: [
            queryPage(nextCursor: "next", coverageStatus: "available"),
            queryPage(nextCursor: nil, coverageStatus: "partial")
        ]), "partial_success")
        let completion = metricAcquisitionCompletion([
            "status": "partial_success",
            "corpus_status": "partial_success",
            "requested_scope_status": "success",
            "unrelated_skips": [["identifier": "WorkoutKitScheduledWorkoutPlan"]]
        ])
        XCTAssertTrue(completion.corpusIsTerminalSuccess)
        XCTAssertTrue(completion.scopeIsUsable)
        XCTAssertEqual(completion.requestedScopeStatus, "success")
        XCTAssertEqual(completion.unrelatedSkips.count, 1)
        XCTAssertEqual(metricQueryExitCode(status: "partial_success", allowPartial: false), 1)
        XCTAssertEqual(metricQueryExitCode(status: "partial_success", allowPartial: true), 0)
        XCTAssertEqual(metricQueryExitCode(status: "success", allowPartial: false), 0)
        XCTAssertEqual(metricQueryExitCode(status: "failure", allowPartial: true), 1)
    }

    func testCredentialAndProfileFlagsAreRejectedAsRemoved() throws {
        XCTAssertThrowsError(try parse(["--token", "obsolete", "status"]))
        XCTAssertThrowsError(try parse(["--token-file", "/tmp/token", "status"]))
        XCTAssertThrowsError(try parse(["agent", "pair"]))
        XCTAssertThrowsError(try parse(["agent", "unpair"]))
        XCTAssertThrowsError(try parse(["agent", "profiles"]))
        XCTAssertThrowsError(try parse([
            "query", "--metric", "sleep_total", "--yesterday", "--grant", UUID().uuidString
        ]))
    }

    func testAllPagesTraversalReceiptTableAndCoverageReuseAreDeterministic() async throws {
        let parsed = try parse([
            "query", "--metric", "sleep_total", "--last", "14",
            "--all-pages", "--progress-json", "--reuse-covered", "--format", "table"
        ])
        guard case .query(let options) = parsed.command else {
            return XCTFail("Expected query")
        }
        XCTAssertTrue(options.allPages)
        XCTAssertTrue(options.progressJSON)
        XCTAssertTrue(options.reuseCovered)
        XCTAssertEqual(options.outputFormat, .table)
        XCTAssertThrowsError(try parse([
            "query", "--metric", "sleep_total", "--last", "14",
            "--cached", "--reuse-covered"
        ]))

        let sequence = MetricPageSequence()
        let body = makeMetricQueryRequestBody(
            dates: ["type": "all_available"],
            metricIDs: ["sleep_total"],
            detail: .summary
        )
        let traversal = try await requestMetricQueryPages(
            path: "/v1/agent/query",
            initialBody: body,
            baseURL: "http://127.0.0.1:1",
            timeout: 10,
            allPages: true,
            progressJSON: false,
            requestPage: { request in try await sequence.response(for: request) }
        )
        XCTAssertNil(traversal.failure)
        XCTAssertTrue(traversal.traversalComplete)
        XCTAssertEqual(traversal.pages.count, 3)
        let observedCursors = await sequence.cursors()
        XCTAssertEqual(observedCursors, [nil, "cursor-1", "cursor-2"])

        let receipt = makeMetricQueryReceipt(
            operation: "metric_series",
            requestedMetricIDs: ["sleep_total"],
            pages: traversal.pages,
            traversalComplete: traversal.traversalComplete,
            acquisitionMode: "cached",
            outputFormat: .table
        )
        XCTAssertEqual(receipt["page_count"] as? Int, 3)
        XCTAssertEqual(receipt["item_count"] as? Int, 3)
        XCTAssertEqual(receipt["traversal_complete"] as? Bool, true)
        let table = renderMetricQueryTable(
            pages: traversal.pages,
            receipt: receipt,
            status: "success"
        )
        XCTAssertTrue(table.contains("type\tidentity"))
        XCTAssertTrue(table.contains("sleep_total"))
        XCTAssertTrue(table.contains("pages=3"))
        XCTAssertTrue(table.contains("table_projection=lossy"))
        XCTAssertTrue(table.contains("diagnostics_json="))

        let limitedSequence = MetricPageSequence()
        let limited = try await requestMetricQueryPages(
            path: "/v1/agent/query",
            initialBody: body,
            baseURL: "http://127.0.0.1:1",
            timeout: 10,
            allPages: true,
            progressJSON: false,
            maximumAggregateBytes: 1_000_000,
            maximumPages: 2,
            requestPage: { request in try await limitedSequence.response(for: request) }
        )
        XCTAssertEqual(limited.failure?.statusCode, 413)
        XCTAssertEqual(limited.pages.count, 2)
        XCTAssertFalse(limited.traversalComplete)
        XCTAssertTrue(metricCoveragePagesAreComplete([
            queryPage(nextCursor: nil, coverageStatus: "available")
        ]))
        XCTAssertTrue(metricCoveragePagesAreComplete([
            queryPage(nextCursor: nil, coverageStatus: "complete_empty")
        ]))
        XCTAssertFalse(metricCoveragePagesAreComplete([
            queryPage(nextCursor: nil, coverageStatus: "partial")
        ]))
        var mixedComplete = queryPage(nextCursor: nil, coverageStatus: "partial")
        mixedComplete["coverage"] = [
            "status": "partial",
            "missing": [["status": "complete_empty"]]
        ]
        XCTAssertTrue(metricCoveragePagesAreComplete([mixedComplete]))
        var missingOwnerDate = queryPage(nextCursor: nil, coverageStatus: "available")
        missingOwnerDate["metadata"] = ["requested_scope_status": "partial_success"]
        XCTAssertFalse(metricCoveragePagesAreComplete([missingOwnerDate]))
    }

    func testFileExportCanPushMetricAndDetailSelectionToIPhone() throws {
        let parsed = try parse([
            "export", "--last", "7", "--category", "Sleep", "--detail", "summary"
        ])
        guard case .export(let options) = parsed.command else {
            return XCTFail("Expected export command")
        }
        XCTAssertTrue(options.selectionRequested)
        XCTAssertFalse(options.raw)
        let body = makeExportRequestBody(
            options: options,
            startDate: "2026-07-01",
            endDate: "2026-07-07"
        )
        XCTAssertEqual(body["response_mode"] as? String, "write_files")
        XCTAssertNil(body["raw_profile"])
        let selection = try XCTUnwrap(body["canonical_selection"] as? [String: Any])
        XCTAssertEqual(selection["categories"] as? [String], ["Sleep"])
        XCTAssertEqual(selection["detail_level"] as? String, "summary")
        XCTAssertThrowsError(try parse([
            "export", "--yesterday", "--metric", "steps", "--use-iphone-settings"
        ]))
        XCTAssertThrowsError(try parse([
            "export", "--yesterday", "--raw", "--metric", "steps"
        ]))
    }

    func testRawOutputPathIsAcceptedOnlyForStrictRawStreaming() throws {
        let parsed = try parse(["export", "--yesterday", "--raw", "--output", "/tmp/corpus.json"])
        guard case .export(let options) = parsed.command else {
            return XCTFail("Expected export command")
        }
        XCTAssertTrue(options.raw)
        XCTAssertEqual(options.outputPath, "/tmp/corpus.json")
        XCTAssertThrowsError(try parse(["export", "--yesterday", "--output", "/tmp/corpus.json"]))
    }

    func testRawParserRequestsStrictModeAndAllowPartial() throws {
        let parsed = try parse([
            "export", "--yesterday", "--raw", "--allow-partial", "--timeout", "120"
        ])
        guard case .export(let options) = parsed.command else {
            return XCTFail("Expected export command")
        }
        XCTAssertTrue(options.raw)
        XCTAssertTrue(options.allowPartial)
        XCTAssertEqual(options.timeout, 120)

        let body = makeExportRequestBody(
            options: options,
            startDate: "2026-07-14",
            endDate: "2026-07-14"
        )
        XCTAssertEqual(body["response_mode"] as? String, "raw_json")
        XCTAssertEqual(body["raw_profile"] as? String, "canonical_source_records_v1")
    }

    func testCanonicalExtractBuildsScopedHealthDataProjection() throws {
        let parsed = try parse([
            "extract", "--last", "7", "--object", "sleep",
            "--metric", "heart_rate_avg", "--field", "/heart/restingHeartRate",
            "--source", "apple_health", "--format", "jsonl", "--output", "/tmp/health.jsonl"
        ])
        guard case .extract(let options) = parsed.command else {
            return XCTFail("Expected extract command")
        }
        XCTAssertTrue(options.canonicalProjection)
        XCTAssertTrue(options.raw)
        XCTAssertEqual(options.detail, .summary)
        XCTAssertEqual(Set(options.metricIDs), ["heart_rate_avg"])
        XCTAssertEqual(Set(options.categories), ["Sleep"])
        XCTAssertEqual(options.objectPaths, ["/sleep"])
        XCTAssertEqual(options.fieldPointers, ["/heart/restingHeartRate"])
        XCTAssertEqual(options.extractionFormat, .jsonl)

        let body = makeExportRequestBody(
            options: options,
            startDate: "2026-07-01",
            endDate: "2026-07-07"
        )
        XCTAssertEqual(body["response_mode"] as? String, "raw_json")
        XCTAssertEqual(body["raw_profile"] as? String, "health_data_projection")
        let selection = try XCTUnwrap(body["canonical_selection"] as? [String: Any])
        XCTAssertEqual(selection["detail_level"] as? String, "summary")
        XCTAssertEqual(selection["source_ids"] as? [String], ["apple_health"])
        let archiveParsed = try parse([
            "extract", "--yesterday", "--metric", "workouts",
            "--object", "records", "--detail", "summary"
        ])
        guard case .extract(let archiveOptions) = archiveParsed.command else {
            return XCTFail("Expected archive extract command")
        }
        XCTAssertEqual(archiveOptions.detail, .lossless)
        XCTAssertThrowsError(try parse(["extract", "--yesterday", "--all-metrics", "--metric", "steps"]))
        XCTAssertThrowsError(try parse(["extract", "--yesterday", "--metric", "steps", "--source", "oura"]))
    }

    func testStreamingCanonicalProjectionFindsOnlyHealthDataDocuments() throws {
        let payload: [String: Any] = [
            "status": "success",
            "raw_result": [
                "schema": "healthmd.raw_result",
                "schema_version": 1,
                "profile": "health_data_projection",
                "canonical_selection": [
                    "metric_ids": ["sleep_total"],
                    "source_ids": ["apple_health"],
                    "detail_level": "summary",
                    "object_paths": ["/sleep"],
                    "field_pointers": []
                ],
                "created_at": "2026-07-22T00:00:00Z",
                "source_device_name": "iPhone",
                "date_range": ["start": "2026-07-20", "end": "2026-07-21"],
                "total_requested_days": 2,
                "days": [
                    [
                        "date": "2026-07-20", "status": "complete",
                        "health_data": [
                            "schema": "healthmd.health_data", "schema_version": 7,
                            "date": "2026-07-20", "type": "health-data",
                            "raw_capture_status": "not_requested", "sleep": ["total": 480],
                            "objects": [["value": 3]]
                        ]
                    ],
                    [
                        "date": "2026-07-21", "status": "complete_empty",
                        "health_data": [
                            "schema": "healthmd.health_data", "schema_version": 7,
                            "date": "2026-07-21", "type": "health-data",
                            "raw_capture_status": "not_requested"
                        ]
                    ]
                ],
                "capture_summary": ["retained_day_count": 2, "missing_day_count": 0],
                "missing_dates": []
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-extract-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(
            try streamingStrictRawValidationIssues(
                fileURL: url,
                expectedDates: ["2026-07-20", "2026-07-21"],
                expectedProfile: "health_data_projection"
            ),
            []
        )
        let metadata = try canonicalTransportMetadata(fileURL: url)
        XCTAssertEqual(metadata.profile, "health_data_projection")
        XCTAssertEqual(metadata.objectPaths, ["/sleep"])
        XCTAssertEqual(metadata.fieldPointers, [])
        let ranges = try canonicalHealthDataRanges(fileURL: url)
        XCTAssertEqual(ranges.count, 2)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var dates: [String] = []
        for range in ranges {
            try handle.seek(toOffset: UInt64(range.lowerBound))
            let document = try XCTUnwrap(try handle.read(upToCount: range.count))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: document) as? [String: Any])
            XCTAssertEqual(object["schema"] as? String, "healthmd.health_data")
            dates.append(try XCTUnwrap(object["date"] as? String))
        }
        XCTAssertEqual(dates, ["2026-07-20", "2026-07-21"])

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-output-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        var options = ExportOptions()
        options.canonicalProjection = true
        options.objectPaths = ["/sleep"]
        options.fieldPointers = ["/objects/0/value"]
        options.outputPath = outputURL.path
        try emitCanonicalHealthData(sourceURL: url, options: options)
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: outputURL)) as? [String: Any]
        )
        XCTAssertEqual(envelope["protocol"] as? String, "healthmd.extract_result")
        let projected = try XCTUnwrap(envelope["projections"] as? [[String: Any]])
        XCTAssertEqual(projected.count, 2)
        let firstSelections = try XCTUnwrap(projected[0]["selections"] as? [[String: Any]])
        let selectionsByPointer = Dictionary(
            uniqueKeysWithValues: firstSelections.compactMap { selection -> (String, [String: Any])? in
                guard let pointer = selection["pointer"] as? String else { return nil }
                return (pointer, selection)
            }
        )
        XCTAssertEqual(selectionsByPointer["/sleep"]?["status"] as? String, "available")
        XCTAssertEqual((selectionsByPointer["/sleep"]?["value"] as? [String: Any])?["total"] as? Int, 480)
        XCTAssertEqual(selectionsByPointer["/objects/0/value"]?["value"] as? Int, 3)
        XCTAssertNil(projected[0]["schema"], "A subtree projection must not claim to be a complete v7 document")
        let secondSelections = try XCTUnwrap(projected[1]["selections"] as? [[String: Any]])
        XCTAssertEqual(secondSelections.first?["status"] as? String, "complete_empty")
        let receipt = try XCTUnwrap(envelope["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["source_schema"] as? String, "healthmd.health_data")
        XCTAssertEqual((receipt["days"] as? [[String: Any]])?.count, 2)

        let fullOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-full-output-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fullOutputURL) }
        var fullOptions = ExportOptions()
        fullOptions.canonicalProjection = true
        fullOptions.outputPath = fullOutputURL.path
        try emitCanonicalHealthData(sourceURL: url, options: fullOptions)
        let fullEnvelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fullOutputURL)) as? [String: Any]
        )
        let healthData = try XCTUnwrap(fullEnvelope["health_data"] as? [[String: Any]])
        XCTAssertEqual(healthData.count, 2)
        XCTAssertEqual(healthData[0]["schema"] as? String, "healthmd.health_data")
        XCTAssertEqual(healthData[0]["schema_version"] as? Int, 7)
    }

    func testAllAvailableHistoryUsesDynamicDateSelectionWithoutFakeRange() throws {
        let parsed = try parse(["export", "--all", "--raw"])
        guard case .export(let options) = parsed.command else {
            return XCTFail("Expected export command")
        }
        XCTAssertTrue(options.allAvailable)

        let body = makeExportRequestBody(options: options, startDate: nil, endDate: nil)
        XCTAssertEqual(body["date_selection"] as? String, "all_available")
        XCTAssertNil(body["date_range"])
        XCTAssertThrowsError(try parse(["export", "--all", "--yesterday"]))
        XCTAssertThrowsError(try parse(["export", "--all", "--from", "2026-01-01", "--to", "2026-01-02"]))
    }

    func testParserRejectsUnsafeOrNonFiniteTimeouts() {
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "4"]))
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "901"]))
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "nan"]))
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "inf"]))
    }

    func testRawPartialRequiresAllowPartialForExitZero() {
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: "partial_success", isRaw: true, allowPartial: false),
            1
        )
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: "partial_success", isRaw: true, allowPartial: true),
            0
        )
    }

    func testFilePartialRetainsLegacyExitBehavior() {
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: "partial_success", isRaw: false, allowPartial: false),
            0
        )
        XCTAssertEqual(exportExitCode(httpStatusCode: 409, status: "failure", isRaw: true, allowPartial: true), 1)
    }

    func testStrictSuccessEnvelopeValidationAcceptsCurrentCompleteArchive() {
        let payload = makeStrictSuccessPayload()
        XCTAssertEqual(
            strictRawValidationIssues(payload: payload, expectedDates: ["2026-07-14"]),
            []
        )
    }

    func testMalformedLegacySuccessProducesMachineReadableFailure() throws {
        let legacy: [String: Any] = [
            "status": "success",
            "raw_data": ["records": []]
        ]
        let issues = strictRawValidationIssues(payload: legacy, expectedDates: ["2026-07-14"])
        XCTAssertEqual(issues, ["raw_result_missing"])

        let validation = validateStrictRawHTTPSuccess(
            payload: legacy,
            expectedDates: ["2026-07-14"]
        )
        XCTAssertFalse(validation.isValid, "The command path must return nonzero for this result")
        let failure = try XCTUnwrap(validation.outputPayload as? [String: Any])
        XCTAssertEqual(failure["status"] as? String, "failure")
        XCTAssertEqual(failure["error"] as? String, "invalid_strict_raw_success")
        let diagnostics = try XCTUnwrap(failure["diagnostics"] as? [String: Any])
        XCTAssertEqual(diagnostics["issues"] as? [String], ["raw_result_missing"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(failure))
    }

    func testStrictSuccessEnvelopeRejectsWrongDailyVersionAndMissingArchive() {
        var wrongVersion = makeStrictSuccessPayload()
        var rawResult = wrongVersion["raw_result"] as! [String: Any]
        var days = rawResult["days"] as! [[String: Any]]
        var healthData = days[0]["health_data"] as! [String: Any]
        healthData["schema_version"] = 5
        days[0]["health_data"] = healthData
        rawResult["days"] = days
        wrongVersion["raw_result"] = rawResult
        XCTAssertTrue(strictRawValidationIssues(
            payload: wrongVersion,
            expectedDates: ["2026-07-14"]
        ).contains("daily_schema_version_mismatch:2026-07-14"))

        var missingArchive = makeStrictSuccessPayload()
        rawResult = missingArchive["raw_result"] as! [String: Any]
        days = rawResult["days"] as! [[String: Any]]
        healthData = days[0]["health_data"] as! [String: Any]
        healthData.removeValue(forKey: "healthkit_record_archive")
        days[0]["health_data"] = healthData
        rawResult["days"] = days
        missingArchive["raw_result"] = rawResult
        XCTAssertTrue(strictRawValidationIssues(
            payload: missingArchive,
            expectedDates: ["2026-07-14"]
        ).contains("canonical_archive_missing:2026-07-14"))
    }

    func testRequestedISODateRangeBuildsExactInclusiveDates() {
        XCTAssertEqual(
            requestedISODateRange(startDate: "2026-07-14", endDate: "2026-07-16"),
            ["2026-07-14", "2026-07-15", "2026-07-16"]
        )
    }

    func testRequestedISODateRangeAllowsMultiYearCorpus() {
        let dates = requestedISODateRange(startDate: "2020-01-01", endDate: "2022-12-31")

        XCTAssertEqual(dates.count, 1_096)
        XCTAssertEqual(dates.first, "2020-01-01")
        XCTAssertEqual(dates.last, "2022-12-31")
    }

    private func makeStrictSuccessPayload() -> [String: Any] {
        [
            "status": "success",
            "raw_result": [
                "schema": "healthmd.raw_result",
                "schema_version": 1,
                "profile": "canonical_source_records_v1",
                "created_at": "2026-07-15T00:00:00Z",
                "source_device_name": "Test iPhone",
                "date_range": ["start": "2026-07-14", "end": "2026-07-14"],
                "total_requested_days": 1,
                "capture_summary": [
                    "retained_day_count": 1,
                    "missing_day_count": 0
                ],
                "missing_dates": [],
                "days": [[
                    "date": "2026-07-14",
                    "status": "complete_empty",
                    "health_data": [
                        "schema": "healthmd.health_data",
                        "schema_version": 7,
                        "healthkit_record_archive": [
                            "schema": "healthmd.healthkit_records",
                            "schema_version": 1
                        ]
                    ]
                ]]
            ]
        ]
    }
}

private func queryPage(
    nextCursor: String?,
    coverageStatus: String = "available",
    ownerDate: String = "2026-07-01"
) -> [String: Any] {
    [
        "schema": "healthmd.query_response",
        "schema_version": 1,
        "items": [[
            "type": "metric",
            "metric": [
                "metric_id": "sleep_total",
                "display_name": "Total Sleep",
                "owner_date": ownerDate,
                "value": ["type": "duration", "seconds": 28_800],
                "status": "available",
                "evidence": [],
                "limitations": []
            ]
        ]],
        "packet": NSNull(),
        "coverage": [
            "status": coverageStatus,
            "days_considered": 1,
            "days_with_values": coverageStatus == "available" ? 1 : 0,
            "missing": []
        ],
        "sources": [],
        "evidence": [],
        "next_cursor": nextCursor.map { $0 as Any } ?? NSNull(),
        "limitations": []
    ]
}

private actor MetricPageSequence {
    private var observedCursors: [String?] = []

    func response(for body: [String: Any]) throws -> HTTPResult {
        let request = body["request"] as? [String: Any]
        let page = request?["page"] as? [String: Any]
        let cursor = page?["cursor"] as? String
        observedCursors.append(cursor)
        let index = observedCursors.count
        let next = index == 1 ? "cursor-1" : (index == 2 ? "cursor-2" : nil)
        return HTTPResult(
            statusCode: 200,
            payload: queryPage(
                nextCursor: next,
                ownerDate: "2026-07-0\(index)"
            )
        )
    }

    func cursors() -> [String?] { observedCursors }
}
