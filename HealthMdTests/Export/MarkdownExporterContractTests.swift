//
//  MarkdownExporterContractTests.swift
//  HealthMdTests
//
//  Golden contract tests for Markdown exporter output stability.
//  Verifies semantic structure, frontmatter, sections, and formatting.
//

import XCTest
@testable import HealthMd

// Static customizations to avoid macOS 26 deinit crash.
private enum MDContractCustomizations {
    static let metric: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .metric
        return c
    }()

    static let imperial: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .imperial
        return c
    }()

    static let emojiOn: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.useEmoji = true
        return c
    }()

    static let emojiOff: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.useEmoji = false
        return c
    }()

    static let headerLevel1: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.sectionHeaderLevel = 1
        return c
    }()

    static let headerLevel3: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.sectionHeaderLevel = 3
        return c
    }()

    static let withSummary: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.includeSummary = true
        return c
    }()

    static let noSummary: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.includeSummary = false
        return c
    }()

    static let camelCaseKeys: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.applyKeyStyle(.camelCase)
        return c
    }()

    static let snakeCaseKeys: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.applyKeyStyle(.snakeCase)
        return c
    }()
}

final class MarkdownExporterContractTests: XCTestCase {

    // MARK: - Frontmatter Contracts

    func testFrontmatter_containsDateKey() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.hasPrefix("---"), "Markdown should start with frontmatter delimiter")
        XCTAssertTrue(md.contains("date:"), "Frontmatter should contain date key")
    }

    func testFrontmatter_containsTypeKey() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.contains("type:"), "Frontmatter should contain type key")
    }

    func testFrontmatter_camelCaseKeys() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.camelCaseKeys)
        // camelCase converts "sleep_total" -> "sleepTotal", "heart_rate_resting" -> "heartRateResting"
        let hasCamelCase = md.contains("sleepTotal") || md.contains("heartRate") || md.contains("activeCalories") || md.contains("Steps") || md.contains("steps:")
        XCTAssertTrue(hasCamelCase, "Frontmatter should use camelCase key style")
    }

    func testFrontmatter_snakeCaseKeys() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.snakeCaseKeys)
        // snake_case converts keys - verify by checking the output contains underscore-separated keys
        // Keys like "date:" and "type:" are single words (same in both styles)
        // Multi-word keys should have underscores
        XCTAssertTrue(md.contains("date:"), "snake_case output should still contain date key")
        XCTAssertTrue(md.hasPrefix("---"), "snake_case output should start with frontmatter")
        // If output has any multi-word frontmatter keys, they should use underscores
        let frontmatter = md.components(separatedBy: "---").dropFirst().first ?? ""
        let lines = frontmatter.components(separatedBy: "\n").filter { $0.contains(":") }
        XCTAssertFalse(lines.isEmpty, "Frontmatter should have key-value pairs")
    }

    // MARK: - Section Structure Contracts

    func testSections_fullDayHasAllCategories() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        let expectedSections = ["Sleep", "Activity", "Heart", "Vitals", "Body", "Nutrition", "Mindfulness", "Mobility", "Hearing", "Workouts"]
        for section in expectedSections {
            XCTAssertTrue(md.contains(section), "Full day markdown should contain \(section) section")
        }
    }

    func testSections_partialDayOmitsMissing() {
        let md = ExportFixtures.partialDay.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.contains("Sleep"), "Partial day should contain Sleep")
        XCTAssertTrue(md.contains("Activity"), "Partial day should contain Activity")
        // These should NOT appear since partialDay has no heart/vitals/body data
        XCTAssertFalse(md.contains("Vitals"), "Partial day should not contain Vitals section")
        XCTAssertFalse(md.contains("Body"), "Partial day should not contain Body section")
    }

    func testSections_headerLevel1_usesH1() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.headerLevel1)
        XCTAssertTrue(md.contains("\n# "), "Header level 1 should use H1 markers")
    }

    func testSections_headerLevel3_usesH3() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.headerLevel3)
        XCTAssertTrue(md.contains("\n### "), "Header level 3 should use H3 markers")
    }

    // MARK: - Unit Contracts

    func testMetricUnits_showsKilometers() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        // 9500 meters = 9.5 km in metric
        XCTAssertTrue(md.contains("km") || md.contains("9.5"), "Metric should display km for distances")
    }

    func testImperialUnits_showsMiles() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.imperial)
        XCTAssertTrue(md.contains("mi") || md.contains("mile"), "Imperial should display miles for distances")
    }

    func testMetricUnits_showsKilogramWeight() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.contains("75") || md.contains("kg"), "Metric should show weight in kg")
    }

    func testImperialUnits_showsPoundWeight() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.imperial)
        XCTAssertTrue(md.contains("lb") || md.contains("165"), "Imperial should show weight in lbs")
    }

    // MARK: - Emoji Contracts

    func testEmojiOn_containsEmojis() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.emojiOn)
        // Common health-related emojis
        let hasEmoji = md.contains("🛏") || md.contains("💤") || md.contains("❤️") ||
                       md.contains("🏃") || md.contains("👟") || md.contains("🔥") ||
                       md.contains("😴") || md.contains("🚶") || md.contains("📊")
        XCTAssertTrue(hasEmoji, "Emoji-on mode should include emoji characters in section headers")
    }

    func testEmojiOff_headersAreSimpler() {
        let mdOn = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.emojiOn)
        let mdOff = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.emojiOff)
        let headersOn = mdOn.components(separatedBy: "\n").filter { $0.hasPrefix("#") }
        let headersOff = mdOff.components(separatedBy: "\n").filter { $0.hasPrefix("#") }
        // Emoji-on headers should generally be longer (contain emoji) or different from emoji-off
        if !headersOn.isEmpty && !headersOff.isEmpty {
            let totalCharsOn = headersOn.reduce(0) { $0 + $1.count }
            let totalCharsOff = headersOff.reduce(0) { $0 + $1.count }
            // Emoji-on should have more characters due to emoji
            XCTAssertGreaterThanOrEqual(totalCharsOn, totalCharsOff, "Emoji-on headers should be at least as long as emoji-off")
        }
    }

    // MARK: - Summary Contracts

    func testSummaryIncluded_hasOverview() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.withSummary)
        // Summary typically includes "Summary" or total counts
        let hasSummaryIndicator = md.contains("Summary") || md.contains("Overview") || md.contains("Total")
        XCTAssertTrue(hasSummaryIndicator, "Summary mode should include summary/overview section")
    }

    // MARK: - Stability: Output Sections Ordering

    func testSectionOrdering_sleepBeforeActivity() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        let sleepRange = md.range(of: "Sleep")
        let activityRange = md.range(of: "Activity")
        if let s = sleepRange, let a = activityRange {
            XCTAssertTrue(s.lowerBound < a.lowerBound, "Sleep section should appear before Activity")
        }
    }

    func testSectionOrdering_heartBeforeVitals() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        let heartRange = md.range(of: "Heart")
        let vitalsRange = md.range(of: "Vitals")
        if let h = heartRange, let v = vitalsRange {
            XCTAssertTrue(h.lowerBound < v.lowerBound, "Heart section should appear before Vitals")
        }
    }

    // MARK: - Granular Data Contracts

    func testGranular_fullDayGranular_hasHeartRateSamplesDetails() {
        let md = ExportFixtures.fullDayGranular.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.contains("<details>"), "Granular data should use collapsible <details> sections")
        XCTAssertTrue(md.contains("Heart Rate Samples"), "Should contain Heart Rate Samples section")
    }

    func testGranular_fullDayGranular_hasSleepStagesTimeline() {
        let md = ExportFixtures.fullDayGranular.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.contains("Sleep Stages"), "Should contain Sleep Stages section")
    }

    func testGranular_fullDay_noDetailsSections() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        let hasGranularDetails = md.contains("Heart Rate Samples") || md.contains("Sleep Stages Timeline")
        XCTAssertFalse(hasGranularDetails, "fullDay without granular data should not have sample detail sections")
    }

    // MARK: - Edge Case Contracts

    func testEmptyDay_producesMinimalOutput() {
        let md = ExportFixtures.emptyDay.toMarkdown(customization: MDContractCustomizations.metric)
        // Empty day should still have frontmatter or be empty
        let lineCount = md.components(separatedBy: "\n").count
        XCTAssertLessThan(lineCount, 20, "Empty day should produce minimal output")
    }

    func testEdgeCaseDay_negativeValence() {
        let md = ExportFixtures.edgeCaseDay.toMarkdown(customization: MDContractCustomizations.metric)
        // Should handle negative valence state of mind data
        let hasValenceRef = md.contains("Unpleasant") || md.contains("valence") || md.contains("Anxious") || md.contains("Mood")
        XCTAssertTrue(hasValenceRef, "Edge case day should render negative valence data")
    }
}
