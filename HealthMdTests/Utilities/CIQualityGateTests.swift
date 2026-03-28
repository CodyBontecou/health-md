//
//  CIQualityGateTests.swift
//  HealthMdTests
//
//  Infrastructure tests for E5 CI quality gates.
//  Validates that scripts, configs, and workflow wiring exist and function correctly.
//

import XCTest

final class CIQualityGateTests: XCTestCase {

    private var projectDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Utilities
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // app
    }

    // MARK: - Coverage Threshold Gate (TODO-55c3e0ec)

    func testCoverageThresholdScript_exists() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-coverage.sh").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scriptPath),
            "scripts/check-coverage.sh must exist"
        )
    }

    func testCoverageThresholdScript_isExecutable() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-coverage.sh").path
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: scriptPath),
            "scripts/check-coverage.sh must be executable"
        )
    }

    func testCoverageThresholdConfig_exists() throws {
        let configPath = projectDir.appendingPathComponent(".ci/coverage-thresholds.json").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configPath),
            ".ci/coverage-thresholds.json must exist"
        )
    }

    func testCoverageThresholdConfig_hasValidJSON() throws {
        let configPath = projectDir.appendingPathComponent(".ci/coverage-thresholds.json").path
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Config must be valid JSON object")
        XCTAssertNotNil(json?["minimum_coverage"], "Config must contain minimum_coverage key")
    }

    func testCoverageThresholdScript_failsOnMissingInput() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-coverage.sh").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, "/nonexistent/path.xcresult"]
        process.environment = ["CI_CONFIG_DIR": projectDir.appendingPathComponent(".ci").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(
            process.terminationStatus, 0,
            "Script must exit non-zero when xcresult path doesn't exist"
        )
    }

    func testWorkflow_referencesCoverageThresholdCheck() throws {
        let workflowPath = projectDir.appendingPathComponent(".github/workflows/tests.yml").path
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("check-coverage"),
            "Workflow must reference the coverage threshold check"
        )
    }

    // MARK: - Warning Gate (TODO-eb0b1b50)

    func testWarningGateScript_exists() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-warnings.sh").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scriptPath),
            "scripts/check-warnings.sh must exist"
        )
    }

    func testWarningGateScript_isExecutable() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-warnings.sh").path
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: scriptPath),
            "scripts/check-warnings.sh must be executable"
        )
    }

    func testWarningBaseline_exists() throws {
        let baselinePath = projectDir.appendingPathComponent(".ci/warning-baseline.json").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: baselinePath),
            ".ci/warning-baseline.json must exist"
        )
    }

    func testWarningBaseline_hasValidJSON() throws {
        let baselinePath = projectDir.appendingPathComponent(".ci/warning-baseline.json").path
        let data = try Data(contentsOf: URL(fileURLWithPath: baselinePath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Baseline must be valid JSON object")
        XCTAssertNotNil(json?["allowed_count"], "Baseline must contain allowed_count key")
    }

    func testWarningGateScript_failsOnMissingLogFile() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-warnings.sh").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, "/nonexistent/build.log"]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
            "CI_CONFIG_DIR": projectDir.appendingPathComponent(".ci").path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(
            process.terminationStatus, 0,
            "Script must exit non-zero when log file doesn't exist"
        )
    }

    func testWorkflow_referencesWarningCheck() throws {
        let workflowPath = projectDir.appendingPathComponent(".github/workflows/tests.yml").path
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("check-warnings"),
            "Workflow must reference the warning gate check"
        )
    }

    // MARK: - Split iOS/macOS Jobs (TODO-a55c5428)

    func testWorkflow_hasSeparateIOSJob() throws {
        let workflowPath = projectDir.appendingPathComponent(".github/workflows/tests.yml").path
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("test-ios:"),
            "Workflow must have a separate test-ios job"
        )
    }

    func testWorkflow_hasSeparateMacOSJob() throws {
        let workflowPath = projectDir.appendingPathComponent(".github/workflows/tests.yml").path
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("test-macos:"),
            "Workflow must have a separate test-macos job"
        )
    }

    func testWorkflow_hasPerJobArtifactUploads() throws {
        let workflowPath = projectDir.appendingPathComponent(".github/workflows/tests.yml").path
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        // Should have at least two artifact upload steps (one per job)
        let uploadCount = content.components(separatedBy: "upload-artifact").count - 1
        XCTAssertGreaterThanOrEqual(
            uploadCount, 2,
            "Workflow must have at least 2 artifact upload steps (one per platform job)"
        )
    }

    func testWorkflow_preservesConcurrency() throws {
        let workflowPath = projectDir.appendingPathComponent(".github/workflows/tests.yml").path
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("cancel-in-progress"),
            "Workflow must preserve concurrency cancellation behavior"
        )
    }

    // MARK: - Scheduled Extended Run (TODO-74fdb59f)

    func testScheduledWorkflow_exists() throws {
        let path = projectDir.appendingPathComponent(".github/workflows/nightly.yml").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path),
            ".github/workflows/nightly.yml must exist for scheduled extended runs"
        )
    }

    func testScheduledWorkflow_hasScheduleTrigger() throws {
        let path = projectDir.appendingPathComponent(".github/workflows/nightly.yml").path
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(
            content.contains("schedule:"),
            "Nightly workflow must have a schedule trigger"
        )
        XCTAssertTrue(
            content.contains("cron:"),
            "Nightly workflow must have a cron expression"
        )
    }

    func testScheduledWorkflow_hasExtendedChecks() throws {
        let path = projectDir.appendingPathComponent(".github/workflows/nightly.yml").path
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(
            content.contains("upload-artifact"),
            "Nightly workflow must upload summary artifacts"
        )
    }

    // MARK: - TDD Evidence Guard (TODO-9f8571ce)

    func testTDDEvidenceScript_exists() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-tdd-evidence.sh").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scriptPath),
            "scripts/check-tdd-evidence.sh must exist"
        )
    }

    func testTDDEvidenceScript_isExecutable() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-tdd-evidence.sh").path
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: scriptPath),
            "scripts/check-tdd-evidence.sh must be executable"
        )
    }

    func testTDDEvidenceScript_failsOnMissingTodosDir() throws {
        let scriptPath = projectDir.appendingPathComponent("scripts/check-tdd-evidence.sh").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
            "TODOS_DIR": "/nonexistent/todos",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(
            process.terminationStatus, 0,
            "Script must exit non-zero when todos directory doesn't exist"
        )
    }

    func testWorkflow_referencesTDDEvidenceCheck() throws {
        let workflowPath = projectDir.appendingPathComponent(".github/workflows/tests.yml").path
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        let nightlyPath = projectDir.appendingPathComponent(".github/workflows/nightly.yml").path
        let nightlyContent = (try? String(contentsOfFile: nightlyPath, encoding: .utf8)) ?? ""
        let combined = content + nightlyContent
        XCTAssertTrue(
            combined.contains("check-tdd-evidence"),
            "At least one workflow must reference the TDD evidence check"
        )
    }

    // MARK: - CI Quality Gates Documentation (TODO-188d2f69)

    func testCIQualityGatesDoc_exists() throws {
        let docPath = projectDir.appendingPathComponent("docs/testing/CI-QUALITY-GATES.md").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: docPath),
            "docs/testing/CI-QUALITY-GATES.md must exist"
        )
    }

    func testCIQualityGatesDoc_coversAllGates() throws {
        let docPath = projectDir.appendingPathComponent("docs/testing/CI-QUALITY-GATES.md").path
        let content = try String(contentsOfFile: docPath, encoding: .utf8)
        XCTAssertTrue(content.contains("check-coverage"), "Docs must cover coverage gate")
        XCTAssertTrue(content.contains("check-warnings"), "Docs must cover warning gate")
        XCTAssertTrue(content.contains("check-tdd-evidence"), "Docs must cover TDD evidence guard")
        XCTAssertTrue(content.contains("coverage-thresholds"), "Docs must explain threshold config")
        XCTAssertTrue(content.contains("warning-baseline"), "Docs must explain warning baseline")
    }
}
