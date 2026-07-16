//
//  SystemHealthStoreAdapter.swift
//  HealthMd
//
//  Production adapter wrapping HKHealthStore behind HealthStoreProviding.
//  Used as the default backend for HealthKitManager.
//

@preconcurrency import Foundation
@preconcurrency import HealthKit
@preconcurrency import CoreLocation
import os.log

final class SystemHealthStoreAdapter: HealthStoreProviding, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "HealthKitExport")
    let store: HKHealthStore

    /// Canonical unit for each quantity type used by this app.
    /// When the adapter returns a Double from a statistics query, it uses this unit.
    /// Internal (not private) so tests can verify completeness.
    let unitMap: [HKQuantityTypeIdentifier: HKUnit] = [
        .stepCount:                     .count(),
        .activeEnergyBurned:            .kilocalorie(),
        .basalEnergyBurned:             .kilocalorie(),
        .appleExerciseTime:             .minute(),
        .appleStandTime:                .minute(),
        .flightsClimbed:                .count(),
        .distanceWalkingRunning:        .meter(),
        .distanceCycling:               .meter(),
        .distanceSwimming:              .meter(),
        .swimmingStrokeCount:           .count(),
        .pushCount:                     .count(),
        .heartRate:                     HKUnit.count().unitDivided(by: .minute()),
        .restingHeartRate:              HKUnit.count().unitDivided(by: .minute()),
        .walkingHeartRateAverage:       HKUnit.count().unitDivided(by: .minute()),
        .heartRateVariabilitySDNN:      .secondUnit(with: .milli),
        .vo2Max:                        HKUnits.vo2Max,
        .respiratoryRate:               HKUnit.count().unitDivided(by: .minute()),
        .oxygenSaturation:              .percent(),
        .bodyTemperature:               .degreeCelsius(),
        .bloodPressureSystolic:         .millimeterOfMercury(),
        .bloodPressureDiastolic:        .millimeterOfMercury(),
        .bloodGlucose:                  HKUnits.milligramsPerDeciliter,
        .bodyMass:                      .gramUnit(with: .kilo),
        .height:                        .meter(),
        .bodyMassIndex:                 .count(),
        .bodyFatPercentage:             .percent(),
        .leanBodyMass:                  .gramUnit(with: .kilo),
        .waistCircumference:            .meter(),
        .dietaryEnergyConsumed:         .kilocalorie(),
        .dietaryProtein:                .gram(),
        .dietaryCarbohydrates:          .gram(),
        .dietaryFatTotal:               .gram(),
        .dietaryFatSaturated:           .gram(),
        .dietaryFiber:                  .gram(),
        .dietarySugar:                  .gram(),
        .dietarySodium:                 .gramUnit(with: .milli),
        .dietaryCholesterol:            .gramUnit(with: .milli),
        .dietaryWater:                  .liter(),
        .dietaryCaffeine:               .gramUnit(with: .milli),
        .walkingSpeed:                  HKUnit.meter().unitDivided(by: .second()),
        .walkingStepLength:             .meter(),
        .walkingDoubleSupportPercentage: .percent(),
        .walkingAsymmetryPercentage:    .percent(),
        .stairAscentSpeed:              HKUnit.meter().unitDivided(by: .second()),
        .stairDescentSpeed:             HKUnit.meter().unitDivided(by: .second()),
        .sixMinuteWalkTestDistance:     .meter(),
        .headphoneAudioExposure:        .decibelAWeightedSoundPressureLevel(),
        .environmentalAudioExposure:    .decibelAWeightedSoundPressureLevel(),

        // Activity (extended)
        .distanceWheelchair:            .meter(),
        .distanceDownhillSnowSports:    .meter(),
        .appleMoveTime:                 .minute(),
        .physicalEffort:                HKUnit(from: "kcal/hr·kg"),

        // Heart (extended)
        .heartRateRecoveryOneMinute:    HKUnit.count().unitDivided(by: .minute()),
        .atrialFibrillationBurden:      .percent(),

        // Vitals / Respiratory (extended)
        .basalBodyTemperature:          .degreeCelsius(),
        .appleSleepingWristTemperature: .degreeCelsius(),
        .electrodermalActivity:         HKUnit(from: "µS"),
        .forcedVitalCapacity:           .liter(),
        .forcedExpiratoryVolume1:       .liter(),
        .peakExpiratoryFlowRate:        HKUnit.liter().unitDivided(by: .minute()),
        .inhalerUsage:                  .count(),

        // Mobility (extended)
        .appleWalkingSteadiness:        .percent(),
        .runningSpeed:                  HKUnit.meter().unitDivided(by: .second()),
        .runningStrideLength:           .meter(),
        .runningGroundContactTime:      HKUnit.secondUnit(with: .milli),
        .runningVerticalOscillation:    .meterUnit(with: .centi),
        .runningPower:                  .watt(),

        // Cycling performance
        .cyclingSpeed:                  HKUnit.meter().unitDivided(by: .second()),
        .cyclingPower:                  .watt(),
        .cyclingCadence:                HKUnit.count().unitDivided(by: .minute()),
        .cyclingFunctionalThresholdPower: .watt(),

        // Nutrition (extended)
        .dietaryFatMonounsaturated:     .gram(),
        .dietaryFatPolyunsaturated:     .gram(),

        // Vitamins
        .dietaryVitaminA:               .gramUnit(with: .micro),
        .dietaryVitaminB6:              .gramUnit(with: .milli),
        .dietaryVitaminB12:             .gramUnit(with: .micro),
        .dietaryVitaminC:               .gramUnit(with: .milli),
        .dietaryVitaminD:               .gramUnit(with: .micro),
        .dietaryVitaminE:               .gramUnit(with: .milli),
        .dietaryVitaminK:               .gramUnit(with: .micro),
        .dietaryThiamin:                .gramUnit(with: .milli),
        .dietaryRiboflavin:             .gramUnit(with: .milli),
        .dietaryNiacin:                 .gramUnit(with: .milli),
        .dietaryFolate:                 .gramUnit(with: .micro),
        .dietaryBiotin:                 .gramUnit(with: .micro),
        .dietaryPantothenicAcid:        .gramUnit(with: .milli),

        // Minerals
        .dietaryCalcium:                .gramUnit(with: .milli),
        .dietaryIron:                   .gramUnit(with: .milli),
        .dietaryPotassium:              .gramUnit(with: .milli),
        .dietaryMagnesium:              .gramUnit(with: .milli),
        .dietaryPhosphorus:             .gramUnit(with: .milli),
        .dietaryZinc:                   .gramUnit(with: .milli),
        .dietarySelenium:               .gramUnit(with: .micro),
        .dietaryCopper:                 .gramUnit(with: .milli),
        .dietaryManganese:              .gramUnit(with: .milli),
        .dietaryChromium:               .gramUnit(with: .micro),
        .dietaryMolybdenum:             .gramUnit(with: .micro),
        .dietaryChloride:               .gramUnit(with: .milli),
        .dietaryIodine:                 .gramUnit(with: .micro),

        // Other
        .uvExposure:                    .count(),
        .timeInDaylight:                .minute(),
        .numberOfTimesFallen:           .count(),
        .bloodAlcoholContent:           .percent(),
        .numberOfAlcoholicBeverages:    .count(),
        .insulinDelivery:               .internationalUnit(),
        .waterTemperature:              .degreeCelsius(),
        .underwaterDepth:               .meter(),
    ]

    nonisolated init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var supportsMedicationAuthorization: Bool {
        if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *) {
            return true
        }
        return false
    }

    func requestAuth(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: toShare, read: read)
    }

    func authorizationRequestStatus(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        try await store.statusForAuthorizationRequest(toShare: toShare, read: read)
    }

    // MARK: - Statistics Queries

    private func unit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        unitMap[identifier] ?? .count()
    }

    func querySum(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        guard let result = try await descriptor.result(for: store),
              let sum = result.sumQuantity() else { return nil }
        return sum.doubleValue(for: unit(for: identifier))
    }

    func queryAverage(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        guard let result = try await descriptor.result(for: store),
              let avg = result.averageQuantity() else { return nil }
        return avg.doubleValue(for: unit(for: identifier))
    }

    func queryMin(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteMin
        )
        guard let result = try await descriptor.result(for: store),
              let min = result.minimumQuantity() else { return nil }
        return min.doubleValue(for: unit(for: identifier))
    }

    func queryMax(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteMax
        )
        guard let result = try await descriptor.result(for: store),
              let max = result.maximumQuantity() else { return nil }
        return max.doubleValue(for: unit(for: identifier))
    }

    func queryMostRecent(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit(for: identifier))
    }

    // MARK: - Category Sample Queries

    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [CategorySampleValue] {
        guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { return [] }
        let order: SortOrder = ascending ? .forward : .reverse
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: order)],
            limit: limit
        )
        let samples = try await descriptor.result(for: store)
        return samples.map {
            CategorySampleValue(
                value: $0.value,
                startDate: $0.startDate,
                endDate: $0.endDate,
                metadata: Self.serializedMetadata($0.metadata)
            )
        }
    }

    // MARK: - Canonical Quantity and Category Record Queries

    func queryQuantityRecords(
        identifier: HKQuantityTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let canonicalUnit = unit(for: identifier)
        let records = try await descriptor.result(for: store).map { sample in
            canonicalQuantityRecord(
                from: sample,
                canonicalUnit: canonicalUnit,
                selectedMetricIDs: selectedMetricIDs
            )
        }
        return Self.limitedCanonicalRecords(records, limit: limit)
    }

    func queryCategoryRecords(
        identifier: HKCategoryTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord] {
        guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let records = try await descriptor.result(for: store).map { sample in
            canonicalCategoryRecord(from: sample, selectedMetricIDs: selectedMetricIDs)
        }
        return Self.limitedCanonicalRecords(records, limit: limit)
    }

    /// Maps while the HealthKit object is still in scope so no identity,
    /// provenance, device, or typed metadata fields are flattened first.
    func canonicalQuantityRecord(
        from sample: HKQuantitySample,
        canonicalUnit: HKUnit,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: sample.uuid,
            objectTypeIdentifier: sample.quantityType.identifier,
            recordKind: .quantity,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: sample.startDate,
            endDate: sample.endDate,
            hasUndeterminedDuration: sample.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
            device: Self.deviceProvenance(from: sample.device),
            metadata: Self.typedMetadata(sample.metadata, sampleQuantityUnit: canonicalUnit),
            payload: .quantity(HealthKitQuantityPayload(
                value: sample.quantity.doubleValue(for: canonicalUnit),
                unit: canonicalUnit.unitString
            ))
        )
    }

    /// Category values intentionally remain raw. Their symbolic enum depends on
    /// the exact category type and can be interpreted by a later typed layer.
    func canonicalCategoryRecord(
        from sample: HKCategorySample,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: sample.uuid,
            objectTypeIdentifier: sample.categoryType.identifier,
            recordKind: .category,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: sample.startDate,
            endDate: sample.endDate,
            hasUndeterminedDuration: sample.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
            device: Self.deviceProvenance(from: sample.device),
            metadata: Self.typedMetadata(sample.metadata),
            payload: .category(HealthKitCategoryPayload(
                rawValue: Int64(sample.value),
                symbolicValue: nil
            ))
        )
    }

    private static func limitedCanonicalRecords(
        _ records: [HealthKitRecord],
        limit: Int?
    ) -> [HealthKitRecord] {
        let sorted = HealthKitRecord.sortedDeterministically(records)
        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    static func sourceRevision(from revision: HKSourceRevision) -> HealthKitSourceRevision {
        let operatingSystem = revision.operatingSystemVersion
        return HealthKitSourceRevision(
            name: revision.source.name,
            bundleIdentifier: revision.source.bundleIdentifier,
            version: revision.version,
            productType: revision.productType,
            operatingSystemVersion: HealthKitOperatingSystemVersion(
                majorVersion: operatingSystem.majorVersion,
                minorVersion: operatingSystem.minorVersion,
                patchVersion: operatingSystem.patchVersion
            )
        )
    }

    static func deviceProvenance(from device: HKDevice?) -> HealthKitDeviceProvenance? {
        guard let device else { return nil }
        return HealthKitDeviceProvenance(
            name: device.name,
            manufacturer: device.manufacturer,
            model: device.model,
            hardwareVersion: device.hardwareVersion,
            firmwareVersion: device.firmwareVersion,
            softwareVersion: device.softwareVersion,
            localIdentifier: device.localIdentifier,
            udiDeviceIdentifier: device.udiDeviceIdentifier
        )
    }

    // MARK: - Workout Queries

    func queryWorkouts(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [WorkoutValue] {
        let order: SortOrder = ascending ? .forward : .reverse
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: order)],
            limit: limit
        )
        let workouts = try await descriptor.result(for: store)

        var results: [WorkoutValue] = []
        results.reserveCapacity(workouts.count)
        for w in workouts {
            let workoutPredicate = HKQuery.predicateForObjects(from: w)
            let workoutRange = Self.rangeDescription(start: w.startDate, end: w.endDate)

            func fetchOptional<T>(_ context: String, operation: () async throws -> T?) async -> T? {
                do {
                    return try await operation()
                } catch {
                    Self.logger.warning("HealthKit workout detail fetch failed for \(context, privacy: .public) workoutRange=\(workoutRange, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }

            func fetchArray<T>(_ context: String, operation: () async throws -> [T]) async -> [T] {
                do {
                    return try await operation()
                } catch {
                    Self.logger.warning("HealthKit workout detail fetch failed for \(context, privacy: .public) workoutRange=\(workoutRange, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return []
                }
            }

            let hrStats = await fetchOptional("heart rate stats") {
                try await fetchHeartRateStats(for: w)
            }

            var avgRunningCadence: Double?
            var avgStrideLength: Double?
            var avgGroundContactTime: Double?
            var avgVerticalOscillation: Double?
            var avgCyclingCadence: Double?
            var avgPower: Double?
            var maxPower: Double?

            switch w.workoutActivityType {
            case .running:
                avgStrideLength = await fetchOptional("running stride length") {
                    try await queryAverage(identifier: .runningStrideLength, predicate: workoutPredicate)
                }
                avgGroundContactTime = await fetchOptional("running ground contact time") {
                    try await queryAverage(identifier: .runningGroundContactTime, predicate: workoutPredicate)
                }
                avgVerticalOscillation = await fetchOptional("running vertical oscillation") {
                    try await queryAverage(identifier: .runningVerticalOscillation, predicate: workoutPredicate)
                }
                avgPower = await fetchOptional("running power average") {
                    try await queryAverage(identifier: .runningPower, predicate: workoutPredicate)
                }
                maxPower = await fetchOptional("running power max") {
                    try await queryMax(identifier: .runningPower, predicate: workoutPredicate)
                }
                let steps = await fetchOptional("running step count") {
                    try await querySum(identifier: .stepCount, predicate: workoutPredicate)
                }
                if let steps, steps > 0, w.duration > 0 {
                    avgRunningCadence = steps / (w.duration / 60.0)
                }
            case .cycling:
                avgCyclingCadence = await fetchOptional("cycling cadence average") {
                    try await queryAverage(identifier: .cyclingCadence, predicate: workoutPredicate)
                }
                avgPower = await fetchOptional("cycling power average") {
                    try await queryAverage(identifier: .cyclingPower, predicate: workoutPredicate)
                }
                maxPower = await fetchOptional("cycling power max") {
                    try await queryMax(identifier: .cyclingPower, predicate: workoutPredicate)
                }
            default:
                break
            }

            // Wave 1: laps from HKWorkoutEvent + GPS route + elevation gain.
            // Lap distance is summed from the workout's distance samples
            // (distanceWalkingRunning/distanceCycling/distanceSwimming) — the
            // same fused GPS+accelerometer signal Apple Health displays — so
            // numbers match Health and indoor workouts work too.
            let distanceSamples: [QuantitySampleValue]
            if let distId = distanceIdentifier(for: w.workoutActivityType) {
                distanceSamples = await fetchArray("lap distance samples") {
                    try await queryQuantitySamples(
                        identifier: distId,
                        predicate: workoutPredicate,
                        ascending: true,
                        limit: nil
                    )
                }
            } else {
                distanceSamples = []
            }
            let laps = extractLaps(from: w, distanceSamples: distanceSamples)
            let route = await fetchArray("route") {
                try await fetchRoute(for: w)
            }
            let elevationGain = computeElevationGain(from: route) ?? metadataElevation(w, key: HKMetadataKeyElevationAscended)
            let elevationLoss = metadataElevation(w, key: HKMetadataKeyElevationDescended)

            // Wave 2: per-sample time-series. Each metric is isolated so a
            // missing route/unsupported metric never drops valid HR samples.
            let timeSeries = await fetchTimeSeries(for: w, route: route)

            // Wave 1: derive auto-distance splits from the route.
            // Distances stay in meters; renderers handle metric/imperial display.
            let splits = await fetchArray("splits") {
                try await deriveSplits(workout: w, route: route)
            }

            results.append(WorkoutValue(
                sourceUUID: w.uuid,
                activityType: w.workoutActivityType.rawValue,
                duration: w.duration,
                startDate: w.startDate,
                endDate: w.endDate,
                sourceRevision: Self.sourceRevision(from: w.sourceRevision),
                device: Self.deviceProvenance(from: w.device),
                isIndoor: metadataIndoor(w),
                metadata: Self.serializedMetadata(w.metadata),
                totalEnergyBurned: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                totalDistance: w.totalDistance?.doubleValue(for: .meter()),
                avgHeartRate: hrStats?.avg,
                maxHeartRate: hrStats?.max,
                minHeartRate: hrStats?.min,
                avgRunningCadence: avgRunningCadence,
                avgStrideLength: avgStrideLength,
                avgGroundContactTime: avgGroundContactTime,
                avgVerticalOscillation: avgVerticalOscillation,
                avgCyclingCadence: avgCyclingCadence,
                avgPower: avgPower,
                maxPower: maxPower,
                elevationGainMeters: elevationGain,
                elevationLossMeters: elevationLoss,
                laps: laps,
                splits: splits,
                route: route,
                timeSeries: timeSeries
            ))
        }
        return results
    }

    // MARK: - Workout Granular Helpers

    /// Reads manual HKWorkoutEvents of type .lap off the workout.
    ///
    /// HealthKit can also attach `.segment` events for auto-distance splits;
    /// those often overlap manual/route-derived splits and can double-count a
    /// workout in Markdown tables. Health.md derives auto splits separately from
    /// the route, so `WorkoutLap` is reserved for true lap events.
    ///
    /// Distance is summed from the supplied `distanceSamples` (matches Apple
    /// Health). Falls back to `HKMetadataKeyAverageSpeed × duration` when no
    /// distance samples cover the lap, which some third-party apps populate.
    private func extractLaps(from workout: HKWorkout, distanceSamples: [QuantitySampleValue]) -> [WorkoutLap] {
        guard let events = workout.workoutEvents, !events.isEmpty else { return [] }
        var laps: [WorkoutLap] = []
        for event in events where event.type == .lap {
            let interval = event.dateInterval
            let sampledDistance = lapDistance(samples: distanceSamples,
                                              from: interval.start,
                                              to: interval.end)
            let metadataDistance = (event.metadata?[HKMetadataKeyAverageSpeed] as? HKQuantity)
                .map { $0.doubleValue(for: HKUnit.meter().unitDivided(by: .second())) * interval.duration }
            laps.append(WorkoutLap(
                startDate: interval.start,
                endDate: interval.end,
                duration: interval.duration,
                distanceMeters: sampledDistance ?? metadataDistance
            ))
        }
        return laps
    }

    /// HK distance identifier for a workout activity type, or nil for activities
    /// that don't track distance (yoga, strength training, etc.).
    private func distanceIdentifier(for activity: HKWorkoutActivityType) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .running, .walking, .hiking:
            return .distanceWalkingRunning
        case .cycling:
            return .distanceCycling
        case .swimming:
            return .distanceSwimming
        case .wheelchairWalkPace, .wheelchairRunPace:
            return .distanceWheelchair
        default:
            return nil
        }
    }

    /// Sums the portion of distance samples overlapping `[lapStart, lapEnd]`,
    /// pro-rating samples that straddle the boundary. Returns nil when no
    /// sample covers the lap, so callers can fall back to other sources.
    private func lapDistance(samples: [QuantitySampleValue], from lapStart: Date, to lapEnd: Date) -> Double? {
        guard lapEnd > lapStart else { return nil }
        var total = 0.0
        var matched = false
        for s in samples {
            let overlapStart = max(s.startDate, lapStart)
            let overlapEnd = min(s.endDate, lapEnd)
            let overlap = overlapEnd.timeIntervalSince(overlapStart)
            if overlap > 0 {
                let sampleDuration = s.endDate.timeIntervalSince(s.startDate)
                guard sampleDuration > 0 else { continue }
                total += s.value * (overlap / sampleDuration)
                matched = true
            } else if s.startDate == s.endDate, s.startDate >= lapStart, s.startDate <= lapEnd {
                // Instantaneous sample sitting inside the lap window.
                total += s.value
                matched = true
            }
        }
        return matched ? total : nil
    }

    /// Returns total ascent in meters by summing positive altitude deltas
    /// across the route. Returns nil when fewer than two altitudes exist.
    private func computeElevationGain(from route: [RoutePoint]) -> Double? {
        let altitudes = route.compactMap(\.altitudeMeters)
        guard altitudes.count >= 2 else { return nil }
        var gain = 0.0
        for i in 1..<altitudes.count {
            let delta = altitudes[i] - altitudes[i - 1]
            if delta > 0 { gain += delta }
        }
        return gain
    }

    /// Reads ascent/descent from HKWorkout metadata as a fallback when the route
    /// is unavailable. Apple Watch populates these for outdoor workouts.
    private func metadataElevation(_ workout: HKWorkout, key: String) -> Double? {
        guard let q = workout.metadata?[key] as? HKQuantity else { return nil }
        return q.doubleValue(for: .meter())
    }

    /// Reads whether the workout was performed indoors. Apple uses this metadata
    /// to distinguish Indoor Walk/Run from Outdoor Walk/Run while the activity
    /// type remains simply `.walking` or `.running`.
    private func metadataIndoor(_ workout: HKWorkout) -> Bool? {
        if let value = workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber {
            return value.boolValue
        }
        if let value = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool {
            return value
        }
        return nil
    }

    /// Serializes arbitrary HKWorkout metadata into stable string values so JSON
    /// export can preserve keys beyond Health.md's first-class workout fields.
    private static func serializedMetadata(_ metadata: [String: Any]?) -> [String: String] {
        guard let metadata else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in metadata {
            result[key] = serializedMetadataValue(value)
        }
        return result
    }

    private static func serializedMetadataValue(_ value: Any) -> String {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let string as String:
            return string
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let quantity as HKQuantity:
            return quantity.description
        case let url as URL:
            return url.absoluteString
        case let values as [Any]:
            return values.map { serializedMetadataValue($0) }.joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }

    // MARK: - Lossless Typed Metadata

    /// Converts every metadata entry recursively without treating an unknown
    /// object as an ordinary string. `sampleQuantityUnit` is used only for the
    /// documented session-estimate key, whose unit follows its parent sample.
    static func typedMetadata(
        _ metadata: [String: Any]?,
        sampleQuantityUnit: HKUnit? = nil
    ) -> [String: HealthKitMetadataValue] {
        guard let metadata else { return [:] }
        var converted: [String: HealthKitMetadataValue] = [:]
        converted.reserveCapacity(metadata.count)
        for (key, value) in metadata {
            converted[key] = typedMetadataValue(
                value,
                canonicalQuantityUnit: canonicalMetadataQuantityUnit(
                    for: key,
                    sampleQuantityUnit: sampleQuantityUnit
                )
            )
        }
        return converted
    }

    private static func typedMetadataValue(
        _ value: Any,
        canonicalQuantityUnit: HKUnit?
    ) -> HealthKitMetadataValue {
        if value is NSNull {
            return .null
        }

        // Swift Bool bridges to the CFBoolean NSNumber singleton. Check that
        // identity before inspecting objCType because CFBoolean reports "c".
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }

        if let number = value as? NSNumber {
            let encoding = String(cString: number.objCType)
            switch encoding {
            case "c", "s", "i", "l", "q":
                return .signedInteger(number.int64Value)
            case "C", "S", "I", "L", "Q":
                return .unsignedInteger(number.uint64Value)
            case "B":
                return .bool(number.boolValue)
            case "f", "d", "D":
                let converted = number.doubleValue
                guard converted.isFinite else {
                    return .unsupported(
                        typeName: String(reflecting: type(of: value)),
                        description: String(describing: value)
                    )
                }
                return .floatingPoint(converted)
            default:
                return .unsupported(
                    typeName: String(reflecting: type(of: value)),
                    description: String(describing: value)
                )
            }
        }

        switch value {
        case let string as String:
            return .string(string)
        case let date as Date:
            return .date(date)
        case let data as Data:
            return .data(data)
        case let url as URL:
            return .url(url)
        case let quantity as HKQuantity:
            let rawDescription = quantity.description
            guard let canonicalQuantityUnit,
                  quantity.is(compatibleWith: canonicalQuantityUnit) else {
                return .quantity(HealthKitMetadataQuantity(rawDescription: rawDescription))
            }
            let converted = quantity.doubleValue(for: canonicalQuantityUnit)
            guard converted.isFinite else {
                return .quantity(HealthKitMetadataQuantity(rawDescription: rawDescription))
            }
            return .quantity(HealthKitMetadataQuantity(
                value: converted,
                unit: canonicalQuantityUnit.unitString,
                rawDescription: rawDescription
            ))
        case let values as [Any]:
            return .array(values.map {
                typedMetadataValue($0, canonicalQuantityUnit: nil)
            })
        case let dictionary as [String: Any]:
            return .dictionary(typedMetadata(dictionary))
        default:
            return .unsupported(
                typeName: String(reflecting: type(of: value)),
                description: String(describing: value)
            )
        }
    }

    private static func canonicalMetadataQuantityUnit(
        for key: String,
        sampleQuantityUnit: HKUnit?
    ) -> HKUnit? {
        switch key {
        case HKMetadataKeySessionEstimate:
            return sampleQuantityUnit
        case HKMetadataKeyHeartRateRecoveryActivityDuration,
             HKMetadataKeyFitnessMachineDuration,
             HKMetadataKeyAudioExposureDuration:
            return .second()
        case HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate,
             HKMetadataKeyHeartRateEventThreshold:
            return HKUnit.count().unitDivided(by: .minute())
        case HKMetadataKeyWeatherTemperature:
            return .degreeCelsius()
        case HKMetadataKeyWeatherHumidity,
             HKMetadataKeyAlpineSlopeGrade:
            return .percent()
        case HKMetadataKeyLapLength,
             HKMetadataKeyElevationAscended,
             HKMetadataKeyElevationDescended,
             HKMetadataKeyIndoorBikeDistance,
             HKMetadataKeyCrossTrainerDistance:
            return .meter()
        case HKMetadataKeyAverageSpeed,
             HKMetadataKeyMaximumSpeed:
            return HKUnit.meter().unitDivided(by: .second())
        case HKMetadataKeyAverageMETs:
            return HKUnit(from: "kcal/hr·kg")
        case HKMetadataKeyAudioExposureLevel,
             HKMetadataKeyHeadphoneGain:
            return .decibelAWeightedSoundPressureLevel()
        case HKMetadataKeyBarometricPressure:
            return HKUnit(from: "Pa")
        case HKMetadataKeyVO2MaxValue,
             HKMetadataKeyLowCardioFitnessEventThreshold:
            return HKUnits.vo2Max
        case HKMetadataKeyMaximumLightIntensity:
            return HKUnit(from: "lx")
        default:
            return nil
        }
    }

    /// Fetches all CLLocations associated with a workout via HKWorkoutRoute.
    /// Returns RoutePoints sorted by timestamp. Returns empty array if no route.
    private func fetchRoute(for workout: HKWorkout) async throws -> [RoutePoint] {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: routeType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let routes = try await routeDescriptor.result(for: store).compactMap { $0 as? HKWorkoutRoute }
        var points: [RoutePoint] = []
        for route in routes {
            let locations = try await locations(for: route)
            for loc in locations {
                points.append(RoutePoint(
                    timestamp: loc.timestamp,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    altitudeMeters: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
                    speedMps: loc.speed >= 0 ? loc.speed : nil,
                    courseDegrees: loc.course >= 0 ? loc.course : nil,
                    horizontalAccuracyMeters: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil
                ))
            }
        }
        return points
    }

    /// Bridges the callback-based HKWorkoutRouteQuery into async/await.
    func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CLLocation], Error>) in
            var collected: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                if let batch { collected.append(contentsOf: batch) }
                if done { cont.resume(returning: collected) }
            }
            store.execute(query)
        }
    }

    /// Derives auto-distance splits every 1 km from the route. Each split's
    /// avgHeartRate is averaged from HR samples falling inside the split's
    /// time window. Renderers format pace/speed in the user's preferred units.
    /// Returns empty if route has no GPS-tracked distance.
    private func deriveSplits(workout: HKWorkout, route: [RoutePoint]) async throws -> [WorkoutSplit] {
        guard route.count >= 2 else { return [] }
        let splitDistance: Double = 1000.0  // meters; renderers handle unit display
        var splits: [WorkoutSplit] = []
        var lastSplitMeters: Double = 0
        var lastSplitTime: Date = route[0].timestamp
        var cumMeters: Double = 0
        var splitIndex = 1

        for i in 1..<route.count {
            let prev = route[i - 1]
            let curr = route[i]
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
            cumMeters += currLoc.distance(from: prevLoc)
            while cumMeters - lastSplitMeters >= splitDistance {
                let splitEnd = curr.timestamp
                let avgHR: Double?
                do {
                    avgHR = try await fetchAverageHeartRate(workout: workout, start: lastSplitTime, end: splitEnd)
                } catch {
                    let range = Self.rangeDescription(start: lastSplitTime, end: splitEnd)
                    Self.logger.warning("HealthKit workout split heart-rate fetch failed for splitRange=\(range, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    avgHR = nil
                }
                splits.append(WorkoutSplit(
                    index: splitIndex,
                    startDate: lastSplitTime,
                    duration: splitEnd.timeIntervalSince(lastSplitTime),
                    distanceMeters: splitDistance,
                    avgHeartRate: avgHR
                ))
                splitIndex += 1
                lastSplitMeters += splitDistance
                lastSplitTime = splitEnd
            }
        }
        return splits
    }

    private static func rangeDescription(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func fetchAverageHeartRate(workout: HKWorkout, start: Date, end: Date) async throws -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let timePredicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: hrType, predicate: combined),
            options: .discreteAverage
        )
        return try await descriptor.result(for: store)?.averageQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    /// Fetches per-sample time-series for HR + activity-relevant form metrics.
    /// Currently uses HKSampleQuery (one sample per HK record); upgrading to
    /// HKQuantitySeriesSampleQuery would expose beat-to-beat HR data when
    /// available.
    private func fetchTimeSeries(for workout: HKWorkout, route: [RoutePoint]) async -> WorkoutTimeSeries {
        let predicate = HKQuery.predicateForObjects(from: workout)

        @Sendable
        func safeSamples(_ context: String, identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> [TimeSeriesSample] {
            do {
                return try await fetchSamples(identifier, predicate: predicate, unit: unit)
            } catch {
                let workoutRange = Self.rangeDescription(start: workout.startDate, end: workout.endDate)
                Self.logger.warning("HealthKit workout time-series fetch failed for \(context, privacy: .public) workoutRange=\(workoutRange, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return []
            }
        }

        let altitude = altitudeSeries(from: route)
        async let heartRate = safeSamples(
            "heart rate",
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )

        switch workout.workoutActivityType {
        case .running:
            async let speed = safeSamples(
                "running speed",
                identifier: .runningSpeed,
                unit: HKUnit.meter().unitDivided(by: .second())
            )
            async let power = safeSamples("running power", identifier: .runningPower, unit: .watt())
            async let stride = safeSamples("running stride length", identifier: .runningStrideLength, unit: .meter())
            async let gct = safeSamples(
                "running ground contact time",
                identifier: .runningGroundContactTime,
                unit: HKUnit.secondUnit(with: .milli)
            )
            async let vertOsc = safeSamples(
                "running vertical oscillation",
                identifier: .runningVerticalOscillation,
                unit: .meterUnit(with: .centi)
            )
            return WorkoutTimeSeries(
                heartRate: await heartRate,
                speed: await speed,
                power: await power,
                cadence: [],   // running cadence is derived from steps; not available as a time-series natively
                strideLength: await stride,
                groundContactTime: await gct,
                verticalOscillation: await vertOsc,
                altitude: altitude
            )
        case .cycling:
            async let speed = safeSamples(
                "cycling speed",
                identifier: .cyclingSpeed,
                unit: HKUnit.meter().unitDivided(by: .second())
            )
            async let power = safeSamples("cycling power", identifier: .cyclingPower, unit: .watt())
            async let cadence = safeSamples(
                "cycling cadence",
                identifier: .cyclingCadence,
                unit: HKUnit.count().unitDivided(by: .minute())
            )
            return WorkoutTimeSeries(
                heartRate: await heartRate,
                speed: await speed,
                power: await power,
                cadence: await cadence,
                altitude: altitude
            )
        default:
            return WorkoutTimeSeries(
                heartRate: await heartRate,
                altitude: altitude
            )
        }
    }

    private func fetchSamples(_ identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?, unit: HKUnit) async throws -> [TimeSeriesSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map {
            TimeSeriesSample(
                timestamp: $0.startDate,
                value: $0.quantity.doubleValue(for: unit),
                metadata: Self.serializedMetadata($0.metadata)
            )
        }
    }

    /// Per-sample altitude is encoded into HKWorkoutRoute CLLocation samples,
    /// so we re-extract it from the already-fetched route rather than issuing a
    /// second route query that can fail independently and drop other series.
    private func altitudeSeries(from route: [RoutePoint]) -> [TimeSeriesSample] {
        route.compactMap { p in
            p.altitudeMeters.map { TimeSeriesSample(timestamp: p.timestamp, value: $0) }
        }
    }

    private func fetchHeartRateStats(for workout: HKWorkout) async throws -> (avg: Double?, max: Double?, min: Double?) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil, nil)
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: hrType, predicate: predicate),
            options: [.discreteAverage, .discreteMax, .discreteMin]
        )
        guard let result = try await descriptor.result(for: store) else {
            return (nil, nil, nil)
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return (
            avg: result.averageQuantity()?.doubleValue(for: bpm),
            max: result.maximumQuantity()?.doubleValue(for: bpm),
            min: result.minimumQuantity()?.doubleValue(for: bpm)
        )
    }

    // MARK: - Quantity Sample Queries

    func queryQuantitySamples(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [QuantitySampleValue] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let order: SortOrder = ascending ? .forward : .reverse
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: order)],
            limit: limit
        )
        let samples = try await descriptor.result(for: store)
        let u = unit(for: identifier)
        return samples.map {
            QuantitySampleValue(
                value: $0.quantity.doubleValue(for: u),
                startDate: $0.startDate,
                endDate: $0.endDate,
                metadata: Self.serializedMetadata($0.metadata)
            )
        }
    }

    // MARK: - Blood Pressure Correlation Queries

    func queryBloodPressureRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord] {
        guard let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure) else {
            return []
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: correlationType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: limit
        )
        return try await descriptor.result(for: store).flatMap {
            canonicalBloodPressureRecords(from: $0, selectedMetricIDs: selectedMetricIDs)
        }
    }

    /// Returns one correlation record and every contained systolic/diastolic
    /// quantity object. Components are not paired, deduplicated, or truncated.
    func canonicalBloodPressureRecords(
        from correlation: HKCorrelation,
        selectedMetricIDs: [String]
    ) -> [HealthKitRecord] {
        let systolicIdentifier = HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
        let diastolicIdentifier = HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
        let unit = HKUnit.millimeterOfMercury()
        let components: [(sample: HKQuantitySample, role: String)] = correlation.objects.compactMap { object in
            guard let sample = object as? HKQuantitySample else { return nil }
            switch sample.quantityType.identifier {
            case systolicIdentifier: return (sample, "systolic")
            case diastolicIdentifier: return (sample, "diastolic")
            default: return nil
            }
        }.sorted { lhs, rhs in
            if lhs.sample.startDate != rhs.sample.startDate {
                return lhs.sample.startDate < rhs.sample.startDate
            }
            if lhs.sample.endDate != rhs.sample.endDate {
                return lhs.sample.endDate < rhs.sample.endDate
            }
            return lhs.sample.uuid.uuidString < rhs.sample.uuid.uuidString
        }

        let correlationRelationships = components.map {
            HealthKitRecordRelationship(
                targetUUID: $0.sample.uuid,
                role: $0.role,
                kind: "component"
            )
        }
        let correlationRecord = HealthKitRecord(
            originalUUID: correlation.uuid,
            objectTypeIdentifier: correlation.correlationType.identifier,
            recordKind: .correlation,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: correlation.startDate,
            endDate: correlation.endDate,
            hasUndeterminedDuration: correlation.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: correlation.sourceRevision),
            device: Self.deviceProvenance(from: correlation.device),
            metadata: Self.typedMetadata(correlation.metadata),
            payload: .correlation(componentUUIDs: components.map { $0.sample.uuid }),
            relationships: correlationRelationships
        )

        let componentRecords = components.map { component in
            let base = canonicalQuantityRecord(
                from: component.sample,
                canonicalUnit: unit,
                selectedMetricIDs: selectedMetricIDs
            )
            return HealthKitRecord(
                originalUUID: base.originalUUID,
                objectTypeIdentifier: base.objectTypeIdentifier,
                recordKind: base.recordKind,
                selectedMetricIDs: base.selectedMetricIDs,
                includedBecause: base.includedBecause,
                startDate: base.startDate,
                endDate: base.endDate,
                hasUndeterminedDuration: base.hasUndeterminedDuration,
                sourceRevision: base.sourceRevision,
                device: base.device,
                metadata: base.metadata,
                payload: base.payload,
                relationships: [HealthKitRecordRelationship(
                    targetUUID: correlation.uuid,
                    role: component.role,
                    kind: "parent"
                )]
            )
        }
        return [correlationRecord] + componentRecords
    }

    func queryBloodPressureSamples(
        predicate: NSPredicate?,
        ascending: Bool,
        limit: Int?
    ) async throws -> [BloodPressureSampleValue] {
        guard let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return []
        }

        let order: SortOrder = ascending ? .forward : .reverse
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: correlationType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: order)],
            limit: limit
        )
        let correlations = try await descriptor.result(for: store)
        let unit = HKUnit.millimeterOfMercury()

        return correlations.compactMap { correlation in
            guard let systolic = correlation.objects(for: systolicType)
                .compactMap({ $0 as? HKQuantitySample })
                .first,
                  let diastolic = correlation.objects(for: diastolicType)
                .compactMap({ $0 as? HKQuantitySample })
                .first else {
                return nil
            }

            return BloodPressureSampleValue(
                correlationUUID: correlation.uuid,
                systolic: systolic.quantity.doubleValue(for: unit),
                diastolic: diastolic.quantity.doubleValue(for: unit),
                startDate: correlation.startDate,
                endDate: correlation.endDate,
                sourceRevision: Self.sourceRevision(from: correlation.sourceRevision),
                device: Self.deviceProvenance(from: correlation.device),
                metadata: Self.serializedMetadata(correlation.metadata)
            )
        }
    }

    // MARK: - State of Mind Queries (iOS 18+)

    func queryStateOfMindRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord] {
        if #available(iOS 18.0, macOS 15.0, *) {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.stateOfMind(predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
                limit: limit
            )
            return try await descriptor.result(for: store).map {
                canonicalStateOfMindRecord(from: $0, selectedMetricIDs: selectedMetricIDs)
            }
        }
        return []
    }

    @available(iOS 18.0, macOS 15.0, *)
    func canonicalStateOfMindRecord(
        from sample: HKStateOfMind,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        let kind = Self.enumMetadata(
            rawValue: sample.kind.rawValue,
            symbolicValue: Self.symbolicName(from: Self.mapStateOfMindKind(sample.kind))
        )
        let classification = Self.enumMetadata(
            rawValue: sample.valenceClassification.rawValue,
            symbolicValue: Self.symbolicName(
                from: Self.mapStateOfMindValenceClassification(sample.valenceClassification)
            )
        )
        let labels = sample.labels.map {
            Self.enumMetadata(
                rawValue: $0.rawValue,
                symbolicValue: Self.symbolicName(from: Self.mapStateOfMindLabel($0))
            )
        }
        let associations = sample.associations.map {
            Self.enumMetadata(
                rawValue: $0.rawValue,
                symbolicValue: Self.symbolicName(from: Self.mapStateOfMindAssociation($0))
            )
        }
        return HealthKitRecord(
            originalUUID: sample.uuid,
            objectTypeIdentifier: sample.sampleType.identifier,
            recordKind: .stateOfMind,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: sample.startDate,
            endDate: sample.endDate,
            hasUndeterminedDuration: sample.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
            device: Self.deviceProvenance(from: sample.device),
            metadata: Self.typedMetadata(sample.metadata),
            payload: .structured(kind: "stateOfMind", fields: [
                "kind": kind,
                "valence": .floatingPoint(sample.valence),
                "valenceClassification": classification,
                "labels": .array(labels),
                "associations": .array(associations),
            ])
        )
    }

    func queryStateOfMind(predicate: NSPredicate?) async throws -> [StateOfMindSampleValue] {
        if #available(iOS 18.0, macOS 15.0, *) {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.stateOfMind(predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await descriptor.result(for: store)
            return samples.map { sample in
                StateOfMindSampleValue(
                    uuid: sample.uuid,
                    kind: Self.mapStateOfMindKind(sample.kind) ?? "Unknown",
                    valence: sample.valence,
                    labels: sample.labels.map { Self.mapStateOfMindLabel($0) ?? "Unknown" },
                    associations: sample.associations.map { Self.mapStateOfMindAssociation($0) ?? "Unknown" },
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
                    device: Self.deviceProvenance(from: sample.device),
                    metadata: Self.serializedMetadata(sample.metadata)
                )
            }
        } else {
            return []
        }
    }

    // MARK: - Medication Queries (iOS/macOS 26+)

    func requestMedicationAuthorization() async throws {
        if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *) {
            try await store.requestPerObjectReadAuthorization(for: .userAnnotatedMedicationType(), predicate: nil)
        }
    }

    func queryMedications() async throws -> [MedicationValue] {
        if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *) {
            let descriptor = HKUserAnnotatedMedicationQueryDescriptor()
            let medications = try await descriptor.result(for: store)
            return medications.map { medicationValue(from: $0) }
        }
        return []
    }

    func queryMedicationDoseEventRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitMedicationRecordQueryResult {
        if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *) {
            let samplePredicate = HKSamplePredicate.sample(
                type: .medicationDoseEventType(),
                predicate: predicate
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [samplePredicate],
                sortDescriptors: [SortDescriptor(\HKSample.startDate, order: .forward)],
                limit: limit
            )
            async let queriedSamples = descriptor.result(for: store)
            async let queriedMedications = HKUserAnnotatedMedicationQueryDescriptor().result(for: store)
            let samples = try await queriedSamples.compactMap { $0 as? HKMedicationDoseEvent }
            let medicationPairs = try await queriedMedications.map {
                ($0.medication.identifier, medicationValue(from: $0))
            }
            let inventory = medicationPairs.map { _, medication in
                medicationInventoryRecord(from: medication, selectedMetricIDs: selectedMetricIDs)
            }
            let records = samples.map { sample in
                let matchingMedication = medicationPairs.first { conceptIdentifier, _ in
                    conceptIdentifier.isEqual(sample.medicationConceptIdentifier)
                }?.1
                return canonicalMedicationDoseEventRecord(
                    from: sample,
                    medication: matchingMedication,
                    selectedMetricIDs: selectedMetricIDs
                )
            }
            return HealthKitMedicationRecordQueryResult(
                records: records,
                inventoryRecords: inventory
            )
        }
        return HealthKitMedicationRecordQueryResult()
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private func canonicalMedicationDoseEventRecord(
        from sample: HKMedicationDoseEvent,
        medication: MedicationValue?,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        let fallbackIdentity = conceptIdentity(for: sample.medicationConceptIdentifier)
        let externalIdentifier = medication?.conceptIdentifier ?? fallbackIdentity.externalIdentifier
        let medicationName: String? = {
            guard let medication else { return nil }
            if let nickname = medication.nickname, !nickname.isEmpty { return nickname }
            return medication.displayName
        }()
        return HealthKitRecord(
            originalUUID: sample.uuid,
            objectTypeIdentifier: sample.sampleType.identifier,
            recordKind: .medicationDoseEvent,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: sample.startDate,
            endDate: sample.endDate,
            hasUndeterminedDuration: sample.hasUndeterminedDuration,
            sourceRevision: Self.sourceRevision(from: sample.sourceRevision),
            device: Self.deviceProvenance(from: sample.device),
            metadata: Self.typedMetadata(sample.metadata),
            payload: .structured(kind: "medicationDoseEvent", fields: [
                "medicationConceptIdentifier": .string(externalIdentifier),
                "medicationName": medicationName.map(HealthKitMetadataValue.string) ?? .null,
                "medicationIdentifierStability": .string(
                    medication?.identifierStability ?? fallbackIdentity.stability
                ),
                "startDate": .date(sample.startDate),
                "endDate": .date(sample.endDate),
                "scheduledDate": sample.scheduledDate.map(HealthKitMetadataValue.date) ?? .null,
                "doseQuantity": sample.doseQuantity.map(HealthKitMetadataValue.floatingPoint) ?? .null,
                "scheduledDoseQuantity": sample.scheduledDoseQuantity.map(HealthKitMetadataValue.floatingPoint) ?? .null,
                "unit": .string(sample.unit.unitString),
                "logStatus": Self.enumMetadata(
                    rawValue: sample.logStatus.rawValue,
                    symbolicValue: Self.medicationDoseStatusSymbol(sample.logStatus)
                ),
                "scheduleType": Self.enumMetadata(
                    rawValue: sample.scheduleType.rawValue,
                    symbolicValue: Self.medicationScheduleTypeSymbol(sample.scheduleType)
                ),
            ]),
            relationships: [HealthKitRecordRelationship(
                targetExternalIdentifier: externalIdentifier,
                role: "medication",
                kind: "medicationConcept"
            )]
        )
    }

    private func medicationInventoryRecord(
        from medication: MedicationValue,
        selectedMetricIDs: [String]
    ) -> HealthKitMedicationInventoryRecord {
        let codings = medication.relatedCodings.map { coding in
            HealthKitMetadataValue.dictionary([
                "system": .string(coding.system),
                "version": coding.version.map(HealthKitMetadataValue.string) ?? .null,
                "code": .string(coding.code),
            ])
        }
        return HealthKitMedicationInventoryRecord(
            externalIdentifier: medication.conceptIdentifier,
            selectedMetricIDs: selectedMetricIDs,
            displayName: medication.displayName,
            fields: [
                "conceptIdentifier": .string(medication.conceptIdentifier),
                "displayName": .string(medication.displayName),
                "nickname": medication.nickname.map(HealthKitMetadataValue.string) ?? .null,
                "generalForm": .string(medication.generalForm),
                "isArchived": .bool(medication.isArchived),
                "hasSchedule": .bool(medication.hasSchedule),
                "relatedCodings": .array(codings),
                "identifierStability": .string(medication.identifierStability),
                "identifierStabilityNotes": .string(medication.identifierStabilityNotes),
            ]
        )
    }

    func queryMedicationDoseEvents(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [MedicationDoseEventValue] {
        if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *) {
            let order: SortOrder = ascending ? .forward : .reverse
            let samplePredicate = HKSamplePredicate.sample(type: .medicationDoseEventType(), predicate: predicate)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [samplePredicate],
                sortDescriptors: [SortDescriptor(\HKSample.startDate, order: order)],
                limit: limit
            )
            let samples = try await descriptor.result(for: store).compactMap { $0 as? HKMedicationDoseEvent }

            // Fetch the authorized medications too so we can export human names and
            // stable best-effort IDs for dose events by comparing the private
            // HKHealthConceptIdentifier objects directly while still inside HealthKit.
            let medications = (try? await HKUserAnnotatedMedicationQueryDescriptor().result(for: store)) ?? []
            let medicationPairs = medications.map { ($0.medication.identifier, medicationValue(from: $0)) }

            return samples.map { sample in
                let matchingMedication = medicationPairs.first { conceptIdentifier, _ in
                    conceptIdentifier.isEqual(sample.medicationConceptIdentifier)
                }?.1
                let conceptIdentifier = matchingMedication?.conceptIdentifier ?? conceptIdentifierString(sample.medicationConceptIdentifier)

                return MedicationDoseEventValue(
                    uuid: sample.uuid,
                    medicationConceptIdentifier: conceptIdentifier,
                    medicationName: matchingMedication?.nickname?.isEmpty == false ? matchingMedication?.nickname : (matchingMedication?.displayName),
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    scheduledDate: sample.scheduledDate,
                    doseQuantity: sample.doseQuantity,
                    scheduledDoseQuantity: sample.scheduledDoseQuantity,
                    unit: sample.unit.unitString,
                    logStatus: Self.mapMedicationDoseStatus(sample.logStatus) ?? "unknown",
                    scheduleType: Self.mapMedicationScheduleType(sample.scheduleType) ?? "unknown",
                    metadata: Self.serializedMetadata(sample.metadata)
                )
            }
        }
        return []
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private func medicationValue(from annotatedMedication: HKUserAnnotatedMedication) -> MedicationValue {
        let medication = annotatedMedication.medication
        let relatedCodings = medication.relatedCodings.map {
            MedicationCodingValue(system: $0.system, version: $0.version, code: $0.code)
        }.sorted { lhs, rhs in
            if lhs.system != rhs.system { return lhs.system < rhs.system }
            return lhs.code < rhs.code
        }

        let identity = conceptIdentity(for: medication.identifier, codings: relatedCodings)
        return MedicationValue(
            conceptIdentifier: identity.externalIdentifier,
            displayName: medication.displayText,
            nickname: annotatedMedication.nickname,
            generalForm: Self.mapMedicationGeneralForm(medication.generalForm),
            isArchived: annotatedMedication.isArchived,
            hasSchedule: annotatedMedication.hasSchedule,
            relatedCodings: relatedCodings,
            identifierStability: identity.stability,
            identifierStabilityNotes: identity.notes
        )
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private static func mapMedicationGeneralForm(_ form: HKMedicationGeneralForm) -> String {
        // Do not switch over `.capsule`, `.tablet`, etc. here. Those typed-enum
        // cases are imported as external HealthKit constants, which makes the
        // app binary contain strong references to macOS 26-only symbols. GitHub
        // Actions currently runs macOS tests on macOS 15, so dyld aborts before
        // tests can bootstrap if any of those constants are referenced directly.
        return normalizedHealthKitStringConstant(
            form.rawValue,
            droppingPrefix: "HKMedicationGeneralForm"
        )
    }

    private static func normalizedHealthKitStringConstant(_ rawValue: String, droppingPrefix prefix: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }

        let snakeCased = value
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1_$2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "[^A-Za-z0-9]+",
                with: "_",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()

        return snakeCased.isEmpty ? "unknown" : snakeCased
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private func conceptIdentifierString(_ identifier: HKHealthConceptIdentifier, codings: [MedicationCodingValue] = []) -> String {
        conceptIdentity(for: identifier, codings: codings).externalIdentifier
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private func conceptIdentity(
        for identifier: HKHealthConceptIdentifier,
        codings: [MedicationCodingValue] = []
    ) -> (externalIdentifier: String, stability: String, notes: String) {
        let rxNormSystem = "http://www.nlm.nih.gov/research/umls/rxnorm"
        if let rxNorm = codings.first(where: { $0.system == rxNormSystem }) {
            return (
                "rxnorm:\(rxNorm.code)",
                "stable_clinical_coding",
                "Derived from the medication's RxNorm coding and suitable for durable external relationships."
            )
        }
        if let coding = codings.first {
            return (
                "\(coding.system):\(coding.code)",
                "stable_clinical_coding",
                "Derived from the medication's first available clinical coding and suitable for durable external relationships."
            )
        }
        return (
            String(describing: identifier),
            "best_effort_healthkit_concept_identifier",
            "HealthKit documents the opaque concept identifier as stable for direct comparisons across devices, but exposes no public serializable raw value; this string description is a best-effort archive identity."
        )
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private static func mapMedicationDoseStatus(_ status: HKMedicationDoseEvent.LogStatus) -> String? {
        switch status {
        case .taken: return "taken"
        case .skipped: return "skipped"
        case .snoozed: return "snoozed"
        case .notInteracted: return "not_interacted"
        case .notificationNotSent: return "notification_not_sent"
        case .notLogged: return "not_logged"
        @unknown default: return nil
        }
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private static func mapMedicationScheduleType(_ scheduleType: HKMedicationDoseEvent.ScheduleType) -> String? {
        switch scheduleType {
        case .asNeeded: return "as_needed"
        case .schedule: return "scheduled"
        @unknown default: return nil
        }
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private static func medicationDoseStatusSymbol(
        _ status: HKMedicationDoseEvent.LogStatus
    ) -> String? {
        switch status {
        case .taken: return "taken"
        case .skipped: return "skipped"
        case .snoozed: return "snoozed"
        case .notInteracted: return "notInteracted"
        case .notificationNotSent: return "notificationNotSent"
        case .notLogged: return "notLogged"
        @unknown default: return nil
        }
    }

    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *)
    private static func medicationScheduleTypeSymbol(
        _ scheduleType: HKMedicationDoseEvent.ScheduleType
    ) -> String? {
        switch scheduleType {
        case .asNeeded: return "asNeeded"
        case .schedule: return "schedule"
        @unknown default: return nil
        }
    }

    private static func enumMetadata(
        rawValue: Int,
        symbolicValue: String?
    ) -> HealthKitMetadataValue {
        .dictionary([
            "rawValue": .signedInteger(Int64(rawValue)),
            "symbolicValue": symbolicValue.map(HealthKitMetadataValue.string) ?? .null,
        ])
    }

    private static func symbolicName(from displayName: String?) -> String? {
        guard let displayName else { return nil }
        let words = displayName.split(separator: " ")
        guard let first = words.first else { return nil }
        return first.lowercased() + words.dropFirst().map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined()
    }

    // MARK: - State of Mind Mapping Helpers

    @available(iOS 18.0, macOS 15.0, *)
    private static func mapStateOfMindKind(_ kind: HKStateOfMind.Kind) -> String? {
        switch kind {
        case .momentaryEmotion: return "Momentary Emotion"
        case .dailyMood:        return "Daily Mood"
        @unknown default:       return nil
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private static func mapStateOfMindValenceClassification(
        _ classification: HKStateOfMind.ValenceClassification
    ) -> String? {
        switch classification {
        case .veryUnpleasant: return "Very Unpleasant"
        case .unpleasant: return "Unpleasant"
        case .slightlyUnpleasant: return "Slightly Unpleasant"
        case .neutral: return "Neutral"
        case .slightlyPleasant: return "Slightly Pleasant"
        case .pleasant: return "Pleasant"
        case .veryPleasant: return "Very Pleasant"
        @unknown default: return nil
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private static func mapStateOfMindLabel(_ label: HKStateOfMind.Label) -> String? {
        switch label {
        case .amazed:        return "Amazed"
        case .amused:        return "Amused"
        case .annoyed:       return "Annoyed"
        case .angry:         return "Angry"
        case .anxious:       return "Anxious"
        case .ashamed:       return "Ashamed"
        case .brave:         return "Brave"
        case .calm:          return "Calm"
        case .confident:     return "Confident"
        case .content:       return "Content"
        case .disappointed:  return "Disappointed"
        case .discouraged:   return "Discouraged"
        case .disgusted:     return "Disgusted"
        case .drained:       return "Drained"
        case .embarrassed:   return "Embarrassed"
        case .excited:       return "Excited"
        case .frustrated:    return "Frustrated"
        case .grateful:      return "Grateful"
        case .guilty:        return "Guilty"
        case .happy:         return "Happy"
        case .hopeful:       return "Hopeful"
        case .hopeless:      return "Hopeless"
        case .indifferent:   return "Indifferent"
        case .irritated:     return "Irritated"
        case .jealous:       return "Jealous"
        case .joyful:        return "Joyful"
        case .lonely:        return "Lonely"
        case .overwhelmed:   return "Overwhelmed"
        case .passionate:    return "Passionate"
        case .peaceful:      return "Peaceful"
        case .proud:         return "Proud"
        case .relieved:      return "Relieved"
        case .sad:           return "Sad"
        case .satisfied:     return "Satisfied"
        case .scared:        return "Scared"
        case .stressed:      return "Stressed"
        case .surprised:     return "Surprised"
        case .worried:       return "Worried"
        @unknown default:    return nil
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private static func mapStateOfMindAssociation(_ association: HKStateOfMind.Association) -> String? {
        switch association {
        case .community:      return "Community"
        case .currentEvents:  return "Current Events"
        case .dating:         return "Dating"
        case .education:      return "Education"
        case .family:         return "Family"
        case .fitness:        return "Fitness"
        case .friends:        return "Friends"
        case .health:         return "Health"
        case .hobbies:        return "Hobbies"
        case .identity:       return "Identity"
        case .money:          return "Money"
        case .partner:        return "Partner"
        case .selfCare:       return "Self Care"
        case .spirituality:   return "Spirituality"
        case .tasks:          return "Tasks"
        case .travel:         return "Travel"
        case .weather:        return "Weather"
        case .work:           return "Work"
        @unknown default:     return nil
        }
    }
}
