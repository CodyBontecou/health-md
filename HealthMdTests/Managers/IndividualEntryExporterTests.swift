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

    private static let canonicalSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        for metricID in [
            "weight", "blood_glucose", "symptom_headache", "menstrual_flow",
            "mindful_sessions", "heart_rate_avg"
        ] {
            s.setTrackIndividually(metricID, enabled: true)
        }
        return s
    }()

    private static let allCanonicalSettings: IndividualTrackingSettings = {
        let s = IndividualTrackingSettings()
        s.globalEnabled = true
        s.enableAll()
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
        XCTAssertEqual(glucoseSamples.first?.additionalFields["entry_kind"] as? String, "daily_aggregate")
    }

    func testExtractSamples_bloodGlucoseUsesCompatibilitySamplesWhenArchiveIsAbsent() {
        let readingDate = Self.testDate.addingTimeInterval(47.25)
        var data = HealthData(date: Self.testDate, healthKitRecordCaptureStatus: .legacyUnavailable)
        data.vitals.bloodGlucoseAvg = 95
        data.vitals.bloodGlucoseSamples = [
            TimeSample(timestamp: readingDate, value: 112.5, metadata: ["source": "Legacy CGM"])
        ]

        let samples = exporter.extractIndividualSamples(from: data, settings: Self.bloodGlucoseSettings)
        let glucose = samples.filter { $0.metricId == "blood_glucose" }

        XCTAssertEqual(glucose.count, 1)
        XCTAssertEqual(glucose.first?.timestamp, readingDate)
        XCTAssertEqual(glucose.first?.value as? Double, 112.5)
        XCTAssertEqual(glucose.first?.source, "Legacy CGM")
        XCTAssertEqual(glucose.first?.additionalFields["entry_kind"] as? String, "granular_compatibility")
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

    func testExtractSamples_bloodPressure_usesTimestampedReadingsWhenAvailable() {
        let secondReading = Self.testDate.addingTimeInterval(120)
        var data = HealthData(date: Calendar.current.startOfDay(for: Self.testDate))
        data.vitals.bloodPressureSystolicAvg = 121.0
        data.vitals.bloodPressureDiastolicAvg = 79.0
        data.vitals.bloodPressureSamples = [
            BloodPressureSample(
                systolic: 124,
                diastolic: 81,
                startDate: Self.testDate,
                endDate: Self.testDate,
                metadata: ["source_mode": "triple"]
            ),
            BloodPressureSample(
                systolic: 118,
                diastolic: 77,
                startDate: secondReading,
                endDate: secondReading
            )
        ]

        let samples = exporter.extractIndividualSamples(from: data, settings: Self.bpSettings)
        let bpSamples = samples.filter { $0.metricId == "blood_pressure" }

        XCTAssertEqual(bpSamples.count, 2)
        XCTAssertEqual(bpSamples[0].timestamp, Self.testDate)
        XCTAssertEqual(bpSamples[0].value as? String, "124/81")
        XCTAssertEqual(bpSamples[1].timestamp, secondReading)
        XCTAssertEqual((bpSamples[0].additionalFields["metadata"] as? [String: String])?["source_mode"], "triple")
        XCTAssertFalse(samples.contains { $0.metricId == "blood_pressure_systolic" })
        XCTAssertFalse(samples.contains { $0.metricId == "blood_pressure_diastolic" })
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
                healthKitActivityType: "cycling",
                healthKitActivityTypeRawValue: 13,
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
        XCTAssertTrue(content.contains("sport: cycling"), "Sport missing")
        XCTAssertTrue(content.contains("healthkit_activity_type: cycling"), "HealthKit type missing")
        XCTAssertTrue(content.contains("healthkit_activity_type_raw_value: 13"), "HealthKit raw value missing")
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

    func testPreviewEntryContent_medicationMetadataEscapesControlCharacters() {
        var data = HealthData(date: Self.testDate)
        let syncIdentifier = "medication\u{001F}|0\u{001F}|urn:apple:health:ontology\u{001F}|1082238120_803412000.000000"
        data.medications = MedicationsData(
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000603")!,
                    medicationConceptIdentifier: "rxnorm:310964",
                    medicationName: "Ibuprofen",
                    startDate: Self.testDate,
                    endDate: Self.testDate,
                    scheduledDate: Self.testDate,
                    doseQuantity: 2,
                    scheduledDoseQuantity: 2,
                    unit: "count",
                    logStatus: .taken,
                    scheduleType: .scheduled,
                    metadata: ["HKMetadataKeySyncIdentifier": syncIdentifier]
                )
            ]
        )

        let sample = exporter.extractIndividualSamples(from: data, settings: Self.medicationsSettings).first!
        let content = exporter.previewEntryContent(for: sample, formatSettings: Self.formatSettings)

        XCTAssertFalse(content.contains("\u{001F}"), "Individual medication notes should escape invisible HealthKit metadata separators")
        XCTAssertTrue(content.contains(#"HKMetadataKeySyncIdentifier: "medication\u001F|0\u001F|urn:apple:health:ontology\u001F|1082238120_803412000.000000""#), content)
    }

    // MARK: - Canonical archive records

    func testCanonicalRecordsDriveWeightGlucoseSymptomReproductiveMindfulAndHeartEntries() throws {
        let starts: [String: Date] = [
            "weight": Self.testDate.addingTimeInterval(1.125),
            "blood_glucose": Self.testDate.addingTimeInterval(2.25),
            "symptom_headache": Self.testDate.addingTimeInterval(3.375),
            "menstrual_flow": Self.testDate.addingTimeInterval(4.5),
            "mindful_sessions": Self.testDate.addingTimeInterval(5.625),
            "heart_rate_avg": Self.testDate.addingTimeInterval(6.75)
        ]
        let specs: [(String, String, HealthKitRecordKind, HealthKitRecordPayload)] = [
            ("weight", "HKQuantityTypeIdentifierBodyMass", .quantity, .quantity(.init(value: 72.375, unit: "kg"))),
            ("blood_glucose", "HKQuantityTypeIdentifierBloodGlucose", .quantity, .quantity(.init(value: 104.25, unit: "mg/dL"))),
            ("symptom_headache", "HKCategoryTypeIdentifierHeadache", .category, .category(.init(rawValue: 2, symbolicValue: "moderate"))),
            ("menstrual_flow", "HKCategoryTypeIdentifierMenstrualFlow", .category, .category(.init(rawValue: 3, symbolicValue: "heavy"))),
            ("mindful_sessions", "HKCategoryTypeIdentifierMindfulSession", .category, .category(.init(rawValue: 0, symbolicValue: "mindful_session"))),
            ("heart_rate_avg", "HKQuantityTypeIdentifierHeartRate", .quantity, .quantity(.init(value: 68.125, unit: "count/min")))
        ]
        let records = specs.enumerated().map { index, spec in
            canonicalRecord(
                uuid: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", index + 1))!,
                metricID: spec.0,
                objectTypeIdentifier: spec.1,
                kind: spec.2,
                payload: spec.3,
                start: starts[spec.0]!
            )
        }
        let data = healthDataWithArchive(records: records)

        let samples = exporter.extractIndividualSamples(from: data, settings: Self.canonicalSettings)

        XCTAssertEqual(samples.count, specs.count)
        for record in records {
            let sample = try XCTUnwrap(samples.first { $0.originalUUID == record.originalUUID })
            XCTAssertEqual(sample.timestamp, record.startDate)
            XCTAssertEqual(sample.additionalFields["original_uuid"] as? String, record.originalUUID.uuidString)
            XCTAssertEqual(sample.additionalFields["entry_kind"] as? String, "healthkit_record")
            XCTAssertEqual(sample.additionalFields["end_datetime"] as? String, CanonicalRFC3339UTC.string(from: record.endDate))
        }

        let symptom = try XCTUnwrap(samples.first { $0.metricId == "symptom_headache" })
        XCTAssertEqual(symptom.value as? String, "moderate")
        XCTAssertEqual(symptom.additionalFields["category_raw_value"] as? Int64, 2)
        let content = exporter.previewEntryContent(for: symptom, formatSettings: Self.formatSettings)
        XCTAssertTrue(content.contains("original_uuid: 20000000-0000-0000-0000-000000000003"), content)
        XCTAssertTrue(content.contains("datetime: \(CanonicalRFC3339UTC.string(from: starts["symptom_headache"]!))"), content)
        XCTAssertTrue(content.contains("source_revision_json:"), content)
        XCTAssertTrue(content.contains("device_json:"), content)
        XCTAssertTrue(content.contains("metadata_json:"), content)
        XCTAssertTrue(content.contains("payload_json:"), content)
        XCTAssertTrue(content.contains("relationships_json:"), content)
        XCTAssertTrue(content.contains("com.example.health"), content)
        XCTAssertTrue(content.contains("Watch Ultra"), content)
        XCTAssertTrue(content.contains("user_entered"), content)
    }

    func testCanonicalGenericQuantityAndCategoryRecordsSupportEveryMappedMetricID() {
        let definitions = HealthMetrics.all.filter {
            switch $0.metricType {
            case .quantity, .category: return true
            case .workout: return false
            }
        }
        let records = definitions.enumerated().map { index, definition in
            let isCategory: Bool
            switch definition.metricType {
            case .category: isCategory = true
            case .quantity, .workout: isCategory = false
            }
            return canonicalRecord(
                uuid: UUID(uuidString: String(format: "25000000-0000-0000-0000-%012d", index + 1))!,
                metricID: definition.id,
                objectTypeIdentifier: definition.healthKitIdentifier ?? "fixture:\(definition.id)",
                kind: isCategory ? .category : .quantity,
                payload: isCategory
                    ? .category(.init(rawValue: Int64(index), symbolicValue: "fixture"))
                    : .quantity(.init(value: Double(index) + 0.5, unit: definition.unit)),
                start: Self.testDate.addingTimeInterval(Double(index))
            )
        }

        let samples = exporter.extractIndividualSamples(
            from: healthDataWithArchive(records: records),
            settings: Self.allCanonicalSettings
        )

        XCTAssertEqual(Set(samples.map(\.metricId)), Set(definitions.map(\.id)))
        XCTAssertEqual(samples.count, definitions.count)
        XCTAssertTrue(samples.allSatisfy { $0.originalUUID != nil })
    }

    func testCanonicalSameMinuteUUIDsUseDistinctStableFilesAndRerunIsIdempotent() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }
        let first = canonicalRecord(
            uuid: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            metricID: "weight",
            objectTypeIdentifier: "HKQuantityTypeIdentifierBodyMass",
            kind: .quantity,
            payload: .quantity(.init(value: 70, unit: "kg")),
            start: Self.testDate
        )
        let second = canonicalRecord(
            uuid: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            metricID: "weight",
            objectTypeIdentifier: "HKQuantityTypeIdentifierBodyMass",
            kind: .quantity,
            payload: .quantity(.init(value: 71, unit: "kg")),
            start: Self.testDate.addingTimeInterval(20)
        )
        let samples = exporter.extractIndividualSamples(
            from: healthDataWithArchive(records: [second, first]),
            settings: Self.weightSettings
        )

        XCTAssertEqual(try exporter.exportIndividualEntries(
            samples: samples,
            to: tmpDir,
            settings: Self.weightSettings,
            formatSettings: Self.formatSettings
        ), 2)
        let folder = tmpDir.appendingPathComponent("entries/body_measurements")
        let firstNames = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

        XCTAssertEqual(firstNames.count, 2)
        XCTAssertTrue(firstNames.contains { $0.contains(first.originalUUID.uuidString.lowercased()) })
        XCTAssertTrue(firstNames.contains { $0.contains(second.originalUUID.uuidString.lowercased()) })

        XCTAssertEqual(try exporter.exportIndividualEntries(
            samples: samples,
            to: tmpDir,
            settings: Self.weightSettings,
            formatSettings: Self.formatSettings
        ), 2)
        let rerunNames = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(rerunNames, firstNames)
    }

    func testSymptomCompatibilityDetailsUseGranularTimingAndSeverityWithoutArchive() throws {
        let uuid = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let start = Self.testDate.addingTimeInterval(91.125)
        let end = start.addingTimeInterval(300)
        var data = HealthData(date: Self.testDate, healthKitRecordCaptureStatus: .legacyUnavailable)
        data.symptoms = SymptomsData(
            counts: ["symptom_headache": 1],
            samples: [SymptomSample(
                metricId: "symptom_headache",
                startDate: start,
                endDate: end,
                rawValue: 2,
                symbolicValue: "moderate",
                source: "Legacy Health",
                metadata: ["timing": "ongoing"],
                originalUUID: uuid
            )]
        )

        let sample = try XCTUnwrap(exporter.extractIndividualSamples(
            from: data,
            settings: Self.canonicalSettings
        ).first { $0.metricId == "symptom_headache" })

        XCTAssertEqual(sample.timestamp, start)
        XCTAssertEqual(sample.originalUUID, uuid)
        XCTAssertEqual(sample.value as? String, "moderate")
        XCTAssertEqual(sample.additionalFields["category_raw_value"] as? Int64, 2)
        XCTAssertEqual(sample.additionalFields["end_datetime"] as? String, CanonicalRFC3339UTC.string(from: end))
        XCTAssertEqual(sample.additionalFields["entry_kind"] as? String, "granular_compatibility")
        XCTAssertEqual((sample.additionalFields["metadata"] as? [String: String])?["timing"], "ongoing")
    }

    func testRequestedCaptureWithoutArchiveDoesNotEmitAggregateFallback() {
        var requested = HealthData(date: Self.testDate, healthKitRecordCaptureStatus: .partial)
        requested.body.weight = 72.5
        XCTAssertTrue(exporter.extractIndividualSamples(from: requested, settings: Self.weightSettings).isEmpty)

        var legacy = HealthData(date: Self.testDate, healthKitRecordCaptureStatus: .legacyUnavailable)
        legacy.body.weight = 72.5
        legacy.symptoms.counts["symptom_headache"] = 2
        let samples = exporter.extractIndividualSamples(from: legacy, settings: Self.canonicalSettings)
        let weight = samples.first { $0.metricId == "weight" }
        let symptom = samples.first { $0.metricId == "symptom_headache" }
        XCTAssertEqual(weight?.additionalFields["entry_kind"] as? String, "daily_aggregate")
        XCTAssertEqual(symptom?.additionalFields["entry_kind"] as? String, "daily_aggregate")
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

    func testExportEntries_preservesBloodPressureReadingsWithinSameMinute() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        let samples = [
            IndividualHealthSample(
                metricId: "blood_pressure",
                metricName: "Blood Pressure",
                category: .vitals,
                timestamp: Self.testDate,
                value: "124/81",
                unit: "mmHg"
            ),
            IndividualHealthSample(
                metricId: "blood_pressure",
                metricName: "Blood Pressure",
                category: .vitals,
                timestamp: Self.testDate.addingTimeInterval(20),
                value: "121/79",
                unit: "mmHg"
            )
        ]

        let count = try exporter.exportIndividualEntries(
            samples: samples,
            to: tmpDir,
            settings: Self.bpSettings,
            formatSettings: Self.formatSettings
        )

        let folder = tmpDir.appendingPathComponent("entries/vitals")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }

        XCTAssertEqual(count, 2)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(contents.contains { $0.contains(#"value: "124/81""#) })
        XCTAssertTrue(contents.contains { $0.contains(#"value: "121/79""#) })
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

    private func canonicalRecord(
        uuid: UUID,
        metricID: String,
        objectTypeIdentifier: String,
        kind: HealthKitRecordKind,
        payload: HealthKitRecordPayload,
        start: Date
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: kind,
            selectedMetricIDs: [metricID],
            includedBecause: .selectedMetric,
            metricAttribution: HealthKitMetricAttribution(directMetricIDs: [metricID]),
            startDate: start,
            endDate: start.addingTimeInterval(33.125),
            sourceRevision: HealthKitSourceRevision(
                name: "Fixture Watch",
                bundleIdentifier: "com.example.health",
                version: "1.2.3",
                productType: "Watch7,5"
            ),
            device: HealthKitDeviceProvenance(name: "Watch Ultra", manufacturer: "Apple"),
            metadata: ["user_entered": .bool(true)],
            payload: payload,
            relationships: [HealthKitRecordRelationship(
                targetExternalIdentifier: "fixture:relationship",
                role: "context",
                kind: "test"
            )]
        )
    }

    private func healthDataWithArchive(records: [HealthKitRecord]) -> HealthData {
        let dayStart = Calendar.current.startOfDay(for: Self.testDate)
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-27",
                intervalStart: dayStart,
                intervalEnd: dayStart.addingTimeInterval(86_400),
                calendarTimeZoneIdentifier: TimeZone.current.identifier
            ),
            records: records
        )
        return HealthData(date: dayStart, healthKitRecordArchive: archive)
    }

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
