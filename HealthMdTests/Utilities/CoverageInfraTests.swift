//
//  CoverageInfraTests.swift
//  HealthMdTests
//
//  Validates that the Makefile exposes coverage targets.
//  These tests verify the build infrastructure supports coverage collection.
//

import XCTest

final class CoverageInfraTests: XCTestCase {

    func testMakefile_hasCoverageTarget() throws {
        // Locate Makefile relative to the project
        let projectDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Utilities
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // app

        let makefilePath = projectDir.appendingPathComponent("Makefile").path
        let content = try String(contentsOfFile: makefilePath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("coverage"),
            "Makefile should contain a coverage-related target"
        )
        XCTAssertTrue(
            content.contains("-enableCodeCoverage YES"),
            "Makefile should enable code coverage in xcodebuild flags"
        )
    }

    func testMakefile_hasCoverageReportTarget() throws {
        let projectDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let makefilePath = projectDir.appendingPathComponent("Makefile").path
        let content = try String(contentsOfFile: makefilePath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("coverage-report"),
            "Makefile should contain a coverage-report target"
        )
    }
}
