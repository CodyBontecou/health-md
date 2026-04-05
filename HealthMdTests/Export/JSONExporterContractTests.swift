//
//  JSONExporterContractTests.swift
//  HealthMdTests
//
//  Structural contract tests for JSON exporter output.
//  Parses JSON and asserts key graph, types, and values instead of string-contains.
//

import XCTest
@testable import HealthMd

// Static customizations to avoid macOS 26 deinit crash.
private enum JSONContractCustomizations {
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
}

final class JSONExporterContractTests: XCTestCase {

    // MARK: - Helpers

    private func parseJSON(_ data: HealthData, customization: FormatCustomization = JSONContractCustomizations.metric) -> [String: Any] {
        let jsonString = data.toJSON(customization: customization)
        guard let jsonData = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to parse JSON output")
            return [:]
        }
        return obj
    }

    // MARK: - Top-Level Structure

    func testJSON_fullDay_isValidJSON() {
        let jsonString = ExportFixtures.fullDay.toJSON(customization: JSONContractCustomizations.metric)
        let jsonData = jsonString.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: jsonData))
    }

    func testJSON_fullDay_hasRequiredTopLevelKeys() {
        let json = parseJSON(ExportFixtures.fullDay)
        let requiredKeys = ["date", "type", "units"]
        for key in requiredKeys {
            XCTAssertNotNil(json[key], "Top-level JSON missing required key: \(key)")
        }
    }

    func testJSON_fullDay_topLevelTypesAreStrings() {
        let json = parseJSON(ExportFixtures.fullDay)
        XCTAssertTrue(json["date"] is String, "date should be a String")
        XCTAssertTrue(json["type"] is String, "type should be a String")
        XCTAssertTrue(json["units"] is String, "units should be a String")
    }

    func testJSON_fullDay_typeIsHealthData() {
        let json = parseJSON(ExportFixtures.fullDay)
        XCTAssertEqual(json["type"] as? String, "health-data")
    }

    func testJSON_metricUnits_saysMetric() {
        let json = parseJSON(ExportFixtures.fullDay, customization: JSONContractCustomizations.metric)
        XCTAssertEqual(json["units"] as? String, "metric")
    }

    func testJSON_imperialUnits_saysImperial() {
        let json = parseJSON(ExportFixtures.fullDay, customization: JSONContractCustomizations.imperial)
        XCTAssertEqual(json["units"] as? String, "imperial")
    }

    // MARK: - Category Presence (fullDay)

    func testJSON_fullDay_hasAllCategoryKeys() {
        let json = parseJSON(ExportFixtures.fullDay)
        let categories = ["sleep", "activity", "heart", "vitals", "body", "nutrition", "mindfulness", "mobility", "hearing", "workouts"]
        for cat in categories {
            XCTAssertNotNil(json[cat], "Full day JSON missing category: \(cat)")
        }
    }

    func testJSON_fullDay_categoriesAreDictionaries() {
        let json = parseJSON(ExportFixtures.fullDay)
        let dictCategories = ["sleep", "activity", "heart", "vitals", "body", "nutrition", "mindfulness", "mobility", "hearing"]
        for cat in dictCategories {
            XCTAssertTrue(json[cat] is [String: Any], "\(cat) should be a dictionary")
        }
    }

    func testJSON_fullDay_workoutsIsArray() {
        let json = parseJSON(ExportFixtures.fullDay)
        XCTAssertTrue(json["workouts"] is [[String: Any]], "workouts should be an array of dictionaries")
    }

    // MARK: - Sleep Key Graph

    func testJSON_fullDay_sleepKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let sleep = json["sleep"] as? [String: Any] else {
            XCTFail("sleep key missing or wrong type"); return
        }
        let expectedKeys = ["totalDuration", "totalDurationFormatted", "deepSleep", "deepSleepFormatted",
                            "remSleep", "remSleepFormatted", "coreSleep", "coreSleepFormatted"]
        for key in expectedKeys {
            XCTAssertNotNil(sleep[key], "sleep missing key: \(key)")
        }
        // totalDuration should be a number
        XCTAssertTrue(sleep["totalDuration"] is Double || sleep["totalDuration"] is Int,
                      "totalDuration should be numeric")
        // totalDurationFormatted should be a string
        XCTAssertTrue(sleep["totalDurationFormatted"] is String,
                      "totalDurationFormatted should be a String")
    }

    // MARK: - Activity Key Graph

    func testJSON_fullDay_activityKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let activity = json["activity"] as? [String: Any] else {
            XCTFail("activity key missing or wrong type"); return
        }
        let expectedKeys = ["steps", "activeCalories", "exerciseMinutes", "flightsClimbed",
                            "walkingRunningDistance", "standHours", "basalEnergyBurned",
                            "cyclingDistance", "vo2Max"]
        for key in expectedKeys {
            XCTAssertNotNil(activity[key], "activity missing key: \(key)")
        }
        XCTAssertEqual(activity["steps"] as? Int, 12500, "steps value mismatch")
    }

    // MARK: - Heart Key Graph

    func testJSON_fullDay_heartKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let heart = json["heart"] as? [String: Any] else {
            XCTFail("heart key missing or wrong type"); return
        }
        let expectedKeys = ["restingHeartRate", "walkingHeartRateAverage", "averageHeartRate",
                            "hrv", "heartRateMin", "heartRateMax"]
        for key in expectedKeys {
            XCTAssertNotNil(heart[key], "heart missing key: \(key)")
        }
        XCTAssertEqual(heart["restingHeartRate"] as? Double, 58.0)
        XCTAssertEqual(heart["hrv"] as? Double, 42.0)
    }

    // MARK: - Vitals Key Graph

    func testJSON_fullDay_vitalsKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let vitals = json["vitals"] as? [String: Any] else {
            XCTFail("vitals key missing or wrong type"); return
        }
        let expectedKeys = ["respiratoryRateAvg", "respiratoryRateMin", "respiratoryRateMax",
                            "bloodOxygenAvg", "bloodOxygenMin", "bloodOxygenMax",
                            "bloodOxygenPercent", "bloodOxygenMinPercent", "bloodOxygenMaxPercent"]
        for key in expectedKeys {
            XCTAssertNotNil(vitals[key], "vitals missing key: \(key)")
        }
        // Blood oxygen should be stored as fraction
        XCTAssertEqual(vitals["bloodOxygenAvg"] as? Double, 0.97)
        // Percent version should be multiplied by 100
        XCTAssertEqual(vitals["bloodOxygenPercent"] as? Double, 97.0)
    }

    // MARK: - Body Key Graph

    func testJSON_fullDay_bodyKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let body = json["body"] as? [String: Any] else {
            XCTFail("body key missing or wrong type"); return
        }
        let expectedKeys = ["weight", "bodyFatPercentage", "bodyFatPercent", "height", "bmi"]
        for key in expectedKeys {
            XCTAssertNotNil(body[key], "body missing key: \(key)")
        }
        XCTAssertEqual(body["weight"] as? Double, 75.0)
        XCTAssertEqual(body["bodyFatPercent"] as? Double, 18.0)
    }

    // MARK: - Nutrition Key Graph

    func testJSON_fullDay_nutritionKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let nutrition = json["nutrition"] as? [String: Any] else {
            XCTFail("nutrition key missing or wrong type"); return
        }
        let expectedKeys = ["dietaryEnergy", "protein", "carbohydrates", "fat", "fiber", "sugar", "water", "caffeine"]
        for key in expectedKeys {
            XCTAssertNotNil(nutrition[key], "nutrition missing key: \(key)")
        }
        XCTAssertEqual(nutrition["protein"] as? Double, 120.0)
    }

    // MARK: - Mindfulness Key Graph

    func testJSON_fullDay_mindfulnessKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let mindfulness = json["mindfulness"] as? [String: Any] else {
            XCTFail("mindfulness key missing or wrong type"); return
        }
        XCTAssertNotNil(mindfulness["mindfulMinutes"], "mindfulness missing mindfulMinutes")
        XCTAssertNotNil(mindfulness["mindfulSessions"], "mindfulness missing mindfulSessions")
        XCTAssertEqual(mindfulness["mindfulMinutes"] as? Double, 15.0)
        XCTAssertEqual(mindfulness["mindfulSessions"] as? Int, 2)
    }

    // MARK: - Mobility Key Graph

    func testJSON_fullDay_mobilityKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let mobility = json["mobility"] as? [String: Any] else {
            XCTFail("mobility key missing or wrong type"); return
        }
        let expectedKeys = ["walkingSpeed", "walkingStepLength", "walkingDoubleSupportPercentage"]
        for key in expectedKeys {
            XCTAssertNotNil(mobility[key], "mobility missing key: \(key)")
        }
    }

    // MARK: - Hearing Key Graph

    func testJSON_fullDay_hearingKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let hearing = json["hearing"] as? [String: Any] else {
            XCTFail("hearing key missing or wrong type"); return
        }
        XCTAssertEqual(hearing["headphoneAudioLevel"] as? Double, 72.0)
        XCTAssertEqual(hearing["environmentalSoundLevel"] as? Double, 55.0)
    }

    // MARK: - Workouts Key Graph

    func testJSON_fullDay_workoutEntryKeyGraph() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let workouts = json["workouts"] as? [[String: Any]],
              let first = workouts.first else {
            XCTFail("workouts missing or empty"); return
        }
        let expectedKeys = ["type", "startTime", "duration", "durationFormatted", "distance", "distanceFormatted", "calories"]
        for key in expectedKeys {
            XCTAssertNotNil(first[key], "workout entry missing key: \(key)")
        }
        XCTAssertEqual(first["type"] as? String, "Running")
    }

    // MARK: - Absent Keys for Empty/Partial Data

    func testJSON_emptyDay_hasCoreKeysOnly() {
        let json = parseJSON(ExportFixtures.emptyDay)
        XCTAssertNotNil(json["date"])
        XCTAssertNotNil(json["type"])
        // No health data categories should be present
        let categoryKeys = ["sleep", "activity", "heart", "vitals", "body", "nutrition", "mindfulness", "mobility", "hearing", "workouts"]
        for key in categoryKeys {
            XCTAssertNil(json[key], "Empty day should not contain \(key)")
        }
    }

    func testJSON_partialDay_onlyHasSleepAndActivity() {
        let json = parseJSON(ExportFixtures.partialDay)
        XCTAssertNotNil(json["sleep"], "Partial day should have sleep")
        XCTAssertNotNil(json["activity"], "Partial day should have activity")
        XCTAssertNil(json["heart"], "Partial day should not have heart")
        XCTAssertNil(json["vitals"], "Partial day should not have vitals")
        XCTAssertNil(json["body"], "Partial day should not have body")
    }

    // MARK: - Edge Cases

    func testJSON_edgeCaseDay_handlesZeroValues() {
        let json = parseJSON(ExportFixtures.edgeCaseDay)
        // Should still have mindfulness (stateOfMind entries exist)
        XCTAssertNotNil(json["mindfulness"], "Edge case should contain mindfulness for state of mind")
        // Sleep has 0 durations - sleep.hasData may or may not include it
        // Activity has 0 steps
    }

    // MARK: - Granular Data

    func testJSON_fullDayGranular_hasHeartRateSamples() {
        let json = parseJSON(ExportFixtures.fullDayGranular)
        guard let heart = json["heart"] as? [String: Any] else {
            XCTFail("heart key missing"); return
        }
        guard let samples = heart["heartRateSamples"] as? [[String: Any]] else {
            XCTFail("heartRateSamples should be an array of dictionaries"); return
        }
        XCTAssertEqual(samples.count, 5, "Should have 5 heart rate samples")
        // Each sample should have timestamp and value keys
        let first = samples[0]
        XCTAssertNotNil(first["timestamp"], "Sample should have timestamp key")
        XCTAssertNotNil(first["value"], "Sample should have value key")
        XCTAssertTrue(first["timestamp"] is String, "timestamp should be ISO 8601 string")
        XCTAssertTrue(first["value"] is Double || first["value"] is Int, "value should be numeric")
    }

    func testJSON_fullDayGranular_hasHrvSamples() {
        let json = parseJSON(ExportFixtures.fullDayGranular)
        guard let heart = json["heart"] as? [String: Any] else {
            XCTFail("heart key missing"); return
        }
        guard let samples = heart["hrvSamples"] as? [[String: Any]] else {
            XCTFail("hrvSamples should be an array of dictionaries"); return
        }
        XCTAssertEqual(samples.count, 2, "Should have 2 HRV samples")
    }

    func testJSON_fullDayGranular_hasSleepStages() {
        let json = parseJSON(ExportFixtures.fullDayGranular)
        guard let sleep = json["sleep"] as? [String: Any] else {
            XCTFail("sleep key missing"); return
        }
        guard let stages = sleep["sleepStages"] as? [[String: Any]] else {
            XCTFail("sleepStages should be an array of dictionaries"); return
        }
        XCTAssertEqual(stages.count, 4, "Should have 4 sleep stage samples")
        let first = stages[0]
        XCTAssertNotNil(first["stage"], "Stage should have stage key")
        XCTAssertNotNil(first["startDate"], "Stage should have startDate key")
        XCTAssertNotNil(first["endDate"], "Stage should have endDate key")
        XCTAssertNotNil(first["durationSeconds"], "Stage should have durationSeconds key")
        XCTAssertEqual(first["stage"] as? String, "deep")
    }

    func testJSON_fullDayGranular_hasVitalsSamples() {
        let json = parseJSON(ExportFixtures.fullDayGranular)
        guard let vitals = json["vitals"] as? [String: Any] else {
            XCTFail("vitals key missing"); return
        }
        XCTAssertNotNil(vitals["bloodOxygenSamples"], "Should have bloodOxygenSamples")
        XCTAssertNotNil(vitals["bloodGlucoseSamples"], "Should have bloodGlucoseSamples")
        XCTAssertNotNil(vitals["respiratoryRateSamples"], "Should have respiratoryRateSamples")

        let spo2 = vitals["bloodOxygenSamples"] as? [[String: Any]]
        XCTAssertEqual(spo2?.count, 3, "Should have 3 blood oxygen samples")
    }

    func testJSON_fullDay_doesNotContainSampleArrays() {
        let json = parseJSON(ExportFixtures.fullDay)
        if let heart = json["heart"] as? [String: Any] {
            XCTAssertNil(heart["heartRateSamples"], "fullDay should not have heartRateSamples")
            XCTAssertNil(heart["hrvSamples"], "fullDay should not have hrvSamples")
        }
        if let sleep = json["sleep"] as? [String: Any] {
            XCTAssertNil(sleep["sleepStages"], "fullDay should not have sleepStages")
        }
        if let vitals = json["vitals"] as? [String: Any] {
            XCTAssertNil(vitals["bloodOxygenSamples"], "fullDay should not have bloodOxygenSamples")
            XCTAssertNil(vitals["bloodGlucoseSamples"], "fullDay should not have bloodGlucoseSamples")
            XCTAssertNil(vitals["respiratoryRateSamples"], "fullDay should not have respiratoryRateSamples")
        }
    }

    // MARK: - Edge Cases (continued)

    func testJSON_edgeCaseDay_mindfulnessHasStateOfMind() {
        let json = parseJSON(ExportFixtures.edgeCaseDay)
        guard let mindfulness = json["mindfulness"] as? [String: Any] else {
            XCTFail("mindfulness should exist for edge case"); return
        }
        XCTAssertNotNil(mindfulness["stateOfMindEntries"], "Should contain state of mind entries")
        XCTAssertNotNil(mindfulness["averageValence"], "Should contain average valence")
    }
}
