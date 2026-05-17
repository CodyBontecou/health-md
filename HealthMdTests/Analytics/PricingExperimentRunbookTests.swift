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
            "HealthMd/iOS/Views/PaywallView.swift",
            "HealthMd/macOS/Views/MacPaywallView.swift"
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
            "paywall complaints",
            "Results status: pending"
        ]

        for text in requiredText {
            XCTAssertTrue(
                runbook.contains(text),
                "Pricing experiment runbook should include '\(text)'."
            )
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
