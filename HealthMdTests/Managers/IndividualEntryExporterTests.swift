//
//  IndividualEntryExporterTests.swift
//  HealthMdTests
//
//  TDD tests for IndividualEntryExporter: sample extraction from HealthData,
//  YAML content generation, and file writing.
//
//  NOTE: IndividualTrackingSettings and FormatCustomization are ObservableObjects.
//  Static instances avoid the macOS 26 / Swift 6 reentrant-main-actor-deinit crash.
//

import XCTest
@testable import HealthMd

@MainActor
final class IndividualEntryExporterTests: XCTestCase {

    private let exporter = IndividualEntryExporter()

    private static let testDate: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 27
        comps.hour = 10; comps.minute = 30
        return Calendar.current.date(from: comps)!
    }()

    // STATIC RETENTION JUSTIFICATION: All instances below are immutable shared
    // read-only fixtures. Per-test factories are not needed because no test
    // mutates them. Static retention avoids the macOS 26 / Swift 6 ObservableObject
    // deinit crash. See docs/testing/lifecycle-audit.md.
    private static let formatSettings = FormatCustomization()

    private static let weightSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("weight", enabled: true)
        return s
    }()

    private static let emptySettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        return s
    }()

    private static let globalDisabledSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = false
        s.setTrackIndividually("weight", enabled: true)
        return s
    }()

    private static let bloodGlucoseSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("blood_glucose", enabled: true)
        return s
    }()

    private static let bpSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("blood_pressure_systolic", enabled: true)
        return s
    }()

    private static let workoutSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("workouts", enabled: true)
        return s
    }()

    private static let moodSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("daily_mood", enabled: true)
        return s
    }()

    private static let momentarySettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("momentary_emotions", enabled: true)
        return s
    }()

    // MARK: - extractIndividualSamples: empty data

    func testExtractSamples_emptyData_returnsEmpty() {
        let data = HealthData(date: Self.testDate)
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.emptySettings)
        XCTAssertTrue(samples.isEmpty)
    }

    // MARK: - extractIndividualSamples: global disabled

    func testExtractSamples_globalDisabled_returnsEmpty() {
        var data = HealthData(date: Self.testDate)
        data.body.weight = 72.5
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.globalDisabledSettings)
        XCTAssertTrue(samples.isEmpty)
    }

    // MARK: - extractIndividualSamples: weight

    func testExtractSamples_weight() {
        var data = HealthData(date: Self.testDate)
        data.body.weight = 72.5
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.weightSettings)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.metricId, "weight")
        XCTAssertEqual(samples.first?.value as? Double, 72.5)
        XCTAssertEqual(samples.first?.unit, "kg")
    }

    func testExtractSamples_weightNil_noSample() {
        let data = HealthData(date: Self.testDate)
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.weightSettings)
        let weightSamples = samples.filter { $0.metricId == "weight" }
        XCTAssertTrue(weightSamples.isEmpty)
    }

    // MARK: - extractIndividualSamples: blood glucose

    func testExtractSamples_bloodGlucose() {
        var data = HealthData(date: Self.testDate)
        data.vitals.bloodGlucoseAvg = 95.0
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.bloodGlucoseSettings)
        let glucoseSamples = samples.filter { $0.metricId == "blood_glucose" }
        XCTAssertEqual(glucoseSamples.count, 1)
        XCTAssertEqual(glucoseSamples.first?.value as? Double, 95.0)
    }

    // MARK: - extractIndividualSamples: blood pressure

    func testExtractSamples_bloodPressure() {
        var data = HealthData(date: Self.testDate)
        data.vitals.bloodPressureSystolicAvg = 120.0
        data.vitals.bloodPressureDiastolicAvg = 80.0
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.bpSettings)
        let bpSamples = samples.filter { $0.metricId == "blood_pressure" }
        XCTAssertEqual(bpSamples.count, 1)
        XCTAssertEqual(bpSamples.first?.value as? String, "120/80")
        XCTAssertEqual(bpSamples.first?.unit, "mmHg")
    }

    func testExtractSamples_bloodPressure_partialData_noSample() {
        var data = HealthData(date: Self.testDate)
        data.vitals.bloodPressureSystolicAvg = 120.0
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.bpSettings)
        let bpSamples = samples.filter { $0.metricId == "blood_pressure" }
        XCTAssertTrue(bpSamples.isEmpty)
    }

    // MARK: - extractIndividualSamples: workouts

    func testExtractSamples_workouts() {
        var data = HealthData(date: Self.testDate)
        data.workouts = [
            WorkoutData(workoutType: .running, startTime: Self.testDate, duration: 1800, calories: 320.0, distance: 5000),
            WorkoutData(workoutType: .yoga, startTime: Self.testDate, duration: 3600, calories: nil, distance: nil)
        ]
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.workoutSettings)
        let workoutSamples = samples.filter { $0.metricId == "workouts" }
        XCTAssertEqual(workoutSamples.count, 2)

        let running = workoutSamples[0]
        XCTAssertEqual(running.value as? String, "Running")
        XCTAssertEqual(running.additionalFields["workout_type"] as? String, "Running")
        XCTAssertEqual(running.additionalFields["duration_minutes"] as? Int, 30)
        XCTAssertEqual(running.additionalFields["calories"] as? Int, 320)
        XCTAssertEqual(running.additionalFields["distance_meters"] as? Int, 5000)

        let yoga = workoutSamples[1]
        XCTAssertEqual(yoga.value as? String, "Yoga")
        XCTAssertNil(yoga.additionalFields["calories"])
        XCTAssertNil(yoga.additionalFields["distance_meters"])
    }

    // MARK: - extractIndividualSamples: state of mind

    func testExtractSamples_stateOfMind() {
        var data = HealthData(date: Self.testDate)
        data.mindfulness.stateOfMind = [
            StateOfMindEntry(
                timestamp: Self.testDate,
                kind: .dailyMood,
                valence: 0.6,
                labels: ["Happy"],
                associations: ["Exercise"]
            )
        ]
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.moodSettings)
        let moodSamples = samples.filter { $0.metricId == "daily_mood" }
        XCTAssertEqual(moodSamples.count, 1)
        XCTAssertEqual(moodSamples.first?.value as? Double, 0.6)
        XCTAssertEqual(moodSamples.first?.additionalFields["valence"] as? Double, 0.6)
        XCTAssertEqual(moodSamples.first?.additionalFields["labels"] as? [String], ["Happy"])
    }

    func testExtractSamples_momentaryEmotions() {
        var data = HealthData(date: Self.testDate)
        data.mindfulness.stateOfMind = [
            StateOfMindEntry(
                timestamp: Self.testDate,
                kind: .momentaryEmotion,
                valence: -0.3,
                labels: ["Anxious"],
                associations: ["Work"]
            )
        ]
        let samples = exporter.extractIndividualSamples(from: data, settings: Self.momentarySettings)
        XCTAssertFalse(samples.isEmpty)
    }

    // MARK: - exportIndividualEntries: file writing

    func testExportEntries_writesFiles() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        let sample = IndividualHealthSample(
            metricId: "weight",
            metricName: "Weight",
            category: .bodyMeasurements,
            timestamp: Self.testDate,
            value: 72.5,
            unit: "kg"
        )

        let count = try exporter.exportIndividualEntries(
            samples: [sample],
            to: tmpDir,
            settings: Self.weightSettings,
            formatSettings: Self.formatSettings
        )

        XCTAssertEqual(count, 1)
    }

    func testExportEntries_skipsUntrackedMetrics() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        let sample = IndividualHealthSample(
            metricId: "weight",
            metricName: "Weight",
            category: .bodyMeasurements,
            timestamp: Self.testDate,
            value: 72.5,
            unit: "kg"
        )

        let count = try exporter.exportIndividualEntries(
            samples: [sample],
            to: tmpDir,
            settings: Self.emptySettings,
            formatSettings: Self.formatSettings
        )

        XCTAssertEqual(count, 0)
    }

    func testExportEntries_createsCategorySubfolders() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        let sample = IndividualHealthSample(
            metricId: "weight",
            metricName: "Weight",
            category: .bodyMeasurements,
            timestamp: Self.testDate,
            value: 72.5,
            unit: "kg"
        )

        _ = try exporter.exportIndividualEntries(
            samples: [sample],
            to: tmpDir,
            settings: Self.weightSettings,
            formatSettings: Self.formatSettings
        )

        let categoryFolder = tmpDir
            .appendingPathComponent("entries")
            .appendingPathComponent("body_measurements")
        XCTAssertTrue(FileManager.default.fileExists(atPath: categoryFolder.path))
    }

    func testExportEntries_fileContainsYAMLFrontmatter() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        let sample = IndividualHealthSample(
            metricId: "weight",
            metricName: "Weight",
            category: .bodyMeasurements,
            timestamp: Self.testDate,
            value: 72.5,
            unit: "kg",
            source: "Apple Watch"
        )

        _ = try exporter.exportIndividualEntries(
            samples: [sample],
            to: tmpDir,
            settings: Self.weightSettings,
            formatSettings: Self.formatSettings
        )

        let folderURL = tmpDir.appendingPathComponent(Self.weightSettings.folderPath(for: HealthMetricDefinition(
            id: "weight", name: "Weight", category: .bodyMeasurements,
            unit: "kg", healthKitIdentifier: nil, metricType: .quantity, aggregation: .mostRecent
        )))
        let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)

        let content = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("---"))
        XCTAssertTrue(content.contains("date: 2026-03-27"))
        XCTAssertTrue(content.contains("metric: weight"))
        XCTAssertTrue(content.contains("unit: kg"))
        XCTAssertTrue(content.contains("source: \"Apple Watch\""))
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd_iee_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
