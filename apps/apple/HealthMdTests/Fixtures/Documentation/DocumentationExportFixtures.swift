import Foundation
@testable import HealthMd

/// Fixed, synthetic source values used only to generate export reference documentation.
/// Every date, UUID, value, and collection order is deterministic.
enum DocumentationExportFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_773_532_800) // 2026-03-15T00:00:00Z
    static let timeContext = ExportTimeContext(calendarTimeZoneIdentifier: "UTC")

    static let recordKindNames = [
        "quantity", "category", "correlation", "workout", "workout_route",
        "heartbeat_series", "activity_summary", "characteristic", "clinical",
        "verifiable_clinical_record", "audiogram", "electrocardiogram",
        "vision_prescription", "state_of_mind", "medication_dose_event",
        "scored_assessment", "document", "attachment", "fixture_future_kind",
    ]

    static let payloadCaseNames = [
        "quantity", "category", "correlation", "structured",
        "binary_artifact_reference", "unknown",
    ]

    static var exhaustiveSummaryDay: HealthData {
        var data = ExportFixtures.fullDayGranular

        data.sleep.sessionStart = date(21_600)
        data.sleep.sessionEnd = date(49_500)
        data.sleep.stages = [
            SleepStageSample(
                stage: "deep",
                startDate: date(21_600),
                endDate: date(25_200),
                metadata: ["source": "synthetic sleep stage"]
            ),
            SleepStageSample(stage: "rem", startDate: date(25_200), endDate: date(28_800)),
            SleepStageSample(stage: "core", startDate: date(28_800), endDate: date(32_400)),
            SleepStageSample(stage: "awake", startDate: date(32_400), endDate: date(32_700)),
            SleepStageSample(stage: "inBed", startDate: date(21_600), endDate: date(49_500)),
            SleepStageSample(stage: "unspecified", startDate: date(32_700), endDate: date(33_000)),
        ]

        data.activity.swimmingDistance = 750
        data.activity.swimmingStrokes = 420
        data.activity.pushCount = 88
        data.activity.vo2MaxSourceUUID = uuid(700)
        data.activity.vo2MaxSourceStartDate = date(-86_400)
        data.activity.vo2MaxSourceEndDate = date(-86_340)
        data.activity.vo2MaxCarriedForward = true
        data.activity.vo2MaxAgeSeconds = 86_400
        data.activity.wheelchairDistance = 1_250
        data.activity.downhillSnowSportsDistance = 2_300
        data.activity.moveTime = 61
        data.activity.physicalEffort = 4.75

        data.heart.heartRateRecovery = 24
        data.heart.atrialFibrillationBurden = 0.0125
        data.heart.heartRateSamples = [
            TimeSample(timestamp: date(1_800), value: 61, metadata: ["motion": "stationary"]),
            TimeSample(timestamp: date(3_600), value: 92),
        ]
        data.heart.hrvSamples = [
            TimeSample(timestamp: date(1_900), value: 43, metadata: ["algorithm": "SDNN"]),
        ]

        data.vitals = VitalsData(
            respiratoryRateAvg: 15.2,
            respiratoryRateMin: 11.8,
            respiratoryRateMax: 19.4,
            bloodOxygenAvg: 0.975,
            bloodOxygenMin: 0.94,
            bloodOxygenMax: 0.99,
            bodyTemperatureAvg: 36.7,
            bodyTemperatureMin: 36.3,
            bodyTemperatureMax: 37.1,
            bloodPressureSystolicAvg: 121,
            bloodPressureSystolicMin: 116,
            bloodPressureSystolicMax: 127,
            bloodPressureDiastolicAvg: 79,
            bloodPressureDiastolicMin: 74,
            bloodPressureDiastolicMax: 84,
            bloodGlucoseAvg: 102,
            bloodGlucoseMin: 82,
            bloodGlucoseMax: 138,
            bloodOxygenSamples: [TimeSample(timestamp: date(2_000), value: 0.97, metadata: ["context": "rest"])],
            bloodGlucoseSamples: [TimeSample(timestamp: date(3_000), value: 102, metadata: ["meal": "breakfast"])],
            respiratoryRateSamples: [TimeSample(timestamp: date(4_000), value: 15.2, metadata: ["position": "supine"])],
            bloodPressureSamples: [BloodPressureSample(
                correlationUUID: uuid(701),
                systolic: 121,
                diastolic: 79,
                startDate: date(5_000),
                endDate: date(5_030),
                sourceRevision: sourceRevision,
                device: device,
                metadata: ["HKWasUserEntered": "true"]
            )],
            basalBodyTemperature: 36.55,
            wristTemperature: 36.45,
            electrodermalActivity: 1.75,
            forcedVitalCapacity: 4.8,
            forcedExpiratoryVolume1: 3.9,
            peakExpiratoryFlowRate: 510,
            inhalerUsage: 2
        )

        data.body.leanBodyMass = 61.5
        data.body.waistCircumference = 0.84
        data.nutrition.sodium = 2_100
        data.nutrition.cholesterol = 180
        data.nutrition.saturatedFat = 20
        data.nutrition.monounsaturatedFat = 24
        data.nutrition.polyunsaturatedFat = 15

        data.mindfulness = MindfulnessData(
            mindfulMinutes: 18,
            mindfulSessions: 3,
            stateOfMind: [
                StateOfMindEntry(
                    id: uuid(710),
                    timestamp: date(28_800),
                    endDate: date(28_860),
                    kind: .dailyMood,
                    valence: 0.65,
                    labels: ["Content", "Calm"],
                    associations: ["Family"],
                    sourceRevision: sourceRevision,
                    device: device,
                    metadata: ["note": "morning check-in"]
                ),
                StateOfMindEntry(
                    id: uuid(711),
                    timestamp: date(50_400),
                    endDate: date(50_430),
                    kind: .momentaryEmotion,
                    valence: -0.25,
                    labels: ["Worried"],
                    associations: ["Work"]
                ),
                StateOfMindEntry(
                    id: uuid(712),
                    timestamp: date(68_400),
                    kind: .unknown,
                    valence: 0,
                    labels: ["Neutral"],
                    associations: []
                ),
            ]
        )

        data.mobility = MobilityData(
            walkingSpeed: 1.42,
            walkingStepLength: 0.73,
            walkingDoubleSupportPercentage: 0.27,
            walkingAsymmetryPercentage: 0.015,
            stairAscentSpeed: 0.62,
            stairDescentSpeed: 0.71,
            sixMinuteWalkDistance: 590,
            walkingSteadiness: 0.92,
            runningSpeed: 3.4,
            runningStrideLength: 1.15,
            runningGroundContactTime: 245,
            runningVerticalOscillation: 8.4,
            runningPower: 278
        )
        data.hearing = HearingData(headphoneAudioLevel: 71.5, environmentalSoundLevel: 54.2)
        data.reproductiveHealth = ReproductiveHealthData(
            menstrualFlow: "medium",
            sexualActivityCount: 1,
            ovulationTestResult: "positive",
            cervicalMucusQuality: "egg_white",
            intermenstrualBleedingCount: 1
        )
        data.cyclingPerformance = CyclingPerformanceData(
            cyclingSpeed: 8.2,
            cyclingPower: 215,
            cyclingCadence: 88,
            cyclingFTP: 260
        )
        data.vitamins = VitaminsData(
            vitaminA: 800, vitaminB6: 1.7, vitaminB12: 2.4, vitaminC: 95,
            vitaminD: 20, vitaminE: 15, vitaminK: 120, thiamin: 1.2,
            riboflavin: 1.3, niacin: 16, folate: 400, biotin: 30,
            pantothenicAcid: 5
        )
        data.minerals = MineralsData(
            calcium: 1_000, iron: 18, potassium: 3_400, magnesium: 420,
            phosphorus: 700, zinc: 11, selenium: 55, copper: 0.9,
            manganese: 2.3, chromium: 35, molybdenum: 45, chloride: 2_300,
            iodine: 150
        )
        data.symptoms = SymptomsData(
            counts: Dictionary(uniqueKeysWithValues: HealthMetrics.symptoms.enumerated().map {
                ($0.element.id, $0.offset + 1)
            }),
            samples: [SymptomSample(
                metricId: "symptom_headache",
                startDate: date(40_000),
                endDate: date(40_600),
                rawValue: 2,
                symbolicValue: "moderate",
                source: "Fixture Health",
                metadata: ["trigger": "screen time"],
                originalUUID: uuid(720)
            )]
        )
        data.medications = medications
        data.other = OtherHealthData(
            uvExposure: 4,
            timeInDaylight: 92,
            numberOfFalls: 1,
            bloodAlcoholContent: 0.001,
            alcoholicBeverages: 1,
            insulinDelivery: 3.5,
            toothbrushingCount: 2,
            handwashingCount: 8,
            waterTemperature: 19.5,
            underwaterDepth: 4.2
        )
        data.workouts = workouts
        data.healthKitRecordCaptureStatus = .notRequested
        return data
    }

    static var exhaustiveLosslessDay: HealthData {
        var data = exhaustiveSummaryDay
        data.healthKitRecordArchive = canonicalArchive
        data.partialFailures = [
            ExportPartialFailure(
                date: date(80_000.125),
                dataType: "attachment bytes",
                dateRangeDescription: "2026-03-15 UTC",
                errorDescription: "One attachment remained unavailable"
            ),
            ExportPartialFailure(
                date: date(81_000.5),
                dataType: "workout route",
                dateRangeDescription: "2026-03-15 UTC",
                errorDescription: "A route query returned partial locations"
            ),
        ]
        return data
    }

    static var canonicalArchive: HealthKitRecordArchive {
        let interval = HealthKitQueryInterval(
            startDate: referenceDate,
            endDate: date(86_400),
            calendarTimeZoneIdentifier: "UTC"
        )
        return HealthKitRecordArchive(
            captureStatus: .partial,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-15",
                intervalStart: referenceDate,
                intervalEnd: date(86_400),
                calendarTimeZoneIdentifier: "UTC"
            ),
            records: canonicalRecords,
            externalRecords: externalRecords,
            queryManifest: HealthKitQueryManifest(results: [
                query("01-success-records", status: .success, recordCount: canonicalRecords.count, interval: interval),
                query("02-success-empty", status: .success, recordCount: 0, interval: interval, description: "No matching samples"),
                query("03-failure", status: .failure, recordCount: 0, interval: interval, error: HealthKitQueryError(
                    domain: "HKErrorDomain",
                    code: 5,
                    description: "Authorization or source data error",
                    isRecoverable: true
                )),
                query("04-unsupported", status: .unsupported, recordCount: 0, interval: interval, description: "API unavailable on this runtime"),
                query("05-skipped", status: .skipped, recordCount: 0, interval: interval, description: "Separate authorization was not requested"),
                query("06-cancelled", status: .cancelled, recordCount: 0, interval: interval, error: HealthKitQueryError(
                    domain: "NSCocoaErrorDomain",
                    code: 3072,
                    description: "The user cancelled the selection",
                    isRecoverable: false
                )),
            ]),
            integrityWarnings: [
                HealthKitRecordIntegrityWarning(
                    code: "cross_day_relationship",
                    message: "A relationship target belongs to another owner date",
                    metricIDs: ["workouts"],
                    recordUUIDs: [uuid(1), uuid(2)]
                ),
                HealthKitRecordIntegrityWarning(
                    code: "partial_binary_availability",
                    message: "One binary reference has metadata but no inline bytes",
                    metricIDs: ["electrocardiograms"],
                    recordUUIDs: [uuid(5)]
                ),
            ],
            medicationInventoryRecords: [
                HealthKitMedicationInventoryRecord(
                    externalIdentifier: "rxnorm:617314",
                    objectTypeIdentifier: "HKDataTypeUserAnnotatedMedicationConcept",
                    selectedMetricIDs: ["medications"],
                    displayName: "Levothyroxine 50 mcg",
                    fields: [
                        "archived": .bool(false),
                        "form": .string("tablet"),
                        "refills": .unsignedInteger(3),
                    ]
                ),
                HealthKitMedicationInventoryRecord(
                    externalIdentifier: "custom:vitamin-d",
                    selectedMetricIDs: ["medications"],
                    includedBecause: .relationshipDependency,
                    displayName: "Vitamin D",
                    fields: ["archived": .bool(true)]
                ),
            ]
        )
    }

    static var canonicalRecords: [HealthKitRecord] {
        let kinds: [(HealthKitRecordKind, String)] = [
            (.quantity, "HKQuantityTypeIdentifierHeartRate"),
            (.category, "HKCategoryTypeIdentifierSleepAnalysis"),
            (.correlation, "HKCorrelationTypeIdentifierBloodPressure"),
            (.workout, "HKWorkoutTypeIdentifier"),
            (.workoutRoute, "HKWorkoutRouteTypeIdentifier"),
            (.heartbeatSeries, "HKDataTypeIdentifierHeartbeatSeries"),
            (.activitySummary, "HKActivitySummaryTypeIdentifier"),
            (.characteristic, "HKCharacteristicTypeIdentifierBiologicalSex"),
            (.clinical, "HKClinicalTypeIdentifierLabResultRecord"),
            (.verifiableClinicalRecord, "HKVerifiableClinicalRecordTypeIdentifier"),
            (.audiogram, "HKDataTypeIdentifierAudiogram"),
            (.electrocardiogram, "HKDataTypeIdentifierElectrocardiogram"),
            (.visionPrescription, "HKVisionPrescriptionTypeIdentifier"),
            (.stateOfMind, "HKDataTypeStateOfMind"),
            (.medicationDoseEvent, "HKMedicationDoseEventTypeIdentifierMedicationDoseEvent"),
            (.scoredAssessment, "HKScoredAssessmentTypeIdentifierGAD7"),
            (.document, "HKDocumentTypeIdentifierCDA"),
            (.attachment, "HKAttachment"),
            (.other("fixture_future_kind"), "HKFixtureFutureTypeIdentifier"),
        ]

        var records = kinds.enumerated().map { offset, element in
            let index = offset + 1
            let recordUUID = uuid(index)
            let payload: HealthKitRecordPayload
            switch index {
            case 1:
                payload = .quantity(HealthKitQuantityPayload(
                    value: 72.25,
                    unit: "count/min",
                    sampleSubclass: "HKDiscreteQuantitySample",
                    sampleKind: "discrete",
                    count: 2,
                    minimum: HealthKitExactQuantity(value: 68, unit: "count/min"),
                    average: HealthKitExactQuantity(value: 72.25, unit: "count/min"),
                    maximum: HealthKitExactQuantity(value: 77, unit: "count/min"),
                    mostRecent: HealthKitExactQuantity(value: 77, unit: "count/min"),
                    mostRecentDateInterval: HealthKitQuantityDateInterval(startDate: date(100), endDate: date(101)),
                    sum: HealthKitExactQuantity(value: 144.5, unit: "count/min"),
                    series: [HealthKitQuantitySeriesPoint(
                        quantity: HealthKitExactQuantity(value: 72.25, unit: "count/min"),
                        dateInterval: HealthKitQuantityDateInterval(startDate: date(100), endDate: date(100.5)),
                        owningSampleUUID: recordUUID,
                        owningSampleTypeIdentifier: element.1
                    )]
                ))
            case 2:
                payload = .category(HealthKitCategoryPayload(rawValue: 3, symbolicValue: "asleepDeep"))
            case 3:
                payload = .correlation(componentUUIDs: [uuid(1), uuid(2)])
            case 18:
                payload = .binaryArtifactReference(HealthKitBinaryArtifactReference(
                    identifier: "attachments/fixture-001.bin",
                    mediaType: "application/octet-stream",
                    filename: "fixture-001.bin",
                    byteCount: 3,
                    sha256: "ae4b3280e56e2faf83f414a6e3dabe9d5fbe18976544c05fed121accb85b53fc"
                ))
            case 19:
                payload = .unknown(kind: "fixture_future_payload", fields: [
                    "opaque": .string("preserved future payload"),
                    "revision": .signedInteger(1),
                ])
            default:
                payload = .structured(
                    kind: element.0.rawValue,
                    fields: specializedFields(identifier: element.1, index: index)
                )
            }

            let attribution = canonicalAttribution(identifier: element.1)
            return HealthKitRecord(
                originalUUID: recordUUID,
                objectTypeIdentifier: element.1,
                recordKind: element.0,
                selectedMetricIDs: attribution.metricIDs,
                includedBecause: attribution.directMetricIDs.isEmpty ? .relationshipDependency : .selectedMetric,
                metricAttribution: attribution,
                startDate: date(Double(index * 100) + 0.125),
                endDate: date(Double(index * 100) + 30.75),
                hasUndeterminedDuration: index == 14,
                sourceRevision: sourceRevision,
                device: device,
                metadata: index == 1 ? comprehensiveMetadata : ["fixture_index": .signedInteger(Int64(index))],
                payload: payload,
                relationships: index == 1 ? [
                    HealthKitRecordRelationship(
                        targetUUID: uuid(2),
                        role: "component",
                        kind: "uuid_relationship",
                        targetOwnerDate: "2026-03-14"
                    ),
                    HealthKitRecordRelationship(
                        targetExternalIdentifier: "attachment:fixture-001",
                        role: "attachment",
                        kind: "external_relationship",
                        targetOwnerDate: "2026-03-15"
                    ),
                ] : []
            )
        }
        records.append(HealthKitRecord(
            originalUUID: uuid(20),
            objectTypeIdentifier: "HKScoredAssessmentTypeIdentifierPHQ9",
            recordKind: .scoredAssessment,
            selectedMetricIDs: ["phq9_assessments"],
            includedBecause: .selectedMetric,
            metricAttribution: HealthKitMetricAttribution(directMetricIDs: ["phq9_assessments"]),
            startDate: date(2_000.125),
            endDate: date(2_030.75),
            sourceRevision: sourceRevision,
            device: device,
            metadata: ["fixture_index": .signedInteger(20)],
            payload: .structured(kind: "phq9_assessment", fields: [
                "answers": .array([.signedInteger(1), .signedInteger(0), .signedInteger(2)]),
                "risk": .string("minimal"),
                "score": .signedInteger(3),
            ])
        ))
        return records
    }

    private static func canonicalAttribution(identifier: String) -> HealthKitMetricAttribution {
        let directMetricID: String
        switch identifier {
        case "HKQuantityTypeIdentifierHeartRate": directMetricID = "heart_rate_avg"
        case "HKCategoryTypeIdentifierSleepAnalysis": directMetricID = "sleep_total"
        case "HKCorrelationTypeIdentifierBloodPressure": directMetricID = "blood_pressure_systolic"
        case "HKWorkoutTypeIdentifier": directMetricID = "workouts"
        case "HKWorkoutRouteTypeIdentifier":
            return HealthKitMetricAttribution(dependencyMetricIDs: ["workouts"])
        case "HKDataTypeIdentifierHeartbeatSeries": directMetricID = "heartbeat_series"
        case "HKActivitySummaryTypeIdentifier": directMetricID = "activity_summary"
        case "HKCharacteristicTypeIdentifierBiologicalSex": directMetricID = "biological_sex"
        case "HKClinicalTypeIdentifierLabResultRecord": directMetricID = "clinical_lab_result_records"
        case "HKVerifiableClinicalRecordTypeIdentifier": directMetricID = "verifiable_clinical_records"
        case "HKDataTypeIdentifierAudiogram": directMetricID = "audiograms"
        case "HKDataTypeIdentifierElectrocardiogram": directMetricID = "electrocardiograms"
        case "HKVisionPrescriptionTypeIdentifier": directMetricID = "vision_prescriptions"
        case "HKDataTypeStateOfMind": directMetricID = "state_of_mind_entries"
        case "HKMedicationDoseEventTypeIdentifierMedicationDoseEvent": directMetricID = "medications"
        case "HKScoredAssessmentTypeIdentifierGAD7": directMetricID = "gad7_assessments"
        case "HKDocumentTypeIdentifierCDA": directMetricID = "cda_documents"
        case "HKAttachment":
            return HealthKitMetricAttribution(dependencyMetricIDs: ["heart_rate_avg"])
        default: directMetricID = "fixture_future_metric"
        }
        return HealthKitMetricAttribution(directMetricIDs: [directMetricID])
    }

    private static func specializedFields(identifier: String, index: Int) -> [String: HealthKitMetadataValue] {
        switch identifier {
        case "HKWorkoutTypeIdentifier":
            return ["activity_type": .unsignedInteger(37), "duration_seconds": .floatingPoint(3_600), "indoor": .bool(false)]
        case "HKWorkoutRouteTypeIdentifier":
            return ["locations": .array([.dictionary(["latitude": .floatingPoint(21.3069), "longitude": .floatingPoint(-157.8583), "timestamp": .date(date(500))])])]
        case "HKDataTypeIdentifierHeartbeatSeries":
            return ["measurements": .array([.dictionary(["preceded_by_gap": .bool(false), "time_since_series_start": .floatingPoint(0.42)])])]
        case "HKActivitySummaryTypeIdentifier":
            return ["active_energy_burned": .floatingPoint(520), "exercise_time": .floatingPoint(45), "stand_hours": .signedInteger(11)]
        case "HKCharacteristicTypeIdentifierBiologicalSex":
            return ["raw_value": .signedInteger(2), "symbolic_value": .string("female")]
        case "HKClinicalTypeIdentifierLabResultRecord":
            return ["fhir_resource": .data(Data("{\"resourceType\":\"Observation\"}".utf8)), "stable_content_identity": .string("fhir:Observation:fixture-001")]
        case "HKVerifiableClinicalRecordTypeIdentifier":
            return ["issuer_identifier": .string("https://issuer.example.invalid"), "record_data": .data(Data("fixture verifiable record".utf8))]
        case "HKDataTypeIdentifierAudiogram":
            return ["sensitivity_points": .array([.dictionary(["frequency_hz": .floatingPoint(1_000), "left_db_hl": .floatingPoint(10), "right_db_hl": .floatingPoint(12)])])]
        case "HKDataTypeIdentifierElectrocardiogram":
            return ["average_heart_rate": .floatingPoint(72), "classification": .string("sinus_rhythm"), "voltage_measurements": .array([.floatingPoint(0.12), .floatingPoint(0.18)])]
        case "HKVisionPrescriptionTypeIdentifier":
            return ["expiration_date": .date(date(31_536_000)), "prescription_type": .string("glasses"), "right_eye_sphere": .floatingPoint(-1.25)]
        case "HKDataTypeStateOfMind":
            return ["associations": .array([.string("work")]), "kind": .string("momentary_emotion"), "labels": .array([.string("calm")]), "valence": .floatingPoint(0.4)]
        case "HKMedicationDoseEventTypeIdentifierMedicationDoseEvent":
            return ["dose_quantity": .floatingPoint(1), "log_status": .string("taken"), "medication_identifier": .string("rxnorm:617314"), "unit": .string("tablet")]
        case "HKScoredAssessmentTypeIdentifierGAD7":
            return ["answers": .array([.signedInteger(0), .signedInteger(1), .signedInteger(0)]), "risk": .string("minimal"), "score": .signedInteger(1)]
        case "HKDocumentTypeIdentifierCDA":
            return ["author_name": .string("Fixture Clinic"), "document_data": .data(Data("<ClinicalDocument/>".utf8)), "title": .string("Fixture CDA")]
        default:
            return ["fixture_index": .signedInteger(Int64(index)), "public_value": .string("Synthetic public record example")]
        }
    }

    static var comprehensiveMetadata: [String: HealthKitMetadataValue] {
        [
            "array": .array([.string("first"), .signedInteger(-2), .null]),
            "bool": .bool(true),
            "data": .data(Data([0x00, 0x7f, 0xff])),
            "date": .date(date(100.125)),
            "dictionary": .dictionary([
                "nested": .dictionary(["enabled": .bool(false)]),
                "unsigned": .unsignedInteger(UInt64.max),
            ]),
            "floating_point": .floatingPoint(12.75),
            "null": .null,
            "quantity": .quantity(HealthKitMetadataQuantity(
                value: 120.25,
                unit: "mmHg",
                rawDescription: "120.25 mmHg"
            )),
            "signed_integer": .signedInteger(Int64.min),
            "string": .string("comma, quote \" and newline\nare preserved"),
            "unsigned_integer": .unsignedInteger(UInt64.max),
            "unsupported": .unsupported(
                typeName: "HKFixtureUnsupportedValue",
                description: "Opaque public value retained as text"
            ),
            "url": .url(URL(string: "https://example.invalid/health?id=1,2")!),
        ]
    }

    static var externalRecords: [HealthKitExternalRecord] {
        [
            HealthKitExternalRecord(
                externalIdentifier: "activity-summary:2026-03-15",
                externalIdentityKind: .activitySummaryDateComponents,
                objectTypeIdentifier: "HKActivitySummary",
                recordKind: .activitySummary,
                selectedMetricIDs: ["activity_summary"],
                fields: ["active_energy": .floatingPoint(520), "date": .string("2026-03-15")]
            ),
            HealthKitExternalRecord(
                externalIdentifier: "characteristic:biological-sex",
                externalIdentityKind: .characteristicSingleton,
                objectTypeIdentifier: "HKCharacteristicTypeIdentifierBiologicalSex",
                recordKind: .characteristic,
                selectedMetricIDs: ["biological_sex"],
                fields: ["value": .string("female")]
            ),
            HealthKitExternalRecord(
                externalIdentifier: "attachment:fixture-001",
                externalIdentityKind: .attachmentIdentifier,
                objectTypeIdentifier: "HKAttachment",
                recordKind: .attachment,
                selectedMetricIDs: ["heart_rate_avg"],
                metricAttribution: HealthKitMetricAttribution(
                    directMetricIDs: ["heart_rate_avg"],
                    dependencyMetricIDs: ["workouts"]
                ),
                fields: [
                    "bytes_available": .bool(true),
                    "data": .data(Data([0x00, 0x7f, 0xff])),
                    "filename": .string("fixture-record.bin"),
                    "sha256": .string("ae4b3280e56e2faf83f414a6e3dabe9d5fbe18976544c05fed121accb85b53fc"),
                ],
                relationships: [HealthKitRecordRelationship(
                    targetUUID: uuid(1), role: "parent", kind: "attachment_parent"
                )]
            ),
            HealthKitExternalRecord(
                externalIdentifier: "workoutkit:schedule-001",
                externalIdentityKind: .other("workoutkit_schedule_identity"),
                objectTypeIdentifier: "WorkoutKit.WorkoutPlan",
                recordKind: .other("scheduled_workout_plan"),
                selectedMetricIDs: ["scheduled_workout_plans"],
                fields: ["representation": .data(Data("fixture workout plan".utf8))]
            ),
        ]
    }

    private static let sourceRevision = HealthKitSourceRevision(
        name: "Fixture Health",
        bundleIdentifier: "com.example.fixture-health",
        version: "6.0",
        productType: "WatchFixture1,1",
        operatingSystemVersion: HealthKitOperatingSystemVersion(
            majorVersion: 26,
            minorVersion: 0,
            patchVersion: 1
        )
    )

    private static let device = HealthKitDeviceProvenance(
        name: "Fixture Watch",
        manufacturer: "Example Manufacturer",
        model: "Synthetic Model",
        hardwareVersion: "1.0",
        firmwareVersion: "2.0",
        softwareVersion: "26.0.1",
        localIdentifier: "fixture-local-device",
        udiDeviceIdentifier: "fixture-udi-device"
    )

    private static var medications: MedicationsData {
        MedicationsData(
            medications: [
                Medication(
                    conceptIdentifier: "rxnorm:617314",
                    displayName: "Levothyroxine Sodium 50 MCG Oral Tablet",
                    nickname: "Thyroid",
                    generalForm: "tablet",
                    isArchived: false,
                    hasSchedule: true,
                    relatedCodings: [MedicationCoding(
                        system: "http://www.nlm.nih.gov/research/umls/rxnorm",
                        version: "2026AA",
                        code: "617314"
                    )]
                ),
                Medication(
                    conceptIdentifier: "custom:vitamin-d",
                    displayName: "Vitamin D",
                    nickname: nil,
                    generalForm: "capsule",
                    isArchived: true,
                    hasSchedule: false,
                    relatedCodings: []
                ),
            ],
            doseEvents: [
                MedicationDoseEvent(
                    id: uuid(730),
                    medicationConceptIdentifier: "rxnorm:617314",
                    medicationName: "Thyroid",
                    startDate: date(28_800),
                    endDate: date(28_830),
                    scheduledDate: date(28_800),
                    doseQuantity: 1,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .taken,
                    scheduleType: .scheduled,
                    metadata: ["with_food": "false"]
                ),
                MedicationDoseEvent(
                    id: uuid(731),
                    medicationConceptIdentifier: "custom:vitamin-d",
                    medicationName: nil,
                    startDate: date(64_800),
                    endDate: date(64_800),
                    scheduledDate: nil,
                    doseQuantity: 2,
                    scheduledDoseQuantity: nil,
                    unit: "capsule",
                    logStatus: .skipped,
                    scheduleType: .asNeeded,
                    metadata: ["reason": "not available"]
                ),
            ]
        )
    }

    private static var workouts: [WorkoutData] {
        let running = WorkoutData(
            id: uuid(740),
            sourceUUID: uuid(740),
            workoutType: .running,
            healthKitActivityType: "running",
            healthKitActivityTypeRawValue: 37,
            startTime: date(36_000),
            actualEndDate: date(39_900),
            sourceRevision: sourceRevision,
            device: device,
            isIndoor: false,
            metadata: ["weather": "clear"],
            duration: 3_600,
            calories: 540,
            distance: 10_000,
            avgHeartRate: 148,
            maxHeartRate: 172,
            minHeartRate: 92,
            avgRunningCadence: 176,
            avgStrideLength: 1.18,
            avgGroundContactTime: 238,
            avgVerticalOscillation: 8.1,
            avgCyclingCadence: 84,
            avgPower: 286,
            maxPower: 430,
            elevationGainMeters: 125,
            elevationLossMeters: 118,
            laps: [WorkoutLap(
                startDate: date(36_000),
                endDate: date(37_800),
                duration: 1_800,
                distanceMeters: 5_000
            )],
            splits: [WorkoutSplit(
                index: 1,
                startDate: date(36_000),
                duration: 360,
                distanceMeters: 1_000,
                avgHeartRate: 142
            )],
            route: [RoutePoint(
                timestamp: date(36_000),
                latitude: 21.3069,
                longitude: -157.8583,
                altitudeMeters: 12,
                speedMps: 3.2,
                courseDegrees: 92,
                horizontalAccuracyMeters: 4.5
            )],
            timeSeries: WorkoutTimeSeries(
                heartRate: [TimeSeriesSample(timestamp: date(36_000), value: 142, metadata: ["source": "watch"])],
                speed: [TimeSeriesSample(timestamp: date(36_001), value: 3.1)],
                power: [TimeSeriesSample(timestamp: date(36_002), value: 286)],
                cadence: [TimeSeriesSample(timestamp: date(36_003), value: 176)],
                strideLength: [TimeSeriesSample(timestamp: date(36_004), value: 1.18)],
                groundContactTime: [TimeSeriesSample(timestamp: date(36_005), value: 238)],
                verticalOscillation: [TimeSeriesSample(timestamp: date(36_006), value: 8.1)],
                altitude: [TimeSeriesSample(timestamp: date(36_007), value: 12)]
            )
        )
        let swimming = WorkoutData(
            id: uuid(741),
            sourceUUID: uuid(741),
            workoutType: .swimming,
            healthKitActivityType: "swimming",
            healthKitActivityTypeRawValue: 46,
            startTime: date(50_000),
            actualEndDate: date(51_800),
            isIndoor: true,
            duration: 1_800,
            calories: 280,
            distance: 1_500
        )
        let cycling = WorkoutData(
            id: uuid(742),
            sourceUUID: uuid(742),
            workoutType: .cycling,
            healthKitActivityType: "cycling",
            healthKitActivityTypeRawValue: 13,
            startTime: date(60_000),
            duration: 2_700,
            calories: 410,
            distance: 20_000,
            avgHeartRate: 136,
            maxHeartRate: 158,
            minHeartRate: 88,
            avgCyclingCadence: 86,
            avgPower: 220,
            maxPower: 415
        )
        return [running, swimming, cycling]
    }

    private static func query(
        _ identifier: String,
        status: HealthKitQueryResultStatus,
        recordCount: Int,
        interval: HealthKitQueryInterval,
        description: String? = nil,
        error: HealthKitQueryError? = nil
    ) -> HealthKitQueryResult {
        HealthKitQueryResult(
            identifier: identifier,
            objectTypeIdentifier: "HKFixtureTypeIdentifier",
            operation: "fixture_query",
            metricIDs: ["heart_rate_avg", "workouts"],
            metricAttribution: HealthKitMetricAttribution(
                directMetricIDs: ["heart_rate_avg"],
                dependencyMetricIDs: ["workouts"]
            ),
            interval: interval,
            status: status,
            recordCount: recordCount,
            error: error,
            statusDescription: description
        )
    }

    private static func date(_ offset: TimeInterval) -> Date {
        referenceDate.addingTimeInterval(offset)
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
