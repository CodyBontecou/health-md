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
    private let userDefaults: UserDefaults
    private let healthAuthorizationRequestedKey = "healthKit.authorizationRequested"
    private let authorizationStateMigrationKey = "healthKit.authorizationStateMigrationCompleted"
    private let legacyOnboardingCompletedKey = "hasCompletedOnboarding"
    private let medicationAuthorizationRequestedKey = "healthKit.medicationAuthorizationRequested"
    private let visionAuthorizationRequestedKey = "healthKit.visionAuthorizationRequested"

    /// Active observer queries for background delivery
    private(set) var observerQueries: [HKObserverQuery] = []

    init(store: HealthStoreProviding = SystemHealthStoreAdapter(), userDefaults: UserDefaults = .standard) {
        self.store = store
        self.healthStore = HKHealthStore()
        self.userDefaults = userDefaults
        let medicationRequested = userDefaults.bool(forKey: medicationAuthorizationRequestedKey)
        self.isMedicationAuthorizationRequested = medicationRequested
        self.medicationAuthorizationStatus = medicationRequested ? "Medication access selected" : "Not requested"
        let visionRequested = userDefaults.bool(forKey: visionAuthorizationRequestedKey)
        self.isVisionAuthorizationRequested = visionRequested
        self.visionAuthorizationStatus = visionRequested ? "Vision prescription access selected" : "Not requested"

        restoreSavedAuthorizationState()
    }

    /// Callback triggered when background delivery receives new data
    var onBackgroundDelivery: (() -> Void)?

    @Published var isAuthorized = false
    @Published var authorizationStatus: String = "Not Connected"
    @Published private(set) var isMedicationAuthorizationRequested: Bool
    @Published private(set) var medicationAuthorizationStatus: String
    @Published private(set) var isVisionAuthorizationRequested: Bool
    @Published private(set) var visionAuthorizationStatus: String

    // MARK: - Error Types

    enum HealthKitError: LocalizedError {
        case dataNotAvailable
        case notAuthorized
        case dataProtectedWhileLocked
        case medicationAuthorizationUnsupported
        case visionAuthorizationUnsupported

        var errorDescription: String? {
            switch self {
            case .dataNotAvailable:
                return "Health data is not available on this device"
            case .notAuthorized:
                return "Health data access not authorized. Please grant permissions in Settings."
            case .dataProtectedWhileLocked:
                return "Health data is unavailable while the device is locked. Please unlock your device."
            case .medicationAuthorizationUnsupported:
                return "Medication export requires iOS 26 or later."
            case .visionAuthorizationUnsupported:
                return "Vision prescription export requires a runtime that supports per-object authorization."
            }
        }
    }

    // MARK: - Health Data Types

    /// Compatibility floor for HealthKit types requested by releases before the
    /// catalog became authoritative. Debug builds verify the catalog never regresses it.
    private var legacyAuthorizationFloor: Set<HKObjectType> {
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
        if let wheelchair = HKQuantityType.quantityType(forIdentifier: .distanceWheelchair) {
            types.insert(wheelchair)
        }
        if let snowSports = HKQuantityType.quantityType(forIdentifier: .distanceDownhillSnowSports) {
            types.insert(snowSports)
        }
        if let moveTime = HKQuantityType.quantityType(forIdentifier: .appleMoveTime) {
            types.insert(moveTime)
        }
        if let physicalEffort = HKQuantityType.quantityType(forIdentifier: .physicalEffort) {
            types.insert(physicalEffort)
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
        if let hrRecovery = HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute) {
            types.insert(hrRecovery)
        }
        if let afib = HKQuantityType.quantityType(forIdentifier: .atrialFibrillationBurden) {
            types.insert(afib)
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
        if let bloodPressure = HKObjectType.correlationType(forIdentifier: .bloodPressure) {
            types.insert(bloodPressure)
        }
        if let bloodGlucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            types.insert(bloodGlucose)
        }
        if let basalTemp = HKQuantityType.quantityType(forIdentifier: .basalBodyTemperature) {
            types.insert(basalTemp)
        }
        if let wristTemp = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            types.insert(wristTemp)
        }
        if let eda = HKQuantityType.quantityType(forIdentifier: .electrodermalActivity) {
            types.insert(eda)
        }
        if let fvc = HKQuantityType.quantityType(forIdentifier: .forcedVitalCapacity) {
            types.insert(fvc)
        }
        if let fev1 = HKQuantityType.quantityType(forIdentifier: .forcedExpiratoryVolume1) {
            types.insert(fev1)
        }
        if let pef = HKQuantityType.quantityType(forIdentifier: .peakExpiratoryFlowRate) {
            types.insert(pef)
        }
        if let inhaler = HKQuantityType.quantityType(forIdentifier: .inhalerUsage) {
            types.insert(inhaler)
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
        if let monoFat = HKQuantityType.quantityType(forIdentifier: .dietaryFatMonounsaturated) {
            types.insert(monoFat)
        }
        if let polyFat = HKQuantityType.quantityType(forIdentifier: .dietaryFatPolyunsaturated) {
            types.insert(polyFat)
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
        if let steadiness = HKQuantityType.quantityType(forIdentifier: .appleWalkingSteadiness) {
            types.insert(steadiness)
        }
        if let runSpeed = HKQuantityType.quantityType(forIdentifier: .runningSpeed) {
            types.insert(runSpeed)
        }
        if let runStride = HKQuantityType.quantityType(forIdentifier: .runningStrideLength) {
            types.insert(runStride)
        }
        if let runGC = HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime) {
            types.insert(runGC)
        }
        if let runVO = HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation) {
            types.insert(runVO)
        }
        if let runPower = HKQuantityType.quantityType(forIdentifier: .runningPower) {
            types.insert(runPower)
        }

        // Hearing
        if let headphoneAudio = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) {
            types.insert(headphoneAudio)
        }
        if let environmentalSound = HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure) {
            types.insert(environmentalSound)
        }

        // Reproductive Health
        if let menstrualFlow = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) {
            types.insert(menstrualFlow)
        }
        if let sexualActivity = HKCategoryType.categoryType(forIdentifier: .sexualActivity) {
            types.insert(sexualActivity)
        }
        if let ovulationTest = HKCategoryType.categoryType(forIdentifier: .ovulationTestResult) {
            types.insert(ovulationTest)
        }
        if let cervicalMucus = HKCategoryType.categoryType(forIdentifier: .cervicalMucusQuality) {
            types.insert(cervicalMucus)
        }
        if let intermenstrualBleeding = HKCategoryType.categoryType(forIdentifier: .intermenstrualBleeding) {
            types.insert(intermenstrualBleeding)
        }

        // Cycling Performance
        for id: HKQuantityTypeIdentifier in [.cyclingSpeed, .cyclingPower, .cyclingCadence, .cyclingFunctionalThresholdPower] {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }

        // Vitamins
        for id: HKQuantityTypeIdentifier in [
            .dietaryVitaminA, .dietaryVitaminB6, .dietaryVitaminB12, .dietaryVitaminC,
            .dietaryVitaminD, .dietaryVitaminE, .dietaryVitaminK,
            .dietaryThiamin, .dietaryRiboflavin, .dietaryNiacin,
            .dietaryFolate, .dietaryBiotin, .dietaryPantothenicAcid
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }

        // Minerals
        for id: HKQuantityTypeIdentifier in [
            .dietaryCalcium, .dietaryIron, .dietaryPotassium, .dietaryMagnesium,
            .dietaryPhosphorus, .dietaryZinc, .dietarySelenium, .dietaryCopper,
            .dietaryManganese, .dietaryChromium, .dietaryMolybdenum, .dietaryChloride,
            .dietaryIodine
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }

        // Symptoms
        for id: HKCategoryTypeIdentifier in [
            .headache, .fatigue, .nausea, .dizziness, .moodChanges, .sleepChanges,
            .appetiteChanges, .hotFlashes, .chills, .fever, .lowerBackPain, .bloating,
            .constipation, .diarrhea, .heartburn, .coughing, .soreThroat, .runnyNose,
            .shortnessOfBreath, .chestTightnessOrPain, .skippedHeartbeat,
            .rapidPoundingOrFlutteringHeartbeat, .acne, .drySkin, .hairLoss,
            .memoryLapse, .nightSweats, .vomiting, .abdominalCramps, .breastPain,
            .pelvicPain, .generalizedBodyAche, .fainting, .lossOfSmell, .lossOfTaste,
            .wheezing, .sinusCongestion, .bladderIncontinence, .vaginalDryness
        ] {
            if let type = HKCategoryType.categoryType(forIdentifier: id) {
                types.insert(type)
            }
        }

        // Medication dose events are intentionally excluded from the standard
        // HealthKit authorization request. Medication APIs use HealthKit's
        // per-object authorization flow via requestMedicationAuthorizationIfNeeded().

        // Other
        for id: HKQuantityTypeIdentifier in [
            .uvExposure, .timeInDaylight, .numberOfTimesFallen, .bloodAlcoholContent,
            .numberOfAlcoholicBeverages, .insulinDelivery, .waterTemperature, .underwaterDepth
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        for id: HKCategoryTypeIdentifier in [.toothbrushingEvent, .handwashingEvent] {
            if let type = HKCategoryType.categoryType(forIdentifier: id) {
                types.insert(type)
            }
        }

        // Workouts
        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.workoutRoute())

        return types
    }

    /// Authorization is resolved from the same reviewed catalog that plans archive
    /// queries. The resolver applies deployment guards and drops unsupported nil types.
    private var allReadTypes: Set<HKObjectType> {
        let resolvedCatalogTypes = HealthKitRecordCatalog.resolvedAuthorizationObjectTypes()
        let catalogTypes = store.supportsHealthRecords ? resolvedCatalogTypes : Set(
            resolvedCatalogTypes.filter {
                !HealthKitRecordCatalog.clinicalTypeIdentifiers.contains($0.identifier)
            }
        )
        #if DEBUG
        let missingLegacyTypes = legacyAuthorizationFloor.subtracting(catalogTypes)
        assert(
            missingLegacyTypes.isEmpty,
            "Catalog authorization regressed legacy types: \(missingLegacyTypes.map(\.identifier).sorted())"
        )
        #endif
        return catalogTypes
    }

    // MARK: - Authorization

    var isHealthDataAvailable: Bool {
        store.isAvailable
    }

    private func restoreSavedAuthorizationState() {
        let authorizationPreviouslyRequested = userDefaults.bool(forKey: healthAuthorizationRequestedKey)
        let shouldMigrateCompletedOnboarding = !userDefaults.bool(forKey: authorizationStateMigrationKey)
            && userDefaults.bool(forKey: legacyOnboardingCompletedKey)

        if !userDefaults.bool(forKey: authorizationStateMigrationKey) {
            userDefaults.set(true, forKey: authorizationStateMigrationKey)
        }

        guard isHealthDataAvailable,
              authorizationPreviouslyRequested || shouldMigrateCompletedOnboarding else {
            return
        }

        if shouldMigrateCompletedOnboarding {
            userDefaults.set(true, forKey: healthAuthorizationRequestedKey)
        }
        isAuthorized = true
        authorizationStatus = "Connected"
    }

    private func markAuthorizationRequested() {
        userDefaults.set(true, forKey: healthAuthorizationRequestedKey)
        userDefaults.set(true, forKey: authorizationStateMigrationKey)
        isAuthorized = true
        authorizationStatus = "Connected"
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            authorizationStatus = "Health data not available"
            return
        }

        // On iOS 26, calling requestAuthorization when the user has already
        // made a decision shows a blank, undismissable sheet. Check first and
        // skip the system dialog if authorization is already settled.
        let authRequestStatus = try await store.authorizationRequestStatus(
            toShare: [],
            read: allReadTypes
        )
        if authRequestStatus == .unnecessary {
            markAuthorizationRequested()
            return
        }

        try await store.requestAuth(toShare: [], read: allReadTypes)
        markAuthorizationRequested()
    }

    /// Whether this runtime supports ordinary Health Records authorization.
    var areClinicalHealthRecordsSupported: Bool {
        isHealthDataAvailable && store.supportsHealthRecords
    }

    /// Whether this runtime can show Apple's per-vision-prescription selector.
    var isVisionAuthorizationSupported: Bool {
        isHealthDataAvailable && store.supportsVisionPrescriptionAuthorization
    }

    /// Shows Apple's per-object selector only from an explicit user action.
    func requestVisionPrescriptionAuthorization(force: Bool = true) async throws {
        guard isHealthDataAvailable else {
            visionAuthorizationStatus = "Health data not available"
            throw HealthKitError.dataNotAvailable
        }
        guard isVisionAuthorizationSupported else {
            visionAuthorizationStatus = "Vision prescription access unavailable"
            throw HealthKitError.visionAuthorizationUnsupported
        }
        guard force || !isVisionAuthorizationRequested else { return }

        visionAuthorizationStatus = "Requesting vision prescription access"
        do {
            try await store.requestVisionPrescriptionAuthorization(predicate: nil)
            userDefaults.set(true, forKey: visionAuthorizationRequestedKey)
            isVisionAuthorizationRequested = true
            visionAuthorizationStatus = "Vision prescription access selected"
        } catch {
            visionAuthorizationStatus = "Vision prescription access failed"
            throw error
        }
    }

    /// Whether this runtime can show Apple's per-medication authorization selector.
    var isMedicationAuthorizationSupported: Bool {
        isHealthDataAvailable && store.supportsMedicationAuthorization
    }

    /// HealthKit medications use per-object authorization. Unlike steps, sleep,
    /// heart rate, etc., medications are not requested in the standard onboarding
    /// permission sheet. Call this from an explicit user action when they enable
    /// medication export so Apple can show the per-medication selector.
    func requestMedicationAuthorization(force: Bool = true) async throws {
        guard isHealthDataAvailable else {
            medicationAuthorizationStatus = "Health data not available"
            throw HealthKitError.dataNotAvailable
        }
        guard isMedicationAuthorizationSupported else {
            medicationAuthorizationStatus = "Requires iOS 26 or later"
            throw HealthKitError.medicationAuthorizationUnsupported
        }
        guard force || !isMedicationAuthorizationRequested else { return }

        medicationAuthorizationStatus = "Requesting medication access"
        do {
            try await store.requestMedicationAuthorization()
            userDefaults.set(true, forKey: medicationAuthorizationRequestedKey)
            isMedicationAuthorizationRequested = true
            medicationAuthorizationStatus = "Medication access selected"
        } catch {
            medicationAuthorizationStatus = "Medication access failed"
            throw error
        }
    }

    func requestMedicationAuthorizationIfNeeded(force: Bool = false) async throws {
        try await requestMedicationAuthorization(force: force)
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

        // Medication dose events use per-object authorization and can trigger
        // HealthKit authorization exceptions when included in standard observer
        // setup before that flow has completed.

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

    private struct HealthDataFetchScope: Sendable {
        private let enabledMetricIDs: Set<String>?

        init(metricSelection: MetricSelectionState?) {
            self.enabledMetricIDs = metricSelection?.enabledMetrics
        }

        private func includesCategory(_ category: HealthMetricCategory) -> Bool {
            guard let enabledMetricIDs else { return true }
            return HealthMetrics.byCategory[category]?.contains {
                enabledMetricIDs.contains($0.id) && !$0.isArchiveOnly
            } ?? false
        }

        func includesMetric(_ metricID: String) -> Bool {
            enabledMetricIDs?.contains(metricID) ?? true
        }

        var sleep: Bool { includesCategory(.sleep) }
        var activity: Bool { includesCategory(.activity) || includesMetric("cycling_distance") }
        var heart: Bool { includesCategory(.heart) }
        var respiratory: Bool { includesCategory(.respiratory) }
        var vitals: Bool { includesCategory(.vitals) }
        var body: Bool { includesCategory(.bodyMeasurements) }
        var nutrition: Bool { includesCategory(.nutrition) }
        var mindfulness: Bool { includesCategory(.mindfulness) }
        var mobility: Bool { includesCategory(.mobility) }
        var hearing: Bool { includesCategory(.hearing) }
        var reproductiveHealth: Bool { includesCategory(.reproductiveHealth) }
        var cyclingPerformance: Bool {
            includesMetric("cycling_speed") || includesMetric("cycling_power") ||
            includesMetric("cycling_cadence") || includesMetric("cycling_ftp")
        }
        var vitamins: Bool { includesCategory(.vitamins) }
        var minerals: Bool { includesCategory(.minerals) }
        var symptoms: Bool { includesCategory(.symptoms) }
        var medications: Bool { includesCategory(.medications) }
        var other: Bool { includesCategory(.other) }
        var workouts: Bool { includesCategory(.workouts) }
    }

    private struct VitalsFetchResult {
        var data: VitalsData = VitalsData()
        var partialFailures: [ExportPartialFailure] = []
    }

    private struct HealthKitRecordArchiveFetchResult {
        let archive: HealthKitRecordArchive
        let partialFailures: [ExportPartialFailure]
    }

    /// Fetches HealthKit data for the requested date without presenting additional authorization UI.
    func fetchHealthData(
        for date: Date,
        includeGranularData: Bool = false,
        metricSelection: MetricSelectionState? = nil
    ) async throws -> HealthData {
        // Capture the calendar timezone before any asynchronous fetch begins so
        // the record keeps the same day/display context when transferred to a
        // Mac or serialized later in a different timezone.
        let timeContext = ExportTimeContext.captured()
        var healthData = HealthData(date: date, timeContext: timeContext)
        let fetchScope = HealthDataFetchScope(metricSelection: metricSelection)

        @Sendable
        func fetchIfEnabled<T>(
            _ isEnabled: Bool,
            fallback defaultValue: T,
            operation: @Sendable () async throws -> T
        ) async throws -> T {
            guard isEnabled else { return defaultValue }
            return try await operation()
        }

        // Check authorization before attempting to query
        // This is especially important in background contexts
        try checkAuthorizationForBackgroundAccess()

        // Kick off selected categories concurrently. When export settings are
        // supplied, avoid touching unselected HealthKit types entirely; this
        // prevents one inaccessible/unselected type from blocking the requested
        // metric(s), and keeps preview/export aligned with the metric picker.
        async let sleepTask = fetchIfEnabled(fetchScope.sleep, fallback: SleepData()) {
            try await fetchSleepData(for: date, includeGranularData: includeGranularData)
        }
        async let activityTask = fetchIfEnabled(fetchScope.activity, fallback: ActivityData()) {
            try await fetchActivityData(for: date)
        }
        async let heartTask = fetchIfEnabled(fetchScope.heart, fallback: HeartData()) {
            try await fetchHeartData(for: date, includeGranularData: includeGranularData)
        }
        let shouldFetchVitals = fetchScope.respiratory || fetchScope.vitals
        async let vitalsTask = fetchIfEnabled(shouldFetchVitals, fallback: VitalsFetchResult()) {
            try await fetchVitalsData(
                for: date,
                includeGranularData: includeGranularData,
                fetchScope: fetchScope
            )
        }
        async let bodyTask = fetchIfEnabled(fetchScope.body, fallback: BodyData()) {
            try await fetchBodyData(for: date)
        }
        async let nutritionTask = fetchIfEnabled(fetchScope.nutrition, fallback: NutritionData()) {
            try await fetchNutritionData(for: date)
        }
        async let mindfulTask = fetchIfEnabled(fetchScope.mindfulness, fallback: MindfulnessData()) {
            try await fetchMindfulnessData(for: date)
        }
        async let mobilityTask = fetchIfEnabled(fetchScope.mobility, fallback: MobilityData()) {
            try await fetchMobilityData(for: date)
        }
        async let hearingTask = fetchIfEnabled(fetchScope.hearing, fallback: HearingData()) {
            try await fetchHearingData(for: date)
        }
        async let reproductiveTask = fetchIfEnabled(fetchScope.reproductiveHealth, fallback: ReproductiveHealthData()) {
            try await fetchReproductiveHealthData(for: date)
        }
        async let cyclingPerfTask = fetchIfEnabled(fetchScope.cyclingPerformance, fallback: CyclingPerformanceData()) {
            try await fetchCyclingPerformanceData(for: date)
        }
        async let vitaminsTask = fetchIfEnabled(fetchScope.vitamins, fallback: VitaminsData()) {
            try await fetchVitaminsData(for: date)
        }
        async let mineralsTask = fetchIfEnabled(fetchScope.minerals, fallback: MineralsData()) {
            try await fetchMineralsData(for: date)
        }
        async let symptomsTask = fetchIfEnabled(fetchScope.symptoms, fallback: SymptomsData()) {
            try await fetchSymptomsData(for: date)
        }
        async let medicationsTask = fetchIfEnabled(fetchScope.medications, fallback: MedicationsData()) {
            try await fetchMedicationsData(for: date)
        }
        async let otherTask = fetchIfEnabled(fetchScope.other, fallback: OtherHealthData()) {
            try await fetchOtherData(for: date)
        }
        async let workoutsTask = fetchIfEnabled(fetchScope.workouts, fallback: [WorkoutData]()) {
            try await fetchWorkouts(for: date)
        }

        // Collect results with per-category isolation.
        //
        // Design intent:
        //  • Device-locked / auth errors are re-thrown so the caller can show a
        //    clear "unlock your device" message.
        //  • Every other error is logged, recorded as a partial failure, and
        //    swallowed — one bad metric never prevents the remaining categories
        //    from exporting.
        //
        // This is the architectural lesson from the v1.7.5 crash: a single
        // invalid HKUnit string in `fetchActivityData` silently aborted the
        // entire export for all users who had VO₂ Max data.

        func isDeviceLocked(_ error: Error) -> Bool {
            let nsError = error as NSError
            if nsError.domain == HKError.errorDomain,
               nsError.code == HKError.Code.errorDatabaseInaccessible.rawValue {
                return true
            }

            // `errorDatabaseInaccessible` is the canonical HealthKit signal for
            // protected data while the device is locked. Some bridged errors only
            // carry localized text, so keep a narrow text fallback without treating
            // generic authorization failures as lock failures.
            let msg = error.localizedDescription.lowercased()
            return msg.contains("database inaccessible")
                || (msg.contains("protected") && msg.contains("locked"))
                || (msg.contains("protected data") && msg.contains("unavailable"))
        }

        let dayRangeDescription = Self.dayRangeDescription(for: date)

        func recordPartialFailure(_ dataType: String, error: Error) {
            let failure = ExportPartialFailure(
                date: date,
                dataType: dataType,
                dateRangeDescription: dayRangeDescription,
                errorDescription: error.localizedDescription
            )
            healthData.partialFailures.append(failure)
            logger.warning("HealthKit export fetch failed for \(dataType, privacy: .public) dateRange=\(dayRangeDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        do { healthData.sleep       = try await sleepTask     } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("sleep", error: error)
        }
        do { healthData.activity    = try await activityTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("activity", error: error)
        }
        do { healthData.heart       = try await heartTask     } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("heart", error: error)
        }
        do {
            let vitalsResult = try await vitalsTask
            healthData.vitals = vitalsResult.data
            healthData.partialFailures.append(contentsOf: vitalsResult.partialFailures)
        } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("vitals", error: error)
        }
        do { healthData.body        = try await bodyTask      } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("body", error: error)
        }
        do { healthData.nutrition   = try await nutritionTask } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("nutrition", error: error)
        }
        do { healthData.mindfulness = try await mindfulTask   } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("mindfulness", error: error)
        }
        do { healthData.mobility    = try await mobilityTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("mobility", error: error)
        }
        do { healthData.hearing     = try await hearingTask   } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("hearing", error: error)
        }
        do { healthData.reproductiveHealth = try await reproductiveTask } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("reproductive health", error: error)
        }
        do { healthData.cyclingPerformance = try await cyclingPerfTask } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("cycling performance", error: error)
        }
        do { healthData.vitamins   = try await vitaminsTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("vitamins", error: error)
        }
        do { healthData.minerals   = try await mineralsTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("minerals", error: error)
        }
        do { healthData.symptoms   = try await symptomsTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("symptoms", error: error)
        }
        do { healthData.medications = try await medicationsTask } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("medications", error: error)
        }
        do { healthData.other      = try await otherTask     } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("other health data", error: error)
        }
        do { healthData.workouts    = try await workoutsTask  } catch {
            guard !isDeviceLocked(error) else { throw HealthKitError.dataProtectedWhileLocked }
            recordPartialFailure("workouts", error: error)
        }

        if includeGranularData {
            let archiveResult = await fetchHealthKitRecordArchive(
                for: date,
                timeContext: timeContext,
                metricSelection: metricSelection
            )
            healthData.healthKitRecordArchive = archiveResult.archive
            healthData.healthKitRecordCaptureStatus = archiveResult.archive.captureStatus
            for failure in archiveResult.partialFailures where !healthData.partialFailures.contains(failure) {
                healthData.partialFailures.append(failure)
            }
        } else {
            healthData.healthKitRecordArchive = nil
            healthData.healthKitRecordCaptureStatus = .notRequested
        }

        if let metricSelection {
            return healthData.filtered(by: metricSelection)
        }
        return healthData
    }

    /// Captures every generic quantity/category object in the exact metric relationship
    /// closure. Summary queries remain separate so their established calculations and
    /// compatibility time-series arrays are unchanged.
    private func fetchHealthKitRecordArchive(
        for date: Date,
        timeContext: ExportTimeContext,
        metricSelection: MetricSelectionState?
    ) async -> HealthKitRecordArchiveFetchResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeContext.calendarTimeZone
        let intervalStart = calendar.startOfDay(for: date)
        let intervalEnd = calendar.date(byAdding: .day, value: 1, to: intervalStart)
            ?? intervalStart.addingTimeInterval(86_400)
        let interval = HealthKitQueryInterval(
            startDate: intervalStart,
            endDate: intervalEnd,
            calendarTimeZoneIdentifier: timeContext.calendarTimeZoneIdentifier
        )
        let ownership = HealthKitDailyOwnershipMetadata(
            ownerDate: HealthKitDailyOwnershipMetadata.ownerDate(
                for: intervalStart,
                calendarTimeZoneIdentifier: timeContext.calendarTimeZoneIdentifier
            ),
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            calendarTimeZoneIdentifier: timeContext.calendarTimeZoneIdentifier
        )
        let predicate = HKQuery.predicateForSamples(
            withStart: intervalStart,
            end: intervalEnd,
            options: .strictStartDate
        )
        let selectedMetricIDs = archiveMetricIDs(for: metricSelection)
        let requestedPlan = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: selectedMetricIDs
        )
        var preflightQueryResults: [HealthKitQueryResult] = []
        var plan: [HealthKitRecordSelectionPlanEntry] = []
        for entry in requestedPlan {
            let rejection: (HealthKitQueryResultStatus, String)?
            if !HealthKitRecordCatalog.isRuntimeAvailable(entry.descriptor) {
                rejection = (.unsupported, "The selected HealthKit type is unavailable on this OS version.")
            } else {
                switch entry.recordKind {
                case .clinical where !store.supportsHealthRecords:
                    rejection = (.unsupported, "HKHealthStore.supportsHealthRecords() returned false on this device or account.")
                case .document where !store.supportsCDADocuments:
                    rejection = (.unsupported, "Public per-document CDA queries are unavailable on this runtime.")
                case .verifiableClinicalRecord where !store.supportsVerifiableClinicalRecords:
                    rejection = (.unsupported, "Verifiable clinical record user-selection queries are unavailable on this runtime.")
                case .visionPrescription where !store.supportsVisionPrescriptionAuthorization:
                    rejection = (.unsupported, "Vision prescription per-object authorization is unavailable on this runtime.")
                case .visionPrescription where !isVisionAuthorizationRequested:
                    rejection = (.skipped, "Vision prescription capture was skipped because the user has not opened Apple's per-object selector from Health.md.")
                default:
                    rejection = nil
                }
            }

            if let (status, description) = rejection {
                preflightQueryResults.append(HealthKitQueryResult(
                    identifier: entry.objectTypeIdentifier,
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: "specializedCapabilityPreflight",
                    metricIDs: entry.metricIDs,
                    metricAttribution: entry.attribution,
                    interval: interval,
                    status: status,
                    recordCount: 0,
                    statusDescription: description
                ))
            } else {
                plan.append(entry)
            }
        }

        var recordsByUUID: [UUID: HealthKitRecord] = [:]
        var externalRecordsByIdentifier: [String: HealthKitExternalRecord] = [:]
        var medicationInventoryRecords: [HealthKitMedicationInventoryRecord] = []
        var queryResults: [HealthKitQueryResult] = preflightQueryResults
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []
        var partialFailures: [ExportPartialFailure] = []

        func isOwnedBySelectedDay(_ record: HealthKitRecord) -> Bool {
            record.startDate >= intervalStart && record.startDate < intervalEnd
        }

        func appendRecords(
            _ records: [HealthKitRecord],
            attribution: HealthKitMetricAttribution,
            includeRelationshipComponents: Bool = false
        ) {
            for record in records where includeRelationshipComponents || isOwnedBySelectedDay(record) {
                let attributedRecord = record.attributed(attribution)
                if let existing = recordsByUUID[attributedRecord.originalUUID] {
                    recordsByUUID[attributedRecord.originalUUID] = existing.mergingRepeatedView(attributedRecord)
                } else {
                    recordsByUUID[attributedRecord.originalUUID] = attributedRecord
                }
            }
        }

        func appendAttributedRecords(
            _ records: [HealthKitRecord],
            includeRelationshipComponents: Bool = false
        ) {
            for record in records where isOwnedBySelectedDay(record) ||
                (includeRelationshipComponents && record.includedBecause == .relationshipDependency) {
                if let existing = recordsByUUID[record.originalUUID] {
                    recordsByUUID[record.originalUUID] = existing.mergingRepeatedView(record)
                } else {
                    recordsByUUID[record.originalUUID] = record
                }
            }
        }

        func appendExternalRecords(_ records: [HealthKitExternalRecord]) {
            for record in records {
                if let existing = externalRecordsByIdentifier[record.externalIdentifier] {
                    externalRecordsByIdentifier[record.externalIdentifier] = existing.mergingRepeatedView(record)
                } else {
                    externalRecordsByIdentifier[record.externalIdentifier] = record
                }
            }
        }

        func successfulResult(
            for entry: HealthKitRecordSelectionPlanEntry,
            operation: String,
            recordCount: Int
        ) -> HealthKitQueryResult {
            HealthKitQueryResult(
                identifier: entry.objectTypeIdentifier,
                objectTypeIdentifier: entry.objectTypeIdentifier,
                operation: operation,
                metricIDs: entry.metricIDs,
                metricAttribution: entry.attribution,
                interval: interval,
                status: .success,
                recordCount: recordCount
            )
        }

        func recordFailure(
            for entry: HealthKitRecordSelectionPlanEntry,
            operation: String,
            error: Error
        ) {
            let nsError = error as NSError
            queryResults.append(HealthKitQueryResult(
                identifier: entry.objectTypeIdentifier,
                objectTypeIdentifier: entry.objectTypeIdentifier,
                operation: operation,
                metricIDs: entry.metricIDs,
                metricAttribution: entry.attribution,
                interval: interval,
                status: .failure,
                recordCount: 0,
                error: HealthKitQueryError(
                    error: nsError,
                    isRecoverable: Self.isRecoverableRecordQueryError(nsError)
                )
            ))

            let failure = ExportPartialFailure(
                date: date,
                dataType: "HealthKit record \(entry.objectTypeIdentifier)",
                dateRangeDescription: "\(ownership.ownerDate) [\(intervalStart)..<\(intervalEnd))",
                errorDescription: nsError.localizedDescription
            )
            if !partialFailures.contains(failure) {
                partialFailures.append(failure)
            }
            // HealthKit error descriptions are intentionally excluded from logs: for
            // clinical/document/vision queries they may contain PHI or filenames.
            let safeLogDescriptor = HealthKitSafeLogging.queryFailureDescriptor(
                objectTypeIdentifier: entry.objectTypeIdentifier,
                error: nsError
            )
            logger.warning("Canonical HealthKit record query failed: \(safeLogDescriptor, privacy: .public)")
        }

        // A single bounded workout query captures the workout plus every route,
        // activity, event, statistic, and discoverable associated sample. It
        // fulfills both specialized catalog entries; child descriptors may still
        // run generically below and merge repeated UUID views/relationships.
        let entriesByIdentifier = Dictionary(
            uniqueKeysWithValues: plan.map { ($0.objectTypeIdentifier, $0) }
        )
        let workoutEntry = entriesByIdentifier[HealthKitRecordCatalog.workoutTypeIdentifier]
        let workoutRouteEntry = entriesByIdentifier[HealthKitRecordCatalog.workoutRouteTypeIdentifier]

        if let workoutEntry {
            let operation = "queryWorkoutRecords"
            do {
                let result = try await store.queryWorkoutRecords(
                    predicate: predicate,
                    selectedMetricIDs: workoutEntry.metricIDs,
                    limit: nil
                )
                for record in result.records {
                    let attribution = entriesByIdentifier[record.objectTypeIdentifier]?.attribution
                        ?? HealthKitMetricAttribution(dependencyMetricIDs: workoutEntry.metricIDs)
                    appendRecords(
                        [record],
                        attribution: attribution,
                        includeRelationshipComponents: true
                    )
                }

                let workoutCount = result.records.filter { $0.recordKind == .workout }.count
                queryResults.append(successfulResult(
                    for: workoutEntry,
                    operation: operation,
                    recordCount: workoutCount
                ))
                if let workoutRouteEntry {
                    let routeCount = result.records.filter { $0.recordKind == .workoutRoute }.count
                    queryResults.append(successfulResult(
                        for: workoutRouteEntry,
                        operation: operation,
                        recordCount: routeCount
                    ))
                }

                integrityWarnings.append(contentsOf: result.integrityWarnings)
                for childFailure in result.childQueryFailures {
                    queryResults.append(childFailure)
                    let failure = ExportPartialFailure(
                        date: date,
                        dataType: "HealthKit workout child \(childFailure.identifier)",
                        dateRangeDescription: "\(ownership.ownerDate) [\(intervalStart)..<\(intervalEnd))",
                        errorDescription: childFailure.error?.description
                            ?? childFailure.statusDescription
                            ?? "Workout child query failed"
                    )
                    if !partialFailures.contains(failure) {
                        partialFailures.append(failure)
                    }
                }
            } catch {
                recordFailure(for: workoutEntry, operation: operation, error: error)
                if let workoutRouteEntry {
                    recordFailure(for: workoutRouteEntry, operation: operation, error: error)
                }
            }
        }

        let specializedEntries = plan.filter { entry in
            switch entry.recordKind {
            case .clinical, .document, .verifiableClinicalRecord, .visionPrescription,
                 .electrocardiogram, .audiogram, .heartbeatSeries, .scoredAssessment,
                 .activitySummary, .characteristic:
                return true
            default:
                return false
            }
        }
        if !specializedEntries.isEmpty {
            let result = await store.querySpecializedRecords(
                predicate: predicate,
                entries: specializedEntries,
                interval: interval,
                limit: nil
            )
            appendAttributedRecords(result.records, includeRelationshipComponents: true)
            appendExternalRecords(result.externalRecords)
            queryResults.append(contentsOf: result.recordQueryResults)
            queryResults.append(contentsOf: result.childQueryFailures)
            integrityWarnings.append(contentsOf: result.integrityWarnings)

            let specializedFailures = (result.recordQueryResults + result.childQueryFailures)
                .filter { $0.status == .failure || $0.status == .cancelled }
            for failureResult in specializedFailures {
                let failure = ExportPartialFailure(
                    date: date,
                    dataType: "HealthKit specialized record \(failureResult.identifier)",
                    dateRangeDescription: "\(ownership.ownerDate) [\(intervalStart)..<\(intervalEnd))",
                    errorDescription: failureResult.error?.description
                        ?? failureResult.statusDescription
                        ?? "Specialized HealthKit query failed"
                )
                if !partialFailures.contains(failure) {
                    partialFailures.append(failure)
                }
            }
        }

        for entry in plan {
            if entry.recordKind == .workout || entry.recordKind == .workoutRoute {
                continue
            }
            switch entry.recordKind {
            case .quantity:
                let operation = "queryQuantityRecords"
                do {
                    let queriedRecords = try await store.queryQuantityRecords(
                        identifier: HKQuantityTypeIdentifier(rawValue: entry.objectTypeIdentifier),
                        predicate: predicate,
                        selectedMetricIDs: entry.metricIDs,
                        limit: nil
                    )
                    let ownedRecords = queriedRecords.filter(isOwnedBySelectedDay)
                    appendRecords(ownedRecords, attribution: entry.attribution)
                    queryResults.append(successfulResult(
                        for: entry,
                        operation: operation,
                        recordCount: ownedRecords.count
                    ))
                } catch {
                    recordFailure(for: entry, operation: operation, error: error)
                }

            case .category:
                let operation = "queryCategoryRecords"
                do {
                    let queriedRecords = try await store.queryCategoryRecords(
                        identifier: HKCategoryTypeIdentifier(rawValue: entry.objectTypeIdentifier),
                        predicate: predicate,
                        selectedMetricIDs: entry.metricIDs,
                        limit: nil
                    )
                    let ownedRecords = queriedRecords.filter(isOwnedBySelectedDay)
                    appendRecords(ownedRecords, attribution: entry.attribution)
                    queryResults.append(successfulResult(
                        for: entry,
                        operation: operation,
                        recordCount: ownedRecords.count
                    ))
                } catch {
                    recordFailure(for: entry, operation: operation, error: error)
                }

            case .correlation where entry.objectTypeIdentifier == HealthKitRecordCatalog.bloodPressureCorrelationIdentifier:
                let operation = "queryBloodPressureRecords"
                do {
                    let queriedRecords = try await store.queryBloodPressureRecords(
                        predicate: predicate,
                        selectedMetricIDs: entry.metricIDs,
                        limit: nil
                    )
                    appendRecords(
                        queriedRecords,
                        attribution: entry.attribution,
                        includeRelationshipComponents: true
                    )
                    queryResults.append(successfulResult(
                        for: entry,
                        operation: operation,
                        recordCount: queriedRecords.count
                    ))
                } catch {
                    recordFailure(for: entry, operation: operation, error: error)
                }

            case .correlation where entry.objectTypeIdentifier == HealthKitRecordCatalog.foodCorrelationIdentifier:
                let operation = "queryFoodRecords"
                do {
                    let queriedRecords = try await store.queryFoodRecords(
                        predicate: predicate,
                        selectedMetricIDs: entry.metricIDs,
                        limit: nil
                    )
                    appendRecords(
                        queriedRecords,
                        attribution: entry.attribution,
                        includeRelationshipComponents: true
                    )
                    queryResults.append(successfulResult(
                        for: entry,
                        operation: operation,
                        recordCount: queriedRecords.filter { $0.recordKind == .correlation }.count
                    ))
                } catch {
                    recordFailure(for: entry, operation: operation, error: error)
                }

            case .stateOfMind:
                let operation = "queryStateOfMindRecords"
                do {
                    let queriedRecords = try await store.queryStateOfMindRecords(
                        predicate: predicate,
                        selectedMetricIDs: entry.metricIDs,
                        limit: nil
                    )
                    let ownedRecords = queriedRecords.filter(isOwnedBySelectedDay)
                    appendRecords(ownedRecords, attribution: entry.attribution)
                    queryResults.append(successfulResult(
                        for: entry,
                        operation: operation,
                        recordCount: ownedRecords.count
                    ))
                } catch {
                    recordFailure(for: entry, operation: operation, error: error)
                }

            case .clinical, .document, .verifiableClinicalRecord, .visionPrescription,
                 .electrocardiogram, .audiogram, .heartbeatSeries, .scoredAssessment,
                 .activitySummary, .characteristic:
                // All selected specialized types are handled together above so
                // child series failures remain isolated and selection stays exact.
                continue

            case .medicationDoseEvent:
                let operation = "queryMedicationDoseEventRecords"
                guard isMedicationAuthorizationRequested else {
                    queryResults.append(HealthKitQueryResult(
                        identifier: entry.objectTypeIdentifier,
                        objectTypeIdentifier: entry.objectTypeIdentifier,
                        operation: operation,
                        metricIDs: entry.metricIDs,
                        metricAttribution: entry.attribution,
                        interval: interval,
                        status: .skipped,
                        recordCount: 0,
                        statusDescription: "Medication record capture was skipped because explicit medication authorization has not been requested."
                    ))
                    continue
                }
                do {
                    let result = try await store.queryMedicationDoseEventRecords(
                        predicate: predicate,
                        selectedMetricIDs: entry.metricIDs,
                        limit: nil
                    )
                    let ownedRecords = result.records.filter(isOwnedBySelectedDay)
                    appendRecords(ownedRecords, attribution: entry.attribution)
                    medicationInventoryRecords.append(contentsOf: result.inventoryRecords)
                    queryResults.append(successfulResult(
                        for: entry,
                        operation: operation,
                        recordCount: ownedRecords.count
                    ))
                } catch {
                    recordFailure(for: entry, operation: operation, error: error)
                }

            default:
                queryResults.append(HealthKitQueryResult(
                    identifier: entry.objectTypeIdentifier,
                    objectTypeIdentifier: entry.objectTypeIdentifier,
                    operation: "specializedRecordQuery",
                    metricIDs: entry.metricIDs,
                    metricAttribution: entry.attribution,
                    interval: interval,
                    status: .unsupported,
                    recordCount: 0,
                    statusDescription: "Lossless capture for \(entry.recordKind.rawValue) objects is not implemented by the generic record query protocol."
                ))
            }
        }

        let captureStatus: HealthKitRecordCaptureStatus = queryResults.allSatisfy {
            $0.status == .success
        } ? .complete : .partial
        let archive = HealthKitRecordArchive(
            captureStatus: captureStatus,
            dailyOwnership: ownership,
            records: Array(recordsByUUID.values),
            externalRecords: Array(externalRecordsByIdentifier.values),
            queryManifest: HealthKitQueryManifest(results: queryResults),
            integrityWarnings: integrityWarnings,
            medicationInventoryRecords: medicationInventoryRecords
        )
        return HealthKitRecordArchiveFetchResult(
            archive: archive,
            partialFailures: partialFailures
        )
    }

    private func archiveMetricIDs(for metricSelection: MetricSelectionState?) -> Set<String> {
        if let metricSelection {
            return metricSelection.enabledMetrics
        }

        var metricIDs = Set(
            HealthMetrics.all
                .filter {
                    !$0.isPendingAppleApproval &&
                    !$0.category.requiresSeparateAuthorization &&
                    !HealthKitRecordCatalog.profileMetricIDs.contains($0.id)
                }
                .map(\.id)
        )
        if isMedicationAuthorizationRequested {
            metricIDs.formUnion(
                HealthMetrics.all
                    .filter { $0.category == .medications && !$0.isPendingAppleApproval }
                    .map(\.id)
            )
        }
        return metricIDs
    }

    private static func isRecoverableRecordQueryError(_ error: NSError) -> Bool {
        if error.domain == HKError.errorDomain,
           error.code == HKError.Code.errorAuthorizationDenied.rawValue {
            return false
        }
        return true
    }

    private static func dayRangeDescription(for date: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private static func isDeviceLockedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == HKError.errorDomain,
           nsError.code == HKError.Code.errorDatabaseInaccessible.rawValue {
            return true
        }

        // `errorDatabaseInaccessible` is the canonical HealthKit signal for
        // protected data while the device is locked. Some bridged errors only
        // carry localized text, so keep a narrow text fallback without treating
        // generic authorization failures as lock failures.
        let msg = error.localizedDescription.lowercased()
        return msg.contains("database inaccessible")
            || (msg.contains("protected") && msg.contains("locked"))
            || (msg.contains("protected data") && msg.contains("unavailable"))
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

    private static func intersections(
        of intervals: [(start: Date, end: Date)],
        with boundaries: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        let intervals = mergeIntervals(intervals)
        let boundaries = mergeIntervals(boundaries)
        guard !intervals.isEmpty, !boundaries.isEmpty else { return [] }

        var result: [(start: Date, end: Date)] = []
        var intervalIndex = 0
        var boundaryIndex = 0

        while intervalIndex < intervals.count, boundaryIndex < boundaries.count {
            let interval = intervals[intervalIndex]
            let boundary = boundaries[boundaryIndex]
            let start = max(interval.start, boundary.start)
            let end = min(interval.end, boundary.end)

            if start < end {
                result.append((start: start, end: end))
            }

            if interval.end < boundary.end {
                intervalIndex += 1
            } else {
                boundaryIndex += 1
            }
        }

        return result
    }

    private static func clippedInterval(
        for sample: CategorySampleValue,
        to window: (start: Date, end: Date)
    ) -> (start: Date, end: Date)? {
        let start = max(sample.startDate, window.start)
        let end = min(sample.endDate, window.end)
        guard start < end else { return nil }
        return (start: start, end: end)
    }

    /// Computes total sleep duration from raw interval buckets, matching Apple Health's
    /// "Time Asleep" display while preserving separately logged naps.
    ///
    /// - When `inBedIntervals` is non-empty (Apple Watch pattern), returns
    ///   `union(inBed + asleep) − awake-overlap`. This keeps unlabelled gaps inside
    ///   the InBed session counted as asleep, but also includes asleep samples that
    ///   sit outside the InBed session (for example, a manually logged daytime nap).
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
        let allAsleepIntervals = deepIntervals + remIntervals + coreIntervals + unspecifiedIntervals
        let inBedDuration = totalDuration(of: inBedIntervals)
        if inBedDuration > 0 {
            let sleepBaseIntervals = inBedIntervals + allAsleepIntervals
            let awakeWithinSleep = intersections(of: awakeIntervals, with: sleepBaseIntervals)
            return max(0, totalDuration(of: sleepBaseIntervals) - totalDuration(of: awakeWithinSleep))
        } else {
            return totalDuration(of: allAsleepIntervals)
        }
    }

    /// Returns the HealthKit query window used to assign sleep to an exported day.
    ///
    /// Health.md treats a daily export date as the user's journal day. Sleep is
    /// partitioned into noon-to-noon sleep days: this preserves the existing
    /// attribution of an evening sleep session to the date it starts, while also
    /// assigning afternoon naps to the calendar day on which they occur.
    static func sleepWindow(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)

        let start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: startOfDay)
            ?? calendar.date(byAdding: .hour, value: 12, to: startOfDay)
            ?? startOfDay.addingTimeInterval(12 * 3600)
        let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: nextDay)
            ?? calendar.date(byAdding: .hour, value: 12, to: nextDay)
            ?? nextDay.addingTimeInterval(12 * 3600)

        return (start: start, end: end)
    }

    private func fetchSleepData(for date: Date, includeGranularData: Bool = false) async throws -> SleepData {
        var sleepData = SleepData()

        // Get sleep samples for the noon-to-noon sleep day that begins on the selected date.
        // This matches daily journaling: exporting "Yesterday" after waking gets
        // yesterday's daytime data, yesterday afternoon naps, and yesterday night's sleep.
        let calendar = Calendar.current
        let sleepWindow = Self.sleepWindow(for: date, calendar: calendar)

        let predicate = HKQuery.predicateForSamples(withStart: sleepWindow.start, end: sleepWindow.end)

        let samples = try await store.queryCategorySamples(identifier: .sleepAnalysis, predicate: predicate, ascending: true)

        // Collect intervals per sleep category to merge overlapping samples from multiple sources
        var deepIntervals: [(start: Date, end: Date)] = []
        var remIntervals: [(start: Date, end: Date)] = []
        var coreIntervals: [(start: Date, end: Date)] = []
        var unspecifiedIntervals: [(start: Date, end: Date)] = []
        var awakeIntervals: [(start: Date, end: Date)] = []
        var inBedIntervals: [(start: Date, end: Date)] = []

        for sample in samples {
            guard let interval = Self.clippedInterval(for: sample, to: sleepWindow) else {
                continue
            }

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

        // Preserve individual sleep stage intervals for granular export.
        // Durations above are de-duplicated by merged intervals; granular JSON
        // keeps matching HealthKit samples clipped to the exported sleep day so
        // boundary-spanning samples are not duplicated across adjacent exports.
        if includeGranularData {
            sleepData.stages = samples.compactMap { sample in
                guard let stage = Self.sleepStageName(for: sample.value),
                      let interval = Self.clippedInterval(for: sample, to: sleepWindow) else {
                    return nil
                }
                return SleepStageSample(
                    stage: stage,
                    startDate: interval.start,
                    endDate: interval.end,
                    metadata: sample.metadata
                )
            }
        }

        return sleepData
    }

    private static func sleepStageName(for value: Int) -> String? {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return "deep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return "rem"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return "core"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return "unspecified"
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return "awake"
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return "inBed"
        default:
            return nil
        }
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

        // Stand Time (the accumulated quantity Apple records in minutes)
        activityData.standTimeMinutes = try await store.querySum(identifier: .appleStandTime, predicate: predicate)

        // Exercise Minutes
        activityData.exerciseMinutes = try await store.querySum(identifier: .appleExerciseTime, predicate: predicate)

        // Stand Hours (Apple's stand ring metric: unique hours with at least 1 minute stood)
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

        // Wheelchair Distance
        activityData.wheelchairDistance = try await store.querySum(identifier: .distanceWheelchair, predicate: predicate)

        // Downhill Snow Sports Distance
        activityData.downhillSnowSportsDistance = try await store.querySum(identifier: .distanceDownhillSnowSports, predicate: predicate)

        // Move Time
        activityData.moveTime = try await store.querySum(identifier: .appleMoveTime, predicate: predicate)

        // Physical Effort
        activityData.physicalEffort = try await store.queryAverage(identifier: .physicalEffort, predicate: predicate)

        return activityData
    }

    // MARK: - Heart Data

    private func fetchHeartData(for date: Date, includeGranularData: Bool = false) async throws -> HeartData {
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

        // Heart Rate Recovery — most recent sample
        heartData.heartRateRecovery = try await store.queryMostRecent(identifier: .heartRateRecoveryOneMinute, predicate: predicate)

        // Atrial Fibrillation Burden — most recent sample
        heartData.atrialFibrillationBurden = try await store.queryMostRecent(identifier: .atrialFibrillationBurden, predicate: predicate)

        // Individual timestamped samples for granular export
        if includeGranularData {
            let hrSamples = try await store.queryQuantitySamples(
                identifier: .heartRate, predicate: predicate, ascending: true, limit: nil
            )
            heartData.heartRateSamples = hrSamples.map {
                TimeSample(timestamp: $0.startDate, value: $0.value, metadata: $0.metadata)
            }

            let hrvSamples = try await store.queryQuantitySamples(
                identifier: .heartRateVariabilitySDNN, predicate: predicate, ascending: true, limit: nil
            )
            heartData.hrvSamples = hrvSamples.map {
                TimeSample(timestamp: $0.startDate, value: $0.value, metadata: $0.metadata)
            }
        }

        return heartData
    }

    // MARK: - Vitals Data

    private func fetchVitalsData(
        for date: Date,
        includeGranularData: Bool = false,
        fetchScope: HealthDataFetchScope
    ) async throws -> VitalsFetchResult {
        var result = VitalsFetchResult()
        var vitalsData = VitalsData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)
        let dayRangeDescription = Self.dayRangeDescription(for: date)

        func recordMetricFailure(_ dataType: String, error: Error) {
            let failure = ExportPartialFailure(
                date: date,
                dataType: dataType,
                dateRangeDescription: dayRangeDescription,
                errorDescription: error.localizedDescription
            )
            result.partialFailures.append(failure)
            logger.warning("HealthKit vitals metric fetch failed for \(dataType, privacy: .public) dateRange=\(dayRangeDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        func fetchMetric(
            _ dataType: String,
            metricID: String,
            operation: () async throws -> Void
        ) async throws {
            guard fetchScope.includesMetric(metricID) else { return }
            do {
                try await operation()
            } catch {
                guard !Self.isDeviceLockedError(error) else { throw error }
                recordMetricFailure(dataType, error: error)
            }
        }

        // Respiratory Rate (daily aggregates)
        try await fetchMetric("respiratory rate", metricID: "respiratory_rate") {
            vitalsData.respiratoryRateAvg = try await store.queryAverage(identifier: .respiratoryRate, predicate: predicate)
            vitalsData.respiratoryRateMin = try await store.queryMin(identifier: .respiratoryRate, predicate: predicate)
            vitalsData.respiratoryRateMax = try await store.queryMax(identifier: .respiratoryRate, predicate: predicate)

            if includeGranularData {
                let samples = try await store.queryQuantitySamples(
                    identifier: .respiratoryRate, predicate: predicate, ascending: true, limit: nil
                )
                vitalsData.respiratoryRateSamples = samples.map {
                    TimeSample(timestamp: $0.startDate, value: $0.value, metadata: $0.metadata)
                }
            }
        }

        // Blood Oxygen / SpO2 (daily aggregates)
        try await fetchMetric("blood oxygen", metricID: "blood_oxygen") {
            vitalsData.bloodOxygenAvg = try await store.queryAverage(identifier: .oxygenSaturation, predicate: predicate)
            vitalsData.bloodOxygenMin = try await store.queryMin(identifier: .oxygenSaturation, predicate: predicate)
            vitalsData.bloodOxygenMax = try await store.queryMax(identifier: .oxygenSaturation, predicate: predicate)

            if includeGranularData {
                let samples = try await store.queryQuantitySamples(
                    identifier: .oxygenSaturation, predicate: predicate, ascending: true, limit: nil
                )
                vitalsData.bloodOxygenSamples = samples.map {
                    TimeSample(timestamp: $0.startDate, value: $0.value, metadata: $0.metadata)
                }
            }
        }

        // Body Temperature (daily aggregates)
        try await fetchMetric("body temperature", metricID: "body_temperature") {
            vitalsData.bodyTemperatureAvg = try await store.queryAverage(identifier: .bodyTemperature, predicate: predicate)
            vitalsData.bodyTemperatureMin = try await store.queryMin(identifier: .bodyTemperature, predicate: predicate)
            vitalsData.bodyTemperatureMax = try await store.queryMax(identifier: .bodyTemperature, predicate: predicate)
        }

        // Blood Pressure Systolic (daily aggregates)
        try await fetchMetric("blood pressure systolic", metricID: "blood_pressure_systolic") {
            vitalsData.bloodPressureSystolicAvg = try await store.queryAverage(identifier: .bloodPressureSystolic, predicate: predicate)
            vitalsData.bloodPressureSystolicMin = try await store.queryMin(identifier: .bloodPressureSystolic, predicate: predicate)
            vitalsData.bloodPressureSystolicMax = try await store.queryMax(identifier: .bloodPressureSystolic, predicate: predicate)
        }

        // Blood Pressure Diastolic (daily aggregates)
        try await fetchMetric("blood pressure diastolic", metricID: "blood_pressure_diastolic") {
            vitalsData.bloodPressureDiastolicAvg = try await store.queryAverage(identifier: .bloodPressureDiastolic, predicate: predicate)
            vitalsData.bloodPressureDiastolicMin = try await store.queryMin(identifier: .bloodPressureDiastolic, predicate: predicate)
            vitalsData.bloodPressureDiastolicMax = try await store.queryMax(identifier: .bloodPressureDiastolic, predicate: predicate)
        }

        // Preserve each actual systolic/diastolic pair when time-series export is enabled.
        // HealthKit correlations keep the two values together and avoid constructing
        // false pairs from independently queried quantity samples.
        if includeGranularData &&
            (fetchScope.includesMetric("blood_pressure_systolic") ||
             fetchScope.includesMetric("blood_pressure_diastolic")) {
            do {
                let samples = try await store.queryBloodPressureSamples(
                    predicate: predicate,
                    ascending: true,
                    limit: nil
                )
                vitalsData.bloodPressureSamples = samples.map {
                    BloodPressureSample(
                        correlationUUID: $0.correlationUUID,
                        systolic: $0.systolic,
                        diastolic: $0.diastolic,
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        sourceRevision: $0.sourceRevision,
                        device: $0.device,
                        metadata: $0.metadata
                    )
                }
            } catch {
                guard !Self.isDeviceLockedError(error) else { throw error }
                recordMetricFailure("blood pressure samples", error: error)
            }
        }

        // Blood Glucose (daily aggregates)
        try await fetchMetric("blood glucose", metricID: "blood_glucose") {
            vitalsData.bloodGlucoseAvg = try await store.queryAverage(identifier: .bloodGlucose, predicate: predicate)
            vitalsData.bloodGlucoseMin = try await store.queryMin(identifier: .bloodGlucose, predicate: predicate)
            vitalsData.bloodGlucoseMax = try await store.queryMax(identifier: .bloodGlucose, predicate: predicate)

            if includeGranularData {
                let samples = try await store.queryQuantitySamples(
                    identifier: .bloodGlucose, predicate: predicate, ascending: true, limit: nil
                )
                vitalsData.bloodGlucoseSamples = samples.map {
                    TimeSample(timestamp: $0.startDate, value: $0.value, metadata: $0.metadata)
                }
            }
        }

        // Additional vitals
        try await fetchMetric("basal body temperature", metricID: "basal_body_temperature") {
            vitalsData.basalBodyTemperature = try await store.queryMostRecent(identifier: .basalBodyTemperature, predicate: predicate)
        }
        try await fetchMetric("wrist temperature", metricID: "wrist_temperature") {
            vitalsData.wristTemperature = try await store.queryMostRecent(identifier: .appleSleepingWristTemperature, predicate: predicate)
        }
        try await fetchMetric("electrodermal activity", metricID: "electrodermal_activity") {
            vitalsData.electrodermalActivity = try await store.queryMostRecent(identifier: .electrodermalActivity, predicate: predicate)
        }

        // Respiratory function tests
        try await fetchMetric("forced vital capacity", metricID: "forced_vital_capacity") {
            vitalsData.forcedVitalCapacity = try await store.queryMostRecent(identifier: .forcedVitalCapacity, predicate: predicate)
        }
        try await fetchMetric("FEV1", metricID: "fev1") {
            vitalsData.forcedExpiratoryVolume1 = try await store.queryMostRecent(identifier: .forcedExpiratoryVolume1, predicate: predicate)
        }
        try await fetchMetric("peak expiratory flow", metricID: "peak_expiratory_flow") {
            vitalsData.peakExpiratoryFlowRate = try await store.queryMostRecent(identifier: .peakExpiratoryFlowRate, predicate: predicate)
        }
        try await fetchMetric("inhaler usage", metricID: "inhaler_usage") {
            if let inhalerCount = try await store.querySum(identifier: .inhalerUsage, predicate: predicate) {
                vitalsData.inhalerUsage = inhalerCount
            }
        }

        result.data = vitalsData
        return result
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
        nutritionData.monounsaturatedFat = try await store.querySum(identifier: .dietaryFatMonounsaturated, predicate: predicate)
        nutritionData.polyunsaturatedFat = try await store.querySum(identifier: .dietaryFatPolyunsaturated, predicate: predicate)

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
            let kind = StateOfMindEntry.StateOfMindKind(rawValue: sample.kind) ?? .unknown
            return StateOfMindEntry(
                id: sample.uuid,
                timestamp: sample.startDate,
                endDate: sample.endDate,
                kind: kind,
                valence: sample.valence,
                labels: sample.labels,
                associations: sample.associations,
                sourceRevision: sample.sourceRevision,
                device: sample.device,
                metadata: sample.metadata
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
        mobilityData.walkingSteadiness = try await store.queryMostRecent(identifier: .appleWalkingSteadiness, predicate: predicate)
        mobilityData.runningSpeed = try await store.queryAverage(identifier: .runningSpeed, predicate: predicate)
        mobilityData.runningStrideLength = try await store.queryAverage(identifier: .runningStrideLength, predicate: predicate)
        mobilityData.runningGroundContactTime = try await store.queryAverage(identifier: .runningGroundContactTime, predicate: predicate)
        mobilityData.runningVerticalOscillation = try await store.queryAverage(identifier: .runningVerticalOscillation, predicate: predicate)
        mobilityData.runningPower = try await store.queryAverage(identifier: .runningPower, predicate: predicate)

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

    // MARK: - Cycling Performance Data

    private func fetchCyclingPerformanceData(for date: Date) async throws -> CyclingPerformanceData {
        var data = CyclingPerformanceData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        data.cyclingSpeed = try await store.queryAverage(identifier: .cyclingSpeed, predicate: predicate)
        data.cyclingPower = try await store.queryAverage(identifier: .cyclingPower, predicate: predicate)
        data.cyclingCadence = try await store.queryAverage(identifier: .cyclingCadence, predicate: predicate)
        data.cyclingFTP = try await store.queryMostRecent(identifier: .cyclingFunctionalThresholdPower, predicate: predicate)

        return data
    }

    // MARK: - Vitamins Data

    private func fetchVitaminsData(for date: Date) async throws -> VitaminsData {
        var data = VitaminsData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        data.vitaminA = try await store.querySum(identifier: .dietaryVitaminA, predicate: predicate)
        data.vitaminB6 = try await store.querySum(identifier: .dietaryVitaminB6, predicate: predicate)
        data.vitaminB12 = try await store.querySum(identifier: .dietaryVitaminB12, predicate: predicate)
        data.vitaminC = try await store.querySum(identifier: .dietaryVitaminC, predicate: predicate)
        data.vitaminD = try await store.querySum(identifier: .dietaryVitaminD, predicate: predicate)
        data.vitaminE = try await store.querySum(identifier: .dietaryVitaminE, predicate: predicate)
        data.vitaminK = try await store.querySum(identifier: .dietaryVitaminK, predicate: predicate)
        data.thiamin = try await store.querySum(identifier: .dietaryThiamin, predicate: predicate)
        data.riboflavin = try await store.querySum(identifier: .dietaryRiboflavin, predicate: predicate)
        data.niacin = try await store.querySum(identifier: .dietaryNiacin, predicate: predicate)
        data.folate = try await store.querySum(identifier: .dietaryFolate, predicate: predicate)
        data.biotin = try await store.querySum(identifier: .dietaryBiotin, predicate: predicate)
        data.pantothenicAcid = try await store.querySum(identifier: .dietaryPantothenicAcid, predicate: predicate)

        return data
    }

    // MARK: - Minerals Data

    private func fetchMineralsData(for date: Date) async throws -> MineralsData {
        var data = MineralsData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        data.calcium = try await store.querySum(identifier: .dietaryCalcium, predicate: predicate)
        data.iron = try await store.querySum(identifier: .dietaryIron, predicate: predicate)
        data.potassium = try await store.querySum(identifier: .dietaryPotassium, predicate: predicate)
        data.magnesium = try await store.querySum(identifier: .dietaryMagnesium, predicate: predicate)
        data.phosphorus = try await store.querySum(identifier: .dietaryPhosphorus, predicate: predicate)
        data.zinc = try await store.querySum(identifier: .dietaryZinc, predicate: predicate)
        data.selenium = try await store.querySum(identifier: .dietarySelenium, predicate: predicate)
        data.copper = try await store.querySum(identifier: .dietaryCopper, predicate: predicate)
        data.manganese = try await store.querySum(identifier: .dietaryManganese, predicate: predicate)
        data.chromium = try await store.querySum(identifier: .dietaryChromium, predicate: predicate)
        data.molybdenum = try await store.querySum(identifier: .dietaryMolybdenum, predicate: predicate)
        data.chloride = try await store.querySum(identifier: .dietaryChloride, predicate: predicate)
        data.iodine = try await store.querySum(identifier: .dietaryIodine, predicate: predicate)

        return data
    }

    // MARK: - Symptoms Data

    /// Maps HealthMetrics symptom IDs to their HKCategoryTypeIdentifier for fetching.
    private static let symptomIdentifierMap: [(metricId: String, identifier: HKCategoryTypeIdentifier)] = [
        ("symptom_headache", .headache), ("symptom_fatigue", .fatigue),
        ("symptom_nausea", .nausea), ("symptom_dizziness", .dizziness),
        ("symptom_mood_changes", .moodChanges), ("symptom_sleep_changes", .sleepChanges),
        ("symptom_appetite_changes", .appetiteChanges), ("symptom_hot_flashes", .hotFlashes),
        ("symptom_chills", .chills), ("symptom_fever", .fever),
        ("symptom_lower_back_pain", .lowerBackPain), ("symptom_bloating", .bloating),
        ("symptom_constipation", .constipation), ("symptom_diarrhea", .diarrhea),
        ("symptom_heartburn", .heartburn), ("symptom_coughing", .coughing),
        ("symptom_sore_throat", .soreThroat), ("symptom_runny_nose", .runnyNose),
        ("symptom_shortness_of_breath", .shortnessOfBreath),
        ("symptom_chest_pain", .chestTightnessOrPain),
        ("symptom_skipped_heartbeat", .skippedHeartbeat),
        ("symptom_rapid_heartbeat", .rapidPoundingOrFlutteringHeartbeat),
        ("symptom_acne", .acne), ("symptom_dry_skin", .drySkin),
        ("symptom_hair_loss", .hairLoss), ("symptom_memory_lapse", .memoryLapse),
        ("symptom_night_sweats", .nightSweats), ("symptom_vomiting", .vomiting),
        ("symptom_abdominal_cramps", .abdominalCramps), ("symptom_breast_pain", .breastPain),
        ("symptom_pelvic_pain", .pelvicPain), ("symptom_body_ache", .generalizedBodyAche),
        ("symptom_fainting", .fainting), ("symptom_loss_of_smell", .lossOfSmell),
        ("symptom_loss_of_taste", .lossOfTaste), ("symptom_wheezing", .wheezing),
        ("symptom_sinus_congestion", .sinusCongestion),
        ("symptom_bladder_incontinence", .bladderIncontinence),
        ("symptom_vaginal_dryness", .vaginalDryness),
    ]

    private func fetchSymptomsData(for date: Date) async throws -> SymptomsData {
        var data = SymptomsData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        for (metricId, identifier) in Self.symptomIdentifierMap {
            let samples = try await store.queryCategorySamples(identifier: identifier, predicate: predicate, ascending: true)
            if !samples.isEmpty {
                data.counts[metricId] = samples.count
            }
        }

        return data
    }

    // MARK: - Medications Data

    private func fetchMedicationsData(for date: Date) async throws -> MedicationsData {
        guard isMedicationAuthorizationRequested else {
            return MedicationsData()
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        async let medicationValuesTask = store.queryMedications()
        async let doseEventValuesTask = store.queryMedicationDoseEvents(predicate: predicate, ascending: true, limit: nil)

        let medicationValues = try await medicationValuesTask
        let medications = medicationValues.map { value in
            Medication(
                conceptIdentifier: value.conceptIdentifier,
                displayName: value.displayName,
                nickname: value.nickname,
                generalForm: value.generalForm,
                isArchived: value.isArchived,
                hasSchedule: value.hasSchedule,
                relatedCodings: value.relatedCodings.map {
                    MedicationCoding(system: $0.system, version: $0.version, code: $0.code)
                }
            )
        }

        let doseEventValues = try await doseEventValuesTask
        var medicationNameByIdentifier: [String: String] = [:]
        for medication in medications {
            medicationNameByIdentifier[medication.conceptIdentifier] = medication.exportName
        }
        let doseEvents = doseEventValues.map { value in
            MedicationDoseEvent(
                id: value.uuid,
                medicationConceptIdentifier: value.medicationConceptIdentifier,
                medicationName: value.medicationName ?? medicationNameByIdentifier[value.medicationConceptIdentifier],
                startDate: value.startDate,
                endDate: value.endDate,
                scheduledDate: value.scheduledDate,
                doseQuantity: value.doseQuantity,
                scheduledDoseQuantity: value.scheduledDoseQuantity,
                unit: value.unit,
                logStatus: MedicationDoseStatus(rawValue: value.logStatus) ?? .unknown,
                scheduleType: MedicationDoseScheduleType(rawValue: value.scheduleType) ?? .unknown,
                metadata: value.metadata
            )
        }

        return MedicationsData(medications: medications, doseEvents: doseEvents)
    }

    // MARK: - Other Health Data

    private func fetchOtherData(for date: Date) async throws -> OtherHealthData {
        var data = OtherHealthData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        data.uvExposure = try await store.queryMax(identifier: .uvExposure, predicate: predicate)
        data.timeInDaylight = try await store.querySum(identifier: .timeInDaylight, predicate: predicate)
        data.numberOfFalls = try await store.querySum(identifier: .numberOfTimesFallen, predicate: predicate)
        data.bloodAlcoholContent = try await store.queryMostRecent(identifier: .bloodAlcoholContent, predicate: predicate)
        data.alcoholicBeverages = try await store.querySum(identifier: .numberOfAlcoholicBeverages, predicate: predicate)
        data.insulinDelivery = try await store.querySum(identifier: .insulinDelivery, predicate: predicate)
        data.waterTemperature = try await store.queryMostRecent(identifier: .waterTemperature, predicate: predicate)
        data.underwaterDepth = try await store.queryMax(identifier: .underwaterDepth, predicate: predicate)

        // Category-type "Other" metrics
        let toothbrushingSamples = try await store.queryCategorySamples(identifier: .toothbrushingEvent, predicate: predicate, ascending: true)
        if !toothbrushingSamples.isEmpty {
            data.toothbrushingCount = toothbrushingSamples.count
        }
        let handwashingSamples = try await store.queryCategorySamples(identifier: .handwashingEvent, predicate: predicate, ascending: true)
        if !handwashingSamples.isEmpty {
            data.handwashingCount = handwashingSamples.count
        }

        return data
    }

    // MARK: - Reproductive Health Data

    private func fetchReproductiveHealthData(for date: Date) async throws -> ReproductiveHealthData {
        var data = ReproductiveHealthData()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        // Menstrual Flow
        let flowSamples = try await store.queryCategorySamples(identifier: .menstrualFlow, predicate: predicate, ascending: false, limit: 1)
        if let sample = flowSamples.first {
            switch sample.value {
            case HKCategoryValueMenstrualFlow.unspecified.rawValue: data.menstrualFlow = "unspecified"
            case HKCategoryValueMenstrualFlow.light.rawValue:       data.menstrualFlow = "light"
            case HKCategoryValueMenstrualFlow.medium.rawValue:      data.menstrualFlow = "medium"
            case HKCategoryValueMenstrualFlow.heavy.rawValue:       data.menstrualFlow = "heavy"
            case HKCategoryValueMenstrualFlow.none.rawValue:        data.menstrualFlow = "none"
            default:                                                data.menstrualFlow = "unspecified"
            }
        }

        // Sexual Activity
        let sexualSamples = try await store.queryCategorySamples(identifier: .sexualActivity, predicate: predicate, ascending: true)
        if !sexualSamples.isEmpty {
            data.sexualActivityCount = sexualSamples.count
        }

        // Ovulation Test Result
        let ovulationSamples = try await store.queryCategorySamples(identifier: .ovulationTestResult, predicate: predicate, ascending: false, limit: 1)
        if let sample = ovulationSamples.first {
            switch sample.value {
            case HKCategoryValueOvulationTestResult.negative.rawValue:                  data.ovulationTestResult = "negative"
            case HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue:   data.ovulationTestResult = "positive"
            case HKCategoryValueOvulationTestResult.indeterminate.rawValue:              data.ovulationTestResult = "indeterminate"
            case HKCategoryValueOvulationTestResult.estrogenSurge.rawValue:              data.ovulationTestResult = "estrogen_surge"
            default:                                                                     data.ovulationTestResult = "unknown"
            }
        }

        // Cervical Mucus Quality
        let mucusSamples = try await store.queryCategorySamples(identifier: .cervicalMucusQuality, predicate: predicate, ascending: false, limit: 1)
        if let sample = mucusSamples.first {
            switch sample.value {
            case HKCategoryValueCervicalMucusQuality.dry.rawValue:      data.cervicalMucusQuality = "dry"
            case HKCategoryValueCervicalMucusQuality.sticky.rawValue:   data.cervicalMucusQuality = "sticky"
            case HKCategoryValueCervicalMucusQuality.creamy.rawValue:   data.cervicalMucusQuality = "creamy"
            case HKCategoryValueCervicalMucusQuality.watery.rawValue:   data.cervicalMucusQuality = "watery"
            case HKCategoryValueCervicalMucusQuality.eggWhite.rawValue: data.cervicalMucusQuality = "egg_white"
            default:                                                     data.cervicalMucusQuality = "unknown"
            }
        }

        // Intermenstrual Bleeding (Spotting)
        let spottingSamples = try await store.queryCategorySamples(identifier: .intermenstrualBleeding, predicate: predicate, ascending: true)
        if !spottingSamples.isEmpty {
            data.intermenstrualBleedingCount = spottingSamples.count
        }

        return data
    }

    // MARK: - Workouts

    private func fetchWorkouts(for date: Date) async throws -> [WorkoutData] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        let workouts = try await store.queryWorkouts(predicate: predicate, ascending: true, limit: nil)

        return workouts.map { workout in
            let activityMapping = WorkoutType.healthKitMapping(rawValue: workout.activityType)
            return WorkoutData(
                sourceUUID: workout.sourceUUID,
                workoutType: activityMapping.workoutType,
                healthKitActivityType: activityMapping.activityTypeName,
                healthKitActivityTypeRawValue: workout.activityType,
                startTime: workout.startDate,
                actualEndDate: workout.actualEndDate,
                sourceRevision: workout.sourceRevision,
                device: workout.device,
                isIndoor: workout.isIndoor,
                metadata: workout.metadata,
                duration: workout.duration,
                calories: workout.totalEnergyBurned,
                distance: workout.totalDistance,
                avgHeartRate: workout.avgHeartRate,
                maxHeartRate: workout.maxHeartRate,
                minHeartRate: workout.minHeartRate,
                avgRunningCadence: workout.avgRunningCadence,
                avgStrideLength: workout.avgStrideLength,
                avgGroundContactTime: workout.avgGroundContactTime,
                avgVerticalOscillation: workout.avgVerticalOscillation,
                avgCyclingCadence: workout.avgCyclingCadence,
                avgPower: workout.avgPower,
                maxPower: workout.maxPower,
                elevationGainMeters: workout.elevationGainMeters,
                elevationLossMeters: workout.elevationLossMeters,
                laps: workout.laps,
                splits: workout.splits,
                route: workout.route,
                timeSeries: workout.timeSeries
            )
        }
    }

    // MARK: - HKWorkoutActivityType → WorkoutType Mapping

}

extension WorkoutType {
    typealias HealthKitMapping = (workoutType: WorkoutType, activityTypeName: String?)

    /// Maps every workout type in the current HealthKit SDK while retaining a
    /// nil symbolic name for values introduced by a future SDK.
    static func healthKitMapping(rawValue: UInt) -> HealthKitMapping {
        guard let healthKitType = HKWorkoutActivityType(rawValue: rawValue) else {
            return (.other, nil)
        }
        return healthKitMapping(hkType: healthKitType)
    }

    static func from(hkType: HKWorkoutActivityType) -> WorkoutType {
        healthKitMapping(hkType: hkType).workoutType
    }

    private static func healthKitMapping(hkType: HKWorkoutActivityType) -> HealthKitMapping {
        let workoutType: WorkoutType
        switch hkType {
        case .americanFootball: workoutType = .americanFootball
        case .archery: workoutType = .archery
        case .australianFootball: workoutType = .australianFootball
        case .badminton: workoutType = .badminton
        case .baseball: workoutType = .baseball
        case .basketball: workoutType = .basketball
        case .bowling: workoutType = .bowling
        case .boxing: workoutType = .boxing
        case .climbing: workoutType = .climbing
        case .cricket: workoutType = .cricket
        case .crossTraining: workoutType = .crossTraining
        case .curling: workoutType = .curling
        case .cycling: workoutType = .cycling
        case .dance: workoutType = .dance
        case .danceInspiredTraining: workoutType = .danceInspiredTraining
        case .elliptical: workoutType = .elliptical
        case .equestrianSports: workoutType = .equestrianSports
        case .fencing: workoutType = .fencing
        case .fishing: workoutType = .fishing
        case .functionalStrengthTraining: workoutType = .functionalStrengthTraining
        case .golf: workoutType = .golf
        case .gymnastics: workoutType = .gymnastics
        case .handball: workoutType = .handball
        case .hiking: workoutType = .hiking
        case .hockey: workoutType = .hockey
        case .hunting: workoutType = .hunting
        case .lacrosse: workoutType = .lacrosse
        case .martialArts: workoutType = .martialArts
        case .mindAndBody: workoutType = .mindAndBody
        case .mixedMetabolicCardioTraining: workoutType = .mixedMetabolicCardioTraining
        case .paddleSports: workoutType = .paddleSports
        case .play: workoutType = .play
        case .preparationAndRecovery: workoutType = .rolling
        case .racquetball: workoutType = .racquetball
        case .rowing: workoutType = .rowing
        case .rugby: workoutType = .rugby
        case .running: workoutType = .running
        case .sailing: workoutType = .sailing
        case .skatingSports: workoutType = .skatingSports
        case .snowSports: workoutType = .snowSports
        case .soccer: workoutType = .soccer
        case .softball: workoutType = .softball
        case .squash: workoutType = .squash
        case .stairClimbing: workoutType = .stairClimbing
        case .surfingSports: workoutType = .surfingSports
        case .swimming: workoutType = .swimming
        case .tableTennis: workoutType = .tableTennis
        case .tennis: workoutType = .tennis
        case .trackAndField: workoutType = .trackAndField
        case .traditionalStrengthTraining: workoutType = .traditionalStrengthTraining
        case .volleyball: workoutType = .volleyball
        case .walking: workoutType = .walking
        case .waterFitness: workoutType = .waterFitness
        case .waterPolo: workoutType = .waterPolo
        case .waterSports: workoutType = .waterSports
        case .wrestling: workoutType = .wrestling
        case .yoga: workoutType = .yoga
        case .barre: workoutType = .barre
        case .coreTraining: workoutType = .coreTraining
        case .crossCountrySkiing: workoutType = .crossCountrySkiing
        case .downhillSkiing: workoutType = .downhillSkiing
        case .flexibility: workoutType = .flexibility
        case .highIntensityIntervalTraining: workoutType = .highIntensityIntervalTraining
        case .jumpRope: workoutType = .jumpRope
        case .kickboxing: workoutType = .kickboxing
        case .pilates: workoutType = .pilates
        case .snowboarding: workoutType = .snowboarding
        case .stairs: workoutType = .stairs
        case .stepTraining: workoutType = .stepTraining
        case .wheelchairWalkPace: workoutType = .wheelchairWalkPace
        case .wheelchairRunPace: workoutType = .wheelchairRunPace
        case .taiChi: workoutType = .taiChi
        case .mixedCardio: workoutType = .mixedCardio
        case .handCycling: workoutType = .handCycling
        case .discSports: workoutType = .discSports
        case .fitnessGaming: workoutType = .fitnessGaming
        case .cardioDance: workoutType = .cardioDance
        case .socialDance: workoutType = .socialDance
        case .pickleball: workoutType = .pickleball
        case .cooldown: workoutType = .cooldown
        case .swimBikeRun: workoutType = .swimBikeRun
        case .transition: workoutType = .transition
        case .underwaterDiving: workoutType = .underwaterDiving
        case .other: workoutType = .other
        @unknown default: return (.other, nil)
        }

        return (workoutType, workoutType.healthKitActivityTypeName)
    }
}
