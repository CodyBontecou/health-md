import Foundation
import HealthKit
import Combine
import os.log

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.healthexporter", category: "HealthKitManager")

    /// Active observer queries for background delivery
    private var observerQueries: [HKObserverQuery] = []

    /// Callback triggered when background delivery receives new data
    var onBackgroundDelivery: (() -> Void)?

    @Published var isAuthorized = false
    @Published var authorizationStatus: String = "Not Connected"

    // MARK: - Error Types

    enum HealthKitError: LocalizedError {
        case dataNotAvailable
        case notAuthorized
        case dataProtectedWhileLocked

        var errorDescription: String? {
            switch self {
            case .dataNotAvailable:
                return "Health data is not available on this device"
            case .notAuthorized:
                return "Health data access not authorized. Please grant permissions in Settings."
            case .dataProtectedWhileLocked:
                return "Health data is unavailable while the device is locked. Please unlock your device."
            }
        }
    }

    // MARK: - Health Data Types

    private var allReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        // Sleep
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        // Activity
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let activeCalories = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeCalories)
        }
        if let exerciseMinutes = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseMinutes)
        }
        if let flights = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) {
            types.insert(flights)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }

        // Vitals
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let respiratoryRate = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respiratoryRate)
        }
        if let bloodOxygen = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(bloodOxygen)
        }

        // Body
        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weight)
        }
        if let bodyFat = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(bodyFat)
        }

        // Workouts
        types.insert(HKObjectType.workoutType())

        return types
    }

    // MARK: - Authorization

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            authorizationStatus = "Health data not available"
            return
        }

        try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)
        isAuthorized = true
        authorizationStatus = "Connected"
    }

    /// Checks if HealthKit data can be accessed in the current context (background or foreground)
    /// Note: For read-only apps, we cannot check authorization status because Apple hides it for privacy.
    /// authorizationStatus(for:) only reports WRITE permission status, not READ permission status.
    /// We simply verify HealthKit is available and let the queries run - if access is denied,
    /// the queries will return empty results (which is indistinguishable from no data).
    private func checkAuthorizationForBackgroundAccess() throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.dataNotAvailable
        }
        // For read-only access, we cannot determine if the user granted permission.
        // Apple intentionally hides this for privacy - denied access looks like empty data.
        // Just proceed with queries; they will return empty results if access is denied.
    }

    // MARK: - Background Delivery

    /// Data types to monitor for background delivery (most likely to trigger daily exports)
    private var backgroundDeliveryTypes: [HKSampleType] {
        var types: [HKSampleType] = []

        // Sleep analysis - triggers when sleep data syncs (usually morning)
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.append(sleepType)
        }

        // Steps - triggers frequently throughout the day
        if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.append(stepsType)
        }

        return types
    }

    /// Enables background delivery for key health data types
    /// Call this after authorization is granted
    func enableBackgroundDelivery() async {
        guard isHealthDataAvailable else {
            logger.warning("Health data not available, skipping background delivery setup")
            return
        }

        for sampleType in backgroundDeliveryTypes {
            do {
                // Use .hourly frequency to balance reliability with battery
                try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly)
                logger.info("Enabled background delivery for \(sampleType.identifier)")
            } catch {
                logger.error("Failed to enable background delivery for \(sampleType.identifier): \(error.localizedDescription)")
            }
        }
    }

    /// Disables all background delivery
    func disableBackgroundDelivery() async {
        do {
            try await healthStore.disableAllBackgroundDelivery()
            logger.info("Disabled all background delivery")
        } catch {
            logger.error("Failed to disable background delivery: \(error.localizedDescription)")
        }
    }

    /// Sets up observer queries for background delivery
    /// These queries will wake the app when new health data arrives
    func setupObserverQueries() {
        // Remove any existing queries first
        stopObserverQueries()

        for sampleType in backgroundDeliveryTypes {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] query, completionHandler, error in
                guard let self = self else {
                    completionHandler()
                    return
                }

                if let error = error {
                    self.logger.error("Observer query error for \(sampleType.identifier): \(error.localizedDescription)")
                    completionHandler()
                    return
                }

                self.logger.info("Background delivery triggered for \(sampleType.identifier)")

                // Notify that new data is available
                Task { @MainActor in
                    self.onBackgroundDelivery?()
                }

                // Important: Must call completion handler
                completionHandler()
            }

            healthStore.execute(query)
            observerQueries.append(query)
            logger.info("Started observer query for \(sampleType.identifier)")
        }
    }

    /// Stops all observer queries
    func stopObserverQueries() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
        logger.info("Stopped all observer queries")
    }

    // MARK: - Fetch All Health Data

    func fetchHealthData(for date: Date) async throws -> HealthData {
        var healthData = HealthData(date: date)

        // Check authorization before attempting to query
        // This is especially important in background contexts
        try checkAuthorizationForBackgroundAccess()

        do {
            // Fetch all data concurrently
            async let sleepData = fetchSleepData(for: date)
            async let activityData = fetchActivityData(for: date)
            async let vitalsData = fetchVitalsData(for: date)
            async let bodyData = fetchBodyData(for: date)
            async let workoutsData = fetchWorkouts(for: date)

            healthData.sleep = try await sleepData
            healthData.activity = try await activityData
            healthData.vitals = try await vitalsData
            healthData.body = try await bodyData
            healthData.workouts = try await workoutsData

            return healthData
        } catch {
            // If we get an error that suggests data protection (device locked),
            // throw a more specific error
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("protected") ||
               errorMessage.contains("authorization") ||
               errorMessage.contains("not authorized") {
                logger.error("HealthKit query failed (likely device locked): \(error.localizedDescription)")
                throw HealthKitError.dataProtectedWhileLocked
            }
            throw error
        }
    }

    // MARK: - Sleep Data

    private func fetchSleepData(for date: Date) async throws -> SleepData {
        var sleepData = SleepData()

        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return sleepData
        }

        // Get sleep samples for the night ending on the selected date
        // Sleep typically spans midnight, so we look from 6pm the day before to 12pm on the selected date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: startOfDay)!
        let sleepWindowEnd = calendar.date(byAdding: .hour, value: 12, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: sleepWindowStart, end: sleepWindowEnd)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        let samples = try await descriptor.result(for: healthStore)

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)

            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                sleepData.deepSleep += duration
                sleepData.totalDuration += duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                sleepData.remSleep += duration
                sleepData.totalDuration += duration
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                sleepData.coreSleep += duration
                sleepData.totalDuration += duration
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                sleepData.totalDuration += duration
            default:
                break
            }
        }

        return sleepData
    }

    // MARK: - Activity Data

    private func fetchActivityData(for date: Date) async throws -> ActivityData {
        var activityData = ActivityData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Steps
        if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let stepsDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: stepsType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await stepsDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.steps = Int(sum.doubleValue(for: .count()))
            }
        }

        // Active Calories
        if let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let caloriesDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: caloriesType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await caloriesDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.activeCalories = sum.doubleValue(for: .kilocalorie())
            }
        }

        // Exercise Minutes
        if let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            let exerciseDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: exerciseType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await exerciseDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.exerciseMinutes = sum.doubleValue(for: .minute())
            }
        }

        // Flights Climbed
        if let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) {
            let flightsDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: flightsType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await flightsDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.flightsClimbed = Int(sum.doubleValue(for: .count()))
            }
        }

        // Walking/Running Distance
        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let distanceDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: distanceType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await distanceDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.walkingRunningDistance = sum.doubleValue(for: .meter())
            }
        }

        return activityData
    }

    // MARK: - Vitals Data

    private func fetchVitalsData(for date: Date) async throws -> VitalsData {
        var vitalsData = VitalsData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Resting Heart Rate
        if let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let hrDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: hrType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await hrDescriptor.result(for: healthStore).first {
                vitalsData.restingHeartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            }
        }

        // HRV
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let hrvDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: hrvType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await hrvDescriptor.result(for: healthStore).first {
                vitalsData.hrv = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
            }
        }

        // Respiratory Rate
        if let rrType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            let rrDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: rrType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await rrDescriptor.result(for: healthStore).first {
                vitalsData.respiratoryRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            }
        }

        // Blood Oxygen (SpO2)
        if let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            let spo2Descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: spo2Type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await spo2Descriptor.result(for: healthStore).first {
                vitalsData.bloodOxygen = sample.quantity.doubleValue(for: .percent())
            }
        }

        return vitalsData
    }

    // MARK: - Body Data

    private func fetchBodyData(for date: Date) async throws -> BodyData {
        var bodyData = BodyData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Weight
        if let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let weightDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: weightType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await weightDescriptor.result(for: healthStore).first {
                bodyData.weight = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            }
        }

        // Body Fat Percentage
        if let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            let bodyFatDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: bodyFatType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await bodyFatDescriptor.result(for: healthStore).first {
                bodyData.bodyFatPercentage = sample.quantity.doubleValue(for: .percent())
            }
        }

        return bodyData
    }

    // MARK: - Workouts

    private func fetchWorkouts(for date: Date) async throws -> [WorkoutData] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        let samples = try await descriptor.result(for: healthStore)

        return samples.map { workout in
            WorkoutData(
                workoutType: workout.workoutActivityType,
                startTime: workout.startDate,
                duration: workout.duration,
                calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                distance: workout.totalDistance?.doubleValue(for: .meter())
            )
        }
    }
}
