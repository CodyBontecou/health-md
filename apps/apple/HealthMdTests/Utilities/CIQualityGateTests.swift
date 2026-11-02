// Host-only guards for the current portable CI and opt-in native diagnostics.
// The former per-platform/nightly job graph was retired by the two-minute CI
// strategy. Do not restore those mandatory jobs just to satisfy old assertions.
import Foundation
import XCTest

final class CIQualityGateTests: XCTestCase {
    private var projectDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var monorepoRoot: URL {
        projectDir.deletingLastPathComponent().deletingLastPathComponent()
    }

    func testPortableWorkflowUsesOneBoundedHostJobAndFreshResults() throws {
        let workflow = try String(contentsOf: monorepoRoot.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
        for snippet in ["name: CI", "runs-on: ubuntu-24.04", "timeout-minutes: 2",
                        "run: python3 scripts/ci/run.py", "run: python3 scripts/ci/verify_run.py",
                        "if: ${{ !cancelled() }}", "cancel-in-progress: ${{ !inputs.release_sha }}"] {
            XCTAssertTrue(workflow.contains(snippet), "Portable CI must retain: \(snippet)")
        }
        XCTAssertFalse(workflow.contains("continue-on-error"))
        XCTAssertFalse(workflow.contains("xcodebuild"))
        XCTAssertFalse(workflow.contains("simctl"))
        let wrapper = try String(contentsOf: monorepoRoot.appendingPathComponent(".github/workflows/apple-ci.yml"), encoding: .utf8)
        XCTAssertTrue(wrapper.contains("uses: ./.github/workflows/ci.yml"))
        XCTAssertTrue(wrapper.contains("release_sha: ${{ inputs.release_sha || github.sha }}"))
    }

    func testNativeDiagnosticsRemainExplicitAndPreserveLogsAndTimeouts() throws {
        let makefile = try source("Makefile")
        for snippet in ["test: test-ios test-macos", "coverage: prepare-healthmd-core-rust",
                        "XCODE_TEST_TIMEOUT_FLAGS := -test-timeouts-enabled YES",
                        "-resultBundlePath \"$(IOS_XCRESULT_PATH)\"", "tee \"$(IOS_TEST_RAW_LOG)\"",
                        "-test-timeouts-enabled NO", "-enableCodeCoverage YES"] {
            XCTAssertTrue(makefile.contains(snippet), "Native diagnostic must retain: \(snippet)")
        }
        let policy = try String(contentsOf: monorepoRoot.appendingPathComponent("docs/qa/two-minute-ci.md"), encoding: .utf8)
        XCTAssertTrue(policy.contains("not PR regression"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: monorepoRoot.appendingPathComponent(".github/workflows/apple-nightly.yml").path))
    }

    func testDiagnosticScriptsAndConfigsRemainAvailable() throws {
        for script in ["check-coverage.sh", "check-warnings.sh", "check-tdd-evidence.sh"] {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: projectDir.appendingPathComponent("scripts/\(script)").path))
        }
        for (file, key) in [("coverage-thresholds.json", "minimum_coverage"), ("warning-baseline.json", "allowed_count")] {
            let data = try Data(contentsOf: projectDir.appendingPathComponent(".ci/\(file)"))
            let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNotNil(config[key], "\(file) must declare \(key)")
        }
    }

    #if os(macOS)
    func testDiagnosticScriptsFailOnMissingExplicitInput() throws {
        for (script, arguments, extra) in [
            ("check-coverage.sh", ["/nonexistent/path.xcresult"], [String: String]()),
            ("check-warnings.sh", ["/nonexistent/build.log"], [String: String]()),
            ("check-tdd-evidence.sh", [], ["TODOS_DIR": "/nonexistent/todos"]),
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [projectDir.appendingPathComponent("scripts/\(script)").path] + arguments
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
                                   "CI_CONFIG_DIR": projectDir.appendingPathComponent(".ci").path]
                .merging(extra, uniquingKeysWith: { _, new in new })
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertNotEqual(process.terminationStatus, 0, "\(script) must fail on missing input")
        }
    }
    #endif

    func testDiagnosticRunbookCoversRetainedGates() throws {
        let content = try source("docs/testing/CI-QUALITY-GATES.md")
        for snippet in ["check-coverage", "check-warnings", "check-tdd-evidence", "coverage-thresholds", "warning-baseline"] {
            XCTAssertTrue(content.contains(snippet))
        }
    }

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
                XCTAssertTrue(content.contains(snippet), "\(relativePath) must keep accessibility label: \(snippet)")
            }
        }
    }

    func testDecorativeGlowAndNavigationIcons_areHiddenFromAccessibilityTree() throws {
        let criticalFiles = [
            "HealthMd/iOS/Components/StatusIndicator.swift": 3,
            "HealthMd/iOS/Components/SectionCard.swift": 6,
            "HealthMd/iOS/Components/ExportModal.swift": 12,
            "HealthMd/iPad/iPadSidebar.swift": 3,
        ]
        for (relativePath, minimumHiddenCount) in criticalFiles {
            let hiddenCount = try source(relativePath).components(separatedBy: ".accessibilityHidden(true)").count - 1
            XCTAssertGreaterThanOrEqual(hiddenCount, minimumHiddenCount, "\(relativePath) must hide decorative layers")
        }
        let onboardingHiddenCount = try [
            "HealthMd/iOS/Views/OnboardingView.swift",
            "HealthMd/iOS/Components/OnboardingA11yComponents.swift",
        ].reduce(into: 0) { count, relativePath in
            count += try source(relativePath).components(separatedBy: ".accessibilityHidden(true)").count - 1
        }
        XCTAssertGreaterThanOrEqual(onboardingHiddenCount, 12)
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectDir.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
