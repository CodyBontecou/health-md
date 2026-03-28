//
//  ExportFixtureTests.swift
//  HealthMdTests
//
//  TDD tests for export fixture datasets and golden test harness.
//

import XCTest
@testable import HealthMd

// Static so they are never deallocated — avoids the macOS 26 / Swift 6
// reentrant-main-actor-deinit crash in ObservableObject teardown.
private enum FixtureCustomizations {
    static let standard = FormatCustomization()
}

final class ExportFixtureTests: XCTestCase {

    // MARK: - Fixture Integrity

    func testEmptyDay_hasNoData() {
        let data = ExportFixtures.emptyDay
        XCTAssertFalse(data.hasAnyData)
    }

    func testPartialDay_hasSomeData() {
        let data = ExportFixtures.partialDay
        XCTAssertTrue(data.hasAnyData)
        XCTAssertTrue(data.sleep.hasData)
        XCTAssertTrue(data.activity.hasData)
        XCTAssertFalse(data.heart.hasData)
        XCTAssertFalse(data.vitals.hasData)
    }

    func testFullDay_hasAllCategories() {
        let data = ExportFixtures.fullDay
        XCTAssertTrue(data.sleep.hasData)
        XCTAssertTrue(data.activity.hasData)
        XCTAssertTrue(data.heart.hasData)
        XCTAssertTrue(data.vitals.hasData)
        XCTAssertTrue(data.body.hasData)
        XCTAssertTrue(data.nutrition.hasData)
        XCTAssertTrue(data.mindfulness.hasData)
        XCTAssertTrue(data.mobility.hasData)
        XCTAssertTrue(data.hearing.hasData)
        XCTAssertFalse(data.workouts.isEmpty)
    }

    func testEdgeCaseDay_hasMixedData() {
        let data = ExportFixtures.edgeCaseDay
        // Sleep has zero values but hasData checks totalDuration > 0
        XCTAssertFalse(data.sleep.hasData)
        // Activity has steps=0, which is non-nil
        XCTAssertTrue(data.activity.hasData)
        // Heart has averageHeartRate=0 (non-nil)
        XCTAssertTrue(data.heart.hasData)
        // Mindfulness has state of mind with negative valence
        XCTAssertTrue(data.mindfulness.hasData)
        XCTAssertEqual(data.mindfulness.stateOfMind.first?.valence, -0.8)
    }

    func testFixtures_useDeterministicDate() {
        let date = ExportFixtures.referenceDate
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    // MARK: - Golden Harness

    func testGoldenMatch_identical() {
        // Should not fail - identical strings match
        assertGoldenMatch("hello\nworld", expected: "hello\nworld")
    }

    func testNormalize_trimsTrailingWhitespace() {
        let input = "line1   \nline2\t\nline3"
        let normalized = normalizeExportOutput(input)
        XCTAssertEqual(normalized, "line1\nline2\nline3")
    }

    func testNormalize_trimsLeadingTrailingNewlines() {
        let input = "\n\nhello\n\n"
        let normalized = normalizeExportOutput(input)
        XCTAssertEqual(normalized, "hello")
    }

    // MARK: - Export Contract Smoke (fixtures produce output)

    func testPartialDay_markdownNotEmpty() {
        let data = ExportFixtures.partialDay
        let markdown = data.toMarkdown(customization: FixtureCustomizations.standard)
        XCTAssertFalse(markdown.isEmpty)
        XCTAssertTrue(markdown.contains("Sleep"), "Markdown should contain Sleep section")
    }

    func testFullDay_jsonNotEmpty() {
        let data = ExportFixtures.fullDay
        let json = data.toJSON(customization: FixtureCustomizations.standard)
        XCTAssertFalse(json.isEmpty)
        // Verify it's valid JSON
        let jsonData = json.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: jsonData))
    }

    func testFullDay_csvNotEmpty() {
        let data = ExportFixtures.fullDay
        let csv = data.toCSV(customization: FixtureCustomizations.standard)
        XCTAssertFalse(csv.isEmpty)
        XCTAssertTrue(csv.contains("Date,Category,Metric,Value,Unit"), "CSV should have header row")
    }

    func testEmptyDay_markdownMinimal() {
        let data = ExportFixtures.emptyDay
        let markdown = data.toMarkdown(customization: FixtureCustomizations.standard)
        // Empty day should still produce frontmatter at minimum
        XCTAssertTrue(markdown.contains("---") || markdown.isEmpty)
    }
}
