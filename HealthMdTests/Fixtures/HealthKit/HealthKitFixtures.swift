//
//  HealthKitFixtures.swift
//  HealthMdTests
//
//  Reusable fake HealthKit dataset fixtures for category-level tests.
//  Provides factory methods to populate FakeHealthStore with deterministic data
//  for sleep, activity, heart, vitals, body, nutrition, mindfulness,
//  mobility, hearing, and workouts.
//

import Foundation
import HealthKit
@testable import HealthMd

// MARK: - Reference Date

enum HealthKitFixtures {
    /// Fixed reference date: 2026-03-15 00:00:00 UTC
    static let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 0
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }()

    // MARK: - Sleep Fixtures

    /// Populates a FakeHealthStore with a full night of sleep data.
    /// Deep: 1.5h, REM: 2h, Core: 3h, Awake: 0.5h, InBed: 8h
    static func populateFullSleep(_ store: FakeHealthStore, date: Date = referenceDate) {
        let calendar = Calendar.current
        let bedtime = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: date)!)!
        let wakeTime = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date)!

        let deepStart = bedtime.addingTimeInterval(1800)  // 22:30
        let deepEnd = deepStart.addingTimeInterval(5400)    // 00:00 (1.5h)
        let remStart = deepEnd.addingTimeInterval(600)       // 00:10
        let remEnd = remStart.addingTimeInterval(7200)       // 02:10 (2h)
        let awakeStart = remEnd                              // 02:10
        let awakeEnd = awakeStart.addingTimeInterval(1800)   // 02:40 (0.5h)
        let coreStart = awakeEnd                             // 02:40
        let coreEnd = coreStart.addingTimeInterval(10800)    // 05:40 (3h)

        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.inBed.rawValue, startDate: bedtime, endDate: wakeTime),
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, startDate: deepStart, endDate: deepEnd),
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, startDate: remStart, endDate: remEnd),
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.awake.rawValue, startDate: awakeStart, endDate: awakeEnd),
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, startDate: coreStart, endDate: coreEnd),
        ]
    }

    /// Populates a FakeHealthStore with minimal sleep data (only unspecified stages, no InBed).
    static func populateMinimalSleep(_ store: FakeHealthStore, date: Date = referenceDate) {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: date)!)!
        let end = start.addingTimeInterval(25200) // 7 hours

        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, startDate: start, endDate: end),
        ]
    }

    // MARK: - Activity Fixtures

    /// Populates a FakeHealthStore with a full activity day.
    static func populateFullActivity(_ store: FakeHealthStore, date: Date = referenceDate) {
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 12500
        store.statisticsSums[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = 520
        store.statisticsSums[HKQuantityTypeIdentifier.basalEnergyBurned.rawValue] = 1800
        store.statisticsSums[HKQuantityTypeIdentifier.appleExerciseTime.rawValue] = 45
        store.statisticsSums[HKQuantityTypeIdentifier.flightsClimbed.rawValue] = 8
        store.statisticsSums[HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue] = 9500
        store.statisticsSums[HKQuantityTypeIdentifier.distanceCycling.rawValue] = 15000
        store.statisticsSums[HKQuantityTypeIdentifier.distanceSwimming.rawValue] = 1500
        store.statisticsSums[HKQuantityTypeIdentifier.swimmingStrokeCount.rawValue] = 450
        store.statisticsSums[HKQuantityTypeIdentifier.pushCount.rawValue] = 0
        store.statisticsMostRecent[HKQuantityTypeIdentifier.vo2Max.rawValue] = 42.5

        // Stand hours: 10 unique hours with "stood" value
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        var standSamples: [CategorySampleValue] = []
        let stoodValue = HKCategoryValueAppleStandHour.stood.rawValue
        let idleValue = HKCategoryValueAppleStandHour.idle.rawValue
        for hour in 8..<20 {
            let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay)!
            let value = hour < 18 ? stoodValue : idleValue  // 10 stood, 2 idle
            standSamples.append(CategorySampleValue(value: value, startDate: hourStart, endDate: hourStart.addingTimeInterval(3600)))
        }
        store.categorySampleResults[HKCategoryTypeIdentifier.appleStandHour.rawValue] = standSamples
    }

    // MARK: - Heart Fixtures

    /// Populates a FakeHealthStore with heart data.
    static func populateFullHeart(_ store: FakeHealthStore) {
        store.statisticsMostRecent[HKQuantityTypeIdentifier.restingHeartRate.rawValue] = 58
        store.statisticsMostRecent[HKQuantityTypeIdentifier.walkingHeartRateAverage.rawValue] = 105
        store.statisticsAverages[HKQuantityTypeIdentifier.heartRate.rawValue] = 72
        store.statisticsMins[HKQuantityTypeIdentifier.heartRate.rawValue] = 52
        store.statisticsMaxes[HKQuantityTypeIdentifier.heartRate.rawValue] = 155
        store.statisticsAverages[HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue] = 42
    }

    // MARK: - Vitals Fixtures

    /// Populates a FakeHealthStore with vitals data.
    static func populateFullVitals(_ store: FakeHealthStore) {
        store.statisticsAverages[HKQuantityTypeIdentifier.respiratoryRate.rawValue] = 15.5
        store.statisticsMins[HKQuantityTypeIdentifier.respiratoryRate.rawValue] = 12.0
        store.statisticsMaxes[HKQuantityTypeIdentifier.respiratoryRate.rawValue] = 20.0

        store.statisticsAverages[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] = 0.97
        store.statisticsMins[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] = 0.95
        store.statisticsMaxes[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] = 0.99

        store.statisticsAverages[HKQuantityTypeIdentifier.bodyTemperature.rawValue] = 36.6
        store.statisticsMins[HKQuantityTypeIdentifier.bodyTemperature.rawValue] = 36.2
        store.statisticsMaxes[HKQuantityTypeIdentifier.bodyTemperature.rawValue] = 37.1

        store.statisticsAverages[HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue] = 120
        store.statisticsMins[HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue] = 115
        store.statisticsMaxes[HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue] = 130

        store.statisticsAverages[HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue] = 80
        store.statisticsMins[HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue] = 75
        store.statisticsMaxes[HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue] = 85

        store.statisticsAverages[HKQuantityTypeIdentifier.bloodGlucose.rawValue] = 95
        store.statisticsMins[HKQuantityTypeIdentifier.bloodGlucose.rawValue] = 80
        store.statisticsMaxes[HKQuantityTypeIdentifier.bloodGlucose.rawValue] = 140
    }

    // MARK: - Body Fixtures

    static func populateFullBody(_ store: FakeHealthStore) {
        store.statisticsMostRecent[HKQuantityTypeIdentifier.bodyMass.rawValue] = 75.0
        store.statisticsMostRecent[HKQuantityTypeIdentifier.height.rawValue] = 1.78
        store.statisticsMostRecent[HKQuantityTypeIdentifier.bodyMassIndex.rawValue] = 23.7
        store.statisticsMostRecent[HKQuantityTypeIdentifier.bodyFatPercentage.rawValue] = 0.18
        store.statisticsMostRecent[HKQuantityTypeIdentifier.leanBodyMass.rawValue] = 61.5
        store.statisticsMostRecent[HKQuantityTypeIdentifier.waistCircumference.rawValue] = 0.82
    }

    // MARK: - Nutrition Fixtures

    static func populateFullNutrition(_ store: FakeHealthStore) {
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue] = 2100
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryProtein.rawValue] = 120
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue] = 250
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryFatTotal.rawValue] = 70
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryFatSaturated.rawValue] = 22
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryFiber.rawValue] = 28
        store.statisticsSums[HKQuantityTypeIdentifier.dietarySugar.rawValue] = 45
        store.statisticsSums[HKQuantityTypeIdentifier.dietarySodium.rawValue] = 2300
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryCholesterol.rawValue] = 300
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryWater.rawValue] = 2.5
        store.statisticsSums[HKQuantityTypeIdentifier.dietaryCaffeine.rawValue] = 200
    }

    // MARK: - Mindfulness Fixtures

    static func populateFullMindfulness(_ store: FakeHealthStore, date: Date = referenceDate) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let session1Start = calendar.date(byAdding: .hour, value: 7, to: startOfDay)!
        let session1End = session1Start.addingTimeInterval(600)    // 10 min
        let session2Start = calendar.date(byAdding: .hour, value: 20, to: startOfDay)!
        let session2End = session2Start.addingTimeInterval(300)    // 5 min

        store.categorySampleResults[HKCategoryTypeIdentifier.mindfulSession.rawValue] = [
            CategorySampleValue(value: 0, startDate: session1Start, endDate: session1End),
            CategorySampleValue(value: 0, startDate: session2Start, endDate: session2End),
        ]
    }

    // MARK: - Mobility Fixtures

    static func populateFullMobility(_ store: FakeHealthStore) {
        store.statisticsAverages[HKQuantityTypeIdentifier.walkingSpeed.rawValue] = 1.4
        store.statisticsAverages[HKQuantityTypeIdentifier.walkingStepLength.rawValue] = 0.72
        store.statisticsAverages[HKQuantityTypeIdentifier.walkingDoubleSupportPercentage.rawValue] = 0.28
        store.statisticsAverages[HKQuantityTypeIdentifier.walkingAsymmetryPercentage.rawValue] = 0.08
        store.statisticsAverages[HKQuantityTypeIdentifier.stairAscentSpeed.rawValue] = 0.35
        store.statisticsAverages[HKQuantityTypeIdentifier.stairDescentSpeed.rawValue] = 0.40
        store.statisticsMostRecent[HKQuantityTypeIdentifier.sixMinuteWalkTestDistance.rawValue] = 520
    }

    // MARK: - Hearing Fixtures

    static func populateFullHearing(_ store: FakeHealthStore) {
        store.statisticsAverages[HKQuantityTypeIdentifier.headphoneAudioExposure.rawValue] = 72
        store.statisticsAverages[HKQuantityTypeIdentifier.environmentalAudioExposure.rawValue] = 55
    }

    // MARK: - Workout Fixtures

    static func populateWorkouts(_ store: FakeHealthStore, date: Date = referenceDate) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let runStart = calendar.date(byAdding: .hour, value: 7, to: startOfDay)!
        let runEnd = runStart.addingTimeInterval(1800)

        store.workoutResults = [
            WorkoutValue(
                activityType: HKWorkoutActivityType.running.rawValue,
                duration: 1800,
                startDate: runStart,
                endDate: runEnd,
                totalEnergyBurned: 300,
                totalDistance: 5000
            )
        ]
    }

    // MARK: - Granular Sample Fixtures

    /// Populates quantity samples for granular time-series data:
    /// heart rate, HRV, blood oxygen, blood glucose, respiratory rate.
    static func populateGranularSamples(_ store: FakeHealthStore, date: Date = referenceDate) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let h6  = calendar.date(byAdding: .hour, value: 6, to: startOfDay)!
        let h9  = calendar.date(byAdding: .hour, value: 9, to: startOfDay)!
        let h12 = calendar.date(byAdding: .hour, value: 12, to: startOfDay)!
        let h15 = calendar.date(byAdding: .hour, value: 15, to: startOfDay)!
        let h20 = calendar.date(byAdding: .hour, value: 20, to: startOfDay)!

        store.quantitySampleResults[HKQuantityTypeIdentifier.heartRate.rawValue] = [
            QuantitySampleValue(value: 55, startDate: h6, endDate: h6),
            QuantitySampleValue(value: 72, startDate: h9, endDate: h9),
            QuantitySampleValue(value: 85, startDate: h12, endDate: h12),
            QuantitySampleValue(value: 68, startDate: h15, endDate: h15),
            QuantitySampleValue(value: 60, startDate: h20, endDate: h20),
        ]

        store.quantitySampleResults[HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue] = [
            QuantitySampleValue(value: 45, startDate: h6, endDate: h6),
            QuantitySampleValue(value: 38, startDate: h20, endDate: h20),
        ]

        store.quantitySampleResults[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] = [
            QuantitySampleValue(value: 0.96, startDate: h6, endDate: h6),
            QuantitySampleValue(value: 0.98, startDate: h12, endDate: h12),
            QuantitySampleValue(value: 0.97, startDate: h20, endDate: h20),
        ]

        store.quantitySampleResults[HKQuantityTypeIdentifier.bloodGlucose.rawValue] = [
            QuantitySampleValue(value: 90, startDate: h9, endDate: h9),
            QuantitySampleValue(value: 110, startDate: h15, endDate: h15),
        ]

        store.quantitySampleResults[HKQuantityTypeIdentifier.respiratoryRate.rawValue] = [
            QuantitySampleValue(value: 14, startDate: h6, endDate: h6),
            QuantitySampleValue(value: 16, startDate: h12, endDate: h12),
        ]
    }

    // MARK: - Composite Fixtures

    /// Populates ALL categories with full data.
    static func populateAllCategories(_ store: FakeHealthStore, date: Date = referenceDate) {
        populateFullSleep(store, date: date)
        populateFullActivity(store, date: date)
        populateFullHeart(store)
        populateFullVitals(store)
        populateFullBody(store)
        populateFullNutrition(store)
        populateFullMindfulness(store, date: date)
        populateFullMobility(store)
        populateFullHearing(store)
        populateWorkouts(store, date: date)
    }

    // MARK: - Error Fixtures

    /// An error whose localizedDescription contains "protected" — triggers device-locked detection.
    static let deviceLockedError = NSError(
        domain: "com.apple.healthkit",
        code: 6,
        userInfo: [NSLocalizedDescriptionKey: "Health data is protected while device is locked"]
    )

    /// A generic non-lock error for testing partial failure scenarios.
    static let genericQueryError = NSError(
        domain: "com.apple.healthkit",
        code: 99,
        userInfo: [NSLocalizedDescriptionKey: "Query failed for unknown reason"]
    )

    // MARK: - Earliest Date Fixtures

    /// Populates quantity samples and workouts with varied dates for earliest-date discovery.
    static func populateEarliestDateScenario(_ store: FakeHealthStore) {
        let oldest = Date(timeIntervalSince1970: 1_500_000_000) // Jul 2017
        let newer = Date(timeIntervalSince1970: 1_600_000_000)  // Sep 2020
        let newest = Date(timeIntervalSince1970: 1_700_000_000) // Nov 2023

        store.quantitySampleResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [
            QuantitySampleValue(value: 100, startDate: newer, endDate: newer)
        ]
        store.quantitySampleResults[HKQuantityTypeIdentifier.heartRate.rawValue] = [
            QuantitySampleValue(value: 70, startDate: oldest, endDate: oldest)
        ]
        store.quantitySampleResults[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = [
            QuantitySampleValue(value: 200, startDate: newest, endDate: newest)
        ]
        store.workoutResults = [
            WorkoutValue(activityType: 37, duration: 1800, startDate: newer, endDate: newer.addingTimeInterval(1800), totalEnergyBurned: nil, totalDistance: nil)
        ]
        // Sleep: no samples (tests empty path)
    }
}
