import Foundation
import HealthKit
import XCTest
@testable import HealthMd

final class SpecializedHealthKitRecordMapperTests: XCTestCase {
    private let source = HealthKitSourceRevision(
        name: "Specialized Fixture",
        bundleIdentifier: "com.example.specialized",
        version: "26.5",
        productType: "Watch7,5",
        operatingSystemVersion: HealthKitOperatingSystemVersion(
            majorVersion: 26,
            minorVersion: 5,
            patchVersion: 0
        )
    )

    func testElectrocardiogramPortableMappingPreservesEnvelopeWaveformPrecisionAndUnknownEnums() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "EC000000-0000-0000-0000-000000000001"))
        let start = Date(timeIntervalSinceReferenceDate: 812_345_678.123_456_7)
        let envelope = makeEnvelope(
            uuid: uuid,
            identifier: HealthKitRecordCatalog.electrocardiogramIdentifier,
            kind: .electrocardiogram,
            start: start,
            metadata: ["typed": .unsignedInteger(UInt64.max)]
        )
        let exactFirstVoltage = 0.000_001_234_567_890_123
        let exactSecondTime = 29.999_999_999_999_996
        let value = HealthKitElectrocardiogramRecordValue(
            envelope: envelope,
            numberOfVoltageMeasurements: 2,
            samplingFrequency: HealthKitExactQuantityValue(
                value: 511.999_999_999_999_94,
                unit: "Hz",
                rawDescription: "511.99999999999994 Hz"
            ),
            classificationRawValue: 9_999,
            classificationSymbolicValue: nil,
            averageHeartRate: HealthKitExactQuantityValue(
                value: 73.125,
                unit: "count/min",
                rawDescription: "73.125 count/min"
            ),
            symptomsStatusRawValue: 2,
            symptomsStatusSymbolicValue: "present",
            voltageMeasurements: [
                HealthKitElectrocardiogramVoltageValue(
                    timeSinceSampleStart: 0.000_000_000_000_001,
                    leadRawValue: 1,
                    leadSymbolicValue: "appleWatchSimilarToLeadI",
                    volts: exactFirstVoltage
                ),
                HealthKitElectrocardiogramVoltageValue(
                    timeSinceSampleStart: exactSecondTime,
                    leadRawValue: 77,
                    leadSymbolicValue: nil,
                    volts: -0.000_000_987_654_321_098
                ),
            ],
            enumeratedMeasurementCount: 2
        )

        let record = SpecializedHealthKitRecordMapper.electrocardiogram(
            value,
            selectedMetricIDs: ["electrocardiograms"]
        )

        XCTAssertEqual(record.originalUUID, uuid)
        XCTAssertEqual(record.startDate.timeIntervalSinceReferenceDate, start.timeIntervalSinceReferenceDate)
        XCTAssertEqual(record.sourceRevision, source)
        XCTAssertEqual(record.metadata["typed"], .unsignedInteger(UInt64.max))
        guard case .structured(let kind, let fields) = record.payload else {
            return XCTFail("Expected structured ECG payload")
        }
        XCTAssertEqual(kind, "electrocardiogram")
        XCTAssertEqual(fields["numberOfVoltageMeasurements"], .signedInteger(2))
        XCTAssertEqual(
            fields["classification"],
            .dictionary(["rawValue": .signedInteger(9_999)]),
            "Unknown enums retain raw identity without a fabricated symbolic value"
        )
        XCTAssertEqual(fields["symptomsStatus"], .dictionary([
            "rawValue": .signedInteger(2),
            "symbolicValue": .string("present"),
        ]))
        guard case .array(let measurements) = fields["voltageMeasurements"] else {
            return XCTFail("Expected inline voltage measurements")
        }
        XCTAssertEqual(measurements.count, 2)
        guard case .dictionary(let first) = measurements[0],
              case .dictionary(let second) = measurements[1] else {
            return XCTFail("Expected typed waveform dictionaries")
        }
        XCTAssertEqual(first["volts"], .floatingPoint(exactFirstVoltage))
        XCTAssertEqual(second["timeSinceSampleStart"], .floatingPoint(exactSecondTime))
        XCTAssertEqual(second["lead"], .dictionary(["rawValue": .signedInteger(77)]))

        let decoded = try JSONDecoder().decode(
            HealthKitRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(decoded, record)

        let symptomUUID = UUID()
        let symptom = HealthKitRecord(
            originalUUID: symptomUUID,
            objectTypeIdentifier: HKCategoryTypeIdentifier.headache.rawValue,
            recordKind: .category,
            selectedMetricIDs: ["electrocardiograms"],
            includedBecause: .relationshipDependency,
            metricAttribution: HealthKitMetricAttribution(
                dependencyMetricIDs: ["electrocardiograms"]
            ),
            startDate: start,
            endDate: start,
            sourceRevision: source,
            payload: .category(HealthKitCategoryPayload(rawValue: 2, symbolicValue: nil))
        )
        let linked = SpecializedHealthKitRecordMapper.linkingElectrocardiogram(
            record,
            associatedSymptoms: [symptom]
        )
        XCTAssertEqual(linked.electrocardiogram.relationships.first?.targetUUID, symptomUUID)
        XCTAssertEqual(linked.electrocardiogram.relationships.first?.role, "symptom")
        XCTAssertEqual(linked.associatedSymptoms.first?.relationships.first?.targetUUID, uuid)
        XCTAssertEqual(linked.associatedSymptoms.first?.relationships.first?.role, "electrocardiogram")
        XCTAssertEqual(linked.associatedSymptoms.first?.includedBecause, .relationshipDependency)
    }

    func testFailedWaveformAndHeartbeatChildAreAbsentRatherThanFakeEmptyArtifacts() {
        let ecg = SpecializedHealthKitRecordMapper.electrocardiogram(
            HealthKitElectrocardiogramRecordValue(
                envelope: makeEnvelope(
                    uuid: UUID(),
                    identifier: HealthKitRecordCatalog.electrocardiogramIdentifier,
                    kind: .electrocardiogram,
                    start: .now
                ),
                numberOfVoltageMeasurements: 500,
                samplingFrequency: nil,
                classificationRawValue: 0,
                classificationSymbolicValue: "notSet",
                averageHeartRate: nil,
                symptomsStatusRawValue: 0,
                symptomsStatusSymbolicValue: "notSet",
                voltageMeasurements: nil,
                enumeratedMeasurementCount: nil
            ),
            selectedMetricIDs: ["electrocardiograms"]
        )
        let heartbeat = SpecializedHealthKitRecordMapper.heartbeatSeries(
            HealthKitHeartbeatSeriesRecordValue(
                envelope: makeEnvelope(
                    uuid: UUID(),
                    identifier: HealthKitRecordCatalog.heartbeatSeriesIdentifier,
                    kind: .heartbeatSeries,
                    start: .now
                ),
                count: 250,
                heartbeats: nil
            ),
            selectedMetricIDs: ["heartbeat_series"]
        )

        guard case .structured(_, let ecgFields) = ecg.payload,
              case .structured(_, let heartbeatFields) = heartbeat.payload else {
            return XCTFail("Expected structured payloads")
        }
        XCTAssertNil(ecgFields["voltageMeasurements"])
        XCTAssertNil(heartbeatFields["heartbeats"])
        XCTAssertEqual(heartbeatFields["count"], .unsignedInteger(250))
    }

    func testAudiogramPreservesPointAndTestOrderAllFieldsAndUnknownRawValues() {
        let points = [
            HealthKitAudiogramSensitivityPointValue(
                frequencyHertz: 8_000.125,
                tests: [HealthKitAudiogramSensitivityTestValue(
                    sensitivityDBHL: 42.75,
                    sideRawValue: 1,
                    sideSymbolicValue: "right",
                    conductionTypeRawValue: 0,
                    conductionTypeSymbolicValue: "air",
                    masked: true,
                    lowerClampingBoundDBHL: -10.5,
                    upperClampingBoundDBHL: 110.25
                )]
            ),
            HealthKitAudiogramSensitivityPointValue(
                frequencyHertz: 250.5,
                tests: [HealthKitAudiogramSensitivityTestValue(
                    sensitivityDBHL: 12.125,
                    sideRawValue: 99,
                    sideSymbolicValue: nil,
                    conductionTypeRawValue: 88,
                    conductionTypeSymbolicValue: nil,
                    masked: false
                )]
            ),
            HealthKitAudiogramSensitivityPointValue(
                frequencyHertz: 125,
                tests: [HealthKitAudiogramSensitivityTestValue(
                    sensitivityDBHL: 7.25,
                    sideRawValue: 0,
                    sideSymbolicValue: "left"
                )]
            ),
        ]
        let record = SpecializedHealthKitRecordMapper.audiogram(
            HealthKitAudiogramRecordValue(
                envelope: makeEnvelope(
                    uuid: UUID(),
                    identifier: HealthKitRecordCatalog.audiogramIdentifier,
                    kind: .audiogram,
                    start: .now
                ),
                sensitivityPoints: points
            ),
            selectedMetricIDs: ["audiograms"]
        )

        guard case .structured(let kind, let fields) = record.payload,
              case .array(let mappedPoints) = fields["sensitivityPoints"],
              case .dictionary(let firstPoint) = mappedPoints[0],
              case .dictionary(let secondPoint) = mappedPoints[1],
              case .array(let firstTests) = firstPoint["tests"],
              case .dictionary(let firstTest) = firstTests[0],
              case .array(let secondTests) = secondPoint["tests"],
              case .dictionary(let secondTest) = secondTests[0],
              case .dictionary(let legacyPoint) = mappedPoints[2],
              case .array(let legacyTests) = legacyPoint["tests"],
              case .dictionary(let legacyTest) = legacyTests[0] else {
            return XCTFail("Expected canonical audiogram payload")
        }
        XCTAssertEqual(kind, "audiogram")
        XCTAssertEqual(firstPoint["frequencyHertz"], .floatingPoint(8_000.125))
        XCTAssertEqual(secondPoint["frequencyHertz"], .floatingPoint(250.5), "Source ordering must not be changed")
        XCTAssertEqual(firstTest["sensitivityDBHL"], .floatingPoint(42.75))
        XCTAssertEqual(firstTest["masked"], .bool(true))
        XCTAssertEqual(firstTest["lowerClampingBoundDBHL"], .floatingPoint(-10.5))
        XCTAssertEqual(firstTest["upperClampingBoundDBHL"], .floatingPoint(110.25))
        XCTAssertEqual(secondTest["side"], .dictionary(["rawValue": .signedInteger(99)]))
        XCTAssertEqual(secondTest["conductionType"], .dictionary(["rawValue": .signedInteger(88)]))
        XCTAssertEqual(legacyTest["sensitivityDBHL"], .floatingPoint(7.25))
        XCTAssertNil(legacyTest["conductionType"], "Legacy left/right fallback must not invent unavailable fields")
        XCTAssertNil(legacyTest["masked"])
        XCTAssertNil(legacyTest["lowerClampingBoundDBHL"])
        XCTAssertNil(legacyTest["upperClampingBoundDBHL"])
    }

    func testHeartbeatSeriesPreservesExactIntervalsAndGapFlagsWithoutHeartRateInference() {
        let firstInterval = 0.812_345_678_901_234_5
        let secondInterval = 1.923_456_789_012_345_6
        let record = SpecializedHealthKitRecordMapper.heartbeatSeries(
            HealthKitHeartbeatSeriesRecordValue(
                envelope: makeEnvelope(
                    uuid: UUID(),
                    identifier: HealthKitRecordCatalog.heartbeatSeriesIdentifier,
                    kind: .heartbeatSeries,
                    start: .now
                ),
                count: 2,
                heartbeats: [
                    HealthKitHeartbeatValue(
                        timeIntervalSinceSeriesStart: firstInterval,
                        precededByGap: false
                    ),
                    HealthKitHeartbeatValue(
                        timeIntervalSinceSeriesStart: secondInterval,
                        precededByGap: true
                    ),
                ]
            ),
            selectedMetricIDs: ["heartbeat_series"]
        )

        guard case .structured(let kind, let fields) = record.payload,
              case .array(let heartbeats) = fields["heartbeats"],
              case .dictionary(let first) = heartbeats[0],
              case .dictionary(let second) = heartbeats[1] else {
            return XCTFail("Expected heartbeat series payload")
        }
        XCTAssertEqual(kind, "heartbeatSeries")
        XCTAssertNil(fields["heartRate"])
        XCTAssertEqual(first["timeIntervalSinceSeriesStart"], .floatingPoint(firstInterval))
        XCTAssertEqual(first["precededByGap"], .bool(false))
        XCTAssertEqual(second["timeIntervalSinceSeriesStart"], .floatingPoint(secondInterval))
        XCTAssertEqual(second["precededByGap"], .bool(true))
    }

    func testAssessmentsPreserveScoreRiskAnswersAndUnknownRawValues() {
        let record = SpecializedHealthKitRecordMapper.scoredAssessment(
            HealthKitScoredAssessmentRecordValue(
                envelope: makeEnvelope(
                    uuid: UUID(),
                    identifier: HealthKitRecordCatalog.phq9AssessmentIdentifier,
                    kind: .scoredAssessment,
                    start: .now
                ),
                assessmentKind: "phq9Assessment",
                score: 17,
                riskRawValue: 444,
                riskSymbolicValue: nil,
                answers: [
                    HealthKitScoredAssessmentAnswerValue(
                        questionIndex: 1,
                        rawValue: 3,
                        symbolicValue: "nearlyEveryDay"
                    ),
                    HealthKitScoredAssessmentAnswerValue(
                        questionIndex: 9,
                        rawValue: 999,
                        symbolicValue: nil
                    ),
                ]
            ),
            selectedMetricIDs: ["phq9_assessments"]
        )

        guard case .structured(let kind, let fields) = record.payload,
              case .array(let answers) = fields["answers"],
              case .dictionary(let last) = answers.last else {
            return XCTFail("Expected scored assessment payload")
        }
        XCTAssertEqual(kind, "phq9Assessment")
        XCTAssertEqual(fields["score"], .signedInteger(17))
        XCTAssertEqual(fields["risk"], .dictionary(["rawValue": .signedInteger(444)]))
        XCTAssertEqual(last["questionIndex"], .signedInteger(9))
        XCTAssertEqual(last["answer"], .dictionary(["rawValue": .signedInteger(999)]))
    }

    func testSpecializedRecordsSurviveJSONCSVAndHealthDataSyncCodable() throws {
        let start = Date(timeIntervalSinceReferenceDate: 812_000_000.25)
        let uuid = try XCTUnwrap(UUID(uuidString: "EC000000-0000-0000-0000-000000000099"))
        let voltage = 0.000_000_123_456_789_012
        let record = SpecializedHealthKitRecordMapper.electrocardiogram(
            HealthKitElectrocardiogramRecordValue(
                envelope: makeEnvelope(
                    uuid: uuid,
                    identifier: HealthKitRecordCatalog.electrocardiogramIdentifier,
                    kind: .electrocardiogram,
                    start: start
                ),
                numberOfVoltageMeasurements: 1,
                samplingFrequency: nil,
                classificationRawValue: 1,
                classificationSymbolicValue: "sinusRhythm",
                averageHeartRate: nil,
                symptomsStatusRawValue: 1,
                symptomsStatusSymbolicValue: "none",
                voltageMeasurements: [HealthKitElectrocardiogramVoltageValue(
                    timeSinceSampleStart: 0.123_456_789_012_345,
                    leadRawValue: 1,
                    leadSymbolicValue: "appleWatchSimilarToLeadI",
                    volts: voltage
                )],
                enumeratedMeasurementCount: 1
            ),
            selectedMetricIDs: ["electrocardiograms"]
        )
        let interval = HealthKitQueryInterval(startDate: start, endDate: start.addingTimeInterval(86_400))
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-09-24",
                intervalStart: interval.startDate,
                intervalEnd: interval.endDate,
                calendarTimeZoneIdentifier: "UTC"
            ),
            records: [record],
            queryManifest: HealthKitQueryManifest(results: [HealthKitQueryResult(
                identifier: HealthKitRecordCatalog.electrocardiogramIdentifier,
                objectTypeIdentifier: HealthKitRecordCatalog.electrocardiogramIdentifier,
                operation: "querySpecializedRecords",
                metricIDs: ["electrocardiograms"],
                interval: interval,
                status: .success,
                recordCount: 1
            )])
        )
        let original = HealthData(
            date: start,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )

        let decoded = try JSONDecoder().decode(HealthData.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.healthKitRecordArchive, archive)

        let json = original.toJSON()
        XCTAssertTrue(json.contains(uuid.uuidString))
        XCTAssertTrue(json.contains("voltageMeasurements"))
        let jsonObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(json.data(using: .utf8))) as? [String: Any]
        )
        let jsonVoltageField = try XCTUnwrap(
            findJSONValue(forKey: "volts", in: jsonObject) as? [String: Any]
        )
        let jsonVoltage = try XCTUnwrap(jsonVoltageField["value"] as? NSNumber)
        XCTAssertEqual(jsonVoltage.doubleValue, voltage)

        let csv = original.toCSV()
        XCTAssertTrue(csv.contains(uuid.uuidString))
        XCTAssertTrue(csv.contains("voltageMeasurements"))
        let rawRecordJSON = try XCTUnwrap(
            parseRFC4180(csv).first { $0.count == 6 && $0[2] == "Raw HealthKit Record" }?[3]
        )
        let csvRecord = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(rawRecordJSON.data(using: .utf8))
            ) as? [String: Any]
        )
        let csvVoltageField = try XCTUnwrap(
            findJSONValue(forKey: "volts", in: csvRecord) as? [String: Any]
        )
        let csvVoltage = try XCTUnwrap(csvVoltageField["value"] as? NSNumber)
        XCTAssertEqual(csvVoltage.doubleValue, voltage)
    }

    private func findJSONValue(forKey key: String, in value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            if let match = dictionary[key] { return match }
            for nested in dictionary.values {
                if let match = findJSONValue(forKey: key, in: nested) { return match }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let match = findJSONValue(forKey: key, in: nested) { return match }
            }
        }
        return nil
    }

    private func parseRFC4180(_ csv: String) -> [[String]] {
        let characters = Array(csv)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !quoted {
                row.append(field)
                field = ""
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private func makeEnvelope(
        uuid: UUID,
        identifier: String,
        kind: HealthKitRecordKind,
        start: Date,
        metadata: [String: HealthKitMetadataValue] = [:]
    ) -> HealthKitSpecializedSampleEnvelope {
        HealthKitSpecializedSampleEnvelope(
            originalUUID: uuid,
            objectTypeIdentifier: identifier,
            recordKind: kind,
            startDate: start,
            endDate: start.addingTimeInterval(30),
            sourceRevision: source,
            device: HealthKitDeviceProvenance(
                name: "Fixture Watch",
                manufacturer: "Example",
                model: "Precision",
                localIdentifier: "exact-device-id",
                udiDeviceIdentifier: "exact-udi"
            ),
            metadata: metadata
        )
    }
}

final class SpecializedHealthKitAdapterTests: XCTestCase {
    func testPublicAssessmentConstructorsMapUUIDMetadataAnswersScoreAndRisk() throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let adapter = SystemHealthStoreAdapter()
        let date = Date(timeIntervalSinceReferenceDate: 812_400_000.125)
        let gad = HKGAD7Assessment(
            date: date,
            answers: [.notAtAll, .severalDays, .moreThanHalfTheDays, .nearlyEveryDay,
                      .notAtAll, .severalDays, .moreThanHalfTheDays],
            metadata: ["typed": NSNumber(value: Int64.max)]
        )
        let phq = HKPHQ9Assessment(
            date: date,
            answers: [.notAtAll, .severalDays, .moreThanHalfTheDays, .nearlyEveryDay,
                      .notAtAll, .severalDays, .moreThanHalfTheDays, .nearlyEveryDay,
                      .preferNotToAnswer],
            metadata: [HKMetadataKeyWasUserEntered: true]
        )

        let gadValue = adapter.canonicalGAD7Value(from: gad)
        let phqValue = adapter.canonicalPHQ9Value(from: phq)

        XCTAssertEqual(gadValue.envelope.originalUUID, gad.uuid)
        XCTAssertEqual(gadValue.envelope.startDate, gad.startDate)
        XCTAssertEqual(gadValue.envelope.sourceRevision.bundleIdentifier, gad.sourceRevision.source.bundleIdentifier)
        XCTAssertEqual(gadValue.envelope.metadata["typed"], .signedInteger(Int64.max))
        XCTAssertEqual(gadValue.score, Int64(gad.score))
        XCTAssertEqual(gadValue.riskRawValue, Int64(gad.risk.rawValue))
        XCTAssertEqual(gadValue.answers.count, 7)
        XCTAssertEqual(gadValue.answers[2].rawValue, Int64(HKGAD7Assessment.Answer.moreThanHalfTheDays.rawValue))
        XCTAssertEqual(gadValue.answers[2].symbolicValue, "moreThanHalfTheDays")

        XCTAssertEqual(phqValue.envelope.originalUUID, phq.uuid)
        XCTAssertEqual(phqValue.envelope.metadata[HKMetadataKeyWasUserEntered], .bool(true))
        XCTAssertEqual(phqValue.answers.count, 9)
        XCTAssertEqual(phqValue.answers.last?.rawValue, Int64(HKPHQ9Assessment.Answer.preferNotToAnswer.rawValue))
        XCTAssertEqual(phqValue.answers.last?.symbolicValue, "preferNotToAnswer")
    }

    func testPublicAudiogramConstructorsMapOrderedTestsAndFields() throws {
        guard #available(iOS 18.1, macOS 15.1, *) else { return }
        let adapter = SystemHealthStoreAdapter()
        let sensitivityUnit = HKUnit.decibelHearingLevel()
        let left = try HKAudiogramSensitivityTest(
            sensitivity: HKQuantity(unit: sensitivityUnit, doubleValue: 10.125),
            type: .air,
            masked: false,
            side: .left,
            clampingRange: nil
        )
        let clampingRange = try HKAudiogramSensitivityPointClampingRange(
            lowerBound: -12.5,
            upperBound: 117.25
        )
        let right = try HKAudiogramSensitivityTest(
            sensitivity: HKQuantity(unit: sensitivityUnit, doubleValue: 20.875),
            type: .air,
            masked: true,
            side: .right,
            clampingRange: clampingRange
        )
        let point = try HKAudiogramSensitivityPoint(
            frequency: HKQuantity(unit: .hertz(), doubleValue: 1_000.25),
            tests: [right, left]
        )
        let start = Date(timeIntervalSinceReferenceDate: 812_500_000.5)
        let sample = HKAudiogramSample(
            sensitivityPoints: [point],
            start: start,
            end: start.addingTimeInterval(120),
            device: HKDevice(
                name: "Audiometer",
                manufacturer: "Example",
                model: "A-1",
                hardwareVersion: nil,
                firmwareVersion: nil,
                softwareVersion: nil,
                localIdentifier: "audio-device",
                udiDeviceIdentifier: nil
            ),
            metadata: ["note": "ordered"]
        )

        let value = adapter.canonicalAudiogramValue(from: sample)

        XCTAssertEqual(value.envelope.originalUUID, sample.uuid)
        XCTAssertEqual(value.envelope.device?.localIdentifier, "audio-device")
        XCTAssertEqual(value.envelope.metadata["note"], .string("ordered"))
        XCTAssertEqual(value.sensitivityPoints.map(\.frequencyHertz), [1_000.25])
        XCTAssertEqual(value.sensitivityPoints[0].tests.map(\.sensitivityDBHL), [20.875, 10.125])
        XCTAssertEqual(value.sensitivityPoints[0].tests.map(\.sideRawValue), [1, 0])
        XCTAssertEqual(value.sensitivityPoints[0].tests.map(\.masked), [true, false])
        XCTAssertEqual(value.sensitivityPoints[0].tests.map(\.conductionTypeRawValue), [0, 0])
        XCTAssertEqual(value.sensitivityPoints[0].tests[0].lowerClampingBoundDBHL, -12.5)
        XCTAssertEqual(value.sensitivityPoints[0].tests[0].upperClampingBoundDBHL, 117.25)
    }
}

final class SpecializedHealthStoreAndManagerTests: XCTestCase {
    private enum FixtureError: Error { case child }

    func testFakeCarriesDeterministicRecordsChildFailuresWarningsAndTracksExactEntries() async throws {
        let store = FakeHealthStore()
        let interval = HealthKitQueryInterval(
            startDate: Date(timeIntervalSinceReferenceDate: 100),
            endDate: Date(timeIntervalSinceReferenceDate: 200)
        )
        let entry = try XCTUnwrap(
            HealthKitRecordCatalog.attributedSelectionPlan(
                enabledMetricIDs: ["heartbeat_series"]
            ).first
        )
        let uuid = try XCTUnwrap(UUID(uuidString: "BEA70000-0000-0000-0000-000000000001"))
        let record = SpecializedHealthKitRecordMapper.heartbeatSeries(
            HealthKitHeartbeatSeriesRecordValue(
                envelope: fixtureEnvelope(
                    uuid: uuid,
                    identifier: HealthKitRecordCatalog.heartbeatSeriesIdentifier,
                    kind: .heartbeatSeries,
                    start: interval.startDate
                ),
                count: 3,
                heartbeats: nil
            ),
            selectedMetricIDs: ["heartbeat_series"]
        )
        let childFailure = HealthKitQueryResult(
            identifier: "heartbeat-child",
            objectTypeIdentifier: HealthKitRecordCatalog.heartbeatSeriesIdentifier,
            operation: "queryHeartbeatSeriesBeats",
            metricIDs: ["heartbeat_series"],
            interval: interval,
            status: .failure,
            recordCount: 0,
            error: HealthKitQueryError(
                error: FixtureError.child as NSError,
                isRecoverable: true
            )
        )
        let warning = HealthKitRecordIntegrityWarning(
            code: "fixture",
            message: "count mismatch",
            metricIDs: ["heartbeat_series"],
            recordUUIDs: [uuid]
        )
        store.specializedRecordResult = HealthKitSpecializedRecordQueryResult(
            records: [record],
            childQueryFailures: [childFailure],
            integrityWarnings: [warning]
        )
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.startDate,
            end: interval.endDate
        )

        let result = await store.querySpecializedRecords(
            predicate: predicate,
            entries: [entry],
            interval: interval,
            limit: nil
        )

        XCTAssertEqual(result.records.map(\.originalUUID), [uuid])
        XCTAssertEqual(result.records.first?.metricAttribution?.directMetricIDs, ["heartbeat_series"])
        XCTAssertEqual(result.recordQueryResults.first?.status, .success)
        XCTAssertEqual(result.recordQueryResults.first?.recordCount, 1)
        XCTAssertEqual(result.childQueryFailures, [childFailure])
        XCTAssertEqual(result.integrityWarnings, [warning])
        XCTAssertEqual(store.specializedRecordQueries.count, 1)
        XCTAssertTrue(store.specializedRecordQueries[0].predicate === predicate)
        XCTAssertEqual(store.specializedRecordQueries[0].entries, [entry])
        XCTAssertEqual(store.specializedRecordQueries[0].interval, interval)
    }

    @MainActor
    func testManagerQueriesOnlySelectedSpecializedDescriptorAndReportsComplete() async throws {
        let store = FakeHealthStore()
        let date = Date(timeIntervalSinceReferenceDate: 812_600_000)
        let start = Calendar.current.startOfDay(for: date)
        let uuid = UUID()
        let unselectedECGUUID = UUID()
        store.specializedRecordResult = HealthKitSpecializedRecordQueryResult(records: [
            SpecializedHealthKitRecordMapper.audiogram(
                HealthKitAudiogramRecordValue(
                    envelope: fixtureEnvelope(
                        uuid: uuid,
                        identifier: HealthKitRecordCatalog.audiogramIdentifier,
                        kind: .audiogram,
                        start: start.addingTimeInterval(60)
                    ),
                    sensitivityPoints: []
                ),
                selectedMetricIDs: ["audiograms"]
            ),
            SpecializedHealthKitRecordMapper.electrocardiogram(
                HealthKitElectrocardiogramRecordValue(
                    envelope: fixtureEnvelope(
                        uuid: unselectedECGUUID,
                        identifier: HealthKitRecordCatalog.electrocardiogramIdentifier,
                        kind: .electrocardiogram,
                        start: start.addingTimeInterval(120)
                    ),
                    numberOfVoltageMeasurements: 0,
                    samplingFrequency: nil,
                    classificationRawValue: 0,
                    classificationSymbolicValue: "notSet",
                    averageHeartRate: nil,
                    symptomsStatusRawValue: 0,
                    symptomsStatusSymbolicValue: "notSet",
                    voltageMeasurements: [],
                    enumeratedMeasurementCount: 0
                ),
                selectedMetricIDs: ["electrocardiograms"]
            ),
        ])
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("audiograms")
        let defaults = UserDefaults(suiteName: "SpecializedHealthKitManagerTests.complete.\(UUID().uuidString)")!
        let manager = HealthKitManager(store: store, userDefaults: defaults)

        let data = try await manager.fetchHealthData(
            for: date,
            includeGranularData: true,
            metricSelection: selection
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .complete)
        XCTAssertEqual(archive.records.map(\.originalUUID), [uuid])
        XCTAssertEqual(store.specializedRecordQueries.count, 1)
        XCTAssertEqual(store.specializedRecordQueries[0].entries.map(\.objectTypeIdentifier), [
            HealthKitRecordCatalog.audiogramIdentifier,
        ])
        XCTAssertTrue(store.queriedQuantityRecordIdentifiers.isEmpty)
        XCTAssertTrue(store.queriedCategoryRecordIdentifiers.isEmpty)
        XCTAssertEqual(archive.queryResults.first?.operation, "querySpecializedRecords")
        XCTAssertEqual(archive.queryResults.first?.metricIDs, ["audiograms"])
    }

    @MainActor
    func testChildFailureIsPartialAndDoesNotDropSuccessfulSpecializedSiblings() async throws {
        let store = FakeHealthStore()
        let date = Date(timeIntervalSinceReferenceDate: 812_700_000)
        let start = Calendar.current.startOfDay(for: date)
        let interval = HealthKitQueryInterval(startDate: start, endDate: start.addingTimeInterval(86_400))
        let ecgUUID = UUID()
        let heartbeatUUID = UUID()
        let ecg = SpecializedHealthKitRecordMapper.electrocardiogram(
            HealthKitElectrocardiogramRecordValue(
                envelope: fixtureEnvelope(
                    uuid: ecgUUID,
                    identifier: HealthKitRecordCatalog.electrocardiogramIdentifier,
                    kind: .electrocardiogram,
                    start: start.addingTimeInterval(60)
                ),
                numberOfVoltageMeasurements: 1,
                samplingFrequency: nil,
                classificationRawValue: 1,
                classificationSymbolicValue: "sinusRhythm",
                averageHeartRate: nil,
                symptomsStatusRawValue: 1,
                symptomsStatusSymbolicValue: "none",
                voltageMeasurements: [HealthKitElectrocardiogramVoltageValue(
                    timeSinceSampleStart: 0,
                    leadRawValue: 1,
                    leadSymbolicValue: "appleWatchSimilarToLeadI",
                    volts: 0.000_001
                )],
                enumeratedMeasurementCount: 1
            ),
            selectedMetricIDs: ["electrocardiograms"]
        )
        let heartbeat = SpecializedHealthKitRecordMapper.heartbeatSeries(
            HealthKitHeartbeatSeriesRecordValue(
                envelope: fixtureEnvelope(
                    uuid: heartbeatUUID,
                    identifier: HealthKitRecordCatalog.heartbeatSeriesIdentifier,
                    kind: .heartbeatSeries,
                    start: start.addingTimeInterval(120)
                ),
                count: 2,
                heartbeats: nil
            ),
            selectedMetricIDs: ["heartbeat_series"]
        )
        store.specializedRecordResult = HealthKitSpecializedRecordQueryResult(
            records: [heartbeat, ecg],
            childQueryFailures: [HealthKitQueryResult(
                identifier: "\(HealthKitRecordCatalog.heartbeatSeriesIdentifier):\(heartbeatUUID):heartbeats",
                objectTypeIdentifier: HealthKitRecordCatalog.heartbeatSeriesIdentifier,
                operation: "queryHeartbeatSeriesBeats",
                metricIDs: ["heartbeat_series"],
                interval: interval,
                status: .failure,
                recordCount: 0,
                error: HealthKitQueryError(error: FixtureError.child as NSError)
            )]
        )
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("electrocardiograms")
        selection.toggleMetric("heartbeat_series")
        let defaults = UserDefaults(suiteName: "SpecializedHealthKitManagerTests.partial.\(UUID().uuidString)")!
        let manager = HealthKitManager(store: store, userDefaults: defaults)

        let data = try await manager.fetchHealthData(
            for: date,
            includeGranularData: true,
            metricSelection: selection
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertEqual(Set(archive.records.map(\.originalUUID)), [ecgUUID, heartbeatUUID])
        XCTAssertEqual(archive.queryResults.filter { $0.status == .failure }.count, 1)
        XCTAssertEqual(archive.queryResults.first { $0.status == .failure }?.operation, "queryHeartbeatSeriesBeats")
        XCTAssertTrue(data.partialFailures.contains {
            $0.dataType.contains("\(heartbeatUUID)")
        })
        guard let heartbeatRecord = archive.records.first(where: { $0.originalUUID == heartbeatUUID }),
              case .structured(_, let fields) = heartbeatRecord.payload else {
            return XCTFail("Expected surviving heartbeat envelope")
        }
        XCTAssertNil(fields["heartbeats"], "A child failure must not masquerade as a successful empty series")
    }

    private func fixtureEnvelope(
        uuid: UUID,
        identifier: String,
        kind: HealthKitRecordKind,
        start: Date
    ) -> HealthKitSpecializedSampleEnvelope {
        HealthKitSpecializedSampleEnvelope(
            originalUUID: uuid,
            objectTypeIdentifier: identifier,
            recordKind: kind,
            startDate: start,
            endDate: start.addingTimeInterval(10),
            sourceRevision: HealthKitSourceRevision(
                name: "Fake Store",
                bundleIdentifier: "com.example.fake-store"
            )
        )
    }
}
