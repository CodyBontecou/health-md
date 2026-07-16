//
//  SystemHealthStoreAdapter+CanonicalWorkouts.swift
//  HealthMd
//
//  Lossless, relationship-aware capture of HKWorkout object graphs.
//

@preconcurrency import Foundation
@preconcurrency import HealthKit
@preconcurrency import CoreLocation
#if canImport(WorkoutKit)
import WorkoutKit
#endif

extension SystemHealthStoreAdapter {
    func queryWorkoutRecords(
        predicate: NSPredicate?,
        associatedSampleEntries: [HealthKitRecordSelectionPlanEntry],
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitWorkoutRecordQueryResult {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: limit
        )
        let workouts = try await descriptor.result(for: store)

        var recordsByUUID: [UUID: HealthKitRecord] = [:]
        var externalRecords: [HealthKitExternalRecord] = []
        var attachmentParents: [HealthKitAttachmentParentReference] = []
        var childFailures: [HealthKitQueryResult] = []
        var childResults: [HealthKitQueryResult] = []
        var warnings: [HealthKitRecordIntegrityWarning] = []

        func merge(_ record: HealthKitRecord) {
            if let existing = recordsByUUID[record.originalUUID] {
                recordsByUUID[record.originalUUID] = existing.mergingRepeatedView(record)
            } else {
                recordsByUUID[record.originalUUID] = record
            }
        }

        for workout in workouts {
            let workoutRelationship = HealthKitRecordRelationship(
                targetUUID: workout.uuid,
                role: "workout",
                kind: "associated_with"
            )
            var workoutRelationships: [HealthKitRecordRelationship] = []

            let workoutStatistics = canonicalWorkoutStatistics(workout.allStatistics)
            let activities = canonicalWorkoutActivities(workout.workoutActivities)
            let associated = await canonicalAssociatedWorkoutSamples(
                for: workout,
                entries: associatedSampleEntries,
                selectedMetricIDs: selectedMetricIDs
            )
            for record in associated.records { merge(record) }
            externalRecords.append(contentsOf: associated.externalRecords)
            attachmentParents.append(contentsOf: associated.attachmentParents)
            workoutRelationships.append(contentsOf: associated.workoutRelationships)
            childResults.append(contentsOf: associated.queryResults)
            warnings.append(contentsOf: associated.integrityWarnings)

            // Keep the historical allStatistics discovery path as a forward-
            // compatibility supplement. Catalog planning is authoritative for
            // completeness, but a future quantity type already present in a
            // workout must remain visible as an isolated unknown-type attempt.
            let plannedAssociatedIdentifiers = Set(
                associatedSampleEntries.map(\.objectTypeIdentifier)
            )
            for quantityType in statisticQuantityTypes(
                workoutStatistics: workout.allStatistics,
                activities: workout.workoutActivities
            ) where !plannedAssociatedIdentifiers.contains(quantityType.identifier) {
                let quantityTypeIdentifier = quantityType.identifier
                let canonicalUnit = canonicalWorkoutUnit(for: quantityType)
                do {
                    let sampleDescriptor = HKSampleQueryDescriptor(
                        predicates: [.quantitySample(
                            type: quantityType,
                            predicate: HKQuery.predicateForObjects(from: workout)
                        )],
                        sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
                    )
                    let samples = try await sampleDescriptor.result(for: store)
                    let series: CanonicalQuantitySeriesEnrichmentBatch
                    if let canonicalUnit {
                        series = await canonicalQuantitySeriesEnrichment(
                            for: samples,
                            canonicalUnitsBySampleUUID: Dictionary(
                                uniqueKeysWithValues: samples.map { ($0.uuid, canonicalUnit) }
                            ),
                            selectedMetricIDs: selectedMetricIDs
                        )
                        childFailures.append(contentsOf: series.childQueryFailures)
                        warnings.append(contentsOf: series.integrityWarnings)
                    } else {
                        series = .empty
                        warnings.append(HealthKitRecordIntegrityWarning(
                            code: "workout_unknown_statistic_quantity_type",
                            message: "A workout exposed an uncatalogued statistic quantity type; its associated samples were attempted with raw public quantity descriptions.",
                            metricIDs: selectedMetricIDs,
                            recordUUIDs: [workout.uuid]
                        ))
                    }
                    attachmentParents.append(contentsOf: samples.map {
                        HealthKitAttachmentParentReference(object: $0)
                    })
                    for sample in samples {
                        merge(canonicalWorkoutQuantityRecord(
                            from: sample,
                            canonicalUnit: canonicalUnit,
                            selectedMetricIDs: selectedMetricIDs,
                            series: series.pointsBySampleUUID[sample.uuid]
                        ).attributed(HealthKitMetricAttribution(
                            dependencyMetricIDs: selectedMetricIDs
                        )).addingRelationships([workoutRelationship]))
                        workoutRelationships.append(HealthKitRecordRelationship(
                            targetUUID: sample.uuid,
                            role: "quantity_sample",
                            kind: "contains"
                        ))
                    }
                    childResults.append(HealthKitQueryResult(
                        identifier: "\(workout.uuid.uuidString):associated:\(quantityTypeIdentifier)",
                        objectTypeIdentifier: quantityTypeIdentifier,
                        operation: "queryWorkoutUnknownStatisticSamples",
                        metricIDs: selectedMetricIDs,
                        metricAttribution: HealthKitMetricAttribution(
                            dependencyMetricIDs: selectedMetricIDs
                        ),
                        interval: HealthKitQueryInterval(
                            startDate: workout.startDate,
                            endDate: workout.endDate
                        ),
                        status: .success,
                        recordCount: samples.count,
                        statusDescription: "uncatalogued_statistic_type=true"
                    ))
                } catch {
                    childFailures.append(canonicalWorkoutChildFailure(
                        identifier: "\(workout.uuid.uuidString):associated:\(quantityTypeIdentifier)",
                        objectTypeIdentifier: quantityTypeIdentifier,
                        operation: "queryWorkoutUnknownStatisticSamples",
                        workout: workout,
                        selectedMetricIDs: selectedMetricIDs,
                        error: error
                    ))
                }
            }

            do {
                let routeType = HKSeriesType.workoutRoute()
                let routeDescriptor = HKSampleQueryDescriptor(
                    predicates: [.sample(
                        type: routeType,
                        predicate: HKQuery.predicateForObjects(from: workout)
                    )],
                    sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
                )
                let routes = try await routeDescriptor.result(for: store).compactMap { $0 as? HKWorkoutRoute }

                attachmentParents.append(contentsOf: routes.map {
                    HealthKitAttachmentParentReference(object: $0)
                })
                for route in routes {
                    let routeRelationship = HealthKitRecordRelationship(
                        targetUUID: route.uuid,
                        role: "workout_route",
                        kind: "contains"
                    )
                    workoutRelationships.append(routeRelationship)

                    let locationFields: [HealthKitMetadataValue]
                    do {
                        let routeLocations = try await locations(for: route)
                        locationFields = routeLocations.enumerated().map { index, location in
                            .dictionary(canonicalLocationFields(location, index: index))
                        }
                    } catch {
                        locationFields = []
                        childFailures.append(canonicalWorkoutChildFailure(
                            identifier: "\(workout.uuid.uuidString):route:\(route.uuid.uuidString):locations",
                            objectTypeIdentifier: HealthKitRecordCatalog.workoutRouteTypeIdentifier,
                            operation: "queryWorkoutRouteLocations",
                            workout: workout,
                            childUUID: route.uuid,
                            selectedMetricIDs: selectedMetricIDs,
                            error: error
                        ))
                    }

                    let routeRecord = HealthKitRecord(
                        originalUUID: route.uuid,
                        objectTypeIdentifier: HealthKitRecordCatalog.workoutRouteTypeIdentifier,
                        recordKind: .workoutRoute,
                        selectedMetricIDs: selectedMetricIDs,
                        includedBecause: .relationshipDependency,
                        metricAttribution: HealthKitMetricAttribution(
                            dependencyMetricIDs: selectedMetricIDs
                        ),
                        startDate: route.startDate,
                        endDate: route.endDate,
                        hasUndeterminedDuration: route.hasUndeterminedDuration,
                        sourceRevision: Self.sourceRevision(from: route.sourceRevision),
                        device: Self.deviceProvenance(from: route.device),
                        metadata: Self.typedMetadata(route.metadata),
                        payload: .structured(
                            kind: "workoutRoute",
                            fields: [
                                "locationCount": .unsignedInteger(UInt64(locationFields.count)),
                                "locations": .array(locationFields),
                            ]
                        ),
                        relationships: [workoutRelationship]
                    )
                    merge(routeRecord)
                }
            } catch {
                childFailures.append(canonicalWorkoutChildFailure(
                    identifier: "\(workout.uuid.uuidString):routes",
                    objectTypeIdentifier: HealthKitRecordCatalog.workoutRouteTypeIdentifier,
                    operation: "queryWorkoutRoutes",
                    workout: workout,
                    selectedMetricIDs: selectedMetricIDs,
                    error: error
                ))
            }

            var workoutFields: [String: HealthKitMetadataValue] = [
                "activityTypeRawValue": .unsignedInteger(UInt64(workout.workoutActivityType.rawValue)),
                "durationSeconds": .floatingPoint(workout.duration),
                "isIndoor": canonicalIndoorValue(workout.metadata),
                "events": .array(canonicalWorkoutEvents(workout.workoutEvents ?? [])),
                "activities": .array(activities),
                "allStatistics": .dictionary(workoutStatistics),
            ]
            if let symbolic = WorkoutType.healthKitMapping(
                rawValue: workout.workoutActivityType.rawValue
            ).activityTypeName {
                workoutFields["activityTypeSymbolicValue"] = .string(symbolic)
            }

            #if canImport(WorkoutKit)
            if #available(iOS 17.0, macOS 15.0, macCatalyst 18.0, watchOS 10.0, *) {
                do {
                    if let plan = try await workout.workoutPlan {
                        do {
                            let planValue = try canonicalWorkoutPlanValue(plan)
                            workoutFields["workoutPlan"] = .dictionary(planValue.metadataFields)
                        } catch {
                            childFailures.append(canonicalWorkoutChildFailure(
                                identifier: "\(workout.uuid.uuidString):workoutPlan:dataRepresentation",
                                objectTypeIdentifier: HealthKitRecordCatalog.workoutTypeIdentifier,
                                operation: "serializeWorkoutPlan",
                                workout: workout,
                                selectedMetricIDs: selectedMetricIDs,
                                error: error
                            ))
                        }
                    }
                } catch {
                    childFailures.append(canonicalWorkoutChildFailure(
                        identifier: "\(workout.uuid.uuidString):workoutPlan",
                        objectTypeIdentifier: HealthKitRecordCatalog.workoutTypeIdentifier,
                        operation: "queryWorkoutPlan",
                        workout: workout,
                        selectedMetricIDs: selectedMetricIDs,
                        error: error
                    ))
                }
            } else {
                childResults.append(canonicalWorkoutChildStatus(
                    identifier: "\(workout.uuid.uuidString):workoutPlan",
                    objectTypeIdentifier: HealthKitRecordCatalog.workoutTypeIdentifier,
                    operation: "queryWorkoutPlan",
                    workout: workout,
                    selectedMetricIDs: selectedMetricIDs,
                    status: .unsupported,
                    description: "HKWorkout.workoutPlan is unavailable on this OS version."
                ))
            }
            #else
            childResults.append(canonicalWorkoutChildStatus(
                identifier: "\(workout.uuid.uuidString):workoutPlan",
                objectTypeIdentifier: HealthKitRecordCatalog.workoutTypeIdentifier,
                operation: "queryWorkoutPlan",
                workout: workout,
                selectedMetricIDs: selectedMetricIDs,
                status: .unsupported,
                description: "WorkoutKit is unavailable to this build."
            ))
            #endif

            appendLegacyWorkoutTotals(workout, to: &workoutFields)

            attachmentParents.append(HealthKitAttachmentParentReference(object: workout))
            let workoutRecord = HealthKitRecord(
                originalUUID: workout.uuid,
                objectTypeIdentifier: HealthKitRecordCatalog.workoutTypeIdentifier,
                recordKind: .workout,
                selectedMetricIDs: selectedMetricIDs,
                includedBecause: .selectedMetric,
                metricAttribution: HealthKitMetricAttribution(
                    directMetricIDs: selectedMetricIDs
                ),
                startDate: workout.startDate,
                endDate: workout.endDate,
                hasUndeterminedDuration: workout.hasUndeterminedDuration,
                sourceRevision: Self.sourceRevision(from: workout.sourceRevision),
                device: Self.deviceProvenance(from: workout.device),
                metadata: Self.typedMetadata(workout.metadata),
                payload: .structured(kind: "workout", fields: workoutFields),
                relationships: workoutRelationships
            )
            merge(workoutRecord)
        }

        let effort = await canonicalWorkoutEffortRelationships(
            workouts: workouts,
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs
        )
        for record in effort.sampleRecords { merge(record) }
        attachmentParents.append(contentsOf: effort.attachmentParents)
        for (workoutUUID, relationshipValues) in effort.relationshipValuesByWorkoutUUID {
            guard let workoutRecord = recordsByUUID[workoutUUID] else { continue }
            recordsByUUID[workoutUUID] = workoutRecord
                .addingRelationships(effort.workoutRelationshipsByUUID[workoutUUID] ?? [])
                .addingStructuredPayloadFields([
                    "effortRelationships": .array(relationshipValues),
                ])
        }
        childResults.append(contentsOf: effort.queryResults)
        warnings.append(contentsOf: effort.integrityWarnings)

        return HealthKitWorkoutRecordQueryResult(
            records: Array(recordsByUUID.values),
            externalRecords: externalRecords,
            attachmentParents: attachmentParents,
            childQueryFailures: childFailures,
            childQueryResults: childResults,
            integrityWarnings: warnings
        )
    }

    private struct CanonicalAssociatedWorkoutBatch {
        var records: [HealthKitRecord] = []
        var externalRecords: [HealthKitExternalRecord] = []
        var attachmentParents: [HealthKitAttachmentParentReference] = []
        var workoutRelationships: [HealthKitRecordRelationship] = []
        var queryResults: [HealthKitQueryResult] = []
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    }

    private func canonicalAssociatedWorkoutSamples(
        for workout: HKWorkout,
        entries: [HealthKitRecordSelectionPlanEntry],
        selectedMetricIDs: [String]
    ) async -> CanonicalAssociatedWorkoutBatch {
        let associationPredicate = HKQuery.predicateForObjects(from: workout)
        let workoutRelationship = HealthKitRecordRelationship(
            targetUUID: workout.uuid,
            role: "workout",
            kind: "associated_with"
        )
        let interval = HealthKitQueryInterval(
            startDate: workout.startDate,
            endDate: workout.endDate
        )
        var recordsByUUID: [UUID: HealthKitRecord] = [:]
        var batch = CanonicalAssociatedWorkoutBatch()

        func merge(_ record: HealthKitRecord) {
            if let existing = recordsByUUID[record.originalUUID] {
                recordsByUUID[record.originalUUID] = existing.mergingRepeatedView(record)
            } else {
                recordsByUUID[record.originalUUID] = record
            }
        }

        func link(
            records: [HealthKitRecord],
            entry: HealthKitRecordSelectionPlanEntry
        ) -> Int {
            var directlyAssociatedCount = 0
            for record in records {
                let attributed = record.attributed(entry.attribution)
                guard record.objectTypeIdentifier == entry.objectTypeIdentifier else {
                    merge(attributed)
                    continue
                }
                directlyAssociatedCount += 1
                merge(attributed.addingRelationships([workoutRelationship]))
                let relationship = HealthKitRecordRelationship(
                    targetUUID: record.originalUUID,
                    role: canonicalWorkoutAssociatedRole(record.recordKind),
                    kind: "contains"
                )
                if !batch.workoutRelationships.contains(relationship) {
                    batch.workoutRelationships.append(relationship)
                }
            }
            return directlyAssociatedCount
        }

        for entry in entries
            .filter({ HealthKitRecordCatalog.isWorkoutAssociatedSampleDescriptor($0.descriptor) })
            .sorted(by: { $0.objectTypeIdentifier < $1.objectTypeIdentifier }) {
            let operation = "queryWorkoutAssociatedSamples"
            do {
                let count: Int
                switch entry.recordKind {
                case .quantity:
                    guard let quantityType = HKObjectType.quantityType(
                        forIdentifier: HKQuantityTypeIdentifier(rawValue: entry.objectTypeIdentifier)
                    ) else {
                        batch.queryResults.append(canonicalWorkoutChildStatus(
                            identifier: "\(workout.uuid.uuidString):associated:\(entry.objectTypeIdentifier)",
                            objectTypeIdentifier: entry.objectTypeIdentifier,
                            operation: operation,
                            workout: workout,
                            selectedMetricIDs: selectedMetricIDs,
                            status: .unsupported,
                            description: "The associated quantity type could not be resolved by this SDK/runtime."
                        ))
                        continue
                    }
                    let descriptor = HKSampleQueryDescriptor(
                        predicates: [.quantitySample(
                            type: quantityType,
                            predicate: associationPredicate
                        )],
                        sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
                    )
                    let samples = try await descriptor.result(for: store)
                    batch.attachmentParents.append(contentsOf: samples.map {
                        HealthKitAttachmentParentReference(object: $0)
                    })
                    let canonicalUnit = canonicalWorkoutUnit(for: quantityType)
                    let series: CanonicalQuantitySeriesEnrichmentBatch
                    if let canonicalUnit {
                        series = await canonicalQuantitySeriesEnrichment(
                            for: samples,
                            canonicalUnitsBySampleUUID: Dictionary(
                                uniqueKeysWithValues: samples.map { ($0.uuid, canonicalUnit) }
                            ),
                            selectedMetricIDs: selectedMetricIDs
                        )
                        batch.queryResults.append(contentsOf: series.childQueryFailures.map {
                            canonicalWorkoutContextualResult($0, workout: workout)
                        })
                        batch.integrityWarnings.append(contentsOf: series.integrityWarnings)
                    } else {
                        series = .empty
                        batch.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                            code: "workout_quantity_unit_unavailable",
                            message: "No reviewed canonical unit is available for associated workout quantity type \(entry.objectTypeIdentifier); raw public HealthKit quantity descriptions were retained.",
                            metricIDs: selectedMetricIDs,
                            recordUUIDs: [workout.uuid]
                        ))
                    }
                    count = link(records: samples.map {
                        canonicalWorkoutQuantityRecord(
                            from: $0,
                            canonicalUnit: canonicalUnit,
                            selectedMetricIDs: selectedMetricIDs,
                            series: series.pointsBySampleUUID[$0.uuid]
                        )
                    }, entry: entry)

                case .category:
                    guard let categoryType = HKObjectType.categoryType(
                        forIdentifier: HKCategoryTypeIdentifier(rawValue: entry.objectTypeIdentifier)
                    ) else {
                        batch.queryResults.append(canonicalWorkoutChildStatus(
                            identifier: "\(workout.uuid.uuidString):associated:\(entry.objectTypeIdentifier)",
                            objectTypeIdentifier: entry.objectTypeIdentifier,
                            operation: operation,
                            workout: workout,
                            selectedMetricIDs: selectedMetricIDs,
                            status: .unsupported,
                            description: "The associated category type could not be resolved by this SDK/runtime."
                        ))
                        continue
                    }
                    let descriptor = HKSampleQueryDescriptor(
                        predicates: [.categorySample(
                            type: categoryType,
                            predicate: associationPredicate
                        )],
                        sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
                    )
                    let samples = try await descriptor.result(for: store)
                    batch.attachmentParents.append(contentsOf: samples.map {
                        HealthKitAttachmentParentReference(object: $0)
                    })
                    count = link(records: samples.map {
                        canonicalCategoryRecord(from: $0, selectedMetricIDs: selectedMetricIDs)
                    }, entry: entry)

                case .correlation where entry.objectTypeIdentifier ==
                    HealthKitRecordCatalog.bloodPressureCorrelationIdentifier:
                    let result = try await queryBloodPressureRecords(
                        predicate: associationPredicate,
                        selectedMetricIDs: selectedMetricIDs,
                        limit: nil
                    )
                    count = link(records: result.records, entry: entry)
                    batch.attachmentParents.append(contentsOf: result.attachmentParents)
                    batch.queryResults.append(contentsOf: result.childQueryFailures.map {
                        canonicalWorkoutContextualResult($0, workout: workout)
                    })
                    batch.integrityWarnings.append(contentsOf: result.integrityWarnings)

                case .correlation where entry.objectTypeIdentifier ==
                    HealthKitRecordCatalog.foodCorrelationIdentifier:
                    let result = try await queryFoodRecords(
                        predicate: associationPredicate,
                        selectedMetricIDs: selectedMetricIDs,
                        limit: nil
                    )
                    count = link(records: result.records, entry: entry)
                    batch.attachmentParents.append(contentsOf: result.attachmentParents)
                    batch.queryResults.append(contentsOf: result.childQueryFailures.map {
                        canonicalWorkoutContextualResult($0, workout: workout)
                    })
                    batch.integrityWarnings.append(contentsOf: result.integrityWarnings)

                case .stateOfMind:
                    let result = try await queryStateOfMindRecords(
                        predicate: associationPredicate,
                        selectedMetricIDs: selectedMetricIDs,
                        limit: nil
                    )
                    count = link(records: result.records, entry: entry)
                    batch.attachmentParents.append(contentsOf: result.attachmentParents)

                case .clinical, .electrocardiogram, .audiogram,
                     .heartbeatSeries, .scoredAssessment:
                    let result = await querySpecializedRecords(
                        predicate: associationPredicate,
                        entries: [entry],
                        interval: interval,
                        limit: nil
                    )
                    count = link(records: result.records, entry: entry)
                    batch.externalRecords.append(contentsOf: result.externalRecords)
                    batch.attachmentParents.append(contentsOf: result.attachmentParents)
                    batch.queryResults.append(contentsOf:
                        (result.recordQueryResults + result.childQueryFailures).map {
                            canonicalWorkoutContextualResult($0, workout: workout)
                        }
                    )
                    batch.integrityWarnings.append(contentsOf: result.integrityWarnings)
                    continue

                default:
                    batch.queryResults.append(canonicalWorkoutChildStatus(
                        identifier: "\(workout.uuid.uuidString):associated:\(entry.objectTypeIdentifier)",
                        objectTypeIdentifier: entry.objectTypeIdentifier,
                        operation: operation,
                        workout: workout,
                        selectedMetricIDs: selectedMetricIDs,
                        status: .unsupported,
                        description: "No public canonical associated-sample mapper exists for record kind \(entry.recordKind.rawValue)."
                    ))
                    continue
                }

                batch.queryResults.append(HealthKitQueryResult(
                    identifier: "\(workout.uuid.uuidString):associated:\(entry.objectTypeIdentifier)",
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: operation,
                    metricIDs: selectedMetricIDs,
                    metricAttribution: entry.attribution,
                    interval: interval,
                    status: .success,
                    recordCount: count,
                    statusDescription: "workout_uuid=\(workout.uuid.uuidString)"
                ))
            } catch {
                batch.queryResults.append(canonicalWorkoutChildFailure(
                    identifier: "\(workout.uuid.uuidString):associated:\(entry.objectTypeIdentifier)",
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: operation,
                    workout: workout,
                    selectedMetricIDs: selectedMetricIDs,
                    error: error
                ))
            }
        }

        batch.records = HealthKitRecord.sortedDeterministically(Array(recordsByUUID.values))
        batch.workoutRelationships.sort {
            ($0.targetUUID?.uuidString ?? "") < ($1.targetUUID?.uuidString ?? "")
        }
        return batch
    }

    private struct CanonicalWorkoutEffortBatch {
        var sampleRecords: [HealthKitRecord] = []
        var attachmentParents: [HealthKitAttachmentParentReference] = []
        var workoutRelationshipsByUUID: [UUID: [HealthKitRecordRelationship]] = [:]
        var relationshipValuesByWorkoutUUID: [UUID: [HealthKitMetadataValue]] = [:]
        var queryResults: [HealthKitQueryResult] = []
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    }

    private func canonicalWorkoutEffortRelationships(
        workouts: [HKWorkout],
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async -> CanonicalWorkoutEffortBatch {
        guard !workouts.isEmpty else { return CanonicalWorkoutEffortBatch() }
        let interval = HealthKitQueryInterval(
            startDate: workouts.map(\.startDate).min() ?? workouts[0].startDate,
            endDate: workouts.map(\.endDate).max() ?? workouts[0].endDate
        )
        let selectedWorkoutUUIDs = Set(workouts.map(\.uuid))

        guard #available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, *) else {
            return CanonicalWorkoutEffortBatch(queryResults: [HealthKitQueryResult(
                identifier: HealthKitRecordCatalog.workoutEffortRelationshipIdentifier,
                objectTypeIdentifier: HealthKitRecordCatalog.workoutEffortRelationshipIdentifier,
                operation: "queryWorkoutEffortRelationships",
                metricIDs: selectedMetricIDs,
                metricAttribution: HealthKitMetricAttribution(dependencyMetricIDs: selectedMetricIDs),
                interval: interval,
                status: .unsupported,
                recordCount: 0,
                statusDescription: "HKWorkoutEffortRelationshipQueryDescriptor is unavailable on this OS version."
            )])
        }

        do {
            let option = HKWorkoutEffortRelationshipQueryOptions.default
            let descriptor = HKWorkoutEffortRelationshipQueryDescriptor(
                predicate: predicate,
                anchor: nil,
                option: option
            )
            let result = try await descriptor.result(for: store)
            let relationships = result.relationships.filter {
                selectedWorkoutUUIDs.contains($0.workout.uuid)
            }.sorted { lhs, rhs in
                if lhs.workout.uuid != rhs.workout.uuid {
                    return lhs.workout.uuid.uuidString < rhs.workout.uuid.uuidString
                }
                let lhsActivity = lhs.activity?.uuid.uuidString ?? ""
                let rhsActivity = rhs.activity?.uuid.uuidString ?? ""
                if lhsActivity != rhsActivity { return lhsActivity < rhsActivity }
                let lhsSamples = (lhs.samples ?? []).map(\.uuid.uuidString).sorted()
                let rhsSamples = (rhs.samples ?? []).map(\.uuid.uuidString).sorted()
                return lhsSamples.lexicographicallyPrecedes(rhsSamples)
            }

            let uniqueSamples = Dictionary(
                (relationships.flatMap { $0.samples ?? [] }).map { ($0.uuid, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let quantitySamples = uniqueSamples.values.compactMap { $0 as? HKQuantitySample }
            let unitsByUUID = Dictionary(uniqueKeysWithValues: quantitySamples.compactMap { sample in
                canonicalWorkoutUnit(for: sample.quantityType).map { (sample.uuid, $0) }
            })
            let series = await canonicalQuantitySeriesEnrichment(
                for: quantitySamples,
                canonicalUnitsBySampleUUID: unitsByUUID,
                selectedMetricIDs: selectedMetricIDs
            )

            var recordsByUUID: [UUID: HealthKitRecord] = [:]
            func merge(_ record: HealthKitRecord) {
                if let existing = recordsByUUID[record.originalUUID] {
                    recordsByUUID[record.originalUUID] = existing.mergingRepeatedView(record)
                } else {
                    recordsByUUID[record.originalUUID] = record
                }
            }

            var batch = CanonicalWorkoutEffortBatch(
                attachmentParents: uniqueSamples.values.map {
                    HealthKitAttachmentParentReference(object: $0)
                },
                queryResults: series.childQueryFailures,
                integrityWarnings: series.integrityWarnings
            )
            for relationship in relationships {
                let workoutUUID = relationship.workout.uuid
                let activityUUID = relationship.activity?.uuid
                let samples = (relationship.samples ?? []).sorted {
                    if $0.sampleType.identifier != $1.sampleType.identifier {
                        return $0.sampleType.identifier < $1.sampleType.identifier
                    }
                    return $0.uuid.uuidString < $1.uuid.uuidString
                }
                var sampleValues: [HealthKitMetadataValue] = []

                for sample in samples {
                    var record = canonicalEffortSampleRecord(
                        sample,
                        selectedMetricIDs: selectedMetricIDs,
                        series: series.pointsBySampleUUID[sample.uuid]
                    ).addingRelationships([
                        HealthKitRecordRelationship(
                            targetUUID: workoutUUID,
                            role: "workout",
                            kind: "workout_effort_relationship"
                        ),
                    ])
                    if let activityUUID {
                        record = record.addingRelationships([
                            HealthKitRecordRelationship(
                                targetUUID: activityUUID,
                                role: "workout_activity",
                                kind: "workout_effort_relationship"
                            ),
                        ])
                    }
                    merge(record)

                    let edge = HealthKitRecordRelationship(
                        targetUUID: sample.uuid,
                        role: "effort_sample",
                        kind: "workout_effort_relationship"
                    )
                    if batch.workoutRelationshipsByUUID[workoutUUID]?.contains(edge) != true {
                        batch.workoutRelationshipsByUUID[workoutUUID, default: []].append(edge)
                    }
                    sampleValues.append(.dictionary([
                        "sampleUUID": .string(sample.uuid.uuidString),
                        "objectTypeIdentifier": .string(sample.sampleType.identifier),
                        "sampleSubclass": .string(NSStringFromClass(type(of: sample))),
                    ]))
                }

                batch.relationshipValuesByWorkoutUUID[workoutUUID, default: []].append(.dictionary([
                    "workoutUUID": .string(workoutUUID.uuidString),
                    "workoutActivityUUID": activityUUID.map {
                        .string($0.uuidString)
                    } ?? .null,
                    "samples": .array(sampleValues),
                    "queryOptionRawValue": .signedInteger(Int64(option.rawValue)),
                    "relationshipScope": .string(activityUUID == nil ? "workout" : "workout_activity"),
                ]))
            }

            batch.sampleRecords = HealthKitRecord.sortedDeterministically(Array(recordsByUUID.values))
            for key in batch.workoutRelationshipsByUUID.keys {
                batch.workoutRelationshipsByUUID[key]?.sort {
                    ($0.targetUUID?.uuidString ?? "") < ($1.targetUUID?.uuidString ?? "")
                }
            }
            batch.queryResults.append(HealthKitQueryResult(
                identifier: HealthKitRecordCatalog.workoutEffortRelationshipIdentifier,
                objectTypeIdentifier: HealthKitRecordCatalog.workoutEffortRelationshipIdentifier,
                operation: "queryWorkoutEffortRelationships",
                metricIDs: selectedMetricIDs,
                metricAttribution: HealthKitMetricAttribution(dependencyMetricIDs: selectedMetricIDs),
                interval: interval,
                status: .success,
                recordCount: relationships.count,
                statusDescription: "query_option_raw_value=\(option.rawValue)"
            ))
            return batch
        } catch {
            let nsError = error as NSError
            return CanonicalWorkoutEffortBatch(queryResults: [HealthKitQueryResult(
                identifier: HealthKitRecordCatalog.workoutEffortRelationshipIdentifier,
                objectTypeIdentifier: HealthKitRecordCatalog.workoutEffortRelationshipIdentifier,
                operation: "queryWorkoutEffortRelationships",
                metricIDs: selectedMetricIDs,
                metricAttribution: HealthKitMetricAttribution(dependencyMetricIDs: selectedMetricIDs),
                interval: interval,
                status: Self.isCancellationError(error) ? .cancelled : .failure,
                recordCount: 0,
                error: HealthKitQueryError(error: nsError, isRecoverable: true)
            )])
        }
    }

    private func canonicalEffortSampleRecord(
        _ sample: HKSample,
        selectedMetricIDs: [String],
        series: [HealthKitQuantitySeriesPoint]?
    ) -> HealthKitRecord {
        let attribution = HealthKitMetricAttribution(dependencyMetricIDs: selectedMetricIDs)
        if let quantity = sample as? HKQuantitySample {
            return canonicalWorkoutQuantityRecord(
                from: quantity,
                canonicalUnit: canonicalWorkoutUnit(for: quantity.quantityType),
                selectedMetricIDs: selectedMetricIDs,
                series: series
            ).attributed(attribution)
        }
        if let category = sample as? HKCategorySample {
            return canonicalCategoryRecord(
                from: category,
                selectedMetricIDs: selectedMetricIDs
            ).attributed(attribution)
        }

        let kind = HealthKitRecordCatalog.descriptorByObjectTypeIdentifier[
            sample.sampleType.identifier
        ]?.recordKind ?? .other("unknownSample")
        return HealthKitRecord(
            originalUUID: sample.uuid,
            objectTypeIdentifier: sample.sampleType.identifier,
            recordKind: kind,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .relationshipDependency,
            metricAttribution: attribution,
            startDate: sample.startDate,
            endDate: sample.endDate,
            hasUndeterminedDuration: sample.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
            device: Self.deviceProvenance(from: sample.device),
            metadata: Self.typedMetadata(sample.metadata),
            payload: .structured(kind: "workoutEffortSample", fields: [
                "sampleSubclass": .string(NSStringFromClass(type(of: sample))),
                "objectTypeIdentifier": .string(sample.sampleType.identifier),
            ])
        )
    }

    private func canonicalWorkoutAssociatedRole(_ kind: HealthKitRecordKind) -> String {
        switch kind {
        case .quantity: return "quantity_sample"
        case .category: return "category_sample"
        case .correlation: return "correlation_sample"
        default: return "specialized_sample"
        }
    }

    private func canonicalWorkoutContextualResult(
        _ result: HealthKitQueryResult,
        workout: HKWorkout
    ) -> HealthKitQueryResult {
        let context = "workout_uuid=\(workout.uuid.uuidString)"
        return HealthKitQueryResult(
            identifier: "\(workout.uuid.uuidString):\(result.identifier)",
            objectTypeIdentifier: result.objectTypeIdentifier,
            operation: result.operation,
            metricIDs: result.metricIDs,
            metricAttribution: result.metricAttribution,
            interval: HealthKitQueryInterval(startDate: workout.startDate, endDate: workout.endDate),
            status: result.status,
            recordCount: result.recordCount,
            error: result.error,
            statusDescription: [context, result.statusDescription].compactMap { $0 }.joined(separator: " ")
        )
    }

    private func canonicalWorkoutChildStatus(
        identifier: String,
        objectTypeIdentifier: String,
        operation: String,
        workout: HKWorkout,
        selectedMetricIDs: [String],
        status: HealthKitQueryResultStatus,
        description: String
    ) -> HealthKitQueryResult {
        HealthKitQueryResult(
            identifier: identifier,
            objectTypeIdentifier: objectTypeIdentifier,
            operation: operation,
            metricIDs: selectedMetricIDs,
            metricAttribution: HealthKitMetricAttribution(dependencyMetricIDs: selectedMetricIDs),
            interval: HealthKitQueryInterval(startDate: workout.startDate, endDate: workout.endDate),
            status: status,
            recordCount: 0,
            statusDescription: "workout_uuid=\(workout.uuid.uuidString) \(description)"
        )
    }

    #if canImport(WorkoutKit)
    @available(iOS 17.0, macOS 15.0, macCatalyst 18.0, watchOS 10.0, *)
    func canonicalWorkoutPlanValue(_ plan: WorkoutPlan) throws -> HealthKitWorkoutPlanValue {
        let kind: String
        let displayName: String?
        switch plan.workout {
        case .goal:
            kind = "goal"
            displayName = nil
        case .custom(let workout):
            kind = "custom"
            displayName = workout.displayName
        case .pacer:
            kind = "pacer"
            displayName = nil
        case .swimBikeRun:
            kind = "swimBikeRun"
            displayName = nil
        @unknown default:
            kind = "unknown"
            displayName = nil
        }
        let activityRawValue = plan.workout.activity.rawValue
        return HealthKitWorkoutPlanValue(
            planIdentifier: plan.id,
            workoutKind: kind,
            activityTypeRawValue: UInt64(activityRawValue),
            activityTypeSymbolicValue: WorkoutType.healthKitMapping(
                rawValue: activityRawValue
            ).activityTypeName,
            displayName: displayName,
            dataRepresentation: try plan.dataRepresentation
        )
    }
    #endif

    // MARK: - Workout statistics and activities

    private func statisticQuantityTypes(
        workoutStatistics: [HKQuantityType: HKStatistics],
        activities: [HKWorkoutActivity]
    ) -> [HKQuantityType] {
        var typesByIdentifier = Dictionary(
            uniqueKeysWithValues: workoutStatistics.keys.map { ($0.identifier, $0) }
        )
        for activity in activities {
            for type in activity.allStatistics.keys {
                typesByIdentifier[type.identifier] = type
            }
        }
        return typesByIdentifier.values.sorted { $0.identifier < $1.identifier }
    }

    private func canonicalWorkoutStatistics(
        _ allStatistics: [HKQuantityType: HKStatistics]
    ) -> [String: HealthKitMetadataValue] {
        Dictionary(uniqueKeysWithValues: allStatistics
            .sorted { $0.key.identifier < $1.key.identifier }
            .map { quantityType, statistics in
                (quantityType.identifier, .dictionary(
                    canonicalStatisticsFields(statistics, quantityType: quantityType)
                ))
            }
        )
    }

    private func canonicalStatisticsFields(
        _ statistics: HKStatistics,
        quantityType: HKQuantityType
    ) -> [String: HealthKitMetadataValue] {
        let unit = canonicalWorkoutUnit(for: quantityType)
        var fields: [String: HealthKitMetadataValue] = [
            "quantityTypeIdentifier": .string(quantityType.identifier),
            "startDate": .date(statistics.startDate),
            "endDate": .date(statistics.endDate),
        ]
        if let unit {
            fields["canonicalUnit"] = .string(unit.unitString)
        }
        appendQuantity(statistics.sumQuantity(), key: "sum", unit: unit, to: &fields)
        appendQuantity(statistics.averageQuantity(), key: "average", unit: unit, to: &fields)
        appendQuantity(statistics.minimumQuantity(), key: "minimum", unit: unit, to: &fields)
        appendQuantity(statistics.maximumQuantity(), key: "maximum", unit: unit, to: &fields)
        appendQuantity(statistics.mostRecentQuantity(), key: "mostRecent", unit: unit, to: &fields)
        appendQuantity(statistics.duration(), key: "duration", unit: .second(), to: &fields)
        if let interval = statistics.mostRecentQuantityDateInterval() {
            fields["mostRecentDateInterval"] = .dictionary(canonicalDateInterval(interval))
        }

        let sources = (statistics.sources ?? []).sorted {
            if $0.bundleIdentifier != $1.bundleIdentifier {
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            return $0.name < $1.name
        }.map { source -> HealthKitMetadataValue in
            var sourceFields: [String: HealthKitMetadataValue] = [
                "name": .string(source.name),
                "bundleIdentifier": .string(source.bundleIdentifier),
            ]
            appendQuantity(statistics.sumQuantity(for: source), key: "sum", unit: unit, to: &sourceFields)
            appendQuantity(statistics.averageQuantity(for: source), key: "average", unit: unit, to: &sourceFields)
            appendQuantity(statistics.minimumQuantity(for: source), key: "minimum", unit: unit, to: &sourceFields)
            appendQuantity(statistics.maximumQuantity(for: source), key: "maximum", unit: unit, to: &sourceFields)
            appendQuantity(statistics.mostRecentQuantity(for: source), key: "mostRecent", unit: unit, to: &sourceFields)
            appendQuantity(statistics.duration(for: source), key: "duration", unit: .second(), to: &sourceFields)
            if let interval = statistics.mostRecentQuantityDateInterval(for: source) {
                sourceFields["mostRecentDateInterval"] = .dictionary(canonicalDateInterval(interval))
            }
            return .dictionary(sourceFields)
        }
        if !sources.isEmpty {
            fields["sources"] = .array(sources)
        }
        return fields
    }

    private func canonicalWorkoutActivities(
        _ activities: [HKWorkoutActivity]
    ) -> [HealthKitMetadataValue] {
        activities.map { activity in
            let configuration = activity.workoutConfiguration
            var configurationFields: [String: HealthKitMetadataValue] = [
                "activityTypeRawValue": .unsignedInteger(UInt64(configuration.activityType.rawValue)),
                "locationTypeRawValue": .signedInteger(Int64(configuration.locationType.rawValue)),
                "swimmingLocationTypeRawValue": .signedInteger(Int64(configuration.swimmingLocationType.rawValue)),
            ]
            if let symbolic = WorkoutType.healthKitMapping(
                rawValue: configuration.activityType.rawValue
            ).activityTypeName {
                configurationFields["activityTypeSymbolicValue"] = .string(symbolic)
            }
            if let symbolic = workoutLocationTypeSymbolic(configuration.locationType) {
                configurationFields["locationTypeSymbolicValue"] = .string(symbolic)
            }
            if let symbolic = swimmingLocationTypeSymbolic(configuration.swimmingLocationType) {
                configurationFields["swimmingLocationTypeSymbolicValue"] = .string(symbolic)
            }
            if let lapLength = configuration.lapLength {
                configurationFields["lapLength"] = canonicalQuantity(
                    lapLength,
                    unit: .meter()
                )
            }

            var fields: [String: HealthKitMetadataValue] = [
                "originalUUID": .string(activity.uuid.uuidString),
                "workoutConfiguration": .dictionary(configurationFields),
                "startDate": .date(activity.startDate),
                "durationSeconds": .floatingPoint(activity.duration),
                "metadata": .dictionary(Self.typedMetadata(activity.metadata)),
                "events": .array(canonicalWorkoutEvents(activity.workoutEvents)),
                "allStatistics": .dictionary(canonicalWorkoutStatistics(activity.allStatistics)),
            ]
            fields["endDate"] = activity.endDate.map(HealthKitMetadataValue.date) ?? .null
            return .dictionary(fields)
        }
    }

    private func canonicalWorkoutEvents(
        _ events: [HKWorkoutEvent]
    ) -> [HealthKitMetadataValue] {
        events.map { event in
            var fields: [String: HealthKitMetadataValue] = [
                "typeRawValue": .signedInteger(Int64(event.type.rawValue)),
                "dateInterval": .dictionary(canonicalDateInterval(event.dateInterval)),
                "metadata": .dictionary(Self.typedMetadata(event.metadata)),
            ]
            if let symbolic = workoutEventTypeSymbolic(event.type) {
                fields["typeSymbolicValue"] = .string(symbolic)
            }
            return .dictionary(fields)
        }
    }

    private func canonicalDateInterval(_ interval: DateInterval) -> [String: HealthKitMetadataValue] {
        [
            "startDate": .date(interval.start),
            "endDate": .date(interval.end),
            "durationSeconds": .floatingPoint(interval.duration),
        ]
    }

    private func appendLegacyWorkoutTotals(
        _ workout: HKWorkout,
        to fields: inout [String: HealthKitMetadataValue]
    ) {
        appendQuantity(workout.totalEnergyBurned, key: "totalEnergyBurned", unit: .kilocalorie(), to: &fields)
        appendQuantity(workout.totalDistance, key: "totalDistance", unit: .meter(), to: &fields)
        appendQuantity(workout.totalSwimmingStrokeCount, key: "totalSwimmingStrokeCount", unit: .count(), to: &fields)
        appendQuantity(workout.totalFlightsClimbed, key: "totalFlightsClimbed", unit: .count(), to: &fields)
    }

    private func appendQuantity(
        _ quantity: HKQuantity?,
        key: String,
        unit: HKUnit?,
        to fields: inout [String: HealthKitMetadataValue]
    ) {
        guard let quantity else { return }
        fields[key] = canonicalQuantity(quantity, unit: unit)
    }

    private func canonicalQuantity(
        _ quantity: HKQuantity,
        unit: HKUnit?
    ) -> HealthKitMetadataValue {
        let rawDescription = quantity.description
        guard let unit, quantity.is(compatibleWith: unit) else {
            return .quantity(HealthKitMetadataQuantity(rawDescription: rawDescription))
        }
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite else {
            return .quantity(HealthKitMetadataQuantity(rawDescription: rawDescription))
        }
        return .quantity(HealthKitMetadataQuantity(
            value: value,
            unit: unit.unitString,
            rawDescription: rawDescription
        ))
    }

    private func canonicalWorkoutUnit(for type: HKQuantityType) -> HKUnit? {
        unitMap[HKQuantityTypeIdentifier(rawValue: type.identifier)]
    }

    func canonicalWorkoutQuantityRecord(
        from sample: HKQuantitySample,
        canonicalUnit: HKUnit?,
        selectedMetricIDs: [String],
        series: [HealthKitQuantitySeriesPoint]? = nil
    ) -> HealthKitRecord {
        if let canonicalUnit {
            return canonicalQuantityRecord(
                from: sample,
                canonicalUnit: canonicalUnit,
                selectedMetricIDs: selectedMetricIDs,
                series: series
            ).attributed(HealthKitMetricAttribution(
                dependencyMetricIDs: selectedMetricIDs
            ))
        }
        return HealthKitRecord(
            originalUUID: sample.uuid,
            objectTypeIdentifier: sample.quantityType.identifier,
            recordKind: .quantity,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .relationshipDependency,
            startDate: sample.startDate,
            endDate: sample.endDate,
            hasUndeterminedDuration: sample.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
            device: Self.deviceProvenance(from: sample.device),
            metadata: Self.typedMetadata(sample.metadata),
            payload: .structured(kind: "quantity", fields: [
                "quantityTypeIdentifier": .string(sample.quantityType.identifier),
                "sampleSubclass": .string(NSStringFromClass(type(of: sample))),
                "sampleKind": .string(sample is HKDiscreteQuantitySample ? "discrete" : (sample is HKCumulativeQuantitySample ? "cumulative" : "quantity")),
                "count": .signedInteger(Int64(sample.count)),
                "rawQuantityDescription": .string(sample.quantity.description),
            ])
        )
    }

    // MARK: - Route locations

    private func canonicalLocationFields(
        _ location: CLLocation,
        index: Int
    ) -> [String: HealthKitMetadataValue] {
        var fields: [String: HealthKitMetadataValue] = [
            "index": .unsignedInteger(UInt64(index)),
            "timestamp": .date(location.timestamp),
            "latitude": .floatingPoint(location.coordinate.latitude),
            "longitude": .floatingPoint(location.coordinate.longitude),
            "altitudeMeters": .floatingPoint(location.altitude),
            "horizontalAccuracyMeters": .floatingPoint(location.horizontalAccuracy),
            "verticalAccuracyMeters": .floatingPoint(location.verticalAccuracy),
            "courseDegrees": .floatingPoint(location.course),
            "speedMetersPerSecond": .floatingPoint(location.speed),
        ]
        if #available(iOS 13.4, macOS 10.15.4, macCatalyst 13.4, watchOS 6.2, *) {
            fields["courseAccuracyDegrees"] = .floatingPoint(location.courseAccuracy)
        }
        if #available(iOS 10.0, macOS 10.15, macCatalyst 13.0, watchOS 3.0, *) {
            fields["speedAccuracyMetersPerSecond"] = .floatingPoint(location.speedAccuracy)
        }
        if #available(iOS 15.0, macOS 12.0, macCatalyst 15.0, watchOS 8.0, *) {
            fields["ellipsoidalAltitudeMeters"] = .floatingPoint(location.ellipsoidalAltitude)
            if let source = location.sourceInformation {
                fields["sourceInformation"] = .dictionary([
                    "isSimulatedBySoftware": .bool(source.isSimulatedBySoftware),
                    "isProducedByAccessory": .bool(source.isProducedByAccessory),
                ])
            }
        }
        if let floor = location.floor {
            fields["floorLevel"] = .signedInteger(Int64(floor.level))
        }
        return fields
    }

    // MARK: - Diagnostics and enum symbols

    private func canonicalWorkoutChildFailure(
        identifier: String,
        objectTypeIdentifier: String,
        operation: String,
        workout: HKWorkout,
        childUUID: UUID? = nil,
        selectedMetricIDs: [String],
        error: Error
    ) -> HealthKitQueryResult {
        let nsError = error as NSError
        let suffix = childUUID.map { " child_uuid=\($0.uuidString)" } ?? ""
        return HealthKitQueryResult(
            identifier: identifier,
            objectTypeIdentifier: objectTypeIdentifier,
            operation: operation,
            metricIDs: selectedMetricIDs,
            metricAttribution: HealthKitMetricAttribution(
                dependencyMetricIDs: selectedMetricIDs
            ),
            interval: HealthKitQueryInterval(
                startDate: workout.startDate,
                endDate: workout.endDate
            ),
            status: .failure,
            recordCount: 0,
            error: HealthKitQueryError(error: nsError, isRecoverable: true),
            statusDescription: "workout_uuid=\(workout.uuid.uuidString)\(suffix)"
        )
    }

    private func canonicalIndoorValue(_ metadata: [String: Any]?) -> HealthKitMetadataValue {
        if let number = metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber {
            return .bool(number.boolValue)
        }
        if let bool = metadata?[HKMetadataKeyIndoorWorkout] as? Bool {
            return .bool(bool)
        }
        return .null
    }

    private func workoutEventTypeSymbolic(_ type: HKWorkoutEventType) -> String? {
        switch type {
        case .pause: return "pause"
        case .resume: return "resume"
        case .lap: return "lap"
        case .marker: return "marker"
        case .motionPaused: return "motionPaused"
        case .motionResumed: return "motionResumed"
        case .segment: return "segment"
        case .pauseOrResumeRequest: return "pauseOrResumeRequest"
        @unknown default: return nil
        }
    }

    private func workoutLocationTypeSymbolic(
        _ type: HKWorkoutSessionLocationType
    ) -> String? {
        switch type {
        case .unknown: return "unknown"
        case .indoor: return "indoor"
        case .outdoor: return "outdoor"
        @unknown default: return nil
        }
    }

    private func swimmingLocationTypeSymbolic(
        _ type: HKWorkoutSwimmingLocationType
    ) -> String? {
        switch type {
        case .unknown: return "unknown"
        case .pool: return "pool"
        case .openWater: return "openWater"
        @unknown default: return nil
        }
    }
}
