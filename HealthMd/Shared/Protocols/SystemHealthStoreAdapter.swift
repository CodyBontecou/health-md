//
//  SystemHealthStoreAdapter.swift
//  HealthMd
//
//  Production adapter wrapping HKHealthStore behind HealthStoreProviding.
//  Used as the default backend for HealthKitManager.
//

import Foundation
import HealthKit

final class SystemHealthStoreAdapter: HealthStoreProviding, @unchecked Sendable {
    private let store: HKHealthStore

    /// Canonical unit for each quantity type used by this app.
    /// When the adapter returns a Double from a statistics query, it uses this unit.
    private let unitMap: [HKQuantityTypeIdentifier: HKUnit] = [
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
        .vo2Max:                        HKUnit(from: "ml/kg*min"),
        .respiratoryRate:               HKUnit.count().unitDivided(by: .minute()),
        .oxygenSaturation:              .percent(),
        .bodyTemperature:               .degreeCelsius(),
        .bloodPressureSystolic:         .millimeterOfMercury(),
        .bloodPressureDiastolic:        .millimeterOfMercury(),
        .bloodGlucose:                  HKUnit(from: "mg/dL"),
        .bodyMass:                      .gramUnit(with: .kilo),
        .height:                        .meter(),
        .bodyMassIndex:                 .count(),
        .bodyFatPercentage:             .percent(),
        .leanBodyMass:                  .gramUnit(with: .kilo),
        .waistCircumference:            .meterUnit(with: .centi),
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
        .walkingStepLength:             .meterUnit(with: .centi),
        .walkingDoubleSupportPercentage: .percent(),
        .walkingAsymmetryPercentage:    .percent(),
        .stairAscentSpeed:              HKUnit.meter().unitDivided(by: .second()),
        .stairDescentSpeed:             HKUnit.meter().unitDivided(by: .second()),
        .sixMinuteWalkTestDistance:     .meter(),
        .headphoneAudioExposure:        .decibelAWeightedSoundPressureLevel(),
        .environmentalAudioExposure:    .decibelAWeightedSoundPressureLevel(),
    ]

    init(store: HKHealthStore = HKHealthStore()) {
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
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit(for: identifier))
    }

    // MARK: - Category Sample Queries

    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool) async throws -> [CategorySampleValue] {
        guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { return [] }
        let order: SortOrder = ascending ? .forward : .reverse
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: order)]
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
        return workouts.map { w in
            WorkoutValue(
                activityType: w.workoutActivityType.rawValue,
                duration: w.duration,
                startDate: w.startDate,
                endDate: w.endDate,
                totalEnergyBurned: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                totalDistance: w.totalDistance?.doubleValue(for: .meter())
            )
        }
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
}
