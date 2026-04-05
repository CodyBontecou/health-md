//
//  HealthKitManagerTests.swift
//  HealthMdTests
//
//  Deterministic tests for HealthKitManager using FakeHealthStore.
//  Covers: auth/error mapping, fetch orchestration, aggregation contracts,
//  observer/background delivery, and earliest-date discovery.
//

import XCTest
import HealthKit
@testable import HealthMd

// MARK: - Test Helpers

@MainActor
private func makeSUT(store: FakeHealthStore = FakeHealthStore()) -> HealthKitManager {
    HealthKitManager(store: store)
}

// MARK: - Authorization & Error Mapping Tests (TODO-4fac60b8)

final class HealthKitManagerAuthTests: XCTestCase {

    @MainActor
    func test_requestAuth_whenUnavailable_setsStatusNotAvailable() async throws {
        let store = FakeHealthStore()
        store.available = false
        let sut = makeSUT(store: store)

        try await sut.requestAuthorization()

        XCTAssertFalse(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Health data not available")
        XCTAssertFalse(store.authRequested)
    }

    @MainActor
    func test_requestAuth_whenAvailable_setsConnected() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        try await sut.requestAuthorization()

        XCTAssertTrue(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Connected")
        XCTAssertTrue(store.authRequested)
    }

    @MainActor
    func test_requestAuth_whenStoreThrows_propagatesError() async {
        let store = FakeHealthStore()
        store.shouldThrowOnAuth = NSError(domain: "HK", code: 5, userInfo: [NSLocalizedDescriptionKey: "Denied"])
        let sut = makeSUT(store: store)

        do {
            try await sut.requestAuthorization()
            XCTFail("Expected error to propagate")
        } catch {
            XCTAssertFalse(sut.isAuthorized)
            XCTAssertEqual(sut.authorizationStatus, "Not Connected")
        }
    }

    @MainActor
    func test_isHealthDataAvailable_reflectsStoreAvailability() async {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        XCTAssertTrue(sut.isHealthDataAvailable)
        store.available = false
        XCTAssertFalse(sut.isHealthDataAvailable)
    }

    @MainActor
    func test_initialState_isNotAuthorized() async {
        let sut = makeSUT()

        XCTAssertFalse(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Not Connected")
    }

    @MainActor
    func test_fetchHealthData_whenUnavailable_throwsDataNotAvailable() async {
        let store = FakeHealthStore()
        store.available = false
        let sut = makeSUT(store: store)

        do {
            _ = try await sut.fetchHealthData(for: Date())
            XCTFail("Expected error")
        } catch let error as HealthKitManager.HealthKitError {
            XCTAssertEqual(error, .dataNotAvailable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func test_errorDescriptions_areHumanReadable() async {
        XCTAssertNotNil(HealthKitManager.HealthKitError.dataNotAvailable.errorDescription)
        XCTAssertNotNil(HealthKitManager.HealthKitError.notAuthorized.errorDescription)
        XCTAssertNotNil(HealthKitManager.HealthKitError.dataProtectedWhileLocked.errorDescription)
    }
}

// MARK: - Fetch Orchestration Tests (TODO-e0f18bb4)

final class HealthKitManagerFetchTests: XCTestCase {

    @MainActor
    func test_fetchHealthData_allSuccess_returnsPopulatedData() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)

        XCTAssertEqual(data.activity.steps, 12500)
        XCTAssertEqual(data.activity.activeCalories, 520)
        XCTAssertEqual(data.heart.averageHeartRate, 72)
        XCTAssertEqual(data.vitals.respiratoryRateAvg, 15.5)
        XCTAssertEqual(data.body.weight, 75.0)
        XCTAssertEqual(data.nutrition.dietaryEnergy, 2100)
        XCTAssertEqual(data.mindfulness.mindfulSessions, 2)
        XCTAssertEqual(data.mobility.walkingSpeed, 1.4)
        XCTAssertEqual(data.hearing.headphoneAudioLevel, 72)
        XCTAssertEqual(data.workouts.count, 1)
    }

    @MainActor
    func test_fetchHealthData_partialFailure_nonLockError_continuesOtherCategories() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store)

        // Make sleep fail with a non-lock error
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] =
            HealthKitFixtures.genericQueryError

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)

        // Sleep should have defaults (zero durations)
        XCTAssertEqual(data.sleep.totalDuration, 0)
        // Other categories should still have data
        XCTAssertEqual(data.activity.steps, 12500)
        XCTAssertEqual(data.heart.averageHeartRate, 72)
    }

    @MainActor
    func test_fetchHealthData_allNonLockFailures_returnsEmptyHealthData() async throws {
        let store = FakeHealthStore()
        let genericError = HealthKitFixtures.genericQueryError

        // Make all query types fail
        for id in [HKQuantityTypeIdentifier.stepCount, .activeEnergyBurned, .basalEnergyBurned,
                    .appleExerciseTime, .flightsClimbed, .distanceWalkingRunning, .distanceCycling,
                    .distanceSwimming, .swimmingStrokeCount, .pushCount, .vo2Max,
                    .restingHeartRate, .walkingHeartRateAverage, .heartRate,
                    .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation,
                    .bodyTemperature, .bloodPressureSystolic, .bloodPressureDiastolic,
                    .bloodGlucose, .bodyMass, .height, .bodyMassIndex, .bodyFatPercentage,
                    .leanBodyMass, .waistCircumference, .dietaryEnergyConsumed, .dietaryProtein,
                    .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFatSaturated, .dietaryFiber,
                    .dietarySugar, .dietarySodium, .dietaryCholesterol, .dietaryWater,
                    .dietaryCaffeine, .walkingSpeed, .walkingStepLength,
                    .walkingDoubleSupportPercentage, .walkingAsymmetryPercentage,
                    .stairAscentSpeed, .stairDescentSpeed, .sixMinuteWalkTestDistance,
                    .headphoneAudioExposure, .environmentalAudioExposure] {
            store.errorsForSum[id.rawValue] = genericError
            store.errorsForAverage[id.rawValue] = genericError
            store.errorsForMin[id.rawValue] = genericError
            store.errorsForMax[id.rawValue] = genericError
            store.errorsForMostRecent[id.rawValue] = genericError
        }
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = genericError
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.appleStandHour.rawValue] = genericError
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.mindfulSession.rawValue] = genericError
        store.errorForWorkouts = genericError

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(for: Date())

        // Should return an empty HealthData without throwing
        XCTAssertEqual(data.sleep.totalDuration, 0)
        XCTAssertNil(data.activity.steps)
        XCTAssertNil(data.heart.averageHeartRate)
        XCTAssertNil(data.vitals.respiratoryRateAvg)
        XCTAssertNil(data.body.weight)
        XCTAssertNil(data.nutrition.dietaryEnergy)
        XCTAssertNil(data.mindfulness.mindfulMinutes)
        XCTAssertNil(data.mobility.walkingSpeed)
        XCTAssertNil(data.hearing.headphoneAudioLevel)
        XCTAssertTrue(data.workouts.isEmpty)
    }

    @MainActor
    func test_fetchHealthData_deviceLockedError_throwsDataProtectedWhileLocked() async {
        let store = FakeHealthStore()
        // Make sleep query throw a "protected" error
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] =
            HealthKitFixtures.deviceLockedError

        let sut = makeSUT(store: store)

        do {
            _ = try await sut.fetchHealthData(for: Date())
            XCTFail("Expected dataProtectedWhileLocked error")
        } catch let error as HealthKitManager.HealthKitError {
            XCTAssertEqual(error, .dataProtectedWhileLocked)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func test_fetchHealthData_authorizationError_throwsDataProtectedWhileLocked() async {
        let store = FakeHealthStore()
        // Error containing "authorization"
        store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(
            domain: "HK", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Request authorization denied by user"]
        )

        let sut = makeSUT(store: store)

        do {
            _ = try await sut.fetchHealthData(for: Date())
            XCTFail("Expected dataProtectedWhileLocked error")
        } catch let error as HealthKitManager.HealthKitError {
            XCTAssertEqual(error, .dataProtectedWhileLocked)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func test_fetchHealthData_emptyStore_returnsDefaultHealthData() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())

        XCTAssertEqual(data.sleep.totalDuration, 0)
        XCTAssertNil(data.activity.steps)
        XCTAssertNil(data.heart.restingHeartRate)
        XCTAssertTrue(data.workouts.isEmpty)
    }
}

// MARK: - Aggregation Contract Tests (TODO-847ca530)

final class HealthKitManagerAggregationTests: XCTestCase {

    // MARK: - Activity Aggregation

    @MainActor
    func test_activity_stepsConvertedToInt() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 8523.7
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.activity.steps, 8523)  // Truncated to Int
    }

    @MainActor
    func test_activity_flightsConvertedToInt() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.flightsClimbed.rawValue] = 5.9
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.activity.flightsClimbed, 5)
    }

    @MainActor
    func test_activity_caloriesReturnedAsDouble() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = 350.7
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.activity.activeCalories!, 350.7, accuracy: 0.01)
    }

    @MainActor
    func test_activity_standHours_deduplicatesByCalendarHour() async throws {
        let store = FakeHealthStore()
        let date = HealthKitFixtures.referenceDate
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let stoodValue = HKCategoryValueAppleStandHour.stood.rawValue

        // Two "stood" samples in the same hour — should count as 1
        let hour9a = calendar.date(byAdding: .hour, value: 9, to: startOfDay)!
        let hour9b = hour9a.addingTimeInterval(1800) // 9:30
        let hour10 = calendar.date(byAdding: .hour, value: 10, to: startOfDay)!

        store.categorySampleResults[HKCategoryTypeIdentifier.appleStandHour.rawValue] = [
            CategorySampleValue(value: stoodValue, startDate: hour9a, endDate: hour9a.addingTimeInterval(3600)),
            CategorySampleValue(value: stoodValue, startDate: hour9b, endDate: hour9b.addingTimeInterval(3600)),
            CategorySampleValue(value: stoodValue, startDate: hour10, endDate: hour10.addingTimeInterval(3600)),
        ]

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(for: date)

        XCTAssertEqual(data.activity.standHours, 2, "Two unique calendar hours should yield 2, not 3")
    }

    @MainActor
    func test_activity_vo2Max_mostRecentLookupThroughEndOfDay() async throws {
        let store = FakeHealthStore()
        store.statisticsMostRecent[HKQuantityTypeIdentifier.vo2Max.rawValue] = 42.5
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.activity.vo2Max!, 42.5, accuracy: 0.1)
    }

    @MainActor
    func test_activity_noSamples_allFieldsNil() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertNil(data.activity.steps)
        XCTAssertNil(data.activity.activeCalories)
        XCTAssertNil(data.activity.exerciseMinutes)
        XCTAssertNil(data.activity.standHours)
        XCTAssertNil(data.activity.flightsClimbed)
        XCTAssertNil(data.activity.vo2Max)
        XCTAssertNil(data.activity.walkingRunningDistance)
    }

    // MARK: - Heart Aggregation

    @MainActor
    func test_heart_fullData_allFieldsPopulated() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullHeart(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.heart.restingHeartRate!, 58, accuracy: 0.1)
        XCTAssertEqual(data.heart.walkingHeartRateAverage!, 105, accuracy: 0.1)
        XCTAssertEqual(data.heart.averageHeartRate!, 72, accuracy: 0.1)
        XCTAssertEqual(data.heart.heartRateMin!, 52, accuracy: 0.1)
        XCTAssertEqual(data.heart.heartRateMax!, 155, accuracy: 0.1)
        XCTAssertEqual(data.heart.hrv!, 42, accuracy: 0.1)
    }

    @MainActor
    func test_heart_noSamples_allFieldsNil() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertNil(data.heart.restingHeartRate)
        XCTAssertNil(data.heart.averageHeartRate)
        XCTAssertNil(data.heart.heartRateMin)
        XCTAssertNil(data.heart.heartRateMax)
        XCTAssertNil(data.heart.hrv)
    }

    // MARK: - Vitals Aggregation

    @MainActor
    func test_vitals_fullData_avgMinMax() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullVitals(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.vitals.respiratoryRateAvg!, 15.5, accuracy: 0.1)
        XCTAssertEqual(data.vitals.respiratoryRateMin!, 12.0, accuracy: 0.1)
        XCTAssertEqual(data.vitals.respiratoryRateMax!, 20.0, accuracy: 0.1)
        XCTAssertEqual(data.vitals.bloodOxygenAvg!, 0.97, accuracy: 0.01)
        XCTAssertEqual(data.vitals.bodyTemperatureAvg!, 36.6, accuracy: 0.1)
        XCTAssertEqual(data.vitals.bloodPressureSystolicAvg!, 120, accuracy: 0.1)
        XCTAssertEqual(data.vitals.bloodPressureDiastolicAvg!, 80, accuracy: 0.1)
        XCTAssertEqual(data.vitals.bloodGlucoseAvg!, 95, accuracy: 0.1)
    }

    @MainActor
    func test_vitals_sparseData_onlyTemperature() async throws {
        let store = FakeHealthStore()
        store.statisticsAverages[HKQuantityTypeIdentifier.bodyTemperature.rawValue] = 36.8
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.vitals.bodyTemperatureAvg!, 36.8, accuracy: 0.1)
        XCTAssertNil(data.vitals.respiratoryRateAvg)
        XCTAssertNil(data.vitals.bloodOxygenAvg)
    }

    // MARK: - Sleep Aggregation

    @MainActor
    func test_sleep_fullNight_inBedMinusAwake() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullSleep(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)

        // InBed: 8h = 28800s, Awake: 0.5h = 1800s → Total sleep: 27000s = 7.5h
        XCTAssertEqual(data.sleep.totalDuration, 27000, accuracy: 1)
        XCTAssertEqual(data.sleep.deepSleep, 5400, accuracy: 1)       // 1.5h
        XCTAssertEqual(data.sleep.remSleep, 7200, accuracy: 1)        // 2h
        XCTAssertEqual(data.sleep.coreSleep, 10800, accuracy: 1)      // 3h
        XCTAssertEqual(data.sleep.awakeTime, 1800, accuracy: 1)       // 0.5h
        XCTAssertEqual(data.sleep.inBedTime, 28800, accuracy: 1)      // 8h
        XCTAssertNotNil(data.sleep.sessionStart)
        XCTAssertNotNil(data.sleep.sessionEnd)
    }

    @MainActor
    func test_sleep_noInBed_fallbackToUnionOfStages() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateMinimalSleep(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)

        // 7 hours of unspecified sleep = 25200s
        XCTAssertEqual(data.sleep.totalDuration, 25200, accuracy: 1)
        XCTAssertNotNil(data.sleep.sessionStart)
        XCTAssertNotNil(data.sleep.sessionEnd)
    }

    @MainActor
    func test_sleep_empty_zeroValues() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.sleep.totalDuration, 0)
        XCTAssertEqual(data.sleep.deepSleep, 0)
        XCTAssertNil(data.sleep.sessionStart)
    }

    // MARK: - Body Aggregation

    @MainActor
    func test_body_fullData_allMostRecent() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullBody(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.body.weight!, 75.0, accuracy: 0.1)
        XCTAssertEqual(data.body.height!, 1.78, accuracy: 0.01)
        XCTAssertEqual(data.body.bmi!, 23.7, accuracy: 0.1)
        XCTAssertEqual(data.body.bodyFatPercentage!, 0.18, accuracy: 0.01)
    }

    // MARK: - Nutrition Aggregation

    @MainActor
    func test_nutrition_fullData_allSums() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullNutrition(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.nutrition.dietaryEnergy!, 2100, accuracy: 0.1)
        XCTAssertEqual(data.nutrition.protein!, 120, accuracy: 0.1)
        XCTAssertEqual(data.nutrition.carbohydrates!, 250, accuracy: 0.1)
        XCTAssertEqual(data.nutrition.fat!, 70, accuracy: 0.1)
    }

    // MARK: - Mindfulness Aggregation

    @MainActor
    func test_mindfulness_sessionsAndMinutes() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullMindfulness(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)
        XCTAssertEqual(data.mindfulness.mindfulSessions, 2)
        XCTAssertEqual(data.mindfulness.mindfulMinutes!, 15, accuracy: 0.1)  // 10 + 5 min
    }

    @MainActor
    func test_mindfulness_stateOfMind_mappedFromProtocol() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullMindfulness(store)
        store.stateOfMindResults = [
            StateOfMindSampleValue(kind: "Daily Mood", valence: 0.7, labels: ["Happy", "Grateful"], associations: ["Family"], startDate: Date()),
            StateOfMindSampleValue(kind: "Momentary Emotion", valence: -0.3, labels: ["Stressed"], associations: ["Work", "Tasks"], startDate: Date()),
        ]
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)
        XCTAssertEqual(data.mindfulness.stateOfMind.count, 2)
        XCTAssertEqual(data.mindfulness.stateOfMind[0].kind, .dailyMood)
        XCTAssertEqual(data.mindfulness.stateOfMind[0].valence, 0.7, accuracy: 0.01)
        XCTAssertEqual(data.mindfulness.stateOfMind[0].labels, ["Happy", "Grateful"])
        XCTAssertEqual(data.mindfulness.stateOfMind[1].kind, .momentaryEmotion)
        XCTAssertEqual(data.mindfulness.stateOfMind[1].associations, ["Work", "Tasks"])
    }

    @MainActor
    func test_mindfulness_stateOfMindFailure_preservesMindfulSessions() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullMindfulness(store)
        store.errorForStateOfMind = HealthKitFixtures.genericQueryError
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)
        // Mindful sessions should survive a State of Mind failure
        XCTAssertEqual(data.mindfulness.mindfulSessions, 2)
        XCTAssertTrue(data.mindfulness.stateOfMind.isEmpty)
    }

    // MARK: - Mobility Aggregation

    @MainActor
    func test_mobility_fullData() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullMobility(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.mobility.walkingSpeed!, 1.4, accuracy: 0.01)
        XCTAssertEqual(data.mobility.sixMinuteWalkDistance!, 520, accuracy: 0.1)
    }

    // MARK: - Hearing Aggregation

    @MainActor
    func test_hearing_averageValues() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullHearing(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.hearing.headphoneAudioLevel!, 72, accuracy: 0.1)
        XCTAssertEqual(data.hearing.environmentalSoundLevel!, 55, accuracy: 0.1)
    }

    // MARK: - Workout Aggregation

    @MainActor
    func test_workouts_mappedCorrectly() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateWorkouts(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)
        XCTAssertEqual(data.workouts.count, 1)
        XCTAssertEqual(data.workouts[0].workoutType, .running)
        XCTAssertEqual(data.workouts[0].duration, 1800)
        XCTAssertEqual(data.workouts[0].calories!, 300, accuracy: 0.1)
        XCTAssertEqual(data.workouts[0].distance!, 5000, accuracy: 0.1)
    }

    @MainActor
    func test_workouts_unknownActivityType_mapsToOther() async throws {
        let store = FakeHealthStore()
        store.workoutResults = [
            WorkoutValue(activityType: 99999, duration: 600, startDate: Date(), endDate: Date().addingTimeInterval(600), totalEnergyBurned: nil, totalDistance: nil)
        ]
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.workouts[0].workoutType, .other)
    }

    // MARK: - VO2 Max Regression Contract

    @MainActor
    func test_vo2Max_unitContract_returnsCorrectValue() async throws {
        // Regression: v1.7.5 crash was caused by invalid VO2 unit string.
        // This test verifies the protocol returns the correct numeric value.
        let store = FakeHealthStore()
        store.statisticsMostRecent[HKQuantityTypeIdentifier.vo2Max.rawValue] = 42.5
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.activity.vo2Max!, 42.5, accuracy: 0.01,
                       "VO2 Max value should pass through unmodified from the protocol layer")
    }

    // MARK: - Static Sleep Utilities

    func test_mergeIntervals_overlapping() {
        let base = Date()
        let intervals: [(start: Date, end: Date)] = [
            (start: base, end: base.addingTimeInterval(3600)),
            (start: base.addingTimeInterval(1800), end: base.addingTimeInterval(5400)),
        ]
        let merged = HealthKitManager.mergeIntervals(intervals)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].end.timeIntervalSince(merged[0].start), 5400, accuracy: 0.1)
    }

    func test_mergeIntervals_noOverlap() {
        let base = Date()
        let intervals: [(start: Date, end: Date)] = [
            (start: base, end: base.addingTimeInterval(3600)),
            (start: base.addingTimeInterval(7200), end: base.addingTimeInterval(10800)),
        ]
        let merged = HealthKitManager.mergeIntervals(intervals)
        XCTAssertEqual(merged.count, 2)
    }

    func test_mergeIntervals_empty() {
        let merged = HealthKitManager.mergeIntervals([])
        XCTAssertTrue(merged.isEmpty)
    }

    func test_totalDuration_mergedIntervals() {
        let base = Date()
        let intervals: [(start: Date, end: Date)] = [
            (start: base, end: base.addingTimeInterval(3600)),
            (start: base.addingTimeInterval(1800), end: base.addingTimeInterval(5400)),
        ]
        let total = HealthKitManager.totalDuration(of: intervals)
        XCTAssertEqual(total, 5400, accuracy: 0.1)
    }

    func test_computeTotalSleepDuration_withInBed_subtractsAwake() {
        let base = Date()
        let inBed = [(start: base, end: base.addingTimeInterval(28800))]  // 8h
        let awake = [(start: base.addingTimeInterval(3600), end: base.addingTimeInterval(5400))]  // 0.5h

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: [], remIntervals: [], coreIntervals: [],
            unspecifiedIntervals: [], awakeIntervals: awake, inBedIntervals: inBed
        )
        XCTAssertEqual(total, 27000, accuracy: 1)  // 8h - 0.5h = 7.5h
    }

    func test_computeTotalSleepDuration_noInBed_usesAsleepUnion() {
        let base = Date()
        let deep = [(start: base, end: base.addingTimeInterval(5400))]        // 1.5h
        let rem = [(start: base.addingTimeInterval(5400), end: base.addingTimeInterval(12600))]  // 2h

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: deep, remIntervals: rem, coreIntervals: [],
            unspecifiedIntervals: [], awakeIntervals: [], inBedIntervals: []
        )
        XCTAssertEqual(total, 12600, accuracy: 1)  // 1.5h + 2h = 3.5h
    }
}

// MARK: - Granular Data Tests

final class HealthKitManagerGranularDataTests: XCTestCase {

    @MainActor
    func test_fetchHealthData_granularFalse_returnsEmptySampleArrays() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store)
        HealthKitFixtures.populateGranularSamples(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate, includeGranularData: false)

        XCTAssertTrue(data.heart.heartRateSamples.isEmpty, "heartRateSamples should be empty when granular=false")
        XCTAssertTrue(data.heart.hrvSamples.isEmpty, "hrvSamples should be empty when granular=false")
        XCTAssertTrue(data.vitals.bloodOxygenSamples.isEmpty, "bloodOxygenSamples should be empty when granular=false")
        XCTAssertTrue(data.vitals.bloodGlucoseSamples.isEmpty, "bloodGlucoseSamples should be empty when granular=false")
        XCTAssertTrue(data.vitals.respiratoryRateSamples.isEmpty, "respiratoryRateSamples should be empty when granular=false")
        XCTAssertTrue(data.sleep.stages.isEmpty, "sleep stages should be empty when granular=false")
    }

    @MainActor
    func test_fetchHealthData_granularTrue_populatesHeartSamples() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullHeart(store)
        HealthKitFixtures.populateGranularSamples(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate, includeGranularData: true)

        XCTAssertEqual(data.heart.heartRateSamples.count, 5, "Should have 5 heart rate samples")
        XCTAssertEqual(data.heart.heartRateSamples[0].value, 55, accuracy: 0.1)
        XCTAssertEqual(data.heart.hrvSamples.count, 2, "Should have 2 HRV samples")
        XCTAssertEqual(data.heart.hrvSamples[0].value, 45, accuracy: 0.1)
    }

    @MainActor
    func test_fetchHealthData_granularTrue_populatesVitalsSamples() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullVitals(store)
        HealthKitFixtures.populateGranularSamples(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate, includeGranularData: true)

        XCTAssertEqual(data.vitals.bloodOxygenSamples.count, 3)
        XCTAssertEqual(data.vitals.bloodOxygenSamples[0].value, 0.96, accuracy: 0.01)
        XCTAssertEqual(data.vitals.bloodGlucoseSamples.count, 2)
        XCTAssertEqual(data.vitals.bloodGlucoseSamples[0].value, 90, accuracy: 0.1)
        XCTAssertEqual(data.vitals.respiratoryRateSamples.count, 2)
        XCTAssertEqual(data.vitals.respiratoryRateSamples[0].value, 14, accuracy: 0.1)
    }

    @MainActor
    func test_fetchHealthData_granularTrue_populatesSleepStages() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullSleep(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate, includeGranularData: true)

        XCTAssertFalse(data.sleep.stages.isEmpty, "Sleep stages should be populated when granular=true")
        let stageNames = Set(data.sleep.stages.map { $0.stage })
        XCTAssertTrue(stageNames.contains("deep"), "Should include deep stage")
        XCTAssertTrue(stageNames.contains("rem"), "Should include rem stage")
        XCTAssertTrue(stageNames.contains("core"), "Should include core stage")
        // Stages should be sorted by startDate
        for i in 1..<data.sleep.stages.count {
            XCTAssertLessThanOrEqual(data.sleep.stages[i - 1].startDate, data.sleep.stages[i].startDate,
                                     "Sleep stages should be sorted by startDate")
        }
    }

    @MainActor
    func test_fetchHealthData_granularTrue_aggregatesStillPresent() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullHeart(store)
        HealthKitFixtures.populateGranularSamples(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate, includeGranularData: true)

        // Aggregates should still be populated alongside samples
        XCTAssertEqual(data.heart.restingHeartRate!, 58, accuracy: 0.1)
        XCTAssertEqual(data.heart.averageHeartRate!, 72, accuracy: 0.1)
        XCTAssertEqual(data.heart.hrv!, 42, accuracy: 0.1)
    }
}

// MARK: - Observer / Background Delivery + Earliest Date Tests (TODO-c389cf56)

final class HealthKitManagerObserverTests: XCTestCase {

    @MainActor
    func test_monitoredTypes_includesExpectedIdentifiers() async {
        let sut = makeSUT()
        let identifiers = sut.monitoredTypeIdentifiers

        XCTAssertTrue(identifiers.contains(HKCategoryTypeIdentifier.sleepAnalysis.rawValue),
                       "Should monitor sleep analysis")
        XCTAssertTrue(identifiers.contains(HKQuantityTypeIdentifier.stepCount.rawValue),
                       "Should monitor step count")
        XCTAssertEqual(identifiers.count, 2, "Should monitor exactly 2 types")
    }

    @MainActor
    func test_observerQueries_initiallyEmpty() async {
        let sut = makeSUT()
        XCTAssertTrue(sut.observerQueries.isEmpty)
    }

    @MainActor
    func test_onBackgroundDelivery_callbackCanBeSet() async {
        let sut = makeSUT()
        var called = false
        sut.onBackgroundDelivery = { called = true }
        sut.onBackgroundDelivery?()
        XCTAssertTrue(called)
    }

    // MARK: - Earliest Date Discovery

    @MainActor
    func test_findEarliestDate_selectsMinimumAcrossTypes() async {
        let store = FakeHealthStore()
        HealthKitFixtures.populateEarliestDateScenario(store)
        let sut = makeSUT(store: store)

        let earliest = await sut.findEarliestHealthDataDate()

        // The heart rate sample has the oldest date (Jul 2017)
        let expected = Date(timeIntervalSince1970: 1_500_000_000)
        XCTAssertEqual(earliest, expected)
    }

    @MainActor
    func test_findEarliestDate_emptyStore_returnsNil() async {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let earliest = await sut.findEarliestHealthDataDate()
        XCTAssertNil(earliest)
    }

    @MainActor
    func test_findEarliestDate_gracefulPerQueryFailure() async {
        let store = FakeHealthStore()
        let genericError = HealthKitFixtures.genericQueryError

        // Make some queries fail, but steps succeeds
        store.errorsForQuantitySamples[HKQuantityTypeIdentifier.heartRate.rawValue] = genericError
        store.errorsForQuantitySamples[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = genericError

        let stepsDate = Date(timeIntervalSince1970: 1_600_000_000)
        store.quantitySampleResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [
            QuantitySampleValue(value: 100, startDate: stepsDate, endDate: stepsDate)
        ]

        let sut = makeSUT(store: store)
        let earliest = await sut.findEarliestHealthDataDate()

        XCTAssertEqual(earliest, stepsDate, "Should still find earliest from succeeding queries")
    }

    @MainActor
    func test_findEarliestDate_workoutCanBeEarliest() async {
        let store = FakeHealthStore()
        let workoutDate = Date(timeIntervalSince1970: 1_400_000_000) // Earliest
        let stepsDate = Date(timeIntervalSince1970: 1_600_000_000)

        store.quantitySampleResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [
            QuantitySampleValue(value: 100, startDate: stepsDate, endDate: stepsDate)
        ]
        store.workoutResults = [
            WorkoutValue(activityType: 37, duration: 1800, startDate: workoutDate, endDate: workoutDate.addingTimeInterval(1800), totalEnergyBurned: nil, totalDistance: nil)
        ]

        let sut = makeSUT(store: store)
        let earliest = await sut.findEarliestHealthDataDate()

        XCTAssertEqual(earliest, workoutDate)
    }

    @MainActor
    func test_findEarliestDate_sleepCanBeEarliest() async {
        let store = FakeHealthStore()
        let sleepDate = Date(timeIntervalSince1970: 1_300_000_000)  // Earliest
        let stepsDate = Date(timeIntervalSince1970: 1_600_000_000)

        store.quantitySampleResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [
            QuantitySampleValue(value: 100, startDate: stepsDate, endDate: stepsDate)
        ]
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, startDate: sleepDate, endDate: sleepDate.addingTimeInterval(28800))
        ]

        let sut = makeSUT(store: store)
        let earliest = await sut.findEarliestHealthDataDate()

        XCTAssertEqual(earliest, sleepDate)
    }
}
