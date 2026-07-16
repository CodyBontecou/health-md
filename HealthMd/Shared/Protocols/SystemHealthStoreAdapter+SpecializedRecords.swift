import Foundation
@preconcurrency import HealthKit

extension SystemHealthStoreAdapter {
    func querySpecializedRecords(
        predicate: NSPredicate?,
        entries: [HealthKitRecordSelectionPlanEntry],
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async -> HealthKitSpecializedRecordQueryResult {
        var records: [HealthKitRecord] = []
        var recordQueryResults: [HealthKitQueryResult] = []
        var childQueryFailures: [HealthKitQueryResult] = []
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []

        for entry in entries.sorted(by: { $0.objectTypeIdentifier < $1.objectTypeIdentifier }) {
            let operation = "querySpecializedRecords"
            do {
                let result: SpecializedQueryBatch
                switch entry.recordKind {
                case .electrocardiogram:
                    result = try await queryElectrocardiogramRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                case .audiogram:
                    result = try await queryAudiogramRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                case .heartbeatSeries:
                    result = try await queryHeartbeatSeriesRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                case .scoredAssessment:
                    result = try await queryScoredAssessmentRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                default:
                    continue
                }

                records.append(contentsOf: result.records)
                childQueryFailures.append(contentsOf: result.childQueryFailures)
                integrityWarnings.append(contentsOf: result.integrityWarnings)
                recordQueryResults.append(HealthKitQueryResult(
                    identifier: entry.objectTypeIdentifier,
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: operation,
                    metricIDs: entry.metricIDs,
                    metricAttribution: entry.attribution,
                    interval: interval,
                    status: .success,
                    recordCount: result.parentRecordCount
                ))
            } catch {
                let nsError = error as NSError
                recordQueryResults.append(HealthKitQueryResult(
                    identifier: entry.objectTypeIdentifier,
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: operation,
                    metricIDs: entry.metricIDs,
                    metricAttribution: entry.attribution,
                    interval: interval,
                    status: .failure,
                    recordCount: 0,
                    error: HealthKitQueryError(error: nsError, isRecoverable: true)
                ))
            }
        }

        return HealthKitSpecializedRecordQueryResult(
            records: records,
            recordQueryResults: recordQueryResults,
            childQueryFailures: childQueryFailures,
            integrityWarnings: integrityWarnings
        )
    }

    private struct SpecializedQueryBatch {
        var records: [HealthKitRecord] = []
        var parentRecordCount = 0
        var childQueryFailures: [HealthKitQueryResult] = []
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    }

    // MARK: Electrocardiograms

    private func queryElectrocardiogramRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        guard #available(iOS 14.0, macOS 13.0, macCatalyst 14.0, watchOS 7.0, *) else {
            return SpecializedQueryBatch()
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.electrocardiogram(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = limitedParents(try await descriptor.result(for: store), limit: limit)
        var batch = SpecializedQueryBatch(parentRecordCount: samples.count)

        for sample in samples {
            var voltageValues: [HealthKitElectrocardiogramVoltageValue]?
            var enumeratedMeasurementCount: Int64?
            do {
                var values: [HealthKitElectrocardiogramVoltageValue] = []
                var returnedCount: Int64 = 0
                for try await measurement in HKElectrocardiogramQueryDescriptor(sample).results(for: store) {
                    returnedCount += 1
                    let leadRawValue = Int64(HKElectrocardiogram.Lead.appleWatchSimilarToLeadI.rawValue)
                    let quantity = measurement.quantity(for: .appleWatchSimilarToLeadI)
                    values.append(HealthKitElectrocardiogramVoltageValue(
                        timeSinceSampleStart: measurement.timeSinceSampleStart,
                        leadRawValue: leadRawValue,
                        leadSymbolicValue: Self.electrocardiogramLeadSymbol(rawValue: leadRawValue),
                        volts: quantity?.doubleValue(for: .volt())
                    ))
                    if quantity == nil {
                        batch.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                            code: "ecg_voltage_missing_for_public_lead",
                            message: "An ECG voltage measurement did not expose a quantity for the public Apple Watch Lead I equivalent; its timestamp and lead were retained.",
                            metricIDs: entry.metricIDs,
                            recordUUIDs: [sample.uuid]
                        ))
                    }
                }
                voltageValues = values
                enumeratedMeasurementCount = returnedCount
                if returnedCount != Int64(sample.numberOfVoltageMeasurements) {
                    batch.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                        code: "ecg_voltage_measurement_count_mismatch",
                        message: "The enumerated ECG waveform count did not match numberOfVoltageMeasurements.",
                        metricIDs: entry.metricIDs,
                        recordUUIDs: [sample.uuid]
                    ))
                }
            } catch {
                batch.childQueryFailures.append(childFailure(
                    parent: sample,
                    suffix: "voltageMeasurements",
                    operation: "queryElectrocardiogramVoltageMeasurements",
                    entry: entry,
                    interval: interval,
                    error: error
                ))
            }

            let value = HealthKitElectrocardiogramRecordValue(
                envelope: specializedEnvelope(from: sample, kind: .electrocardiogram),
                numberOfVoltageMeasurements: Int64(sample.numberOfVoltageMeasurements),
                samplingFrequency: sample.samplingFrequency.map {
                    exactQuantity($0, unit: .hertz())
                },
                classificationRawValue: Int64(sample.classification.rawValue),
                classificationSymbolicValue: Self.electrocardiogramClassificationSymbol(
                    rawValue: Int64(sample.classification.rawValue)
                ),
                averageHeartRate: sample.averageHeartRate.map {
                    exactQuantity($0, unit: HKUnit.count().unitDivided(by: .minute()))
                },
                symptomsStatusRawValue: Int64(sample.symptomsStatus.rawValue),
                symptomsStatusSymbolicValue: Self.electrocardiogramSymptomsStatusSymbol(
                    rawValue: Int64(sample.symptomsStatus.rawValue)
                ),
                voltageMeasurements: voltageValues,
                enumeratedMeasurementCount: enumeratedMeasurementCount
            )
            var parent = SpecializedHealthKitRecordMapper.electrocardiogram(
                value,
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution)

            #if os(iOS) && !targetEnvironment(macCatalyst)
            let associated = await queryAssociatedSymptoms(
                for: sample,
                entry: entry,
                interval: interval
            )
            batch.childQueryFailures.append(contentsOf: associated.failures)
            batch.integrityWarnings.append(contentsOf: associated.warnings)
            let linked = SpecializedHealthKitRecordMapper.linkingElectrocardiogram(
                parent,
                associatedSymptoms: associated.records
            )
            parent = linked.electrocardiogram
            batch.records.append(contentsOf: linked.associatedSymptoms)
            #endif

            batch.records.append(parent)
        }
        return batch
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 14.0, *)
    private func queryAssociatedSymptoms(
        for electrocardiogram: HKElectrocardiogram,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval
    ) async -> (
        records: [HealthKitRecord],
        failures: [HealthKitQueryResult],
        warnings: [HealthKitRecordIntegrityWarning]
    ) {
        let associationPredicate = HKQuery.predicateForObjectsAssociated(
            electrocardiogram: electrocardiogram
        )
        let identifiers = Set(
            HealthMetrics.symptoms
                .filter { $0.availability.isAvailableOnCurrentPlatform }
                .compactMap(\.healthKitIdentifier)
        ).sorted()
        var records: [HealthKitRecord] = []
        var failures: [HealthKitQueryResult] = []
        let dependencyAttribution = HealthKitMetricAttribution(
            dependencyMetricIDs: entry.metricIDs
        )

        for identifier in identifiers {
            guard let type = HKObjectType.categoryType(
                forIdentifier: HKCategoryTypeIdentifier(rawValue: identifier)
            ) else { continue }
            do {
                let descriptor = HKSampleQueryDescriptor(
                    predicates: [.categorySample(type: type, predicate: associationPredicate)],
                    sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
                )
                let samples = try await descriptor.result(for: store)
                for sample in samples {
                    records.append(canonicalCategoryRecord(
                        from: sample,
                        selectedMetricIDs: entry.metricIDs
                    ).attributed(dependencyAttribution))
                }
            } catch {
                failures.append(childFailure(
                    parent: electrocardiogram,
                    suffix: "associatedSymptoms:\(identifier)",
                    operation: "queryElectrocardiogramAssociatedSymptoms",
                    entry: entry,
                    interval: interval,
                    error: error
                ))
            }
        }
        return (records, failures, [])
    }
    #endif

    // MARK: Audiograms

    private func queryAudiogramRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval _: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        guard #available(iOS 13.0, macOS 13.0, macCatalyst 13.0, watchOS 6.0, *) else {
            return SpecializedQueryBatch()
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.audiogram(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = limitedParents(try await descriptor.result(for: store), limit: limit)
        var batch = SpecializedQueryBatch(parentRecordCount: samples.count)
        for sample in samples {
            let value = canonicalAudiogramValue(from: sample)
            batch.records.append(SpecializedHealthKitRecordMapper.audiogram(
                value,
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution))
            let frequencies = value.sensitivityPoints.map(\.frequencyHertz)
            if frequencies != frequencies.sorted() {
                batch.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                    code: "audiogram_frequency_order_unexpected",
                    message: "HealthKit returned audiogram sensitivity points outside documented ascending-frequency order; source order was preserved.",
                    metricIDs: entry.metricIDs,
                    recordUUIDs: [sample.uuid]
                ))
            }
        }
        return batch
    }

    func canonicalAudiogramValue(from sample: HKAudiogramSample) -> HealthKitAudiogramRecordValue {
        let frequencyUnit = HKUnit.hertz()
        let sensitivityUnit = HKUnit.decibelHearingLevel()
        let points = sample.sensitivityPoints.map { point -> HealthKitAudiogramSensitivityPointValue in
            let tests: [HealthKitAudiogramSensitivityTestValue]
            if #available(iOS 18.1, macOS 15.1, macCatalyst 18.1, watchOS 11.1, visionOS 2.1, *) {
                tests = point.tests.map { test in
                    let sideRawValue = Int64(test.side.rawValue)
                    let conductionRawValue = Int64(test.type.rawValue)
                    return HealthKitAudiogramSensitivityTestValue(
                        sensitivityDBHL: test.sensitivity.doubleValue(for: sensitivityUnit),
                        sideRawValue: sideRawValue,
                        sideSymbolicValue: Self.audiogramSideSymbol(rawValue: sideRawValue),
                        conductionTypeRawValue: conductionRawValue,
                        conductionTypeSymbolicValue: Self.audiogramConductionSymbol(
                            rawValue: conductionRawValue
                        ),
                        masked: test.masked,
                        lowerClampingBoundDBHL: test.clampingRange?.lowerBound?.doubleValue(
                            for: sensitivityUnit
                        ),
                        upperClampingBoundDBHL: test.clampingRange?.upperBound?.doubleValue(
                            for: sensitivityUnit
                        )
                    )
                }
            } else {
                var legacyTests: [HealthKitAudiogramSensitivityTestValue] = []
                if let sensitivity = point.leftEarSensitivity {
                    legacyTests.append(HealthKitAudiogramSensitivityTestValue(
                        sensitivityDBHL: sensitivity.doubleValue(for: sensitivityUnit),
                        sideRawValue: 0,
                        sideSymbolicValue: Self.audiogramSideSymbol(rawValue: 0)
                    ))
                }
                if let sensitivity = point.rightEarSensitivity {
                    legacyTests.append(HealthKitAudiogramSensitivityTestValue(
                        sensitivityDBHL: sensitivity.doubleValue(for: sensitivityUnit),
                        sideRawValue: 1,
                        sideSymbolicValue: Self.audiogramSideSymbol(rawValue: 1)
                    ))
                }
                tests = legacyTests
            }
            return HealthKitAudiogramSensitivityPointValue(
                frequencyHertz: point.frequency.doubleValue(for: frequencyUnit),
                tests: tests
            )
        }
        return HealthKitAudiogramRecordValue(
            envelope: specializedEnvelope(from: sample, kind: .audiogram),
            sensitivityPoints: points
        )
    }

    // MARK: Heartbeat series

    private func queryHeartbeatSeriesRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        guard #available(iOS 13.0, macOS 13.0, macCatalyst 13.0, watchOS 6.0, visionOS 1.0, *) else {
            return SpecializedQueryBatch()
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.heartbeatSeries(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = limitedParents(try await descriptor.result(for: store), limit: limit)
        var batch = SpecializedQueryBatch(parentRecordCount: samples.count)
        for sample in samples {
            var heartbeats: [HealthKitHeartbeatValue]?
            do {
                var values: [HealthKitHeartbeatValue] = []
                for try await heartbeat in HKHeartbeatSeriesQueryDescriptor(sample).results(for: store) {
                    values.append(HealthKitHeartbeatValue(
                        timeIntervalSinceSeriesStart: heartbeat.timeIntervalSinceStart,
                        precededByGap: heartbeat.precededByGap
                    ))
                }
                heartbeats = values
                if UInt64(values.count) != UInt64(sample.count) {
                    batch.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                        code: "heartbeat_series_count_mismatch",
                        message: "The enumerated heartbeat count did not match HKSeriesSample.count.",
                        metricIDs: entry.metricIDs,
                        recordUUIDs: [sample.uuid]
                    ))
                }
            } catch {
                batch.childQueryFailures.append(childFailure(
                    parent: sample,
                    suffix: "heartbeats",
                    operation: "queryHeartbeatSeriesBeats",
                    entry: entry,
                    interval: interval,
                    error: error
                ))
            }
            let value = HealthKitHeartbeatSeriesRecordValue(
                envelope: specializedEnvelope(from: sample, kind: .heartbeatSeries),
                count: UInt64(sample.count),
                heartbeats: heartbeats
            )
            batch.records.append(SpecializedHealthKitRecordMapper.heartbeatSeries(
                value,
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution))
        }
        return batch
    }

    // MARK: Scored assessments

    private func queryScoredAssessmentRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval _: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        guard #available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *) else {
            return SpecializedQueryBatch()
        }

        var batch = SpecializedQueryBatch()
        if entry.objectTypeIdentifier == HealthKitRecordCatalog.gad7AssessmentIdentifier {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.gad7Assessment(predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
            )
            let samples = limitedParents(try await descriptor.result(for: store), limit: limit)
            batch.parentRecordCount = samples.count
            for sample in samples {
                let value = canonicalGAD7Value(from: sample)
                batch.records.append(SpecializedHealthKitRecordMapper.scoredAssessment(
                    value,
                    selectedMetricIDs: entry.metricIDs
                ).attributed(entry.attribution))
                if value.answers.count != 7 {
                    batch.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                        code: "gad7_answer_count_mismatch",
                        message: "A GAD-7 assessment did not expose exactly seven answers.",
                        metricIDs: entry.metricIDs,
                        recordUUIDs: [sample.uuid]
                    ))
                }
            }
        } else if entry.objectTypeIdentifier == HealthKitRecordCatalog.phq9AssessmentIdentifier {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.phq9Assessment(predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
            )
            let samples = limitedParents(try await descriptor.result(for: store), limit: limit)
            batch.parentRecordCount = samples.count
            for sample in samples {
                let value = canonicalPHQ9Value(from: sample)
                batch.records.append(SpecializedHealthKitRecordMapper.scoredAssessment(
                    value,
                    selectedMetricIDs: entry.metricIDs
                ).attributed(entry.attribution))
                if value.answers.count != 9 {
                    batch.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                        code: "phq9_answer_count_mismatch",
                        message: "A PHQ-9 assessment did not expose exactly nine answers.",
                        metricIDs: entry.metricIDs,
                        recordUUIDs: [sample.uuid]
                    ))
                }
            }
        }
        return batch
    }

    @available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *)
    func canonicalGAD7Value(from sample: HKGAD7Assessment) -> HealthKitScoredAssessmentRecordValue {
        HealthKitScoredAssessmentRecordValue(
            envelope: specializedEnvelope(from: sample, kind: .scoredAssessment),
            assessmentKind: "gad7Assessment",
            score: Int64(sample.score),
            riskRawValue: Int64(sample.risk.rawValue),
            riskSymbolicValue: Self.gad7RiskSymbol(rawValue: Int64(sample.risk.rawValue)),
            answers: sample.answers.enumerated().map { index, answer in
                let rawValue = Int64(answer.rawValue)
                return HealthKitScoredAssessmentAnswerValue(
                    questionIndex: Int64(index + 1),
                    rawValue: rawValue,
                    symbolicValue: Self.assessmentAnswerSymbol(rawValue: rawValue, allowsSkipped: false)
                )
            }
        )
    }

    @available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *)
    func canonicalPHQ9Value(from sample: HKPHQ9Assessment) -> HealthKitScoredAssessmentRecordValue {
        HealthKitScoredAssessmentRecordValue(
            envelope: specializedEnvelope(from: sample, kind: .scoredAssessment),
            assessmentKind: "phq9Assessment",
            score: Int64(sample.score),
            riskRawValue: Int64(sample.risk.rawValue),
            riskSymbolicValue: Self.phq9RiskSymbol(rawValue: Int64(sample.risk.rawValue)),
            answers: sample.answers.enumerated().map { index, answer in
                let rawValue = Int64(answer.rawValue)
                return HealthKitScoredAssessmentAnswerValue(
                    questionIndex: Int64(index + 1),
                    rawValue: rawValue,
                    symbolicValue: Self.assessmentAnswerSymbol(rawValue: rawValue, allowsSkipped: true)
                )
            }
        )
    }

    // MARK: Common helpers

    private func specializedEnvelope(
        from sample: HKSample,
        kind: HealthKitRecordKind
    ) -> HealthKitSpecializedSampleEnvelope {
        HealthKitSpecializedSampleEnvelope(
            originalUUID: sample.uuid,
            objectTypeIdentifier: sample.sampleType.identifier,
            recordKind: kind,
            startDate: sample.startDate,
            endDate: sample.endDate,
            hasUndeterminedDuration: sample.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
            device: Self.deviceProvenance(from: sample.device),
            metadata: Self.typedMetadata(sample.metadata)
        )
    }

    private func exactQuantity(_ quantity: HKQuantity, unit: HKUnit) -> HealthKitExactQuantityValue {
        HealthKitExactQuantityValue(
            value: quantity.doubleValue(for: unit),
            unit: unit.unitString,
            rawDescription: quantity.description
        )
    }

    private func childFailure(
        parent: HKSample,
        suffix: String,
        operation: String,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        error: Error
    ) -> HealthKitQueryResult {
        HealthKitQueryResult(
            identifier: "\(entry.objectTypeIdentifier):\(parent.uuid.uuidString):\(suffix)",
            objectTypeIdentifier: entry.objectTypeIdentifier,
            operation: operation,
            metricIDs: entry.metricIDs,
            metricAttribution: entry.attribution,
            interval: interval,
            status: .failure,
            recordCount: 0,
            error: HealthKitQueryError(error: error as NSError, isRecoverable: true)
        )
    }

    private func limitedParents<Sample>(_ samples: [Sample], limit: Int?) -> [Sample] {
        guard let limit else { return samples }
        return Array(samples.prefix(max(0, limit)))
    }

    static func electrocardiogramLeadSymbol(rawValue: Int64) -> String? {
        rawValue == 1 ? "appleWatchSimilarToLeadI" : nil
    }

    static func electrocardiogramClassificationSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "notSet"
        case 1: return "sinusRhythm"
        case 2: return "atrialFibrillation"
        case 3: return "inconclusiveLowHeartRate"
        case 4: return "inconclusiveHighHeartRate"
        case 5: return "inconclusivePoorReading"
        case 6: return "inconclusiveOther"
        case 100: return "unrecognized"
        default: return nil
        }
    }

    static func electrocardiogramSymptomsStatusSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "notSet"
        case 1: return "none"
        case 2: return "present"
        default: return nil
        }
    }

    static func audiogramSideSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "left"
        case 1: return "right"
        default: return nil
        }
    }

    static func audiogramConductionSymbol(rawValue: Int64) -> String? {
        rawValue == 0 ? "air" : nil
    }

    static func assessmentAnswerSymbol(rawValue: Int64, allowsSkipped: Bool) -> String? {
        switch rawValue {
        case 0: return "notAtAll"
        case 1: return "severalDays"
        case 2: return "moreThanHalfTheDays"
        case 3: return "nearlyEveryDay"
        case 4 where allowsSkipped: return "preferNotToAnswer"
        default: return nil
        }
    }

    static func gad7RiskSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 1: return "noneToMinimal"
        case 2: return "mild"
        case 3: return "moderate"
        case 4: return "severe"
        default: return nil
        }
    }

    static func phq9RiskSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 1: return "noneToMinimal"
        case 2: return "mild"
        case 3: return "moderate"
        case 4: return "moderatelySevere"
        case 5: return "severe"
        default: return nil
        }
    }
}
