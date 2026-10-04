//
//  PricingExperimentRunbookTests.swift
//  HealthMdTests
//
//  Regression coverage for the first sequential pricing experiment controls.
//

import XCTest

final class PricingExperimentRunbookTests: XCTestCase {

    func testProductionCopyDoesNotHardcodePreviousLifetimePrice() throws {
        let projectRoot = try locateProjectRoot()
        let sourcePaths = [
            "HealthMd/iOS/Views/OnboardingView.swift",
            "HealthMd/iOS/ContentView.swift",
            "HealthMd/iOS/Views/PaywallView.swift"
        ]

        for sourcePath in sourcePaths {
            let source = try String(
                contentsOf: projectRoot.appendingPathComponent(sourcePath),
                encoding: .utf8
            )

            XCTAssertFalse(
                source.contains("$9.99"),
                "\(sourcePath) should use StoreKit displayPrice or a price-agnostic fallback."
            )
        }
    }

    func test1499ExperimentRunbookCapturesControlGates() throws {
        let projectRoot = try locateProjectRoot()
        let runbookURL = projectRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("experiments")
            .appendingPathComponent("health-md-1499-lifetime-price-experiment.md")
        let runbook = try String(contentsOf: runbookURL, encoding: .utf8)

        let requiredText = [
            "Baseline window",
            "Minimum sample",
            "$14.99 test window",
            "Free-export limit remains 3",
            "App Store Connect change steps",
            "Rollback steps",
            "net revenue per activated user",
            "Support messages",
            "refunds",
            "ratings/reviews",
            "paywall complaints"
        ]

        for text in requiredText {
            XCTAssertTrue(
                runbook.contains(text),
                "Pricing experiment runbook should include '\(text)'."
            )
        }

        XCTAssertEqual(resultsStatusIssues(in: runbook, at: runbookURL), [],
                       "The plan must declare a truthful results status and link current evidence when superseded.")
    }

    func testResultsStatusAllowsPendingOrHistoricalWithReadableOperationalEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runbookURL = root.appendingPathComponent("apps/apple/docs/experiments/plan.md")
        for link in operationalResultsLinks {
            let target = runbookURL.deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "# Recorded pricing evidence\n".write(to: target, atomically: true, encoding: .utf8)
        }
        let pending = "- Results status: pending\n"
        let historical = "## Historical status\nThis plan is superseded as an operational runbook.\n"
            + operationalResultsLinks.map { "[Current evidence](\($0))" }.joined(separator: "\n")
        XCTAssertEqual(resultsStatusIssues(in: pending, at: runbookURL), [])
        XCTAssertEqual(resultsStatusIssues(in: historical, at: runbookURL), [])
        XCTAssertFalse(resultsStatusIssues(in: "No results status", at: runbookURL).isEmpty)
        XCTAssertFalse(resultsStatusIssues(in: "- Results status: completed", at: runbookURL).isEmpty,
                       "Completed results cannot be asserted without evidence.")
        XCTAssertFalse(resultsStatusIssues(in: pending + historical, at: runbookURL).isEmpty,
                       "A superseded operational plan must not still claim pending results.")
        for link in operationalResultsLinks {
            XCTAssertFalse(resultsStatusIssues(in: historical.replacingOccurrences(of: link, with: "missing.md"),
                                               at: runbookURL).isEmpty)
            let target = runbookURL.deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL
            try "".write(to: target, atomically: true, encoding: .utf8)
            XCTAssertFalse(resultsStatusIssues(in: historical, at: runbookURL).isEmpty,
                           "An empty evidence file must not qualify a historical plan.")
            try FileManager.default.removeItem(at: target)
            XCTAssertFalse(resultsStatusIssues(in: historical, at: runbookURL).isEmpty,
                           "A broken evidence link must not qualify a historical plan.")
            try "# Recorded pricing evidence\n".write(to: target, atomically: true, encoding: .utf8)
        }
    }

    private var operationalResultsLinks: [String] {
        ["../../../../docs/experiments/index.md",
         "../../../../docs/experiments/2026-09-17-19.99-lifetime-price.md"]
    }

    private func resultsStatusIssues(in runbook: String, at runbookURL: URL) -> [String] {
        let pending = runbook.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces) == "- Results status: pending"
        }
        let historical = runbook.contains("## Historical status")
            && runbook.contains("superseded as an operational runbook")
        guard pending != historical else {
            return ["Expected either pending results or an explicitly superseded historical plan, not neither/both."]
        }
        guard historical else { return [] }
        return operationalResultsLinks.compactMap { link in
            guard runbook.contains("](\(link))") else { return "Missing operational evidence link: \(link)" }
            let target = runbookURL.deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL
            guard let evidence = try? String(contentsOf: target, encoding: .utf8),
                  !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Operational evidence must exist and be readable/nonempty: \(link)"
            }
            return nil
        }
    }

    private func locateProjectRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("HealthMd.xcodeproj")
                    .path
            ) {
                return directory
            }

            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "PricingExperimentRunbookTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate project root from \(#filePath)."]
        )
    }
}
