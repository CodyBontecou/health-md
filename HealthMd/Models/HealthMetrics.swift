import Foundation
import HealthKit
import Combine

// MARK: - Health Metric Categories

enum HealthMetricCategory: String, CaseIterable, Codable, Identifiable {
    case sleep = "Sleep"
    case activity = "Activity"
    case heart = "Heart"
    case respiratory = "Respiratory"
    case vitals = "Vitals"
    case bodyMeasurements = "Body Measurements"
    case mobility = "Mobility"
    case cycling = "Cycling"
    case nutrition = "Nutrition"
    case vitamins = "Vitamins"
    case minerals = "Minerals"
    case hearing = "Hearing"
    case mindfulness = "Mindfulness"
    case reproductiveHealth = "Reproductive Health"
    case symptoms = "Symptoms"
    case other = "Other"
    case workouts = "Workouts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sleep: return "bed.double.fill"
        case .activity: return "figure.walk"
        case .heart: return "heart.fill"
        case .respiratory: return "lungs.fill"
        case .vitals: return "waveform.path.ecg"
        case .bodyMeasurements: return "figure.stand"
        case .mobility: return "figure.walk.motion"
        case .cycling: return "bicycle"
        case .nutrition: return "fork.knife"
        case .vitamins: return "pill.fill"
        case .minerals: return "atom"
        case .hearing: return "ear.fill"
        case .mindfulness: return "brain.head.profile"
        case .reproductiveHealth: return "heart.text.square.fill"
        case .symptoms: return "staroflife.fill"
        case .other: return "ellipsis.circle.fill"
        case .workouts: return "figure.run"
        }
    }
}

// MARK: - Health Metric Definition

struct HealthMetricDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let category: HealthMetricCategory
    let unit: String
    let healthKitIdentifier: String?
    let metricType: MetricType
    let aggregation: AggregationType

    enum MetricType {
        case quantity
        case category
        case workout
    }

    enum AggregationType {
        case cumulative      // Sum over the day (steps, calories)
        case discreteAvg     // Average over the day (heart rate)
        case discreteMin     // Minimum value
        case discreteMax     // Maximum value
        case mostRecent      // Most recent sample (weight)
        case duration        // Total duration (sleep stages)
        case count           // Count of samples (mindful sessions)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HealthMetricDefinition, rhs: HealthMetricDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - All Health Metrics

struct HealthMetrics {
    static let all: [HealthMetricDefinition] = sleep + activity + heart + respiratory +
        vitals + bodyMeasurements + mobility + cycling + nutrition + vitamins + minerals +
        hearing + mindfulness + reproductiveHealth + symptoms + other + [workouts]

    static var byCategory: [HealthMetricCategory: [HealthMetricDefinition]] {
        Dictionary(grouping: all, by: { $0.category })
    }

    // MARK: - Sleep

    static let sleep: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "sleep_total", name: "Total Sleep", category: .sleep, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "sleep_deep", name: "Deep Sleep", category: .sleep, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "sleep_rem", name: "REM Sleep", category: .sleep, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "sleep_core", name: "Core Sleep", category: .sleep, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "sleep_awake", name: "Awake During Sleep", category: .sleep, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "sleep_in_bed", name: "Time in Bed", category: .sleep, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
    ]

    // MARK: - Activity

    static let activity: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "steps", name: "Steps", category: .activity, unit: "steps", healthKitIdentifier: "HKQuantityTypeIdentifierStepCount", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "distance_walking_running", name: "Walking + Running Distance", category: .activity, unit: "km", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceWalkingRunning", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "distance_swimming", name: "Swimming Distance", category: .activity, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceSwimming", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "distance_wheelchair", name: "Wheelchair Distance", category: .activity, unit: "km", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceWheelchair", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "distance_downhill_snow", name: "Downhill Snow Sports Distance", category: .activity, unit: "km", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceDownhillSnowSports", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "active_energy", name: "Active Energy", category: .activity, unit: "kcal", healthKitIdentifier: "HKQuantityTypeIdentifierActiveEnergyBurned", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "basal_energy", name: "Resting Energy", category: .activity, unit: "kcal", healthKitIdentifier: "HKQuantityTypeIdentifierBasalEnergyBurned", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "exercise_time", name: "Exercise Time", category: .activity, unit: "min", healthKitIdentifier: "HKQuantityTypeIdentifierAppleExerciseTime", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "stand_time", name: "Stand Time", category: .activity, unit: "min", healthKitIdentifier: "HKQuantityTypeIdentifierAppleStandTime", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "move_time", name: "Move Time", category: .activity, unit: "min", healthKitIdentifier: "HKQuantityTypeIdentifierAppleMoveTime", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "flights_climbed", name: "Flights Climbed", category: .activity, unit: "floors", healthKitIdentifier: "HKQuantityTypeIdentifierFlightsClimbed", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "swimming_strokes", name: "Swimming Strokes", category: .activity, unit: "strokes", healthKitIdentifier: "HKQuantityTypeIdentifierSwimmingStrokeCount", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "push_count", name: "Wheelchair Pushes", category: .activity, unit: "pushes", healthKitIdentifier: "HKQuantityTypeIdentifierPushCount", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vo2_max", name: "VO2 Max", category: .activity, unit: "mL/kg/min", healthKitIdentifier: "HKQuantityTypeIdentifierVO2Max", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "physical_effort", name: "Physical Effort", category: .activity, unit: "kcal/hr/kg", healthKitIdentifier: "HKQuantityTypeIdentifierPhysicalEffort", metricType: .quantity, aggregation: .discreteAvg),
    ]

    // MARK: - Heart

    static let heart: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "heart_rate_avg", name: "Average Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRate", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "heart_rate_min", name: "Minimum Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRate", metricType: .quantity, aggregation: .discreteMin),
        HealthMetricDefinition(id: "heart_rate_max", name: "Maximum Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRate", metricType: .quantity, aggregation: .discreteMax),
        HealthMetricDefinition(id: "resting_heart_rate", name: "Resting Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierRestingHeartRate", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "walking_heart_rate", name: "Walking Heart Rate Average", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierWalkingHeartRateAverage", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "hrv", name: "Heart Rate Variability", category: .heart, unit: "ms", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "heart_rate_recovery", name: "Heart Rate Recovery", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "afib_burden", name: "Atrial Fibrillation Burden", category: .heart, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierAtrialFibrillationBurden", metricType: .quantity, aggregation: .mostRecent),
    ]

    // MARK: - Respiratory

    static let respiratory: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "respiratory_rate", name: "Respiratory Rate", category: .respiratory, unit: "breaths/min", healthKitIdentifier: "HKQuantityTypeIdentifierRespiratoryRate", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "blood_oxygen", name: "Blood Oxygen", category: .respiratory, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierOxygenSaturation", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "forced_vital_capacity", name: "Forced Vital Capacity", category: .respiratory, unit: "L", healthKitIdentifier: "HKQuantityTypeIdentifierForcedVitalCapacity", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "fev1", name: "Forced Expiratory Volume (FEV1)", category: .respiratory, unit: "L", healthKitIdentifier: "HKQuantityTypeIdentifierForcedExpiratoryVolume1", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "peak_expiratory_flow", name: "Peak Expiratory Flow Rate", category: .respiratory, unit: "L/min", healthKitIdentifier: "HKQuantityTypeIdentifierPeakExpiratoryFlowRate", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "inhaler_usage", name: "Inhaler Usage", category: .respiratory, unit: "uses", healthKitIdentifier: "HKQuantityTypeIdentifierInhalerUsage", metricType: .quantity, aggregation: .cumulative),
    ]

    // MARK: - Vitals

    static let vitals: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "body_temperature", name: "Body Temperature", category: .vitals, unit: "°C", healthKitIdentifier: "HKQuantityTypeIdentifierBodyTemperature", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "basal_body_temperature", name: "Basal Body Temperature", category: .vitals, unit: "°C", healthKitIdentifier: "HKQuantityTypeIdentifierBasalBodyTemperature", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "wrist_temperature", name: "Wrist Temperature", category: .vitals, unit: "°C", healthKitIdentifier: "HKQuantityTypeIdentifierAppleSleepingWristTemperature", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "blood_pressure_systolic", name: "Blood Pressure (Systolic)", category: .vitals, unit: "mmHg", healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureSystolic", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "blood_pressure_diastolic", name: "Blood Pressure (Diastolic)", category: .vitals, unit: "mmHg", healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureDiastolic", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "blood_glucose", name: "Blood Glucose", category: .vitals, unit: "mg/dL", healthKitIdentifier: "HKQuantityTypeIdentifierBloodGlucose", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "electrodermal_activity", name: "Electrodermal Activity", category: .vitals, unit: "µS", healthKitIdentifier: "HKQuantityTypeIdentifierElectrodermalActivity", metricType: .quantity, aggregation: .mostRecent),
    ]

    // MARK: - Body Measurements

    static let bodyMeasurements: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "weight", name: "Weight", category: .bodyMeasurements, unit: "kg", healthKitIdentifier: "HKQuantityTypeIdentifierBodyMass", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "height", name: "Height", category: .bodyMeasurements, unit: "cm", healthKitIdentifier: "HKQuantityTypeIdentifierHeight", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "bmi", name: "Body Mass Index", category: .bodyMeasurements, unit: "kg/m²", healthKitIdentifier: "HKQuantityTypeIdentifierBodyMassIndex", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "body_fat", name: "Body Fat Percentage", category: .bodyMeasurements, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierBodyFatPercentage", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "lean_body_mass", name: "Lean Body Mass", category: .bodyMeasurements, unit: "kg", healthKitIdentifier: "HKQuantityTypeIdentifierLeanBodyMass", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "waist_circumference", name: "Waist Circumference", category: .bodyMeasurements, unit: "cm", healthKitIdentifier: "HKQuantityTypeIdentifierWaistCircumference", metricType: .quantity, aggregation: .mostRecent),
    ]

    // MARK: - Mobility

    static let mobility: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "walking_speed", name: "Walking Speed", category: .mobility, unit: "km/h", healthKitIdentifier: "HKQuantityTypeIdentifierWalkingSpeed", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "walking_step_length", name: "Walking Step Length", category: .mobility, unit: "cm", healthKitIdentifier: "HKQuantityTypeIdentifierWalkingStepLength", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "walking_double_support", name: "Double Support Time", category: .mobility, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "walking_asymmetry", name: "Walking Asymmetry", category: .mobility, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierWalkingAsymmetryPercentage", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "walking_steadiness", name: "Walking Steadiness", category: .mobility, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierAppleWalkingSteadiness", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "stair_ascent_speed", name: "Stair Ascent Speed", category: .mobility, unit: "m/s", healthKitIdentifier: "HKQuantityTypeIdentifierStairAscentSpeed", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "stair_descent_speed", name: "Stair Descent Speed", category: .mobility, unit: "m/s", healthKitIdentifier: "HKQuantityTypeIdentifierStairDescentSpeed", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "six_minute_walk", name: "Six-Minute Walk Distance", category: .mobility, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierSixMinuteWalkTestDistance", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "running_speed", name: "Running Speed", category: .mobility, unit: "km/h", healthKitIdentifier: "HKQuantityTypeIdentifierRunningSpeed", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "running_stride_length", name: "Running Stride Length", category: .mobility, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierRunningStrideLength", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "running_ground_contact", name: "Running Ground Contact Time", category: .mobility, unit: "ms", healthKitIdentifier: "HKQuantityTypeIdentifierRunningGroundContactTime", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "running_vertical_oscillation", name: "Running Vertical Oscillation", category: .mobility, unit: "cm", healthKitIdentifier: "HKQuantityTypeIdentifierRunningVerticalOscillation", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "running_power", name: "Running Power", category: .mobility, unit: "W", healthKitIdentifier: "HKQuantityTypeIdentifierRunningPower", metricType: .quantity, aggregation: .discreteAvg),
    ]

    // MARK: - Cycling

    static let cycling: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "cycling_distance", name: "Cycling Distance", category: .cycling, unit: "km", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceCycling", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "cycling_speed", name: "Cycling Speed", category: .cycling, unit: "km/h", healthKitIdentifier: "HKQuantityTypeIdentifierCyclingSpeed", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "cycling_power", name: "Cycling Power", category: .cycling, unit: "W", healthKitIdentifier: "HKQuantityTypeIdentifierCyclingPower", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "cycling_cadence", name: "Cycling Cadence", category: .cycling, unit: "rpm", healthKitIdentifier: "HKQuantityTypeIdentifierCyclingCadence", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "cycling_ftp", name: "Functional Threshold Power", category: .cycling, unit: "W", healthKitIdentifier: "HKQuantityTypeIdentifierCyclingFunctionalThresholdPower", metricType: .quantity, aggregation: .mostRecent),
    ]

    // MARK: - Nutrition (Macros)

    static let nutrition: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "dietary_energy", name: "Dietary Energy", category: .nutrition, unit: "kcal", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryEnergyConsumed", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_protein", name: "Protein", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryProtein", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_carbs", name: "Carbohydrates", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryCarbohydrates", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_fat", name: "Total Fat", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryFatTotal", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_fat_saturated", name: "Saturated Fat", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryFatSaturated", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_fat_mono", name: "Monounsaturated Fat", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryFatMonounsaturated", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_fat_poly", name: "Polyunsaturated Fat", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryFatPolyunsaturated", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_cholesterol", name: "Cholesterol", category: .nutrition, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryCholesterol", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_fiber", name: "Fiber", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryFiber", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_sugar", name: "Sugar", category: .nutrition, unit: "g", healthKitIdentifier: "HKQuantityTypeIdentifierDietarySugar", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_sodium", name: "Sodium", category: .nutrition, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietarySodium", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_water", name: "Water", category: .nutrition, unit: "L", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryWater", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "dietary_caffeine", name: "Caffeine", category: .nutrition, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryCaffeine", metricType: .quantity, aggregation: .cumulative),
    ]

    // MARK: - Vitamins

    static let vitamins: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "vitamin_a", name: "Vitamin A", category: .vitamins, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryVitaminA", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vitamin_b6", name: "Vitamin B6", category: .vitamins, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryVitaminB6", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vitamin_b12", name: "Vitamin B12", category: .vitamins, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryVitaminB12", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vitamin_c", name: "Vitamin C", category: .vitamins, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryVitaminC", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vitamin_d", name: "Vitamin D", category: .vitamins, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryVitaminD", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vitamin_e", name: "Vitamin E", category: .vitamins, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryVitaminE", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vitamin_k", name: "Vitamin K", category: .vitamins, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryVitaminK", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "thiamin", name: "Thiamin (B1)", category: .vitamins, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryThiamin", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "riboflavin", name: "Riboflavin (B2)", category: .vitamins, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryRiboflavin", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "niacin", name: "Niacin (B3)", category: .vitamins, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryNiacin", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "folate", name: "Folate", category: .vitamins, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryFolate", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "biotin", name: "Biotin", category: .vitamins, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryBiotin", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "pantothenic_acid", name: "Pantothenic Acid (B5)", category: .vitamins, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryPantothenicAcid", metricType: .quantity, aggregation: .cumulative),
    ]

    // MARK: - Minerals

    static let minerals: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "calcium", name: "Calcium", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryCalcium", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "iron", name: "Iron", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryIron", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "potassium", name: "Potassium", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryPotassium", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "magnesium", name: "Magnesium", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryMagnesium", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "phosphorus", name: "Phosphorus", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryPhosphorus", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "zinc", name: "Zinc", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryZinc", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "selenium", name: "Selenium", category: .minerals, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietarySelenium", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "copper", name: "Copper", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryCopper", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "manganese", name: "Manganese", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryManganese", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "chromium", name: "Chromium", category: .minerals, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryChromium", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "molybdenum", name: "Molybdenum", category: .minerals, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryMolybdenum", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "chloride", name: "Chloride", category: .minerals, unit: "mg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryChloride", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "iodine", name: "Iodine", category: .minerals, unit: "µg", healthKitIdentifier: "HKQuantityTypeIdentifierDietaryIodine", metricType: .quantity, aggregation: .cumulative),
    ]

    // MARK: - Hearing

    static let hearing: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "headphone_audio", name: "Headphone Audio Level", category: .hearing, unit: "dB", healthKitIdentifier: "HKQuantityTypeIdentifierHeadphoneAudioExposure", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "environmental_audio", name: "Environmental Sound Level", category: .hearing, unit: "dB", healthKitIdentifier: "HKQuantityTypeIdentifierEnvironmentalAudioExposure", metricType: .quantity, aggregation: .discreteAvg),
    ]

    // MARK: - Mindfulness

    static let mindfulness: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "mindful_minutes", name: "Mindful Minutes", category: .mindfulness, unit: "min", healthKitIdentifier: "HKCategoryTypeIdentifierMindfulSession", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "mindful_sessions", name: "Mindful Sessions", category: .mindfulness, unit: "sessions", healthKitIdentifier: "HKCategoryTypeIdentifierMindfulSession", metricType: .category, aggregation: .count),
    ]

    // MARK: - Reproductive Health

    static let reproductiveHealth: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "menstrual_flow", name: "Menstrual Flow", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierMenstrualFlow", metricType: .category, aggregation: .mostRecent),
        HealthMetricDefinition(id: "sexual_activity", name: "Sexual Activity", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierSexualActivity", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "ovulation_test", name: "Ovulation Test Result", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierOvulationTestResult", metricType: .category, aggregation: .mostRecent),
        HealthMetricDefinition(id: "cervical_mucus", name: "Cervical Mucus Quality", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierCervicalMucusQuality", metricType: .category, aggregation: .mostRecent),
        HealthMetricDefinition(id: "intermenstrual_bleeding", name: "Spotting", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierIntermenstrualBleeding", metricType: .category, aggregation: .count),
    ]

    // MARK: - Symptoms

    static let symptoms: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "symptom_headache", name: "Headache", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierHeadache", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_fatigue", name: "Fatigue", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierFatigue", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_nausea", name: "Nausea", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierNausea", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_dizziness", name: "Dizziness", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierDizziness", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_mood_changes", name: "Mood Changes", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierMoodChanges", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_sleep_changes", name: "Sleep Changes", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierSleepChanges", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_appetite_changes", name: "Appetite Changes", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierAppetiteChanges", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_hot_flashes", name: "Hot Flashes", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierHotFlashes", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_chills", name: "Chills", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierChills", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_fever", name: "Fever", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierFever", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_lower_back_pain", name: "Lower Back Pain", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierLowerBackPain", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_bloating", name: "Bloating", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierBloating", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_constipation", name: "Constipation", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierConstipation", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_diarrhea", name: "Diarrhea", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierDiarrhea", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_heartburn", name: "Heartburn", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierHeartburn", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_coughing", name: "Coughing", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierCoughing", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_sore_throat", name: "Sore Throat", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierSoreThroat", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_runny_nose", name: "Runny Nose", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierRunnyNose", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_shortness_of_breath", name: "Shortness of Breath", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierShortnessOfBreath", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_chest_pain", name: "Chest Tightness or Pain", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierChestTightnessOrPain", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_skipped_heartbeat", name: "Skipped Heartbeat", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierSkippedHeartbeat", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_rapid_heartbeat", name: "Rapid/Pounding Heartbeat", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_acne", name: "Acne", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierAcne", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_dry_skin", name: "Dry Skin", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierDrySkin", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_hair_loss", name: "Hair Loss", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierHairLoss", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_memory_lapse", name: "Memory Lapse", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierMemoryLapse", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_night_sweats", name: "Night Sweats", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierNightSweats", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_vomiting", name: "Vomiting", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierVomiting", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_abdominal_cramps", name: "Abdominal Cramps", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierAbdominalCramps", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_breast_pain", name: "Breast Pain", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierBreastPain", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_pelvic_pain", name: "Pelvic Pain", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierPelvicPain", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_body_ache", name: "Generalized Body Ache", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierGeneralizedBodyAche", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_fainting", name: "Fainting", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierFainting", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_loss_of_smell", name: "Loss of Smell", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierLossOfSmell", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_loss_of_taste", name: "Loss of Taste", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierLossOfTaste", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_wheezing", name: "Wheezing", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierWheezing", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_sinus_congestion", name: "Sinus Congestion", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierSinusCongestion", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_bladder_incontinence", name: "Bladder Incontinence", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierBladderIncontinence", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "symptom_vaginal_dryness", name: "Vaginal Dryness", category: .symptoms, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierVaginalDryness", metricType: .category, aggregation: .count),
    ]

    // MARK: - Other

    static let other: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "uv_exposure", name: "UV Exposure", category: .other, unit: "", healthKitIdentifier: "HKQuantityTypeIdentifierUVExposure", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "time_in_daylight", name: "Time in Daylight", category: .other, unit: "min", healthKitIdentifier: "HKQuantityTypeIdentifierTimeInDaylight", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "number_of_falls", name: "Number of Falls", category: .other, unit: "falls", healthKitIdentifier: "HKQuantityTypeIdentifierNumberOfTimesFallen", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "blood_alcohol", name: "Blood Alcohol Content", category: .other, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierBloodAlcoholContent", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "alcoholic_beverages", name: "Alcoholic Beverages", category: .other, unit: "drinks", healthKitIdentifier: "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "insulin_delivery", name: "Insulin Delivery", category: .other, unit: "IU", healthKitIdentifier: "HKQuantityTypeIdentifierInsulinDelivery", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "toothbrushing", name: "Toothbrushing", category: .other, unit: "events", healthKitIdentifier: "HKCategoryTypeIdentifierToothbrushingEvent", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "handwashing", name: "Handwashing", category: .other, unit: "events", healthKitIdentifier: "HKCategoryTypeIdentifierHandwashingEvent", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "water_temperature", name: "Water Temperature", category: .other, unit: "°C", healthKitIdentifier: "HKQuantityTypeIdentifierWaterTemperature", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "underwater_depth", name: "Underwater Depth", category: .other, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierUnderwaterDepth", metricType: .quantity, aggregation: .discreteMax),
    ]

    // MARK: - Workouts

    static let workouts = HealthMetricDefinition(id: "workouts", name: "Workouts", category: .workouts, unit: "", healthKitIdentifier: nil, metricType: .workout, aggregation: .count)
}

// MARK: - Metric Selection State

class MetricSelectionState: ObservableObject, Codable {
    @Published var enabledMetrics: Set<String>
    @Published var enabledCategories: Set<String>

    enum CodingKeys: String, CodingKey {
        case enabledMetrics
        case enabledCategories
    }

    init() {
        // Default: enable common categories
        let defaultCategories: Set<HealthMetricCategory> = [
            .sleep, .activity, .heart, .bodyMeasurements, .workouts
        ]
        self.enabledCategories = Set(defaultCategories.map { $0.rawValue })

        // Enable all metrics in default categories
        var defaultMetrics = Set<String>()
        for category in defaultCategories {
            if let metrics = HealthMetrics.byCategory[category] {
                for metric in metrics {
                    defaultMetrics.insert(metric.id)
                }
            }
        }
        self.enabledMetrics = defaultMetrics
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledMetrics = try container.decode(Set<String>.self, forKey: .enabledMetrics)
        enabledCategories = try container.decode(Set<String>.self, forKey: .enabledCategories)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledMetrics, forKey: .enabledMetrics)
        try container.encode(enabledCategories, forKey: .enabledCategories)
    }

    func isMetricEnabled(_ metricId: String) -> Bool {
        enabledMetrics.contains(metricId)
    }

    func isCategoryEnabled(_ category: HealthMetricCategory) -> Bool {
        enabledCategories.contains(category.rawValue)
    }

    func toggleMetric(_ metricId: String) {
        if enabledMetrics.contains(metricId) {
            enabledMetrics.remove(metricId)
        } else {
            enabledMetrics.insert(metricId)
        }
        updateCategoryState(for: metricId)
    }

    func toggleCategory(_ category: HealthMetricCategory) {
        let metrics = HealthMetrics.byCategory[category] ?? []
        let metricIds = metrics.map { $0.id }

        if isCategoryFullyEnabled(category) {
            // Disable all metrics in category
            for id in metricIds {
                enabledMetrics.remove(id)
            }
            enabledCategories.remove(category.rawValue)
        } else {
            // Enable all metrics in category
            for id in metricIds {
                enabledMetrics.insert(id)
            }
            enabledCategories.insert(category.rawValue)
        }
    }

    func isCategoryFullyEnabled(_ category: HealthMetricCategory) -> Bool {
        let metrics = HealthMetrics.byCategory[category] ?? []
        return metrics.allSatisfy { enabledMetrics.contains($0.id) }
    }

    func isCategoryPartiallyEnabled(_ category: HealthMetricCategory) -> Bool {
        let metrics = HealthMetrics.byCategory[category] ?? []
        let enabledCount = metrics.filter { enabledMetrics.contains($0.id) }.count
        return enabledCount > 0 && enabledCount < metrics.count
    }

    func enabledMetricCount(for category: HealthMetricCategory) -> Int {
        let metrics = HealthMetrics.byCategory[category] ?? []
        return metrics.filter { enabledMetrics.contains($0.id) }.count
    }

    func totalMetricCount(for category: HealthMetricCategory) -> Int {
        return HealthMetrics.byCategory[category]?.count ?? 0
    }

    private func updateCategoryState(for metricId: String) {
        // Find which category this metric belongs to
        guard let metric = HealthMetrics.all.first(where: { $0.id == metricId }) else { return }
        let category = metric.category

        if isCategoryFullyEnabled(category) {
            enabledCategories.insert(category.rawValue)
        } else {
            enabledCategories.remove(category.rawValue)
        }
    }

    func selectAll() {
        for metric in HealthMetrics.all {
            enabledMetrics.insert(metric.id)
        }
        for category in HealthMetricCategory.allCases {
            enabledCategories.insert(category.rawValue)
        }
    }

    func deselectAll() {
        enabledMetrics.removeAll()
        enabledCategories.removeAll()
    }

    var totalEnabledCount: Int {
        enabledMetrics.count
    }

    var totalMetricCount: Int {
        HealthMetrics.all.count
    }
}
