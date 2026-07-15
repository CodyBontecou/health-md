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

    static let stepsDisabled: FormatCustomization = {
        let c = FormatCustomization()
        if let idx = c.frontmatterConfig.fields.firstIndex(where: { $0.originalKey == "steps" }) {
            c.frontmatterConfig.fields[idx].isEnabled = false
        }
        return c
    }()

    static let customMetricKey: FormatCustomization = {
        let c = FormatCustomization()
        if let idx = c.frontmatterConfig.fields.firstIndex(where: { $0.originalKey == "steps" }) {
            c.frontmatterConfig.fields[idx].customKey = "dailySteps"
        }
        return c
    }()
}

final class MarkdownExporterContractTests: XCTestCase {

    // MARK: - Helpers

    /// Parse only the leading YAML frontmatter block from a Markdown export.
    private func parseFrontmatter(_ data: HealthData, customization: FormatCustomization = MDContractCustomizations.metric) -> [(key: String, value: String)] {
        parseFrontmatterString(data.toMarkdown(customization: customization))
    }

    private func parseFrontmatterString(_ output: String) -> [(key: String, value: String)] {
        let lines = output.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }

        var pairs: [(key: String, value: String)] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.isEmpty { continue }
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                pairs.append((key: key, value: val))
            }
        }
        return pairs
    }

    private func keySet(_ pairs: [(key: String, value: String)]) -> Set<String> {
        Set(pairs.map { $0.key })
    }

    private func value(for key: String, in pairs: [(key: String, value: String)]) -> String? {
        pairs.first(where: { $0.key == key })?.value
    }

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

    func testFrontmatter_containsExplicitTimeContext() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.contains("time_context:\n  calendar_timezone: UTC\n  timestamp_timezone: UTC"))
    }

    func testFrontmatter_containsEnabledHealthMetricKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("sleep_total_hours"), "Markdown frontmatter should include enabled sleep metric fields")
        XCTAssertTrue(keys.contains("steps"), "Markdown frontmatter should include enabled activity metric fields")
        XCTAssertTrue(keys.contains("resting_heart_rate"), "Markdown frontmatter should include enabled heart metric fields")
    }

    func testFrontmatter_healthMetricValuesArePopulated() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        XCTAssertEqual(value(for: "steps", in: pairs), "12500", "Markdown frontmatter should include the exported metric value")
    }

    func testFrontmatter_camelCaseKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: MDContractCustomizations.camelCaseKeys)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("sleepTotalHours"), "camelCase should have sleepTotalHours")
        XCTAssertTrue(keys.contains("activeCalories"), "camelCase should have activeCalories")
        XCTAssertFalse(keys.contains("sleep_total_hours"), "camelCase should not keep snake_case metric keys")
    }

    func testFrontmatter_snakeCaseKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: MDContractCustomizations.snakeCaseKeys)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("sleep_total_hours"), "snake_case should have sleep_total_hours")
        XCTAssertTrue(keys.contains("active_calories"), "snake_case should have active_calories")
        XCTAssertFalse(keys.contains("sleepTotalHours"), "snake_case should not contain camelCase metric keys")
    }

    func testFrontmatter_disabledMetricKeyAbsent() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: MDContractCustomizations.stepsDisabled)
        let keys = keySet(pairs)
        XCTAssertFalse(keys.contains("steps"), "Disabled metric fields should not appear in Markdown frontmatter")
        XCTAssertTrue(keys.contains("active_calories"), "Other enabled metric fields should still appear")
    }

    func testFrontmatter_customMetricKeyRespected() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: MDContractCustomizations.customMetricKey)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("dailySteps"), "Custom frontmatter key should be used for Markdown metric fields")
        XCTAssertEqual(value(for: "dailySteps", in: pairs), "12500")
        XCTAssertFalse(keys.contains("steps"), "Original key should not appear when a custom key is configured")
    }

    // MARK: - Section Structure Contracts

    func testSections_fullDayHasAllCategories() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        let expectedSections = ["Sleep", "Activity", "Heart", "Vitals", "Body", "Nutrition", "Mindfulness", "Mobility", "Hearing", "Workouts", "Medications"]
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

    // MARK: - Medication Contracts

    func testMedications_frontmatterListTokensDoNotContainCommaSeparatorsInsideNames() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        data.medications = MedicationsData(
            medications: [
                Medication(
                    conceptIdentifier: "rxnorm:243670",
                    displayName: "Aspirin, 81 mg Oral Tablet",
                    nickname: nil,
                    generalForm: "tablet",
                    isArchived: false,
                    hasSchedule: false,
                    relatedCodings: []
                )
            ],
            doseEvents: []
        )

        let md = data.toMarkdown(customization: MDContractCustomizations.metric)

        XCTAssertTrue(md.contains("medications: [aspirin-81-mg-oral-tablet]"), md)
        XCTAssertFalse(md.contains("aspirin,"), md)
    }

    func testMedications_htmlLikeHealthKitIdentifiersAreEscapedInDetailsTables() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        let conceptID = "<HKHealthConceptIdentifier: 0x11b5a6200>"
        let doseTime = Calendar(identifier: .gregorian).date(byAdding: .hour, value: 9, to: ExportFixtures.referenceDate)!

        data.medications = MedicationsData(
            medications: [
                Medication(
                    conceptIdentifier: conceptID,
                    displayName: "Centrum Silver Tablet",
                    nickname: nil,
                    generalForm: "tablet",
                    isArchived: false,
                    hasSchedule: true,
                    relatedCodings: [
                        MedicationCoding(system: "urn:apple:health:ontology", version: nil, code: conceptID)
                    ]
                )
            ],
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
                    medicationConceptIdentifier: conceptID,
                    medicationName: "Centrum Silver Tablet",
                    startDate: doseTime,
                    endDate: doseTime,
                    scheduledDate: doseTime,
                    doseQuantity: 1,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .taken,
                    scheduleType: .scheduled,
                    metadata: ["rawConcept": conceptID]
                )
            ]
        )

        let md = data.toMarkdown(customization: MDContractCustomizations.metric)
        let detailRows = md.components(separatedBy: "\n")
            .filter { $0.hasPrefix("|") && $0.contains("HKHealthConceptIdentifier") }

        XCTAssertFalse(detailRows.isEmpty, md)
        XCTAssertTrue(detailRows.allSatisfy { $0.contains("&lt;HKHealthConceptIdentifier: 0x11b5a6200&gt;") }, detailRows.joined(separator: "\n"))
        XCTAssertFalse(detailRows.contains(where: { $0.contains(conceptID) }), detailRows.joined(separator: "\n"))
    }

    func testMedications_notLoggedDoseCountsAsSkippedInSummary() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        let calendar = Calendar(identifier: .gregorian)
        let morningDose = calendar.date(byAdding: .hour, value: 8, to: ExportFixtures.referenceDate)!
        let eveningDose = calendar.date(byAdding: .hour, value: 20, to: ExportFixtures.referenceDate)!

        data.medications = MedicationsData(
            medications: [
                Medication(
                    conceptIdentifier: "rxnorm:617314",
                    displayName: "Levothyroxine Sodium 50 MCG Oral Tablet",
                    nickname: "Thyroid",
                    generalForm: "tablet",
                    isArchived: false,
                    hasSchedule: true,
                    relatedCodings: []
                )
            ],
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                    medicationConceptIdentifier: "rxnorm:617314",
                    medicationName: "Thyroid",
                    startDate: morningDose,
                    endDate: morningDose,
                    scheduledDate: morningDose,
                    doseQuantity: 1,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .taken,
                    scheduleType: .scheduled,
                    metadata: ["HKMetadataKeySyncIdentifier": "medication\u{001F}|0\u{001F}|urn:apple:health:ontology\u{001F}|1082238120_803412000.000000"]
                ),
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
                    medicationConceptIdentifier: "rxnorm:617314",
                    medicationName: "Thyroid",
                    startDate: eveningDose,
                    endDate: eveningDose,
                    scheduledDate: eveningDose,
                    doseQuantity: nil,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .notLogged,
                    scheduleType: .scheduled
                )
            ]
        )

        let md = data.toMarkdown(customization: MDContractCustomizations.metric)

        XCTAssertTrue(md.contains("medication_details:\n  - name: \"Thyroid\""))
        XCTAssertTrue(md.contains("concept_identifier: \"rxnorm:617314\""))
        XCTAssertTrue(md.contains("medication_dose_events:\n  - name: \"Thyroid\"\n    status: taken"))
        XCTAssertTrue(md.contains("id: \"00000000-0000-0000-0000-000000000401\""))
        XCTAssertFalse(md.contains("\u{001F}"), "Markdown frontmatter should escape invisible HealthKit metadata separators")
        XCTAssertTrue(md.contains(#""HKMetadataKeySyncIdentifier": "medication\u001F|0\u001F|urn:apple:health:ontology\u001F|1082238120_803412000.000000""#), md)
        XCTAssertTrue(md.contains("dose_quantity: 1"))
        XCTAssertTrue(md.contains("scheduled_dose_quantity: 1"))
        XCTAssertTrue(md.contains("  - name: \"Thyroid\"\n    status: not_logged"))
        XCTAssertTrue(md.contains("**Dose events:** 2 (1 taken, 1 skipped)"))
        XCTAssertTrue(md.contains("Dose Event Details"))
        XCTAssertTrue(md.contains("**Thyroid:** Not logged"))
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

    func testGranular_fullDayGranular_hasBloodPressureSamples() {
        let md = ExportFixtures.fullDayGranular.toMarkdown(customization: MDContractCustomizations.metric)
        XCTAssertTrue(md.contains("Blood Pressure Samples (2 readings)"))
        XCTAssertTrue(md.contains("124.0 mmHg | 81.0 mmHg"))
    }

    func testGranular_fullDay_noDetailsSections() {
        let md = ExportFixtures.fullDay.toMarkdown(customization: MDContractCustomizations.metric)
        let hasGranularDetails = md.contains("Heart Rate Samples") ||
            md.contains("Sleep Stages Timeline") ||
            md.contains("Blood Pressure Samples")
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
