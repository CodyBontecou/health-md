//
//  LifecycleAuditTests.swift
//  HealthMdTests
//
//  Validates that the lifecycle audit report exists and contains expected sections.
//  Part of TODO-e4c602d1: Audit and catalog static-retention workarounds.
//

import XCTest

final class LifecycleAuditTests: XCTestCase {

    /// Resolve the project root from this source file's compile-time path.
    /// This file lives at HealthMdTests/Utilities/LifecycleAuditTests.swift,
    /// so walking up 3 levels reaches the project root.
    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // Utilities/
            .deletingLastPathComponent()  // HealthMdTests/
            .deletingLastPathComponent()  // project root
    }()

    private var auditReportURL: URL {
        Self.projectRoot.appendingPathComponent("docs/testing/lifecycle-audit.md")
    }

    // MARK: - Report existence

    func testAuditReport_exists() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: auditReportURL.path),
            "Lifecycle audit report must exist at docs/testing/lifecycle-audit.md"
        )
    }

    // MARK: - Required section headers

    func testAuditReport_containsSummarySection() throws {
        let content = try String(contentsOf: auditReportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("## Summary"), "Report must contain a Summary section")
    }

    func testAuditReport_containsAuditMatrix() throws {
        let content = try String(contentsOf: auditReportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("## Audit Matrix"), "Report must contain an Audit Matrix section")
    }

    func testAuditReport_containsClassificationKey() throws {
        let content = try String(contentsOf: auditReportURL, encoding: .utf8)
        XCTAssertTrue(
            content.contains("## Classification Key"),
            "Report must contain a Classification Key section"
        )
    }

    func testAuditReport_containsRecommendations() throws {
        let content = try String(contentsOf: auditReportURL, encoding: .utf8)
        XCTAssertTrue(
            content.contains("## Recommendations"),
            "Report must contain a Recommendations section"
        )
    }

    // MARK: - Matrix content validation

    func testAuditReport_matrixListsKnownFiles() throws {
        let content = try String(contentsOf: auditReportURL, encoding: .utf8)
        // These files are known to contain static retention patterns
        let expectedFiles = [
            "DailyNoteInjectorTests.swift",
            "ExporterSmokeTests.swift",
            "IndividualEntryExporterTests.swift",
            "ModelTests.swift"
        ]
        for file in expectedFiles {
            XCTAssertTrue(content.contains(file),
                          "Audit matrix must reference \(file)")
        }
    }

    func testAuditReport_matrixHasTableHeaders() throws {
        let content = try String(contentsOf: auditReportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("| File"), "Matrix table must have a File column")
        XCTAssertTrue(content.contains("Object Type"), "Matrix table must have an Object Type column")
    }
}
