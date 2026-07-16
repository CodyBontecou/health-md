//
//  FakeHealthStore.swift
//  HealthMdTests
//
//  Shared deterministic fake for HealthStoreProviding.
//  Used by all HealthKitManager test files.
//

import XCTest
import HealthKit
@testable import HealthMd

final class FakeHealthStore: HealthStoreProviding, @unchecked Sendable {
    var available = true
    var authRequested = false
    var shouldThrowOnAuth: Error?
    var authRequestStatus: HKAuthorizationRequestStatus = .shouldRequest
    var shouldThrowOnAuthStatus: Error?
    var requestedReadTypes: Set<HKObjectType> = []
    var statusReadTypes: Set<HKObjectType> = []

    // Pre-configured statistics results keyed by HKQuantityTypeIdentifier raw value
    var statisticsSums: [String: Double] = [:]
    var statisticsAverages: [String: Double] = [:]
    var statisticsMins: [String: Double] = [:]
    var statisticsMaxes: [String: Double] = [:]
    var statisticsMostRecent: [String: Double] = [:]

    // Pre-configured category sample results
    var categorySampleResults: [String: [CategorySampleValue]] = [:]

    // Pre-configured workout results
    var workoutResults: [WorkoutValue] = []

    // Pre-configured quantity and paired blood pressure sample results
    var quantitySampleResults: [String: [QuantitySampleValue]] = [:]
    var bloodPressureSampleResults: [BloodPressureSampleValue] = []

    // Canonical record fixtures remain arrays so records with identical dates,
    // types, and payloads but distinct HealthKit UUIDs are never collapsed.
    var quantityRecordResults: [String: [HealthKitRecord]] = [:]
    var quantityRecordChildQueryFailures: [String: [HealthKitQueryResult]] = [:]
    var quantityRecordIntegrityWarnings: [String: [HealthKitRecordIntegrityWarning]] = [:]
    var categoryRecordResults: [String: [HealthKitRecord]] = [:]
    var bloodPressureRecordResults: [HealthKitRecord] = []
    var bloodPressureRecordChildQueryFailures: [HealthKitQueryResult] = []
    var bloodPressureRecordIntegrityWarnings: [HealthKitRecordIntegrityWarning] = []
    var foodRecordResults: [HealthKitRecord] = []
    var foodRecordChildQueryFailures: [HealthKitQueryResult] = []
    var foodRecordIntegrityWarnings: [HealthKitRecordIntegrityWarning] = []
    var stateOfMindRecordResults: [HealthKitRecord] = []
    var medicationRecordResult = HealthKitMedicationRecordQueryResult()
    var workoutRecordResult = HealthKitWorkoutRecordQueryResult()
    var scheduledWorkoutPlanRecordResult = HealthKitScheduledWorkoutPlanQueryResult()
    var specializedRecordResult = HealthKitSpecializedRecordQueryResult()
    var attachmentRecordResult: HealthKitAttachmentQueryResult?

    // Pre-configured State of Mind results
    var stateOfMindResults: [StateOfMindSampleValue] = []
    var errorForStateOfMind: Error?

    // Pre-configured medication results
    var medicationResults: [MedicationValue] = []
    var medicationDoseEventResults: [MedicationDoseEventValue] = []
    var medicationAuthRequested = false
    var visionAuthorizationRequested = false
    var visionAuthorizationPredicate: NSPredicate?
    var errorForVisionAuthorization: Error?
    var medicationsQueried = false
    var medicationDoseEventsQueried = false
    var errorForMedicationAuthorization: Error?
    var errorForMedications: Error?
    var errorForMedicationDoseEvents: Error?

    // Per-query error simulation keyed by identifier raw value
    var errorsForSum: [String: Error] = [:]
    var errorsForAverage: [String: Error] = [:]
    var errorsForMin: [String: Error] = [:]
    var errorsForMax: [String: Error] = [:]
    var errorsForMostRecent: [String: Error] = [:]
    var errorsForCategorySamples: [String: Error] = [:]
    var errorsForQuantitySamples: [String: Error] = [:]
    var errorsForQuantityRecords: [String: Error] = [:]
    var errorsForCategoryRecords: [String: Error] = [:]
    var errorForBloodPressureRecords: Error?
    var errorForFoodRecords: Error?
    var errorForStateOfMindRecords: Error?
    var errorForMedicationRecords: Error?
    var errorForWorkoutRecords: Error?
    var errorForBloodPressureSamples: Error?
    var errorForWorkouts: Error?

    // Tracking
    var queriedSumIdentifiers: [String] = []
    var queriedAverageIdentifiers: [String] = []
    var queriedCategoryIdentifiers: [String] = []
    var queriedQuantityRecordIdentifiers: [String] = []
    var queriedCategoryRecordIdentifiers: [String] = []
    var quantityRecordQueries: [(
        identifier: String,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    )] = []
    var categoryRecordQueries: [(
        identifier: String,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    )] = []
    var bloodPressureRecordQueries: [(predicate: NSPredicate?, selectedMetricIDs: [String], limit: Int?)] = []
    var foodRecordQueries: [(predicate: NSPredicate?, selectedMetricIDs: [String], limit: Int?)] = []
    var stateOfMindRecordQueries: [(predicate: NSPredicate?, selectedMetricIDs: [String], limit: Int?)] = []
    var medicationRecordQueries: [(
        predicate: NSPredicate?,
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String],
        limit: Int?
    )] = []
    var workoutRecordQueries: [(
        predicate: NSPredicate?,
        associatedSampleEntries: [HealthKitRecordSelectionPlanEntry],
        selectedMetricIDs: [String],
        limit: Int?
    )] = []
    var scheduledWorkoutPlanRecordQueries: [(
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String]
    )] = []
    var specializedRecordQueries: [(
        predicate: NSPredicate?,
        entries: [HealthKitRecordSelectionPlanEntry],
        interval: HealthKitQueryInterval,
        limit: Int?
    )] = []
    var attachmentRecordQueries: [[HealthKitAttachmentParentReference]] = []
    var bloodPressureSamplesQueried = false

    var isAvailable: Bool { available }
    var supportsHealthRecords = true
    var supportsCDADocuments = true
    var supportsVerifiableClinicalRecords = true
    var supportsVisionPrescriptionAuthorization = true
    var supportsMedicationAuthorization = true
    var supportsScheduledWorkoutPlans = true

    func requestAuth(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        if let error = shouldThrowOnAuth { throw error }
        requestedReadTypes = read
        authRequested = true
    }

    func authorizationRequestStatus(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        if let error = shouldThrowOnAuthStatus { throw error }
        statusReadTypes = read
        return authRequestStatus
    }

    func querySum(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        queriedSumIdentifiers.append(identifier.rawValue)
        if let error = errorsForSum[identifier.rawValue] { throw error }
        return statisticsSums[identifier.rawValue]
    }

    func queryAverage(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        queriedAverageIdentifiers.append(identifier.rawValue)
        if let error = errorsForAverage[identifier.rawValue] { throw error }
        return statisticsAverages[identifier.rawValue]
    }

    func queryMin(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        if let error = errorsForMin[identifier.rawValue] { throw error }
        return statisticsMins[identifier.rawValue]
    }

    func queryMax(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        if let error = errorsForMax[identifier.rawValue] { throw error }
        return statisticsMaxes[identifier.rawValue]
    }

    func queryMostRecent(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        if let error = errorsForMostRecent[identifier.rawValue] { throw error }
        return statisticsMostRecent[identifier.rawValue]
    }

    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [CategorySampleValue] {
        queriedCategoryIdentifiers.append(identifier.rawValue)
        if let error = errorsForCategorySamples[identifier.rawValue] { throw error }
        var results = categorySampleResults[identifier.rawValue] ?? []
        results = ascending ? results.sorted { $0.startDate < $1.startDate } : results.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryWorkouts(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [WorkoutValue] {
        if let error = errorForWorkouts { throw error }
        var results = ascending ? workoutResults.sorted { $0.startDate < $1.startDate } : workoutResults.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryQuantitySamples(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [QuantitySampleValue] {
        if let error = errorsForQuantitySamples[identifier.rawValue] { throw error }
        var results = quantitySampleResults[identifier.rawValue] ?? []
        results = ascending ? results.sorted { $0.startDate < $1.startDate } : results.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryQuantityRecords(
        identifier: HKQuantityTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        queriedQuantityRecordIdentifiers.append(identifier.rawValue)
        quantityRecordQueries.append((identifier.rawValue, predicate, selectedMetricIDs, limit))
        if let error = errorsForQuantityRecords[identifier.rawValue] { throw error }
        let records = Self.limitedCanonicalRecords(
            (quantityRecordResults[identifier.rawValue] ?? []).map {
                $0.withSelectedMetricIDs(selectedMetricIDs)
            },
            limit: limit
        )
        return HealthKitCanonicalRecordQueryResult(
            records: records,
            parentRecordCount: records.count,
            attachmentParents: Self.attachmentParents(for: records),
            childQueryFailures: quantityRecordChildQueryFailures[identifier.rawValue] ?? [],
            integrityWarnings: quantityRecordIntegrityWarnings[identifier.rawValue] ?? []
        )
    }

    func queryCategoryRecords(
        identifier: HKCategoryTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        queriedCategoryRecordIdentifiers.append(identifier.rawValue)
        categoryRecordQueries.append((identifier.rawValue, predicate, selectedMetricIDs, limit))
        if let error = errorsForCategoryRecords[identifier.rawValue] { throw error }
        let records = Self.limitedCanonicalRecords(
            (categoryRecordResults[identifier.rawValue] ?? []).map {
                $0.withSelectedMetricIDs(selectedMetricIDs)
            },
            limit: limit
        )
        return HealthKitCanonicalRecordQueryResult(
            records: records,
            attachmentParents: Self.attachmentParents(for: records)
        )
    }

    func queryBloodPressureRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        bloodPressureRecordQueries.append((predicate, selectedMetricIDs, limit))
        if let error = errorForBloodPressureRecords { throw error }
        let records = Self.limitedCanonicalRecords(
            bloodPressureRecordResults.map { $0.withSelectedMetricIDs(selectedMetricIDs) },
            limit: nil
        )
        let parentCount = records.filter { $0.recordKind == .correlation }.count
        let limitedParentCount = limit.map { min(max(0, $0), parentCount) } ?? parentCount
        return HealthKitCanonicalRecordQueryResult(
            records: records,
            parentRecordCount: limitedParentCount,
            attachmentParents: Self.attachmentParents(for: records),
            childQueryFailures: bloodPressureRecordChildQueryFailures,
            integrityWarnings: bloodPressureRecordIntegrityWarnings
        )
    }

    func queryFoodRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        foodRecordQueries.append((predicate, selectedMetricIDs, limit))
        if let error = errorForFoodRecords { throw error }
        let records = Self.limitedCanonicalRecords(
            foodRecordResults.map { $0.withSelectedMetricIDs(selectedMetricIDs) },
            limit: nil
        )
        let parentCount = records.filter { $0.recordKind == .correlation }.count
        let limitedParentCount = limit.map { min(max(0, $0), parentCount) } ?? parentCount
        return HealthKitCanonicalRecordQueryResult(
            records: records,
            parentRecordCount: limitedParentCount,
            attachmentParents: Self.attachmentParents(for: records),
            childQueryFailures: foodRecordChildQueryFailures,
            integrityWarnings: foodRecordIntegrityWarnings
        )
    }

    func queryStateOfMindRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        stateOfMindRecordQueries.append((predicate, selectedMetricIDs, limit))
        if let error = errorForStateOfMindRecords { throw error }
        let records = Self.limitedCanonicalRecords(
            stateOfMindRecordResults.map { $0.withSelectedMetricIDs(selectedMetricIDs) },
            limit: limit
        )
        return HealthKitCanonicalRecordQueryResult(
            records: records,
            attachmentParents: Self.attachmentParents(for: records)
        )
    }

    func queryWorkoutRecords(
        predicate: NSPredicate?,
        associatedSampleEntries: [HealthKitRecordSelectionPlanEntry],
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitWorkoutRecordQueryResult {
        workoutRecordQueries.append((
            predicate,
            associatedSampleEntries.sorted { $0.objectTypeIdentifier < $1.objectTypeIdentifier },
            selectedMetricIDs,
            limit
        ))
        if let error = errorForWorkoutRecords { throw error }
        let limitedRecords = Self.limitedCanonicalRecords(
            workoutRecordResult.records,
            limit: limit
        )
        return HealthKitWorkoutRecordQueryResult(
            records: limitedRecords,
            externalRecords: workoutRecordResult.externalRecords,
            attachmentParents: workoutRecordResult.attachmentParents.isEmpty
                ? Self.attachmentParents(for: limitedRecords)
                : workoutRecordResult.attachmentParents,
            childQueryResults: workoutRecordResult.childQueryResults,
            integrityWarnings: workoutRecordResult.integrityWarnings
        )
    }

    func queryScheduledWorkoutPlanRecords(
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String]
    ) async -> HealthKitScheduledWorkoutPlanQueryResult {
        scheduledWorkoutPlanRecordQueries.append((interval, selectedMetricIDs))
        return HealthKitScheduledWorkoutPlanQueryResult(
            externalRecords: scheduledWorkoutPlanRecordResult.externalRecords.map {
                $0.attributed(HealthKitMetricAttribution(directMetricIDs: selectedMetricIDs))
            },
            status: scheduledWorkoutPlanRecordResult.status,
            statusDescription: scheduledWorkoutPlanRecordResult.statusDescription,
            childQueryResults: scheduledWorkoutPlanRecordResult.childQueryResults,
            integrityWarnings: scheduledWorkoutPlanRecordResult.integrityWarnings
        )
    }

    func querySpecializedRecords(
        predicate: NSPredicate?,
        entries: [HealthKitRecordSelectionPlanEntry],
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async -> HealthKitSpecializedRecordQueryResult {
        let sortedEntries = entries.sorted { $0.objectTypeIdentifier < $1.objectTypeIdentifier }
        specializedRecordQueries.append((predicate, sortedEntries, interval, limit))
        let enabledMetricIDs = Set(sortedEntries.flatMap(\.metricIDs))
        let entryByIdentifier = Dictionary(
            uniqueKeysWithValues: sortedEntries.map { ($0.objectTypeIdentifier, $0) }
        )

        let filteredRecords = specializedRecordResult.records.compactMap { record -> HealthKitRecord? in
            if let entry = entryByIdentifier[record.objectTypeIdentifier] {
                return record.attributed(entry.attribution)
            }
            guard !Set(record.selectedMetricIDs).isDisjoint(with: enabledMetricIDs) else { return nil }
            return record.attributed(HealthKitMetricAttribution(
                dependencyMetricIDs: record.selectedMetricIDs.filter(enabledMetricIDs.contains)
            ))
        }
        let limitedRecords = Self.limitedCanonicalRecords(filteredRecords, limit: limit)
        let filteredExternalRecords = specializedRecordResult.externalRecords.compactMap {
            record -> HealthKitExternalRecord? in
            if let entry = entryByIdentifier[record.objectTypeIdentifier] {
                return record.attributed(entry.attribution)
            }
            let retainedMetricIDs = record.selectedMetricIDs.filter(enabledMetricIDs.contains)
            guard !retainedMetricIDs.isEmpty else { return nil }
            return record.attributed(HealthKitMetricAttribution(directMetricIDs: retainedMetricIDs))
        }
        let limitedExternalRecords: [HealthKitExternalRecord]
        if let limit {
            limitedExternalRecords = Array(
                HealthKitExternalRecord.sortedDeterministically(filteredExternalRecords)
                    .prefix(max(0, limit))
            )
        } else {
            limitedExternalRecords = HealthKitExternalRecord.sortedDeterministically(filteredExternalRecords)
        }

        var configuredResults = specializedRecordResult.recordQueryResults.filter {
            !$0.metricIDs.isEmpty && !Set($0.metricIDs).isDisjoint(with: enabledMetricIDs)
        }
        let configuredIdentifiers = Set(configuredResults.map(\.objectTypeIdentifier))
        for entry in sortedEntries where !configuredIdentifiers.contains(entry.objectTypeIdentifier) {
            configuredResults.append(HealthKitQueryResult(
                identifier: entry.objectTypeIdentifier,
                objectTypeIdentifier: entry.objectTypeIdentifier,
                operation: "querySpecializedRecords",
                metricIDs: entry.metricIDs,
                metricAttribution: entry.attribution,
                interval: interval,
                status: .success,
                recordCount: limitedRecords.filter {
                    $0.objectTypeIdentifier == entry.objectTypeIdentifier
                }.count + limitedExternalRecords.filter {
                    $0.objectTypeIdentifier == entry.objectTypeIdentifier
                }.count
            ))
        }

        return HealthKitSpecializedRecordQueryResult(
            records: limitedRecords,
            externalRecords: limitedExternalRecords,
            attachmentParents: specializedRecordResult.attachmentParents.isEmpty
                ? Self.attachmentParents(for: limitedRecords)
                : specializedRecordResult.attachmentParents,
            recordQueryResults: configuredResults,
            childQueryFailures: specializedRecordResult.childQueryFailures.filter {
                $0.metricIDs.isEmpty || !Set($0.metricIDs).isDisjoint(with: enabledMetricIDs)
            },
            integrityWarnings: specializedRecordResult.integrityWarnings.filter {
                $0.metricIDs.isEmpty || !Set($0.metricIDs).isDisjoint(with: enabledMetricIDs)
            }
        )
    }

    func queryMedicationDoseEventRecords(
        predicate: NSPredicate?,
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitMedicationRecordQueryResult {
        medicationRecordQueries.append((predicate, interval, selectedMetricIDs, limit))
        if let error = errorForMedicationRecords { throw error }
        let records = Self.limitedCanonicalRecords(
            medicationRecordResult.records.map { $0.withSelectedMetricIDs(selectedMetricIDs) },
            limit: limit
        )
        let inventory = medicationRecordResult.inventoryRecords.map {
            HealthKitMedicationInventoryRecord(
                externalIdentifier: $0.externalIdentifier,
                objectTypeIdentifier: $0.objectTypeIdentifier,
                selectedMetricIDs: selectedMetricIDs,
                includedBecause: $0.includedBecause,
                displayName: $0.displayName,
                fields: $0.fields
            )
        }
        return HealthKitMedicationRecordQueryResult(
            records: records,
            inventoryRecords: inventory,
            attachmentParents: medicationRecordResult.attachmentParents.isEmpty
                ? Self.attachmentParents(for: records)
                : medicationRecordResult.attachmentParents,
            childQueryResults: medicationRecordResult.childQueryResults
        )
    }

    func queryAttachmentRecords(
        parents: [HealthKitAttachmentParentReference],
        interval: HealthKitQueryInterval
    ) async -> HealthKitAttachmentQueryResult {
        attachmentRecordQueries.append(parents)
        if let attachmentRecordResult { return attachmentRecordResult }
        return HealthKitAttachmentQueryResult(queryResults: parents.map { parent in
            HealthKitQueryResult(
                identifier: "\(parent.parentUUID.uuidString):attachments",
                objectTypeIdentifier: "HKAttachment",
                operation: "queryAttachmentMetadata",
                metricIDs: parent.metricAttribution?.metricIDs ?? [],
                metricAttribution: parent.metricAttribution,
                interval: interval,
                status: .success,
                recordCount: 0
            )
        })
    }

    private static func attachmentParents(
        for records: [HealthKitRecord]
    ) -> [HealthKitAttachmentParentReference] {
        records.map {
            HealthKitAttachmentParentReference(
                parentUUID: $0.originalUUID,
                objectTypeIdentifier: $0.objectTypeIdentifier
            )
        }
    }

    private static func limitedCanonicalRecords(
        _ records: [HealthKitRecord],
        limit: Int?
    ) -> [HealthKitRecord] {
        let sorted = HealthKitRecord.sortedDeterministically(records)
        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    func queryBloodPressureSamples(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [BloodPressureSampleValue] {
        bloodPressureSamplesQueried = true
        if let error = errorForBloodPressureSamples { throw error }
        var results = ascending
            ? bloodPressureSampleResults.sorted { $0.startDate < $1.startDate }
            : bloodPressureSampleResults.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryStateOfMind(predicate: NSPredicate?) async throws -> [StateOfMindSampleValue] {
        if let error = errorForStateOfMind { throw error }
        return stateOfMindResults
    }

    func requestVisionPrescriptionAuthorization(predicate: NSPredicate?) async throws {
        if let error = errorForVisionAuthorization { throw error }
        visionAuthorizationPredicate = predicate
        visionAuthorizationRequested = true
    }

    func requestMedicationAuthorization() async throws {
        if let error = errorForMedicationAuthorization { throw error }
        medicationAuthRequested = true
    }

    func queryMedications() async throws -> [MedicationValue] {
        medicationsQueried = true
        if let error = errorForMedications { throw error }
        return medicationResults
    }

    func queryMedicationDoseEvents(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [MedicationDoseEventValue] {
        medicationDoseEventsQueried = true
        if let error = errorForMedicationDoseEvents { throw error }
        var results = medicationDoseEventResults
        results = ascending ? results.sorted { $0.startDate < $1.startDate } : results.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }
}

private extension HealthKitRecord {
    func withSelectedMetricIDs(_ selectedMetricIDs: [String]) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: originalUUID,
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: recordKind,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: startDate,
            endDate: endDate,
            hasUndeterminedDuration: hasUndeterminedDuration,
            sourceRevision: sourceRevision,
            device: device,
            metadata: metadata,
            payload: payload,
            relationships: relationships
        )
    }
}
