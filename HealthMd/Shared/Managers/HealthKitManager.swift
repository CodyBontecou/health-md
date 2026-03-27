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
        if let basalCalories = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) {
            types.insert(basalCalories)
        }
        if let exerciseMinutes = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseMinutes)
        }
        // Stand metrics (both stand time and stand-hour ring buckets)
        if let standTime = HKQuantityType.quantityType(forIdentifier: .appleStandTime) {
            types.insert(standTime)
        }
        if let standHour = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(standHour)
        }
        if let flights = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) {
            types.insert(flights)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let cycling = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            types.insert(cycling)
        }
        if let swimming = HKQuantityType.quantityType(forIdentifier: .distanceSwimming) {
            types.insert(swimming)
        }
        if let strokes = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount) {
            types.insert(strokes)
        }
        if let pushCount = HKQuantityType.quantityType(forIdentifier: .pushCount) {
            types.insert(pushCount)
        }

        // Heart
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let walkingHR = HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage) {
            types.insert(walkingHR)
        }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let vo2Max = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            types.insert(vo2Max)
        }

        // Vitals
        if let respiratoryRate = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respiratoryRate)
        }
        if let bloodOxygen = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(bloodOxygen)
        }
        if let bodyTemp = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) {
            types.insert(bodyTemp)
        }
        if let bloodPressureSystolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) {
            types.insert(bloodPressureSystolic)
        }
        if let bloodPressureDiastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(bloodPressureDiastolic)
        }
        if let bloodGlucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            types.insert(bloodGlucose)
        }

        // Body
        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weight)
        }
        if let height = HKQuantityType.quantityType(forIdentifier: .height) {
            types.insert(height)
        }
        if let bmi = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            types.insert(bmi)
        }
        if let bodyFat = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(bodyFat)
        }
        if let leanBodyMass = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            types.insert(leanBodyMass)
        }
        if let waist = HKQuantityType.quantityType(forIdentifier: .waistCircumference) {
            types.insert(waist)
        }

        // Nutrition
        if let dietaryEnergy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            types.insert(dietaryEnergy)
        }
        if let protein = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            types.insert(protein)
        }
        if let carbs = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            types.insert(carbs)
        }
        if let fat = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            types.insert(fat)
        }
        if let saturatedFat = HKQuantityType.quantityType(forIdentifier: .dietaryFatSaturated) {
            types.insert(saturatedFat)
        }
        if let fiber = HKQuantityType.quantityType(forIdentifier: .dietaryFiber) {
            types.insert(fiber)
        }
        if let sugar = HKQuantityType.quantityType(forIdentifier: .dietarySugar) {
            types.insert(sugar)
        }
        if let sodium = HKQuantityType.quantityType(forIdentifier: .dietarySodium) {
            types.insert(sodium)
        }
        if let cholesterol = HKQuantityType.quantityType(forIdentifier: .dietaryCholesterol) {
            types.insert(cholesterol)
        }
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }
        if let caffeine = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) {
            types.insert(caffeine)
        }

        // Mindfulness
        if let mindful = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindful)
        }
        
        // State of Mind (iOS 18+)
        if #available(iOS 18.0, macOS 15.0, *) {
            types.insert(HKSampleType.stateOfMindType())
        }

        // Mobility
        if let walkingSpeed = HKQuantityType.quantityType(forIdentifier: .walkingSpeed) {
            types.insert(walkingSpeed)
        }
        if let stepLength = HKQuantityType.quantityType(forIdentifier: .walkingStepLength) {
            types.insert(stepLength)
        }
        if let doubleSupport = HKQuantityType.quantityType(forIdentifier: .walkingDoubleSupportPercentage) {
            types.insert(doubleSupport)
        }
        if let asymmetry = HKQuantityType.quantityType(forIdentifier: .walkingAsymmetryPercentage) {
            types.insert(asymmetry)
        }
        if let stairAscent = HKQuantityType.quantityType(forIdentifier: .stairAscentSpeed) {
            types.insert(stairAscent)
        }
        if let stairDescent = HKQuantityType.quantityType(forIdentifier: .stairDescentSpeed) {
            types.insert(stairDescent)
        }
        if let sixMinWalk = HKQuantityType.quantityType(forIdentifier: .sixMinuteWalkTestDistance) {
            types.insert(sixMinWalk)
        }

        // Hearing
        if let headphoneAudio = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) {
            types.insert(headphoneAudio)
        }
        if let environmentalSound = HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure) {
            types.insert(environmentalSound)
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

    // MARK: - Observer / Background Delivery

    /// Data types to monitor for new data (background delivery on iOS, observer queries on macOS)
    private var monitoredTypes: [HKSampleType] {
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

    #if os(iOS)
    /// Enables background delivery for key health data types (iOS only).
    /// Call this after authorization is granted.
    func enableBackgroundDelivery() async {
        guard isHealthDataAvailable else {
            logger.warning("Health data not available, skipping background delivery setup")
            return
        }

        for sampleType in monitoredTypes {
            do {
                // Use .hourly frequency to balance reliability with battery
                try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly)
                logger.info("Enabled background delivery for \(sampleType.identifier)")
            } catch {
                logger.error("Failed to enable background delivery for \(sampleType.identifier): \(error.localizedDescription)")
            }
        }
    }

    /// Disables all background delivery (iOS only)
    func disableBackgroundDelivery() async {
        do {
            try await healthStore.disableAllBackgroundDelivery()
            logger.info("Disabled all background delivery")
        } catch {
            logger.error("Failed to disable background delivery: \(error.localizedDescription)")
        }
    }
    #endif

    /// Sets up observer queries to detect new health data.
    /// On iOS these pair with background delivery; on macOS they fire while the app is running.
    func setupObserverQueries() {
        // Remove any existing queries first
        stopObserverQueries()

        for sampleType in monitoredTypes {
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

                self.logger.info("New data detected for \(sampleType.identifier)")

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

    #if os(macOS)
    /// Polling timer for macOS — supplements observer queries for reliability.
    /// The app stays running in the menu bar, so a simple timer works.
    private var pollingTimer: Timer?

    func setupPollingTimer(interval: TimeInterval = 3600) {
        stopPollingTimer()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let manager = self else { return }
            Task { @MainActor [manager] in
                manager.onBackgroundDelivery?()
            }
        }
        logger.info("Started macOS polling timer with interval \(interval)s")
    }

    func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    #endif

    // MARK: - Fetch All Health Data

    func fetchHealthData(for date: Date) async throws -> HealthData {
        var healthData = HealthData(date: date)

        // Check authorization before attempting to query
        // This is especially important in background contexts
        try checkAuthorizationForBackgroundAccess()

        // Kick off all categories concurrently.
        async let sleepTask     = fetchSleepData(for: date)
        async let activityTask  = fetchActivityData(for: date)
        async let heartTask     = fetchHeartData(for: date)
        async let vitalsTask    = fetchVitalsData(for: date)
        async let bodyTask      = fetchBodyData(for: date)
        async let nutritionTask = fetchNutritionData(for: date)
        async let mindfulTask   = fetchMindfulnessData(for: date)
        async let mobilityTask  = fetchMobilityData(for: date)
        async let hearingTask   = fetchHearingData(for: date)
        async let workoutsTask  = fetchWorkouts(for: date)

        // Collect results with per-category isolation.
        //
        // Design intent:
        //  • Device-locked / auth errors are re-thrown so the caller can show a
        //    clear "unlock your device" message.
        //  • Every other error is logged and swallowed — one bad metric never
        //    prevents the remaining categories from exporting.
        //
        // This is the architectural lesson from the v1.7.5 crash: a single
        // invalid HKUnit string in `fetchActivityData` silently aborted the
        // entire export for all users who had VO₂ Max data.

        func isDeviceLocked(_ error: Error) -> Bool {
            let msg = error.localizedDescription.lowercased()
            return msg.contains("protected") || msg.contains("authorization") || msg.contains("not authorized")
        }

        do { healthData.sleep       = try await sleepTask     } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("sleep fetch failed: \(error.localizedDescription)")
        }
        do { healthData.activity    = try await activityTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("activity fetch failed: \(error.localizedDescription)")
        }
        do { healthData.heart       = try await heartTask     } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("heart fetch failed: \(error.localizedDescription)")
        }
        do { healthData.vitals      = try await vitalsTask    } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("vitals fetch failed: \(error.localizedDescription)")
        }
        do { healthData.body        = try await bodyTask      } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("body fetch failed: \(error.localizedDescription)")
        }
        do { healthData.nutrition   = try await nutritionTask } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("nutrition fetch failed: \(error.localizedDescription)")
        }
        do { healthData.mindfulness = try await mindfulTask   } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("mindfulness fetch failed: \(error.localizedDescription)")
        }
        do { healthData.mobility    = try await mobilityTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("mobility fetch failed: \(error.localizedDescription)")
        }
        do { healthData.hearing     = try await hearingTask   } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("hearing fetch failed: \(error.localizedDescription)")
        }
        do { healthData.workouts    = try await workoutsTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            logger.warning("workouts fetch failed: \(error.localizedDescription)")
        }

        return healthData
    }

    // MARK: - Earliest Data Date

    /// Finds the earliest date for which HealthKit has any data.
    /// Queries the oldest sample across several common data types to determine
    /// when the user's health data history begins.
    func findEarliestHealthDataDate() async -> Date? {
        // Query a few common types that most users will have
        let typeIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .heartRate,
            .bodyMass
        ]

        var earliestDate: Date?

        for identifier in typeIdentifiers {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }

            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: quantityType)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
                limit: 1
            )

            do {
                if let sample = try await descriptor.result(for: healthStore).first {
                    if earliestDate == nil || sample.startDate < earliestDate! {
                        earliestDate = sample.startDate
                    }
                }
            } catch {
                logger.warning("Failed to query earliest date for \(identifier.rawValue): \(error.localizedDescription)")
            }
        }

        // Also check sleep analysis
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: sleepType)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
                limit: 1
            )

            do {
                if let sample = try await descriptor.result(for: healthStore).first {
                    if earliestDate == nil || sample.startDate < earliestDate! {
                        earliestDate = sample.startDate
                    }
                }
            } catch {
                logger.warning("Failed to query earliest sleep date: \(error.localizedDescription)")
            }
        }

        // Also check workouts
        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [.workout()],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 1
        )

        do {
            if let sample = try await workoutDescriptor.result(for: healthStore).first {
                if earliestDate == nil || sample.startDate < earliestDate! {
                    earliestDate = sample.startDate
                }
            }
        } catch {
            logger.warning("Failed to query earliest workout date: \(error.localizedDescription)")
        }

        return earliestDate
    }

    // MARK: - Sleep Data

    /// Merges an array of (start, end) intervals, combining any that overlap or are adjacent.
    /// Returns the merged intervals sorted by start date.
    private func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        Self.mergeIntervals(intervals)
    }

    /// Computes total duration from merged intervals.
    private func totalDuration(of intervals: [(start: Date, end: Date)]) -> TimeInterval {
        Self.totalDuration(of: intervals)
    }

    // MARK: - Sleep Interval Utilities (internal for testing)

    /// Merges an array of (start, end) intervals, combining any that overlap or are adjacent.
    /// Returns the merged intervals sorted by start date.
    static func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }

        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = [sorted[0]]

        for interval in sorted.dropFirst() {
            if interval.start <= merged[merged.count - 1].end {
                // Overlapping or adjacent — extend the current merged interval
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, interval.end)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    /// Computes total duration from merged intervals.
    static func totalDuration(of intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let merged = mergeIntervals(intervals)
        return merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// Computes total sleep duration from raw interval buckets, matching Apple Health's
    /// "Time Asleep" display.
    ///
    /// - When `inBedIntervals` is non-empty (Apple Watch pattern), returns
    ///   `union(inBed) − union(awake)` so that unlabelled gaps inside the InBed session
    ///   are counted as asleep — exactly as Apple Health does.
    /// - Otherwise falls back to `union(deep + rem + core + unspecified)` for sources that
    ///   emit only asleep-labelled samples without a wrapping InBed interval.
    static func computeTotalSleepDuration(
        deepIntervals: [(start: Date, end: Date)],
        remIntervals: [(start: Date, end: Date)],
        coreIntervals: [(start: Date, end: Date)],
        unspecifiedIntervals: [(start: Date, end: Date)],
        awakeIntervals: [(start: Date, end: Date)],
        inBedIntervals: [(start: Date, end: Date)]
    ) -> TimeInterval {
        let inBedDuration = totalDuration(of: inBedIntervals)
        if inBedDuration > 0 {
            let awakeDuration = totalDuration(of: awakeIntervals)
            return max(0, inBedDuration - awakeDuration)
        } else {
            let allAsleepIntervals = deepIntervals + remIntervals + coreIntervals + unspecifiedIntervals
            return totalDuration(of: allAsleepIntervals)
        }
    }

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

        // Collect intervals per sleep category to merge overlapping samples from multiple sources
        var deepIntervals: [(start: Date, end: Date)] = []
        var remIntervals: [(start: Date, end: Date)] = []
        var coreIntervals: [(start: Date, end: Date)] = []
        var unspecifiedIntervals: [(start: Date, end: Date)] = []
        var awakeIntervals: [(start: Date, end: Date)] = []
        var inBedIntervals: [(start: Date, end: Date)] = []

        for sample in samples {
            let interval = (start: sample.startDate, end: sample.endDate)

            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepIntervals.append(interval)
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remIntervals.append(interval)
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                coreIntervals.append(interval)
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                unspecifiedIntervals.append(interval)
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeIntervals.append(interval)
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                inBedIntervals.append(interval)
            default:
                break
            }
        }

        // Compute per-stage durations from merged (deduplicated) intervals
        sleepData.deepSleep = totalDuration(of: deepIntervals)
        sleepData.remSleep = totalDuration(of: remIntervals)
        sleepData.coreSleep = totalDuration(of: coreIntervals)
        sleepData.awakeTime = totalDuration(of: awakeIntervals)
        sleepData.inBedTime = totalDuration(of: inBedIntervals)

        // See computeTotalSleepDuration for the full explanation of this calculation.
        sleepData.totalDuration = Self.computeTotalSleepDuration(
            deepIntervals: deepIntervals,
            remIntervals: remIntervals,
            coreIntervals: coreIntervals,
            unspecifiedIntervals: unspecifiedIntervals,
            awakeIntervals: awakeIntervals,
            inBedIntervals: inBedIntervals
        )

        // Compute session boundaries (Bedtime and Wake).
        // Prefer InBed intervals as they define the full session edges; fall back to
        // the union of sleep-stage intervals for sources that don't emit InBed samples.
        let sessionIntervals: [(start: Date, end: Date)]
        if !inBedIntervals.isEmpty {
            sessionIntervals = mergeIntervals(inBedIntervals)
        } else {
            let allSleepIntervals = deepIntervals + remIntervals + coreIntervals + unspecifiedIntervals
            sessionIntervals = mergeIntervals(allSleepIntervals)
        }
        sleepData.sessionStart = sessionIntervals.first?.start
        sleepData.sessionEnd   = sessionIntervals.last?.end

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

        // Basal Energy Burned
        if let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) {
            let basalDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: basalType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await basalDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.basalEnergyBurned = sum.doubleValue(for: .kilocalorie())
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

        // Stand Hours (Apple's stand ring metric: hours with at least 1 minute stood)
        if let standHourType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            let standHourDescriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: standHourType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let standHourSamples = try await standHourDescriptor.result(for: healthStore)

            if !standHourSamples.isEmpty {
                let stoodValue = HKCategoryValueAppleStandHour.stood.rawValue
                let stoodHours = Set(
                    standHourSamples
                        .filter { $0.value == stoodValue }
                        .compactMap { calendar.dateInterval(of: .hour, for: $0.startDate)?.start }
                )
                activityData.standHours = stoodHours.count
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

        // Cycling Distance
        if let cyclingType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            let cyclingDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: cyclingType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await cyclingDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.cyclingDistance = sum.doubleValue(for: .meter())
            }
        }

        // Swimming Distance
        if let swimmingType = HKQuantityType.quantityType(forIdentifier: .distanceSwimming) {
            let swimmingDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: swimmingType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await swimmingDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.swimmingDistance = sum.doubleValue(for: .meter())
            }
        }

        // Swimming Strokes
        if let strokesType = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount) {
            let strokesDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: strokesType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await strokesDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.swimmingStrokes = Int(sum.doubleValue(for: .count()))
            }
        }

        // Wheelchair Push Count
        if let pushType = HKQuantityType.quantityType(forIdentifier: .pushCount) {
            let pushDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: pushType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await pushDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                activityData.pushCount = Int(sum.doubleValue(for: .count()))
            }
        }

        // VO2 Max / Cardio Fitness — Apple Watch only generates a sample after certain
        // workouts or periodic background measurements, so there may be no sample on a
        // given day.  Query for the most-recent sample up to (and including) the end of
        // the requested day so we always surface the latest known value.
        if let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            let vo2Predicate = HKQuery.predicateForSamples(withStart: nil, end: endOfDay)
            let vo2Descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: vo2MaxType, predicate: vo2Predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await vo2Descriptor.result(for: healthStore).first {
                // HKUnit for VO2 Max: must use parentheses form "ml/(kg*min)".
                // "ml/kg/min" (two bare divisions) throws an NSException at runtime.
                let vo2Unit = HKUnits.vo2Max
                activityData.vo2Max = sample.quantity.doubleValue(for: vo2Unit)
            }
        }

        return activityData
    }

    // MARK: - Heart Data

    private func fetchHeartData(for date: Date) async throws -> HeartData {
        var heartData = HeartData()

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
                heartData.restingHeartRate = sample.quantity.doubleValue(for: HKUnits.countPerMinute)
            }
        }

        // Walking Heart Rate Average
        if let walkingHRType = HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage) {
            let walkingHRDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: walkingHRType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await walkingHRDescriptor.result(for: healthStore).first {
                heartData.walkingHeartRateAverage = sample.quantity.doubleValue(for: HKUnits.countPerMinute)
            }
        }

        // Heart Rate (average, min, max for the day)
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let avgDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: heartRateType, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            if let result = try await avgDescriptor.result(for: healthStore) {
                if let avg = result.averageQuantity() {
                    heartData.averageHeartRate = avg.doubleValue(for: HKUnits.countPerMinute)
                }
                if let min = result.minimumQuantity() {
                    heartData.heartRateMin = min.doubleValue(for: HKUnits.countPerMinute)
                }
                if let max = result.maximumQuantity() {
                    heartData.heartRateMax = max.doubleValue(for: HKUnits.countPerMinute)
                }
            }
        }

        // HRV — use the daily average across all SDNN samples, matching Apple Health's display
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let hrvDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: hrvType, predicate: predicate),
                options: [.discreteAverage]
            )
            if let result = try await hrvDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                heartData.hrv = avg.doubleValue(for: .secondUnit(with: .milli))
            }
        }

        return heartData
    }

    // MARK: - Vitals Data

    private func fetchVitalsData(for date: Date) async throws -> VitalsData {
        var vitalsData = VitalsData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Respiratory Rate (daily aggregates)
        if let rrType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            let rrDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: rrType, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            if let result = try await rrDescriptor.result(for: healthStore) {
                let unit = HKUnits.countPerMinute
                if let avg = result.averageQuantity() {
                    vitalsData.respiratoryRateAvg = avg.doubleValue(for: unit)
                }
                if let min = result.minimumQuantity() {
                    vitalsData.respiratoryRateMin = min.doubleValue(for: unit)
                }
                if let max = result.maximumQuantity() {
                    vitalsData.respiratoryRateMax = max.doubleValue(for: unit)
                }
            }
        }

        // Blood Oxygen / SpO2 (daily aggregates)
        if let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            let spo2Descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: spo2Type, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            if let result = try await spo2Descriptor.result(for: healthStore) {
                if let avg = result.averageQuantity() {
                    vitalsData.bloodOxygenAvg = avg.doubleValue(for: .percent())
                }
                if let min = result.minimumQuantity() {
                    vitalsData.bloodOxygenMin = min.doubleValue(for: .percent())
                }
                if let max = result.maximumQuantity() {
                    vitalsData.bloodOxygenMax = max.doubleValue(for: .percent())
                }
            }
        }

        // Body Temperature (daily aggregates)
        if let tempType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) {
            let tempDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: tempType, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            if let result = try await tempDescriptor.result(for: healthStore) {
                if let avg = result.averageQuantity() {
                    vitalsData.bodyTemperatureAvg = avg.doubleValue(for: .degreeCelsius())
                }
                if let min = result.minimumQuantity() {
                    vitalsData.bodyTemperatureMin = min.doubleValue(for: .degreeCelsius())
                }
                if let max = result.maximumQuantity() {
                    vitalsData.bodyTemperatureMax = max.doubleValue(for: .degreeCelsius())
                }
            }
        }

        // Blood Pressure Systolic (daily aggregates)
        if let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) {
            let systolicDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: systolicType, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            if let result = try await systolicDescriptor.result(for: healthStore) {
                if let avg = result.averageQuantity() {
                    vitalsData.bloodPressureSystolicAvg = avg.doubleValue(for: .millimeterOfMercury())
                }
                if let min = result.minimumQuantity() {
                    vitalsData.bloodPressureSystolicMin = min.doubleValue(for: .millimeterOfMercury())
                }
                if let max = result.maximumQuantity() {
                    vitalsData.bloodPressureSystolicMax = max.doubleValue(for: .millimeterOfMercury())
                }
            }
        }

        // Blood Pressure Diastolic (daily aggregates)
        if let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            let diastolicDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: diastolicType, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            if let result = try await diastolicDescriptor.result(for: healthStore) {
                if let avg = result.averageQuantity() {
                    vitalsData.bloodPressureDiastolicAvg = avg.doubleValue(for: .millimeterOfMercury())
                }
                if let min = result.minimumQuantity() {
                    vitalsData.bloodPressureDiastolicMin = min.doubleValue(for: .millimeterOfMercury())
                }
                if let max = result.maximumQuantity() {
                    vitalsData.bloodPressureDiastolicMax = max.doubleValue(for: .millimeterOfMercury())
                }
            }
        }

        // Blood Glucose (daily aggregates)
        if let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            let glucoseDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: glucoseType, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            if let result = try await glucoseDescriptor.result(for: healthStore) {
                let unit = HKUnits.milligramsPerDeciliter
                if let avg = result.averageQuantity() {
                    vitalsData.bloodGlucoseAvg = avg.doubleValue(for: unit)
                }
                if let min = result.minimumQuantity() {
                    vitalsData.bloodGlucoseMin = min.doubleValue(for: unit)
                }
                if let max = result.maximumQuantity() {
                    vitalsData.bloodGlucoseMax = max.doubleValue(for: unit)
                }
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

        // Height
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            let heightDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: heightType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await heightDescriptor.result(for: healthStore).first {
                bodyData.height = sample.quantity.doubleValue(for: .meter())
            }
        }

        // BMI
        if let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            let bmiDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: bmiType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await bmiDescriptor.result(for: healthStore).first {
                bodyData.bmi = sample.quantity.doubleValue(for: .count())
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

        // Lean Body Mass
        if let leanType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            let leanDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: leanType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await leanDescriptor.result(for: healthStore).first {
                bodyData.leanBodyMass = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            }
        }

        // Waist Circumference
        if let waistType = HKQuantityType.quantityType(forIdentifier: .waistCircumference) {
            let waistDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: waistType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await waistDescriptor.result(for: healthStore).first {
                bodyData.waistCircumference = sample.quantity.doubleValue(for: .meter())
            }
        }

        return bodyData
    }

    // MARK: - Nutrition Data

    private func fetchNutritionData(for date: Date) async throws -> NutritionData {
        var nutritionData = NutritionData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Dietary Energy
        if let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let energyDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: energyType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await energyDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.dietaryEnergy = sum.doubleValue(for: .kilocalorie())
            }
        }

        // Protein
        if let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            let proteinDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: proteinType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await proteinDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.protein = sum.doubleValue(for: .gram())
            }
        }

        // Carbohydrates
        if let carbsType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let carbsDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: carbsType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await carbsDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.carbohydrates = sum.doubleValue(for: .gram())
            }
        }

        // Fat
        if let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            let fatDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: fatType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await fatDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.fat = sum.doubleValue(for: .gram())
            }
        }

        // Saturated Fat
        if let satFatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatSaturated) {
            let satFatDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: satFatType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await satFatDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.saturatedFat = sum.doubleValue(for: .gram())
            }
        }

        // Fiber
        if let fiberType = HKQuantityType.quantityType(forIdentifier: .dietaryFiber) {
            let fiberDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: fiberType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await fiberDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.fiber = sum.doubleValue(for: .gram())
            }
        }

        // Sugar
        if let sugarType = HKQuantityType.quantityType(forIdentifier: .dietarySugar) {
            let sugarDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: sugarType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await sugarDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.sugar = sum.doubleValue(for: .gram())
            }
        }

        // Sodium
        if let sodiumType = HKQuantityType.quantityType(forIdentifier: .dietarySodium) {
            let sodiumDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: sodiumType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await sodiumDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.sodium = sum.doubleValue(for: HKUnits.milligrams)
            }
        }

        // Cholesterol
        if let cholesterolType = HKQuantityType.quantityType(forIdentifier: .dietaryCholesterol) {
            let cholesterolDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: cholesterolType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await cholesterolDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.cholesterol = sum.doubleValue(for: HKUnits.milligrams)
            }
        }

        // Water
        if let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            let waterDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: waterType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await waterDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.water = sum.doubleValue(for: .liter())
            }
        }

        // Caffeine
        if let caffeineType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) {
            let caffeineDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: caffeineType, predicate: predicate),
                options: .cumulativeSum
            )
            if let result = try await caffeineDescriptor.result(for: healthStore),
               let sum = result.sumQuantity() {
                nutritionData.caffeine = sum.doubleValue(for: HKUnits.milligrams)
            }
        }

        return nutritionData
    }

    // MARK: - Mindfulness Data

    private func fetchMindfulnessData(for date: Date) async throws -> MindfulnessData {
        var mindfulnessData = MindfulnessData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Mindful Sessions
        if let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            let mindfulDescriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: mindfulType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await mindfulDescriptor.result(for: healthStore)

            if !samples.isEmpty {
                mindfulnessData.mindfulSessions = samples.count
                let totalMinutes = samples.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate) / 60
                }
                mindfulnessData.mindfulMinutes = totalMinutes
            }
        }
        
        // State of Mind (iOS 18+)
        if #available(iOS 18.0, macOS 15.0, *) {
            let stateOfMindEntries = try await fetchStateOfMindData(for: date)
            mindfulnessData.stateOfMind = stateOfMindEntries
        }

        return mindfulnessData
    }
    
    // MARK: - State of Mind Data (iOS 18+)
    
    @available(iOS 18.0, macOS 15.0, *)
    private func fetchStateOfMindData(for date: Date) async throws -> [StateOfMindEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        
        let samples = try await descriptor.result(for: healthStore)
        
        return samples.map { sample in
            // Convert HKStateOfMind.Kind to our enum
            let kind: StateOfMindEntry.StateOfMindKind = {
                switch sample.kind {
                case .momentaryEmotion:
                    return .momentaryEmotion
                case .dailyMood:
                    return .dailyMood
                @unknown default:
                    return .momentaryEmotion
                }
            }()
            
            // Convert labels to readable strings
            let labels = sample.labels.map { label -> String in
                switch label {
                case .amazed: return "Amazed"
                case .amused: return "Amused"
                case .annoyed: return "Annoyed"
                case .angry: return "Angry"
                case .anxious: return "Anxious"
                case .ashamed: return "Ashamed"
                case .brave: return "Brave"
                case .calm: return "Calm"
                case .confident: return "Confident"
                case .content: return "Content"
                case .disappointed: return "Disappointed"
                case .discouraged: return "Discouraged"
                case .disgusted: return "Disgusted"
                case .drained: return "Drained"
                case .embarrassed: return "Embarrassed"
                case .excited: return "Excited"
                case .frustrated: return "Frustrated"
                case .grateful: return "Grateful"
                case .guilty: return "Guilty"
                case .happy: return "Happy"
                case .hopeful: return "Hopeful"
                case .hopeless: return "Hopeless"
                case .indifferent: return "Indifferent"
                case .irritated: return "Irritated"
                case .jealous: return "Jealous"
                case .joyful: return "Joyful"
                case .lonely: return "Lonely"
                case .overwhelmed: return "Overwhelmed"
                case .passionate: return "Passionate"
                case .peaceful: return "Peaceful"
                case .proud: return "Proud"
                case .relieved: return "Relieved"
                case .sad: return "Sad"
                case .satisfied: return "Satisfied"
                case .scared: return "Scared"
                case .stressed: return "Stressed"
                case .surprised: return "Surprised"
                case .worried: return "Worried"
                @unknown default: return "Unknown"
                }
            }
            
            // Convert associations to readable strings
            let associations = sample.associations.map { association -> String in
                switch association {
                case .community: return "Community"
                case .currentEvents: return "Current Events"
                case .dating: return "Dating"
                case .education: return "Education"
                case .family: return "Family"
                case .fitness: return "Fitness"
                case .friends: return "Friends"
                case .health: return "Health"
                case .hobbies: return "Hobbies"
                case .identity: return "Identity"
                case .money: return "Money"
                case .partner: return "Partner"
                case .selfCare: return "Self Care"
                case .spirituality: return "Spirituality"
                case .tasks: return "Tasks"
                case .travel: return "Travel"
                case .weather: return "Weather"
                case .work: return "Work"
                @unknown default: return "Unknown"
                }
            }
            
            return StateOfMindEntry(
                timestamp: sample.startDate,
                kind: kind,
                valence: sample.valence,
                labels: labels,
                associations: associations
            )
        }
    }

    // MARK: - Mobility Data

    private func fetchMobilityData(for date: Date) async throws -> MobilityData {
        var mobilityData = MobilityData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Walking Speed
        if let walkingSpeedType = HKQuantityType.quantityType(forIdentifier: .walkingSpeed) {
            let walkingSpeedDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: walkingSpeedType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await walkingSpeedDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                mobilityData.walkingSpeed = avg.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
            }
        }

        // Walking Step Length
        if let stepLengthType = HKQuantityType.quantityType(forIdentifier: .walkingStepLength) {
            let stepLengthDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: stepLengthType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await stepLengthDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                mobilityData.walkingStepLength = avg.doubleValue(for: .meter())
            }
        }

        // Walking Double Support Percentage
        if let doubleSupportType = HKQuantityType.quantityType(forIdentifier: .walkingDoubleSupportPercentage) {
            let doubleSupportDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: doubleSupportType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await doubleSupportDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                mobilityData.walkingDoubleSupportPercentage = avg.doubleValue(for: .percent())
            }
        }

        // Walking Asymmetry Percentage
        if let asymmetryType = HKQuantityType.quantityType(forIdentifier: .walkingAsymmetryPercentage) {
            let asymmetryDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: asymmetryType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await asymmetryDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                mobilityData.walkingAsymmetryPercentage = avg.doubleValue(for: .percent())
            }
        }

        // Stair Ascent Speed
        if let ascentType = HKQuantityType.quantityType(forIdentifier: .stairAscentSpeed) {
            let ascentDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: ascentType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await ascentDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                mobilityData.stairAscentSpeed = avg.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
            }
        }

        // Stair Descent Speed
        if let descentType = HKQuantityType.quantityType(forIdentifier: .stairDescentSpeed) {
            let descentDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: descentType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await descentDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                mobilityData.stairDescentSpeed = avg.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
            }
        }

        // Six Minute Walk Test Distance
        if let sixMinType = HKQuantityType.quantityType(forIdentifier: .sixMinuteWalkTestDistance) {
            let sixMinDescriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: sixMinType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let sample = try await sixMinDescriptor.result(for: healthStore).first {
                mobilityData.sixMinuteWalkDistance = sample.quantity.doubleValue(for: .meter())
            }
        }

        return mobilityData
    }

    // MARK: - Hearing Data

    private func fetchHearingData(for date: Date) async throws -> HearingData {
        var hearingData = HearingData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Headphone Audio Exposure
        if let headphoneType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) {
            let headphoneDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: headphoneType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await headphoneDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                hearingData.headphoneAudioLevel = avg.doubleValue(for: .decibelAWeightedSoundPressureLevel())
            }
        }

        // Environmental Audio Exposure
        if let envType = HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure) {
            let envDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: envType, predicate: predicate),
                options: .discreteAverage
            )
            if let result = try await envDescriptor.result(for: healthStore),
               let avg = result.averageQuantity() {
                hearingData.environmentalSoundLevel = avg.doubleValue(for: .decibelAWeightedSoundPressureLevel())
            }
        }

        return hearingData
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
                workoutType: WorkoutType.from(hkType: workout.workoutActivityType),
                startTime: workout.startDate,
                duration: workout.duration,
                calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                distance: workout.totalDistance?.doubleValue(for: .meter())
            )
        }
    }

    // MARK: - HKWorkoutActivityType → WorkoutType Mapping

}

extension WorkoutType {
    static func from(hkType: HKWorkoutActivityType) -> WorkoutType {
        switch hkType {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .hiking: return .hiking
        case .yoga: return .yoga
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .traditionalStrengthTraining: return .traditionalStrengthTraining
        case .coreTraining: return .coreTraining
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .elliptical: return .elliptical
        case .rowing: return .rowing
        case .stairClimbing: return .stairClimbing
        case .pilates: return .pilates
        case .dance: return .dance
        case .cooldown: return .cooldown
        case .mixedCardio: return .mixedCardio
        case .socialDance: return .socialDance
        case .pickleball: return .pickleball
        case .tennis: return .tennis
        case .badminton: return .badminton
        case .tableTennis: return .tableTennis
        case .golf: return .golf
        case .soccer: return .soccer
        case .basketball: return .basketball
        case .baseball: return .baseball
        case .softball: return .softball
        case .volleyball: return .volleyball
        case .americanFootball: return .americanFootball
        case .rugby: return .rugby
        case .hockey: return .hockey
        case .lacrosse: return .lacrosse
        case .skatingSports: return .skatingSports
        case .snowSports: return .snowSports
        case .waterSports: return .waterSports
        case .martialArts: return .martialArts
        case .boxing: return .boxing
        case .kickboxing: return .kickboxing
        case .wrestling: return .wrestling
        case .climbing: return .climbing
        case .jumpRope: return .jumpRope
        case .mindAndBody: return .mindAndBody
        case .flexibility: return .flexibility
        default: return .other
        }
    }
}
