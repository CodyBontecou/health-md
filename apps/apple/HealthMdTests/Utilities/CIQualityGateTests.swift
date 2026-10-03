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

    private enum OwnedPlanError: Error { case invalid }

    private func ownedPlan(_ content: String, marker: String) throws -> [String: Any] {
        let pieces = content.components(separatedBy: "<<'\(marker)'\n")
        guard pieces.count == 2,
              let end = pieces[1].range(of: "\n          \(marker)"),
              let data = String(pieces[1][..<end.lowerBound]).data(using: .utf8),
              let plan = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw OwnedPlanError.invalid }
        return plan
    }

    private var ownedSelections: [[String]] {
        [
            ["HealthMdUILaunchTests/testAppLaunches",
             "ExportJourneyUITests/testFirstRunExportJourney_showsExportButton_andCompletesExport",
             "ExportJourneyUITests/testDateRangePresets_visibleAndCustomPickersHiddenByDefault",
             "ExportJourneyUITests/testDateRangePresets_customRevealsStartAndEndPickers",
             "OnboardingJourneyUITests/testReleaseNotesStillAppearForReturningUsers",
             "PaywallJourneyUITests/testPaywallShown_whenQuotaExhausted",
             "ScheduleSyncJourneyUITests/testSyncView_showsDisconnectedState",
             "ConfigurationProtectionJourneyUITests/testProtectedProfileManagementBlocksCreationAndRoutesToSetting",
             "ConfigurationProtectionJourneyUITests/testProtectedProfileDetailActionsAreBlocked",
             "ConfigurationProtectionJourneyUITests/testProtectedProfileSchedulesCardIsLockedOnScheduleTab"],
            ["ConfigurationProtectionJourneyUITests/testBlockedChangeToastNavigatesToProtectionToggle",
             "ConfigurationProtectionJourneyUITests/testTurningProtectionOffRestoresConfigurationControls",
             "ExportProfilesJourneyUITests/testQA_MigrationShowsDefaultProfileInSettings",
             "ExportProfilesJourneyUITests/testQA_ManagementDuplicateRenameDeleteAndLastProfileGuard",
             "ExportProfilesJourneyUITests/testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter",
             "ExportProfilesJourneyUITests/testQA_ManageProfilesViewDetailCopyIDActivateAndRename",
             "HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide",
             "HistoryAuthorizationJourneyUITests/testBoundedUnknownHistoryRechecksExecutionWithoutClaimingFullAccess",
             "HistoryAuthorizationJourneyUITests/testDelayedAssessmentCanContinueUnverifiedWithoutBlockingReadableExport"],
            ["ExportJourneyUITests/testNoDataExport_showsGuidanceInsteadOfGenericError",
             "HistoryAuthorizationJourneyUITests/testUnavailableHistoryAtLargeTextHasAccessibleAction",
             "HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide",
             "HistoryAuthorizationJourneyUITests/testUnknownHistoryPreviewHasAccessibleActionOnNativeRoot"]
        ]
    }

    private func validatedOwnedUICommands(_ content: String) throws -> [[String]] {
        let phone = try ownedPlan(content, marker: "PHONE_PLAN")
        let tablet = try ownedPlan(content, marker: "IPAD_PLAN")
        guard let phonePipelines = phone["pipelines"] as? [[String: Any]], phonePipelines.count == 2,
              let tabletPipelines = tablet["pipelines"] as? [[String: Any]], tabletPipelines.count == 1,
              content.contains("test-ios-ui:\n    name: iOS UI regressions\n    needs: [changes, prepare-shared-core]\n    if: ${{ needs.changes.outputs.run == 'true' }}\n    runs-on: xcode-27\n    timeout-minutes: 60")
        else { throw OwnedPlanError.invalid }
        let phoneStep = content.components(separatedBy: "- name: Run UI smoke tests (iOS)").last?
            .components(separatedBy: "- name: Run App Review export regression (iPad)").first
        let tabletStep = content.components(separatedBy: "- name: Run App Review export regression (iPad)").last?
            .components(separatedBy: "- name: Check warnings (iOS UI)").first
        guard let phoneStep, let tabletStep,
              phoneStep.components(separatedBy: "timeout-minutes: 35\n").count == 2,
              tabletStep.components(separatedBy: "timeout-minutes: 15\n").count == 2,
              !phoneStep.contains("continue-on-error:"), !tabletStep.contains("continue-on-error:")
        else { throw OwnedPlanError.invalid }
        return try (phonePipelines + tabletPipelines).enumerated().map { index, pipeline in
            guard let command = pipeline["command"] as? [String], Array(command.prefix(2)) == ["xcodebuild", "test"],
                  command.filter({ $0.hasPrefix("-only-testing:") }) == ownedSelections[index].map({ "-only-testing:HealthMdUITests/" + $0 })
            else { throw OwnedPlanError.invalid }
            for (flag, value) in [("-test-timeouts-enabled", "YES"),
                                  ("-default-test-execution-time-allowance", "180"),
                                  ("-maximum-test-execution-time-allowance", "300")] {
                guard command.filter({ $0 == flag }).count == 1,
                      let position = command.firstIndex(of: flag), position + 1 < command.count,
                      command[position + 1] == value else { throw OwnedPlanError.invalid }
            }
            return command
        }
    }

    func testWorkflow_ownedUIActualJSONRejectsMutatedCommandsSelectorsFlagsAndBudgets() throws {
        let content = try String(contentsOfFile: appleCIWorkflowPath, encoding: .utf8)
        XCTAssertEqual(try validatedOwnedUICommands(content).map { $0.filter { $0.hasPrefix("-only-testing:") }.count }, [10, 9, 4])
        for marker in ["PHONE_PLAN", "IPAD_PLAN"] {
            let actual = try ownedPlan(content, marker: marker)
            let pipelines = try XCTUnwrap(actual["pipelines"] as? [[String: Any]])
            let command = try XCTUnwrap(pipelines[0]["command"] as? [String])
            var mutants: [[[String: Any]]] = [Array(pipelines.dropLast()), pipelines + [pipelines[0]]]
            var commandMutants: [[String]] = []
            var wrongCommand = command; wrongCommand[0] = "not-xcodebuild"; commandMutants.append(wrongCommand)
            var wrongOperation = command; wrongOperation[1] = "build"; commandMutants.append(wrongOperation)
            let selection = try XCTUnwrap(command.firstIndex(where: { $0.hasPrefix("-only-testing:") }))
            var omitted = command; omitted.remove(at: selection); commandMutants.append(omitted)
            var duplicated = command; duplicated.append(command[selection]); commandMutants.append(duplicated)
            var moved = command; moved.swapAt(selection, selection + 1); commandMutants.append(moved)
            for flag in ["-test-timeouts-enabled", "-default-test-execution-time-allowance", "-maximum-test-execution-time-allowance"] {
                let position = try XCTUnwrap(command.firstIndex(of: flag))
                var missing = command; missing.removeSubrange(position...position + 1); commandMutants.append(missing)
                var wrong = command; wrong[position + 1] = "0"; commandMutants.append(wrong)
            }
            if marker == "PHONE_PLAN" {
                var relocated = pipelines
                var first = try XCTUnwrap(relocated[0]["command"] as? [String])
                var second = try XCTUnwrap(relocated[1]["command"] as? [String])
                let firstID = try XCTUnwrap(first.firstIndex(where: { $0.hasPrefix("-only-testing:") }))
                let secondID = try XCTUnwrap(second.firstIndex(where: { $0.hasPrefix("-only-testing:") }))
                let saved = first[firstID]; first[firstID] = second[secondID]; second[secondID] = saved
                relocated[0]["command"] = first; relocated[1]["command"] = second
                mutants.append(relocated) // Same19/counts, WRONG invocation attribution.
            }
            for mutatedCommand in commandMutants {
                var mutated = pipelines; mutated[0]["command"] = mutatedCommand; mutants.append(mutated)
            }
            for mutated in mutants {
                var plan = actual; plan["pipelines"] = mutated
                let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: plan), encoding: .utf8))
                let start = try XCTUnwrap(content.range(of: "<<'\(marker)'\n")).upperBound
                let end = try XCTUnwrap(content.range(of: "\n          \(marker)", range: start..<content.endIndex)).lowerBound
                let changed = content.replacingCharacters(in: start..<end, with: json)
                XCTAssertThrowsError(try validatedOwnedUICommands(changed), "Actual \(marker) mutation must fail")
            }
        }
        for (before, after) in [("timeout-minutes: 35", "timeout-minutes: 36"),
                                ("timeout-minutes: 15", "timeout-minutes: 16"),
                                ("timeout-minutes: 60", "timeout-minutes: 61"),
                                ("- name: Run UI smoke tests (iOS)", "- name: Run UI smoke tests (iOS)\n        continue-on-error: true")] {
            XCTAssertThrowsError(try validatedOwnedUICommands(content.replacingOccurrences(of: before, with: after)))
        }
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
            content.contains("test-ios-ui:\n    name: iOS UI regressions\n    needs: [changes, prepare-shared-core]\n    if: ${{ needs.changes.outputs.run == 'true' }}\n    runs-on: xcode-27\n    timeout-minutes: 60"),
            "The split UI job must allow at least 60 minutes for clean builds"
        )
        XCTAssertEqual(
            content.components(separatedBy: "- name: Prepare and validate shared Rust core for Apple").count - 1,
            1,
            "Apple CI must build the exact shared-core XCFramework only once"
        )
        XCTAssertEqual(
            content.components(separatedBy: "needs: [changes, prepare-shared-core]").count - 1,
            3,
            "All Xcode test jobs must consume the single prepared shared-core artifact"
        )
        let commands = try validatedOwnedUICommands(content)
        XCTAssertEqual(commands.count, 3, "Two phone and one tablet native invocation must remain bounded")
        let smokeStep = try XCTUnwrap(
            content.components(separatedBy: "- name: Run UI smoke tests (iOS)").last?
                .components(separatedBy: "- name: Run App Review export regression (iPad)").first
        )
        XCTAssertFalse(
            smokeStep.contains("continue-on-error: true"),
            "Selected PR UI smoke failures must remain blocking"
        )
        let smokeInvocations = Array(commands.prefix(2))
        XCTAssertEqual(smokeInvocations.count, 2, "PR smoke must use two deterministic test invocations")
        for invocation in smokeInvocations {
            let selectionCount = invocation.filter { $0.hasPrefix("-only-testing:HealthMdUITests/") }.count
            XCTAssertGreaterThan(selectionCount, 0, "Each PR smoke invocation must select tests explicitly")
            XCTAssertLessThanOrEqual(selectionCount, 10, "Each PR smoke invocation must remain bounded")
        }
        let smokeSelectionCount = smokeStep.components(separatedBy: "-only-testing:HealthMdUITests/").count - 1
        XCTAssertEqual(smokeSelectionCount, 19, "PR smoke must preserve all 16 regressions plus three history journeys")
        XCTAssertEqual(content.components(separatedBy: "runs-on: xcode-27").count - 1, 4,
                       "All native consumers and the single producer must use the verified free SDK27 runner")
        XCTAssertEqual(content.components(separatedBy: "name: apple-sdk27-shared-core").count - 1, 4,
                       "The producer and all three consumers must share the SDK27 artifact namespace")
        XCTAssertTrue(content.contains("apple-shared-core-sdk27-27A266a-"))
        XCTAssertEqual(content.components(separatedBy: "cmp build/logs/history-sdk27-receipt.txt").count - 1, 3,
                       "All native consumers must verify producer SDK/target/head/tree provenance")
        XCTAssertTrue(smokeStep.contains("HistoryAuthorizationJourneyUITests/testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide"))
        XCTAssertTrue(smokeStep.contains("HistoryAuthorizationJourneyUITests/testBoundedUnknownHistoryRechecksExecutionWithoutClaimingFullAccess"))
        XCTAssertTrue(content.contains("HistoryAuthorizationJourneyUITests/testUnavailableHistoryAtLargeTextHasAccessibleAction"))
        XCTAssertTrue(smokeStep.contains("HistoryAuthorizationJourneyUITests/testDelayedAssessmentCanContinueUnverifiedWithoutBlockingReadableExport"))
        let qualifier = try String(contentsOf: projectDir.appendingPathComponent("scripts/qualify-history-authorization-sdk27.sh"), encoding: .utf8)
        XCTAssertTrue(qualifier.contains("Xcode 27.0\\nBuild version 27A266a"))
        XCTAssertTrue(qualifier.contains("swiftlang-6.4.0.34.1 clang-2100.3.34.1"))
        XCTAssertTrue(qualifier.contains("[[ \"$sdk_version\" == 27.0 ]]"))
        XCTAssertFalse(qualifier.contains("== 27.*"), "Floating SDK versions cannot relabel the pinned shared-core cache")
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
