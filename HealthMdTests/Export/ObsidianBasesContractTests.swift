//
//  ObsidianBasesContractTests.swift
//  HealthMdTests
//
//  Strict contract tests for Obsidian Bases (YAML frontmatter) exporter.
//  Parses frontmatter and asserts key presence, value types, key-style
//  transformations, custom/placeholder fields, and disabled field absence.
//

import XCTest
@testable import HealthMd

// Static customizations to avoid macOS 26 deinit crash.
private enum BasesContractCustomizations {
    static let defaultMetric: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .metric
        return c
    }()

    static let imperial: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .imperial
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

    static let customFields: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.customFields = ["project": "health-md", "reviewed": "false"]
        c.frontmatterConfig.placeholderFields = ["notes", "mood_override"]
        return c
    }()

    static let noDateNoType: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.includeDate = false
        c.frontmatterConfig.includeType = false
        return c
    }()

    static let stepsDisabled: FormatCustomization = {
        let c = FormatCustomization()
        if let idx = c.frontmatterConfig.fields.firstIndex(where: { $0.originalKey == "steps" }) {
            c.frontmatterConfig.fields[idx].isEnabled = false
        }
        return c
    }()

    static let sleepDisabled: FormatCustomization = {
        let c = FormatCustomization()
        for i in c.frontmatterConfig.fields.indices {
            if c.frontmatterConfig.fields[i].originalKey.hasPrefix("sleep_") {
                c.frontmatterConfig.fields[i].isEnabled = false
            }
        }
        return c
    }()
}

final class ObsidianBasesContractTests: XCTestCase {

    // MARK: - Helpers

    /// Parse YAML frontmatter into key-value pairs.
    private func parseFrontmatter(_ data: HealthData, customization: FormatCustomization = BasesContractCustomizations.defaultMetric) -> [(key: String, value: String)] {
        let output = data.toObsidianBases(customization: customization)
        return parseFrontmatterString(output)
    }

    /// Parse a raw frontmatter string into ordered key-value pairs.
    private func parseFrontmatterString(_ output: String) -> [(key: String, value: String)] {
        let lines = output.components(separatedBy: "\n")
        var pairs: [(key: String, value: String)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed.isEmpty { continue }
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

    // MARK: - Basic Structure

    func testBases_fullDay_startsAndEndsWithDelimiters() {
        let output = ExportFixtures.fullDay.toObsidianBases(customization: BasesContractCustomizations.defaultMetric)
        XCTAssertTrue(output.hasPrefix("---\n"), "Should start with ---")
        XCTAssertTrue(output.contains("\n---\n"), "Should contain closing ---")
    }

    func testBases_fullDay_hasDateAndTypeKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("date"), "Should contain date key")
        XCTAssertTrue(keys.contains("type"), "Should contain type key")
    }

    func testBases_fullDay_typeValueIsHealthData() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        XCTAssertEqual(value(for: "type", in: pairs), "health-data")
    }

    // MARK: - Core Metric Keys Present (snake_case default)

    func testBases_fullDay_containsSleepKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        let expected = ["sleep_total_hours", "sleep_deep_hours", "sleep_rem_hours", "sleep_core_hours"]
        for key in expected {
            XCTAssertTrue(keys.contains(key), "Missing sleep key: \(key)")
        }
    }

    func testBases_fullDay_containsActivityKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        let expected = ["steps", "active_calories", "exercise_minutes"]
        for key in expected {
            XCTAssertTrue(keys.contains(key), "Missing activity key: \(key)")
        }
    }

    func testBases_fullDay_containsHeartKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        let expected = ["resting_heart_rate", "hrv_ms", "walking_heart_rate",
                        "average_heart_rate", "heart_rate_min", "heart_rate_max"]
        for key in expected {
            XCTAssertTrue(keys.contains(key), "Missing heart key: \(key)")
        }
    }

    func testBases_fullDay_containsVitalsKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        let expected = ["respiratory_rate_avg", "blood_oxygen_avg"]
        for key in expected {
            XCTAssertTrue(keys.contains(key), "Missing vitals key: \(key)")
        }
    }

    func testBases_fullDay_containsBodyKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("weight_kg"), "Missing weight_kg key")
        XCTAssertTrue(keys.contains("bmi"), "Missing bmi key")
        XCTAssertTrue(keys.contains("body_fat_percent"), "Missing body_fat_percent key")
    }

    func testBases_fullDay_containsNutritionKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        let expected = ["dietary_calories", "protein_g", "carbohydrates_g", "fat_g", "fiber_g", "sugar_g"]
        for key in expected {
            XCTAssertTrue(keys.contains(key), "Missing nutrition key: \(key)")
        }
    }

    func testBases_fullDay_containsMindfulnessKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("mindful_minutes"), "Missing mindful_minutes key")
    }

    func testBases_fullDay_containsMobilityKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("walking_speed"), "Missing walking_speed key")
    }

    func testBases_fullDay_containsHearingKeys() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("headphone_audio_db"), "Missing headphone_audio_db key")
        XCTAssertTrue(keys.contains("environmental_sound_db"), "Missing environmental_sound_db key")
    }

    func testBases_fullDay_containsVO2Max() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("vo2_max"), "Missing vo2_max key")
    }

    // MARK: - Value Type Assertions (numbers vs strings)

    func testBases_fullDay_numericValuesAreNumbers() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        let numericKeys = ["steps", "active_calories", "resting_heart_rate", "hrv_ms"]
        for key in numericKeys {
            if let val = value(for: key, in: pairs) {
                XCTAssertNotNil(Double(val), "\(key) should have a numeric value, got: \(val)")
            }
        }
    }

    func testBases_fullDay_stepsValueIs12500() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        if let val = value(for: "steps", in: pairs) {
            XCTAssertEqual(val, "12500", "steps should be 12500, got: \(val)")
        } else {
            XCTFail("steps key not found")
        }
    }

    func testBases_fullDay_restingHeartRateValue() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay)
        if let val = value(for: "resting_heart_rate", in: pairs) {
            XCTAssertTrue(val.contains("58"), "resting_heart_rate should contain 58, got: \(val)")
        } else {
            XCTFail("resting_heart_rate key not found")
        }
    }

    // MARK: - Key-Style: camelCase

    func testBases_camelCase_keysAreCamelCase() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.camelCaseKeys)
        let keys = keySet(pairs)
        // camelCase should convert sleep_total_hours → sleepTotalHours
        XCTAssertTrue(keys.contains("sleepTotalHours"), "camelCase should have sleepTotalHours, keys: \(keys.sorted())")
        XCTAssertFalse(keys.contains("sleep_total_hours"), "camelCase should NOT have sleep_total_hours")
    }

    func testBases_camelCase_activityKeysConverted() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.camelCaseKeys)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("activeCalories"), "camelCase should have activeCalories")
        XCTAssertTrue(keys.contains("exerciseMinutes"), "camelCase should have exerciseMinutes")
    }

    func testBases_camelCase_heartKeysConverted() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.camelCaseKeys)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("restingHeartRate"), "camelCase should have restingHeartRate")
        XCTAssertTrue(keys.contains("hrvMs"), "camelCase should have hrvMs")
    }

    // MARK: - Key-Style: snake_case (explicit)

    func testBases_snakeCase_keysAreSnakeCase() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.snakeCaseKeys)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("sleep_total_hours"), "snake_case should have sleep_total_hours")
        XCTAssertTrue(keys.contains("active_calories"), "snake_case should have active_calories")
        XCTAssertFalse(keys.contains("sleepTotalHours"), "snake_case should NOT have camelCase keys")
    }

    // MARK: - Custom and Placeholder Fields

    func testBases_customFields_present() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.customFields)
        XCTAssertEqual(value(for: "project", in: pairs), "health-md")
        XCTAssertEqual(value(for: "reviewed", in: pairs), "false")
    }

    func testBases_placeholderFields_presentWithEmptyValue() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.customFields)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("notes"), "Placeholder 'notes' should be present")
        XCTAssertTrue(keys.contains("mood_override"), "Placeholder 'mood_override' should be present")
        // Placeholder values should be empty
        XCTAssertEqual(value(for: "notes", in: pairs), "", "Placeholder should have empty value")
        XCTAssertEqual(value(for: "mood_override", in: pairs), "", "Placeholder should have empty value")
    }

    // MARK: - Disabled Fields Absent

    func testBases_stepsDisabled_stepsKeyAbsent() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.stepsDisabled)
        let keys = keySet(pairs)
        XCTAssertFalse(keys.contains("steps"), "Disabled steps should not appear in output")
    }

    func testBases_sleepDisabled_sleepKeysAbsent() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.sleepDisabled)
        let keys = keySet(pairs)
        let sleepKeys = keys.filter { $0.hasPrefix("sleep_") }
        XCTAssertTrue(sleepKeys.isEmpty, "Disabled sleep keys should not appear: \(sleepKeys)")
    }

    func testBases_stepsDisabled_otherKeysStillPresent() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.stepsDisabled)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("active_calories"), "Non-disabled keys should still be present")
        XCTAssertTrue(keys.contains("resting_heart_rate"), "Non-disabled keys should still be present")
    }

    // MARK: - No Date/Type

    func testBases_noDateNoType_keysAbsent() {
        let pairs = parseFrontmatter(ExportFixtures.fullDay, customization: BasesContractCustomizations.noDateNoType)
        let keys = keySet(pairs)
        XCTAssertFalse(keys.contains("date"), "date should be absent when disabled")
        XCTAssertFalse(keys.contains("type"), "type should be absent when disabled")
    }

    // MARK: - Empty Day

    func testBases_emptyDay_hasDateAndType() {
        let pairs = parseFrontmatter(ExportFixtures.emptyDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("date"), "Empty day should have date")
        XCTAssertTrue(keys.contains("type"), "Empty day should have type")
    }

    func testBases_emptyDay_noHealthMetricKeys() {
        let pairs = parseFrontmatter(ExportFixtures.emptyDay)
        let keys = keySet(pairs)
        let healthKeys = keys.subtracting(["date", "type"])
        XCTAssertTrue(healthKeys.isEmpty, "Empty day should have no health metric keys, found: \(healthKeys)")
    }

    // MARK: - Partial Day

    func testBases_partialDay_hasSleepAndActivityKeys() {
        let pairs = parseFrontmatter(ExportFixtures.partialDay)
        let keys = keySet(pairs)
        XCTAssertTrue(keys.contains("sleep_total_hours"), "Partial day should have sleep keys")
        XCTAssertTrue(keys.contains("steps"), "Partial day should have activity keys")
    }

    func testBases_partialDay_noHeartOrVitalsKeys() {
        let pairs = parseFrontmatter(ExportFixtures.partialDay)
        let keys = keySet(pairs)
        XCTAssertFalse(keys.contains("resting_heart_rate"), "Partial day should not have heart keys")
        XCTAssertFalse(keys.contains("respiratory_rate_avg"), "Partial day should not have vitals keys")
        XCTAssertFalse(keys.contains("weight_kg"), "Partial day should not have body keys")
    }

    // MARK: - Edge Cases

    func testBases_edgeCaseDay_handlesNilOptionals() {
        let pairs = parseFrontmatter(ExportFixtures.edgeCaseDay)
        // Should not crash, should produce valid frontmatter
        let output = ExportFixtures.edgeCaseDay.toObsidianBases(customization: BasesContractCustomizations.defaultMetric)
        XCTAssertTrue(output.hasPrefix("---"), "Edge case should produce valid frontmatter")
        // Verify key count is reasonable
        XCTAssertFalse(pairs.isEmpty, "Edge case should have at least date/type")
    }

    // MARK: - Parity with allMetricsDictionary

    func testBases_fullDay_allDictionaryKeysPresent() {
        let data = ExportFixtures.fullDay
        let customization = BasesContractCustomizations.defaultMetric
        let output = data.toObsidianBases(customization: customization)
        let allKeys = data.allMetricsDictionary(using: customization.unitConverter).keys

        for key in allKeys.sorted() {
            XCTAssertTrue(output.contains("\(key): "),
                          "Obsidian Bases output missing dictionary key: \(key)")
        }
    }
}
