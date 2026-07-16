import Foundation

/// Common public HKSample fields captured before a specialized HealthKit object
/// leaves the adapter. These portable values also make waveform/series mappers
/// testable without private HealthKit constructors.
struct HealthKitSpecializedSampleEnvelope: Codable, Equatable, Sendable {
    let originalUUID: UUID
    let objectTypeIdentifier: String
    let recordKind: HealthKitRecordKind
    let startDate: Date
    let endDate: Date
    let hasUndeterminedDuration: Bool
    let sourceRevision: HealthKitSourceRevision
    let device: HealthKitDeviceProvenance?
    let metadata: [String: HealthKitMetadataValue]

    init(
        originalUUID: UUID,
        objectTypeIdentifier: String,
        recordKind: HealthKitRecordKind,
        startDate: Date,
        endDate: Date,
        hasUndeterminedDuration: Bool = false,
        sourceRevision: HealthKitSourceRevision,
        device: HealthKitDeviceProvenance? = nil,
        metadata: [String: HealthKitMetadataValue] = [:]
    ) {
        self.originalUUID = originalUUID
        self.objectTypeIdentifier = objectTypeIdentifier
        self.recordKind = recordKind
        self.startDate = startDate
        self.endDate = endDate
        self.hasUndeterminedDuration = hasUndeterminedDuration
        self.sourceRevision = sourceRevision
        self.device = device
        self.metadata = metadata
    }
}

struct HealthKitExactQuantityValue: Codable, Equatable, Sendable {
    let value: Double
    let unit: String
    let rawDescription: String

    init(value: Double, unit: String, rawDescription: String) {
        self.value = value
        self.unit = unit
        self.rawDescription = rawDescription
    }

    var metadataValue: HealthKitMetadataValue {
        .quantity(HealthKitMetadataQuantity(
            value: value,
            unit: unit,
            rawDescription: rawDescription
        ))
    }
}

struct HealthKitElectrocardiogramVoltageValue: Codable, Equatable, Sendable {
    let timeSinceSampleStart: TimeInterval
    let leadRawValue: Int64
    let leadSymbolicValue: String?
    let volts: Double?

    init(
        timeSinceSampleStart: TimeInterval,
        leadRawValue: Int64,
        leadSymbolicValue: String?,
        volts: Double?
    ) {
        self.timeSinceSampleStart = timeSinceSampleStart
        self.leadRawValue = leadRawValue
        self.leadSymbolicValue = leadSymbolicValue
        self.volts = volts
    }
}

struct HealthKitElectrocardiogramRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    let numberOfVoltageMeasurements: Int64
    let samplingFrequency: HealthKitExactQuantityValue?
    let classificationRawValue: Int64
    let classificationSymbolicValue: String?
    let averageHeartRate: HealthKitExactQuantityValue?
    let symptomsStatusRawValue: Int64
    let symptomsStatusSymbolicValue: String?
    /// Nil means enumeration failed. An empty array means it completed with no measurements.
    let voltageMeasurements: [HealthKitElectrocardiogramVoltageValue]?
    let enumeratedMeasurementCount: Int64?

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        numberOfVoltageMeasurements: Int64,
        samplingFrequency: HealthKitExactQuantityValue?,
        classificationRawValue: Int64,
        classificationSymbolicValue: String?,
        averageHeartRate: HealthKitExactQuantityValue?,
        symptomsStatusRawValue: Int64,
        symptomsStatusSymbolicValue: String?,
        voltageMeasurements: [HealthKitElectrocardiogramVoltageValue]?,
        enumeratedMeasurementCount: Int64?
    ) {
        self.envelope = envelope
        self.numberOfVoltageMeasurements = numberOfVoltageMeasurements
        self.samplingFrequency = samplingFrequency
        self.classificationRawValue = classificationRawValue
        self.classificationSymbolicValue = classificationSymbolicValue
        self.averageHeartRate = averageHeartRate
        self.symptomsStatusRawValue = symptomsStatusRawValue
        self.symptomsStatusSymbolicValue = symptomsStatusSymbolicValue
        self.voltageMeasurements = voltageMeasurements
        self.enumeratedMeasurementCount = enumeratedMeasurementCount
    }
}

struct HealthKitAudiogramSensitivityTestValue: Codable, Equatable, Sendable {
    let sensitivityDBHL: Double
    let sideRawValue: Int64
    let sideSymbolicValue: String?
    /// Nil on runtimes whose public audiogram API exposed only left/right values.
    let conductionTypeRawValue: Int64?
    let conductionTypeSymbolicValue: String?
    let masked: Bool?
    let lowerClampingBoundDBHL: Double?
    let upperClampingBoundDBHL: Double?

    init(
        sensitivityDBHL: Double,
        sideRawValue: Int64,
        sideSymbolicValue: String?,
        conductionTypeRawValue: Int64? = nil,
        conductionTypeSymbolicValue: String? = nil,
        masked: Bool? = nil,
        lowerClampingBoundDBHL: Double? = nil,
        upperClampingBoundDBHL: Double? = nil
    ) {
        self.sensitivityDBHL = sensitivityDBHL
        self.sideRawValue = sideRawValue
        self.sideSymbolicValue = sideSymbolicValue
        self.conductionTypeRawValue = conductionTypeRawValue
        self.conductionTypeSymbolicValue = conductionTypeSymbolicValue
        self.masked = masked
        self.lowerClampingBoundDBHL = lowerClampingBoundDBHL
        self.upperClampingBoundDBHL = upperClampingBoundDBHL
    }
}

struct HealthKitAudiogramSensitivityPointValue: Codable, Equatable, Sendable {
    let frequencyHertz: Double
    let tests: [HealthKitAudiogramSensitivityTestValue]

    init(frequencyHertz: Double, tests: [HealthKitAudiogramSensitivityTestValue]) {
        self.frequencyHertz = frequencyHertz
        self.tests = tests
    }
}

struct HealthKitAudiogramRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    /// HealthKit defines this as an ordered collection. The mapper never re-sorts it.
    let sensitivityPoints: [HealthKitAudiogramSensitivityPointValue]

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        sensitivityPoints: [HealthKitAudiogramSensitivityPointValue]
    ) {
        self.envelope = envelope
        self.sensitivityPoints = sensitivityPoints
    }
}

struct HealthKitHeartbeatValue: Codable, Equatable, Sendable {
    let timeIntervalSinceSeriesStart: TimeInterval
    let precededByGap: Bool

    init(timeIntervalSinceSeriesStart: TimeInterval, precededByGap: Bool) {
        self.timeIntervalSinceSeriesStart = timeIntervalSinceSeriesStart
        self.precededByGap = precededByGap
    }
}

struct HealthKitHeartbeatSeriesRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    let count: UInt64
    /// Nil means the child series query failed; empty means successful and empty.
    let heartbeats: [HealthKitHeartbeatValue]?

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        count: UInt64,
        heartbeats: [HealthKitHeartbeatValue]?
    ) {
        self.envelope = envelope
        self.count = count
        self.heartbeats = heartbeats
    }
}

struct HealthKitScoredAssessmentAnswerValue: Codable, Equatable, Sendable {
    let questionIndex: Int64
    let rawValue: Int64
    let symbolicValue: String?

    init(questionIndex: Int64, rawValue: Int64, symbolicValue: String?) {
        self.questionIndex = questionIndex
        self.rawValue = rawValue
        self.symbolicValue = symbolicValue
    }
}

struct HealthKitScoredAssessmentRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    let assessmentKind: String
    let score: Int64
    let riskRawValue: Int64
    let riskSymbolicValue: String?
    let answers: [HealthKitScoredAssessmentAnswerValue]

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        assessmentKind: String,
        score: Int64,
        riskRawValue: Int64,
        riskSymbolicValue: String?,
        answers: [HealthKitScoredAssessmentAnswerValue]
    ) {
        self.envelope = envelope
        self.assessmentKind = assessmentKind
        self.score = score
        self.riskRawValue = riskRawValue
        self.riskSymbolicValue = riskSymbolicValue
        self.answers = answers
    }
}

/// Pure Foundation mapper for canonical structured payloads. Unknown enum raw
/// values remain present while their symbolic value is simply absent.
enum SpecializedHealthKitRecordMapper {
    static func electrocardiogram(
        _ value: HealthKitElectrocardiogramRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "numberOfVoltageMeasurements": .signedInteger(value.numberOfVoltageMeasurements),
            "classification": rawEnum(
                rawValue: value.classificationRawValue,
                symbolicValue: value.classificationSymbolicValue
            ),
            "symptomsStatus": rawEnum(
                rawValue: value.symptomsStatusRawValue,
                symbolicValue: value.symptomsStatusSymbolicValue
            ),
        ]
        if let samplingFrequency = value.samplingFrequency {
            fields["samplingFrequency"] = samplingFrequency.metadataValue
        }
        if let averageHeartRate = value.averageHeartRate {
            fields["averageHeartRate"] = averageHeartRate.metadataValue
        }
        if let enumeratedMeasurementCount = value.enumeratedMeasurementCount {
            fields["enumeratedMeasurementCount"] = .signedInteger(enumeratedMeasurementCount)
        }
        if let voltageMeasurements = value.voltageMeasurements {
            fields["voltageMeasurements"] = .array(voltageMeasurements.map { measurement in
                var measurementFields: [String: HealthKitMetadataValue] = [
                    "timeSinceSampleStart": .floatingPoint(measurement.timeSinceSampleStart),
                    "lead": rawEnum(
                        rawValue: measurement.leadRawValue,
                        symbolicValue: measurement.leadSymbolicValue
                    ),
                ]
                if let volts = measurement.volts {
                    measurementFields["volts"] = .floatingPoint(volts)
                }
                return .dictionary(measurementFields)
            })
        }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(kind: "electrocardiogram", fields: fields)
        )
    }

    static func linkingElectrocardiogram(
        _ electrocardiogram: HealthKitRecord,
        associatedSymptoms: [HealthKitRecord]
    ) -> (electrocardiogram: HealthKitRecord, associatedSymptoms: [HealthKitRecord]) {
        let parentRelationships = associatedSymptoms.map {
            HealthKitRecordRelationship(
                targetUUID: $0.originalUUID,
                role: "symptom",
                kind: "electrocardiogramAssociatedObject"
            )
        }
        let linkedSymptoms = associatedSymptoms.map { symptom in
            symptom.addingRelationships([
                HealthKitRecordRelationship(
                    targetUUID: electrocardiogram.originalUUID,
                    role: "electrocardiogram",
                    kind: "parent"
                ),
            ])
        }
        return (
            electrocardiogram.addingRelationships(parentRelationships),
            linkedSymptoms
        )
    }

    static func audiogram(
        _ value: HealthKitAudiogramRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        let points: [HealthKitMetadataValue] = value.sensitivityPoints.map { point in
            let tests: [HealthKitMetadataValue] = point.tests.map { test in
                var fields: [String: HealthKitMetadataValue] = [
                    "sensitivityDBHL": .floatingPoint(test.sensitivityDBHL),
                    "side": rawEnum(
                        rawValue: test.sideRawValue,
                        symbolicValue: test.sideSymbolicValue
                    ),
                ]
                if let conductionTypeRawValue = test.conductionTypeRawValue {
                    fields["conductionType"] = rawEnum(
                        rawValue: conductionTypeRawValue,
                        symbolicValue: test.conductionTypeSymbolicValue
                    )
                }
                if let masked = test.masked {
                    fields["masked"] = .bool(masked)
                }
                if let lower = test.lowerClampingBoundDBHL {
                    fields["lowerClampingBoundDBHL"] = .floatingPoint(lower)
                }
                if let upper = test.upperClampingBoundDBHL {
                    fields["upperClampingBoundDBHL"] = .floatingPoint(upper)
                }
                return .dictionary(fields)
            }
            return .dictionary([
                "frequencyHertz": .floatingPoint(point.frequencyHertz),
                "tests": .array(tests),
            ])
        }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(
                kind: "audiogram",
                fields: ["sensitivityPoints": .array(points)]
            )
        )
    }

    static func heartbeatSeries(
        _ value: HealthKitHeartbeatSeriesRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "count": .unsignedInteger(value.count),
        ]
        if let heartbeats = value.heartbeats {
            fields["heartbeats"] = .array(heartbeats.map { heartbeat in
                .dictionary([
                    "timeIntervalSinceSeriesStart": .floatingPoint(heartbeat.timeIntervalSinceSeriesStart),
                    "precededByGap": .bool(heartbeat.precededByGap),
                ])
            })
        }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(kind: "heartbeatSeries", fields: fields)
        )
    }

    static func scoredAssessment(
        _ value: HealthKitScoredAssessmentRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        let answers: [HealthKitMetadataValue] = value.answers.map { answer in
            .dictionary([
                "questionIndex": .signedInteger(answer.questionIndex),
                "answer": rawEnum(rawValue: answer.rawValue, symbolicValue: answer.symbolicValue),
            ])
        }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(kind: value.assessmentKind, fields: [
                "score": .signedInteger(value.score),
                "risk": rawEnum(
                    rawValue: value.riskRawValue,
                    symbolicValue: value.riskSymbolicValue
                ),
                "answers": .array(answers),
            ])
        )
    }

    static func rawEnum(rawValue: Int64, symbolicValue: String?) -> HealthKitMetadataValue {
        var fields: [String: HealthKitMetadataValue] = [
            "rawValue": .signedInteger(rawValue),
        ]
        if let symbolicValue {
            fields["symbolicValue"] = .string(symbolicValue)
        }
        return .dictionary(fields)
    }

    private static func record(
        envelope: HealthKitSpecializedSampleEnvelope,
        selectedMetricIDs: [String],
        payload: HealthKitRecordPayload
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: envelope.originalUUID,
            objectTypeIdentifier: envelope.objectTypeIdentifier,
            recordKind: envelope.recordKind,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: envelope.startDate,
            endDate: envelope.endDate,
            hasUndeterminedDuration: envelope.hasUndeterminedDuration,
            sourceRevision: envelope.sourceRevision,
            device: envelope.device,
            metadata: envelope.metadata,
            payload: payload
        )
    }
}
