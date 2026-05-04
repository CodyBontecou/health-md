//
//  ExporterSmokeTests.swift
//  HealthMdTests
//
//  Crash-safety smoke tests for all export formats.
//  Each test verifies that the exporter does not crash and returns a non-nil
//  string for a variety of HealthData configurations. No HealthKit access is
//  required — all data is constructed directly from the model structs.
//
//  NOTE: FormatCustomization and FrontmatterConfiguration are ObservableObjects
//  whose deinits are dispatched to the main actor. On macOS 26 / Swift 6,
//  deallocating a nested ObservableObject from within another ObservableObject's
//  deinit causes a reentrant main-actor dispatch crash
//  (swift_task_deinitOnExecutorMainActorBackDeploy bug).
//  Workaround: store all FormatCustomization instances as static let properties
//  so they are never deallocated during the test run.
//

import XCTest
@testable import HealthMd

// MARK: - Shared Static Customizations
// Static so they are never deallocated — avoids the macOS 26 / Swift 6
// reentrant-main-actor-deinit crash in ObservableObject teardown.

private enum TestCustomizations {
    static let `default` = FormatCustomization()

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

    static let customTemplate: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.style = .custom
        c.markdownTemplate.customTemplate = MarkdownTemplateConfig.defaultTemplate
        return c
    }()

    static let camelCase: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.applyKeyStyle(.camelCase)
        return c
    }()

    static let customFields: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.customFields = ["project": "health-md", "reviewed": "false"]
        c.frontmatterConfig.placeholderFields = ["notes", "mood_override"]
        return c
    }()

    static let noSummary: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.includeSummary = false
        return c
    }()

    static let withSummary: FormatCustomization = {
        let c = FormatCustomization()
        c.markdownTemplate.includeSummary = true
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

    static let noMetaKeys: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.includeDate = false
        c.frontmatterConfig.includeType = false
        return c
    }()

    static let dateOnly: FormatCustomization = {
        let c = FormatCustomization()
        c.frontmatterConfig.includeDate = true
        c.frontmatterConfig.includeType = false
        return c
    }()

    // Per-date-format customizations (one per DateFormatPreference)
    static let dateFormats: [DateFormatPreference: FormatCustomization] = {
        var result: [DateFormatPreference: FormatCustomization] = [:]
        for fmt in DateFormatPreference.allCases {
            let c = FormatCustomization()
            c.dateFormat = fmt
            result[fmt] = c
        }
        return result
    }()

    // Per-time-format customizations
    static let timeFormats: [TimeFormatPreference: FormatCustomization] = {
        var result: [TimeFormatPreference: FormatCustomization] = [:]
        for fmt in TimeFormatPreference.allCases {
            let c = FormatCustomization()
            c.timeFormat = fmt
            result[fmt] = c
        }
        return result
    }()

    // Per-bullet-style customizations
    static let bulletStyles: [MarkdownTemplateConfig.BulletStyle: FormatCustomization] = {
        var result: [MarkdownTemplateConfig.BulletStyle: FormatCustomization] = [:]
        for style in MarkdownTemplateConfig.BulletStyle.allCases {
            let c = FormatCustomization()
            c.markdownTemplate.bulletStyle = style
            result[style] = c
        }
        return result
    }()

    static let stepsDisabled: FormatCustomization = {
        let c = FormatCustomization()
        if let idx = c.frontmatterConfig.fields.firstIndex(where: { $0.originalKey == "steps" }) {
            c.frontmatterConfig.fields[idx].isEnabled = false
        }
        return c
    }()
}

// MARK: - HealthData Factories

private extension HealthData {

    /// A HealthData object with every field set to a realistic value.
    static func fullyPopulated(on date: Date = Date()) -> HealthData {
        var data = HealthData(date: date)

        // Sleep
        data.sleep.totalDuration    = 7.5 * 3600
        data.sleep.deepSleep        = 1.5 * 3600
        data.sleep.remSleep         = 2.0 * 3600
        data.sleep.coreSleep        = 3.0 * 3600
        data.sleep.awakeTime        = 0.25 * 3600
        data.sleep.inBedTime        = 8.0 * 3600
        data.sleep.sessionStart     = date.addingTimeInterval(-8 * 3600)
        data.sleep.sessionEnd       = date.addingTimeInterval(-0.5 * 3600)

        // Activity
        data.activity.steps                  = 10_432
        data.activity.activeCalories         = 480.0
        data.activity.basalEnergyBurned      = 1900.0
        data.activity.exerciseMinutes        = 45.0
        data.activity.standHours             = 10
        data.activity.flightsClimbed         = 8
        data.activity.walkingRunningDistance = 7_500
        data.activity.cyclingDistance        = 12_000
        data.activity.swimmingDistance       = 500
        data.activity.swimmingStrokes        = 400
        data.activity.pushCount              = 120
        data.activity.vo2Max                 = 42.5

        // Heart
        data.heart.restingHeartRate        = 58.0
        data.heart.walkingHeartRateAverage = 72.0
        data.heart.averageHeartRate        = 68.0
        data.heart.heartRateMin            = 48.0
        data.heart.heartRateMax            = 142.0
        data.heart.hrv                     = 38.5

        // Vitals (with ranges)
        data.vitals.respiratoryRateAvg        = 14.5
        data.vitals.respiratoryRateMin        = 12.0
        data.vitals.respiratoryRateMax        = 18.0
        data.vitals.bloodOxygenAvg            = 0.98
        data.vitals.bloodOxygenMin            = 0.96
        data.vitals.bloodOxygenMax            = 1.00
        data.vitals.bodyTemperatureAvg        = 36.8
        data.vitals.bodyTemperatureMin        = 36.5
        data.vitals.bodyTemperatureMax        = 37.2
        data.vitals.bloodPressureSystolicAvg  = 120.0
        data.vitals.bloodPressureSystolicMin  = 115.0
        data.vitals.bloodPressureSystolicMax  = 128.0
        data.vitals.bloodPressureDiastolicAvg = 80.0
        data.vitals.bloodPressureDiastolicMin = 76.0
        data.vitals.bloodPressureDiastolicMax = 84.0
        data.vitals.bloodGlucoseAvg           = 95.0
        data.vitals.bloodGlucoseMin           = 82.0
        data.vitals.bloodGlucoseMax           = 110.0

        // Body
        data.body.weight             = 72.5
        data.body.height             = 1.78
        data.body.bmi                = 22.9
        data.body.bodyFatPercentage  = 0.18
        data.body.leanBodyMass       = 59.45
        data.body.waistCircumference = 0.81

        // Nutrition
        data.nutrition.dietaryEnergy  = 2100.0
        data.nutrition.protein        = 145.0
        data.nutrition.carbohydrates  = 210.0
        data.nutrition.fat            = 75.0
        data.nutrition.saturatedFat   = 20.0
        data.nutrition.fiber          = 28.0
        data.nutrition.sugar          = 45.0
        data.nutrition.sodium         = 1800.0
        data.nutrition.cholesterol    = 180.0
        data.nutrition.water          = 2.5
        data.nutrition.caffeine       = 200.0

        // Mindfulness — ≤5 entries to exercise the detailed-list branch
        data.mindfulness.mindfulMinutes  = 20.0
        data.mindfulness.mindfulSessions = 2
        data.mindfulness.stateOfMind = [
            StateOfMindEntry(timestamp: date, kind: .dailyMood,
                             valence: 0.6, labels: ["Happy"], associations: ["Exercise"]),
            StateOfMindEntry(timestamp: date, kind: .momentaryEmotion,
                             valence: -0.3, labels: ["Anxious"], associations: ["Work"])
        ]

        // Mobility
        data.mobility.walkingSpeed                   = 1.35
        data.mobility.walkingStepLength              = 0.72
        data.mobility.walkingDoubleSupportPercentage = 0.27
        data.mobility.walkingAsymmetryPercentage     = 0.04
        data.mobility.stairAscentSpeed               = 0.60
        data.mobility.stairDescentSpeed              = 0.75
        data.mobility.sixMinuteWalkDistance          = 520.0

        // Hearing
        data.hearing.headphoneAudioLevel     = 62.0
        data.hearing.environmentalSoundLevel = 55.0

        // Workouts (with and without optional fields)
        data.workouts = [
            WorkoutData(workoutType: .running, startTime: date, duration: 1800,
                        calories: 320.0, distance: 5_000),
            WorkoutData(workoutType: .yoga,    startTime: date, duration: 3600,
                        calories: nil,   distance: nil)
        ]

        return data
    }

    /// Only Sleep data set.
    static func sleepOnly(on date: Date = Date()) -> HealthData {
        var data = HealthData(date: date)
        data.sleep.totalDuration = 6.0 * 3600
        data.sleep.sessionStart  = date.addingTimeInterval(-6.5 * 3600)
        data.sleep.sessionEnd    = date.addingTimeInterval(-0.5 * 3600)
        return data
    }

    /// No health metrics at all.
    static func empty(on date: Date = Date()) -> HealthData {
        HealthData(date: date)
    }

    /// Vitals whose min == max (tests the no-range code path).
    static func vitalsNoRange(on date: Date = Date()) -> HealthData {
        var data = HealthData(date: date)
        data.vitals.respiratoryRateAvg = 14.0
        data.vitals.respiratoryRateMin = 14.0
        data.vitals.respiratoryRateMax = 14.0
        data.vitals.bloodOxygenAvg     = 0.98
        data.vitals.bloodOxygenMin     = 0.98
        data.vitals.bloodOxygenMax     = 0.98
        data.vitals.bodyTemperatureAvg = 36.8
        data.vitals.bodyTemperatureMin = 36.8
        data.vitals.bodyTemperatureMax = 36.8
        data.vitals.bloodPressureSystolicAvg  = 120.0
        data.vitals.bloodPressureSystolicMin  = 120.0
        data.vitals.bloodPressureSystolicMax  = 120.0
        data.vitals.bloodPressureDiastolicAvg = 80.0
        data.vitals.bloodPressureDiastolicMin = 80.0
        data.vitals.bloodPressureDiastolicMax = 80.0
        data.vitals.bloodGlucoseAvg = 95.0
        data.vitals.bloodGlucoseMin = 95.0
        data.vitals.bloodGlucoseMax = 95.0
        return data
    }

    /// >5 mindfulness entries — exercises the list-suppression branch.
    static func manyMoodEntries(on date: Date = Date()) -> HealthData {
        var data = HealthData(date: date)
        data.mindfulness.mindfulMinutes = 30.0
        data.mindfulness.stateOfMind = (0..<6).map { i in
            StateOfMindEntry(timestamp: date, kind: .momentaryEmotion,
                             valence: Double(i) * 0.3 - 0.75,
                             labels: ["Label\(i)"], associations: ["Assoc\(i)"])
        }
        return data
    }
}

// MARK: - Markdown Exporter Smoke Tests

final class MarkdownExporterSmokeTests: XCTestCase {

    // MARK: Empty data

    func testMarkdown_emptyData_doesNotCrash() {
        let result = HealthData.empty().toMarkdown(customization: TestCustomizations.default)
        XCTAssertNotNil(result)
    }

    func testMarkdown_emptyData_noMetadata_doesNotCrash() {
        let result = HealthData.empty().toMarkdown(includeMetadata: false,
                                                   customization: TestCustomizations.default)
        XCTAssertNotNil(result)
    }

    // MARK: Partial data

    func testMarkdown_sleepOnly_doesNotCrash() {
        let result = HealthData.sleepOnly().toMarkdown(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Sleep"))
    }

    func testMarkdown_vitalsNoRange_doesNotCrash() {
        let result = HealthData.vitalsNoRange().toMarkdown(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Vitals"))
    }

    func testMarkdown_manyMoodEntries_doesNotCrash() {
        let result = HealthData.manyMoodEntries().toMarkdown(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Mindfulness"))
    }

    // MARK: Fully populated — standard variants

    // Section presence and frontmatter contracts are in MarkdownExporterContractTests.
    // These smoke tests verify crash safety across the fullyPopulated() factory data.

    func testMarkdown_fullData_withMetadata_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            includeMetadata: true,
            customization: TestCustomizations.default
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_noMetadata_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            includeMetadata: false,
            customization: TestCustomizations.default
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_imperial_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.imperial
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_withEmoji_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(customization: TestCustomizations.emojiOn)
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_withoutEmoji_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(customization: TestCustomizations.emojiOff)
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_sectionHeaderLevel1_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.headerLevel1
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_sectionHeaderLevel3_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.headerLevel3
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_bulletStyles() {
        for (style, customization) in TestCustomizations.bulletStyles {
            let result = HealthData.fullyPopulated().toMarkdown(customization: customization)
            XCTAssertFalse(result.isEmpty, "Empty output for bullet style \(style)")
        }
    }

    func testMarkdown_fullData_allDateFormats() {
        for (fmt, customization) in TestCustomizations.dateFormats {
            let result = HealthData.fullyPopulated().toMarkdown(customization: customization)
            XCTAssertFalse(result.isEmpty, "Empty output for date format \(fmt)")
        }
    }

    func testMarkdown_fullData_allTimeFormats() {
        for (fmt, customization) in TestCustomizations.timeFormats {
            let result = HealthData.fullyPopulated().toMarkdown(customization: customization)
            XCTAssertFalse(result.isEmpty, "Empty output for time format \(fmt)")
        }
    }

    // MARK: Custom template

    func testMarkdown_customTemplate_fullData_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.customTemplate
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_customTemplate_emptyData_noUnresolvedPlaceholders() {
        let result = HealthData.empty().toMarkdown(
            customization: TestCustomizations.customTemplate
        )
        XCTAssertNotNil(result)
        // All conditional blocks should have been expanded/removed
        XCTAssertFalse(result.contains("{{"))
    }

    func testMarkdown_customTemplate_sleepOnly_hidesOtherBlocks() {
        let result = HealthData.sleepOnly().toMarkdown(
            customization: TestCustomizations.customTemplate
        )
        XCTAssertTrue(result.contains("Sleep"))
        XCTAssertFalse(result.contains("{{#activity}}"))
    }

    // MARK: Summary line

    func testMarkdown_fullData_summaryIncluded_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.withSummary
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fullData_summaryExcluded_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.noSummary
        )
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: Frontmatter key styles

    func testMarkdown_camelCaseKeys_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.camelCase
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_customAndPlaceholderFields_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.customFields
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_fieldDisabled_doesNotCrash() {
        let result = HealthData.fullyPopulated().toMarkdown(
            customization: TestCustomizations.stepsDisabled
        )
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: Workout edge cases

    func testMarkdown_workoutWithNilOptionals_doesNotCrash() {
        var data = HealthData(date: Date())
        data.workouts = [
            WorkoutData(workoutType: .other, startTime: Date(), duration: 600,
                        calories: nil, distance: nil)
        ]
        let result = data.toMarkdown(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testMarkdown_workoutWithZeroDistanceAndCalories_doesNotCrash() {
        var data = HealthData(date: Date())
        data.workouts = [
            WorkoutData(workoutType: .running, startTime: Date(), duration: 1800,
                        calories: 0, distance: 0)
        ]
        let result = data.toMarkdown(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }
}

// MARK: - CSV Exporter Smoke Tests

final class CSVExporterSmokeTests: XCTestCase {
    // Structural assertions (header schema, row counts, categories, units)
    // are in CSVExporterContractTests. These smoke tests only verify crash safety.

    func testCSV_emptyData_doesNotCrash() {
        let result = HealthData.empty().toCSV(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testCSV_sleepOnly_doesNotCrash() {
        let result = HealthData.sleepOnly().toCSV(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testCSV_fullData_metric_doesNotCrash() {
        let result = HealthData.fullyPopulated().toCSV(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testCSV_fullData_imperial_doesNotCrash() {
        let result = HealthData.fullyPopulated().toCSV(customization: TestCustomizations.imperial)
        XCTAssertFalse(result.isEmpty)
    }

    func testCSV_allDateFormats_doesNotCrash() {
        for (fmt, customization) in TestCustomizations.dateFormats {
            let result = HealthData.fullyPopulated().toCSV(customization: customization)
            XCTAssertFalse(result.isEmpty, "Empty output for date format \(fmt)")
        }
    }

    func testCSV_vitalsNoRange_doesNotCrash() {
        let result = HealthData.vitalsNoRange().toCSV(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testCSV_workoutsWithNilFields_doesNotCrash() {
        var data = HealthData(date: Date())
        data.workouts = [
            WorkoutData(workoutType: .yoga, startTime: Date(), duration: 3600,
                        calories: nil, distance: nil)
        ]
        let result = data.toCSV(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }
}

// MARK: - JSON Exporter Smoke Tests

final class JSONExporterSmokeTests: XCTestCase {
    // Structural assertions (key graphs, types, values)
    // are in JSONExporterContractTests. These smoke tests only verify crash safety.

    func testJSON_emptyData_doesNotCrash() {
        let result = HealthData.empty().toJSON(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testJSON_sleepOnly_doesNotCrash() {
        let result = HealthData.sleepOnly().toJSON(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testJSON_fullData_metric_doesNotCrash() {
        let result = HealthData.fullyPopulated().toJSON(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testJSON_fullData_imperial_doesNotCrash() {
        let result = HealthData.fullyPopulated().toJSON(customization: TestCustomizations.imperial)
        XCTAssertFalse(result.isEmpty)
    }

    func testJSON_allDateFormats_doesNotCrash() {
        for (fmt, customization) in TestCustomizations.dateFormats {
            let result = HealthData.fullyPopulated().toJSON(customization: customization)
            XCTAssertFalse(result.isEmpty, "Empty output for date format \(fmt)")
        }
    }

    func testJSON_vitalsNoRange_doesNotCrash() {
        let result = HealthData.vitalsNoRange().toJSON(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testJSON_manyMoodEntries_doesNotCrash() {
        let result = HealthData.manyMoodEntries().toJSON(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testJSON_workoutsWithNilFields_doesNotCrash() {
        var data = HealthData(date: Date())
        data.workouts = [
            WorkoutData(workoutType: .running, startTime: Date(), duration: 1800,
                        calories: nil, distance: nil)
        ]
        let result = data.toJSON(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }
}

// MARK: - Obsidian Bases Exporter Smoke Tests

final class ObsidianBasesExporterSmokeTests: XCTestCase {
    // Structural assertions (key presence, values, key-style, disabled fields)
    // are in ObsidianBasesContractTests. These smoke tests only verify crash safety
    // across various customization variants.

    func testObsidianBases_emptyData_doesNotCrash() {
        let result = HealthData.empty().toObsidianBases(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_sleepOnly_doesNotCrash() {
        let result = HealthData.sleepOnly().toObsidianBases(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_fullData_metric_doesNotCrash() {
        let result = HealthData.fullyPopulated().toObsidianBases(
            customization: TestCustomizations.default
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_fullData_imperial_doesNotCrash() {
        let result = HealthData.fullyPopulated().toObsidianBases(
            customization: TestCustomizations.imperial
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_camelCaseKeys_doesNotCrash() {
        let result = HealthData.fullyPopulated().toObsidianBases(
            customization: TestCustomizations.camelCase
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_customAndPlaceholderFields_doesNotCrash() {
        let result = HealthData.fullyPopulated().toObsidianBases(
            customization: TestCustomizations.customFields
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_dateOnlyFrontmatter_doesNotCrash() {
        let result = HealthData.empty().toObsidianBases(
            customization: TestCustomizations.dateOnly
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_noMetaKeys_doesNotCrash() {
        let result = HealthData.empty().toObsidianBases(
            customization: TestCustomizations.noMetaKeys
        )
        XCTAssertNotNil(result)
    }

    func testObsidianBases_allDateFormats_doesNotCrash() {
        for (fmt, customization) in TestCustomizations.dateFormats {
            let result = HealthData.fullyPopulated().toObsidianBases(customization: customization)
            XCTAssertFalse(result.isEmpty, "Empty output for date format \(fmt)")
        }
    }

    func testObsidianBases_allTimeFormats_doesNotCrash() {
        for (fmt, customization) in TestCustomizations.timeFormats {
            let result = HealthData.fullyPopulated().toObsidianBases(customization: customization)
            XCTAssertFalse(result.isEmpty, "Empty output for time format \(fmt)")
        }
    }

    func testObsidianBases_fieldDisabled_doesNotCrash() {
        let result = HealthData.fullyPopulated().toObsidianBases(
            customization: TestCustomizations.stepsDisabled
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_vitalsNoRange_doesNotCrash() {
        let result = HealthData.vitalsNoRange().toObsidianBases(
            customization: TestCustomizations.default
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_manyMoodEntries_doesNotCrash() {
        let result = HealthData.manyMoodEntries().toObsidianBases(
            customization: TestCustomizations.default
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testObsidianBases_workoutsWithNilFields_doesNotCrash() {
        var data = HealthData(date: Date())
        data.workouts = [
            WorkoutData(workoutType: .cycling, startTime: Date(), duration: 2400,
                        calories: nil, distance: nil)
        ]
        let result = data.toObsidianBases(customization: TestCustomizations.default)
        XCTAssertFalse(result.isEmpty)
    }
}

// MARK: - Health Metrics Dictionary Completeness Tests

final class HealthMetricsDictionaryTests: XCTestCase {

    /// The shared dictionary must include vitals min/max/avg split keys so that
    /// every exporter consuming it can surface the full range data.
    func testDictionary_containsExtendedVitalsKeys() {
        let data = HealthData.fullyPopulated()
        let dict = data.allMetricsDictionary(using: TestCustomizations.default.unitConverter)

        let expectedVitalsKeys = [
            "respiratory_rate_avg", "respiratory_rate_min", "respiratory_rate_max",
            "blood_oxygen_avg", "blood_oxygen_min", "blood_oxygen_max",
            "body_temperature_avg", "body_temperature_min", "body_temperature_max",
            "blood_pressure_systolic_avg", "blood_pressure_systolic_min", "blood_pressure_systolic_max",
            "blood_pressure_diastolic_avg", "blood_pressure_diastolic_min", "blood_pressure_diastolic_max",
            "blood_glucose_avg", "blood_glucose_min", "blood_glucose_max",
        ]
        for key in expectedVitalsKeys {
            XCTAssertNotNil(dict[key], "Dictionary missing vitals key: \(key)")
        }
    }

    /// The shared dictionary must include extended mindfulness keys so that
    /// exporters can surface mood entry counts, labels, and associations.
    func testDictionary_containsExtendedMindfulnessKeys() {
        let data = HealthData.fullyPopulated()
        let dict = data.allMetricsDictionary(using: TestCustomizations.default.unitConverter)

        let expectedKeys = [
            "mood_entries", "daily_mood_count", "daily_mood_percent",
            "momentary_emotion_count", "mood_labels", "mood_associations",
        ]
        for key in expectedKeys {
            XCTAssertNotNil(dict[key], "Dictionary missing mindfulness key: \(key)")
        }
    }

    /// Canonical regression: direct dictionary and snapshot frontmatter metrics
    /// must always be identical for fully populated fixtures.
    func testDictionary_matchesSnapshotFrontmatter_fullFixture() {
        let data = ExportFixtures.fullDay
        let customization = TestCustomizations.default

        let snapshot = data.exportSnapshot(customization: customization)
        let dict = data.allMetricsDictionary(
            using: customization.unitConverter,
            timeFormat: customization.timeFormat
        )

        XCTAssertEqual(dict, snapshot.frontmatterMetrics)
    }

    /// Canonical regression for sparse/edge fixture coverage.
    func testDictionary_matchesSnapshotFrontmatter_edgeFixture() {
        let data = ExportFixtures.edgeCaseDay
        let customization = TestCustomizations.imperial

        let snapshot = data.exportSnapshot(customization: customization)
        let dict = data.allMetricsDictionary(
            using: customization.unitConverter,
            timeFormat: customization.timeFormat
        )

        XCTAssertEqual(dict, snapshot.frontmatterMetrics)
    }
}

// MARK: - Obsidian Bases / Dictionary Parity Tests

final class ObsidianBasesDictionaryParityTests: XCTestCase {

    /// Every key produced by the shared dictionary must appear in the Obsidian
    /// Bases output. If this test fails, the exporter has drifted from the
    /// canonical metric source and a field will be missing for users.
    func testObsidianBases_parity_allDictionaryKeysPresent() {
        let data = HealthData.fullyPopulated()
        let customization = TestCustomizations.default
        let result = data.toObsidianBases(customization: customization)
        let allKeys = data.allMetricsDictionary(
            using: customization.unitConverter
        ).keys

        for key in allKeys.sorted() {
            XCTAssertTrue(
                result.contains("\n\(key): "),
                "Obsidian Bases export missing dictionary key: \(key)"
            )
        }
    }
}

// MARK: - DailyNoteInjector Helper Tests
// These test the public static helper that maps metric IDs to frontmatter keys.
// MetricSelectionState is also an ObservableObject; we hold a static reference
// to avoid the macOS 26 reentrant-main-actor-deinit crash.

final class DailyNoteInjectorHelperTests: XCTestCase {

    // Static instances to avoid the ObservableObject deinit crash
    private static let allEnabledSelection = MetricSelectionState()
    private static let noneEnabledSelection: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        return s
    }()
    private static let sleepOnlySelection: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.toggleCategory(.sleep)
        return s
    }()
    private static let activityOnlySelection: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.toggleCategory(.activity)
        return s
    }()

    func testFrontmatterKeys_allEnabled_returnsNonEmpty() {
        let keys = DailyNoteInjector.frontmatterKeys(
            enabledIn: DailyNoteInjectorHelperTests.allEnabledSelection
        )
        XCTAssertFalse(keys.isEmpty)
    }

    func testFrontmatterKeys_noneEnabled_returnsEmpty() {
        let keys = DailyNoteInjector.frontmatterKeys(
            enabledIn: DailyNoteInjectorHelperTests.noneEnabledSelection
        )
        XCTAssertTrue(keys.isEmpty)
    }

    func testFrontmatterKeys_sleepOnly_containsSleepKeys() {
        let keys = DailyNoteInjector.frontmatterKeys(
            enabledIn: DailyNoteInjectorHelperTests.sleepOnlySelection
        )
        XCTAssertTrue(keys.contains("sleep_total_hours"))
    }

    func testFrontmatterKeys_noDuplicates() {
        let keys = DailyNoteInjector.frontmatterKeys(
            enabledIn: DailyNoteInjectorHelperTests.allEnabledSelection
        )
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testFrontmatterKeys_activityOnly_containsSteps() {
        let keys = DailyNoteInjector.frontmatterKeys(
            enabledIn: DailyNoteInjectorHelperTests.activityOnlySelection
        )
        XCTAssertTrue(keys.contains("steps"))
    }
}

// MARK: - Export Metric Selection Tests

final class ExportMetricSelectionTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings contains nested
    // ObservableObjects. Static retention avoids macOS 26 / Swift 6 deinit crash.
    // See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testExport_ignoresLegacyDataTypes_andUsesMetricSelection() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var legacyTypes = DataTypeSelection()
        legacyTypes.deselectAll()
        settings.dataTypes = legacyTypes

        settings.metricSelection.deselectAll()
        settings.metricSelection.enabledMetrics.insert("steps")

        let output = HealthData.fullyPopulated().export(format: .json, settings: settings)

        XCTAssertTrue(output.contains("\"steps\""))
        XCTAssertFalse(output.contains("\"activeCalories\""))
        XCTAssertFalse(output.contains("\"sleep\""))
    }

    func testExport_metricSelection_appliesConsistentlyAcrossFormats() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.metricSelection.deselectAll()
        settings.metricSelection.enabledMetrics.insert("steps")

        let data = HealthData.fullyPopulated()

        let markdown = data.export(format: .markdown, settings: settings)
        XCTAssertTrue(markdown.contains("Steps"))
        XCTAssertFalse(markdown.contains("Active Calories"))

        let bases = data.export(format: .obsidianBases, settings: settings)
        XCTAssertTrue(bases.contains("\nsteps: "))
        XCTAssertFalse(bases.contains("active_calories:"))

        let json = data.export(format: .json, settings: settings)
        XCTAssertTrue(json.contains("\"steps\""))
        XCTAssertFalse(json.contains("\"activeCalories\""))

        let csv = data.export(format: .csv, settings: settings)
        XCTAssertTrue(csv.contains(",Activity,Steps,"))
        XCTAssertFalse(csv.contains(",Activity,Active Calories,"))
    }

    func testExport_metricSelection_enablingMetricsIncludesThem() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.metricSelection.deselectAll()
        settings.metricSelection.enabledMetrics.insert("workouts")

        let output = HealthData.fullyPopulated().export(format: .json, settings: settings)

        XCTAssertTrue(output.contains("\"workouts\""))
        XCTAssertFalse(output.contains("\"activity\""))
    }

    func testExport_metricSelection_mindfulnessRespectsAverageAndKindToggles() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.metricSelection.deselectAll()
        settings.metricSelection.enabledMetrics.insert("momentary_emotions")

        var data = HealthData(date: Date())
        data.mindfulness.stateOfMind = [
            StateOfMindEntry(timestamp: Date(), kind: .dailyMood, valence: 0.6, labels: ["Good"], associations: ["Work"]),
            StateOfMindEntry(timestamp: Date(), kind: .momentaryEmotion, valence: -0.2, labels: ["Stressed"], associations: ["Commute"]),
        ]

        let output = data.export(format: .json, settings: settings)

        XCTAssertTrue(output.contains("\"mindfulness\""))
        XCTAssertTrue(output.contains("\"momentaryEmotionCount\""))
        XCTAssertFalse(output.contains("\"dailyMoodCount\""))
        XCTAssertFalse(output.contains("\"averageValence\""))
    }

    private func makeSettings() -> (AdvancedExportSettings, UserDefaults, String) {
        let suiteName = "healthmd.tests.export-metric-selection.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)

        settings.includeMetadata = false
        settings.groupByCategory = true
        settings.exportFormats = [.json]

        return (settings, defaults, suiteName)
    }
}
