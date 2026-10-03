//
//  CIQualityGateTests.swift
//  HealthMdTests
//
//  Infrastructure tests for E5 CI quality gates.
//  Validates that scripts, configs, and workflow wiring exist and function correctly.
//

import Foundation
import XCTest

final class CIQualityGateTests: XCTestCase {

    private var projectDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Utilities
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // apps/apple
    }

    private var monorepoRoot: URL {
        projectDir
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repository root
    }

    private var appleCIWorkflowPath: String {
        monorepoRoot.appendingPathComponent(".github/workflows/apple-ci.yml").path
    }

    private var appleNightlyWorkflowPath: String {
        monorepoRoot.appendingPathComponent(".github/workflows/apple-nightly.yml").path
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

    #if os(macOS)
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
    #else
    func testCoverageThresholdScript_failsOnMissingInput() throws {
        throw XCTSkip("Process is unavailable on iOS test runtime")
    }
    #endif

    func testWorkflow_referencesCoverageThresholdCheck() throws {
        let workflowPath = appleCIWorkflowPath
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

    #if os(macOS)
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
    #else
    func testWarningGateScript_failsOnMissingLogFile() throws {
        throw XCTSkip("Process is unavailable on iOS test runtime")
    }
    #endif

    func testWorkflow_referencesWarningCheck() throws {
        let workflowPath = appleCIWorkflowPath
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("check-warnings"),
            "Workflow must reference the warning gate check"
        )
    }

    // MARK: - Split iOS/macOS Jobs (TODO-a55c5428)

    func testWorkflow_hasSeparateIOSJob() throws {
        let workflowPath = appleCIWorkflowPath
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("test-ios:"),
            "Workflow must have a separate test-ios job"
        )
    }

    func testWorkflow_hasSeparateMacOSJob() throws {
        let workflowPath = appleCIWorkflowPath
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("test-macos:"),
            "Workflow must have a separate test-macos job"
        )
    }

    func testWorkflow_hasPerJobArtifactUploads() throws {
        let workflowPath = appleCIWorkflowPath
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        // Should have at least two artifact upload steps (one per job)
        let uploadCount = content.components(separatedBy: "upload-artifact").count - 1
        XCTAssertGreaterThanOrEqual(
            uploadCount, 2,
            "Workflow must have at least 2 artifact upload steps (one per platform job)"
        )
    }

    func testWorkflow_boundsAppleTestsAndRunsMacOSSuiteOnce() throws {
        let workflowPath = appleCIWorkflowPath
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertEqual(
            content.components(separatedBy: "timeout-minutes: 75").count - 1,
            2,
            "Hosted Apple unit and coverage jobs must allow enough time for clean builds"
        )
        XCTAssertTrue(
            content.contains("test-ios-ui:\n    name: iOS UI regressions\n    needs: [changes, prepare-shared-core]\n    if: ${{ needs.changes.outputs.run == 'true' }}\n    runs-on: macos-26\n    timeout-minutes: 60"),
            "The split UI job must allow at least 60 minutes for clean builds"
        )
        XCTAssertEqual(
            content.components(separatedBy: "- name: Prepare and validate shared Rust core for Apple").count - 1,
            1,
            "Apple CI must build the exact shared-core XCFramework only once"
        )
        XCTAssertEqual(
            content.components(separatedBy: "needs: [changes, prepare-shared-core]").count - 1,
            4,
            "The three Xcode test jobs and actual Watch build must consume one prepared artifact"
        )
        XCTAssertTrue(
            content.contains("-test-timeouts-enabled YES"),
            "UI tests must fail diagnostically instead of hanging indefinitely"
        )
        let smokeStep = try XCTUnwrap(
            content.components(separatedBy: "- name: Run UI smoke tests (iOS)").last?
                .components(separatedBy: "- name: Run App Review export regression (iPad)").first
        )
        XCTAssertFalse(
            smokeStep.contains("continue-on-error: true"),
            "Selected PR UI smoke failures must remain blocking"
        )
        let smokeInvocations = smokeStep.components(separatedBy: "xcodebuild test").dropFirst()
        XCTAssertEqual(smokeInvocations.count, 2, "PR smoke must use two deterministic test invocations")
        for invocation in smokeInvocations {
            let selectionCount = invocation.components(separatedBy: "-only-testing:HealthMdUITests/").count - 1
            XCTAssertGreaterThan(selectionCount, 0, "Each PR smoke invocation must select tests explicitly")
            XCTAssertLessThanOrEqual(selectionCount, 10, "Each PR smoke invocation must remain bounded")
        }
        let smokeSelectionCount = smokeStep.components(separatedBy: "-only-testing:HealthMdUITests/").count - 1
        XCTAssertEqual(smokeSelectionCount, 16, "PR smoke must preserve all selected UI regressions")
        XCTAssertTrue(
            smokeStep.contains("OnboardingJourneyUITests/testReleaseNotesStillAppearForReturningUsers"),
            "PR smoke must cover deterministic returning-user release notes"
        )
        XCTAssertTrue(
            content.contains("-only-testing:HealthMdUITests/ExportJourneyUITests/testNoDataExport_showsGuidanceInsteadOfGenericError"),
            "The blocking iPad App Review regression must remain selected"
        )
        let makefile = try String(
            contentsOf: projectDir.appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        XCTAssertTrue(
            makefile.contains("XCODE_TEST_TIMEOUT_FLAGS := -test-timeouts-enabled YES"),
            "macOS, coverage, and sanitizer tests must enable per-test execution timeouts"
        )
        XCTAssertTrue(
            makefile.contains("-resultBundlePath \"$(IOS_XCRESULT_PATH)\""),
            "iOS unit tests must retain an xcresult bundle"
        )
        XCTAssertTrue(
            makefile.contains("tee \"$(IOS_TEST_RAW_LOG)\""),
            "iOS unit tests must retain unfiltered xcodebuild output"
        )
        let iosTestTarget = makefile.components(separatedBy: "test-ios: prepare-healthmd-core-rust").last?
            .components(separatedBy: "test-macos: prepare-healthmd-core-rust").first ?? ""
        XCTAssertFalse(
            iosTestTarget.contains("$(XCODE_TEST_TIMEOUT_FLAGS)"),
            "iOS unit tests must not use Xcode's flaky hosted-simulator timeout allowances"
        )
        XCTAssertTrue(
            iosTestTarget.contains("-test-timeouts-enabled NO"),
            "iOS unit tests must explicitly disable hosted-simulator timeout handling"
        )
        XCTAssertTrue(
            content.contains("xcrun xcresulttool get test-results summary --path \"$result\""),
            "CI must report the structured iOS test result"
        )
        XCTAssertTrue(
            content.contains("raise SystemExit(1)"),
            "An inconsistent or failed iOS xcresult must fail the reporting step"
        )
        XCTAssertTrue(
            content.contains("scripts/check-warnings.sh build/logs/xcodebuild-ios-raw.log"),
            "The iOS warning gate must scan unfiltered compiler output"
        )
        XCTAssertTrue(
            content.contains("apps/apple/build/logs/xcodebuild-ios-raw.log") &&
                content.contains("apps/apple/build/test-results/HealthMd-iOS.xcresult"),
            "CI must upload raw iOS diagnostics and the xcresult bundle"
        )
        XCTAssertFalse(
            content.contains("make test-macos"),
            "The PR workflow must not run the macOS suite before the coverage pass"
        )
        XCTAssertEqual(
            content.components(separatedBy: "make coverage").count - 1,
            1,
            "The PR workflow must run the coverage-enabled macOS suite exactly once"
        )
        XCTAssertTrue(
            content.contains("test-ios-ui:"),
            "UI regressions must run in a job parallel to iOS unit tests"
        )
    }

    func testWorkflow_exactFourConsumersValidateOneSharedCoreArtifactAndRemainBlocking() throws {
        let content = try String(contentsOfFile: appleCIWorkflowPath, encoding: .utf8)
        let jobs = try workflowJobs(content)
        let consumers: Set<String> = ["test-ios", "test-macos", "test-ios-ui", "build-watch"]
        let artifactName = "name: apple-shared-core\n"
        let topology = try sharedCoreArtifactTopology(jobs)
        XCTAssertEqual(topology.consumers, consumers.sorted(), "Consumer identities matter, not just a count")
        XCTAssertEqual(topology.producers, ["prepare-shared-core"])
        XCTAssertTrue(topology.isExpected, "Exactly one producer and four named consumers, without duplicates")
        XCTAssertEqual(content.components(separatedBy: artifactName).count - 1, 5)
        let producer = try XCTUnwrap(jobs["prepare-shared-core"])
        XCTAssertEqual(producer.components(separatedBy: "run: make prepare-healthmd-core-rust").count - 1, 1)
        XCTAssertTrue(producer.contains("include-hidden-files: true"))
        XCTAssertTrue(producer.contains("if-no-files-found: error"))
        XCTAssertTrue(producer.contains("Artifacts/.healthmd-core-source.sha256"))

        let invocations = [
            "test-ios": "make test-ios CORE_RUST_PREPARE=:",
            "test-macos": "make coverage CORE_RUST_PREPARE=:",
            "test-ios-ui": "xcodebuild test",
            "build-watch": "xcodebuild build -project HealthMd.xcodeproj -scheme HealthMdWatch",
        ]
        let resultVariables = [
            "test-ios": "IOS_RESULT", "test-macos": "MACOS_RESULT",
            "test-ios-ui": "IOS_UI_RESULT", "build-watch": "WATCH_RESULT",
        ]
        let gate = try XCTUnwrap(jobs["gate"])
        XCTAssertTrue(gate.contains("if: ${{ always() }}"))
        for id in consumers.sorted() {
            let job = try XCTUnwrap(jobs[id])
            XCTAssertTrue(job.contains("needs: [changes, prepare-shared-core]"), id)
            XCTAssertTrue(job.contains("if: ${{ needs.changes.outputs.run == 'true' }}"), id)
            XCTAssertTrue(job.contains("ref: ${{ inputs.release_sha || github.sha }}"), id)
            XCTAssertEqual(job.components(separatedBy: "actions/download-artifact@v4").count - 1, 1, id)
            XCTAssertEqual(job.components(separatedBy: artifactName).count - 1, 1, id)
            XCTAssertTrue(job.contains("path: apps/apple/Packages/HealthMdCoreRust/Artifacts"), id)
            XCTAssertTrue(job.contains("test -s Packages/HealthMdCoreRust/Artifacts/.healthmd-core-source.sha256"), id)
            let validation = try XCTUnwrap(job.range(of: "scripts/validate-apple-xcframework.sh"), id)
            let invocation = try XCTUnwrap(job.range(of: try XCTUnwrap(invocations[id])), id)
            XCTAssertLessThan(validation.lowerBound, invocation.lowerBound, id)
            XCTAssertFalse(job.contains("run: make prepare-healthmd-core-rust"), id)
            XCTAssertFalse(job.contains("continue-on-error: true"), id)
            XCTAssertTrue(gate.contains("      - \(id)\n"), id)
            let variable = try XCTUnwrap(resultVariables[id])
            XCTAssertTrue(gate.contains("\(variable): ${{ needs.\(id).result }}"), id)
            XCTAssertTrue(gate.contains("test \"$\(variable)\" = success"), id)
        }
        let watch = try XCTUnwrap(jobs["build-watch"])
        XCTAssertTrue(watch.contains("timeout-minutes: 25"))
        XCTAssertTrue(watch.contains("generic/platform=watchOS Simulator"))
        XCTAssertTrue(watch.contains("-jobs 2"))
        XCTAssertTrue(watch.contains("set -euo pipefail"))
        XCTAssertTrue(watch.contains("tee build/watch-ci/build.log"))
    }

    func testWatchWorkflow_preservesFullBehaviorContractAndProjectionChecks() throws {
        let content = try String(
            contentsOf: monorepoRoot.appendingPathComponent(".github/workflows/apple-watch-ci.yml"),
            encoding: .utf8
        )
        let jobs = try workflowJobs(content)
        let behavior = try XCTUnwrap(jobs["capture-upload-and-build"])
        XCTAssertTrue(behavior.contains("python3 packages/contracts/validate.py"))
        XCTAssertTrue(behavior.contains("python3 packages/contracts/test_watch_capability_governance.py"))
        XCTAssertTrue(behavior.contains("swift test --package-path apps/apple/Packages/HealthMdWatchExport --jobs 2"))
        XCTAssertFalse(behavior.contains("--filter"), "All 22 Watch behavior tests must remain registered")
        XCTAssertFalse(behavior.contains("--skip"))
        XCTAssertFalse(behavior.contains("continue-on-error: true"))
        let projections = try XCTUnwrap(jobs["registry-projections"])
        XCTAssertTrue(projections.contains("python3 packages/healthmd-core-rust/scripts/tests/test_registry_capability_scope.py"))
        XCTAssertTrue(projections.contains("python3 packages/healthmd-core-rust/scripts/import-native-registry.py"))
        XCTAssertTrue(projections.contains("python3 packages/healthmd-core-rust/scripts/generate-registry-adapters.py"))
        XCTAssertTrue(projections.contains("git diff --exit-code"))
        XCTAssertFalse(projections.contains("continue-on-error: true"))
    }

    func testSharedCoreArtifactTopology_diagnosticUploadsAreNotProducers() throws {
        let topology = try sharedCoreArtifactTopology(artifactFixtureJobs())
        XCTAssertEqual(topology.producers, ["prepare-shared-core"])
        XCTAssertEqual(topology.consumers, ["build-watch", "test-ios", "test-ios-ui", "test-macos"])
        XCTAssertTrue(topology.isExpected)
    }

    func testSharedCoreArtifactTopology_extraSharedCoreUploadOrMissingConsumerFails() throws {
        var extraProducer = artifactFixtureJobs()
        extraProducer["unexpected-producer"] = "    steps:\n" + artifactFixtureStep("upload", name: "apple-shared-core")
        XCTAssertFalse(try sharedCoreArtifactTopology(extraProducer).isExpected)
        var duplicateUpload = artifactFixtureJobs()
        duplicateUpload["prepare-shared-core", default: ""] += artifactFixtureStep("upload", name: "apple-shared-core")
        XCTAssertFalse(try sharedCoreArtifactTopology(duplicateUpload).isExpected)
        var missingConsumer = artifactFixtureJobs()
        missingConsumer.removeValue(forKey: "build-watch")
        XCTAssertFalse(try sharedCoreArtifactTopology(missingConsumer).isExpected)
    }

    func testSharedCoreArtifactTopology_requiresNameInsideTheSameActionsWithBlock() throws {
        var jobs = artifactFixtureJobs()
        jobs["build-watch"] = """
            steps:
              - name: apple-shared-core
                uses: actions/download-artifact@v4
                with:
                  name: diagnostics
                env:
                  name: apple-shared-core
              - uses: actions/upload-artifact@v4
                with:
                  name: apple-watch-build-diagnostics

        """
        let topology = try sharedCoreArtifactTopology(jobs)
        XCTAssertEqual(topology.producers, ["prepare-shared-core"])
        XCTAssertFalse(topology.consumers.contains("build-watch"))
        XCTAssertFalse(topology.isExpected)
    }

    private struct SharedCoreArtifactTopology {
        var producers: [String] = []
        var consumers: [String] = []

        var isExpected: Bool {
            producers == ["prepare-shared-core"] &&
                consumers == ["build-watch", "test-ios", "test-ios-ui", "test-macos"]
        }
    }

    // Parse the current explicit workflow style only: steps at six spaces,
    // action fields at eight, and with fields at ten. Never combine fields
    // from different steps or confuse a display/env name with with.name.
    private func sharedCoreArtifactTopology(_ jobs: [String: String]) throws -> SharedCoreArtifactTopology {
        let stepHeader = try NSRegularExpression(pattern: "^      - [a-z][a-z-]*:", options: .anchorsMatchLines)
        var topology = SharedCoreArtifactTopology()
        for (id, job) in jobs {
            guard let stepsRange = job.range(of: "    steps:\n") else { continue }
            let steps = String(job[stepsRange.upperBound...])
            let source = steps as NSString
            let headers = stepHeader.matches(in: steps, range: NSRange(location: 0, length: source.length))
            for (index, header) in headers.enumerated() {
                let end = index + 1 < headers.count ? headers[index + 1].range.location : source.length
                let lines = source.substring(with: NSRange(location: header.range.location, length: end - header.range.location))
                    .components(separatedBy: "\n")
                let uses = lines.compactMap { line -> String? in
                    for prefix in ["      - uses: ", "        uses: "] where line.hasPrefix(prefix) {
                        return String(line.dropFirst(prefix.count))
                    }
                    return nil
                }
                guard uses.count == 1, let action = uses.first,
                      ["actions/upload-artifact@v4", "actions/download-artifact@v4"].contains(action),
                      let withIndex = lines.firstIndex(of: "        with:") else { continue }
                let fields = lines.dropFirst(withIndex + 1).prefix { $0.isEmpty || $0.hasPrefix("          ") }
                let names = fields.filter { $0.hasPrefix("          name: ") }
                    .map { String($0.dropFirst("          name: ".count)) }
                guard names == ["apple-shared-core"] else { continue }
                if action == "actions/upload-artifact@v4" { topology.producers.append(id) }
                else { topology.consumers.append(id) }
            }
        }
        topology.producers.sort()
        topology.consumers.sort()
        return topology
    }

    private func artifactFixtureStep(_ direction: String, name: String) -> String {
        "      - uses: actions/\(direction)-artifact@v4\n        with:\n          name: \(name)\n"
    }

    private func artifactFixtureJobs() -> [String: String] {
        var jobs = ["prepare-shared-core": "    steps:\n" + artifactFixtureStep("upload", name: "apple-shared-core")]
        for id in ["test-ios", "test-macos", "test-ios-ui", "build-watch"] {
            // A named download step followed by a uses-first diagnostic upload.
            jobs[id] = "    steps:\n      - name: Restore shared core\n        uses: actions/download-artifact@v4\n        with:\n          name: apple-shared-core\n" +
                artifactFixtureStep("upload", name: "\(id)-diagnostics")
        }
        return jobs
    }

    // Inspect anchored job sections in the repository's explicit workflow format.
    // This is a source-wiring guard, not a replacement for executing hosted jobs.
    private func workflowJobs(_ content: String) throws -> [String: String] {
        let jobSection = try XCTUnwrap(content.components(separatedBy: "\njobs:\n").last)
        XCTAssertEqual(content.components(separatedBy: "\njobs:\n").count, 2)
        let regex = try NSRegularExpression(pattern: "^  ([a-z][a-z0-9-]*):$", options: .anchorsMatchLines)
        let source = jobSection as NSString
        let matches = regex.matches(in: jobSection, range: NSRange(location: 0, length: source.length))
        var jobs: [String: String] = [:]
        for (index, match) in matches.enumerated() {
            let id = source.substring(with: match.range(at: 1))
            XCTAssertNil(jobs[id], "Duplicate workflow job \(id)")
            let end = index + 1 < matches.count ? matches[index + 1].range.location : source.length
            jobs[id] = source.substring(with: NSRange(location: match.range.location, length: end - match.range.location))
        }
        return jobs
    }

    func testWorkflow_preservesConcurrency() throws {
        let workflowPath = appleCIWorkflowPath
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("cancel-in-progress"),
            "Workflow must preserve concurrency cancellation behavior"
        )
    }

    func testWorkflows_doNotLaunchExpensiveFollowupsAfterCancellation() throws {
        for path in [appleCIWorkflowPath, appleNightlyWorkflowPath] {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(
                content.contains("if: always()\n        continue-on-error: true"),
                "UI tests must not start after an in-progress workflow is cancelled: \(path)"
            )
            XCTAssertTrue(
                content.contains("if: ${{ success() }}"),
                "Expensive follow-up tests must require earlier steps to succeed: \(path)"
            )
            XCTAssertTrue(
                content.contains("if: ${{ !cancelled() }}"),
                "Artifact and diagnostic follow-ups must stop when a run is cancelled: \(path)"
            )
        }
    }

    // MARK: - Scheduled Extended Run (TODO-74fdb59f)

    func testScheduledWorkflow_exists() throws {
        let path = appleNightlyWorkflowPath
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path),
            ".github/workflows/apple-nightly.yml must exist for scheduled extended runs"
        )
    }

    func testScheduledWorkflow_hasScheduleTrigger() throws {
        let path = appleNightlyWorkflowPath
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
        let path = appleNightlyWorkflowPath
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

    #if os(macOS)
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
    #else
    func testTDDEvidenceScript_failsOnMissingTodosDir() throws {
        throw XCTSkip("Process is unavailable on iOS test runtime")
    }
    #endif

    func testWorkflow_referencesTDDEvidenceCheck() throws {
        let workflowPath = appleCIWorkflowPath
        let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
        let nightlyPath = appleNightlyWorkflowPath
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

    // MARK: - Accessibility Source Checks (issue #38)

    func testIconOnlyControls_haveExplicitAccessibilityLabels() throws {
        let criticalFiles = [
            "HealthMd/iPad/iPadExportView.swift": [
                ".accessibilityLabel(\"Stop export\")",
                ".accessibilityLabel(\"Preview export\")",
                ".accessibilityLabel(purchaseManager.canExport ? \"Export Health Data\" : \"Unlock to export\")",
            ],
            "HealthMd/iPad/iPadSettingsView.swift": [
                ".accessibilityLabel(\"Join our Discord\")",
                ".accessibilityLabel(\"Send feedback\")",
                ".accessibilityLabel(\"Report a bug on GitHub\")",
                ".accessibilityLabel(\"Remove placeholder field \\(key)\")",
            ],
            "HealthMd/iOS/Views/MetricSelectionView.swift": [
                ".accessibilityLabel(\"Metric actions\")",
                ".accessibilityLabel(\"Clear search\")",
            ],
            "HealthMd/iOS/Views/FormatCustomizationView.swift": [
                ".accessibilityLabel(\"Frontmatter field actions\")",
                ".accessibilityLabel(\"Rename \\(field.originalKey)\")",
            ],
        ]

        for (relativePath, expectedSnippets) in criticalFiles {
            let content = try source(relativePath)
            for snippet in expectedSnippets {
                XCTAssertTrue(
                    content.contains(snippet),
                    "\(relativePath) must keep explicit accessibility label snippet: \(snippet)"
                )
            }
        }
    }

    func testDecorativeGlowAndNavigationIcons_areHiddenFromAccessibilityTree() throws {
        let criticalFiles = [
            // The heart and folder icons are semantic and labeled; only the three remaining layers are decorative.
            "HealthMd/iOS/Components/StatusIndicator.swift": 3,
            "HealthMd/iOS/Components/SectionCard.swift": 6,
            "HealthMd/iOS/Components/ExportModal.swift": 12,
            "HealthMd/iPad/iPadSidebar.swift": 3,
        ]

        for (relativePath, minimumHiddenCount) in criticalFiles {
            let content = try source(relativePath)
            let hiddenCount = content.components(separatedBy: ".accessibilityHidden(true)").count - 1
            XCTAssertGreaterThanOrEqual(
                hiddenCount,
                minimumHiddenCount,
                "\(relativePath) must hide decorative icons, status dots, and glow layers from VoiceOver"
            )
        }

        // Onboarding's production surface is split between the page and its
        // extracted accessibility components; preserve the original combined guard.
        let onboardingHiddenCount = try [
            "HealthMd/iOS/Views/OnboardingView.swift",
            "HealthMd/iOS/Components/OnboardingA11yComponents.swift",
        ].reduce(into: 0) { count, relativePath in
            count += try source(relativePath).components(separatedBy: ".accessibilityHidden(true)").count - 1
        }
        XCTAssertGreaterThanOrEqual(
            onboardingHiddenCount,
            12,
            "Onboarding must hide decorative icons and progress layers from VoiceOver"
        )
    }

    private func source(_ relativePath: String) throws -> String {
        let path = projectDir.appendingPathComponent(relativePath).path
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
