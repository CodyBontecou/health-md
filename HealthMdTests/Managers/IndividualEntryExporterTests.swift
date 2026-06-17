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

    private static let heightSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("height", enabled: true)
        return s
    }()

    private static let walkingSpeedSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("walking_speed", enabled: true)
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

    private static let medicationsSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.setTrackIndividually("medications", enabled: true)
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

    func testExtractSamples_aggregateMetricsUseCanonicalExportUnits() {
        var heightData = HealthData(date: Self.testDate)
        heightData.body.height = 1.78
        let height = exporter.extractIndividualSamples(from: heightData, settings: Self.heightSettings).first { $0.metricId == "height" }
        XCTAssertEqual(height?.value as? String, "1.78")
        XCTAssertEqual(height?.unit, "m")
        let heightFieldUnits = height?.additionalFields["field_units"] as? [String: Any]
        XCTAssertEqual(heightFieldUnits?["height_m"] as? String, "m")

        var speedData = HealthData(date: Self.testDate)
        speedData.mobility.walkingSpeed = 1.4
        let walkingSpeed = exporter.extractIndividualSamples(from: speedData, settings: Self.walkingSpeedSettings).first { $0.metricId == "walking_speed" }
        XCTAssertEqual(walkingSpeed?.value as? String, "1.40")
        XCTAssertEqual(walkingSpeed?.unit, "m/s")
        let speedFieldUnits = walkingSpeed?.additionalFields["field_units"] as? [String: Any]
        XCTAssertEqual(speedFieldUnits?["walking_speed"] as? String, "m/s")
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
        XCTAssertNotNil(running.workout, "Workout samples should carry the rich workout payload for detailed notes")

        let yoga = workoutSamples[1]
        XCTAssertEqual(yoga.value as? String, "Yoga")
        XCTAssertNil(yoga.additionalFields["calories"])
        XCTAssertNil(yoga.additionalFields["distance_meters"])
    }

    func testPreviewWorkoutEntryContent_includesDetailedMarkdownAndHeartRateZones() {
        func sample(offset: TimeInterval, value: Double) -> TimeSeriesSample {
            TimeSeriesSample(timestamp: Self.testDate.addingTimeInterval(offset), value: value)
        }

        let series = WorkoutTimeSeries(
            heartRate: [sample(offset: 0, value: 100), sample(offset: 60, value: 130), sample(offset: 120, value: 150), sample(offset: 180, value: 170), sample(offset: 240, value: 190)],
            power: [sample(offset: 0, value: 100), sample(offset: 60, value: 110), sample(offset: 120, value: 120), sample(offset: 180, value: 130), sample(offset: 240, value: 140)],
            cadence: [sample(offset: 0, value: 80), sample(offset: 60, value: 82), sample(offset: 120, value: 84), sample(offset: 180, value: 86), sample(offset: 240, value: 88)]
        )
        let lap = WorkoutLap(
            startDate: Self.testDate,
            endDate: Self.testDate.addingTimeInterval(300),
            duration: 300,
            distanceMeters: 1000
        )
        let split = WorkoutSplit(
            index: 1,
            startDate: Self.testDate,
            duration: 300,
            distanceMeters: 1000,
            avgHeartRate: 150
        )

        var data = HealthData(date: Self.testDate)
        data.workouts = [
            WorkoutData(
                workoutType: .cycling,
                startTime: Self.testDate,
                isIndoor: false,
                metadata: ["Device": "Apple Watch"],
                duration: 300,
                calories: 50,
                distance: 1000,
                avgHeartRate: 150,
                maxHeartRate: 200,
                minHeartRate: 100,
                avgCyclingCadence: 84,
                avgPower: 120,
                maxPower: 140,
                elevationGainMeters: 12,
                laps: [lap],
                splits: [split],
                timeSeries: series
            )
        ]

        let workoutSample = exporter.extractIndividualSamples(from: data, settings: Self.workoutSettings).first!
        let content = exporter.previewEntryContent(for: workoutSample, formatSettings: Self.formatSettings)

        XCTAssertTrue(content.contains("type: workout"), "Workout note should use workout frontmatter: \(content)")
        XCTAssertTrue(content.contains("source: Health.md"), "Source frontmatter missing")
        XCTAssertTrue(content.contains("activity_type: \"Cycling\""), "Activity type missing")
        XCTAssertTrue(content.contains("duration_sec: 300"), "Duration frontmatter missing")
        XCTAssertTrue(content.contains("distance_km: 1.00"), "Distance frontmatter missing")
        XCTAssertTrue(content.contains("hr_avg: 150"), "Average HR frontmatter missing")
        XCTAssertTrue(content.contains("sample_counts:\n  heart_rate: 5"), "Sample counts frontmatter missing")
        XCTAssertTrue(content.contains("heart_rate_zones:"), "Zones frontmatter missing")
        XCTAssertTrue(content.contains("  zone5:"), "Zone 5 frontmatter missing")
        XCTAssertTrue(content.contains("laps:\n  - lap: 1"), "Structured lap frontmatter missing: \(content)")
        XCTAssertTrue(content.contains("splits:\n  - split: 1"), "Structured split frontmatter missing: \(content)")
        XCTAssertTrue(content.contains("    speed_kmh_formatted: \"12.0 km/h\""), "Interval km/h speed frontmatter missing")
        XCTAssertTrue(content.contains("    speed_mph_formatted: \"7.5 mph\""), "Interval mph speed frontmatter missing")
        XCTAssertTrue(content.contains("    hr_max: 190"), "Interval max HR frontmatter missing")
        XCTAssertTrue(content.contains("    power_avg_w: 120"), "Interval power frontmatter missing")
        XCTAssertTrue(content.contains("    cadence_avg_rpm: 84"), "Interval cadence frontmatter missing")
        XCTAssertTrue(content.contains("# Cycling — 2026-03-27"), "Workout title missing")
        XCTAssertTrue(content.contains("## Heart Rate Zones"), "Zone table missing")
        XCTAssertTrue(content.contains("| Zone 5 | Max | 180-200 bpm | 1:00 |"), "Zone row missing: \(content)")
        XCTAssertTrue(content.contains("## Laps"), "Laps section missing")
        XCTAssertTrue(content.contains("## Splits"), "Splits section missing")
        XCTAssertTrue(content.contains("| # | Distance | Time | Speed | Avg HR | Max HR | Avg Power | Avg Cadence |"), "Interval table header missing")
        XCTAssertTrue(content.contains("| 1 | 1.00 km | 5:00 | 12.0 km/h | 150 bpm | 190 bpm | 120 W | 84 rpm |"), "Interval detail row missing: \(content)")
        XCTAssertTrue(content.contains("| Power | 5 |"), "Sample count table missing")
    }

    func testPreviewWorkoutEntryContent_lowIntensityWorkoutDoesNotUseWorkoutMaxAsZoneMax() {
        func sample(offset: TimeInterval, value: Double) -> TimeSeriesSample {
            TimeSeriesSample(timestamp: Self.testDate.addingTimeInterval(offset), value: value)
        }

        var data = HealthData(date: Self.testDate)
        data.workouts = [
            WorkoutData(
                workoutType: .walking,
                startTime: Self.testDate,
                duration: 180,
                calories: 10,
                distance: 300,
                avgHeartRate: 90,
                maxHeartRate: 95,
                minHeartRate: 85,
                timeSeries: WorkoutTimeSeries(
                    heartRate: [
                        sample(offset: 0, value: 90),
                        sample(offset: 60, value: 92),
                        sample(offset: 120, value: 95)
                    ]
                )
            )
        ]

        let workoutSample = exporter.extractIndividualSamples(from: data, settings: Self.workoutSettings).first!
        let content = exporter.previewEntryContent(for: workoutSample, formatSettings: Self.formatSettings)

        XCTAssertTrue(content.contains("| Zone 1 | Recovery | 87-103 bpm | 3:00 |"), "Low-intensity HR should land in recovery, not max: \(content)")
        XCTAssertFalse(content.contains("Max 3:00"), "Workout max HR should not define Zone 5 for easy workouts: \(content)")
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

    // MARK: - extractIndividualSamples: medications

    func testExtractSamples_medicationDoseIncludesAllFetchedFields() {
        var data = HealthData(date: Self.testDate)
        let scheduledDate = Self.testDate.addingTimeInterval(-900)
        data.medications = MedicationsData(
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
                    medicationConceptIdentifier: "rxnorm:617314",
                    medicationName: "Thyroid",
                    startDate: Self.testDate,
                    endDate: Self.testDate.addingTimeInterval(60),
                    scheduledDate: scheduledDate,
                    doseQuantity: 2,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .taken,
                    scheduleType: .scheduled,
                    metadata: ["HKMetadataKeyWasUserEntered": "true"]
                )
            ]
        )

        let sample = exporter.extractIndividualSamples(from: data, settings: Self.medicationsSettings).first
        XCTAssertEqual(sample?.metricId, "medications")
        XCTAssertEqual(sample?.value as? Double, 2)
        XCTAssertEqual(sample?.additionalFields["event_id"] as? String, "00000000-0000-0000-0000-000000000601")
        XCTAssertEqual(sample?.additionalFields["medication_concept_identifier"] as? String, "rxnorm:617314")
        XCTAssertEqual(sample?.additionalFields["medication_name"] as? String, "Thyroid")
        XCTAssertEqual(sample?.additionalFields["status"] as? String, "taken")
        XCTAssertEqual(sample?.additionalFields["status_display"] as? String, "Taken")
        XCTAssertEqual(sample?.additionalFields["schedule_type"] as? String, "scheduled")
        XCTAssertEqual(sample?.additionalFields["dose_quantity"] as? Double, 2)
        XCTAssertEqual(sample?.additionalFields["scheduled_dose_quantity"] as? Double, 1)
        XCTAssertEqual(sample?.additionalFields["dose_unit"] as? String, "tablet")
        XCTAssertEqual((sample?.additionalFields["metadata"] as? [String: String])?["HKMetadataKeyWasUserEntered"], "true")
    }

    func testPreviewEntryContent_medicationDoseIncludesAllFetchedFields() {
        var data = HealthData(date: Self.testDate)
        data.medications = MedicationsData(
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000602")!,
                    medicationConceptIdentifier: "rxnorm:617314",
                    medicationName: "Thyroid",
                    startDate: Self.testDate,
                    endDate: Self.testDate.addingTimeInterval(60),
                    scheduledDate: Self.testDate,
                    doseQuantity: 1,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .taken,
                    scheduleType: .scheduled,
                    metadata: ["source": "Health"]
                )
            ]
        )

        let sample = exporter.extractIndividualSamples(from: data, settings: Self.medicationsSettings).first!
        let content = exporter.previewEntryContent(for: sample, formatSettings: Self.formatSettings)

        XCTAssertTrue(content.contains("event_id: 00000000-0000-0000-0000-000000000602"), content)
        XCTAssertTrue(content.contains("medication_concept_identifier: \"rxnorm:617314\""), content)
        XCTAssertTrue(content.contains("start_datetime:"), content)
        XCTAssertTrue(content.contains("end_datetime:"), content)
        XCTAssertTrue(content.contains("dose_quantity: 1"), content)
        XCTAssertTrue(content.contains("scheduled_dose_quantity: 1"), content)
        XCTAssertTrue(content.contains("metadata:\n  source: Health"), content)
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
