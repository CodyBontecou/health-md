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
