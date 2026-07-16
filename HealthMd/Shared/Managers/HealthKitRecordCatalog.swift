import Foundation
import HealthKit

/// Why an object type is required in addition to the metric that initiated a query plan.
enum HealthKitObjectTypeDependencyReason: String, Sendable, Hashable {
    case bloodPressureCorrelation
    case bloodPressureComponent
    case appleStandHourCompatibility
    case workoutRoute
    case workoutChildSample
    case foodCorrelation
    case nutritionComponent
}

/// A typed edge in the HealthKit object relationship graph.
struct HealthKitObjectTypeDependency: Sendable, Hashable {
    let objectTypeIdentifier: String
    let reason: HealthKitObjectTypeDependencyReason

    init(objectTypeIdentifier: String, reason: HealthKitObjectTypeDependencyReason) {
        self.objectTypeIdentifier = objectTypeIdentifier
        self.reason = reason
    }
}

/// Lossless-query metadata for one HealthKit object type.
///
/// `metricIDs` contains every Health.md metric represented by this object type. Duplicate
/// HealthKit identifiers therefore produce one descriptor without losing any metric IDs.
/// Units are canonical HealthKit conversion unit strings, not presentation units.
struct HealthKitObjectTypeDescriptor: Sendable, Hashable {
    let objectTypeIdentifier: String
    let recordKind: HealthKitRecordKind
    let canonicalUnit: String?
    let availability: HealthMetricAvailability
    let metricIDs: [String]
    let dependencies: [HealthKitObjectTypeDependency]

    var dependencyIdentifiers: [String] {
        dependencies.map(\.objectTypeIdentifier)
    }

    var dependencyReasons: [String: HealthKitObjectTypeDependencyReason] {
        Dictionary(uniqueKeysWithValues: dependencies.map { ($0.objectTypeIdentifier, $0.reason) })
    }

    init(
        objectTypeIdentifier: String,
        recordKind: HealthKitRecordKind,
        canonicalUnit: String? = nil,
        availability: HealthMetricAvailability = .baseline,
        metricIDs: [String],
        dependencies: [HealthKitObjectTypeDependency] = []
    ) {
        self.objectTypeIdentifier = objectTypeIdentifier
        self.recordKind = recordKind
        self.canonicalUnit = canonicalUnit
        self.availability = availability
        self.metricIDs = Array(Set(metricIDs)).sorted()
        self.dependencies = Array(Set(dependencies)).sorted {
            if $0.objectTypeIdentifier == $1.objectTypeIdentifier {
                return $0.reason.rawValue < $1.reason.rawValue
            }
            return $0.objectTypeIdentifier < $1.objectTypeIdentifier
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.objectTypeIdentifier == rhs.objectTypeIdentifier
            && lhs.recordKind.rawValue == rhs.recordKind.rawValue
            && lhs.canonicalUnit == rhs.canonicalUnit
            && lhs.availability == rhs.availability
            && lhs.metricIDs == rhs.metricIDs
            && lhs.dependencies == rhs.dependencies
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(objectTypeIdentifier)
        hasher.combine(recordKind.rawValue)
        hasher.combine(canonicalUnit)
        hasher.combine(availability)
        hasher.combine(metricIDs)
        hasher.combine(dependencies)
    }
}

/// One exact query-plan entry with metric-level provenance for why its object type is present.
struct HealthKitRecordSelectionPlanEntry: Sendable, Equatable {
    let descriptor: HealthKitObjectTypeDescriptor
    let attribution: HealthKitMetricAttribution

    var objectTypeIdentifier: String { descriptor.objectTypeIdentifier }
    var recordKind: HealthKitRecordKind { descriptor.recordKind }
    var metricIDs: [String] { attribution.metricIDs }
    var directMetricIDs: [String] { attribution.directMetricIDs }
    var dependencyMetricIDs: [String] { attribution.dependencyMetricIDs }
}

/// The single object-type graph used to plan lossless record queries and authorization.
enum HealthKitRecordCatalog {
    static let workoutTypeIdentifier = "HKWorkoutTypeIdentifier"
    static let workoutRouteTypeIdentifier = "HKWorkoutRouteTypeIdentifier"
    static let bloodPressureCorrelationIdentifier = "HKCorrelationTypeIdentifierBloodPressure"
    static let foodCorrelationIdentifier = "HKCorrelationTypeIdentifierFood"
    static let appleStandHourIdentifier = "HKCategoryTypeIdentifierAppleStandHour"
    /// `HealthMetrics` uses `HKStateOfMind` as a cross-version sentinel; this is the
    /// actual identifier returned by `HKSampleType.stateOfMindType()`.
    static let stateOfMindIdentifier = "HKDataTypeStateOfMind"
    static let medicationDoseEventIdentifier = "HKMedicationDoseEventTypeIdentifierMedicationDoseEvent"
    static let electrocardiogramIdentifier = "HKDataTypeIdentifierElectrocardiogram"
    static let audiogramIdentifier = "HKDataTypeIdentifierAudiogram"
    static let heartbeatSeriesIdentifier = "HKDataTypeIdentifierHeartbeatSeries"
    static let gad7AssessmentIdentifier = "HKScoredAssessmentTypeIdentifierGAD7"
    static let phq9AssessmentIdentifier = "HKScoredAssessmentTypeIdentifierPHQ9"

    private static let stateOfMindDefinitionIdentifier = "HKStateOfMind"

    /// Explicit metric contract. A newly added HealthMetrics definition is intentionally not
    /// accepted until it is reviewed and added here, so completeness tests fail rather than
    /// silently omitting an unknown record type from lossless capture.
    static let expectedMetricIDs: Set<String> = [
        "sleep_total",
        "sleep_bedtime",
        "sleep_wake",
        "sleep_deep",
        "sleep_rem",
        "sleep_core",
        "sleep_awake",
        "sleep_in_bed",
        "steps",
        "distance_walking_running",
        "distance_swimming",
        "distance_wheelchair",
        "distance_downhill_snow",
        "active_energy",
        "basal_energy",
        "exercise_time",
        "stand_time",
        "stand_hours",
        "move_time",
        "flights_climbed",
        "swimming_strokes",
        "push_count",
        "vo2_max",
        "physical_effort",
        "cross_country_skiing_speed",
        "distance_cross_country_skiing",
        "paddle_sports_speed",
        "distance_paddle_sports",
        "rowing_speed",
        "distance_rowing",
        "distance_skating_sports",
        "workout_effort_score",
        "estimated_workout_effort_score",
        "nike_fuel",
        "heart_rate_avg",
        "heart_rate_min",
        "heart_rate_max",
        "resting_heart_rate",
        "walking_heart_rate",
        "hrv",
        "heart_rate_recovery",
        "afib_burden",
        "peripheral_perfusion_index",
        "high_heart_rate_event",
        "low_heart_rate_event",
        "irregular_heart_rhythm_event",
        "low_cardio_fitness_event",
        "hypertension_event",
        "electrocardiograms",
        "heartbeat_series",
        "respiratory_rate",
        "blood_oxygen",
        "forced_vital_capacity",
        "fev1",
        "peak_expiratory_flow",
        "inhaler_usage",
        "sleeping_breathing_disturbances",
        "sleep_apnea_event",
        "body_temperature",
        "basal_body_temperature",
        "wrist_temperature",
        "blood_pressure_systolic",
        "blood_pressure_diastolic",
        "blood_glucose",
        "electrodermal_activity",
        "weight",
        "height",
        "bmi",
        "body_fat",
        "lean_body_mass",
        "waist_circumference",
        "walking_speed",
        "walking_step_length",
        "walking_double_support",
        "walking_asymmetry",
        "walking_steadiness",
        "stair_ascent_speed",
        "stair_descent_speed",
        "six_minute_walk",
        "running_speed",
        "running_stride_length",
        "running_ground_contact",
        "running_vertical_oscillation",
        "running_power",
        "walking_steadiness_event",
        "cycling_distance",
        "cycling_speed",
        "cycling_power",
        "cycling_cadence",
        "cycling_ftp",
        "dietary_energy",
        "dietary_protein",
        "dietary_carbs",
        "dietary_fat",
        "dietary_fat_saturated",
        "dietary_fat_mono",
        "dietary_fat_poly",
        "dietary_cholesterol",
        "dietary_fiber",
        "dietary_sugar",
        "dietary_sodium",
        "dietary_water",
        "dietary_caffeine",
        "vitamin_a",
        "vitamin_b6",
        "vitamin_b12",
        "vitamin_c",
        "vitamin_d",
        "vitamin_e",
        "vitamin_k",
        "thiamin",
        "riboflavin",
        "niacin",
        "folate",
        "biotin",
        "pantothenic_acid",
        "calcium",
        "iron",
        "potassium",
        "magnesium",
        "phosphorus",
        "zinc",
        "selenium",
        "copper",
        "manganese",
        "chromium",
        "molybdenum",
        "chloride",
        "iodine",
        "headphone_audio",
        "environmental_audio",
        "environmental_sound_reduction",
        "environmental_audio_exposure_event",
        "headphone_audio_exposure_event",
        "audiograms",
        "mindful_minutes",
        "mindful_sessions",
        "state_of_mind_entries",
        "daily_mood",
        "average_valence",
        "momentary_emotions",
        "gad7_assessments",
        "phq9_assessments",
        "menstrual_flow",
        "sexual_activity",
        "ovulation_test",
        "cervical_mucus",
        "intermenstrual_bleeding",
        "bleeding_after_pregnancy",
        "bleeding_during_pregnancy",
        "contraceptive",
        "infrequent_menstrual_cycles",
        "irregular_menstrual_cycles",
        "lactation",
        "persistent_intermenstrual_bleeding",
        "pregnancy",
        "pregnancy_test_result",
        "progesterone_test_result",
        "prolonged_menstrual_periods",
        "symptom_headache",
        "symptom_fatigue",
        "symptom_nausea",
        "symptom_dizziness",
        "symptom_mood_changes",
        "symptom_sleep_changes",
        "symptom_appetite_changes",
        "symptom_hot_flashes",
        "symptom_chills",
        "symptom_fever",
        "symptom_lower_back_pain",
        "symptom_bloating",
        "symptom_constipation",
        "symptom_diarrhea",
        "symptom_heartburn",
        "symptom_coughing",
        "symptom_sore_throat",
        "symptom_runny_nose",
        "symptom_shortness_of_breath",
        "symptom_chest_pain",
        "symptom_skipped_heartbeat",
        "symptom_rapid_heartbeat",
        "symptom_acne",
        "symptom_dry_skin",
        "symptom_hair_loss",
        "symptom_memory_lapse",
        "symptom_night_sweats",
        "symptom_vomiting",
        "symptom_abdominal_cramps",
        "symptom_breast_pain",
        "symptom_pelvic_pain",
        "symptom_body_ache",
        "symptom_fainting",
        "symptom_loss_of_smell",
        "symptom_loss_of_taste",
        "symptom_wheezing",
        "symptom_sinus_congestion",
        "symptom_bladder_incontinence",
        "symptom_vaginal_dryness",
        "medications",
        "uv_exposure",
        "time_in_daylight",
        "number_of_falls",
        "blood_alcohol",
        "alcoholic_beverages",
        "insulin_delivery",
        "toothbrushing",
        "handwashing",
        "water_temperature",
        "underwater_depth",
        "workouts",
    ]

    /// Canonical conversion units mirrored as strings to keep the catalog independent of
    /// SystemHealthStoreAdapter. A focused contract test compares every entry to unitMap.
    private static let canonicalQuantityUnits: [String: String] = [
        "HKQuantityTypeIdentifierStepCount": "count",
        "HKQuantityTypeIdentifierActiveEnergyBurned": "kcal",
        "HKQuantityTypeIdentifierBasalEnergyBurned": "kcal",
        "HKQuantityTypeIdentifierAppleExerciseTime": "min",
        "HKQuantityTypeIdentifierAppleStandTime": "min",
        "HKQuantityTypeIdentifierFlightsClimbed": "count",
        "HKQuantityTypeIdentifierDistanceWalkingRunning": "m",
        "HKQuantityTypeIdentifierDistanceCycling": "m",
        "HKQuantityTypeIdentifierDistanceSwimming": "m",
        "HKQuantityTypeIdentifierSwimmingStrokeCount": "count",
        "HKQuantityTypeIdentifierPushCount": "count",
        "HKQuantityTypeIdentifierHeartRate": "count/min",
        "HKQuantityTypeIdentifierRestingHeartRate": "count/min",
        "HKQuantityTypeIdentifierWalkingHeartRateAverage": "count/min",
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": "ms",
        "HKQuantityTypeIdentifierVO2Max": "mL/min·kg",
        "HKQuantityTypeIdentifierRespiratoryRate": "count/min",
        "HKQuantityTypeIdentifierOxygenSaturation": "%",
        "HKQuantityTypeIdentifierBodyTemperature": "degC",
        "HKQuantityTypeIdentifierBloodPressureSystolic": "mmHg",
        "HKQuantityTypeIdentifierBloodPressureDiastolic": "mmHg",
        "HKQuantityTypeIdentifierBloodGlucose": "mg/dL",
        "HKQuantityTypeIdentifierBodyMass": "kg",
        "HKQuantityTypeIdentifierHeight": "m",
        "HKQuantityTypeIdentifierBodyMassIndex": "count",
        "HKQuantityTypeIdentifierBodyFatPercentage": "%",
        "HKQuantityTypeIdentifierLeanBodyMass": "kg",
        "HKQuantityTypeIdentifierWaistCircumference": "m",
        "HKQuantityTypeIdentifierDietaryEnergyConsumed": "kcal",
        "HKQuantityTypeIdentifierDietaryProtein": "g",
        "HKQuantityTypeIdentifierDietaryCarbohydrates": "g",
        "HKQuantityTypeIdentifierDietaryFatTotal": "g",
        "HKQuantityTypeIdentifierDietaryFatSaturated": "g",
        "HKQuantityTypeIdentifierDietaryFiber": "g",
        "HKQuantityTypeIdentifierDietarySugar": "g",
        "HKQuantityTypeIdentifierDietarySodium": "mg",
        "HKQuantityTypeIdentifierDietaryCholesterol": "mg",
        "HKQuantityTypeIdentifierDietaryWater": "L",
        "HKQuantityTypeIdentifierDietaryCaffeine": "mg",
        "HKQuantityTypeIdentifierWalkingSpeed": "m/s",
        "HKQuantityTypeIdentifierWalkingStepLength": "m",
        "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage": "%",
        "HKQuantityTypeIdentifierWalkingAsymmetryPercentage": "%",
        "HKQuantityTypeIdentifierStairAscentSpeed": "m/s",
        "HKQuantityTypeIdentifierStairDescentSpeed": "m/s",
        "HKQuantityTypeIdentifierSixMinuteWalkTestDistance": "m",
        "HKQuantityTypeIdentifierHeadphoneAudioExposure": "dBASPL",
        "HKQuantityTypeIdentifierEnvironmentalAudioExposure": "dBASPL",
        "HKQuantityTypeIdentifierDistanceWheelchair": "m",
        "HKQuantityTypeIdentifierDistanceDownhillSnowSports": "m",
        "HKQuantityTypeIdentifierAppleMoveTime": "min",
        "HKQuantityTypeIdentifierPhysicalEffort": "kcal/hr·kg",
        "HKQuantityTypeIdentifierCrossCountrySkiingSpeed": "m/s",
        "HKQuantityTypeIdentifierDistanceCrossCountrySkiing": "m",
        "HKQuantityTypeIdentifierPaddleSportsSpeed": "m/s",
        "HKQuantityTypeIdentifierDistancePaddleSports": "m",
        "HKQuantityTypeIdentifierRowingSpeed": "m/s",
        "HKQuantityTypeIdentifierDistanceRowing": "m",
        "HKQuantityTypeIdentifierDistanceSkatingSports": "m",
        "HKQuantityTypeIdentifierWorkoutEffortScore": "appleEffortScore",
        "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore": "appleEffortScore",
        "HKQuantityTypeIdentifierNikeFuel": "count",
        "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute": "count/min",
        "HKQuantityTypeIdentifierAtrialFibrillationBurden": "%",
        "HKQuantityTypeIdentifierPeripheralPerfusionIndex": "%",
        "HKQuantityTypeIdentifierBasalBodyTemperature": "degC",
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature": "degC",
        "HKQuantityTypeIdentifierElectrodermalActivity": "µS",
        "HKQuantityTypeIdentifierForcedVitalCapacity": "L",
        "HKQuantityTypeIdentifierForcedExpiratoryVolume1": "L",
        "HKQuantityTypeIdentifierPeakExpiratoryFlowRate": "L/min",
        "HKQuantityTypeIdentifierInhalerUsage": "count",
        "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances": "count",
        "HKQuantityTypeIdentifierAppleWalkingSteadiness": "%",
        "HKQuantityTypeIdentifierRunningSpeed": "m/s",
        "HKQuantityTypeIdentifierRunningStrideLength": "m",
        "HKQuantityTypeIdentifierRunningGroundContactTime": "ms",
        "HKQuantityTypeIdentifierRunningVerticalOscillation": "cm",
        "HKQuantityTypeIdentifierRunningPower": "W",
        "HKQuantityTypeIdentifierCyclingSpeed": "m/s",
        "HKQuantityTypeIdentifierCyclingPower": "W",
        "HKQuantityTypeIdentifierCyclingCadence": "count/min",
        "HKQuantityTypeIdentifierCyclingFunctionalThresholdPower": "W",
        "HKQuantityTypeIdentifierDietaryFatMonounsaturated": "g",
        "HKQuantityTypeIdentifierDietaryFatPolyunsaturated": "g",
        "HKQuantityTypeIdentifierDietaryVitaminA": "mcg",
        "HKQuantityTypeIdentifierDietaryVitaminB6": "mg",
        "HKQuantityTypeIdentifierDietaryVitaminB12": "mcg",
        "HKQuantityTypeIdentifierDietaryVitaminC": "mg",
        "HKQuantityTypeIdentifierDietaryVitaminD": "mcg",
        "HKQuantityTypeIdentifierDietaryVitaminE": "mg",
        "HKQuantityTypeIdentifierDietaryVitaminK": "mcg",
        "HKQuantityTypeIdentifierDietaryThiamin": "mg",
        "HKQuantityTypeIdentifierDietaryRiboflavin": "mg",
        "HKQuantityTypeIdentifierDietaryNiacin": "mg",
        "HKQuantityTypeIdentifierDietaryFolate": "mcg",
        "HKQuantityTypeIdentifierDietaryBiotin": "mcg",
        "HKQuantityTypeIdentifierDietaryPantothenicAcid": "mg",
        "HKQuantityTypeIdentifierDietaryCalcium": "mg",
        "HKQuantityTypeIdentifierDietaryIron": "mg",
        "HKQuantityTypeIdentifierDietaryPotassium": "mg",
        "HKQuantityTypeIdentifierDietaryMagnesium": "mg",
        "HKQuantityTypeIdentifierDietaryPhosphorus": "mg",
        "HKQuantityTypeIdentifierDietaryZinc": "mg",
        "HKQuantityTypeIdentifierDietarySelenium": "mcg",
        "HKQuantityTypeIdentifierDietaryCopper": "mg",
        "HKQuantityTypeIdentifierDietaryManganese": "mg",
        "HKQuantityTypeIdentifierDietaryChromium": "mcg",
        "HKQuantityTypeIdentifierDietaryMolybdenum": "mcg",
        "HKQuantityTypeIdentifierDietaryChloride": "mg",
        "HKQuantityTypeIdentifierDietaryIodine": "mcg",
        "HKQuantityTypeIdentifierUVExposure": "count",
        "HKQuantityTypeIdentifierTimeInDaylight": "min",
        "HKQuantityTypeIdentifierNumberOfTimesFallen": "count",
        "HKQuantityTypeIdentifierBloodAlcoholContent": "%",
        "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages": "count",
        "HKQuantityTypeIdentifierInsulinDelivery": "IU",
        "HKQuantityTypeIdentifierWaterTemperature": "degC",
        "HKQuantityTypeIdentifierUnderwaterDepth": "m",
        "HKQuantityTypeIdentifierEnvironmentalSoundReduction": "dBASPL",
    ]

    private struct DescriptorSeed {
        let objectTypeIdentifier: String
        let recordKind: HealthKitRecordKind
        let canonicalUnit: String?
        let availability: HealthMetricAvailability
        var metricIDs: Set<String>
        var dependencies: Set<HealthKitObjectTypeDependency>
    }

    private static let definitionsByMetricID: [String: HealthMetricDefinition] =
        Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })

    /// Maps only explicitly reviewed definitions. Future HealthMetrics IDs remain visible in
    /// `uncataloguedMetricIDs` until the catalog contract is updated.
    static let primaryObjectTypeIdentifierByMetricID: [String: String] = {
        var result: [String: String] = [:]
        for metricID in expectedMetricIDs.sorted() {
            guard let definition = definitionsByMetricID[metricID],
                  let identifier = objectTypeIdentifier(for: definition) else { continue }
            result[metricID] = identifier
        }
        return result
    }()

    static let descriptors: [HealthKitObjectTypeDescriptor] = buildDescriptors()

    static let descriptorByObjectTypeIdentifier: [String: HealthKitObjectTypeDescriptor] =
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.objectTypeIdentifier, $0) })

    /// Reverse lookup used to attribute queried records back to every represented metric.
    static let metricIDsByObjectTypeIdentifier: [String: [String]] =
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.objectTypeIdentifier, $0.metricIDs) })

    static let cataloguedMetricIDs = Set(primaryObjectTypeIdentifierByMetricID.keys)
    static let uncataloguedMetricIDs = Set(HealthMetrics.all.map(\.id)).subtracting(cataloguedMetricIDs)
    static let staleExpectedMetricIDs = expectedMetricIDs.subtracting(Set(HealthMetrics.all.map(\.id)))

    static let unresolvedDependencyIdentifiers: Set<String> = {
        let known = Set(descriptors.map(\.objectTypeIdentifier))
        return Set(descriptors.flatMap(\.dependencyIdentifiers)).subtracting(known)
    }()

    /// Standard HealthKit authorization comes from the same descriptors as query planning.
    /// Medication dose events remain catalogued but are excluded because their per-object
    /// authorization flow is intentionally separate.
    static let authorizationDescriptors: Set<HealthKitObjectTypeDescriptor> = Set(
        descriptors.filter { $0.recordKind != .medicationDoseEvent }
    )

    /// Runtime-filtered descriptors used by both authorization and lossless queries.
    /// A descriptor can represent multiple metric definitions, so it is usable when at
    /// least one represented definition is declared on the running OS.
    static var runtimeAuthorizationDescriptors: Set<HealthKitObjectTypeDescriptor> {
        var available: Set<HealthKitObjectTypeDescriptor> = []
        for descriptor in authorizationDescriptors where isRuntimeAvailable(descriptor) {
            available.insert(descriptor)
        }
        return available
    }

    static func isRuntimeAvailable(_ descriptor: HealthKitObjectTypeDescriptor) -> Bool {
        descriptor.availability.isAvailableOnCurrentPlatform
    }

    /// Resolves only object types that exist on this runtime. New identifiers are kept as
    /// strings in the catalog, then guarded before HealthKit sees an authorization set.
    static func resolvedAuthorizationObjectTypes() -> Set<HKObjectType> {
        var resolved: Set<HKObjectType> = []
        for descriptor in runtimeAuthorizationDescriptors {
            if let objectType = resolveObjectType(descriptor) {
                resolved.insert(objectType)
            }
        }
        return resolved
    }

    static func resolveObjectType(_ descriptor: HealthKitObjectTypeDescriptor) -> HKObjectType? {
        guard isRuntimeAvailable(descriptor) else { return nil }

        switch descriptor.recordKind {
        case .quantity:
            return HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: descriptor.objectTypeIdentifier))
        case .category:
            return HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: descriptor.objectTypeIdentifier))
        case .correlation:
            return HKObjectType.correlationType(forIdentifier: HKCorrelationTypeIdentifier(rawValue: descriptor.objectTypeIdentifier))
        case .workout:
            return HKObjectType.workoutType()
        case .workoutRoute:
            return HKSeriesType.workoutRoute()
        case .stateOfMind:
            if #available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *) {
                return HKSampleType.stateOfMindType()
            }
            return nil
        case .electrocardiogram:
            if #available(iOS 14.0, macOS 13.0, macCatalyst 14.0, watchOS 7.0, *) {
                return HKObjectType.electrocardiogramType()
            }
            return nil
        case .audiogram:
            if #available(iOS 13.0, macOS 13.0, macCatalyst 13.0, watchOS 6.0, *) {
                return HKObjectType.audiogramSampleType()
            }
            return nil
        case .heartbeatSeries:
            if #available(iOS 13.0, macOS 13.0, macCatalyst 13.0, watchOS 6.0, visionOS 1.0, *) {
                return HKSeriesType.heartbeat()
            }
            return nil
        case .scoredAssessment:
            if #available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *) {
                return HKScoredAssessmentType(
                    HKScoredAssessmentTypeIdentifier(rawValue: descriptor.objectTypeIdentifier)
                )
            }
            return nil
        case .medicationDoseEvent:
            // Medication authorization is intentionally handled by its per-object API.
            return nil
        default:
            return nil
        }
    }

    static let specialAuthorizationDescriptors: Set<HealthKitObjectTypeDescriptor> = Set(
        descriptors.filter { $0.recordKind == .medicationDoseEvent }
    )

    static func metricIDs(forObjectTypeIdentifier identifier: String) -> [String] {
        metricIDsByObjectTypeIdentifier[identifier] ?? []
    }

    /// Returns the transitive object relationship closure for the selected metrics.
    /// The returned array and every descriptor's nested collections are deterministic.
    static func selectionPlan<MetricIDs: Sequence>(
        enabledMetricIDs: MetricIDs
    ) -> [HealthKitObjectTypeDescriptor] where MetricIDs.Element == String {
        attributedSelectionPlan(enabledMetricIDs: enabledMetricIDs).map(\.descriptor)
    }

    /// Builds the same deterministic closure while retaining which selected metric
    /// directly owns each descriptor and which selected metric reached it through a
    /// dependency edge. Traversal is performed per metric so shared and cyclic graph
    /// edges never erase attribution.
    static func attributedSelectionPlan<MetricIDs: Sequence>(
        enabledMetricIDs: MetricIDs
    ) -> [HealthKitRecordSelectionPlanEntry] where MetricIDs.Element == String {
        let selectedMetricIDs = Set(enabledMetricIDs).intersection(cataloguedMetricIDs)
        var directMetricIDsByIdentifier: [String: Set<String>] = [:]
        var dependencyMetricIDsByIdentifier: [String: Set<String>] = [:]

        for metricID in selectedMetricIDs.sorted() {
            guard let rootIdentifier = primaryObjectTypeIdentifierByMetricID[metricID] else { continue }
            var visited: Set<String> = []
            var queue = [rootIdentifier]
            var index = 0

            while index < queue.count {
                let identifier = queue[index]
                index += 1
                guard visited.insert(identifier).inserted,
                      let descriptor = descriptorByObjectTypeIdentifier[identifier] else { continue }

                if identifier == rootIdentifier {
                    directMetricIDsByIdentifier[identifier, default: []].insert(metricID)
                } else {
                    dependencyMetricIDsByIdentifier[identifier, default: []].insert(metricID)
                }

                for dependency in descriptor.dependencies.sorted(by: {
                    $0.objectTypeIdentifier < $1.objectTypeIdentifier
                }) {
                    if !visited.contains(dependency.objectTypeIdentifier) {
                        queue.append(dependency.objectTypeIdentifier)
                    }
                }
            }
        }

        let plannedIdentifiers = Set(directMetricIDsByIdentifier.keys)
            .union(dependencyMetricIDsByIdentifier.keys)

        return plannedIdentifiers.compactMap { identifier in
            guard let descriptor = descriptorByObjectTypeIdentifier[identifier] else { return nil }
            return HealthKitRecordSelectionPlanEntry(
                descriptor: descriptor,
                attribution: HealthKitMetricAttribution(
                    directMetricIDs: Array(directMetricIDsByIdentifier[identifier, default: []]),
                    dependencyMetricIDs: Array(dependencyMetricIDsByIdentifier[identifier, default: []])
                )
            )
        }.sorted { $0.objectTypeIdentifier < $1.objectTypeIdentifier }
    }

    /// Selection-scoped authorization descriptors, excluding special per-object APIs.
    static func authorizationDescriptors<MetricIDs: Sequence>(
        enabledMetricIDs: MetricIDs
    ) -> Set<HealthKitObjectTypeDescriptor> where MetricIDs.Element == String {
        Set(selectionPlan(enabledMetricIDs: enabledMetricIDs).filter {
            $0.recordKind != .medicationDoseEvent
        })
    }

    private static func objectTypeIdentifier(for definition: HealthMetricDefinition) -> String? {
        if definition.id == "workouts" {
            return workoutTypeIdentifier
        }
        if definition.healthKitIdentifier == stateOfMindDefinitionIdentifier {
            return stateOfMindIdentifier
        }
        return definition.healthKitIdentifier
    }

    private static func recordKind(for definition: HealthMetricDefinition) -> HealthKitRecordKind {
        if definition.healthKitIdentifier == stateOfMindDefinitionIdentifier {
            return .stateOfMind
        }
        if definition.healthKitIdentifier == medicationDoseEventIdentifier {
            return .medicationDoseEvent
        }
        switch definition.healthKitIdentifier {
        case electrocardiogramIdentifier: return .electrocardiogram
        case audiogramIdentifier: return .audiogram
        case heartbeatSeriesIdentifier: return .heartbeatSeries
        case gad7AssessmentIdentifier, phq9AssessmentIdentifier: return .scoredAssessment
        default: break
        }
        switch definition.metricType {
        case .quantity: return .quantity
        case .category: return .category
        case .workout: return .workout
        }
    }

    private static func buildDescriptors() -> [HealthKitObjectTypeDescriptor] {
        var seeds: [String: DescriptorSeed] = [:]

        for metricID in expectedMetricIDs.sorted() {
            guard let definition = definitionsByMetricID[metricID],
                  let identifier = objectTypeIdentifier(for: definition) else { continue }
            let kind = recordKind(for: definition)
            let unit = kind == .quantity ? canonicalQuantityUnits[identifier] : nil

            if var seed = seeds[identifier] {
                seed.metricIDs.insert(metricID)
                seeds[identifier] = seed
            } else {
                seeds[identifier] = DescriptorSeed(
                    objectTypeIdentifier: identifier,
                    recordKind: kind,
                    canonicalUnit: unit,
                    availability: definition.availability,
                    metricIDs: [metricID],
                    dependencies: []
                )
            }
        }

        let bloodPressureMetricIDs: Set<String> = [
            "blood_pressure_systolic", "blood_pressure_diastolic",
        ]
        let dietaryDefinitions = definitionsByMetricID.values.filter {
            expectedMetricIDs.contains($0.id)
                && ($0.category == .nutrition || $0.category == .vitamins || $0.category == .minerals)
        }
        let dietaryMetricIDs = Set(dietaryDefinitions.map(\.id))
        let dietaryIdentifiers = Set(dietaryDefinitions.compactMap { objectTypeIdentifier(for: $0) })

        seeds[bloodPressureCorrelationIdentifier] = DescriptorSeed(
            objectTypeIdentifier: bloodPressureCorrelationIdentifier,
            recordKind: .correlation,
            canonicalUnit: nil,
            availability: .baseline,
            metricIDs: bloodPressureMetricIDs,
            dependencies: []
        )
        if seeds[appleStandHourIdentifier] == nil {
            seeds[appleStandHourIdentifier] = DescriptorSeed(
                objectTypeIdentifier: appleStandHourIdentifier,
                recordKind: .category,
                canonicalUnit: nil,
                availability: .baseline,
                metricIDs: ["stand_hours"],
                dependencies: []
            )
        }
        seeds[workoutRouteTypeIdentifier] = DescriptorSeed(
            objectTypeIdentifier: workoutRouteTypeIdentifier,
            recordKind: .workoutRoute,
            canonicalUnit: nil,
            availability: .baseline,
            metricIDs: ["workouts"],
            dependencies: []
        )
        seeds[foodCorrelationIdentifier] = DescriptorSeed(
            objectTypeIdentifier: foodCorrelationIdentifier,
            recordKind: .correlation,
            canonicalUnit: nil,
            availability: .baseline,
            metricIDs: dietaryMetricIDs,
            dependencies: []
        )

        func addDependency(
            from source: String,
            to target: String,
            reason: HealthKitObjectTypeDependencyReason
        ) {
            guard var seed = seeds[source] else { return }
            seed.dependencies.insert(
                HealthKitObjectTypeDependency(objectTypeIdentifier: target, reason: reason)
            )
            seeds[source] = seed
        }

        let systolic = "HKQuantityTypeIdentifierBloodPressureSystolic"
        let diastolic = "HKQuantityTypeIdentifierBloodPressureDiastolic"
        for component in [systolic, diastolic] {
            addDependency(
                from: component,
                to: bloodPressureCorrelationIdentifier,
                reason: .bloodPressureCorrelation
            )
            addDependency(
                from: bloodPressureCorrelationIdentifier,
                to: component,
                reason: .bloodPressureComponent
            )
        }

        addDependency(
            from: "HKQuantityTypeIdentifierAppleStandTime",
            to: appleStandHourIdentifier,
            reason: .appleStandHourCompatibility
        )

        addDependency(
            from: workoutTypeIdentifier,
            to: workoutRouteTypeIdentifier,
            reason: .workoutRoute
        )
        for childIdentifier in workoutChildSampleIdentifiers {
            addDependency(
                from: workoutTypeIdentifier,
                to: childIdentifier,
                reason: .workoutChildSample
            )
        }

        for dietaryIdentifier in dietaryIdentifiers {
            addDependency(
                from: dietaryIdentifier,
                to: foodCorrelationIdentifier,
                reason: .foodCorrelation
            )
            addDependency(
                from: foodCorrelationIdentifier,
                to: dietaryIdentifier,
                reason: .nutritionComponent
            )
        }

        return seeds.values.map {
            HealthKitObjectTypeDescriptor(
                objectTypeIdentifier: $0.objectTypeIdentifier,
                recordKind: $0.recordKind,
                canonicalUnit: $0.canonicalUnit,
                availability: $0.availability,
                metricIDs: Array($0.metricIDs),
                dependencies: Array($0.dependencies)
            )
        }.sorted(by: descriptorSort)
    }

    /// Child sample types currently consumed to preserve workout details, totals, laps, and
    /// time series. Edges point from workouts to children only: selecting heart rate alone
    /// must not broaden the query to workouts.
    private static let workoutChildSampleIdentifiers: Set<String> = [
        "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKQuantityTypeIdentifierStepCount",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierDistanceWalkingRunning",
        "HKQuantityTypeIdentifierDistanceCycling",
        "HKQuantityTypeIdentifierDistanceSwimming",
        "HKQuantityTypeIdentifierDistanceWheelchair",
        "HKQuantityTypeIdentifierSwimmingStrokeCount",
        "HKQuantityTypeIdentifierRunningSpeed",
        "HKQuantityTypeIdentifierRunningStrideLength",
        "HKQuantityTypeIdentifierRunningGroundContactTime",
        "HKQuantityTypeIdentifierRunningVerticalOscillation",
        "HKQuantityTypeIdentifierRunningPower",
        "HKQuantityTypeIdentifierCyclingSpeed",
        "HKQuantityTypeIdentifierCyclingPower",
        "HKQuantityTypeIdentifierCyclingCadence",
        "HKQuantityTypeIdentifierCrossCountrySkiingSpeed",
        "HKQuantityTypeIdentifierDistanceCrossCountrySkiing",
        "HKQuantityTypeIdentifierPaddleSportsSpeed",
        "HKQuantityTypeIdentifierDistancePaddleSports",
        "HKQuantityTypeIdentifierRowingSpeed",
        "HKQuantityTypeIdentifierDistanceRowing",
        "HKQuantityTypeIdentifierDistanceSkatingSports",
        "HKQuantityTypeIdentifierWorkoutEffortScore",
        "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore",
    ]

    nonisolated private static func descriptorSort(
        _ lhs: HealthKitObjectTypeDescriptor,
        _ rhs: HealthKitObjectTypeDescriptor
    ) -> Bool {
        lhs.objectTypeIdentifier < rhs.objectTypeIdentifier
    }
}
