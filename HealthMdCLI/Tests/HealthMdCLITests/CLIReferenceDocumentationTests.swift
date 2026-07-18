import Darwin
import Foundation
import XCTest
@testable import healthmd

final class CLIReferenceDocumentationTests: XCTestCase {
    func testGeneratedCLIReferenceDocumentationIsCurrent() throws {
        let artifacts = try CLIReferenceDocumentation.artifacts()

        for (name, data) in artifacts {
            if name.hasSuffix(".json") {
                XCTAssertNoThrow(
                    try JSONSerialization.jsonObject(with: data),
                    "\(name) must contain valid JSON"
                )
            } else {
                XCTAssertEqual(name, "exit-codes.md", "Only the linked exit-code table is non-JSON")
            }
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertFalse(text.contains("..."), "\(name) must not contain placeholder ellipses")
            XCTAssertFalse(text.localizedCaseInsensitiveContains("cody"), "\(name) must remain synthetic")
        }

        if let outputPath = ProcessInfo.processInfo.environment["HEALTHMD_CLI_REFERENCE_OUTPUT"] {
            try CLIReferenceDocumentation.write(artifacts, to: URL(fileURLWithPath: outputPath))
            return
        }

        let generatedDirectory = CLIReferenceDocumentation.generatedDirectory
        let fileManager = FileManager.default
        let committedNames = try fileManager.contentsOfDirectory(
            at: generatedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .map(\.lastPathComponent)
        .sorted()
        let expectedNames = artifacts.keys.sorted()

        XCTAssertEqual(
            committedNames,
            expectedNames,
            "Generated CLI reference artifact names drifted. Run scripts/generated-cli-reference-docs.sh update."
        )

        for name in expectedNames {
            let expected = try XCTUnwrap(artifacts[name])
            let committedURL = generatedDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: committedURL.path) else { continue }
            let committed = try Data(contentsOf: committedURL)
            XCTAssertEqual(
                committed,
                expected,
                "\(name) drifted. Run scripts/generated-cli-reference-docs.sh update."
            )
        }
    }

    func testGeneratedExamplesExerciseCLIContractLogic() throws {
        let objects = try CLIReferenceDocumentation.objects()

        let writeRequest = try object(named: "write-files-export-request.json", in: objects)
        XCTAssertEqual(writeRequest["response_mode"] as? String, "write_files")
        XCTAssertNil(writeRequest["raw_profile"])

        let rawRequest = try object(named: "strict-raw-export-request.json", in: objects)
        XCTAssertEqual(rawRequest["response_mode"] as? String, "raw_json")
        XCTAssertEqual(rawRequest["raw_profile"] as? String, "canonical_source_records_v1")

        let complete = try object(named: "strict-raw-complete-response.json", in: objects)
        XCTAssertEqual(
            strictRawValidationIssues(payload: complete, expectedDates: ["2026-03-15"]),
            []
        )
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: complete["status"] as? String, isRaw: true, allowPartial: false),
            0
        )

        let partial = try object(named: "strict-raw-partial-response.json", in: objects)
        XCTAssertEqual(
            strictRawValidationIssues(
                payload: partial,
                expectedDates: ["2026-03-15", "2026-03-16"]
            ),
            []
        )
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: partial["status"] as? String, isRaw: true, allowPartial: false),
            1
        )
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: partial["status"] as? String, isRaw: true, allowPartial: true),
            0
        )

        let malformed = try object(named: "invalid-strict-raw-success.json", in: objects)
        XCTAssertEqual(malformed["error"] as? String, "invalid_strict_raw_success")
        XCTAssertEqual(malformed["status"] as? String, "failure")
    }

    func testExecutableParsesHTTPJSONAndAppliesStrictRawDiagnostics() throws {
        let objects = try CLIReferenceDocumentation.objects()
        let executable = try healthmdExecutableURL()

        let statusPayload = try object(named: "status-success.json", in: objects)
        let statusRun = try runCLI(
            executable: executable,
            arguments: ["status"],
            statusCode: 200,
            responseObject: statusPayload
        )
        XCTAssertEqual(statusRun.exitCode, 0, statusRun.stderr)
        XCTAssertEqual(
            try parsedJSONObject(from: statusRun.stdout),
            statusPayload as NSDictionary
        )

        let legacySuccess: [String: Any] = [
            "raw_data": ["records": []],
            "status": "success"
        ]
        let malformedRun = try runCLI(
            executable: executable,
            arguments: [
                "export", "--from", "2026-07-14", "--to", "2026-07-14",
                "--raw", "--timeout", "5"
            ],
            statusCode: 200,
            responseObject: legacySuccess
        )
        XCTAssertEqual(malformedRun.exitCode, 1, malformedRun.stderr)
        XCTAssertEqual(
            try parsedJSONObject(from: malformedRun.stdout),
            try object(named: "invalid-strict-raw-success.json", in: objects) as NSDictionary
        )

        let executableCases: [(name: String, arguments: [String], statusCode: Int, exitCode: Int32)] = [
            ("status-unavailable.json", ["status"], 200, 0),
            (
                "write-files-export-success-response.json",
                ["export", "--yesterday", "--timeout", "5"],
                200,
                0
            ),
            (
                "write-files-export-partial-response.json",
                ["export", "--last", "2", "--use-iphone-settings", "--timeout", "5"],
                200,
                0
            ),
            (
                "write-files-export-failure-response.json",
                ["export", "--from", "2026-07-14", "--to", "2026-07-15", "--timeout", "5"],
                409,
                1
            ),
            (
                "strict-raw-complete-response.json",
                ["export", "--from", "2026-03-15", "--to", "2026-03-15", "--raw", "--timeout", "5"],
                200,
                0
            ),
            (
                "strict-raw-partial-response.json",
                ["export", "--from", "2026-03-15", "--to", "2026-03-16", "--raw", "--timeout", "5"],
                200,
                1
            ),
            (
                "strict-raw-partial-response.json",
                ["export", "--from", "2026-03-15", "--to", "2026-03-16", "--raw", "--allow-partial", "--timeout", "5"],
                200,
                0
            )
        ]
        for executableCase in executableCases {
            let response = try object(named: executableCase.name, in: objects)
            let run = try runCLI(
                executable: executable,
                arguments: executableCase.arguments,
                statusCode: executableCase.statusCode,
                responseObject: response
            )
            XCTAssertEqual(run.exitCode, executableCase.exitCode, "\(executableCase.name): \(run.stderr)")
            XCTAssertEqual(
                try parsedJSONObject(from: run.stdout),
                response as NSDictionary,
                executableCase.name
            )
        }

        let usageRun = try runCLIWithoutServer(
            executable: executable,
            arguments: ["export", "--last", "0"]
        )
        XCTAssertEqual(usageRun.exitCode, 2)
        XCTAssertTrue(usageRun.stderr.contains("--last must be at least 1"), usageRun.stderr)
    }

    func testProductionParserCoversDocumentedDateAndSettingsModes() throws {
        guard case .export(let yesterday) = try parse(["export", "--yesterday"]).command else {
            return XCTFail("Expected yesterday export options")
        }
        XCTAssertTrue(yesterday.yesterday)

        guard case .export(let last) = try parse([
            "export", "--last", "3", "--use-iphone-settings", "--iphone"
        ]).command else {
            return XCTFail("Expected last-days export options")
        }
        XCTAssertEqual(last.lastDays, 3)
        XCTAssertTrue(last.useIPhoneSettings)
        let request = makeExportRequestBody(
            options: last,
            startDate: "2026-03-13",
            endDate: "2026-03-15"
        )
        XCTAssertEqual(request["settings_policy"] as? String, "current_iphone_settings")
        XCTAssertEqual(request["response_mode"] as? String, "write_files")
    }

    private func object(
        named name: String,
        in objects: [String: Any]
    ) throws -> [String: Any] {
        try XCTUnwrap(objects[name] as? [String: Any], "Missing generated object \(name)")
    }

    private func parsedJSONObject(from data: Data) throws -> NSDictionary {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func healthmdExecutableURL() throws -> URL {
        let fileManager = FileManager.default
        let packageBuild = CLIReferenceDocumentation.packageDirectory
            .appendingPathComponent(".build/debug/healthmd")
        if fileManager.isExecutableFile(atPath: packageBuild.path) {
            return packageBuild
        }

        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = directory.appendingPathComponent("healthmd")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        throw CLIReferenceTestError.executableNotFound
    }

    private func runCLIWithoutServer(
        executable: URL,
        arguments: [String]
    ) throws -> (exitCode: Int32, stdout: Data, stderr: String) {
        let output = Pipe()
        let error = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        let terminated = expectation(description: "healthmd usage process terminated")
        process.terminationHandler = { _ in terminated.fulfill() }
        try process.run()
        wait(for: [terminated], timeout: 10)
        if process.isRunning {
            process.terminate()
            throw CLIReferenceTestError.processTimedOut
        }
        return (
            process.terminationStatus,
            output.fileHandleForReading.readDataToEndOfFile(),
            String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func runCLI(
        executable: URL,
        arguments: [String],
        statusCode: Int,
        responseObject: Any
    ) throws -> (exitCode: Int32, stdout: Data, stderr: String) {
        let responseData = try CLIReferenceDocumentation.canonicalJSON(responseObject)
        let server = try OneShotHTTPServer(statusCode: statusCode, responseBody: responseData)
        server.start()
        defer { server.stop() }

        let output = Pipe()
        let error = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--base-url", "http://127.0.0.1:\(server.port)"] + arguments
        process.standardOutput = output
        process.standardError = error

        let terminated = expectation(description: "healthmd process terminated")
        process.terminationHandler = { _ in terminated.fulfill() }
        try process.run()
        wait(for: [terminated], timeout: 10)
        if process.isRunning {
            process.terminate()
            throw CLIReferenceTestError.processTimedOut
        }

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderrData = error.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        XCTAssertTrue(server.waitUntilFinished(timeout: 2), "Fixture HTTP server did not finish")
        return (process.terminationStatus, stdout, stderr)
    }
}

private enum CLIReferenceTestError: Error {
    case executableNotFound
    case invalidGeneratedCommand
    case processTimedOut
    case socketFailure(String)
}

enum CLIReferenceDocumentation {
    static let packageDirectory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }()

    static let generatedDirectory = packageDirectory
        .deletingLastPathComponent()
        .appendingPathComponent("docs/reference/generated/cli", isDirectory: true)

    static func objects() throws -> [String: Any] {
        let writeRequest = try exportRequest(arguments: [
            "export", "--from", "2026-07-14", "--to", "2026-07-15", "--timeout", "120"
        ])
        let strictRawRequest = try exportRequest(arguments: [
            "export", "--from", "2026-03-15", "--to", "2026-03-15", "--raw", "--timeout", "120"
        ])
        let completeRawResponse = try strictRawCompleteResponse()
        let partialRawResponse = try strictRawPartialResponse()

        let legacySuccess: [String: Any] = [
            "raw_data": ["records": []],
            "status": "success"
        ]
        let malformedValidation = validateStrictRawHTTPSuccess(
            payload: legacySuccess,
            expectedDates: ["2026-07-14"]
        )
        guard !malformedValidation.isValid,
              let malformedDiagnostic = malformedValidation.outputPayload as? [String: Any] else {
            throw CLIReferenceTestError.invalidGeneratedCommand
        }

        return [
            "cli-structured-errors.json": structuredErrors(),
            "invalid-strict-raw-success.json": malformedDiagnostic,
            "status-success.json": statusSuccess(),
            "status-unavailable.json": statusUnavailable(),
            "strict-raw-complete-response.json": completeRawResponse,
            "strict-raw-export-request.json": strictRawRequest,
            "strict-raw-partial-response.json": partialRawResponse,
            "write-files-export-failure-response.json": writeFilesFailureResponse(),
            "write-files-export-partial-response.json": writeFilesPartialResponse(),
            "write-files-export-request.json": writeRequest,
            "write-files-export-success-response.json": writeFilesSuccessResponse()
        ]
    }

    static func artifacts() throws -> [String: Data] {
        var generated = try objects().mapValues(canonicalJSON)
        generated["exit-codes.md"] = Data(exitCodesMarkdown().utf8)
        return generated
    }

    static func canonicalJSON(_ object: Any) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    static func write(_ artifacts: [String: Data], to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in existing {
            try fileManager.removeItem(at: url)
        }
        for name in artifacts.keys.sorted() {
            try artifacts[name]?.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }

    private static func exportRequest(arguments: [String]) throws -> [String: Any] {
        let parsed = try parse(arguments)
        guard case .export(let options) = parsed.command else {
            throw CLIReferenceTestError.invalidGeneratedCommand
        }
        let from = try XCTUnwrap(options.fromDate)
        let to = try XCTUnwrap(options.toDate)
        return makeExportRequestBody(options: options, startDate: from, endDate: to)
    }

    private static func statusSuccess() -> [String: Any] {
        [
            "active_export": NSNull(),
            "destination": [
                "display_name": "Synthetic Export Folder",
                "path": "/Users/example/HealthMdExports",
                "selected": true,
                "writable": true
            ],
            "iphone": [
                "can_trigger_exports": true,
                "can_trigger_raw_exports": true,
                "connected": true,
                "name": "Synthetic iPhone"
            ],
            "mac_app": "running"
        ]
    }

    private static func statusUnavailable() -> [String: Any] {
        [
            "active_export": NSNull(),
            "destination": [
                "display_name": NSNull(),
                "path": NSNull(),
                "selected": false,
                "writable": false
            ],
            "iphone": [
                "can_trigger_exports": false,
                "can_trigger_raw_exports": false,
                "connected": false,
                "name": NSNull()
            ],
            "mac_app": "running"
        ]
    }

    private static func writeFilesSuccessResponse() -> [String: Any] {
        [
            "destination_display_name": "Synthetic Export Folder",
            "destination_path": "/Users/example/HealthMdExports",
            "external_record_count": 0,
            "files_written": 4,
            "job_id": "00000000-0000-4000-8000-000000000101",
            "message": "Exported 2 day(s), wrote 4 file(s).",
            "status": "success",
            "success_count": 2,
            "total_count": 2
        ]
    }

    private static func writeFilesPartialResponse() -> [String: Any] {
        [
            "destination_display_name": "Synthetic Export Folder",
            "destination_path": "/Users/example/HealthMdExports",
            "external_record_count": 0,
            "failure_reason": "healthkit_query_failed",
            "files_written": 2,
            "job_id": "00000000-0000-4000-8000-000000000102",
            "message": "Exported 1/2 day(s), wrote 2 file(s).",
            "status": "partial_success",
            "success_count": 1,
            "total_count": 2
        ]
    }

    private static func writeFilesFailureResponse() -> [String: Any] {
        [
            "external_record_count": 0,
            "failure_reason": "healthkit_unavailable",
            "files_written": 0,
            "job_id": "00000000-0000-4000-8000-000000000103",
            "message": "Health data was unavailable for the requested dates.",
            "status": "failure",
            "success_count": 0,
            "total_count": 2
        ]
    }

    private static func strictRawCompleteResponse() throws -> [String: Any] {
        [
            "external_record_count": 0,
            "files_written": 0,
            "job_id": "00000000-0000-4000-8000-000000000201",
            "message": "Fetched canonical raw data for all 1 requested day(s).",
            "raw_result": try automationRawResult(named: "raw-result-complete.json"),
            "status": "success",
            "success_count": 1,
            "total_count": 1
        ]
    }

    private static func strictRawPartialResponse() throws -> [String: Any] {
        [
            "external_record_count": 0,
            "failure_reason": "incomplete_raw_capture",
            "files_written": 0,
            "job_id": "00000000-0000-4000-8000-000000000202",
            "message": "Fetched canonical raw data for 1/2 day(s) with incomplete capture.",
            "raw_result": try automationRawResult(named: "raw-result-partial.json"),
            "status": "partial_success",
            "success_count": 1,
            "total_count": 2
        ]
    }

    private static func automationRawResult(named name: String) throws -> [String: Any] {
        let url = generatedDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("automation", isDirectory: true)
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Missing generated production raw-result fixture at \(url.path)"
        )
    }

    private static func structuredErrors() -> [String: Any] {
        let unavailableExit = exportExitCode(
            httpStatusCode: 409,
            status: "unavailable",
            isRaw: false,
            allowPartial: false
        )
        let invalidRequestExit = exportExitCode(
            httpStatusCode: 400,
            status: nil,
            isRaw: false,
            allowPartial: false
        )
        let transportExit = exportExitCode(
            httpStatusCode: 503,
            status: nil,
            isRaw: false,
            allowPartial: false
        )

        return [
            "examples": [[
                "command": "healthmd status",
                "exit_code": 1,
                "http_status": 503,
                "response": [
                    "error": "mac_app_unreachable",
                    "message": "Connection refused"
                ]
            ], [
                "command": "healthmd export --from 2026-07-14 --to 2026-07-15",
                "exit_code": transportExit,
                "http_status": 503,
                "response": [
                    "error": "mac_app_unreachable",
                    "message": "Connection refused"
                ]
            ], [
                "command": "healthmd export --from 2026-07-14 --to 2026-07-15",
                "exit_code": invalidRequestExit,
                "http_status": 400,
                "response": [
                    "error": "invalid_date_range"
                ]
            ], [
                "command": "healthmd export --from 2026-07-14 --to 2026-07-15",
                "exit_code": unavailableExit,
                "http_status": 409,
                "response": [
                    "failure_reason": "iphone_disconnected",
                    "message": "The iPhone disconnected before the export completed.",
                    "status": "unavailable"
                ]
            ]]
        ]
    }

    private static func exitCodeReference() -> [String: Any] {
        struct ExportCase {
            let label: String
            let httpStatus: Int
            let responseStatus: String?
            let raw: Bool
            let allowPartial: Bool
        }

        let exportCases = [
            ExportCase(label: "write_files_success", httpStatus: 200, responseStatus: "success", raw: false, allowPartial: false),
            ExportCase(label: "write_files_partial_success", httpStatus: 200, responseStatus: "partial_success", raw: false, allowPartial: false),
            ExportCase(label: "strict_raw_success", httpStatus: 200, responseStatus: "success", raw: true, allowPartial: false),
            ExportCase(label: "strict_raw_partial_default", httpStatus: 200, responseStatus: "partial_success", raw: true, allowPartial: false),
            ExportCase(label: "strict_raw_partial_allowed", httpStatus: 200, responseStatus: "partial_success", raw: true, allowPartial: true),
            ExportCase(label: "export_failure", httpStatus: 409, responseStatus: "failure", raw: false, allowPartial: false),
            ExportCase(label: "http_200_unknown_status", httpStatus: 200, responseStatus: "accepted", raw: false, allowPartial: false),
            ExportCase(label: "http_error", httpStatus: 503, responseStatus: nil, raw: false, allowPartial: false)
        ]
        let rows: [[String: Any]] = [
            [
                "allow_partial": false,
                "command": "status",
                "exit_code": 0,
                "http_status": 200,
                "label": "status_success",
                "raw": false,
                "response_status": NSNull()
            ],
            [
                "allow_partial": false,
                "command": "status",
                "exit_code": 1,
                "http_status": 503,
                "label": "status_http_error",
                "raw": false,
                "response_status": NSNull()
            ]
        ] + exportCases.map { item in
            [
                "allow_partial": item.allowPartial,
                "command": "export",
                "exit_code": exportExitCode(
                    httpStatusCode: item.httpStatus,
                    status: item.responseStatus,
                    isRaw: item.raw,
                    allowPartial: item.allowPartial
                ),
                "http_status": item.httpStatus,
                "label": item.label,
                "raw": item.raw,
                "response_status": item.responseStatus as Any? ?? NSNull()
            ]
        } + [[
            "allow_partial": false,
            "command": "export",
            "exit_code": 1,
            "http_status": 200,
            "label": "strict_raw_invalid_success_envelope",
            "raw": true,
            "response_status": "success",
            "strict_raw_validation": "invalid"
        ]]

        return [
            "reference": rows,
            "top_level_errors": [
                "cli_usage_error": 2,
                "unexpected_error": 1
            ]
        ]
    }

    private static func exitCodesMarkdown() -> String {
        let reference = exitCodeReference()
        let rows = reference["reference"] as? [[String: Any]] ?? []
        var lines = [
            "# Health.md CLI Exit Codes",
            "",
            "This file is generated by `scripts/generated-cli-reference-docs.sh` from the CLI exit-code logic.",
            "",
            "| Scenario | Command | HTTP | Response status | Raw | Allow partial | Exit code |",
            "| --- | --- | ---: | --- | --- | --- | ---: |"
        ]
        for row in rows {
            let label = row["label"] as? String ?? "unknown"
            let command = row["command"] as? String ?? "unknown"
            let httpStatus = row["http_status"] as? Int ?? 0
            let responseStatus = row["response_status"] as? String ?? "n/a"
            let raw = (row["raw"] as? Bool) == true ? "yes" : "no"
            let allowPartial = (row["allow_partial"] as? Bool) == true ? "yes" : "no"
            let exitCode = row["exit_code"] as? Int ?? 1
            lines.append("| `\(label)` | `\(command)` | \(httpStatus) | `\(responseStatus)` | \(raw) | \(allowPartial) | \(exitCode) |")
        }
        lines += [
            "",
            "Strict raw HTTP-200 responses are validated before the table's status mapping is applied. An invalid envelope emits `invalid_strict_raw_success` and exits 1.",
            "",
            "| Top-level CLI error | Exit code |",
            "| --- | ---: |",
            "| Usage or argument error | 2 |",
            "| Unexpected error | 1 |",
            ""
        ]
        return lines.joined(separator: "\n")
    }
}

private final class OneShotHTTPServer: @unchecked Sendable {
    let port: UInt16

    private let listener: Int32
    private let statusCode: Int
    private let responseBody: Data
    private let finished = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "healthmd.cli-reference-http-server")
    private let stateLock = NSLock()
    private var started = false
    private var stopped = false

    init(statusCode: Int, responseBody: Data) throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CLIReferenceTestError.socketFailure("socket")
        }
        listener = descriptor
        self.statusCode = statusCode
        self.responseBody = responseBody

        var reuse: Int32 = 1
        guard Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            Darwin.close(descriptor)
            throw CLIReferenceTestError.socketFailure("setsockopt")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw CLIReferenceTestError.socketFailure("bind/listen")
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(descriptor)
            throw CLIReferenceTestError.socketFailure("getsockname")
        }
        port = UInt16(bigEndian: boundAddress.sin_port)
    }

    deinit {
        stop()
    }

    func start() {
        guard !started else { return }
        started = true
        queue.async { [self] in
            defer { finished.signal() }
            var peer = sockaddr_storage()
            var peerLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client = withUnsafeMutablePointer(to: &peer) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listener, $0, &peerLength)
                }
            }
            guard client >= 0 else { return }
            defer { Darwin.close(client) }

            readCompleteRequest(from: client)
            sendResponse(to: client)
        }
    }

    func stop() {
        stateLock.lock()
        guard !stopped else {
            stateLock.unlock()
            return
        }
        stopped = true
        stateLock.unlock()
        Darwin.shutdown(listener, SHUT_RDWR)
        Darwin.close(listener)
    }

    func waitUntilFinished(timeout: TimeInterval) -> Bool {
        finished.wait(timeout: .now() + timeout) == .success
    }

    private func readCompleteRequest(from descriptor: Int32) {
        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        var expectedLength: Int?

        while request.count < (expectedLength ?? Int.max) {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            request.append(buffer, count: count)

            if expectedLength == nil,
               let headerRange = request.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: request[..<headerRange.lowerBound], encoding: .utf8) {
                let contentLength = header
                    .components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
                    ?? 0
                expectedLength = headerRange.upperBound + contentLength
            }
        }
    }

    private func sendResponse(to descriptor: Int32) {
        let reason = statusCode == 200 ? "OK" : "Error"
        var response = Data(
            "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(responseBody.count)\r\nConnection: close\r\n\r\n".utf8
        )
        response.append(responseBody)

        response.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(descriptor, baseAddress.advanced(by: sent), bytes.count - sent, 0)
                guard count > 0 else { return }
                sent += count
            }
        }
    }
}
