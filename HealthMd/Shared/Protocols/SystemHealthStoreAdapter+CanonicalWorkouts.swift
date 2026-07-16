//
//  SystemHealthStoreAdapter+CanonicalWorkouts.swift
//  HealthMd
//
//  Lossless, relationship-aware capture of HKWorkout object graphs.
//

@preconcurrency import Foundation
@preconcurrency import HealthKit
@preconcurrency import CoreLocation

extension SystemHealthStoreAdapter {
    func queryWorkoutRecords(
        predicate: NSPredicate?,
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
        var childFailures: [HealthKitQueryResult] = []
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
            let statisticTypes = statisticQuantityTypes(
                workoutStatistics: workout.allStatistics,
                activities: workout.workoutActivities
            )

            for quantityType in statisticTypes {
                let quantityTypeIdentifier = quantityType.identifier
                let canonicalUnit = canonicalWorkoutUnit(for: quantityType)
                if canonicalUnit == nil {
                    warnings.append(HealthKitRecordIntegrityWarning(
                        code: "workout_quantity_unit_unavailable",
                        message: "No reviewed canonical unit is available for workout statistic type \(quantityTypeIdentifier); raw public HealthKit quantity descriptions were retained.",
                        metricIDs: selectedMetricIDs,
                        recordUUIDs: [workout.uuid]
                    ))
                }

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
                    }
                    for sample in samples {
                        let sampleRecord = canonicalWorkoutQuantityRecord(
                            from: sample,
                            canonicalUnit: canonicalUnit,
                            selectedMetricIDs: selectedMetricIDs,
                            series: series.pointsBySampleUUID[sample.uuid]
                        ).attributed(HealthKitMetricAttribution(
                            dependencyMetricIDs: selectedMetricIDs
                        )).addingRelationships([workoutRelationship])
                        merge(sampleRecord)
                        workoutRelationships.append(HealthKitRecordRelationship(
                            targetUUID: sample.uuid,
                            role: "quantity_sample",
                            kind: "contains"
                        ))
                    }
                } catch {
                    childFailures.append(canonicalWorkoutChildFailure(
                        identifier: "\(workout.uuid.uuidString):statistics:\(quantityTypeIdentifier)",
                        objectTypeIdentifier: quantityTypeIdentifier,
                        operation: "queryWorkoutStatisticSamples",
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
            appendLegacyWorkoutTotals(workout, to: &workoutFields)

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

        return HealthKitWorkoutRecordQueryResult(
            records: Array(recordsByUUID.values),
            childQueryFailures: childFailures,
            integrityWarnings: warnings
        )
    }

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
