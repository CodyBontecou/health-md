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

final class SystemHealthStoreAdapter: HealthStoreProviding, @unchecked Sendable {
    private let store: HKHealthStore

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
        .dietaryVitaminA:               .gram(),
        .dietaryVitaminB6:              .gram(),
        .dietaryVitaminB12:             .gram(),
        .dietaryVitaminC:               .gram(),
        .dietaryVitaminD:               .gram(),
        .dietaryVitaminE:               .gram(),
        .dietaryVitaminK:               .gram(),
        .dietaryThiamin:                .gram(),
        .dietaryRiboflavin:             .gram(),
        .dietaryNiacin:                 .gram(),
        .dietaryFolate:                 .gram(),
        .dietaryBiotin:                 .gram(),
        .dietaryPantothenicAcid:        .gram(),

        // Minerals
        .dietaryCalcium:                .gram(),
        .dietaryIron:                   .gram(),
        .dietaryPotassium:              .gram(),
        .dietaryMagnesium:              .gram(),
        .dietaryPhosphorus:             .gram(),
        .dietaryZinc:                   .gram(),
        .dietarySelenium:               .gram(),
        .dietaryCopper:                 .gram(),
        .dietaryManganese:              .gram(),
        .dietaryChromium:               .gram(),
        .dietaryMolybdenum:             .gram(),
        .dietaryChloride:               .gram(),
        .dietaryIodine:                 .gram(),

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

    func requestAuth(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: toShare, read: read)
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
        return samples.map { CategorySampleValue(value: $0.value, startDate: $0.startDate, endDate: $0.endDate) }
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
            let hrStats = try? await fetchHeartRateStats(for: w)
            let workoutPredicate = HKQuery.predicateForObjects(from: w)

            var avgRunningCadence: Double?
            var avgStrideLength: Double?
            var avgGroundContactTime: Double?
            var avgVerticalOscillation: Double?
            var avgCyclingCadence: Double?
            var avgPower: Double?
            var maxPower: Double?

            switch w.workoutActivityType {
            case .running:
                avgStrideLength = try? await queryAverage(identifier: .runningStrideLength, predicate: workoutPredicate)
                avgGroundContactTime = try? await queryAverage(identifier: .runningGroundContactTime, predicate: workoutPredicate)
                avgVerticalOscillation = try? await queryAverage(identifier: .runningVerticalOscillation, predicate: workoutPredicate)
                avgPower = try? await queryAverage(identifier: .runningPower, predicate: workoutPredicate)
                maxPower = try? await queryMax(identifier: .runningPower, predicate: workoutPredicate)
                if let steps = try? await querySum(identifier: .stepCount, predicate: workoutPredicate),
                   steps > 0, w.duration > 0 {
                    avgRunningCadence = steps / (w.duration / 60.0)
                }
            case .cycling:
                avgCyclingCadence = try? await queryAverage(identifier: .cyclingCadence, predicate: workoutPredicate)
                avgPower = try? await queryAverage(identifier: .cyclingPower, predicate: workoutPredicate)
                maxPower = try? await queryMax(identifier: .cyclingPower, predicate: workoutPredicate)
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
                distanceSamples = (try? await queryQuantitySamples(
                    identifier: distId,
                    predicate: workoutPredicate,
                    ascending: true,
                    limit: nil
                )) ?? []
            } else {
                distanceSamples = []
            }
            let laps = extractLaps(from: w, distanceSamples: distanceSamples)
            let route = (try? await fetchRoute(for: w)) ?? []
            let elevationGain = computeElevationGain(from: route) ?? metadataElevation(w, key: HKMetadataKeyElevationAscended)
            let elevationLoss = metadataElevation(w, key: HKMetadataKeyElevationDescended)

            // Wave 2: per-second time-series samples
            let timeSeries = (try? await fetchTimeSeries(for: w)) ?? .empty

            // Wave 1: derive auto-distance splits from the route (1 km / 1 mi).
            // Adapter renders metric splits by default; renderers handle unit display.
            let splits = (try? await deriveSplits(workout: w, route: route)) ?? []

            results.append(WorkoutValue(
                activityType: w.workoutActivityType.rawValue,
                duration: w.duration,
                startDate: w.startDate,
                endDate: w.endDate,
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

    /// Reads HKWorkoutEvents of type .lap and .segment off the workout — these
    /// represent manual lap markers (.lap) and auto-distance splits (.segment).
    /// We surface both as `WorkoutLap` entries; auto-mile/km splits are derived
    /// separately from the route.
    ///
    /// Distance is summed from the supplied `distanceSamples` (matches Apple
    /// Health). Falls back to `HKMetadataKeyAverageSpeed × duration` when no
    /// distance samples cover the lap, which some third-party apps populate.
    private func extractLaps(from workout: HKWorkout, distanceSamples: [QuantitySampleValue]) -> [WorkoutLap] {
        guard let events = workout.workoutEvents, !events.isEmpty else { return [] }
        var laps: [WorkoutLap] = []
        for event in events where event.type == .lap || event.type == .segment {
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
    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
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

    /// Derives auto-distance splits (every 1 km) from the route. Each split's
    /// avgHeartRate is averaged from HR samples falling inside the split's
    /// time window. Returns empty if route has no GPS-tracked distance.
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
                let avgHR = try? await fetchAverageHeartRate(workout: workout, start: lastSplitTime, end: splitEnd)
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
    private func fetchTimeSeries(for workout: HKWorkout) async throws -> WorkoutTimeSeries {
        let predicate = HKQuery.predicateForObjects(from: workout)

        async let heartRate     = fetchSamples(.heartRate, predicate: predicate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let altitude      = fetchAltitudeSeriesFromRoute(for: workout)

        switch workout.workoutActivityType {
        case .running:
            async let speed     = fetchSamples(.runningSpeed, predicate: predicate, unit: HKUnit.meter().unitDivided(by: .second()))
            async let power     = fetchSamples(.runningPower, predicate: predicate, unit: .watt())
            async let stride    = fetchSamples(.runningStrideLength, predicate: predicate, unit: .meter())
            async let gct       = fetchSamples(.runningGroundContactTime, predicate: predicate, unit: HKUnit.secondUnit(with: .milli))
            async let vertOsc   = fetchSamples(.runningVerticalOscillation, predicate: predicate, unit: .meterUnit(with: .centi))
            return WorkoutTimeSeries(
                heartRate: try await heartRate,
                speed: try await speed,
                power: try await power,
                cadence: [],   // running cadence is derived from steps; not available as a time-series natively
                strideLength: try await stride,
                groundContactTime: try await gct,
                verticalOscillation: try await vertOsc,
                altitude: try await altitude
            )
        case .cycling:
            async let speed     = fetchSamples(.cyclingSpeed, predicate: predicate, unit: HKUnit.meter().unitDivided(by: .second()))
            async let power     = fetchSamples(.cyclingPower, predicate: predicate, unit: .watt())
            async let cadence   = fetchSamples(.cyclingCadence, predicate: predicate, unit: HKUnit.count().unitDivided(by: .minute()))
            return WorkoutTimeSeries(
                heartRate: try await heartRate,
                speed: try await speed,
                power: try await power,
                cadence: try await cadence,
                altitude: try await altitude
            )
        default:
            return WorkoutTimeSeries(
                heartRate: try await heartRate,
                altitude: try await altitude
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
        return samples.map { TimeSeriesSample(timestamp: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Per-second altitude is encoded into HKWorkoutRoute CLLocation samples,
    /// so we re-extract it from the route rather than via a quantity query.
    private func fetchAltitudeSeriesFromRoute(for workout: HKWorkout) async throws -> [TimeSeriesSample] {
        let route = try await fetchRoute(for: workout)
        return route.compactMap { p in
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
        return samples.map { QuantitySampleValue(value: $0.quantity.doubleValue(for: u), startDate: $0.startDate, endDate: $0.endDate) }
    }

    // MARK: - State of Mind Queries (iOS 18+)

    func queryStateOfMind(predicate: NSPredicate?) async throws -> [StateOfMindSampleValue] {
        if #available(iOS 18.0, macOS 15.0, *) {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.stateOfMind(predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await descriptor.result(for: store)
            return samples.map { sample in
                StateOfMindSampleValue(
                    kind: Self.mapStateOfMindKind(sample.kind),
                    valence: sample.valence,
                    labels: sample.labels.map { Self.mapStateOfMindLabel($0) },
                    associations: sample.associations.map { Self.mapStateOfMindAssociation($0) },
                    startDate: sample.startDate
                )
            }
        } else {
            return []
        }
    }

    // MARK: - State of Mind Mapping Helpers

    @available(iOS 18.0, macOS 15.0, *)
    private static func mapStateOfMindKind(_ kind: HKStateOfMind.Kind) -> String {
        switch kind {
        case .momentaryEmotion: return "Momentary Emotion"
        case .dailyMood:        return "Daily Mood"
        @unknown default:       return "Momentary Emotion"
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private static func mapStateOfMindLabel(_ label: HKStateOfMind.Label) -> String {
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
        @unknown default:    return "Unknown"
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private static func mapStateOfMindAssociation(_ association: HKStateOfMind.Association) -> String {
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
        @unknown default:     return "Unknown"
        }
    }
}
