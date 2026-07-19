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
        var externalRecords: [HealthKitExternalRecord] = []
        var attachmentParents: [HealthKitAttachmentParentReference] = []
        var recordQueryResults: [HealthKitQueryResult] = []
        var childQueryFailures: [HealthKitQueryResult] = []
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []

        for entry in entries.sorted(by: { $0.objectTypeIdentifier < $1.objectTypeIdentifier }) {
            let operation = "querySpecializedRecords"
            do {
                let result: SpecializedQueryBatch
                switch entry.recordKind {
                case .clinical:
                    result = try await queryClinicalRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                case .document:
                    result = try await queryCDADocumentRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                case .verifiableClinicalRecord:
                    result = try await queryVerifiableClinicalRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                case .visionPrescription:
                    result = try await queryVisionPrescriptionRecords(
                        predicate: predicate,
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
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
                case .activitySummary:
                    result = try await queryActivitySummaryRecords(
                        entry: entry,
                        interval: interval,
                        limit: limit
                    )
                case .characteristic:
                    result = try queryCharacteristicRecord(entry: entry)
                default:
                    continue
                }

                records.append(contentsOf: result.records)
                externalRecords.append(contentsOf: result.externalRecords)
                attachmentParents.append(contentsOf: result.attachmentParents)
                childQueryFailures.append(contentsOf: result.childQueryFailures)
                integrityWarnings.append(contentsOf: result.integrityWarnings)
                recordQueryResults.append(HealthKitQueryResult(
                    identifier: entry.objectTypeIdentifier,
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: result.operation ?? operation,
                    metricIDs: entry.metricIDs,
                    metricAttribution: entry.attribution,
                    interval: interval,
                    status: result.queryStatus,
                    recordCount: result.parentRecordCount,
                    statusDescription: result.statusDescription
                ))
            } catch {
                let nsError = error as NSError
                let status: HealthKitQueryResultStatus = Self.isCancellationError(error) ? .cancelled : .failure
                recordQueryResults.append(HealthKitQueryResult(
                    identifier: entry.objectTypeIdentifier,
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: operation,
                    metricIDs: entry.metricIDs,
                    metricAttribution: entry.attribution,
                    interval: interval,
                    status: status,
                    recordCount: 0,
                    error: HealthKitQueryError(error: nsError, isRecoverable: true)
                ))
            }
        }

        return HealthKitSpecializedRecordQueryResult(
            records: records,
            externalRecords: externalRecords,
            attachmentParents: attachmentParents,
            recordQueryResults: recordQueryResults,
            childQueryFailures: childQueryFailures,
            integrityWarnings: integrityWarnings
        )
    }

    static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == HKError.errorDomain
            && nsError.code == HKError.Code.errorUserCanceled.rawValue
    }

    private struct SpecializedQueryBatch {
        var records: [HealthKitRecord] = []
        var externalRecords: [HealthKitExternalRecord] = []
        var attachmentParents: [HealthKitAttachmentParentReference] = []
        var parentRecordCount = 0
        var queryStatus: HealthKitQueryResultStatus = .success
        var operation: String?
        var statusDescription: String?
        var childQueryFailures: [HealthKitQueryResult] = []
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    }

    // MARK: Clinical records, documents, verifiable records, and vision

    private func queryClinicalRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        #if os(watchOS)
        return SpecializedQueryBatch(
            queryStatus: .unsupported,
            statusDescription: "Health Records are unavailable on watchOS."
        )
        #else
        guard supportsHealthRecords else {
            return SpecializedQueryBatch(
                queryStatus: .unsupported,
                operation: "queryClinicalRecords",
                statusDescription: "HKHealthStore.supportsHealthRecords() returned false on this device or account."
            )
        }
        guard #available(iOS 15.4, macOS 13.0, macCatalyst 15.4, *) else {
            return SpecializedQueryBatch(
                queryStatus: .unsupported,
                statusDescription: "The runtime cannot execute typed clinical record descriptors."
            )
        }

        let type = HKClinicalType(HKClinicalTypeIdentifier(rawValue: entry.objectTypeIdentifier))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.clinicalRecord(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = limitedParents(try await descriptor.result(for: store), limit: limit)
        var batch = SpecializedQueryBatch(
            parentRecordCount: samples.count,
            operation: "queryClinicalRecords"
        )
        for sample in samples {
            batch.records.append(ClinicalDocumentVisionHealthKitRecordMapper.clinical(
                canonicalClinicalRecordValue(from: sample),
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution))
            batch.attachmentParents.append(HealthKitAttachmentParentReference(object: sample))
        }
        return batch
        #endif
    }

    #if !os(watchOS)
    @available(iOS 15.4, macOS 13.0, macCatalyst 15.4, *)
    func canonicalClinicalRecordValue(from sample: HKClinicalRecord) -> HealthKitClinicalRecordValue {
        let resourceValue: HealthKitFHIRResourceValue?
        if let resource = sample.fhirResource {
            let version = resource.fhirVersion
            resourceValue = HealthKitFHIRResourceValue(
                resourceType: resource.resourceType.rawValue,
                identifier: resource.identifier,
                fhirVersionString: version.stringRepresentation,
                fhirVersionMajor: Int64(version.majorVersion),
                fhirVersionMinor: Int64(version.minorVersion),
                fhirVersionPatch: Int64(version.patchVersion),
                fhirRelease: version.fhirRelease.rawValue,
                sourceURLString: resource.sourceURL?.absoluteString,
                rawJSONData: resource.data
            )
        } else {
            resourceValue = nil
        }
        return HealthKitClinicalRecordValue(
            envelope: specializedEnvelope(from: sample, kind: .clinical),
            clinicalTypeIdentifier: sample.clinicalType.identifier,
            displayName: sample.displayName,
            fhirResource: resourceValue
        )
    }
    #endif

    private func queryCDADocumentRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        #if os(watchOS)
        return SpecializedQueryBatch(
            queryStatus: .unsupported,
            statusDescription: "CDA document queries are unavailable on watchOS."
        )
        #else
        guard supportsCDADocuments else {
            return SpecializedQueryBatch(
                queryStatus: .unsupported,
                operation: "queryCDADocumentRecords",
                statusDescription: "The runtime does not support public CDA document queries."
            )
        }
        let samples = try await queryCDADocumentsWithUserSelection(
            predicate: predicate,
            limit: limit
        )
        var batch = SpecializedQueryBatch(
            parentRecordCount: samples.count,
            operation: "queryCDADocumentRecords"
        )
        for sample in samples {
            let value = canonicalCDADocumentValue(from: sample)
            let parent = ClinicalDocumentVisionHealthKitRecordMapper.cdaDocument(
                value,
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution)
            if value.documentData == nil {
                batch.childQueryFailures.append(childFailure(
                    parent: sample,
                    suffix: "documentData",
                    operation: "queryCDADocumentData",
                    entry: entry,
                    interval: interval,
                    error: NSError(
                        domain: "HealthMd.HealthKitArchive",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The authorized CDA sample did not expose document XML bytes."]
                    )
                ))
            }
            batch.records.append(parent)
            batch.attachmentParents.append(HealthKitAttachmentParentReference(object: sample))
        }
        return batch
        #endif
    }

    #if !os(watchOS)
    nonisolated private final class CDADocumentQueryState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[HKCDADocumentSample], Error>?
        private var samples: [HKCDADocumentSample] = []
        private var completed = false
        private var cancelled = false
        private var query: HKDocumentQuery?

        nonisolated func install(_ continuation: CheckedContinuation<[HKCDADocumentSample], Error>) {
            lock.lock()
            if cancelled {
                completed = true
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        nonisolated func receive(_ results: [HKDocumentSample]?, done: Bool, error: Error?) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            if let error {
                completed = true
                let continuation = self.continuation
                self.continuation = nil
                lock.unlock()
                continuation?.resume(throwing: error)
                return
            }
            samples.append(contentsOf: (results ?? []).compactMap { $0 as? HKCDADocumentSample })
            guard done else { lock.unlock(); return }
            completed = true
            let output = samples
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: output)
        }

        nonisolated func executeIfActive(_ query: HKDocumentQuery, store: HKHealthStore) {
            lock.lock()
            guard !cancelled, !completed else {
                lock.unlock()
                return
            }
            self.query = query
            // Starting execution while holding the lock closes the race where cancellation
            // could otherwise stop a not-yet-executed query before it is submitted.
            store.execute(query)
            lock.unlock()
        }

        @discardableResult
        nonisolated func cancel() -> HKDocumentQuery? {
            lock.lock()
            cancelled = true
            guard !completed else { lock.unlock(); return nil }
            completed = true
            let query = self.query
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(throwing: CancellationError())
            return query
        }
    }

    private func queryCDADocumentsWithUserSelection(
        predicate: NSPredicate?,
        limit: Int?
    ) async throws -> [HKCDADocumentSample] {
        let state = CDADocumentQueryState()
        let samples: [HKCDADocumentSample] = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                guard !Task.isCancelled else {
                    if let query = state.cancel() { store.stop(query) }
                    return
                }
                let query = HKDocumentQuery(
                    documentType: HKDocumentType(.CDA),
                    predicate: predicate,
                    limit: limit ?? HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)],
                    includeDocumentData: true
                ) { _, results, done, error in
                    state.receive(results, done: done, error: error)
                }
                state.executeIfActive(query, store: store)
            }
        } onCancel: {
            let query = state.cancel()
            if let query {
                Task { @MainActor in store.stop(query) }
            }
        }
        let sorted = samples.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
            if lhs.sampleType.identifier != rhs.sampleType.identifier {
                return lhs.sampleType.identifier < rhs.sampleType.identifier
            }
            return lhs.uuid.uuidString < rhs.uuid.uuidString
        }
        return limitedParents(sorted, limit: limit)
    }

    func canonicalCDADocumentValue(from sample: HKCDADocumentSample) -> HealthKitCDADocumentRecordValue {
        HealthKitCDADocumentRecordValue(
            envelope: specializedEnvelope(from: sample, kind: .document),
            title: sample.document?.title,
            patientName: sample.document?.patientName,
            authorName: sample.document?.authorName,
            custodianName: sample.document?.custodianName,
            documentData: sample.document?.documentData
        )
    }
    #endif

    private func queryVerifiableClinicalRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        #if os(watchOS)
        return SpecializedQueryBatch(
            queryStatus: .unsupported,
            statusDescription: "Verifiable clinical record queries are unavailable on watchOS."
        )
        #else
        guard supportsVerifiableClinicalRecords else {
            return SpecializedQueryBatch(
                queryStatus: .unsupported,
                operation: "queryVerifiableClinicalRecords",
                statusDescription: "This Health.md build does not include Apple's restricted Verifiable Health Records entitlement."
            )
        }
        guard #available(iOS 15.4, macOS 13.0, macCatalyst 15.4, *) else {
            return SpecializedQueryBatch(queryStatus: .unsupported)
        }
        var samplesByUUID: [UUID: HKVerifiableClinicalRecord] = [:]
        for descriptor in Self.verifiableClinicalRecordQueryDescriptors(predicate: predicate) {
            for sample in try await descriptor.result(for: store) {
                samplesByUUID[sample.uuid] = sample
            }
        }
        let sortedSamples = samplesByUUID.values.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            if $0.endDate != $1.endDate { return $0.endDate < $1.endDate }
            return $0.uuid.uuidString < $1.uuid.uuidString
        }
        let samples = limitedParents(sortedSamples, limit: limit)
        var batch = SpecializedQueryBatch(
            parentRecordCount: samples.count,
            operation: "queryVerifiableClinicalRecords"
        )
        for sample in samples {
            let parent = ClinicalDocumentVisionHealthKitRecordMapper.verifiableClinicalRecord(
                canonicalVerifiableClinicalRecordValue(from: sample),
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution)
            batch.records.append(parent)
            batch.attachmentParents.append(HealthKitAttachmentParentReference(object: sample))
        }
        return batch
        #endif
    }

    #if !os(watchOS)
    @available(iOS 15.4, macOS 13.0, macCatalyst 15.4, *)
    static func verifiableClinicalRecordQueryDescriptors(
        predicate: NSPredicate?
    ) -> [HKVerifiableClinicalRecordQueryDescriptor] {
        // HealthKit accepts any number of qualifier types (for example,
        // `.covid19`) but requires exactly one clinical type per query. Query
        // each clinical category without a qualifier to include every disease,
        // then merge repeated records by their public UUID.
        [
            HKVerifiableClinicalRecordQueryDescriptor(
                recordTypes: [.immunization],
                sourceTypes: [.smartHealthCard, .euDigitalCOVIDCertificate],
                predicate: predicate
            ),
            HKVerifiableClinicalRecordQueryDescriptor(
                recordTypes: [.laboratory],
                sourceTypes: [.smartHealthCard, .euDigitalCOVIDCertificate],
                predicate: predicate
            ),
            HKVerifiableClinicalRecordQueryDescriptor(
                recordTypes: [.recovery],
                sourceTypes: [.smartHealthCard, .euDigitalCOVIDCertificate],
                predicate: predicate
            ),
        ]
    }

    @available(iOS 15.4, macOS 13.0, macCatalyst 15.4, *)
    func canonicalVerifiableClinicalRecordValue(
        from sample: HKVerifiableClinicalRecord
    ) -> HealthKitVerifiableClinicalRecordValue {
        HealthKitVerifiableClinicalRecordValue(
            envelope: specializedEnvelope(from: sample, kind: .verifiableClinicalRecord),
            recordTypes: sample.recordTypes,
            sourceType: sample.sourceType?.rawValue,
            issuerIdentifier: sample.issuerIdentifier,
            subjectFullName: sample.subject.fullName,
            subjectDateOfBirthComponents: sample.subject.dateOfBirthComponents.map {
                Self.dateComponentsValue($0 as DateComponents)
            },
            issuedDate: sample.issuedDate,
            relevantDate: sample.relevantDate,
            expirationDate: sample.expirationDate,
            itemNames: sample.itemNames,
            dataRepresentation: sample.dataRepresentation
        )
    }
    #endif

    private func queryVisionPrescriptionRecords(
        predicate: NSPredicate?,
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        guard supportsVisionPrescriptionAuthorization else {
            return SpecializedQueryBatch(
                queryStatus: .unsupported,
                operation: "queryVisionPrescriptionRecords",
                statusDescription: "The runtime does not support vision prescription per-object authorization."
            )
        }
        guard #available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *) else {
            return SpecializedQueryBatch(queryStatus: .unsupported)
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.visionPrescription(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = limitedParents(try await descriptor.result(for: store), limit: limit)
        var batch = SpecializedQueryBatch(
            parentRecordCount: samples.count,
            operation: "queryVisionPrescriptionRecords"
        )
        for sample in samples {
            let parent = ClinicalDocumentVisionHealthKitRecordMapper.visionPrescription(
                canonicalVisionPrescriptionValue(from: sample),
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution)
            batch.records.append(parent)
            batch.attachmentParents.append(HealthKitAttachmentParentReference(object: sample))
        }
        return batch
    }

    @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *)
    func canonicalVisionPrescriptionValue(
        from sample: HKVisionPrescription
    ) -> HealthKitVisionPrescriptionRecordValue {
        let common = (
            envelope: specializedEnvelope(from: sample, kind: .visionPrescription),
            rawType: Int64(sample.prescriptionType.rawValue),
            symbolicType: Self.visionPrescriptionTypeSymbol(Int64(sample.prescriptionType.rawValue))
        )
        if let glasses = sample as? HKGlassesPrescription {
            return HealthKitVisionPrescriptionRecordValue(
                envelope: common.envelope,
                prescriptionTypeRawValue: common.rawType,
                prescriptionTypeSymbolicValue: common.symbolicType,
                dateIssued: sample.dateIssued,
                expirationDate: sample.expirationDate,
                subtype: "glasses",
                rightEye: glasses.rightEye.map(canonicalGlassesLensValue),
                leftEye: glasses.leftEye.map(canonicalGlassesLensValue)
            )
        }
        if let contacts = sample as? HKContactsPrescription {
            return HealthKitVisionPrescriptionRecordValue(
                envelope: common.envelope,
                prescriptionTypeRawValue: common.rawType,
                prescriptionTypeSymbolicValue: common.symbolicType,
                dateIssued: sample.dateIssued,
                expirationDate: sample.expirationDate,
                subtype: "contacts",
                rightEye: contacts.rightEye.map(canonicalContactsLensValue),
                leftEye: contacts.leftEye.map(canonicalContactsLensValue),
                brand: contacts.brand
            )
        }
        return HealthKitVisionPrescriptionRecordValue(
            envelope: common.envelope,
            prescriptionTypeRawValue: common.rawType,
            prescriptionTypeSymbolicValue: common.symbolicType,
            dateIssued: sample.dateIssued,
            expirationDate: sample.expirationDate,
            subtype: "unknown",
            rightEye: nil,
            leftEye: nil
        )
    }

    @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *)
    private func canonicalGlassesLensValue(
        _ lens: HKGlassesLensSpecification
    ) -> HealthKitVisionLensValue {
        HealthKitVisionLensValue(
            sphere: exactQuantity(lens.sphere, unit: .diopter()),
            cylinder: lens.cylinder.map { exactQuantity($0, unit: .diopter()) },
            axis: lens.axis.map { exactQuantity($0, unit: .degreeAngle()) },
            addPower: lens.addPower.map { exactQuantity($0, unit: .diopter()) },
            vertexDistance: lens.vertexDistance.map { exactQuantity($0, unit: .meterUnit(with: .milli)) },
            prism: lens.prism.map(canonicalVisionPrismValue),
            farPupillaryDistance: lens.farPupillaryDistance.map { exactQuantity($0, unit: .meterUnit(with: .milli)) },
            nearPupillaryDistance: lens.nearPupillaryDistance.map { exactQuantity($0, unit: .meterUnit(with: .milli)) }
        )
    }

    @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *)
    private func canonicalContactsLensValue(
        _ lens: HKContactsLensSpecification
    ) -> HealthKitVisionLensValue {
        HealthKitVisionLensValue(
            sphere: exactQuantity(lens.sphere, unit: .diopter()),
            cylinder: lens.cylinder.map { exactQuantity($0, unit: .diopter()) },
            axis: lens.axis.map { exactQuantity($0, unit: .degreeAngle()) },
            addPower: lens.addPower.map { exactQuantity($0, unit: .diopter()) },
            baseCurve: lens.baseCurve.map { exactQuantity($0, unit: .meterUnit(with: .milli)) },
            diameter: lens.diameter.map { exactQuantity($0, unit: .meterUnit(with: .milli)) }
        )
    }

    @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *)
    private func canonicalVisionPrismValue(_ prism: HKVisionPrism) -> HealthKitVisionPrismValue {
        HealthKitVisionPrismValue(
            amount: exactQuantity(prism.amount, unit: .prismDiopter()),
            angle: exactQuantity(prism.angle, unit: .degreeAngle()),
            verticalAmount: exactQuantity(prism.verticalAmount, unit: .prismDiopter()),
            horizontalAmount: exactQuantity(prism.horizontalAmount, unit: .prismDiopter()),
            verticalBaseRawValue: Int64(prism.verticalBase.rawValue),
            verticalBaseSymbolicValue: Self.prismBaseSymbol(Int64(prism.verticalBase.rawValue)),
            horizontalBaseRawValue: Int64(prism.horizontalBase.rawValue),
            horizontalBaseSymbolicValue: Self.prismBaseSymbol(Int64(prism.horizontalBase.rawValue)),
            eyeRawValue: Int64(prism.eye.rawValue),
            eyeSymbolicValue: Self.visionEyeSymbol(Int64(prism.eye.rawValue))
        )
    }

    static func visionPrescriptionTypeSymbol(_ rawValue: Int64) -> String? {
        switch rawValue {
        case 1: return "glasses"
        case 2: return "contacts"
        default: return nil
        }
    }

    static func prismBaseSymbol(_ rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "none"
        case 1: return "up"
        case 2: return "down"
        case 3: return "in"
        case 4: return "out"
        default: return nil
        }
    }

    static func visionEyeSymbol(_ rawValue: Int64) -> String? {
        switch rawValue {
        case 1: return "left"
        case 2: return "right"
        default: return nil
        }
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
            batch.attachmentParents.append(HealthKitAttachmentParentReference(object: sample))
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
            batch.attachmentParents.append(contentsOf: associated.attachmentParents)
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
        attachmentParents: [HealthKitAttachmentParentReference],
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
        var attachmentParents: [HealthKitAttachmentParentReference] = []
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
                attachmentParents.append(contentsOf: samples.map {
                    HealthKitAttachmentParentReference(object: $0)
                })
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
        return (records, attachmentParents, failures, [])
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
            batch.attachmentParents.append(HealthKitAttachmentParentReference(object: sample))
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
            batch.attachmentParents.append(HealthKitAttachmentParentReference(object: sample))
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
            batch.attachmentParents.append(contentsOf: samples.map {
                HealthKitAttachmentParentReference(object: $0)
            })
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
            batch.attachmentParents.append(contentsOf: samples.map {
                HealthKitAttachmentParentReference(object: $0)
            })
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

    // MARK: Activity summaries and characteristics

    private func queryActivitySummaryRecords(
        entry: HealthKitRecordSelectionPlanEntry,
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async throws -> SpecializedQueryBatch {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = interval.calendarTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: 0)!
        let requestedComponents = Self.activitySummaryDateComponents(
            for: interval.startDate,
            calendar: calendar
        )
        let summaryPredicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: requestedComponents,
            end: requestedComponents
        )
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: summaryPredicate)
        let summaries = limitedParents(try await descriptor.result(for: store), limit: limit)
        let externalRecords = summaries.map { summary in
            HealthKitExternalRecordMapper.activitySummary(
                canonicalActivitySummaryValue(from: summary, calendar: calendar),
                objectTypeIdentifier: entry.objectTypeIdentifier,
                selectedMetricIDs: entry.metricIDs
            ).attributed(entry.attribution)
        }
        return SpecializedQueryBatch(
            externalRecords: externalRecords,
            parentRecordCount: externalRecords.count,
            operation: "queryActivitySummaryRecords"
        )
    }

    static func activitySummaryDateComponents(
        for date: Date,
        calendar: Calendar
    ) -> DateComponents {
        var components = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: date
        )
        // HealthKit raises an uncaught NSInvalidArgumentException when the
        // date components do not carry their Gregorian calendar.
        components.calendar = calendar
        return components
    }

    func canonicalActivitySummaryValue(
        from summary: HKActivitySummary,
        calendar: Calendar
    ) -> HealthKitActivitySummaryRecordValue {
        let energyUnit = HKUnit.kilocalorie()
        let timeUnit = HKUnit.minute()
        let countUnit = HKUnit.count()
        let components = summary.dateComponents(for: calendar)

        return HealthKitActivitySummaryRecordValue(
            dateComponents: Self.dateComponentsValue(components, fallbackCalendar: calendar),
            activityMoveModeRawValue: Int64(summary.activityMoveMode.rawValue),
            activityMoveModeSymbolicValue: Self.activityMoveModeSymbol(
                rawValue: Int64(summary.activityMoveMode.rawValue)
            ),
            paused: {
                if #available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *) {
                    return summary.isPaused
                }
                return nil
            }(),
            activeEnergyBurned: exactQuantity(summary.activeEnergyBurned, unit: energyUnit),
            appleMoveTime: exactQuantity(summary.appleMoveTime, unit: timeUnit),
            appleExerciseTime: exactQuantity(summary.appleExerciseTime, unit: timeUnit),
            appleStandHours: exactQuantity(summary.appleStandHours, unit: countUnit),
            activeEnergyBurnedGoal: exactQuantity(summary.activeEnergyBurnedGoal, unit: energyUnit),
            appleMoveTimeGoal: exactQuantity(summary.appleMoveTimeGoal, unit: timeUnit),
            appleExerciseTimeGoal: exactQuantity(summary.appleExerciseTimeGoal, unit: timeUnit),
            exerciseTimeGoal: summary.exerciseTimeGoal.map { exactQuantity($0, unit: timeUnit) },
            appleStandHoursGoal: exactQuantity(summary.appleStandHoursGoal, unit: countUnit),
            standHoursGoal: summary.standHoursGoal.map { exactQuantity($0, unit: countUnit) }
        )
    }

    private func queryCharacteristicRecord(
        entry: HealthKitRecordSelectionPlanEntry
    ) throws -> SpecializedQueryBatch {
        let fields: [String: HealthKitMetadataValue]
        do {
            switch entry.objectTypeIdentifier {
            case HealthKitRecordCatalog.dateOfBirthIdentifier:
                fields = [
                    "dateComponents": Self.dateComponentsValue(
                        try store.dateOfBirthComponents()
                    ).metadataValue,
                ]
            case HealthKitRecordCatalog.biologicalSexIdentifier:
                let rawValue = Int64(try store.biologicalSex().biologicalSex.rawValue)
                fields = ["value": HealthKitExternalRecordMapper.rawEnum(
                    rawValue: rawValue,
                    symbolicValue: Self.biologicalSexSymbol(rawValue: rawValue)
                )]
            case HealthKitRecordCatalog.bloodTypeIdentifier:
                let rawValue = Int64(try store.bloodType().bloodType.rawValue)
                fields = ["value": HealthKitExternalRecordMapper.rawEnum(
                    rawValue: rawValue,
                    symbolicValue: Self.bloodTypeSymbol(rawValue: rawValue)
                )]
            case HealthKitRecordCatalog.fitzpatrickSkinTypeIdentifier:
                let rawValue = Int64(try store.fitzpatrickSkinType().skinType.rawValue)
                fields = ["value": HealthKitExternalRecordMapper.rawEnum(
                    rawValue: rawValue,
                    symbolicValue: Self.fitzpatrickSkinTypeSymbol(rawValue: rawValue)
                )]
            case HealthKitRecordCatalog.wheelchairUseIdentifier:
                let rawValue = Int64(try store.wheelchairUse().wheelchairUse.rawValue)
                fields = ["value": HealthKitExternalRecordMapper.rawEnum(
                    rawValue: rawValue,
                    symbolicValue: Self.wheelchairUseSymbol(rawValue: rawValue)
                )]
            case HealthKitRecordCatalog.activityMoveModeIdentifier:
                let rawValue = Int64(try store.activityMoveMode().activityMoveMode.rawValue)
                fields = ["value": HealthKitExternalRecordMapper.rawEnum(
                    rawValue: rawValue,
                    symbolicValue: Self.activityMoveModeSymbol(rawValue: rawValue)
                )]
            default:
                return SpecializedQueryBatch(
                    queryStatus: .unsupported,
                    operation: "queryCharacteristicRecord",
                    statusDescription: "The requested characteristic identifier is not supported by the direct HealthKit adapter."
                )
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == HKError.errorDomain,
               nsError.code == HKError.Code.errorNoData.rawValue {
                return SpecializedQueryBatch(
                    operation: "queryCharacteristicRecord",
                    statusDescription: "HealthKit returned no characteristic value. Read privacy does not allow inferring whether the value is absent or access was declined."
                )
            }
            throw error
        }

        let record = HealthKitExternalRecordMapper.characteristic(
            objectTypeIdentifier: entry.objectTypeIdentifier,
            selectedMetricIDs: entry.metricIDs,
            fields: fields
        ).attributed(entry.attribution)
        return SpecializedQueryBatch(
            externalRecords: [record],
            parentRecordCount: 1,
            operation: "queryCharacteristicRecord"
        )
    }

    static func dateComponentsValue(
        _ components: DateComponents,
        fallbackCalendar: Calendar? = nil
    ) -> HealthKitDateComponentsValue {
        let dayOfYear: Int?
        if #available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *) {
            dayOfYear = components.dayOfYear
        } else {
            dayOfYear = nil
        }
        return HealthKitDateComponentsValue(
            calendarIdentifier: components.calendar.map { String(describing: $0.identifier) }
                ?? fallbackCalendar.map { String(describing: $0.identifier) },
            timeZoneIdentifier: components.timeZone?.identifier ?? fallbackCalendar?.timeZone.identifier,
            era: components.era,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: components.hour,
            minute: components.minute,
            second: components.second,
            nanosecond: components.nanosecond,
            weekday: components.weekday,
            weekdayOrdinal: components.weekdayOrdinal,
            dayOfYear: dayOfYear,
            quarter: components.quarter,
            weekOfMonth: components.weekOfMonth,
            weekOfYear: components.weekOfYear,
            yearForWeekOfYear: components.yearForWeekOfYear,
            isLeapMonth: components.isLeapMonth
        )
    }

    static func activityMoveModeSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 1: return "activeEnergy"
        case 2: return "appleMoveTime"
        default: return nil
        }
    }

    static func biologicalSexSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "notSet"
        case 1: return "female"
        case 2: return "male"
        case 3: return "other"
        default: return nil
        }
    }

    static func bloodTypeSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "notSet"
        case 1: return "aPositive"
        case 2: return "aNegative"
        case 3: return "bPositive"
        case 4: return "bNegative"
        case 5: return "abPositive"
        case 6: return "abNegative"
        case 7: return "oPositive"
        case 8: return "oNegative"
        default: return nil
        }
    }

    static func fitzpatrickSkinTypeSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "notSet"
        case 1: return "typeI"
        case 2: return "typeII"
        case 3: return "typeIII"
        case 4: return "typeIV"
        case 5: return "typeV"
        case 6: return "typeVI"
        default: return nil
        }
    }

    static func wheelchairUseSymbol(rawValue: Int64) -> String? {
        switch rawValue {
        case 0: return "notSet"
        case 1: return "no"
        case 2: return "yes"
        default: return nil
        }
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
