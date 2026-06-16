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
        let requiredKeys = ["schema", "schema_version", "date", "type", "unit_system", "units"]
        for key in requiredKeys {
            XCTAssertNotNil(json[key], "Top-level JSON missing required key: \(key)")
        }
    }

    func testJSON_fullDay_topLevelTypesAreStrings() {
        let json = parseJSON(ExportFixtures.fullDay)
        XCTAssertTrue(json["schema"] is String, "schema should be a String")
        XCTAssertTrue(json["date"] is String, "date should be a String")
        XCTAssertTrue(json["type"] is String, "type should be a String")
        XCTAssertTrue(json["unit_system"] is String, "unit_system should be a String")
        XCTAssertTrue(json["units"] is [String: Any], "units should be a metric unit dictionary")
    }

    func testJSON_fullDay_schemaIdentifierAndVersionAreCurrent() {
        let json = parseJSON(ExportFixtures.fullDay)
        XCTAssertEqual(json["schema"] as? String, HealthMdExportSchema.identifier)
        XCTAssertEqual(json["schema_version"] as? Int, HealthMdExportSchema.version)
    }

    func testJSON_fullDay_typeIsHealthData() {
        let json = parseJSON(ExportFixtures.fullDay)
        XCTAssertEqual(json["type"] as? String, "health-data")
    }

    func testJSON_metricUnitSystem_saysMetric() {
        let json = parseJSON(ExportFixtures.fullDay, customization: JSONContractCustomizations.metric)
        XCTAssertEqual(json["unit_system"] as? String, "metric")
    }

    func testJSON_imperialPreference_stillUsesCanonicalMetricUnitSystem() {
        let json = parseJSON(ExportFixtures.fullDay, customization: JSONContractCustomizations.imperial)
        XCTAssertEqual(json["unit_system"] as? String, "metric")
    }

    func testJSON_unitsMapDescribesCanonicalMetricKeys() {
        let json = parseJSON(ExportFixtures.fullDay, customization: JSONContractCustomizations.metric)
        let units = json["units"] as? [String: Any]
        XCTAssertEqual(units?["active_calories"] as? String, "kcal")
        XCTAssertEqual(units?["heart_rate_min"] as? String, "bpm")
        XCTAssertEqual(units?["blood_oxygen"] as? String, "percent")
        XCTAssertEqual(units?["vo2_max"] as? String, "mL/kg/min")
    }

    func testJSON_unitsMapIsStableUnderImperialPreference() {
        let json = parseJSON(ExportFixtures.fullDay, customization: JSONContractCustomizations.imperial)
        let units = json["units"] as? [String: Any]
        XCTAssertEqual(units?["weight_kg"] as? String, "kg")
        XCTAssertEqual(units?["height_m"] as? String, "m")
        XCTAssertEqual(units?["walking_running_km"] as? String, "km")
        XCTAssertEqual(units?["walking_running_mi"] as? String, "mi")
        XCTAssertEqual(units?["water_l"] as? String, "L")
    }

    // MARK: - Category Presence (fullDay)

    func testJSON_fullDay_hasAllCategoryKeys() {
        let json = parseJSON(ExportFixtures.fullDay)
        let categories = ["sleep", "activity", "heart", "vitals", "body", "nutrition", "mindfulness", "mobility", "hearing", "workouts", "medications"]
        for cat in categories {
            XCTAssertNotNil(json[cat], "Full day JSON missing category: \(cat)")
        }
    }

    func testJSON_fullDay_categoriesAreDictionaries() {
        let json = parseJSON(ExportFixtures.fullDay)
        let dictCategories = ["sleep", "activity", "heart", "vitals", "body", "nutrition", "mindfulness", "mobility", "hearing", "medications"]
        for cat in dictCategories {
            XCTAssertTrue(json[cat] is [String: Any], "\(cat) should be a dictionary")
        }
    }

    func testJSON_fullDay_workoutsIsArray() {
        let json = parseJSON(ExportFixtures.fullDay)
        XCTAssertTrue(json["workouts"] is [[String: Any]], "workouts should be an array of dictionaries")
    }

    func testJSON_fullDay_medicationsIncludeMetadataAndDoseEvents() {
        let json = parseJSON(ExportFixtures.fullDay)
        guard let medications = json["medications"] as? [String: Any] else {
            XCTFail("medications key missing or wrong type"); return
        }
        XCTAssertEqual(medications["medicationCount"] as? Int, 2)
        XCTAssertEqual(medications["doseEventCount"] as? Int, 1)
        XCTAssertTrue(medications["medications"] is [[String: Any]])
        XCTAssertTrue(medications["doseEvents"] is [[String: Any]])
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
                            "walkingRunningDistance", "walkingRunningDistanceKm", "walkingRunningDistanceMi",
                            "standHours", "basalEnergyBurned",
                            "cyclingDistance", "cyclingDistanceKm", "cyclingDistanceMi", "vo2Max"]
        for key in expectedKeys {
            XCTAssertNotNil(activity[key], "activity missing key: \(key)")
        }
        XCTAssertEqual(activity["steps"] as? Int, 12500, "steps value mismatch")
    }

    func testJSON_imperialPreference_activityDistancesRemainCanonicalAndExposeExplicitVariants() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        data.activity.walkingRunningDistance = 9500
        data.activity.cyclingDistance = 3200
        data.activity.wheelchairDistance = 5000
        data.activity.downhillSnowSportsDistance = 12000

        let json = parseJSON(data, customization: JSONContractCustomizations.imperial)
        guard let activity = json["activity"] as? [String: Any] else {
            XCTFail("activity key missing or wrong type"); return
        }

        XCTAssertEqual(activity["walkingRunningDistance"] as? Double, 9500)
        XCTAssertEqual(activity["walkingRunningDistanceKm"] as? Double, 9.5)
        XCTAssertEqual(activity["walkingRunningDistanceMi"] as? Double ?? 0, 5.903, accuracy: 0.001)
        XCTAssertEqual(activity["cyclingDistance"] as? Double, 3200)
        XCTAssertEqual(activity["cyclingDistanceKm"] as? Double, 3.2)
        XCTAssertEqual(activity["cyclingDistanceMi"] as? Double ?? 0, 1.988, accuracy: 0.001)
        XCTAssertEqual(activity["wheelchairDistance"] as? Double, 5000)
        XCTAssertEqual(activity["wheelchairDistanceKm"] as? Double, 5.0)
        XCTAssertEqual(activity["wheelchairDistanceMi"] as? Double ?? 0, 3.107, accuracy: 0.001)
        XCTAssertEqual(activity["downhillSnowSportsDistance"] as? Double, 12000)
        XCTAssertEqual(activity["downhillSnowSportsDistanceKm"] as? Double, 12.0)
        XCTAssertEqual(activity["downhillSnowSportsDistanceMi"] as? Double ?? 0, 7.456, accuracy: 0.001)
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
        let expectedKeys = ["type", "startTime", "startTimeISO", "endTimeISO", "duration", "durationFormatted", "distance", "distanceKm", "distanceMi", "speedKmh", "speedMph", "distanceFormatted", "avgPacePerKmFormatted", "avgPacePerMiFormatted", "calories"]
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

    func testJSON_granularSamples_includeMetadataWhenPresent() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        var data = HealthData(date: referenceDate)
        data.sleep = SleepData(
            totalDuration: 60,
            stages: [
                SleepStageSample(
                    stage: "core",
                    startDate: referenceDate,
                    endDate: referenceDate.addingTimeInterval(60),
                    metadata: ["sleep_source": "watch"]
                )
            ]
        )
        data.heart = HeartData(
            averageHeartRate: 72,
            heartRateSamples: [
                TimeSample(timestamp: referenceDate, value: 72, metadata: ["heart_source": "watch"])
            ]
        )
        data.vitals = VitalsData(
            bloodOxygenAvg: 0.98,
            bloodOxygenSamples: [
                TimeSample(timestamp: referenceDate, value: 0.98, metadata: ["spo2_source": "watch"])
            ]
        )
        data.mindfulness = MindfulnessData(
            stateOfMind: [
                StateOfMindEntry(
                    timestamp: referenceDate,
                    kind: .dailyMood,
                    valence: 0.4,
                    labels: ["Calm"],
                    associations: ["Fitness"],
                    metadata: ["mood_source": "health"]
                )
            ]
        )
        data.medications = MedicationsData(
            medications: [],
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(),
                    medicationConceptIdentifier: "med-1",
                    medicationName: "Example",
                    startDate: referenceDate,
                    endDate: referenceDate,
                    scheduledDate: nil,
                    doseQuantity: 1,
                    scheduledDoseQuantity: nil,
                    unit: "count",
                    logStatus: .taken,
                    scheduleType: .unknown,
                    metadata: ["dose_source": "health"]
                )
            ]
        )

        let json = parseJSON(data)
        let sleepStage = ((json["sleep"] as? [String: Any])?["sleepStages"] as? [[String: Any]])?.first
        XCTAssertEqual((sleepStage?["metadata"] as? [String: Any])?["sleep_source"] as? String, "watch")
        let hrSample = ((json["heart"] as? [String: Any])?["heartRateSamples"] as? [[String: Any]])?.first
        XCTAssertEqual((hrSample?["metadata"] as? [String: Any])?["heart_source"] as? String, "watch")
        let spo2Sample = ((json["vitals"] as? [String: Any])?["bloodOxygenSamples"] as? [[String: Any]])?.first
        XCTAssertEqual((spo2Sample?["metadata"] as? [String: Any])?["spo2_source"] as? String, "watch")
        let moodEntry = ((json["mindfulness"] as? [String: Any])?["stateOfMindEntries"] as? [[String: Any]])?.first
        XCTAssertEqual((moodEntry?["metadata"] as? [String: Any])?["mood_source"] as? String, "health")
        let doseEvent = ((json["medications"] as? [String: Any])?["doseEvents"] as? [[String: Any]])?.first
        XCTAssertEqual((doseEvent?["metadata"] as? [String: Any])?["dose_source"] as? String, "health")
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
