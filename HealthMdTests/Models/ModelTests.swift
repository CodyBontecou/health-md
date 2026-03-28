//
//  ModelTests.swift
//  HealthMdTests
//
//  TDD tests for ExportSchedule, SyncPayload, SyncMessage, HealthData,
//  DailyNoteInjectionSettings, and IndividualTrackingSettings models.
//

import XCTest
@testable import HealthMd

// MARK: - ExportSchedule Tests

final class ExportScheduleTests: XCTestCase {

    func testDefaultValues() {
        let schedule = ExportSchedule()
        XCTAssertFalse(schedule.isEnabled)
        XCTAssertEqual(schedule.frequency, .daily)
        XCTAssertEqual(schedule.preferredHour, 8)
        XCTAssertEqual(schedule.preferredMinute, 0)
        XCTAssertNil(schedule.lastExportDate)
    }

    func testDailyInterval() {
        XCTAssertEqual(ScheduleFrequency.daily.interval, 86_400)
    }

    func testWeeklyInterval() {
        XCTAssertEqual(ScheduleFrequency.weekly.interval, 604_800)
    }

    func testFrequencyDescriptions() {
        XCTAssertEqual(ScheduleFrequency.daily.description, "Daily")
        XCTAssertEqual(ScheduleFrequency.weekly.description, "Weekly")
    }

    func testCodable() throws {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 22,
            preferredMinute: 30,
            lastExportDate: Date()
        )
        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(ExportSchedule.self, from: data)
        XCTAssertEqual(decoded.isEnabled, true)
        XCTAssertEqual(decoded.frequency, .weekly)
        XCTAssertEqual(decoded.preferredHour, 22)
        XCTAssertEqual(decoded.preferredMinute, 30)
        XCTAssertNotNil(decoded.lastExportDate)
    }

    func testAllFrequencyCases() {
        let cases = ScheduleFrequency.allCases
        XCTAssertEqual(cases.count, 2)
        XCTAssertTrue(cases.contains(.daily))
        XCTAssertTrue(cases.contains(.weekly))
    }
}

// MARK: - SyncPayload Tests

final class SyncPayloadTests: XCTestCase {

    func testSyncPayload_codable() throws {
        let healthData = HealthData(date: Date())
        let payload = SyncPayload(
            deviceName: "Test iPhone",
            syncTimestamp: Date(),
            healthRecords: [healthData]
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SyncPayload.self, from: data)
        XCTAssertEqual(decoded.deviceName, "Test iPhone")
        XCTAssertEqual(decoded.healthRecords.count, 1)
    }

    func testSyncPayload_multipleRecords() throws {
        let records = (0..<5).map { i in
            HealthData(date: Date().addingTimeInterval(Double(i) * -86400))
        }
        let payload = SyncPayload(
            deviceName: "Cody's iPhone",
            syncTimestamp: Date(),
            healthRecords: records
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SyncPayload.self, from: data)
        XCTAssertEqual(decoded.healthRecords.count, 5)
    }

    func testSyncPayload_emptyRecords() throws {
        let payload = SyncPayload(
            deviceName: "Empty Phone",
            syncTimestamp: Date(),
            healthRecords: []
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SyncPayload.self, from: data)
        XCTAssertTrue(decoded.healthRecords.isEmpty)
    }
}

// MARK: - SyncMessage Tests

final class SyncMessageTests: XCTestCase {

    func testPingPong_codable() throws {
        let ping = SyncMessage.ping
        let data = try JSONEncoder().encode(ping)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)
        if case .ping = decoded { /* pass */ }
        else { XCTFail("Expected .ping") }

        let pong = SyncMessage.pong
        let pongData = try JSONEncoder().encode(pong)
        let decodedPong = try JSONDecoder().decode(SyncMessage.self, from: pongData)
        if case .pong = decodedPong { /* pass */ }
        else { XCTFail("Expected .pong") }
    }

    func testRequestData_codable() throws {
        let dates = [Date(), Date().addingTimeInterval(-86400)]
        let msg = SyncMessage.requestData(dates: dates)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)
        if case .requestData(let decodedDates) = decoded {
            XCTAssertEqual(decodedDates.count, 2)
        } else {
            XCTFail("Expected .requestData")
        }
    }

    func testRequestAllData_codable() throws {
        let msg = SyncMessage.requestAllData
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)
        if case .requestAllData = decoded { /* pass */ }
        else { XCTFail("Expected .requestAllData") }
    }

    func testSyncProgress_codable() throws {
        let progress = SyncProgressInfo(
            totalDays: 100,
            processedDays: 50,
            recordsInBatch: 10,
            isComplete: false,
            message: "Processing..."
        )
        let msg = SyncMessage.syncProgress(progress)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)
        if case .syncProgress(let p) = decoded {
            XCTAssertEqual(p.totalDays, 100)
            XCTAssertEqual(p.processedDays, 50)
            XCTAssertEqual(p.fractionComplete, 0.5, accuracy: 0.001)
        } else {
            XCTFail("Expected .syncProgress")
        }
    }
}

// MARK: - SyncProgressInfo Tests

final class SyncProgressInfoTests: XCTestCase {

    func testFractionComplete_normal() {
        let info = SyncProgressInfo(totalDays: 100, processedDays: 25, recordsInBatch: 5, isComplete: false, message: nil)
        XCTAssertEqual(info.fractionComplete, 0.25, accuracy: 0.001)
    }

    func testFractionComplete_zeroTotal() {
        let info = SyncProgressInfo(totalDays: 0, processedDays: 0, recordsInBatch: 0, isComplete: false, message: nil)
        XCTAssertEqual(info.fractionComplete, 0)
    }

    func testFractionComplete_complete() {
        let info = SyncProgressInfo(totalDays: 50, processedDays: 50, recordsInBatch: 10, isComplete: true, message: "Done")
        XCTAssertEqual(info.fractionComplete, 1.0, accuracy: 0.001)
    }
}

// MARK: - SyncMetadata Tests

final class SyncMetadataTests: XCTestCase {

    func testDefaults() {
        let metadata = SyncMetadata()
        XCTAssertNil(metadata.lastSyncDate)
        XCTAssertNil(metadata.sourceDeviceName)
        XCTAssertEqual(metadata.recordCount, 0)
        XCTAssertTrue(metadata.syncedDates.isEmpty)
    }

    func testCodable() throws {
        var metadata = SyncMetadata()
        metadata.lastSyncDate = Date()
        metadata.sourceDeviceName = "Test iPhone"
        metadata.recordCount = 30
        metadata.syncedDates = [Date()]

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(SyncMetadata.self, from: data)
        XCTAssertNotNil(decoded.lastSyncDate)
        XCTAssertEqual(decoded.sourceDeviceName, "Test iPhone")
        XCTAssertEqual(decoded.recordCount, 30)
        XCTAssertEqual(decoded.syncedDates.count, 1)
    }
}

// MARK: - HealthData Tests

final class HealthDataTests: XCTestCase {
    private func makeSelection(_ configure: (MetricSelectionState) -> Void) -> MetricSelectionState {
        let selection = MetricSelectionState()
        configure(selection)
        return LifecycleHarness.retain(selection)
    }

    func testHasAnyData_empty() {
        let data = HealthData(date: Date())
        XCTAssertFalse(data.hasAnyData)
    }

    func testHasAnyData_sleepOnly() {
        var data = HealthData(date: Date())
        data.sleep.totalDuration = 7 * 3600
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_activityOnly() {
        var data = HealthData(date: Date())
        data.activity.steps = 10_000
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_workoutsOnly() {
        var data = HealthData(date: Date())
        data.workouts = [WorkoutData(workoutType: .running, startTime: Date(), duration: 1800, calories: nil, distance: nil)]
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_heartOnly() {
        var data = HealthData(date: Date())
        data.heart.restingHeartRate = 60
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_vitalsOnly() {
        var data = HealthData(date: Date())
        data.vitals.bloodOxygenAvg = 0.98
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_nutritionOnly() {
        var data = HealthData(date: Date())
        data.nutrition.dietaryEnergy = 2000
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_mindfulnessOnly() {
        var data = HealthData(date: Date())
        data.mindfulness.mindfulMinutes = 15
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_mobilityOnly() {
        var data = HealthData(date: Date())
        data.mobility.walkingSpeed = 1.2
        XCTAssertTrue(data.hasAnyData)
    }

    func testHasAnyData_hearingOnly() {
        var data = HealthData(date: Date())
        data.hearing.headphoneAudioLevel = 65.0
        XCTAssertTrue(data.hasAnyData)
    }

    func testHealthData_codable() throws {
        var data = HealthData(date: Date())
        data.activity.steps = 10_000
        data.sleep.totalDuration = 7 * 3600
        data.heart.restingHeartRate = 58

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(HealthData.self, from: encoded)
        XCTAssertEqual(decoded.activity.steps, 10_000)
        XCTAssertEqual(decoded.sleep.totalDuration, 7 * 3600)
        XCTAssertEqual(decoded.heart.restingHeartRate, 58)
    }

    func testFilteredByMetricSelection_disablesSpecificActivityMetricOnly() {
        var data = HealthData(date: Date())
        data.activity.steps = 10_000
        data.activity.activeCalories = 450

        let selection = makeSelection { selection in
            selection.deselectAll()
            selection.enabledMetrics.insert("steps")
        }

        let filtered = data.filtered(by: selection)
        XCTAssertEqual(filtered.activity.steps, 10_000)
        XCTAssertNil(filtered.activity.activeCalories)
    }

    func testFilteredByMetricSelection_disablesBloodGlucoseBundleOnly() {
        var data = HealthData(date: Date())
        data.vitals.bloodGlucoseAvg = 95
        data.vitals.bloodGlucoseMin = 80
        data.vitals.bloodGlucoseMax = 110
        data.vitals.bloodPressureSystolicAvg = 120
        data.vitals.bloodPressureDiastolicAvg = 80

        let selection = makeSelection { selection in
            selection.deselectAll()
            selection.enabledMetrics.insert("blood_pressure_systolic")
            selection.enabledMetrics.insert("blood_pressure_diastolic")
        }

        let filtered = data.filtered(by: selection)
        XCTAssertNil(filtered.vitals.bloodGlucoseAvg)
        XCTAssertNil(filtered.vitals.bloodGlucoseMin)
        XCTAssertNil(filtered.vitals.bloodGlucoseMax)
        XCTAssertEqual(filtered.vitals.bloodPressureSystolicAvg, 120)
        XCTAssertEqual(filtered.vitals.bloodPressureDiastolicAvg, 80)
    }

    func testFilteredByMetricSelection_mindfulnessRespectsPerMetricToggles() {
        var data = HealthData(date: Date())
        data.mindfulness.mindfulMinutes = 15
        data.mindfulness.mindfulSessions = 2
        data.mindfulness.stateOfMind = [
            StateOfMindEntry(timestamp: Date(), kind: .dailyMood, valence: 0.4, labels: ["Good"], associations: ["Work"]),
            StateOfMindEntry(timestamp: Date(), kind: .momentaryEmotion, valence: -0.1, labels: ["Tired"], associations: ["Travel"]),
        ]

        let selection = makeSelection { selection in
            selection.deselectAll()
            selection.enabledMetrics.insert("mindful_minutes")
            selection.enabledMetrics.insert("mindful_sessions")
            selection.enabledMetrics.insert("momentary_emotions")
        }

        let filtered = data.filtered(by: selection)
        XCTAssertEqual(filtered.mindfulness.mindfulMinutes, 15)
        XCTAssertEqual(filtered.mindfulness.mindfulSessions, 2)
        XCTAssertEqual(filtered.mindfulness.stateOfMind.count, 1)
        XCTAssertEqual(filtered.mindfulness.stateOfMind.first?.kind, .momentaryEmotion)
        XCTAssertNil(filtered.mindfulness.averageValence)
    }

    func testFiltered_disablesSleep() {
        var data = HealthData(date: Date())
        data.sleep.totalDuration = 7 * 3600
        data.activity.steps = 10_000

        var types = DataTypeSelection()
        types.sleep = false

        let filtered = data.filtered(by: types)
        XCTAssertFalse(filtered.sleep.hasData)
        XCTAssertTrue(filtered.activity.hasData) // activity still has data
    }

    func testMakeSelection_retainsViaLifecycleHarness() {
        let before = LifecycleHarness.retainedCount
        _ = makeSelection { $0.selectAll() }
        XCTAssertGreaterThan(LifecycleHarness.retainedCount, before,
            "makeSelection should retain via LifecycleHarness")
    }

    func testFiltered_disablesAll() {
        var data = HealthData(date: Date())
        data.sleep.totalDuration = 7 * 3600
        data.activity.steps = 10_000
        data.heart.restingHeartRate = 60

        var types = DataTypeSelection()
        types.sleep = false
        types.activity = false
        types.heart = false
        types.vitals = false
        types.body = false
        types.nutrition = false
        types.mindfulness = false
        types.mobility = false
        types.hearing = false
        types.workouts = false

        let filtered = data.filtered(by: types)
        XCTAssertFalse(filtered.hasAnyData)
    }
}

// MARK: - AdvancedExportSettings Migration Tests

final class AdvancedExportSettingsMigrationTests: XCTestCase {

    func testMigration_legacyDataTypes_populatesAndPersistsMetricSelection() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        var legacy = DataTypeSelection()
        legacy.sleep = false
        legacy.activity = false
        legacy.workouts = false

        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: "advancedExportSettings.dataTypes")
        defaults.removeObject(forKey: "advancedExportSettings.metricSelection")

        let settings = AdvancedExportSettings(userDefaults: defaults)
        LifecycleHarness.retain(settings)

        let expected = legacy.toMetricSelectionState()
        LifecycleHarness.retain(expected)
        XCTAssertEqual(settings.metricSelection.enabledMetrics, expected.enabledMetrics)
        XCTAssertEqual(settings.metricSelection.enabledCategories, expected.enabledCategories)

        let persistedData = defaults.data(forKey: "advancedExportSettings.metricSelection")
        XCTAssertNotNil(persistedData, "Migrated metricSelection should be persisted immediately")
    }

    func testMigration_existingMetricSelectionTakesPrecedenceOverLegacyDataTypes() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        var legacy = DataTypeSelection()
        legacy.deselectAll()
        defaults.set(try JSONEncoder().encode(legacy), forKey: "advancedExportSettings.dataTypes")

        let metricSelection = MetricSelectionState()
        metricSelection.deselectAll()
        metricSelection.enabledMetrics.insert("steps")
        LifecycleHarness.retain(metricSelection)
        defaults.set(try JSONEncoder().encode(metricSelection), forKey: "advancedExportSettings.metricSelection")

        let settings = AdvancedExportSettings(userDefaults: defaults)
        LifecycleHarness.retain(settings)

        XCTAssertTrue(settings.metricSelection.isMetricEnabled("steps"))
        XCTAssertEqual(settings.metricSelection.enabledMetrics, ["steps"])
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "healthmd.tests.advanced-export-settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func cleanup(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - DailyNoteInjectionSettings Tests
// Static instances avoid the macOS 26 / Swift 6 ObservableObject deinit crash.

final class DailyNoteInjectionSettingsTests: XCTestCase {

    // Static read-only instances to avoid the macOS 26 / Swift 6 ObservableObject
    // deinit crash. These are immutable shared fixtures — per-test factories are
    // not needed because no test mutates them. See docs/testing/lifecycle-audit.md.
    private static let defaultSettings = LifecycleHarness.create({ DailyNoteInjectionSettings() })
    // resetSettings: migrated to per-test factory (mutable, used only in testReset)
    private static let yearMonthDaySettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.filenamePattern = "{year}/{month}/{day}"
        return s
    }()
    private static let quarterSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.filenamePattern = "{date}_{quarter}"
        return s
    }()
    private static let dailyFolderSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.folderPath = "Daily"
        return s
    }()
    private static let emptyFolderSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.folderPath = ""
        return s
    }()
    private static let testDate: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 27
        return Calendar.current.date(from: comps)!
    }()

    private static let julyDate: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 27
        return Calendar.current.date(from: comps)!
    }()

    func testDefaults() {
        let s = Self.defaultSettings
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.folderPath, "Daily")
        XCTAssertEqual(s.filenamePattern, "{date}")
        XCTAssertFalse(s.createIfMissing)
    }

    func testReset() {
        let s = LifecycleHarness.create({ DailyNoteInjectionSettings() }) { s in
            s.enabled = true
            s.folderPath = "Custom"
            s.filenamePattern = "{year}-{month}-{day}"
            s.createIfMissing = true
        }
        s.reset()
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.folderPath, "Daily")
        XCTAssertEqual(s.filenamePattern, "{date}")
        XCTAssertFalse(s.createIfMissing)
    }

    func testFormatFilename_defaultPattern() {
        let s = LifecycleHarness.create({ DailyNoteInjectionSettings() })
        XCTAssertEqual(s.formatFilename(for: Self.testDate), "2026-03-27")
    }

    func testFormatFilename_yearMonthDay() {
        XCTAssertEqual(Self.yearMonthDaySettings.formatFilename(for: Self.testDate), "2026/03/27")
    }

    func testFormatFilename_quarter() {
        XCTAssertEqual(Self.quarterSettings.formatFilename(for: Self.testDate), "2026-03-27_Q1")
        XCTAssertEqual(Self.quarterSettings.formatFilename(for: Self.julyDate), "2026-07-27_Q3")
    }

    func testPreviewPath_noSubfolder() {
        XCTAssertEqual(Self.dailyFolderSettings.previewPath(for: Self.testDate), "Daily/2026-03-27.md")
    }

    func testPreviewPath_withHealthSubfolder() {
        XCTAssertEqual(Self.dailyFolderSettings.previewPath(for: Self.testDate, healthSubfolder: "Health"), "Health/Daily/2026-03-27.md")
    }

    func testPreviewPath_emptyFolderPath() {
        XCTAssertEqual(Self.emptyFolderSettings.previewPath(for: Self.testDate), "2026-03-27.md")
    }

    func testCodable() throws {
        let settings = LifecycleHarness.create({ DailyNoteInjectionSettings() }) { s in
            s.enabled = true
            s.folderPath = "Journal"
            s.filenamePattern = "{date}"
            s.createIfMissing = true
        }

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DailyNoteInjectionSettings.self, from: data)
        LifecycleHarness.retain(decoded)

        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.folderPath, "Journal")
        XCTAssertEqual(decoded.filenamePattern, "{date}")
        XCTAssertTrue(decoded.createIfMissing)
    }
}

// MARK: - IndividualTrackingSettings Tests
// Static read-only instances avoid the macOS 26 / Swift 6 ObservableObject deinit
// crash. Mutable instances (toggleSettings, resetSettings) use per-test factories
// via LifecycleHarness.create() for test isolation. See docs/testing/lifecycle-audit.md.

final class IndividualTrackingSettingsTests: XCTestCase {

    private static let defaultSettings = LifecycleHarness.create({ IndividualTrackingSettings() })

    private static let globalDisabledWithWeight: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = false
        s.setTrackIndividually("weight", enabled: true)
        return s
    }()

    private static let globalEnabledWithWeight: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("weight", enabled: true)
        return s
    }()

    private static let globalEnabledEmpty: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        return s
    }()

    // toggleSettings: migrated to per-test factory (mutable, used in testToggleMetric)

    private static let threeMetrics: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("weight", enabled: true)
        s.setTrackIndividually("blood_glucose", enabled: true)
        s.setTrackIndividually("steps", enabled: true)
        return s
    }()

    // resetSettings: migrated to per-test factory (mutable, used in testReset)

    private static let categoryFolderSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.useCategoryFolders = true
        return s
    }()

    private static let noCategoryFolderSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.useCategoryFolders = false
        return s
    }()

    private static let filenameSettings = IndividualTrackingSettings()

    private static let weightMetric = HealthMetricDefinition(
        id: "weight", name: "Weight", category: .bodyMeasurements,
        unit: "kg", healthKitIdentifier: nil, metricType: .quantity, aggregation: .mostRecent
    )

    private static let testDate: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 27
        comps.hour = 10; comps.minute = 30
        return Calendar.current.date(from: comps)!
    }()

    func testDefaults() {
        XCTAssertFalse(Self.defaultSettings.globalEnabled)
        XCTAssertTrue(Self.defaultSettings.metricConfigs.isEmpty)
        XCTAssertEqual(Self.defaultSettings.entriesFolder, "entries")
        XCTAssertTrue(Self.defaultSettings.useCategoryFolders)
    }

    func testShouldTrackIndividually_globalDisabled() {
        XCTAssertFalse(Self.globalDisabledWithWeight.shouldTrackIndividually("weight"))
    }

    func testShouldTrackIndividually_enabled() {
        XCTAssertTrue(Self.globalEnabledWithWeight.shouldTrackIndividually("weight"))
    }

    func testShouldTrackIndividually_notConfigured() {
        XCTAssertFalse(Self.globalEnabledEmpty.shouldTrackIndividually("weight"))
    }

    func testToggleMetric() {
        let s = LifecycleHarness.create({ IndividualTrackingSettings() }) { s in
            s.globalEnabled = true
        }
        XCTAssertFalse(s.shouldTrackIndividually("blood_glucose"))
        s.toggleMetric("blood_glucose")
        XCTAssertTrue(s.shouldTrackIndividually("blood_glucose"))
        s.toggleMetric("blood_glucose")
        XCTAssertFalse(s.shouldTrackIndividually("blood_glucose"))
    }

    func testTotalEnabledCount() {
        XCTAssertEqual(Self.threeMetrics.totalEnabledCount, 3)
    }

    func testTotalEnabledCount_globalDisabled() {
        XCTAssertEqual(Self.globalDisabledWithWeight.totalEnabledCount, 0)
    }

    func testReset() {
        let s = LifecycleHarness.create({ IndividualTrackingSettings() }) { s in
            s.globalEnabled = true
            s.entriesFolder = "custom"
            s.useCategoryFolders = false
            s.filenameTemplate = "custom_{date}"
            s.setTrackIndividually("weight", enabled: true)
        }
        s.reset()
        XCTAssertFalse(s.globalEnabled)
        XCTAssertTrue(s.metricConfigs.isEmpty)
        XCTAssertEqual(s.entriesFolder, "entries")
        XCTAssertTrue(s.useCategoryFolders)
        XCTAssertEqual(s.filenameTemplate, "{date}_{time}_{metric}")
    }

    func testFolderPath_withCategoryFolders() {
        XCTAssertEqual(Self.categoryFolderSettings.folderPath(for: Self.weightMetric), "entries/body_measurements")
    }

    func testFolderPath_withoutCategoryFolders() {
        XCTAssertEqual(Self.noCategoryFolderSettings.folderPath(for: Self.weightMetric), "entries")
    }

    func testFilename_defaultTemplate() {
        let filename = Self.filenameSettings.filename(for: Self.weightMetric, date: Self.testDate, time: Self.testDate)
        XCTAssertEqual(filename, "2026_03_27_1030_weight.md")
    }

    func testCodable() throws {
        let settings = LifecycleHarness.create({ IndividualTrackingSettings() }) { s in
            s.globalEnabled = true
            s.entriesFolder = "data"
            s.setTrackIndividually("weight", enabled: true)
        }

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(IndividualTrackingSettings.self, from: data)
        LifecycleHarness.retain(decoded)

        XCTAssertTrue(decoded.globalEnabled)
        XCTAssertEqual(decoded.entriesFolder, "data")
        XCTAssertTrue(decoded.metricConfigs["weight"]?.trackIndividually ?? false)
    }

    func testIsSuggested() {
        XCTAssertTrue(IndividualTrackingSettings.isSuggested("daily_mood"))
        XCTAssertTrue(IndividualTrackingSettings.isSuggested("workouts"))
        XCTAssertTrue(IndividualTrackingSettings.isSuggested("blood_glucose"))
        XCTAssertFalse(IndividualTrackingSettings.isSuggested("steps"))
        XCTAssertFalse(IndividualTrackingSettings.isSuggested("weight"))
    }
}

// MARK: - StateOfMindEntry Tests

final class StateOfMindEntryTests: XCTestCase {

    func testValenceDescription_ranges() {
        let entry = makeEntry(valence: 0.7)
        XCTAssertEqual(entry.valenceDescription, "Very Pleasant")

        XCTAssertEqual(makeEntry(valence: -0.8).valenceDescription, "Very Unpleasant")
        XCTAssertEqual(makeEntry(valence: -0.4).valenceDescription, "Unpleasant")
        XCTAssertEqual(makeEntry(valence: 0.0).valenceDescription, "Neutral")
        XCTAssertEqual(makeEntry(valence: 0.4).valenceDescription, "Pleasant")
    }

    func testValencePercent() {
        XCTAssertEqual(makeEntry(valence: -1.0).valencePercent, 0)
        XCTAssertEqual(makeEntry(valence: 0.0).valencePercent, 50)
        XCTAssertEqual(makeEntry(valence: 1.0).valencePercent, 100)
    }

    func testCodable() throws {
        let entry = makeEntry(valence: 0.5, labels: ["Happy"], associations: ["Exercise"])
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(StateOfMindEntry.self, from: data)
        XCTAssertEqual(decoded.valence, 0.5)
        XCTAssertEqual(decoded.labels, ["Happy"])
        XCTAssertEqual(decoded.associations, ["Exercise"])
        XCTAssertEqual(decoded.kind, .dailyMood)
    }

    func testMindfulnessData_averageValence() {
        var mind = MindfulnessData()
        mind.stateOfMind = [
            makeEntry(valence: 0.5),
            makeEntry(valence: -0.5)
        ]
        XCTAssertEqual(mind.averageValence!, 0.0, accuracy: 0.001)
    }

    func testMindfulnessData_averageValence_empty() {
        let mind = MindfulnessData()
        XCTAssertNil(mind.averageValence)
    }

    func testMindfulnessData_allLabels() {
        var mind = MindfulnessData()
        mind.stateOfMind = [
            makeEntry(valence: 0.5, labels: ["Happy", "Calm"]),
            makeEntry(valence: -0.3, labels: ["Anxious", "Happy"])
        ]
        let labels = mind.allLabels
        XCTAssertEqual(labels.count, 3) // Anxious, Calm, Happy (sorted, deduplicated)
        XCTAssertEqual(labels, ["Anxious", "Calm", "Happy"])
    }

    // MARK: - Helpers

    private func makeEntry(
        valence: Double,
        labels: [String] = [],
        associations: [String] = []
    ) -> StateOfMindEntry {
        StateOfMindEntry(
            timestamp: Date(),
            kind: .dailyMood,
            valence: valence,
            labels: labels,
            associations: associations
        )
    }
}

// MARK: - WorkoutData Tests

final class WorkoutDataTests: XCTestCase {

    func testWorkoutTypeName() {
        let workout = WorkoutData(workoutType: .running, startTime: Date(), duration: 1800, calories: 320, distance: 5000)
        XCTAssertEqual(workout.workoutTypeName, "Running")
    }

    func testAllWorkoutTypes_haveDisplayNames() {
        for type in WorkoutType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type.rawValue) should have a display name")
        }
    }

    func testCodable() throws {
        let workout = WorkoutData(workoutType: .cycling, startTime: Date(), duration: 3600, calories: 500, distance: 20_000)
        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(WorkoutData.self, from: data)
        XCTAssertEqual(decoded.workoutType, .cycling)
        XCTAssertEqual(decoded.duration, 3600)
        XCTAssertEqual(decoded.calories, 500)
        XCTAssertEqual(decoded.distance, 20_000)
    }
}

// MARK: - SubData hasData Tests

final class SubDataHasDataTests: XCTestCase {

    func testSleepData_hasData() {
        var sleep = SleepData()
        XCTAssertFalse(sleep.hasData)
        sleep.deepSleep = 3600
        XCTAssertTrue(sleep.hasData)
    }

    func testActivityData_hasData() {
        var activity = ActivityData()
        XCTAssertFalse(activity.hasData)
        activity.vo2Max = 42.5
        XCTAssertTrue(activity.hasData)
    }

    func testHeartData_hasData() {
        var heart = HeartData()
        XCTAssertFalse(heart.hasData)
        heart.hrv = 38.5
        XCTAssertTrue(heart.hasData)
    }

    func testVitalsData_hasData() {
        var vitals = VitalsData()
        XCTAssertFalse(vitals.hasData)
        vitals.bloodGlucoseAvg = 95.0
        XCTAssertTrue(vitals.hasData)
    }

    func testVitalsData_convenienceProperties() {
        var vitals = VitalsData()
        vitals.respiratoryRateAvg = 14.5
        vitals.bloodOxygenAvg = 0.98
        vitals.bodyTemperatureAvg = 36.8
        vitals.bloodPressureSystolicAvg = 120
        vitals.bloodPressureDiastolicAvg = 80
        vitals.bloodGlucoseAvg = 95

        XCTAssertEqual(vitals.respiratoryRate, 14.5)
        XCTAssertEqual(vitals.bloodOxygen, 0.98)
        XCTAssertEqual(vitals.bodyTemperature, 36.8)
        XCTAssertEqual(vitals.bloodPressureSystolic, 120)
        XCTAssertEqual(vitals.bloodPressureDiastolic, 80)
        XCTAssertEqual(vitals.bloodGlucose, 95)
    }

    func testBodyData_hasData() {
        var body = BodyData()
        XCTAssertFalse(body.hasData)
        body.bmi = 22.5
        XCTAssertTrue(body.hasData)
    }

    func testNutritionData_hasData() {
        var nutrition = NutritionData()
        XCTAssertFalse(nutrition.hasData)
        nutrition.caffeine = 200
        XCTAssertTrue(nutrition.hasData)
    }

    func testMindfulnessData_hasData() {
        var mind = MindfulnessData()
        XCTAssertFalse(mind.hasData)
        mind.stateOfMind = [StateOfMindEntry(timestamp: Date(), kind: .dailyMood, valence: 0.5, labels: [], associations: [])]
        XCTAssertTrue(mind.hasData)
    }

    func testMobilityData_hasData() {
        var mobility = MobilityData()
        XCTAssertFalse(mobility.hasData)
        mobility.sixMinuteWalkDistance = 500
        XCTAssertTrue(mobility.hasData)
    }

    func testHearingData_hasData() {
        var hearing = HearingData()
        XCTAssertFalse(hearing.hasData)
        hearing.environmentalSoundLevel = 55
        XCTAssertTrue(hearing.hasData)
    }
}
