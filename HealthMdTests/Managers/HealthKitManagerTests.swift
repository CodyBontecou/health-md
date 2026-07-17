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
private func makeSUT(
    store: FakeHealthStore = FakeHealthStore(),
    medicationAuthorizationRequested: Bool = false,
    visionAuthorizationRequested: Bool = false,
    healthAuthorizationRequested: Bool = false,
    completedOnboarding: Bool = false,
    authorizationMigrationCompleted: Bool = false
) -> HealthKitManager {
    let suiteName = "HealthKitManagerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    if medicationAuthorizationRequested {
        defaults.set(true, forKey: "healthKit.medicationAuthorizationRequested")
    }
    if visionAuthorizationRequested {
        defaults.set(true, forKey: "healthKit.visionAuthorizationRequested")
    }
    if healthAuthorizationRequested {
        defaults.set(true, forKey: "healthKit.authorizationRequested")
    }
    if completedOnboarding {
        defaults.set(true, forKey: "hasCompletedOnboarding")
    }
    if authorizationMigrationCompleted {
        defaults.set(true, forKey: "healthKit.authorizationStateMigrationCompleted")
    }
    return HealthKitManager(store: store, userDefaults: defaults)
}

// MARK: - Authorization & Error Mapping Tests (TODO-4fac60b8)

final class HealthKitManagerAuthTests: XCTestCase {

    @MainActor
    func test_requestAuth_whenUnavailable_setsStatusNotAvailable() async throws {
        let store = FakeHealthStore()
        store.available = false
        let sut = makeSUT(store: store)

        let outcome = try await sut.requestAuthorization()

        XCTAssertEqual(outcome, .unavailable)
        XCTAssertFalse(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Health data not available")
        XCTAssertFalse(store.authRequested)
    }

    @MainActor
    func test_requestAuth_whenAvailable_setsConnected() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let outcome = try await sut.requestAuthorization()

        XCTAssertEqual(outcome, .requested)
        XCTAssertTrue(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Connected")
        XCTAssertTrue(store.authRequested)
    }

    @MainActor
    func test_requestAuth_usesAvailabilityFilteredCatalogTypes() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)
        let expected = HealthKitRecordCatalog.resolvedAuthorizationObjectTypes()

        try await sut.requestAuthorization()

        XCTAssertEqual(store.statusReadTypes, expected)
        XCTAssertEqual(store.requestedReadTypes, expected)
        XCTAssertFalse(store.requestedReadTypes.contains { $0.identifier == HealthKitRecordCatalog.medicationDoseEventIdentifier })
        XCTAssertTrue(
            Set(store.requestedReadTypes.map(\.identifier))
                .isDisjoint(with: HealthKitRecordCatalog.standardAuthorizationDisallowedIdentifiers)
        )
        XCTAssertTrue(store.requestedReadTypes.contains { $0.identifier == "HKQuantityTypeIdentifierBloodPressureSystolic" })
        XCTAssertTrue(store.requestedReadTypes.contains { $0.identifier == "HKQuantityTypeIdentifierBloodPressureDiastolic" })
        XCTAssertTrue(store.requestedReadTypes.contains { $0.identifier == "HKQuantityTypeIdentifierStepCount" })
    }

    @MainActor
    func test_requestAuth_doesNotRequestMedicationAuthorization() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        try await sut.requestAuthorization()

        XCTAssertTrue(store.authRequested)
        XCTAssertFalse(store.medicationAuthRequested)
        XCTAssertFalse(sut.isMedicationAuthorizationRequested)
    }

    @MainActor
    func test_requestMedicationAuthorization_setsMedicationState() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        try await sut.requestMedicationAuthorization(force: true)

        XCTAssertTrue(store.medicationAuthRequested)
        XCTAssertTrue(sut.isMedicationAuthorizationRequested)
        XCTAssertEqual(sut.medicationAuthorizationStatus, "Medication access selected")
    }

    @MainActor
    func test_fetchHealthData_withoutMedicationAuthorization_skipsMedicationQueries() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store)
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)

        XCTAssertFalse(data.medications?.hasData ?? true)
        XCTAssertFalse(store.medicationsQueried)
        XCTAssertFalse(store.medicationDoseEventsQueried)
    }

    @MainActor
    func test_fetchHealthData_medicationFailure_recordsPartialFailureAndContinues() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(store)
        store.errorForMedications = HealthKitFixtures.genericQueryError
        let sut = makeSUT(store: store, medicationAuthorizationRequested: true)

        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)

        XCTAssertEqual(data.activity.steps, 12500)
        XCTAssertEqual(data.heart.averageHeartRate, 72)
        XCTAssertTrue(store.medicationsQueried)
        XCTAssertNil(data.medications)

        let failure = try XCTUnwrap(data.partialFailures.first { $0.dataType == "medications" })
        XCTAssertTrue(failure.dateRangeDescription.contains("2026-03-15"))
        XCTAssertTrue(failure.errorDescription.contains("Query failed"))
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
    func test_initialState_whenHealthAuthorizationWasPreviouslyRequested_assumesConnected() async {
        let sut = makeSUT(healthAuthorizationRequested: true)

        XCTAssertTrue(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Connected")
    }

    @MainActor
    func test_initialState_migratesExistingOnboardedUsersToConnectedWithoutPrompting() async {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store, completedOnboarding: true)

        XCTAssertTrue(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Connected")
        XCTAssertFalse(store.authRequested)
    }

    @MainActor
    func test_initialState_doesNotTreatFutureCompletedOnboardingAsLegacyMigration() async {
        let sut = makeSUT(
            completedOnboarding: true,
            authorizationMigrationCompleted: true
        )

        XCTAssertFalse(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Not Connected")
    }

    @MainActor
    func test_requestAuth_whenAuthorizationStatusUnnecessary_doesNotShowSystemSheet() async throws {
        let store = FakeHealthStore()
        store.authRequestStatus = .unnecessary
        let sut = makeSUT(store: store)

        let outcome = try await sut.requestAuthorization()

        XCTAssertEqual(outcome, .unnecessary)
        XCTAssertTrue(sut.isAuthorized)
        XCTAssertEqual(sut.authorizationStatus, "Connected")
        XCTAssertFalse(store.authRequested)
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
        let sut = makeSUT(store: store, medicationAuthorizationRequested: true)

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
        XCTAssertEqual(data.medications?.medications.count, 1)
        XCTAssertEqual(data.medications?.doseEvents.count, 1)
        XCTAssertEqual(data.medications?.doseEvents.first?.logStatus, .taken)
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
        XCTAssertEqual(data.partialFailures.count, 1)
        XCTAssertEqual(data.partialFailures.first?.dataType, "sleep")
        XCTAssertTrue(data.partialFailures.first?.dateRangeDescription.contains("2026-03-15") ?? false)
        XCTAssertTrue(data.partialFailures.first?.errorDescription.isEmpty == false)
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
        XCTAssertFalse(data.partialFailures.isEmpty)
        XCTAssertTrue(data.partialFailures.contains { $0.dataType == "sleep" })
        XCTAssertTrue(data.partialFailures.contains { $0.dataType == "workouts" })
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
    func test_fetchHealthData_withMetricSelection_skipsUnselectedLockedCategories() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1234
        store.errorsForCategorySamples[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] =
            HealthKitFixtures.deviceLockedError
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("steps")
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            metricSelection: selection
        )

        XCTAssertEqual(data.activity.steps, 1234)
        XCTAssertEqual(data.sleep.totalDuration, 0)
        XCTAssertFalse(store.queriedCategoryIdentifiers.contains(HKCategoryTypeIdentifier.sleepAnalysis.rawValue))
    }

    @MainActor
    func test_fetchHealthData_authorizationError_recordsPartialFailureAndContinues() async throws {
        let store = FakeHealthStore()
        store.statisticsAverages[HKQuantityTypeIdentifier.heartRate.rawValue] = 72
        store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(
            domain: HKError.errorDomain,
            code: HKError.Code.errorAuthorizationDenied.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Request authorization denied by user"]
        )

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(for: Date())

        XCTAssertNil(data.activity.steps)
        XCTAssertEqual(data.heart.averageHeartRate, 72)
        XCTAssertTrue(data.partialFailures.contains { failure in
            failure.dataType == "activity" && failure.errorDescription.contains("authorization")
        })
    }

    @MainActor
    func test_fetchHealthData_vitalsAuthorizationNotDeterminedForOneMetricPreservesOtherVitals() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullVitals(store)
        store.errorsForAverage[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] = NSError(
            domain: HKError.errorDomain,
            code: HKError.Code.errorAuthorizationNotDetermined.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Authorization not determined"]
        )

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate)

        XCTAssertEqual(data.vitals.respiratoryRateAvg, 15.5)
        XCTAssertEqual(data.vitals.bodyTemperatureAvg, 36.6)
        XCTAssertNil(data.vitals.bloodOxygenAvg)
        XCTAssertTrue(data.partialFailures.contains { failure in
            failure.dataType == "blood oxygen" &&
            failure.errorDescription.contains("Authorization not determined")
        })
        XCTAssertFalse(data.partialFailures.contains { $0.dataType == "vitals" })
        XCTAssertFalse(store.authRequested)
    }

    @MainActor
    func test_fetchHealthData_metricSelectionSkipsUnselectedVitalsMetricWithUndeterminedAuthorization() async throws {
        let store = FakeHealthStore()
        store.statisticsAverages[HKQuantityTypeIdentifier.respiratoryRate.rawValue] = 15.5
        store.errorsForAverage[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] = NSError(
            domain: HKError.errorDomain,
            code: HKError.Code.errorAuthorizationNotDetermined.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Authorization not determined"]
        )
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("respiratory_rate")

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            metricSelection: selection
        )

        XCTAssertEqual(data.vitals.respiratoryRateAvg, 15.5)
        XCTAssertFalse(store.queriedAverageIdentifiers.contains(HKQuantityTypeIdentifier.oxygenSaturation.rawValue))
        XCTAssertTrue(data.partialFailures.isEmpty)
    }

    @MainActor
    func test_fetchHealthData_bloodPressureAuthorizationNotDeterminedDoesNotRequestRepair() async throws {
        let store = FakeHealthStore()
        let systolicID = HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
        let diastolicID = HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
        store.statisticsAverages[diastolicID] = 80
        store.statisticsMins[diastolicID] = 76
        store.statisticsMaxes[diastolicID] = 84
        store.errorsForAverage[systolicID] = NSError(
            domain: HKError.errorDomain,
            code: HKError.Code.errorAuthorizationNotDetermined.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Authorization not determined"]
        )

        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("blood_pressure_systolic")
        selection.toggleMetric("blood_pressure_diastolic")

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            metricSelection: selection
        )

        XCTAssertNil(data.vitals.bloodPressureSystolicAvg)
        XCTAssertEqual(data.vitals.bloodPressureDiastolicAvg, 80)
        XCTAssertFalse(store.authRequested)
        XCTAssertTrue(data.partialFailures.contains { failure in
            failure.dataType == "blood pressure systolic" &&
            failure.errorDescription.contains("Authorization not determined")
        })
        XCTAssertFalse(data.partialFailures.contains { $0.dataType == "vitals" })
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
        XCTAssertEqual(data.timeContext.calendarTimeZoneIdentifier, Calendar.current.timeZone.identifier)
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
    func test_activity_standTimeAndStandHours_remainSeparateAndHoursDeduplicate() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.appleStandTime.rawValue] = 37.5
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

        XCTAssertEqual(data.activity.standTimeMinutes, 37.5)
        XCTAssertEqual(data.activity.standHours, 2, "Two unique calendar hours should yield 2, not 3")
    }

    @MainActor
    func test_activity_standSelectors_filterSummariesIndependently() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.appleStandTime.rawValue] = 37.5
        let date = HealthKitFixtures.referenceDate
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let stoodValue = HKCategoryValueAppleStandHour.stood.rawValue
        store.categorySampleResults[HKCategoryTypeIdentifier.appleStandHour.rawValue] = [
            CategorySampleValue(value: stoodValue, startDate: startOfDay, endDate: startOfDay.addingTimeInterval(3600)),
            CategorySampleValue(value: stoodValue, startDate: startOfDay.addingTimeInterval(3600), endDate: startOfDay.addingTimeInterval(7200)),
        ]
        let sut = makeSUT(store: store)

        let standTimeOnly = MetricSelectionState()
        standTimeOnly.deselectAll()
        standTimeOnly.toggleMetric("stand_time")
        let timeData = try await sut.fetchHealthData(for: date, metricSelection: standTimeOnly)
        XCTAssertEqual(timeData.activity.standTimeMinutes, 37.5)
        XCTAssertNil(timeData.activity.standHours)

        let standHoursOnly = MetricSelectionState()
        standHoursOnly.deselectAll()
        standHoursOnly.toggleMetric("stand_hours")
        let hoursData = try await sut.fetchHealthData(for: date, metricSelection: standHoursOnly)
        XCTAssertNil(hoursData.activity.standTimeMinutes)
        XCTAssertEqual(hoursData.activity.standHours, 2)
    }

    @MainActor
    func test_activity_vo2Max_mostRecentLookupThroughEndOfDay() async throws {
        let store = FakeHealthStore()
        store.statisticsMostRecent[HKQuantityTypeIdentifier.vo2Max.rawValue] = 42.5
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertEqual(data.activity.vo2Max!, 42.5, accuracy: 0.1)
        XCTAssertNil(data.activity.vo2MaxSourceStartDate, "Legacy scalar adapters must not invent provenance")
    }

    @MainActor
    func test_activity_vo2MaxCarriesHistoricalProvenancePrefersInDayAndRejectsFuture() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let oldUUID = UUID(uuidString: "52000000-0000-0000-0000-000000000001")!
        let inDayUUID = UUID(uuidString: "52000000-0000-0000-0000-000000000002")!
        let futureUUID = UUID(uuidString: "52000000-0000-0000-0000-000000000003")!
        let oldStart = dayStart.addingTimeInterval(-((2 * 86_400) + 3_600))
        let inDayStart = dayStart.addingTimeInterval(43_210.125)
        let futureStart = dayEnd.addingTimeInterval(1)
        let old = QuantitySampleValue(
            uuid: oldUUID,
            value: 38.25,
            startDate: oldStart,
            endDate: oldStart.addingTimeInterval(0.75)
        )
        let inDay = QuantitySampleValue(
            uuid: inDayUUID,
            value: 44.5,
            startDate: inDayStart,
            endDate: inDayStart.addingTimeInterval(1.125)
        )
        let future = QuantitySampleValue(
            uuid: futureUUID,
            value: 60,
            startDate: futureStart,
            endDate: futureStart
        )
        let sut = makeSUT(store: store)

        store.quantitySampleResults[HKQuantityTypeIdentifier.vo2Max.rawValue] = [old, inDay, future]
        let inDayData = try await sut.fetchHealthData(for: dayStart)
        XCTAssertEqual(inDayData.activity.vo2Max, 44.5)
        XCTAssertEqual(inDayData.activity.vo2MaxSourceUUID, inDayUUID)
        XCTAssertEqual(inDayData.activity.vo2MaxSourceStartDate, inDayStart)
        XCTAssertEqual(inDayData.activity.vo2MaxSourceEndDate, inDay.endDate)
        XCTAssertEqual(inDayData.activity.vo2MaxCarriedForward, false)
        XCTAssertEqual(inDayData.activity.vo2MaxAgeSeconds, 0)

        store.quantitySampleResults[HKQuantityTypeIdentifier.vo2Max.rawValue] = [old, future]
        let historicalData = try await sut.fetchHealthData(for: dayStart)
        XCTAssertEqual(historicalData.activity.vo2Max, 38.25)
        XCTAssertEqual(historicalData.activity.vo2MaxSourceUUID, oldUUID)
        XCTAssertEqual(historicalData.activity.vo2MaxSourceStartDate, oldStart)
        XCTAssertEqual(historicalData.activity.vo2MaxSourceEndDate, old.endDate)
        XCTAssertEqual(historicalData.activity.vo2MaxCarriedForward, true)
        XCTAssertEqual(
            try XCTUnwrap(historicalData.activity.vo2MaxAgeSeconds),
            dayStart.timeIntervalSince(oldStart),
            accuracy: 0.000_001
        )

        store.quantitySampleResults[HKQuantityTypeIdentifier.vo2Max.rawValue] = [future]
        let futureOnlyData = try await sut.fetchHealthData(for: dayStart)
        XCTAssertNil(futureOnlyData.activity.vo2Max)
        XCTAssertNil(futureOnlyData.activity.vo2MaxSourceUUID)
    }

    @MainActor
    func test_activity_noSamples_allFieldsNil() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: Date())
        XCTAssertNil(data.activity.steps)
        XCTAssertNil(data.activity.activeCalories)
        XCTAssertNil(data.activity.exerciseMinutes)
        XCTAssertNil(data.activity.standTimeMinutes)
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
    func test_sleep_daytimeNapOutsideInBedAddsToTotalAndGranularStages() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullSleep(store)

        let calendar = Calendar.current
        let napStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: HealthKitFixtures.referenceDate)!
        let napEnd = napStart.addingTimeInterval(90 * 60)
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue, default: []].append(
            CategorySampleValue(
                value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                startDate: napStart,
                endDate: napEnd,
                metadata: ["HKWasUserEntered": "1"]
            )
        )

        let sut = makeSUT(store: store)
        let data = try await sut.fetchHealthData(for: HealthKitFixtures.referenceDate, includeGranularData: true)

        XCTAssertEqual(data.sleep.totalDuration, 27000 + 90 * 60, accuracy: 1)
        XCTAssertNotNil(data.sleep.stages.first { stage in
            stage.stage == "unspecified" && stage.startDate == napStart && stage.endDate == napEnd
        })
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
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        store.stateOfMindResults = [
            StateOfMindSampleValue(uuid: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!, kind: "Daily Mood", valence: 0.7, labels: ["Happy", "Grateful"], associations: ["Family"], startDate: dayStart.addingTimeInterval(1_000)),
            StateOfMindSampleValue(uuid: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!, kind: "Momentary Emotion", valence: -0.3, labels: ["Stressed"], associations: ["Work", "Tasks"], startDate: dayStart.addingTimeInterval(2_000)),
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

    @MainActor
    func test_compatibilityRecordsUseStrictStartOwnershipAcrossAdjacentDays() async throws {
        let store = FakeHealthStore()
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: HealthKitFixtures.referenceDate)
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let crossMidnightStart = secondDay.addingTimeInterval(-600)
        let crossMidnightEnd = secondDay.addingTimeInterval(1_200)

        store.categorySampleResults[HKCategoryTypeIdentifier.mindfulSession.rawValue] = [
            CategorySampleValue(value: 0, startDate: crossMidnightStart, endDate: crossMidnightEnd)
        ]
        store.categorySampleResults[HKCategoryTypeIdentifier.appleStandHour.rawValue] = [
            CategorySampleValue(
                value: HKCategoryValueAppleStandHour.stood.rawValue,
                startDate: crossMidnightStart,
                endDate: crossMidnightEnd
            )
        ]
        store.stateOfMindResults = [StateOfMindSampleValue(
            uuid: UUID(uuidString: "53000000-0000-0000-0000-000000000001")!,
            kind: "Momentary Emotion",
            valence: 0.3,
            labels: ["Calm"],
            associations: ["Evening"],
            startDate: crossMidnightStart,
            endDate: crossMidnightEnd
        )]
        store.workoutResults = [WorkoutValue(
            sourceUUID: UUID(uuidString: "53000000-0000-0000-0000-000000000002")!,
            activityType: HKWorkoutActivityType.running.rawValue,
            duration: 1_800,
            startDate: crossMidnightStart,
            endDate: crossMidnightEnd,
            totalEnergyBurned: 250,
            totalDistance: 4_000
        )]
        // HKStatistics summary queries intentionally retain HealthKit's day
        // bucket semantics rather than being replaced by source-start filtering.
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123

        let selection = MetricSelectionState()
        selection.deselectAll()
        for metricID in [
            "mindful_minutes", "mindful_sessions", "state_of_mind_entries",
            "workouts", "stand_hours", "steps"
        ] {
            selection.enabledMetrics.insert(metricID)
        }
        let sut = makeSUT(store: store)

        let first = try await sut.fetchHealthData(for: firstDay, metricSelection: selection)
        let second = try await sut.fetchHealthData(for: secondDay, metricSelection: selection)

        XCTAssertEqual(first.mindfulness.mindfulSessions, 1)
        XCTAssertEqual(first.mindfulness.mindfulMinutes, 30)
        XCTAssertEqual(first.mindfulness.stateOfMind.map(\.id), [
            UUID(uuidString: "53000000-0000-0000-0000-000000000001")!
        ])
        XCTAssertEqual(first.workouts.map(\.sourceUUID), [
            UUID(uuidString: "53000000-0000-0000-0000-000000000002")!
        ])
        XCTAssertEqual(first.activity.standHours, 1)

        XCTAssertNil(second.mindfulness.mindfulSessions)
        XCTAssertNil(second.mindfulness.mindfulMinutes)
        XCTAssertTrue(second.mindfulness.stateOfMind.isEmpty)
        XCTAssertTrue(second.workouts.isEmpty)
        XCTAssertNil(second.activity.standHours)

        XCTAssertEqual(first.activity.steps, 123)
        XCTAssertEqual(second.activity.steps, 123, "HKStatistics daily bucket semantics must remain unchanged")
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
    func test_workouts_rolling_preservesHealthKitIdentity() async throws {
        let store = FakeHealthStore()
        let start = Date()
        store.workoutResults = [
            WorkoutValue(
                activityType: HKWorkoutActivityType.preparationAndRecovery.rawValue,
                duration: 600,
                startDate: start,
                endDate: start.addingTimeInterval(600),
                totalEnergyBurned: nil,
                totalDistance: nil
            )
        ]
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: start)
        let workout = try XCTUnwrap(data.workouts.first)
        XCTAssertEqual(workout.workoutType, .rolling)
        XCTAssertEqual(workout.workoutTypeName, "Rolling")
        XCTAssertEqual(workout.workoutSportName, "rolling")
        XCTAssertEqual(workout.healthKitActivityType, "preparationAndRecovery")
        XCTAssertEqual(workout.healthKitActivityTypeRawValue, 33)
    }

    @MainActor
    func test_workouts_unknownActivityType_preservesRawValue() async throws {
        let store = FakeHealthStore()
        let start = Date()
        store.workoutResults = [
            WorkoutValue(activityType: 99999, duration: 600, startDate: start, endDate: start.addingTimeInterval(600), totalEnergyBurned: nil, totalDistance: nil)
        ]
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(for: start)
        let workout = try XCTUnwrap(data.workouts.first)
        XCTAssertEqual(workout.workoutType, .other)
        XCTAssertEqual(workout.workoutTypeName, "Unknown HealthKit Activity")
        XCTAssertEqual(workout.workoutSportName, "healthkit-99999")
        XCTAssertNil(workout.healthKitActivityType)
        XCTAssertEqual(workout.healthKitActivityTypeRawValue, 99999)
    }

    func test_workoutMapping_coversEveryCurrentHealthKitActivityType() {
        let healthKitTypes: [HKWorkoutActivityType] = [
            .americanFootball, .archery, .australianFootball, .badminton, .baseball,
            .basketball, .bowling, .boxing, .climbing, .cricket, .crossTraining,
            .curling, .cycling, .dance, .danceInspiredTraining, .elliptical,
            .equestrianSports, .fencing, .fishing, .functionalStrengthTraining,
            .golf, .gymnastics, .handball, .hiking, .hockey, .hunting, .lacrosse,
            .martialArts, .mindAndBody, .mixedMetabolicCardioTraining, .paddleSports,
            .play, .preparationAndRecovery, .racquetball, .rowing, .rugby, .running,
            .sailing, .skatingSports, .snowSports, .soccer, .softball, .squash,
            .stairClimbing, .surfingSports, .swimming, .tableTennis, .tennis,
            .trackAndField, .traditionalStrengthTraining, .volleyball, .walking,
            .waterFitness, .waterPolo, .waterSports, .wrestling, .yoga, .barre,
            .coreTraining, .crossCountrySkiing, .downhillSkiing, .flexibility,
            .highIntensityIntervalTraining, .jumpRope, .kickboxing, .pilates,
            .snowboarding, .stairs, .stepTraining, .wheelchairWalkPace,
            .wheelchairRunPace, .taiChi, .mixedCardio, .handCycling, .discSports,
            .fitnessGaming, .cardioDance, .socialDance, .pickleball, .cooldown,
            .swimBikeRun, .transition, .underwaterDiving, .other
        ]

        let mappings = healthKitTypes.map { WorkoutType.healthKitMapping(rawValue: $0.rawValue) }
        XCTAssertEqual(healthKitTypes.count, 84)
        XCTAssertEqual(Set(mappings.map { $0.workoutType }), Set(WorkoutType.allCases))
        XCTAssertTrue(mappings.allSatisfy { $0.activityTypeName != nil })
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

    func test_sleepWindow_assignsNoonToNoonSleepDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let exportDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 11))!

        let window = HealthKitManager.sleepWindow(for: exportDate, calendar: calendar)

        XCTAssertEqual(
            window.start,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12))
        )
        XCTAssertEqual(
            window.end,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 12))
        )

        let nextDay = calendar.date(byAdding: .day, value: 1, to: exportDate)!
        XCTAssertEqual(window.end, HealthKitManager.sleepWindow(for: nextDay, calendar: calendar).start)
    }

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
        XCTAssertTrue(data.vitals.bloodPressureSamples.isEmpty, "bloodPressureSamples should be empty when granular=false")
        XCTAssertFalse(store.bloodPressureSamplesQueried, "Blood pressure correlations should not be queried when granular=false")
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
        XCTAssertEqual(data.vitals.bloodPressureSamples.count, 2)
        XCTAssertEqual(data.vitals.bloodPressureSamples[0].systolic, 124, accuracy: 0.1)
        XCTAssertEqual(data.vitals.bloodPressureSamples[0].diastolic, 81, accuracy: 0.1)
        XCTAssertEqual(data.vitals.bloodPressureSamples[0].metadata["HKWasUserEntered"], "false")
        XCTAssertTrue(store.bloodPressureSamplesQueried)
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

// MARK: - Lossless HealthKit Record Archive Tests

final class HealthKitManagerRecordArchiveTests: XCTestCase {
    private static let source = HealthKitSourceRevision(
        name: "Archive Fixture",
        bundleIdentifier: "com.example.archive-fixture",
        version: "1.0"
    )

    @MainActor
    func test_exactCurrentMetricSelectionQueriesOnlyItsGenericDescriptor() async throws {
        let store = FakeHealthStore()
        let selection = selection(["steps"])
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection
        )

        XCTAssertEqual(store.queriedQuantityRecordIdentifiers, [HKQuantityTypeIdentifier.stepCount.rawValue])
        XCTAssertTrue(store.queriedCategoryRecordIdentifiers.isEmpty)
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .complete)
        XCTAssertEqual(archive.queryResults.map(\.objectTypeIdentifier), [HKQuantityTypeIdentifier.stepCount.rawValue])
        XCTAssertEqual(archive.queryResults.first?.metricIDs, ["steps"])
        XCTAssertEqual(archive.queryResults.first?.metricAttribution?.directMetricIDs, ["steps"])
        XCTAssertEqual(archive.queryResults.first?.metricAttribution?.dependencyMetricIDs, [])
    }

    @MainActor
    func test_archiveOnlyMetricSelectionQueriesExactlyOneNewGenericType() async throws {
        guard HealthMetrics.all.first(where: { $0.id == "rowing_speed" })?.availability.isAvailableOnCurrentPlatform == true else { return }
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["rowing_speed"])
        )

        XCTAssertEqual(store.queriedQuantityRecordIdentifiers, ["HKQuantityTypeIdentifierRowingSpeed"])
        XCTAssertTrue(store.queriedCategoryRecordIdentifiers.isEmpty)
        let result = try XCTUnwrap(data.healthKitRecordArchive?.queryResults.first)
        XCTAssertEqual(result.objectTypeIdentifier, "HKQuantityTypeIdentifierRowingSpeed")
        XCTAssertEqual(result.metricIDs, ["rowing_speed"])
        XCTAssertEqual(result.status, .success)
    }

    @MainActor
    func test_environmentalAudioExposureEventQueriesResolvedRawIdentifierAndReportsSuccess() async throws {
        let store = FakeHealthStore()
        let data = try await makeSUT(store: store).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["environmental_audio_exposure_event"])
        )

        XCTAssertEqual(
            store.queriedCategoryRecordIdentifiers,
            [HealthKitRecordCatalog.environmentalAudioExposureEventIdentifier]
        )
        let result = try XCTUnwrap(data.healthKitRecordArchive?.queryResults.first)
        XCTAssertEqual(result.objectTypeIdentifier, "HKCategoryTypeIdentifierAudioExposureEvent")
        XCTAssertEqual(result.metricIDs, ["environmental_audio_exposure_event"])
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.recordCount, 0)
    }

    @MainActor
    func test_noMetricSelectionQueriesEveryNormallySelectableGenericIdentifier() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)
        let normallySelectable = MetricSelectionState().enabledMetrics
        let expectedPlan = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: normallySelectable
        ).filter { HealthKitRecordCatalog.isRuntimeAvailable($0.descriptor) }
        let expectedQuantity = Set(expectedPlan.filter { $0.recordKind == .quantity }.map(\.objectTypeIdentifier))
        let expectedCategory = Set(expectedPlan.filter { $0.recordKind == .category }.map(\.objectTypeIdentifier))

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true
        )

        XCTAssertEqual(Set(store.queriedQuantityRecordIdentifiers), expectedQuantity)
        XCTAssertEqual(Set(store.queriedCategoryRecordIdentifiers), expectedCategory)
        XCTAssertEqual(store.queriedQuantityRecordIdentifiers.count, expectedQuantity.count)
        XCTAssertEqual(store.queriedCategoryRecordIdentifiers.count, expectedCategory.count)

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertFalse(archive.queryResults.contains {
            $0.operation == "specializedRecordQuery" && $0.status == .unsupported
        })
        let food = try XCTUnwrap(archive.queryResults.first {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.foodCorrelationIdentifier
        })
        XCTAssertEqual(food.operation, "queryFoodRecords")
        XCTAssertEqual(food.status, .success)
        XCTAssertEqual(archive.captureStatus, .complete)
        XCTAssertFalse(archive.queryResults.contains {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.medicationDoseEventIdentifier
        })
        XCTAssertTrue(archive.records.isEmpty, "Existing specialized summaries must not become fake generic records")
    }

    @MainActor
    func test_duplicateLookingUUIDsSurviveAndRepeatedUUIDViewsMergeAttributionAndRelationships() async throws {
        let store = FakeHealthStore()
        let selection = selection(["steps", "heart_rate_avg"])
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let firstUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let secondUUID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let firstTarget = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let secondTarget = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let firstRelationship = HealthKitRecordRelationship(
            targetUUID: firstTarget,
            role: "first",
            kind: "fixture"
        )
        let secondRelationship = HealthKitRecordRelationship(
            targetUUID: secondTarget,
            role: "second",
            kind: "fixture"
        )
        store.quantityRecordResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [
            record(
                uuid: firstUUID,
                identifier: HKQuantityTypeIdentifier.stepCount.rawValue,
                startDate: dayStart.addingTimeInterval(60),
                relationships: [firstRelationship]
            ),
            record(
                uuid: secondUUID,
                identifier: HKQuantityTypeIdentifier.stepCount.rawValue,
                startDate: dayStart.addingTimeInterval(60)
            ),
        ]
        store.quantityRecordResults[HKQuantityTypeIdentifier.heartRate.rawValue] = [
            record(
                uuid: firstUUID,
                identifier: HKQuantityTypeIdentifier.heartRate.rawValue,
                startDate: dayStart.addingTimeInterval(60),
                relationships: [secondRelationship]
            ),
        ]
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection
        )

        let records = try XCTUnwrap(data.healthKitRecordArchive).records
        XCTAssertEqual(records.count, 2, "Only repeated views of the same UUID may merge")
        XCTAssertEqual(Set(records.map(\.originalUUID)), [firstUUID, secondUUID])
        let merged = try XCTUnwrap(records.first { $0.originalUUID == firstUUID })
        XCTAssertEqual(merged.relationships.count, 2)
        XCTAssertTrue(merged.relationships.contains(firstRelationship))
        XCTAssertTrue(merged.relationships.contains(secondRelationship))
        XCTAssertEqual(merged.selectedMetricIDs, ["heart_rate_avg", "steps"])
        XCTAssertEqual(merged.metricAttribution?.directMetricIDs, ["heart_rate_avg", "steps"])
    }

    @MainActor
    func test_bloodPressureCanonicalGraphPreservesExtrasAndKeepsComponentsDependencyOnly() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let correlationUUID = UUID(uuidString: "11000000-0000-0000-0000-000000000001")!
        let firstSystolicUUID = UUID(uuidString: "11000000-0000-0000-0000-000000000002")!
        let extraSystolicUUID = UUID(uuidString: "11000000-0000-0000-0000-000000000003")!
        let diastolicUUID = UUID(uuidString: "11000000-0000-0000-0000-000000000004")!
        let standaloneTargetUUID = UUID(uuidString: "11000000-0000-0000-0000-000000000005")!
        let componentUUIDs = [firstSystolicUUID, extraSystolicUUID, diastolicUUID]
        let parentRelationships = [
            HealthKitRecordRelationship(targetUUID: firstSystolicUUID, role: "systolic", kind: "component"),
            HealthKitRecordRelationship(targetUUID: extraSystolicUUID, role: "systolic", kind: "component"),
            HealthKitRecordRelationship(targetUUID: diastolicUUID, role: "diastolic", kind: "component"),
        ]
        let correlation = HealthKitRecord(
            originalUUID: correlationUUID,
            objectTypeIdentifier: HealthKitRecordCatalog.bloodPressureCorrelationIdentifier,
            recordKind: .correlation,
            selectedMetricIDs: ["fixture"],
            includedBecause: .selectedMetric,
            startDate: dayStart.addingTimeInterval(300),
            endDate: dayStart.addingTimeInterval(301),
            hasUndeterminedDuration: true,
            sourceRevision: Self.source,
            device: HealthKitDeviceProvenance(name: "Cuff"),
            metadata: ["correlation": .bool(true)],
            payload: .correlation(componentUUIDs: componentUUIDs),
            relationships: parentRelationships
        )
        func component(_ uuid: UUID, identifier: HKQuantityTypeIdentifier, value: Double, role: String) -> HealthKitRecord {
            HealthKitRecord(
                originalUUID: uuid,
                objectTypeIdentifier: identifier.rawValue,
                recordKind: .quantity,
                selectedMetricIDs: ["fixture"],
                includedBecause: .selectedMetric,
                startDate: dayStart.addingTimeInterval(300.25),
                endDate: dayStart.addingTimeInterval(300.75),
                sourceRevision: Self.source,
                device: HealthKitDeviceProvenance(model: "BP-1"),
                metadata: ["component": .string(role)],
                payload: .quantity(HealthKitQuantityPayload(value: value, unit: "mmHg")),
                relationships: [HealthKitRecordRelationship(
                    targetUUID: correlationUUID,
                    role: role,
                    kind: "parent"
                )]
            )
        }
        let firstSystolic = component(firstSystolicUUID, identifier: .bloodPressureSystolic, value: 121, role: "systolic")
        let extraSystolic = component(extraSystolicUUID, identifier: .bloodPressureSystolic, value: 123, role: "systolic")
        let diastolic = component(diastolicUUID, identifier: .bloodPressureDiastolic, value: 79, role: "diastolic")
        store.bloodPressureRecordResults = [correlation, firstSystolic, extraSystolic, diastolic]
        store.quantityRecordResults[HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue] = [
            HealthKitRecord(
                originalUUID: firstSystolic.originalUUID,
                objectTypeIdentifier: firstSystolic.objectTypeIdentifier,
                recordKind: firstSystolic.recordKind,
                selectedMetricIDs: ["fixture"],
                includedBecause: .selectedMetric,
                startDate: firstSystolic.startDate,
                endDate: firstSystolic.endDate,
                sourceRevision: firstSystolic.sourceRevision,
                device: firstSystolic.device,
                metadata: firstSystolic.metadata,
                payload: firstSystolic.payload,
                relationships: [HealthKitRecordRelationship(
                    targetUUID: standaloneTargetUUID,
                    role: "standalone-query-view",
                    kind: "attribution"
                )]
            ),
            extraSystolic,
        ]
        store.quantityRecordResults[HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue] = [diastolic]

        let data = try await makeSUT(store: store).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["blood_pressure_systolic"])
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .complete)
        XCTAssertEqual(Set(archive.records.map(\.originalUUID)), Set([correlationUUID] + componentUUIDs))
        let archivedCorrelation = try XCTUnwrap(archive.records.first { $0.originalUUID == correlationUUID })
        guard case .correlation(let archivedComponents) = archivedCorrelation.payload else {
            return XCTFail("Expected blood pressure correlation payload")
        }
        XCTAssertEqual(Set(archivedComponents), Set(componentUUIDs))
        XCTAssertEqual(archivedCorrelation.relationships.count, parentRelationships.count)
        for relationship in parentRelationships {
            XCTAssertTrue(archivedCorrelation.relationships.contains(relationship))
        }
        XCTAssertEqual(archivedCorrelation.hasUndeterminedDuration, true)

        let mergedChild = try XCTUnwrap(archive.records.first { $0.originalUUID == firstSystolicUUID })
        XCTAssertEqual(mergedChild.relationships.count, 2)
        XCTAssertTrue(mergedChild.relationships.contains { $0.targetUUID == correlationUUID && $0.kind == "parent" })
        XCTAssertTrue(mergedChild.relationships.contains { $0.targetUUID == standaloneTargetUUID })
        XCTAssertEqual(mergedChild.metricAttribution?.directMetricIDs, [])
        XCTAssertEqual(mergedChild.metricAttribution?.dependencyMetricIDs, ["blood_pressure_systolic"])
        XCTAssertEqual(store.bloodPressureRecordQueries.count, 1)
        XCTAssertEqual(store.bloodPressureRecordQueries[0].selectedMetricIDs, ["blood_pressure_systolic"])
    }

    @MainActor
    func test_stateOfMindCanonicalAndCompatibilityCaptureUseSourceUUIDDatesAndProvenance() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let uuid = UUID(uuidString: "12000000-0000-0000-0000-000000000001")!
        let start = dayStart.addingTimeInterval(1_234.125)
        let end = start.addingTimeInterval(0.875)
        let device = HealthKitDeviceProvenance(name: "Watch", model: "State-1", localIdentifier: "state-local")
        let payloadFields: [String: HealthKitMetadataValue] = [
            "kind": .dictionary(["rawValue": .signedInteger(999), "symbolicValue": .null]),
            "valence": .floatingPoint(-0.375),
            "valenceClassification": .dictionary(["rawValue": .signedInteger(888), "symbolicValue": .null]),
            "labels": .array([
                .dictionary(["rawValue": .signedInteger(777), "symbolicValue": .null]),
                .dictionary(["rawValue": .signedInteger(17), "symbolicValue": .string("Happy")]),
            ]),
            "associations": .array([
                .dictionary(["rawValue": .signedInteger(666), "symbolicValue": .null]),
            ]),
        ]
        store.stateOfMindRecordResults = [HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: HealthKitRecordCatalog.stateOfMindIdentifier,
            recordKind: .stateOfMind,
            selectedMetricIDs: ["fixture"],
            includedBecause: .selectedMetric,
            startDate: start,
            endDate: end,
            sourceRevision: Self.source,
            device: device,
            metadata: ["typed": .signedInteger(42)],
            payload: .structured(kind: "stateOfMind", fields: payloadFields)
        )]
        store.stateOfMindResults = [StateOfMindSampleValue(
            uuid: uuid,
            kind: "Unknown",
            valence: -0.375,
            labels: ["Happy"],
            associations: ["Family"],
            startDate: start,
            endDate: end,
            sourceRevision: Self.source,
            device: device,
            metadata: ["legacy": "preserved"]
        )]

        let data = try await makeSUT(store: store).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["state_of_mind_entries"])
        )

        let entry = try XCTUnwrap(data.mindfulness.stateOfMind.first)
        XCTAssertEqual(entry.id, uuid)
        XCTAssertEqual(entry.timestamp, start)
        XCTAssertEqual(entry.endDate, end)
        XCTAssertEqual(entry.kind, .unknown)
        XCTAssertEqual(entry.sourceRevision, Self.source)
        XCTAssertEqual(entry.device, device)
        XCTAssertEqual(entry.metadata, ["legacy": "preserved"])

        let record = try XCTUnwrap(data.healthKitRecordArchive?.records.first)
        XCTAssertEqual(record.originalUUID, uuid)
        XCTAssertEqual(record.endDate, end)
        XCTAssertEqual(record.sourceRevision, Self.source)
        XCTAssertEqual(record.device, device)
        XCTAssertEqual(record.metadata["typed"], .signedInteger(42))
        XCTAssertEqual(record.payload, .structured(kind: "stateOfMind", fields: payloadFields))
        XCTAssertEqual(data.healthKitRecordArchive?.queryResults.first?.status, .success)
        XCTAssertEqual(store.stateOfMindRecordQueries.count, 1)
    }

    @MainActor
    func test_quantitySeriesChildFailureKeepsParentCountAndMakesArchivePartial() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let parentUUID = UUID(uuidString: "15000000-0000-0000-0000-000000000001")!
        let siblingUUID = UUID(uuidString: "15000000-0000-0000-0000-000000000002")!
        let identifier = HKQuantityTypeIdentifier.stepCount.rawValue
        store.quantityRecordResults[identifier] = [
            record(
                uuid: parentUUID,
                identifier: identifier,
                startDate: dayStart.addingTimeInterval(120)
            ),
            record(
                uuid: siblingUUID,
                identifier: identifier,
                startDate: dayStart.addingTimeInterval(180)
            ),
        ]
        let childFailure = HealthKitQueryResult(
            identifier: "\(identifier):\(parentUUID.uuidString):quantitySeries",
            objectTypeIdentifier: identifier,
            operation: "queryQuantitySeriesChildren",
            metricIDs: ["steps"],
            interval: HealthKitQueryInterval(
                startDate: dayStart.addingTimeInterval(120),
                endDate: dayStart.addingTimeInterval(121)
            ),
            status: .failure,
            recordCount: 0,
            error: HealthKitQueryError(
                domain: "SeriesFixture",
                code: 9,
                description: "Child series unavailable",
                isRecoverable: true
            ),
            statusDescription: "parent_uuid=\(parentUUID.uuidString) expected_child_count=3"
        )
        store.quantityRecordChildQueryFailures[identifier] = [childFailure]
        store.quantityRecordIntegrityWarnings[identifier] = [HealthKitRecordIntegrityWarning(
            code: "quantity_series_capture_failed",
            message: "No values were inferred.",
            metricIDs: ["steps"],
            recordUUIDs: [parentUUID]
        )]

        let data = try await makeSUT(store: store).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["steps"])
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertEqual(archive.records.map(\.originalUUID), [parentUUID, siblingUUID])
        let parentQuery = try XCTUnwrap(archive.queryResults.first {
            $0.operation == "queryQuantityRecords"
        })
        XCTAssertEqual(parentQuery.status, .success)
        XCTAssertEqual(parentQuery.recordCount, 2, "Series children must not inflate parent query counts")
        let failedChild = try XCTUnwrap(archive.queryResults.first {
            $0.operation == "queryQuantitySeriesChildren"
        })
        XCTAssertEqual(failedChild.metricIDs, ["steps"])
        XCTAssertTrue(failedChild.statusDescription?.contains(parentUUID.uuidString) == true)
        XCTAssertEqual(archive.integrityWarnings.first?.recordUUIDs, [parentUUID])
        XCTAssertEqual(data.partialFailures.count, 1)
    }

    @MainActor
    func test_successEmptyIsCompleteWhileFailureIsPartialAndDoesNotBlockSiblingQuery() async throws {
        let successStore = FakeHealthStore()
        let stepsOnly = selection(["steps"])
        let successData = try await makeSUT(store: successStore).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: stepsOnly
        )
        let emptyArchive = try XCTUnwrap(successData.healthKitRecordArchive)
        XCTAssertEqual(emptyArchive.captureStatus, .complete)
        XCTAssertEqual(emptyArchive.records, [])
        XCTAssertEqual(emptyArchive.queryResults.first?.status, .success)
        XCTAssertEqual(emptyArchive.queryResults.first?.recordCount, 0)
        XCTAssertTrue(successData.partialFailures.isEmpty)

        let failureStore = FakeHealthStore()
        let error = NSError(
            domain: "ArchiveQueryDomain",
            code: 17,
            userInfo: [NSLocalizedDescriptionKey: "Step record query failed"]
        )
        failureStore.errorsForQuantityRecords[HKQuantityTypeIdentifier.stepCount.rawValue] = error
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let headacheIdentifier = HKCategoryTypeIdentifier.headache.rawValue
        let siblingUUID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        failureStore.categoryRecordResults[headacheIdentifier] = [record(
            uuid: siblingUUID,
            identifier: headacheIdentifier,
            kind: .category,
            startDate: dayStart.addingTimeInterval(120)
        )]
        let sut = makeSUT(store: failureStore)

        let failureData = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["steps", "symptom_headache"])
        )

        let archive = try XCTUnwrap(failureData.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertTrue(failureStore.queriedCategoryRecordIdentifiers.contains(headacheIdentifier))
        XCTAssertEqual(archive.records.map(\.originalUUID), [siblingUUID])
        let failedQuery = try XCTUnwrap(archive.queryResults.first { $0.status == .failure })
        XCTAssertEqual(failedQuery.objectTypeIdentifier, HKQuantityTypeIdentifier.stepCount.rawValue)
        XCTAssertEqual(failedQuery.error?.domain, "ArchiveQueryDomain")
        XCTAssertEqual(failedQuery.error?.code, 17)
        XCTAssertEqual(failedQuery.error?.description, "Step record query failed")
        XCTAssertEqual(failedQuery.error?.isRecoverable, true)
        XCTAssertEqual(failureData.partialFailures.filter {
            $0.dataType == "HealthKit record \(HKQuantityTypeIdentifier.stepCount.rawValue)"
        }.count, 1)
    }

    @MainActor
    func test_dependencyRecordsAreHonestlyAttributedAndSurviveFinalMetricFiltering() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let standTimeIdentifier = HKQuantityTypeIdentifier.appleStandTime.rawValue
        let standHourIdentifier = HKCategoryTypeIdentifier.appleStandHour.rawValue
        let directUUID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let dependencyUUID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        store.quantityRecordResults[standTimeIdentifier] = [record(
            uuid: directUUID,
            identifier: standTimeIdentifier,
            startDate: dayStart.addingTimeInterval(60)
        )]
        store.categoryRecordResults[standHourIdentifier] = [record(
            uuid: dependencyUUID,
            identifier: standHourIdentifier,
            kind: .category,
            startDate: dayStart.addingTimeInterval(120)
        )]
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["stand_time"])
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(Set(archive.records.map(\.originalUUID)), [directUUID, dependencyUUID])
        let direct = try XCTUnwrap(archive.records.first { $0.originalUUID == directUUID })
        XCTAssertEqual(direct.includedBecause, .selectedMetric)
        XCTAssertEqual(direct.metricAttribution?.directMetricIDs, ["stand_time"])
        XCTAssertEqual(direct.metricAttribution?.dependencyMetricIDs, [])
        let dependency = try XCTUnwrap(archive.records.first { $0.originalUUID == dependencyUUID })
        XCTAssertEqual(dependency.includedBecause, .relationshipDependency)
        XCTAssertEqual(dependency.selectedMetricIDs, ["stand_time"])
        XCTAssertEqual(dependency.metricAttribution?.directMetricIDs, [])
        XCTAssertEqual(dependency.metricAttribution?.dependencyMetricIDs, ["stand_time"])
        let dependencyQuery = try XCTUnwrap(archive.queryResults.first {
            $0.objectTypeIdentifier == standHourIdentifier
        })
        XCTAssertEqual(dependencyQuery.metricAttribution?.dependencyMetricIDs, ["stand_time"])
    }

    @MainActor
    func test_strictStartOwnershipUsesCapturedCalendarDayWithoutClippingDates() async throws {
        let store = FakeHealthStore()
        let selection = selection(["steps"])
        let sut = makeSUT(store: store)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        let start = calendar.startOfDay(for: HealthKitFixtures.referenceDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let beforeUUID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let ownedUUID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        let endUUID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
        let originalEnd = end.addingTimeInterval(3_600)
        store.quantityRecordResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [
            record(
                uuid: beforeUUID,
                identifier: HKQuantityTypeIdentifier.stepCount.rawValue,
                startDate: start.addingTimeInterval(-0.001)
            ),
            record(
                uuid: ownedUUID,
                identifier: HKQuantityTypeIdentifier.stepCount.rawValue,
                startDate: start,
                endDate: originalEnd
            ),
            record(
                uuid: endUUID,
                identifier: HKQuantityTypeIdentifier.stepCount.rawValue,
                startDate: end
            ),
        ]

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.dailyOwnership.intervalStart, start)
        XCTAssertEqual(archive.dailyOwnership.intervalEnd, end)
        XCTAssertEqual(archive.dailyOwnership.calendarTimeZoneIdentifier, data.timeContext.calendarTimeZoneIdentifier)
        XCTAssertEqual(archive.dailyOwnership.assignmentRule, "record_start_in_half_open_day_interval")
        XCTAssertEqual(archive.records.map(\.originalUUID), [ownedUUID])
        XCTAssertEqual(archive.records.first?.startDate, start)
        XCTAssertEqual(archive.records.first?.endDate, originalEnd, "Canonical dates must not be clipped to day ownership")
        let query = try XCTUnwrap(store.quantityRecordQueries.first)
        XCTAssertNotNil(query.predicate)
        XCTAssertTrue(String(describing: query.predicate!).contains("startDate"))
    }

    @MainActor
    func test_falseModeIsNotRequestedAndPerformsNoCanonicalQueries() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: false,
            metricSelection: selection(["steps"])
        )

        XCTAssertEqual(data.healthKitRecordCaptureStatus, .notRequested)
        XCTAssertNil(data.healthKitRecordArchive)
        XCTAssertTrue(store.queriedQuantityRecordIdentifiers.isEmpty)
        XCTAssertTrue(store.queriedCategoryRecordIdentifiers.isEmpty)
    }

    @MainActor
    func test_archiveCodableRoundTripsThroughHealthData() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let uuid = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        store.quantityRecordResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [record(
            uuid: uuid,
            identifier: HKQuantityTypeIdentifier.stepCount.rawValue,
            startDate: dayStart.addingTimeInterval(60)
        )]
        let sut = makeSUT(store: store)
        let original = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["steps"])
        )

        let decoded = try JSONDecoder().decode(
            HealthData.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.healthKitRecordArchive, original.healthKitRecordArchive)
        XCTAssertEqual(decoded.healthKitRecordCaptureStatus, .complete)
        XCTAssertEqual(decoded.healthKitRecordArchive?.records.first?.originalUUID, uuid)
    }

    func test_compatibilityModelsDecodeLegacyCodableWithoutNewProvenanceFields() throws {
        struct LegacyBloodPressure: Encodable {
            let systolic: Double
            let diastolic: Double
            let startDate: Date
            let endDate: Date
            let metadata: [String: String]
        }
        struct LegacyStateOfMind: Encodable {
            let id: UUID
            let timestamp: Date
            let kind: StateOfMindEntry.StateOfMindKind
            let valence: Double
            let labels: [String]
            let associations: [String]
            let metadata: [String: String]
        }

        let timestamp = Date(timeIntervalSinceReferenceDate: 700_000_000.25)
        let bloodPressure = try JSONDecoder().decode(
            BloodPressureSample.self,
            from: JSONEncoder().encode(LegacyBloodPressure(
                systolic: 120,
                diastolic: 80,
                startDate: timestamp,
                endDate: timestamp,
                metadata: ["legacy": "bp"]
            ))
        )
        XCTAssertNil(bloodPressure.correlationUUID)
        XCTAssertNil(bloodPressure.sourceRevision)
        XCTAssertNil(bloodPressure.device)
        XCTAssertEqual(bloodPressure.metadata, ["legacy": "bp"])

        let sourceUUID = UUID(uuidString: "50500000-0000-0000-0000-000000000001")!
        let state = try JSONDecoder().decode(
            StateOfMindEntry.self,
            from: JSONEncoder().encode(LegacyStateOfMind(
                id: sourceUUID,
                timestamp: timestamp,
                kind: .dailyMood,
                valence: 0.5,
                labels: ["Happy"],
                associations: ["Family"],
                metadata: ["legacy": "state"]
            ))
        )
        XCTAssertEqual(state.id, sourceUUID)
        XCTAssertEqual(state.endDate, timestamp)
        XCTAssertNil(state.sourceRevision)
        XCTAssertNil(state.device)
        XCTAssertEqual(state.metadata, ["legacy": "state"])
    }

    func test_fullHealthDataCodablePreservesSpecializedArchiveInventoryAndCompatibilityProvenance() throws {
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let end = dayStart.addingTimeInterval(1)
        let source = Self.source
        let device = HealthKitDeviceProvenance(
            name: "Fixture Device",
            manufacturer: "Acme",
            model: "All-1",
            localIdentifier: "all-local"
        )
        let correlationUUID = UUID(uuidString: "51000000-0000-0000-0000-000000000001")!
        let stateUUID = UUID(uuidString: "51000000-0000-0000-0000-000000000002")!
        let doseUUID = UUID(uuidString: "51000000-0000-0000-0000-000000000003")!
        let stateRecord = HealthKitRecord(
            originalUUID: stateUUID,
            objectTypeIdentifier: HealthKitRecordCatalog.stateOfMindIdentifier,
            recordKind: .stateOfMind,
            selectedMetricIDs: ["state_of_mind_entries"],
            includedBecause: .selectedMetric,
            startDate: dayStart,
            endDate: end,
            sourceRevision: source,
            device: device,
            metadata: ["raw": .signedInteger(1)],
            payload: .structured(kind: "stateOfMind", fields: [
                "kind": .dictionary(["rawValue": .signedInteger(999), "symbolicValue": .null]),
            ])
        )
        let doseRecord = HealthKitRecord(
            originalUUID: doseUUID,
            objectTypeIdentifier: HealthKitRecordCatalog.medicationDoseEventIdentifier,
            recordKind: .medicationDoseEvent,
            selectedMetricIDs: ["medications"],
            includedBecause: .selectedMetric,
            startDate: dayStart,
            endDate: end,
            sourceRevision: source,
            device: device,
            payload: .structured(kind: "medicationDoseEvent", fields: ["unit": .string("tablet")]),
            relationships: [HealthKitRecordRelationship(
                targetExternalIdentifier: "rxnorm:1",
                role: "medication",
                kind: "medicationConcept"
            )]
        )
        let ownership = HealthKitDailyOwnershipMetadata(
            ownerDate: HealthKitDailyOwnershipMetadata.ownerDate(
                for: dayStart,
                calendarTimeZoneIdentifier: Calendar.current.timeZone.identifier
            ),
            intervalStart: dayStart,
            intervalEnd: dayStart.addingTimeInterval(86_400),
            calendarTimeZoneIdentifier: Calendar.current.timeZone.identifier
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: ownership,
            records: [stateRecord, doseRecord],
            medicationInventoryRecords: [HealthKitMedicationInventoryRecord(
                externalIdentifier: "rxnorm:1",
                selectedMetricIDs: ["medications"],
                displayName: "Fixture Medication",
                fields: ["identifierStabilityNotes": .string("Stable coding")]
            )]
        )
        var original = HealthData(
            date: HealthKitFixtures.referenceDate,
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )
        original.vitals.bloodPressureSamples = [BloodPressureSample(
            correlationUUID: correlationUUID,
            systolic: 120,
            diastolic: 80,
            startDate: dayStart,
            endDate: end,
            sourceRevision: source,
            device: device,
            metadata: ["legacy": "bp"]
        )]
        original.mindfulness.stateOfMind = [StateOfMindEntry(
            id: stateUUID,
            timestamp: dayStart,
            endDate: end,
            kind: .unknown,
            valence: 0,
            labels: ["Unknown"],
            associations: ["Unknown"],
            sourceRevision: source,
            device: device,
            metadata: ["legacy": "state"]
        )]

        let decoded = try JSONDecoder().decode(
            HealthData.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.healthKitRecordArchive, archive)
        XCTAssertEqual(decoded.healthKitRecordCaptureStatus, .complete)
        XCTAssertEqual(decoded.vitals.bloodPressureSamples, original.vitals.bloodPressureSamples)
        let state = try XCTUnwrap(decoded.mindfulness.stateOfMind.first)
        XCTAssertEqual(state.id, stateUUID)
        XCTAssertEqual(state.timestamp, dayStart)
        XCTAssertEqual(state.endDate, end)
        XCTAssertEqual(state.sourceRevision, source)
        XCTAssertEqual(state.device, device)
        XCTAssertEqual(decoded.healthKitRecordArchive?.medicationInventoryRecords.first?.externalIdentifier, "rxnorm:1")
    }

    @MainActor
    func test_dailySummaryValuesAreUnchangedWhenRecordCaptureIsOn() async throws {
        let summaryStore = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(summaryStore)
        let archiveStore = FakeHealthStore()
        HealthKitFixtures.populateAllCategories(archiveStore)

        let summaryOnly = try await makeSUT(store: summaryStore).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: false
        )
        let withArchive = try await makeSUT(store: archiveStore).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true
        )

        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(
            summaryOnly.allMetricsDictionary(using: converter),
            withArchive.allMetricsDictionary(using: converter),
            "Canonical record queries must not alter any established daily summary calculation"
        )
        XCTAssertFalse(withArchive.workouts.isEmpty)
        XCTAssertFalse(withArchive.healthKitRecordArchive?.records.contains {
            $0.recordKind == .workout || $0.recordKind == .stateOfMind ||
                $0.recordKind == .medicationDoseEvent
        } ?? true)
    }

    @MainActor
    func test_finalFilteringDoesNotLeakDisabledCompatibilitySamplesOrArchiveQueries() async throws {
        let store = FakeHealthStore()
        HealthKitFixtures.populateFullHeart(store)
        HealthKitFixtures.populateFullVitals(store)
        HealthKitFixtures.populateGranularSamples(store)
        let sut = makeSUT(store: store)

        let unfiltered = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true
        )
        XCTAssertFalse(unfiltered.heart.heartRateSamples.isEmpty)
        XCTAssertFalse(unfiltered.heart.hrvSamples.isEmpty)
        XCTAssertFalse(unfiltered.vitals.bloodOxygenSamples.isEmpty)
        XCTAssertFalse(unfiltered.vitals.bloodPressureSamples.isEmpty)

        let data = unfiltered.filtered(by: selection(["resting_heart_rate"]))

        XCTAssertTrue(data.heart.heartRateSamples.isEmpty)
        XCTAssertTrue(data.heart.hrvSamples.isEmpty)
        XCTAssertTrue(data.vitals.bloodOxygenSamples.isEmpty)
        XCTAssertTrue(data.vitals.bloodGlucoseSamples.isEmpty)
        XCTAssertTrue(data.vitals.respiratoryRateSamples.isEmpty)
        XCTAssertTrue(data.vitals.bloodPressureSamples.isEmpty)
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(
            archive.queryResults.map(\.objectTypeIdentifier),
            [HKQuantityTypeIdentifier.restingHeartRate.rawValue]
        )
        XCTAssertTrue(archive.queryResults.allSatisfy { $0.metricIDs == ["resting_heart_rate"] })
    }

    @MainActor
    func test_authorizedMedicationCanonicalCaptureAttachesInventoryAndHonestRelationship() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let doseUUID = UUID(uuidString: "13000000-0000-0000-0000-000000000001")!
        let conceptIdentifier = "rxnorm:617314"
        let doseFields: [String: HealthKitMetadataValue] = [
            "medicationConceptIdentifier": .string(conceptIdentifier),
            "medicationName": .string("Thyroid"),
            "startDate": .date(dayStart.addingTimeInterval(28_800)),
            "endDate": .date(dayStart.addingTimeInterval(28_801)),
            "scheduledDate": .date(dayStart.addingTimeInterval(28_800)),
            "doseQuantity": .floatingPoint(1),
            "scheduledDoseQuantity": .floatingPoint(1),
            "unit": .string("tablet"),
            "logStatus": .dictionary(["rawValue": .signedInteger(4), "symbolicValue": .string("taken")]),
            "scheduleType": .dictionary(["rawValue": .signedInteger(2), "symbolicValue": .string("schedule")]),
        ]
        let doseRecord = HealthKitRecord(
            originalUUID: doseUUID,
            objectTypeIdentifier: HealthKitRecordCatalog.medicationDoseEventIdentifier,
            recordKind: .medicationDoseEvent,
            selectedMetricIDs: ["fixture"],
            includedBecause: .selectedMetric,
            startDate: dayStart.addingTimeInterval(28_800),
            endDate: dayStart.addingTimeInterval(28_801),
            hasUndeterminedDuration: true,
            sourceRevision: Self.source,
            device: HealthKitDeviceProvenance(name: "iPhone", model: "Phone-1"),
            metadata: ["typed": .date(dayStart)],
            payload: .structured(kind: "medicationDoseEvent", fields: doseFields),
            relationships: [HealthKitRecordRelationship(
                targetExternalIdentifier: conceptIdentifier,
                role: "medication",
                kind: "medicationConcept"
            )]
        )
        let inventory = HealthKitMedicationInventoryRecord(
            externalIdentifier: conceptIdentifier,
            objectTypeIdentifier: HealthKitRecordCatalog.userAnnotatedMedicationIdentifier,
            selectedMetricIDs: ["fixture"],
            displayName: "Levothyroxine Sodium 50 MCG Oral Tablet",
            fields: [
                "conceptIdentifier": .string(conceptIdentifier),
                "conceptIdentifierDomain": .string("HKHealthConceptDomainMedication"),
                "objectTypeIdentifier": .string(HealthKitRecordCatalog.userAnnotatedMedicationIdentifier),
                "displayName": .string("Levothyroxine Sodium 50 MCG Oral Tablet"),
                "nickname": .string("Thyroid"),
                "generalForm": .string("tablet"),
                "isArchived": .bool(false),
                "hasSchedule": .bool(true),
                "relatedCodings": .array([.dictionary([
                    "system": .string("http://www.nlm.nih.gov/research/umls/rxnorm"),
                    "version": .null,
                    "code": .string("617314"),
                ])]),
                "identifierStability": .string("stable_clinical_coding"),
                "identifierStabilityNotes": .string("RxNorm identity"),
            ]
        )
        store.medicationRecordResult = HealthKitMedicationRecordQueryResult(
            records: [doseRecord],
            inventoryRecords: [inventory]
        )

        let data = try await makeSUT(
            store: store,
            medicationAuthorizationRequested: true
        ).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["medications"])
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .complete)
        XCTAssertEqual(archive.records, [doseRecord.attributed(HealthKitMetricAttribution(directMetricIDs: ["medications"]))])
        XCTAssertEqual(archive.medicationInventoryRecords.count, 1)
        let archivedInventory = try XCTUnwrap(archive.medicationInventoryRecords.first)
        XCTAssertEqual(archivedInventory.externalIdentifier, conceptIdentifier)
        XCTAssertEqual(
            archivedInventory.objectTypeIdentifier,
            "HKDataTypeUserAnnotatedMedicationConcept"
        )
        XCTAssertEqual(
            archivedInventory.fields["conceptIdentifierDomain"],
            .string("HKHealthConceptDomainMedication")
        )
        XCTAssertEqual(
            archivedInventory.fields["objectTypeIdentifier"],
            .string("HKDataTypeUserAnnotatedMedicationConcept")
        )
        XCTAssertEqual(archivedInventory.selectedMetricIDs, ["medications"])
        XCTAssertEqual(archivedInventory.fields["relatedCodings"], inventory.fields["relatedCodings"])
        XCTAssertEqual(archivedInventory.fields["identifierStabilityNotes"], .string("RxNorm identity"))
        let serializedInventory = try HealthKitRecordArchiveSerializer.medicationInventoryRecordString(
            for: archivedInventory
        )
        XCTAssertTrue(serializedInventory.contains("\"object_type_identifier\":\"HKDataTypeUserAnnotatedMedicationConcept\""))
        XCTAssertTrue(serializedInventory.contains("HKHealthConceptDomainMedication"))
        XCTAssertEqual(archive.records[0].relationships[0].targetExternalIdentifier, conceptIdentifier)
        XCTAssertEqual(archive.records[0].relationships[0].role, "medication")
        XCTAssertEqual(store.medicationRecordQueries.count, 1)
        XCTAssertTrue(store.medicationRecordQueries[0].includeInventory)
        XCTAssertTrue(store.medicationsQueried, "Compatibility medication export must remain intact")
        XCTAssertTrue(store.medicationDoseEventsQueried, "Compatibility dose export must remain intact")
    }

    @MainActor
    func test_specializedQueryFailureIsIsolatedFromOtherSpecializedRecords() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let stateUUID = UUID(uuidString: "14000000-0000-0000-0000-000000000001")!
        store.errorForBloodPressureRecords = NSError(
            domain: "SpecializedFixture",
            code: 81,
            userInfo: [NSLocalizedDescriptionKey: "Blood pressure correlation failed"]
        )
        store.stateOfMindRecordResults = [HealthKitRecord(
            originalUUID: stateUUID,
            objectTypeIdentifier: HealthKitRecordCatalog.stateOfMindIdentifier,
            recordKind: .stateOfMind,
            selectedMetricIDs: ["fixture"],
            includedBecause: .selectedMetric,
            startDate: dayStart.addingTimeInterval(600),
            endDate: dayStart.addingTimeInterval(601),
            sourceRevision: Self.source,
            payload: .structured(kind: "stateOfMind", fields: ["valence": .floatingPoint(0.2)])
        )]

        let data = try await makeSUT(store: store).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["blood_pressure_systolic", "state_of_mind_entries"])
        )

        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertEqual(archive.records.map(\.originalUUID), [stateUUID])
        let failed = try XCTUnwrap(archive.queryResults.first { $0.operation == "queryBloodPressureRecords" })
        XCTAssertEqual(failed.status, .failure)
        XCTAssertEqual(failed.error?.domain, "SpecializedFixture")
        let state = try XCTUnwrap(archive.queryResults.first { $0.operation == "queryStateOfMindRecords" })
        XCTAssertEqual(state.status, .success)
        XCTAssertEqual(state.recordCount, 1)
        XCTAssertEqual(store.bloodPressureRecordQueries.count, 1)
        XCTAssertEqual(store.stateOfMindRecordQueries.count, 1)
        XCTAssertEqual(data.partialFailures.filter { $0.dataType.contains(HealthKitRecordCatalog.bloodPressureCorrelationIdentifier) }.count, 1)
    }

    @MainActor
    func test_relationshipQueriesRetainOnlyScopedComponentsAndSelectedStandaloneSamples() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let foodUUID = UUID(uuidString: "16000000-0000-0000-0000-000000000001")!
        let proteinComponentUUID = UUID(uuidString: "16000000-0000-0000-0000-000000000002")!
        let vitaminComponentUUID = UUID(uuidString: "16000000-0000-0000-0000-000000000003")!
        let standaloneProteinUUID = UUID(uuidString: "16000000-0000-0000-0000-000000000004")!
        let unrelatedVitaminUUID = UUID(uuidString: "16000000-0000-0000-0000-000000000005")!
        let proteinIdentifier = HKQuantityTypeIdentifier.dietaryProtein.rawValue
        let vitaminIdentifier = HKQuantityTypeIdentifier.dietaryVitaminC.rawValue
        let foodRelationships = [
            HealthKitRecordRelationship(
                targetUUID: proteinComponentUUID,
                role: proteinIdentifier,
                kind: "component"
            ),
            HealthKitRecordRelationship(
                targetUUID: vitaminComponentUUID,
                role: vitaminIdentifier,
                kind: "component"
            ),
        ]
        store.foodRecordResults = [
            record(
                uuid: foodUUID,
                identifier: HealthKitRecordCatalog.foodCorrelationIdentifier,
                kind: .correlation,
                startDate: dayStart.addingTimeInterval(3_600),
                relationships: foodRelationships
            ),
            record(
                uuid: proteinComponentUUID,
                identifier: proteinIdentifier,
                startDate: dayStart.addingTimeInterval(3_600),
                relationships: [HealthKitRecordRelationship(
                    targetUUID: foodUUID,
                    role: proteinIdentifier,
                    kind: "parent"
                )]
            ),
            record(
                uuid: vitaminComponentUUID,
                identifier: vitaminIdentifier,
                startDate: dayStart.addingTimeInterval(3_600),
                relationships: [HealthKitRecordRelationship(
                    targetUUID: foodUUID,
                    role: vitaminIdentifier,
                    kind: "parent"
                )]
            ),
        ]
        store.quantityRecordResults[proteinIdentifier] = [
            record(
                uuid: proteinComponentUUID,
                identifier: proteinIdentifier,
                startDate: dayStart.addingTimeInterval(3_600)
            ),
            record(
                uuid: standaloneProteinUUID,
                identifier: proteinIdentifier,
                startDate: dayStart.addingTimeInterval(7_200)
            ),
        ]
        store.quantityRecordResults[vitaminIdentifier] = [
            record(
                uuid: unrelatedVitaminUUID,
                identifier: vitaminIdentifier,
                startDate: dayStart.addingTimeInterval(7_200)
            ),
        ]

        let data = try await makeSUT(store: store).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["dietary_protein"])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)

        XCTAssertEqual(Set(archive.records.map(\.originalUUID)), [
            foodUUID, proteinComponentUUID, vitaminComponentUUID, standaloneProteinUUID,
        ])
        XCTAssertFalse(archive.records.contains { $0.originalUUID == unrelatedVitaminUUID })
        XCTAssertEqual(store.queriedQuantityRecordIdentifiers, [proteinIdentifier])
        let food = try XCTUnwrap(archive.records.first { $0.originalUUID == foodUUID })
        XCTAssertEqual(food.metricAttribution?.directMetricIDs, ["dietary_protein"])
        let proteinComponent = try XCTUnwrap(archive.records.first {
            $0.originalUUID == proteinComponentUUID
        })
        XCTAssertEqual(proteinComponent.metricAttribution?.directMetricIDs, [])
        XCTAssertEqual(proteinComponent.metricAttribution?.dependencyMetricIDs, ["dietary_protein"])
        let standalone = try XCTUnwrap(archive.records.first {
            $0.originalUUID == standaloneProteinUUID
        })
        XCTAssertEqual(standalone.metricAttribution?.directMetricIDs, ["dietary_protein"])
        XCTAssertEqual(archive.queryResults.first {
            $0.operation == "queryQuantityRecords"
        }?.recordCount, 1)
    }

    @MainActor
    func test_bloodPressureCorrelationOwnsDirectAttributionWithoutLeakingOtherStandaloneComponents() async throws {
        let store = FakeHealthStore()
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let correlationUUID = UUID(uuidString: "16100000-0000-0000-0000-000000000001")!
        let systolicComponentUUID = UUID(uuidString: "16100000-0000-0000-0000-000000000002")!
        let diastolicComponentUUID = UUID(uuidString: "16100000-0000-0000-0000-000000000003")!
        let standaloneSystolicUUID = UUID(uuidString: "16100000-0000-0000-0000-000000000004")!
        let unrelatedDiastolicUUID = UUID(uuidString: "16100000-0000-0000-0000-000000000005")!
        let systolicIdentifier = HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
        let diastolicIdentifier = HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
        store.bloodPressureRecordResults = [
            record(
                uuid: correlationUUID,
                identifier: HealthKitRecordCatalog.bloodPressureCorrelationIdentifier,
                kind: .correlation,
                startDate: dayStart.addingTimeInterval(4_000),
                relationships: [
                    HealthKitRecordRelationship(targetUUID: systolicComponentUUID, role: "systolic", kind: "component"),
                    HealthKitRecordRelationship(targetUUID: diastolicComponentUUID, role: "diastolic", kind: "component"),
                ]
            ),
            record(
                uuid: systolicComponentUUID,
                identifier: systolicIdentifier,
                startDate: dayStart.addingTimeInterval(4_000),
                relationships: [HealthKitRecordRelationship(targetUUID: correlationUUID, role: "systolic", kind: "parent")]
            ),
            record(
                uuid: diastolicComponentUUID,
                identifier: diastolicIdentifier,
                startDate: dayStart.addingTimeInterval(4_000),
                relationships: [HealthKitRecordRelationship(targetUUID: correlationUUID, role: "diastolic", kind: "parent")]
            ),
        ]
        store.quantityRecordResults[systolicIdentifier] = [
            record(uuid: systolicComponentUUID, identifier: systolicIdentifier, startDate: dayStart.addingTimeInterval(4_000)),
            record(uuid: standaloneSystolicUUID, identifier: systolicIdentifier, startDate: dayStart.addingTimeInterval(8_000)),
        ]
        store.quantityRecordResults[diastolicIdentifier] = [
            record(uuid: unrelatedDiastolicUUID, identifier: diastolicIdentifier, startDate: dayStart.addingTimeInterval(8_000)),
        ]

        let data = try await makeSUT(store: store).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["blood_pressure_systolic"])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)

        XCTAssertEqual(Set(archive.records.map(\.originalUUID)), [
            correlationUUID, systolicComponentUUID, diastolicComponentUUID, standaloneSystolicUUID,
        ])
        XCTAssertEqual(store.queriedQuantityRecordIdentifiers, [systolicIdentifier])
        XCTAssertFalse(archive.records.contains { $0.originalUUID == unrelatedDiastolicUUID })
        XCTAssertEqual(archive.records.first {
            $0.originalUUID == correlationUUID
        }?.metricAttribution?.directMetricIDs, ["blood_pressure_systolic"])
        XCTAssertEqual(archive.records.first {
            $0.originalUUID == systolicComponentUUID
        }?.metricAttribution?.dependencyMetricIDs, ["blood_pressure_systolic"])
        XCTAssertEqual(archive.records.first {
            $0.originalUUID == standaloneSystolicUUID
        }?.metricAttribution?.directMetricIDs, ["blood_pressure_systolic"])
    }

    @MainActor
    func test_crossDayCorrelationRecordsAreOwnedOnceAndKeepTargetOwnerHints() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let firstDay = calendar.startOfDay(for: HealthKitFixtures.referenceDate)
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let parentUUID = UUID(uuidString: "16200000-0000-0000-0000-000000000001")!
        let firstComponentUUID = UUID(uuidString: "16200000-0000-0000-0000-000000000002")!
        let secondComponentUUID = UUID(uuidString: "16200000-0000-0000-0000-000000000003")!
        let store = FakeHealthStore()
        store.bloodPressureRecordResults = [
            record(
                uuid: parentUUID,
                identifier: HealthKitRecordCatalog.bloodPressureCorrelationIdentifier,
                kind: .correlation,
                startDate: secondDay.addingTimeInterval(-60),
                endDate: secondDay.addingTimeInterval(60),
                relationships: [
                    HealthKitRecordRelationship(targetUUID: firstComponentUUID, role: "systolic", kind: "component"),
                    HealthKitRecordRelationship(targetUUID: secondComponentUUID, role: "diastolic", kind: "component"),
                ]
            ),
            record(
                uuid: firstComponentUUID,
                identifier: HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
                startDate: secondDay.addingTimeInterval(-60),
                relationships: [HealthKitRecordRelationship(targetUUID: parentUUID, role: "systolic", kind: "parent")]
            ),
            record(
                uuid: secondComponentUUID,
                identifier: HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue,
                startDate: secondDay.addingTimeInterval(30),
                relationships: [HealthKitRecordRelationship(targetUUID: parentUUID, role: "diastolic", kind: "parent")]
            ),
        ]
        let manager = makeSUT(store: store)
        let firstData = try await manager.fetchHealthData(
            for: firstDay,
            includeGranularData: true,
            metricSelection: selection(["blood_pressure_systolic"])
        )
        let secondData = try await manager.fetchHealthData(
            for: secondDay,
            includeGranularData: true,
            metricSelection: selection(["blood_pressure_systolic"])
        )
        let firstArchive = try XCTUnwrap(firstData.healthKitRecordArchive)
        let secondArchive = try XCTUnwrap(secondData.healthKitRecordArchive)

        XCTAssertEqual(Set(firstArchive.records.map(\.originalUUID)), [parentUUID, firstComponentUUID])
        XCTAssertEqual(secondArchive.records.map(\.originalUUID), [secondComponentUUID])
        let hintedForward = try XCTUnwrap(firstArchive.records.first {
            $0.originalUUID == parentUUID
        }?.relationships.first { $0.targetUUID == secondComponentUUID })
        XCTAssertEqual(hintedForward.targetOwnerDate, secondArchive.dailyOwnership.ownerDate)
        XCTAssertEqual(secondArchive.records.first?.relationships.first?.targetOwnerDate,
                       firstArchive.dailyOwnership.ownerDate)
        let allUUIDs = firstArchive.records.map(\.originalUUID) +
            secondArchive.records.map(\.originalUUID)
        XCTAssertEqual(
            allUUIDs.count,
            Set(allUUIDs).count,
            "A UUID-backed source object must occur in exactly one daily archive"
        )
        XCTAssertEqual(secondArchive.queryResults.first {
            $0.operation == "queryBloodPressureRecords"
        }?.recordCount, 0)
    }

    @MainActor
    func test_selectedSpecialWorkoutAssociationCoverageDoesNotRunUnselectedSelectors() async throws {
        let workoutOnlyStore = FakeHealthStore()
        _ = try await makeSUT(store: workoutOnlyStore).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["workouts"])
        )
        let specialIdentifiers: Set<String> = [
            HealthKitRecordCatalog.cdaDocumentIdentifier,
            HealthKitRecordCatalog.verifiableClinicalRecordIdentifier,
            HealthKitRecordCatalog.visionPrescriptionIdentifier,
            HealthKitRecordCatalog.medicationDoseEventIdentifier,
        ]
        XCTAssertTrue(Set(workoutOnlyStore.workoutRecordQueries.first?
            .associatedSampleEntries.map(\.objectTypeIdentifier) ?? []).isDisjoint(with: specialIdentifiers))

        let selectedStore = FakeHealthStore()
        let selectedMetrics: Set<String> = [
            "workouts", "cda_documents", "verifiable_clinical_records",
            "vision_prescriptions", "medications",
        ]
        _ = try await makeSUT(
            store: selectedStore,
            medicationAuthorizationRequested: true,
            visionAuthorizationRequested: true
        ).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(selectedMetrics)
        )
        let associatedIdentifiers = Set(selectedStore.workoutRecordQueries.first?
            .associatedSampleEntries.map(\.objectTypeIdentifier) ?? [])
        XCTAssertTrue(specialIdentifiers.isSubset(of: associatedIdentifiers))
        XCTAssertTrue(selectedStore.workoutRecordQueries.first?.associatedSampleEntries
            .filter { specialIdentifiers.contains($0.objectTypeIdentifier) }
            .allSatisfy { $0.attribution == HealthKitMetricAttribution(dependencyMetricIDs: ["workouts"]) } == true)
    }

    @MainActor
    func test_medicationSiblingFailuresPreserveSuccessfulDoseOrInventory() async throws {
        let dayStart = Calendar.current.startOfDay(for: HealthKitFixtures.referenceDate)
        let doseUUID = UUID(uuidString: "16300000-0000-0000-0000-000000000001")!
        let dose = HealthKitRecord(
            originalUUID: doseUUID,
            objectTypeIdentifier: HealthKitRecordCatalog.medicationDoseEventIdentifier,
            recordKind: .medicationDoseEvent,
            selectedMetricIDs: ["fixture"],
            includedBecause: .selectedMetric,
            startDate: dayStart.addingTimeInterval(3_600),
            endDate: dayStart.addingTimeInterval(3_601),
            sourceRevision: Self.source,
            payload: .structured(kind: "medicationDoseEvent", fields: [:])
        )
        let inventory = HealthKitMedicationInventoryRecord(
            externalIdentifier: "fixture-medication",
            objectTypeIdentifier: HealthKitRecordCatalog.userAnnotatedMedicationIdentifier,
            selectedMetricIDs: ["fixture"],
            displayName: "Fixture",
            fields: [:]
        )
        let interval = HealthKitQueryInterval(startDate: dayStart, endDate: dayStart.addingTimeInterval(86_400))
        func childFailure(identifier: String, operation: String) -> HealthKitQueryResult {
            HealthKitQueryResult(
                identifier: identifier,
                objectTypeIdentifier: identifier,
                operation: operation,
                metricIDs: ["medications"],
                metricAttribution: HealthKitMetricAttribution(directMetricIDs: ["medications"]),
                interval: interval,
                status: .failure,
                recordCount: 0,
                error: HealthKitQueryError(
                    domain: "MedicationSiblingFixture",
                    code: 91,
                    description: "Sibling query failed",
                    isRecoverable: true
                )
            )
        }

        let doseStore = FakeHealthStore()
        doseStore.medicationRecordResult = HealthKitMedicationRecordQueryResult(
            records: [dose],
            childQueryResults: [childFailure(
                identifier: HealthKitRecordCatalog.userAnnotatedMedicationIdentifier,
                operation: "queryMedicationInventory"
            )]
        )
        let doseData = try await makeSUT(
            store: doseStore,
            medicationAuthorizationRequested: true
        ).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["medications"])
        )
        let doseArchive = try XCTUnwrap(doseData.healthKitRecordArchive)
        XCTAssertEqual(doseArchive.records.map(\.originalUUID), [doseUUID])
        XCTAssertTrue(doseArchive.medicationInventoryRecords.isEmpty)
        XCTAssertEqual(doseArchive.captureStatus, .partial)
        XCTAssertEqual(doseArchive.queryResults.first {
            $0.operation == "queryMedicationInventory"
        }?.status, .failure)

        let inventoryStore = FakeHealthStore()
        inventoryStore.medicationRecordResult = HealthKitMedicationRecordQueryResult(
            inventoryRecords: [inventory],
            childQueryResults: [childFailure(
                identifier: HealthKitRecordCatalog.medicationDoseEventIdentifier,
                operation: "queryMedicationDoseEvents"
            )]
        )
        let inventoryData = try await makeSUT(
            store: inventoryStore,
            medicationAuthorizationRequested: true
        ).fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["medications"])
        )
        let inventoryArchive = try XCTUnwrap(inventoryData.healthKitRecordArchive)
        XCTAssertTrue(inventoryArchive.records.isEmpty)
        XCTAssertEqual(inventoryArchive.medicationInventoryRecords.map(\.externalIdentifier),
                       ["fixture-medication"])
        XCTAssertEqual(inventoryArchive.captureStatus, .partial)
        XCTAssertEqual(inventoryArchive.queryResults.first {
            $0.operation == "queryMedicationDoseEvents"
        }?.status, .failure)
    }

    @MainActor
    func test_unauthorizedMedicationSelectionProducesExplicitSkippedManifestEntry() async throws {
        let store = FakeHealthStore()
        let sut = makeSUT(store: store)

        let data = try await sut.fetchHealthData(
            for: HealthKitFixtures.referenceDate,
            includeGranularData: true,
            metricSelection: selection(["medications"])
        )

        let result = try XCTUnwrap(data.healthKitRecordArchive?.queryResults.first)
        XCTAssertEqual(result.objectTypeIdentifier, HealthKitRecordCatalog.medicationDoseEventIdentifier)
        XCTAssertEqual(result.status, .skipped)
        XCTAssertNotNil(result.statusDescription)
        XCTAssertEqual(data.healthKitRecordCaptureStatus, .partial)
        XCTAssertTrue(store.queriedQuantityRecordIdentifiers.isEmpty)
        XCTAssertTrue(store.queriedCategoryRecordIdentifiers.isEmpty)
        XCTAssertFalse(store.medicationsQueried)
        XCTAssertFalse(store.medicationDoseEventsQueried)
    }

    private func selection(_ metricIDs: Set<String>) -> MetricSelectionState {
        let result = MetricSelectionState()
        result.deselectAll()
        result.enabledMetrics = metricIDs
        return result
    }

    private func record(
        uuid: UUID,
        identifier: String,
        kind: HealthKitRecordKind = .quantity,
        startDate: Date,
        endDate: Date? = nil,
        relationships: [HealthKitRecordRelationship] = []
    ) -> HealthKitRecord {
        let payload: HealthKitRecordPayload
        switch kind {
        case .category:
            payload = .category(HealthKitCategoryPayload(rawValue: 1, symbolicValue: nil))
        case .correlation:
            payload = .correlation(componentUUIDs: relationships.compactMap(\.targetUUID))
        default:
            payload = .quantity(HealthKitQuantityPayload(value: 100, unit: "count"))
        }
        return HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: identifier,
            recordKind: kind,
            selectedMetricIDs: ["fixture"],
            includedBecause: .selectedMetric,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(1),
            sourceRevision: Self.source,
            payload: payload,
            relationships: relationships
        )
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
        XCTAssertFalse(identifiers.contains("HKMedicationDoseEventTypeIdentifierMedicationDoseEvent"),
                       "Medication dose events use per-object authorization and should not be registered in standard observer setup")
        XCTAssertEqual(identifiers.count, 2, "Should monitor exactly expected standard types")
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
