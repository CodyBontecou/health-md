//
//  SanitizerGateTests.swift
//  HealthMdTests
//
//  Validates that the sanitizer/diagnostic infrastructure exists and the
//  lifecycle audit is up to date.
//  Part of TODO-e8508ecb / E6 lifecycle stress epic.
//

import XCTest

final class SanitizerGateTests: XCTestCase {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // Support/
            .deletingLastPathComponent()  // HealthMdTests/
            .deletingLastPathComponent()  // project root
    }()

    // MARK: - Makefile target existence

    func testMakefile_containsTsanTarget() throws {
        let makefile = try String(
            contentsOf: Self.projectRoot.appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        XCTAssertTrue(
            makefile.contains("test-tsan:"),
            "Makefile must define a test-tsan target"
        )
        XCTAssertTrue(
            makefile.contains("-enableThreadSanitizer YES"),
            "test-tsan must enable Thread Sanitizer"
        )
    }

    // MARK: - Lifecycle audit is current

    func testLifecycleAudit_reflectsE6Migrations() throws {
        let audit = try String(
            contentsOf: Self.projectRoot.appendingPathComponent("docs/testing/lifecycle-audit.md"),
            encoding: .utf8
        )
        // After E6 migrations, the audit should reference LifecycleHarness
        XCTAssertTrue(
            audit.contains("LifecycleHarness"),
            "Audit should document LifecycleHarness migration"
        )
        // Should document that mutable instances were migrated
        XCTAssertTrue(
            audit.contains("per-test factory"),
            "Audit should document per-test factory pattern"
        )
    }

    // MARK: - No hidden workarounds

    func testNoUnexplainedStaticRetention() throws {
        let testDir = Self.projectRoot.appendingPathComponent("HealthMdTests")
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: testDir, includingPropertiesForKeys: nil)!

        var violations: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let filename = url.lastPathComponent

            // Skip test support/infrastructure files
            if filename == "LifecycleHarness.swift" ||
               filename == "SanitizerGateTests.swift" { continue }

            // Check for static var arrays of ObservableObject types
            // that aren't using LifecycleHarness and lack justification
            let lines = content.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("static var retained") ||
                   trimmed.contains("static var _retained") {
                    // Check if there's a justification comment nearby
                    let context = lines[max(0, i-3)...min(lines.count-1, i+1)]
                        .joined(separator: "\n")
                    if !context.contains("JUSTIFICATION") &&
                       !context.contains("LifecycleHarness") &&
                       !context.contains("lifecycle-audit") {
                        violations.append("\(filename):\(i+1) — unexplained static var retained")
                    }
                }
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "Found unexplained static retention:\n" + violations.joined(separator: "\n")
        )
    }
}
