//
//  ExportFixtures.swift
//  HealthMdTests
//
//  Canonical fixture datasets for export contract/golden tests.
//  All fixtures use fixed dates and values for deterministic output.
//

import Foundation
@testable import HealthMd

/// Provides canonical HealthData fixtures for export testing.
enum ExportFixtures {
    /// Fixed reference date: 2026-03-15T00:00:00Z
    static let referenceDate: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
    }()

    static let timeContext = ExportTimeContext(calendarTimeZoneIdentifier: "UTC")

    // MARK: - Empty Day

    /// A day with no health data at all.
    static var emptyDay: HealthData {
        HealthData(date: referenceDate, timeContext: timeContext)
    }

    // MARK: - Partial Day

    /// A day with only sleep and activity data (common for basic Apple Watch users).
    static var partialDay: HealthData {
        var data = HealthData(date: referenceDate, timeContext: timeContext)
        data.sleep = SleepData(
            totalDuration: 7.5 * 3600,
            deepSleep: 1.5 * 3600,
            remSleep: 2.0 * 3600,
            coreSleep: 4.0 * 3600
        )
        data.activity = ActivityData(
            steps: 8500,
            activeCalories: 350.0,
            exerciseMinutes: 32.0,
            flightsClimbed: 5,
            walkingRunningDistance: 6200.0
        )
        return data
    }

    // MARK: - Fully Populated Day

    /// A day with all categories populated (power user / full health tracking).
    static var fullDay: HealthData {
        var data = HealthData(date: referenceDate, timeContext: timeContext)
        data.sleep = SleepData(
            totalDuration: 7.75 * 3600,
            deepSleep: 1.5 * 3600,
            remSleep: 2.25 * 3600,
            coreSleep: 4.0 * 3600,
            awakeTime: 0.25 * 3600,
            inBedTime: 8.0 * 3600
        )
        data.activity = ActivityData(
            steps: 12500,
            activeCalories: 520.0,
            exerciseMinutes: 45.0,
            flightsClimbed: 8,
            walkingRunningDistance: 9500.0,
            standTimeMinutes: 37.5,
            standHours: 11,
            basalEnergyBurned: 1650.0,
            cyclingDistance: 3200.0,
            vo2Max: 42.5
        )
        data.heart = HeartData(
            restingHeartRate: 58.0,
            walkingHeartRateAverage: 105.0,
            averageHeartRate: 72.0,
            hrv: 42.0,
            heartRateMin: 52.0,
            heartRateMax: 155.0
        )
        data.vitals = VitalsData(
            respiratoryRateAvg: 15.0,
            respiratoryRateMin: 12.0,
            respiratoryRateMax: 18.0,
            bloodOxygenAvg: 0.97,
            bloodOxygenMin: 0.94,
            bloodOxygenMax: 0.99,
            bloodPressureSystolicAvg: 121.0,
            bloodPressureSystolicMin: 118.0,
            bloodPressureSystolicMax: 124.0,
            bloodPressureDiastolicAvg: 79.0,
            bloodPressureDiastolicMin: 77.0,
            bloodPressureDiastolicMax: 81.0
        )
        data.body = BodyData(
            weight: 75.0,
            bodyFatPercentage: 0.18,
            height: 1.78,
            bmi: 23.7
        )
        data.nutrition = NutritionData(
            dietaryEnergy: 2100.0,
            protein: 120.0,
            carbohydrates: 250.0,
            fat: 70.0,
            fiber: 25.0,
            sugar: 45.0,
            water: 2.5,
            caffeine: 200.0
        )
        data.mindfulness = MindfulnessData(
            mindfulMinutes: 15.0,
            mindfulSessions: 2
        )
        data.mobility = MobilityData(
            walkingSpeed: 1.4,
            walkingStepLength: 0.72,
            walkingDoubleSupportPercentage: 0.28
        )
        data.hearing = HearingData(
            headphoneAudioLevel: 72.0,
            environmentalSoundLevel: 55.0
        )
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                healthKitActivityType: "running",
                healthKitActivityTypeRawValue: 37,
                startTime: referenceDate,
                duration: 1800,
                calories: 300,
                distance: 5000
            )
        ]
        let doseTime = Calendar(identifier: .gregorian).date(byAdding: .hour, value: 8, to: referenceDate)!
        data.medications = MedicationsData(
            medications: [
                Medication(
                    conceptIdentifier: "rxnorm:617314",
                    displayName: "Levothyroxine Sodium 50 MCG Oral Tablet",
                    nickname: "Thyroid",
                    generalForm: "tablet",
                    isArchived: false,
                    hasSchedule: true,
                    relatedCodings: [MedicationCoding(system: "http://www.nlm.nih.gov/research/umls/rxnorm", version: nil, code: "617314")]
                ),
                Medication(
                    conceptIdentifier: "custom:vitamin-d",
                    displayName: "Vitamin D",
                    nickname: nil,
                    generalForm: "capsule",
                    isArchived: true,
                    hasSchedule: false,
                    relatedCodings: []
                )
            ],
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
                    medicationConceptIdentifier: "rxnorm:617314",
                    medicationName: "Thyroid",
                    startDate: doseTime,
                    endDate: doseTime,
                    scheduledDate: doseTime,
                    doseQuantity: 1,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .taken,
                    scheduleType: .scheduled
                )
            ]
        )
        return data
    }

    // MARK: - Fully Populated Day with Granular Data

    /// Same as fullDay but with time-series sample arrays populated.
    static var fullDayGranular: HealthData {
        var data = fullDay

        // Heart rate samples spread across the day
        let cal = Calendar(identifier: .gregorian)
        let h6  = cal.date(byAdding: .hour, value: 6, to: referenceDate)!
        let h9  = cal.date(byAdding: .hour, value: 9, to: referenceDate)!
        let h12 = cal.date(byAdding: .hour, value: 12, to: referenceDate)!
        let h15 = cal.date(byAdding: .hour, value: 15, to: referenceDate)!
        let h20 = cal.date(byAdding: .hour, value: 20, to: referenceDate)!

        data.heart.heartRateSamples = [
            TimeSample(timestamp: h6,  value: 55.0),
            TimeSample(timestamp: h9,  value: 72.0),
            TimeSample(timestamp: h12, value: 85.0),
            TimeSample(timestamp: h15, value: 68.0),
            TimeSample(timestamp: h20, value: 60.0),
        ]
        data.heart.hrvSamples = [
            TimeSample(timestamp: h6,  value: 45.0),
            TimeSample(timestamp: h20, value: 38.0),
        ]

        // Sleep stage samples (night beginning on referenceDate)
        let bedtime = cal.date(byAdding: .hour, value: 22, to: referenceDate)! // 22:00 same day
        data.sleep.stages = [
            SleepStageSample(stage: "deep", startDate: bedtime, endDate: bedtime.addingTimeInterval(5400)),
            SleepStageSample(stage: "rem",  startDate: bedtime.addingTimeInterval(5400), endDate: bedtime.addingTimeInterval(12600)),
            SleepStageSample(stage: "core", startDate: bedtime.addingTimeInterval(12600), endDate: bedtime.addingTimeInterval(23400)),
            SleepStageSample(stage: "awake", startDate: bedtime.addingTimeInterval(23400), endDate: bedtime.addingTimeInterval(24300)),
        ]

        // Vitals samples
        data.vitals.bloodOxygenSamples = [
            TimeSample(timestamp: h6,  value: 0.96),
            TimeSample(timestamp: h12, value: 0.98),
            TimeSample(timestamp: h20, value: 0.97),
        ]
        data.vitals.bloodGlucoseSamples = [
            TimeSample(timestamp: h9,  value: 90.0),
            TimeSample(timestamp: h15, value: 110.0),
        ]
        data.vitals.respiratoryRateSamples = [
            TimeSample(timestamp: h6,  value: 14.0),
            TimeSample(timestamp: h12, value: 16.0),
        ]
        data.vitals.bloodPressureSamples = [
            BloodPressureSample(
                systolic: 124.0,
                diastolic: 81.0,
                startDate: h9,
                endDate: h9,
                metadata: ["HKWasUserEntered": "false"]
            ),
            BloodPressureSample(
                systolic: 118.0,
                diastolic: 77.0,
                startDate: h9.addingTimeInterval(120),
                endDate: h9.addingTimeInterval(120)
            ),
        ]

        return data
    }

    // MARK: - Lossless HealthKit Archive Day

    /// A fully populated summary with a canonical archive covering every payload and metadata shape.
    static var losslessDay: HealthData {
        var data = fullDay
        let intervalEnd = referenceDate.addingTimeInterval(86_400)
        let firstStart = referenceDate.addingTimeInterval(1.125)
        let firstEnd = referenceDate.addingTimeInterval(2.5)
        let firstUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let duplicateUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let categoryUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let correlationUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let structuredUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
        let binaryUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000006")!
        let unknownUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000007")!

        let source = HealthKitSourceRevision(
            name: "Fixture Health, Inc.",
            bundleIdentifier: "com.example.\"health\"",
            version: "19.0\nrelease",
            productType: "Watch7,5",
            operatingSystemVersion: HealthKitOperatingSystemVersion(
                majorVersion: 19,
                minorVersion: 1,
                patchVersion: 2
            )
        )
        let device = HealthKitDeviceProvenance(
            name: "Cody's Watch, \"Daily\"",
            manufacturer: "Apple, Inc.",
            model: "Watch\nUltra",
            hardwareVersion: "7,5",
            firmwareVersion: "12.0",
            softwareVersion: "12.0.1",
            localIdentifier: "local,watch",
            udiDeviceIdentifier: "udi-\"watch\""
        )
        let comprehensiveMetadata: [String: HealthKitMetadataValue] = [
            "null": .null,
            "string": .string("comma, quote \" and newline\nkept"),
            "bool": .bool(true),
            "signed": .signedInteger(.min),
            "unsigned": .unsignedInteger(.max),
            "floating": .floatingPoint(12.75),
            "date": .date(firstStart),
            "data": .data(Data([0x00, 0x7f, 0xff])),
            "url": .url(URL(string: "https://example.com/record?id=1,2")!),
            "quantity": .quantity(HealthKitMetadataQuantity(
                value: 120.25,
                unit: "mmHg",
                rawDescription: "120.25 mmHg"
            )),
            "array": .array([.signedInteger(-7), .null, .string("nested, value")]),
            "dictionary": .dictionary([
                "maximum": .unsignedInteger(.max),
                "nested": .dictionary(["flag": .bool(false)])
            ]),
            "unsupported": .unsupported(
                typeName: "HKFutureMetadata",
                description: "future, \"opaque\"\nvalue"
            )
        ]

        func quantityRecord(uuid: UUID) -> HealthKitRecord {
            HealthKitRecord(
                originalUUID: uuid,
                objectTypeIdentifier: "HKQuantityTypeIdentifierHeartRate",
                recordKind: .quantity,
                selectedMetricIDs: ["heart_rate_avg", "heart_rate_max"],
                includedBecause: .selectedMetric,
                startDate: firstStart,
                endDate: firstEnd,
                hasUndeterminedDuration: true,
                sourceRevision: source,
                device: device,
                metadata: comprehensiveMetadata,
                payload: .quantity(HealthKitQuantityPayload(
                    value: 71.25,
                    unit: "count/min",
                    sampleSubclass: "HKDiscreteQuantitySample",
                    sampleKind: "discrete",
                    count: 2,
                    minimum: HealthKitExactQuantity(value: 70.5, unit: "count/min"),
                    average: HealthKitExactQuantity(value: 71.25, unit: "count/min"),
                    maximum: HealthKitExactQuantity(value: 72.0, unit: "count/min"),
                    mostRecent: HealthKitExactQuantity(value: 72.0, unit: "count/min"),
                    mostRecentDateInterval: HealthKitQuantityDateInterval(
                        startDate: firstStart,
                        endDate: firstEnd
                    ),
                    sum: HealthKitExactQuantity(value: 142.5, unit: "count/min"),
                    series: [
                        HealthKitQuantitySeriesPoint(
                            quantity: HealthKitExactQuantity(value: 70.5, unit: "count/min"),
                            dateInterval: HealthKitQuantityDateInterval(
                                startDate: firstStart,
                                endDate: firstStart.addingTimeInterval(0.25)
                            ),
                            owningSampleUUID: uuid,
                            owningSampleTypeIdentifier: "HKQuantityTypeIdentifierHeartRate"
                        ),
                        HealthKitQuantitySeriesPoint(
                            quantity: HealthKitExactQuantity(value: 72.0, unit: "count/min"),
                            dateInterval: HealthKitQuantityDateInterval(
                                startDate: firstStart.addingTimeInterval(0.25),
                                endDate: firstEnd
                            ),
                            owningSampleUUID: uuid,
                            owningSampleTypeIdentifier: "HKQuantityTypeIdentifierHeartRate"
                        ),
                    ]
                )),
                relationships: [
                    HealthKitRecordRelationship(
                        targetUUID: categoryUUID,
                        role: "component",
                        kind: "correlation_component",
                        targetOwnerDate: "2026-03-15"
                    ),
                    HealthKitRecordRelationship(
                        targetExternalIdentifier: "rxnorm:617314",
                        role: "medication",
                        kind: "annotation",
                        targetOwnerDate: "2026-03-15"
                    )
                ]
            )
        }

        let records: [HealthKitRecord] = [
            quantityRecord(uuid: duplicateUUID),
            HealthKitRecord(
                originalUUID: categoryUUID,
                objectTypeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
                recordKind: .category,
                selectedMetricIDs: ["sleep"],
                includedBecause: .relationshipDependency,
                startDate: referenceDate.addingTimeInterval(10.25),
                endDate: referenceDate.addingTimeInterval(20.5),
                sourceRevision: source,
                payload: .category(HealthKitCategoryPayload(rawValue: .min, symbolicValue: "futureSleepValue"))
            ),
            HealthKitRecord(
                originalUUID: correlationUUID,
                objectTypeIdentifier: "HKCorrelationTypeIdentifierBloodPressure",
                recordKind: .correlation,
                selectedMetricIDs: ["blood_pressure"],
                includedBecause: .selectedMetric,
                startDate: referenceDate.addingTimeInterval(30.125),
                endDate: referenceDate.addingTimeInterval(30.25),
                sourceRevision: source,
                payload: .correlation(componentUUIDs: [duplicateUUID, firstUUID])
            ),
            HealthKitRecord(
                originalUUID: structuredUUID,
                objectTypeIdentifier: "HKWorkoutTypeIdentifier",
                recordKind: .workout,
                selectedMetricIDs: ["workouts"],
                includedBecause: .selectedMetric,
                startDate: referenceDate.addingTimeInterval(40.5),
                endDate: referenceDate.addingTimeInterval(100.75),
                sourceRevision: source,
                payload: .structured(kind: "future_workout", fields: [
                    "activity_type": .unsignedInteger(.max),
                    "indoor": .bool(false)
                ])
            ),
            HealthKitRecord(
                originalUUID: binaryUUID,
                objectTypeIdentifier: "HKElectrocardiogramTypeIdentifier",
                recordKind: .electrocardiogram,
                selectedMetricIDs: ["electrocardiogram"],
                includedBecause: .selectedMetric,
                startDate: referenceDate.addingTimeInterval(110.125),
                endDate: referenceDate.addingTimeInterval(120.875),
                sourceRevision: source,
                payload: .binaryArtifactReference(HealthKitBinaryArtifactReference(
                    identifier: "artifacts/ecg,\"1\".dat",
                    mediaType: "application/octet-stream",
                    filename: "ecg\n1.dat",
                    byteCount: .max,
                    sha256: "0123456789abcdef"
                ))
            ),
            HealthKitRecord(
                originalUUID: unknownUUID,
                objectTypeIdentifier: "HKFutureTypeIdentifier",
                recordKind: .other("future_record_kind"),
                selectedMetricIDs: ["future_metric"],
                includedBecause: .other("future_reason"),
                startDate: referenceDate.addingTimeInterval(130.625),
                endDate: referenceDate.addingTimeInterval(131.875),
                sourceRevision: source,
                payload: .unknown(kind: "HKFuturePayload", fields: [
                    "exact": .unsignedInteger(.max),
                    "opaque": .string("comma, quote \" and newline\nkept")
                ])
            ),
            quantityRecord(uuid: firstUUID)
        ]

        let interval = HealthKitQueryInterval(startDate: referenceDate, endDate: intervalEnd)
        let archive = HealthKitRecordArchive(
            captureStatus: .partial,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-15",
                intervalStart: referenceDate,
                intervalEnd: intervalEnd,
                calendarTimeZoneIdentifier: "UTC"
            ),
            records: records,
            externalRecords: [HealthKitExternalRecord(
                externalIdentifier: "healthkit.attachment|20000000-0000-0000-0000-000000000001",
                externalIdentityKind: .attachmentIdentifier,
                objectTypeIdentifier: "HKAttachment",
                recordKind: .attachment,
                selectedMetricIDs: ["heart_rate_avg"],
                metricAttribution: HealthKitMetricAttribution(
                    directMetricIDs: ["heart_rate_avg"]
                ),
                fields: [
                    "identifier": .string("20000000-0000-0000-0000-000000000001"),
                    "filename": .string("source, record.bin"),
                    "uniformTypeIdentifier": .string("application/octet-stream"),
                    "byteCount": .signedInteger(3),
                    "creationDate": .date(firstStart),
                    "metadata": .dictionary(comprehensiveMetadata),
                    "parentObjectTypeIdentifiers": .array([
                        .string("HKQuantityTypeIdentifierHeartRate")
                    ]),
                    "bytesAvailable": .bool(true),
                    "data": .data(Data([0x00, 0x7f, 0xff])),
                    "sha256": .string("0123456789abcdef")
                ],
                relationships: [HealthKitRecordRelationship(
                    targetUUID: firstUUID,
                    role: "parent",
                    kind: "attachment"
                )]
            )],
            queryManifest: HealthKitQueryManifest(results: [
                HealthKitQueryResult(
                    identifier: "success-empty",
                    objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
                    operation: "sample_query",
                    metricIDs: ["steps"],
                    interval: interval,
                    status: .success,
                    recordCount: 0,
                    statusDescription: "No matching samples"
                ),
                HealthKitQueryResult(
                    identifier: "failed-heart-rate",
                    objectTypeIdentifier: "HKQuantityTypeIdentifierHeartRate",
                    operation: "sample_query",
                    metricIDs: ["heart_rate_avg"],
                    interval: interval,
                    status: .failure,
                    recordCount: 0,
                    error: HealthKitQueryError(
                        domain: "HKErrorDomain,Fixture",
                        code: .min,
                        description: "Denied, \"temporarily\"\nretry later",
                        isRecoverable: true
                    )
                )
            ]),
            integrityWarnings: [HealthKitRecordIntegrityWarning(
                code: "fixture_warning",
                message: "Duplicate-looking records, intentionally retained\nwith provenance",
                metricIDs: ["heart_rate_avg"],
                recordUUIDs: [duplicateUUID, firstUUID]
            )],
            medicationInventoryRecords: [HealthKitMedicationInventoryRecord(
                externalIdentifier: "rxnorm:617314",
                objectTypeIdentifier: "HKDataTypeUserAnnotatedMedicationConcept",
                selectedMetricIDs: ["medications"],
                includedBecause: .relationshipDependency,
                displayName: "Levothyroxine, \"Thyroid\"",
                fields: [
                    "maximum_refills": .unsignedInteger(.max),
                    "instructions": .string("Take one\nwith water")
                ]
            )]
        )

        data.healthKitRecordArchive = archive
        data.healthKitRecordCaptureStatus = .complete // The archive remains authoritative (`partial`).
        data.partialFailures = [ExportPartialFailure(
            date: referenceDate.addingTimeInterval(200.125),
            dataType: "vitals, secondary",
            dateRangeDescription: "2026-03-15 \"UTC\"",
            errorDescription: "Some values failed\nwithout hiding summaries"
        )]
        return data
    }

    // MARK: - Edge Case Day

    /// A day with edge cases: negative valence, sparse vitals, nil optionals.
    static var edgeCaseDay: HealthData {
        var data = HealthData(date: referenceDate, timeContext: timeContext)
        data.sleep = SleepData(
            totalDuration: 0, // no sleep recorded
            deepSleep: 0,
            remSleep: 0,
            coreSleep: 0
        )
        data.activity = ActivityData(
            steps: 0 // zero steps
        )
        data.heart = HeartData(
            restingHeartRate: nil,
            averageHeartRate: 0 // edge: zero HR
        )
        data.mindfulness = MindfulnessData(
            mindfulMinutes: nil,
            mindfulSessions: nil,
            stateOfMind: [
                StateOfMindEntry(
                    timestamp: referenceDate,
                    kind: .dailyMood,
                    valence: -0.8, // very unpleasant
                    labels: ["Anxious", "Stressed"],
                    associations: ["Work"]
                )
            ]
        )
        data.vitals = VitalsData(
            respiratoryRateAvg: nil,
            bloodOxygenAvg: nil,
            bodyTemperatureAvg: 36.5 // only temp recorded
        )
        return data
    }
}
