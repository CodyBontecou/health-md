import Foundation
import HealthKit
import Combine
import os.log

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    /// Abstracted health store for all data queries (tests inject FakeHealthStore).
    private let store: HealthStoreProviding
    /// Raw HealthKit store — used only for observer queries and background delivery.
    private let healthStore: HKHealthStore
    private let logger = Logger(subsystem: "com.healthexporter", category: "HealthKitManager")

    /// Active observer queries for background delivery
    private(set) var observerQueries: [HKObserverQuery] = []

    init(store: HealthStoreProviding = SystemHealthStoreAdapter()) {
        self.store = store
        self.healthStore = HKHealthStore()
    }

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
        store.isAvailable
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            authorizationStatus = "Health data not available"
            return
        }

        try await store.requestAuth(toShare: [], read: allReadTypes)
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

    /// Identifiers of types monitored for background delivery — exposed for testing.
    var monitoredTypeIdentifiers: [String] {
        monitoredTypes.map { $0.identifier }
    }

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
            do {
                let samples = try await store.queryQuantitySamples(
                    identifier: identifier, predicate: nil, ascending: true, limit: 1
                )
                if let sample = samples.first {
                    if earliestDate == nil || sample.startDate < earliestDate! {
                        earliestDate = sample.startDate
                    }
                }
            } catch {
                logger.warning("Failed to query earliest date for \(identifier.rawValue): \(error.localizedDescription)")
            }
        }

        // Also check sleep analysis
        do {
            let sleepSamples = try await store.queryCategorySamples(
                identifier: .sleepAnalysis, predicate: nil, ascending: true, limit: 1
            )
            if let sample = sleepSamples.first {
                if earliestDate == nil || sample.startDate < earliestDate! {
                    earliestDate = sample.startDate
                }
            }
        } catch {
            logger.warning("Failed to query earliest sleep date: \(error.localizedDescription)")
        }

        // Also check workouts
        do {
            let workouts = try await store.queryWorkouts(predicate: nil, ascending: true, limit: 1)
            if let workout = workouts.first {
                if earliestDate == nil || workout.startDate < earliestDate! {
                    earliestDate = workout.startDate
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

        // Get sleep samples for the night ending on the selected date
        // Sleep typically spans midnight, so we look from 6pm the day before to 12pm on the selected date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: startOfDay)!
        let sleepWindowEnd = calendar.date(byAdding: .hour, value: 12, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: sleepWindowStart, end: sleepWindowEnd)

        let samples = try await store.queryCategorySamples(identifier: .sleepAnalysis, predicate: predicate, ascending: true)

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
        if let steps = try await store.querySum(identifier: .stepCount, predicate: predicate) {
            activityData.steps = Int(steps)
        }

        // Active Calories
        activityData.activeCalories = try await store.querySum(identifier: .activeEnergyBurned, predicate: predicate)

        // Basal Energy Burned
        activityData.basalEnergyBurned = try await store.querySum(identifier: .basalEnergyBurned, predicate: predicate)

        // Exercise Minutes
        activityData.exerciseMinutes = try await store.querySum(identifier: .appleExerciseTime, predicate: predicate)

        // Stand Hours (Apple's stand ring metric: hours with at least 1 minute stood)
        let standSamples = try await store.queryCategorySamples(identifier: .appleStandHour, predicate: predicate, ascending: true)
        if !standSamples.isEmpty {
            let stoodValue = HKCategoryValueAppleStandHour.stood.rawValue
            let stoodHours = Set(
                standSamples
                    .filter { $0.value == stoodValue }
                    .compactMap { calendar.dateInterval(of: .hour, for: $0.startDate)?.start }
            )
            activityData.standHours = stoodHours.count
        }

        // Flights Climbed
        if let flights = try await store.querySum(identifier: .flightsClimbed, predicate: predicate) {
            activityData.flightsClimbed = Int(flights)
        }

        // Walking/Running Distance
        activityData.walkingRunningDistance = try await store.querySum(identifier: .distanceWalkingRunning, predicate: predicate)

        // Cycling Distance
        activityData.cyclingDistance = try await store.querySum(identifier: .distanceCycling, predicate: predicate)

        // Swimming Distance
        activityData.swimmingDistance = try await store.querySum(identifier: .distanceSwimming, predicate: predicate)

        // Swimming Strokes
        if let strokes = try await store.querySum(identifier: .swimmingStrokeCount, predicate: predicate) {
            activityData.swimmingStrokes = Int(strokes)
        }

        // Wheelchair Push Count
        if let pushes = try await store.querySum(identifier: .pushCount, predicate: predicate) {
            activityData.pushCount = Int(pushes)
        }

        // VO2 Max / Cardio Fitness — most-recent sample up to end of requested day
        let vo2Predicate = HKQuery.predicateForSamples(withStart: nil, end: endOfDay)
        activityData.vo2Max = try await store.queryMostRecent(identifier: .vo2Max, predicate: vo2Predicate)

        return activityData
    }

    // MARK: - Heart Data

    private func fetchHeartData(for date: Date) async throws -> HeartData {
        var heartData = HeartData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Resting Heart Rate — most recent sample
        heartData.restingHeartRate = try await store.queryMostRecent(identifier: .restingHeartRate, predicate: predicate)

        // Walking Heart Rate Average — most recent sample
        heartData.walkingHeartRateAverage = try await store.queryMostRecent(identifier: .walkingHeartRateAverage, predicate: predicate)

        // Heart Rate (average, min, max for the day)
        heartData.averageHeartRate = try await store.queryAverage(identifier: .heartRate, predicate: predicate)
        heartData.heartRateMin = try await store.queryMin(identifier: .heartRate, predicate: predicate)
        heartData.heartRateMax = try await store.queryMax(identifier: .heartRate, predicate: predicate)

        // HRV — daily average across all SDNN samples, matching Apple Health's display
        heartData.hrv = try await store.queryAverage(identifier: .heartRateVariabilitySDNN, predicate: predicate)

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
        vitalsData.respiratoryRateAvg = try await store.queryAverage(identifier: .respiratoryRate, predicate: predicate)
        vitalsData.respiratoryRateMin = try await store.queryMin(identifier: .respiratoryRate, predicate: predicate)
        vitalsData.respiratoryRateMax = try await store.queryMax(identifier: .respiratoryRate, predicate: predicate)

        // Blood Oxygen / SpO2 (daily aggregates)
        vitalsData.bloodOxygenAvg = try await store.queryAverage(identifier: .oxygenSaturation, predicate: predicate)
        vitalsData.bloodOxygenMin = try await store.queryMin(identifier: .oxygenSaturation, predicate: predicate)
        vitalsData.bloodOxygenMax = try await store.queryMax(identifier: .oxygenSaturation, predicate: predicate)

        // Body Temperature (daily aggregates)
        vitalsData.bodyTemperatureAvg = try await store.queryAverage(identifier: .bodyTemperature, predicate: predicate)
        vitalsData.bodyTemperatureMin = try await store.queryMin(identifier: .bodyTemperature, predicate: predicate)
        vitalsData.bodyTemperatureMax = try await store.queryMax(identifier: .bodyTemperature, predicate: predicate)

        // Blood Pressure Systolic (daily aggregates)
        vitalsData.bloodPressureSystolicAvg = try await store.queryAverage(identifier: .bloodPressureSystolic, predicate: predicate)
        vitalsData.bloodPressureSystolicMin = try await store.queryMin(identifier: .bloodPressureSystolic, predicate: predicate)
        vitalsData.bloodPressureSystolicMax = try await store.queryMax(identifier: .bloodPressureSystolic, predicate: predicate)

        // Blood Pressure Diastolic (daily aggregates)
        vitalsData.bloodPressureDiastolicAvg = try await store.queryAverage(identifier: .bloodPressureDiastolic, predicate: predicate)
        vitalsData.bloodPressureDiastolicMin = try await store.queryMin(identifier: .bloodPressureDiastolic, predicate: predicate)
        vitalsData.bloodPressureDiastolicMax = try await store.queryMax(identifier: .bloodPressureDiastolic, predicate: predicate)

        // Blood Glucose (daily aggregates)
        vitalsData.bloodGlucoseAvg = try await store.queryAverage(identifier: .bloodGlucose, predicate: predicate)
        vitalsData.bloodGlucoseMin = try await store.queryMin(identifier: .bloodGlucose, predicate: predicate)
        vitalsData.bloodGlucoseMax = try await store.queryMax(identifier: .bloodGlucose, predicate: predicate)

        return vitalsData
    }

    // MARK: - Body Data

    private func fetchBodyData(for date: Date) async throws -> BodyData {
        var bodyData = BodyData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        bodyData.weight = try await store.queryMostRecent(identifier: .bodyMass, predicate: predicate)
        bodyData.height = try await store.queryMostRecent(identifier: .height, predicate: predicate)
        bodyData.bmi = try await store.queryMostRecent(identifier: .bodyMassIndex, predicate: predicate)
        bodyData.bodyFatPercentage = try await store.queryMostRecent(identifier: .bodyFatPercentage, predicate: predicate)
        bodyData.leanBodyMass = try await store.queryMostRecent(identifier: .leanBodyMass, predicate: predicate)
        bodyData.waistCircumference = try await store.queryMostRecent(identifier: .waistCircumference, predicate: predicate)

        return bodyData
    }

    // MARK: - Nutrition Data

    private func fetchNutritionData(for date: Date) async throws -> NutritionData {
        var nutritionData = NutritionData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        nutritionData.dietaryEnergy = try await store.querySum(identifier: .dietaryEnergyConsumed, predicate: predicate)
        nutritionData.protein = try await store.querySum(identifier: .dietaryProtein, predicate: predicate)
        nutritionData.carbohydrates = try await store.querySum(identifier: .dietaryCarbohydrates, predicate: predicate)
        nutritionData.fat = try await store.querySum(identifier: .dietaryFatTotal, predicate: predicate)
        nutritionData.saturatedFat = try await store.querySum(identifier: .dietaryFatSaturated, predicate: predicate)
        nutritionData.fiber = try await store.querySum(identifier: .dietaryFiber, predicate: predicate)
        nutritionData.sugar = try await store.querySum(identifier: .dietarySugar, predicate: predicate)
        nutritionData.sodium = try await store.querySum(identifier: .dietarySodium, predicate: predicate)
        nutritionData.cholesterol = try await store.querySum(identifier: .dietaryCholesterol, predicate: predicate)
        nutritionData.water = try await store.querySum(identifier: .dietaryWater, predicate: predicate)
        nutritionData.caffeine = try await store.querySum(identifier: .dietaryCaffeine, predicate: predicate)

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
        let samples = try await store.queryCategorySamples(identifier: .mindfulSession, predicate: predicate, ascending: true)
        if !samples.isEmpty {
            mindfulnessData.mindfulSessions = samples.count
            let totalMinutes = samples.reduce(0.0) { total, sample in
                total + sample.endDate.timeIntervalSince(sample.startDate) / 60
            }
            mindfulnessData.mindfulMinutes = totalMinutes
        }
        
        // State of Mind — isolated so a failure here doesn't
        // destroy already-fetched mindful session data.
        // The protocol adapter returns empty on OS versions < iOS 18 / macOS 15.
        do {
            let stateOfMindEntries = try await fetchStateOfMindData(for: date)
            mindfulnessData.stateOfMind = stateOfMindEntries
        } catch {
            logger.warning("State of Mind fetch failed: \(error.localizedDescription)")
        }

        return mindfulnessData
    }
    
    // MARK: - State of Mind Data

    private func fetchStateOfMindData(for date: Date) async throws -> [StateOfMindEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        let samples = try await store.queryStateOfMind(predicate: predicate)

        return samples.map { sample in
            let kind = StateOfMindEntry.StateOfMindKind(rawValue: sample.kind) ?? .momentaryEmotion
            return StateOfMindEntry(
                timestamp: sample.startDate,
                kind: kind,
                valence: sample.valence,
                labels: sample.labels,
                associations: sample.associations
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

        mobilityData.walkingSpeed = try await store.queryAverage(identifier: .walkingSpeed, predicate: predicate)
        mobilityData.walkingStepLength = try await store.queryAverage(identifier: .walkingStepLength, predicate: predicate)
        mobilityData.walkingDoubleSupportPercentage = try await store.queryAverage(identifier: .walkingDoubleSupportPercentage, predicate: predicate)
        mobilityData.walkingAsymmetryPercentage = try await store.queryAverage(identifier: .walkingAsymmetryPercentage, predicate: predicate)
        mobilityData.stairAscentSpeed = try await store.queryAverage(identifier: .stairAscentSpeed, predicate: predicate)
        mobilityData.stairDescentSpeed = try await store.queryAverage(identifier: .stairDescentSpeed, predicate: predicate)
        mobilityData.sixMinuteWalkDistance = try await store.queryMostRecent(identifier: .sixMinuteWalkTestDistance, predicate: predicate)

        return mobilityData
    }

    // MARK: - Hearing Data

    private func fetchHearingData(for date: Date) async throws -> HearingData {
        var hearingData = HearingData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        hearingData.headphoneAudioLevel = try await store.queryAverage(identifier: .headphoneAudioExposure, predicate: predicate)
        hearingData.environmentalSoundLevel = try await store.queryAverage(identifier: .environmentalAudioExposure, predicate: predicate)

        return hearingData
    }

    // MARK: - Workouts

    private func fetchWorkouts(for date: Date) async throws -> [WorkoutData] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        let workouts = try await store.queryWorkouts(predicate: predicate, ascending: true, limit: nil)

        return workouts.map { workout in
            let workoutType: WorkoutType
            if let hkType = HKWorkoutActivityType(rawValue: workout.activityType) {
                workoutType = WorkoutType.from(hkType: hkType)
            } else {
                workoutType = .other
            }
            return WorkoutData(
                workoutType: workoutType,
                startTime: workout.startDate,
                duration: workout.duration,
                calories: workout.totalEnergyBurned,
                distance: workout.totalDistance
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
