import Foundation
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
    case clinicalRecords = "Clinical Records"
    case clinicalDocuments = "Clinical Documents"
    case vision = "Vision"
    case medications = "Medications"
    case other = "Other"
    case workouts = "Workouts"

    var id: String { rawValue }

    /// Localized display name for the category
    var displayName: String {
        switch self {
        case .sleep: return String(localized: "Sleep", comment: "Health metric category")
        case .activity: return String(localized: "Activity", comment: "Health metric category")
        case .heart: return String(localized: "Heart", comment: "Health metric category")
        case .respiratory: return String(localized: "Respiratory", comment: "Health metric category")
        case .vitals: return String(localized: "Vitals", comment: "Health metric category")
        case .bodyMeasurements: return String(localized: "Body Measurements", comment: "Health metric category")
        case .mobility: return String(localized: "Mobility", comment: "Health metric category")
        case .cycling: return String(localized: "Cycling", comment: "Health metric category")
        case .nutrition: return String(localized: "Nutrition", comment: "Health metric category")
        case .vitamins: return String(localized: "Vitamins", comment: "Health metric category")
        case .minerals: return String(localized: "Minerals", comment: "Health metric category")
        case .hearing: return String(localized: "Hearing", comment: "Health metric category")
        case .mindfulness: return String(localized: "Mindfulness", comment: "Health metric category")
        case .reproductiveHealth: return String(localized: "Reproductive Health", comment: "Health metric category")
        case .symptoms: return String(localized: "Symptoms", comment: "Health metric category")
        case .clinicalRecords: return String(localized: "Clinical Records", comment: "Health metric category")
        case .clinicalDocuments: return String(localized: "Clinical Documents", comment: "Health metric category")
        case .vision: return String(localized: "Vision", comment: "Health metric category")
        case .medications: return String(localized: "Medications", comment: "Health metric category")
        case .other: return String(localized: "Other", comment: "Health metric category")
        case .workouts: return String(localized: "Workouts", comment: "Health metric category")
        }
    }

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
        case .clinicalRecords: return "cross.case.fill"
        case .clinicalDocuments: return "doc.text.fill"
        case .vision: return "eye.fill"
        case .medications: return "pills.fill"
        case .other: return "ellipsis.circle.fill"
        case .workouts: return "figure.run"
        }
    }

    /// True if this category requires special Apple authorization that we have
    /// applied for but not yet been granted.
    var isPendingAppleApproval: Bool { false }

    /// True when the category uses a separate HealthKit authorization flow and
    /// should not be enabled by broad "select all" or onboarding permission
    /// requests. Documents use one-time user-selection queries; vision and
    /// medications use HealthKit per-object selectors.
    var requiresSeparateAuthorization: Bool {
        self == .clinicalDocuments || self == .vision || self == .medications
    }

    /// Default export selection: all normal HealthKit categories are enabled;
    /// categories with special permission flows are opt-in.
    var isEnabledByDefault: Bool {
        !isPendingAppleApproval && !requiresSeparateAuthorization
    }
}

// MARK: - Health Metric Definition

enum HealthMetricPlatform: Sendable {
    case iOS
    case macOS
    case macCatalyst
    case watchOS
    case visionOS
}

/// The HealthKit declaration family that makes a metric readable.
///
/// The catalog stores identifiers as stable strings, while this value provides the
/// deployment guard needed before authorization or archive queries use that identifier.
enum HealthMetricAvailability: String, Sendable, Hashable {
    case baseline
    case healthKit12_2
    case healthKit13
    case healthKit14
    case healthKit14_2
    case healthKit14_3
    case healthKit15
    case healthKit15_4
    case healthKit16
    case healthKit16_4
    case healthKit18
    case healthKit26
    case healthKit26_2

    func minimumVersion(for platform: HealthMetricPlatform) -> OperatingSystemVersion {
        let version: (Int, Int)
        switch (self, platform) {
        case (.baseline, .iOS): version = (8, 0)
        case (.baseline, .watchOS): version = (2, 0)
        case (.baseline, .macOS), (.baseline, .macCatalyst): version = (13, 0)
        case (.baseline, .visionOS): version = (1, 0)
        case (.healthKit12_2, .iOS): version = (12, 2)
        case (.healthKit12_2, .watchOS): version = (5, 2)
        case (.healthKit12_2, .macOS), (.healthKit12_2, .macCatalyst): version = (13, 0)
        case (.healthKit12_2, .visionOS): version = (1, 0)
        case (.healthKit13, .iOS), (.healthKit13, .macCatalyst): version = (13, 0)
        case (.healthKit13, .watchOS): version = (6, 0)
        case (.healthKit13, .macOS): version = (13, 0)
        case (.healthKit13, .visionOS): version = (1, 0)
        case (.healthKit14, .iOS), (.healthKit14, .macCatalyst): version = (14, 0)
        case (.healthKit14, .watchOS): version = (7, 0)
        case (.healthKit14, .macOS): version = (13, 0)
        case (.healthKit14, .visionOS): version = (1, 0)
        case (.healthKit14_2, .iOS), (.healthKit14_2, .macCatalyst): version = (14, 2)
        case (.healthKit14_2, .watchOS): version = (7, 1)
        case (.healthKit14_2, .macOS): version = (13, 0)
        case (.healthKit14_2, .visionOS): version = (1, 0)
        case (.healthKit14_3, .iOS), (.healthKit14_3, .macCatalyst): version = (14, 3)
        case (.healthKit14_3, .watchOS): version = (7, 2)
        case (.healthKit14_3, .macOS): version = (13, 0)
        case (.healthKit14_3, .visionOS): version = (1, 0)
        case (.healthKit15, .iOS), (.healthKit15, .macCatalyst): version = (15, 0)
        case (.healthKit15, .watchOS): version = (8, 0)
        case (.healthKit15, .macOS): version = (13, 0)
        case (.healthKit15, .visionOS): version = (1, 0)
        case (.healthKit15_4, .iOS), (.healthKit15_4, .macCatalyst): version = (15, 4)
        case (.healthKit15_4, .watchOS): version = (8, 5)
        case (.healthKit15_4, .macOS): version = (13, 0)
        case (.healthKit15_4, .visionOS): version = (1, 0)
        case (.healthKit16, .iOS), (.healthKit16, .macCatalyst): version = (16, 0)
        case (.healthKit16, .watchOS): version = (9, 0)
        case (.healthKit16, .macOS): version = (13, 0)
        case (.healthKit16, .visionOS): version = (1, 0)
        case (.healthKit16_4, .iOS), (.healthKit16_4, .macCatalyst): version = (16, 4)
        case (.healthKit16_4, .watchOS): version = (9, 4)
        case (.healthKit16_4, .macOS): version = (13, 3)
        case (.healthKit16_4, .visionOS): version = (1, 0)
        case (.healthKit18, .iOS), (.healthKit18, .macCatalyst): version = (18, 0)
        case (.healthKit18, .watchOS): version = (11, 0)
        case (.healthKit18, .macOS): version = (15, 0)
        case (.healthKit18, .visionOS): version = (2, 0)
        case (.healthKit26, _): version = (26, 0)
        case (.healthKit26_2, _): version = (26, 2)
        }
        return OperatingSystemVersion(majorVersion: version.0, minorVersion: version.1, patchVersion: 0)
    }

    func isAvailable(on platform: HealthMetricPlatform, version: OperatingSystemVersion) -> Bool {
        let minimum = minimumVersion(for: platform)
        return (version.majorVersion, version.minorVersion, version.patchVersion) >=
            (minimum.majorVersion, minimum.minorVersion, minimum.patchVersion)
    }

    nonisolated var isAvailableOnCurrentPlatform: Bool {
        switch self {
        case .baseline:
            return true
        case .healthKit12_2:
            if #available(iOS 12.2, macOS 13.0, macCatalyst 13.0, watchOS 5.2, visionOS 1.0, *) { return true }
        case .healthKit13:
            if #available(iOS 13.0, macOS 13.0, macCatalyst 13.0, watchOS 6.0, visionOS 1.0, *) { return true }
        case .healthKit14:
            if #available(iOS 14.0, macOS 13.0, macCatalyst 14.0, watchOS 7.0, visionOS 1.0, *) { return true }
        case .healthKit14_2:
            if #available(iOS 14.2, macOS 13.0, macCatalyst 14.2, watchOS 7.1, visionOS 1.0, *) { return true }
        case .healthKit14_3:
            if #available(iOS 14.3, macOS 13.0, macCatalyst 14.3, watchOS 7.2, visionOS 1.0, *) { return true }
        case .healthKit15:
            if #available(iOS 15.0, macOS 13.0, macCatalyst 15.0, watchOS 8.0, visionOS 1.0, *) { return true }
        case .healthKit15_4:
            if #available(iOS 15.4, macOS 13.0, macCatalyst 15.4, watchOS 8.5, visionOS 1.0, *) { return true }
        case .healthKit16:
            if #available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *) { return true }
        case .healthKit16_4:
            if #available(iOS 16.4, macOS 13.3, macCatalyst 16.4, watchOS 9.4, visionOS 1.0, *) { return true }
        case .healthKit18:
            if #available(iOS 18.0, macOS 15.0, macCatalyst 18.0, watchOS 11.0, visionOS 2.0, *) { return true }
        case .healthKit26:
            if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, watchOS 26.0, visionOS 26.0, *) { return true }
        case .healthKit26_2:
            if #available(iOS 26.2, macOS 26.2, macCatalyst 26.2, watchOS 26.2, visionOS 26.2, *) { return true }
        }
        return false
    }

    var displayDescription: String? {
        switch self {
        case .baseline: return nil
        case .healthKit12_2: return "iOS 12.2+"
        case .healthKit13: return "iOS 13+"
        case .healthKit14: return "iOS 14+"
        case .healthKit14_2: return "iOS 14.2+"
        case .healthKit14_3: return "iOS 14.3+"
        case .healthKit15: return "iOS 15+"
        case .healthKit15_4: return "iOS 15.4+"
        case .healthKit16: return "iOS 16+"
        case .healthKit16_4: return "iOS 16.4+"
        case .healthKit18: return "iOS 18+ / macOS 15+"
        case .healthKit26: return "iOS 26+ / macOS 26+"
        case .healthKit26_2: return "iOS 26.2+ / macOS 26.2+"
        }
    }
}

struct HealthMetricDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let category: HealthMetricCategory
    let unit: String
    let healthKitIdentifier: String?
    let metricType: MetricType
    let aggregation: AggregationType
    let isArchiveOnly: Bool
    let availability: HealthMetricAvailability

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

    init(
        id: String,
        name: String,
        category: HealthMetricCategory,
        unit: String,
        healthKitIdentifier: String?,
        metricType: MetricType,
        aggregation: AggregationType,
        isArchiveOnly: Bool = false,
        availability: HealthMetricAvailability = .baseline
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.unit = unit
        self.healthKitIdentifier = healthKitIdentifier
        self.metricType = metricType
        self.aggregation = aggregation
        self.isArchiveOnly = isArchiveOnly
        self.availability = availability
    }

    /// Convenience: pending approval is determined by the metric's category.
    var isPendingAppleApproval: Bool {
        category.isPendingAppleApproval
    }

    /// Selection-row detail. Archive-only metrics intentionally do not promise a
    /// daily summary field; their exact HealthKit source records are the product.
    var selectionDetail: String {
        var parts: [String] = []
        if !unit.isEmpty { parts.append(unit) }
        if isArchiveOnly { parts.append("Source records only") }
        if let availability = availability.displayDescription { parts.append(availability) }
        return parts.joined(separator: " · ")
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
        hearing + mindfulness + reproductiveHealth + symptoms + clinicalRecords +
        clinicalDocuments + vision + medications + other + [workouts]

    static var byCategory: [HealthMetricCategory: [HealthMetricDefinition]] {
        Dictionary(grouping: all, by: { $0.category })
    }

    // MARK: - Sleep

    static let sleep: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "sleep_total", name: "Total Sleep", category: .sleep, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "sleep_bedtime", name: "Bedtime", category: .sleep, unit: "time", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "sleep_wake", name: "Wake Time", category: .sleep, unit: "time", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", metricType: .category, aggregation: .duration),
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
        HealthMetricDefinition(id: "stand_hours", name: "Stand Hours", category: .activity, unit: "hours", healthKitIdentifier: "HKCategoryTypeIdentifierAppleStandHour", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "move_time", name: "Move Time", category: .activity, unit: "min", healthKitIdentifier: "HKQuantityTypeIdentifierAppleMoveTime", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "flights_climbed", name: "Flights Climbed", category: .activity, unit: "floors", healthKitIdentifier: "HKQuantityTypeIdentifierFlightsClimbed", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "swimming_strokes", name: "Swimming Strokes", category: .activity, unit: "strokes", healthKitIdentifier: "HKQuantityTypeIdentifierSwimmingStrokeCount", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "push_count", name: "Wheelchair Pushes", category: .activity, unit: "pushes", healthKitIdentifier: "HKQuantityTypeIdentifierPushCount", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "vo2_max", name: "Cardio Fitness", category: .activity, unit: "mL/kg/min", healthKitIdentifier: "HKQuantityTypeIdentifierVO2Max", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "physical_effort", name: "Physical Effort", category: .activity, unit: "kcal/hr/kg", healthKitIdentifier: "HKQuantityTypeIdentifierPhysicalEffort", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "activity_summary", name: "Activity Summary Rings and Goals", category: .activity, unit: "summary", healthKitIdentifier: "HKActivitySummaryTypeIdentifier", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true),
        HealthMetricDefinition(id: "activity_move_mode", name: "Activity Move Mode", category: .activity, unit: "profile value", healthKitIdentifier: "HKCharacteristicTypeIdentifierActivityMoveMode", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true),
        HealthMetricDefinition(id: "cross_country_skiing_speed", name: "Cross-Country Skiing Speed", category: .activity, unit: "m/s", healthKitIdentifier: "HKQuantityTypeIdentifierCrossCountrySkiingSpeed", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "distance_cross_country_skiing", name: "Cross-Country Skiing Distance", category: .activity, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceCrossCountrySkiing", metricType: .quantity, aggregation: .cumulative, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "paddle_sports_speed", name: "Paddle Sports Speed", category: .activity, unit: "m/s", healthKitIdentifier: "HKQuantityTypeIdentifierPaddleSportsSpeed", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "distance_paddle_sports", name: "Paddle Sports Distance", category: .activity, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierDistancePaddleSports", metricType: .quantity, aggregation: .cumulative, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "rowing_speed", name: "Rowing Speed", category: .activity, unit: "m/s", healthKitIdentifier: "HKQuantityTypeIdentifierRowingSpeed", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "distance_rowing", name: "Rowing Distance", category: .activity, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceRowing", metricType: .quantity, aggregation: .cumulative, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "distance_skating_sports", name: "Skating Sports Distance", category: .activity, unit: "m", healthKitIdentifier: "HKQuantityTypeIdentifierDistanceSkatingSports", metricType: .quantity, aggregation: .cumulative, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "workout_effort_score", name: "Workout Effort Score", category: .activity, unit: "appleEffortScore", healthKitIdentifier: "HKQuantityTypeIdentifierWorkoutEffortScore", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "estimated_workout_effort_score", name: "Estimated Workout Effort Score", category: .activity, unit: "appleEffortScore", healthKitIdentifier: "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "nike_fuel", name: "Nike Fuel", category: .activity, unit: "count", healthKitIdentifier: "HKQuantityTypeIdentifierNikeFuel", metricType: .quantity, aggregation: .cumulative, isArchiveOnly: true),
    ]

    // MARK: - Heart

    static let heart: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "heart_rate_avg", name: "Average Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRate", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "heart_rate_min", name: "Minimum Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRate", metricType: .quantity, aggregation: .discreteMin),
        HealthMetricDefinition(id: "heart_rate_max", name: "Maximum Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRate", metricType: .quantity, aggregation: .discreteMax),
        HealthMetricDefinition(id: "resting_heart_rate", name: "Resting Heart Rate", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierRestingHeartRate", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "walking_heart_rate", name: "Walking Heart Rate Average", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierWalkingHeartRateAverage", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "hrv", name: "Heart Rate Variability", category: .heart, unit: "ms", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", metricType: .quantity, aggregation: .discreteAvg),
        HealthMetricDefinition(id: "heart_rate_recovery", name: "Heart Rate Recovery", category: .heart, unit: "bpm", healthKitIdentifier: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "afib_burden", name: "Atrial Fibrillation Burden", category: .heart, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierAtrialFibrillationBurden", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "peripheral_perfusion_index", name: "Peripheral Perfusion Index", category: .heart, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierPeripheralPerfusionIndex", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true),
        HealthMetricDefinition(id: "high_heart_rate_event", name: "High Heart Rate Event", category: .heart, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierHighHeartRateEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit12_2),
        HealthMetricDefinition(id: "low_heart_rate_event", name: "Low Heart Rate Event", category: .heart, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierLowHeartRateEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit12_2),
        HealthMetricDefinition(id: "irregular_heart_rhythm_event", name: "Irregular Heart Rhythm Event", category: .heart, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierIrregularHeartRhythmEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit12_2),
        HealthMetricDefinition(id: "low_cardio_fitness_event", name: "Low Cardio Fitness Event", category: .heart, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierLowCardioFitnessEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit14_3),
        HealthMetricDefinition(id: "hypertension_event", name: "Hypertension Event", category: .heart, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierHypertensionEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit26_2),
        HealthMetricDefinition(id: "electrocardiograms", name: "Electrocardiograms", category: .heart, unit: "waveforms", healthKitIdentifier: "HKDataTypeIdentifierElectrocardiogram", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit14),
        HealthMetricDefinition(id: "heartbeat_series", name: "Heartbeat Series", category: .heart, unit: "series", healthKitIdentifier: "HKDataTypeIdentifierHeartbeatSeries", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit13),
    ]

    // MARK: - Respiratory

    static let respiratory: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "respiratory_rate", name: "Respiratory Rate", category: .respiratory, unit: "breaths/min", healthKitIdentifier: "HKQuantityTypeIdentifierRespiratoryRate", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "blood_oxygen", name: "Blood Oxygen", category: .respiratory, unit: "%", healthKitIdentifier: "HKQuantityTypeIdentifierOxygenSaturation", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "forced_vital_capacity", name: "Forced Vital Capacity", category: .respiratory, unit: "L", healthKitIdentifier: "HKQuantityTypeIdentifierForcedVitalCapacity", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "fev1", name: "Forced Expiratory Volume (FEV1)", category: .respiratory, unit: "L", healthKitIdentifier: "HKQuantityTypeIdentifierForcedExpiratoryVolume1", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "peak_expiratory_flow", name: "Peak Expiratory Flow Rate", category: .respiratory, unit: "L/min", healthKitIdentifier: "HKQuantityTypeIdentifierPeakExpiratoryFlowRate", metricType: .quantity, aggregation: .mostRecent),
        HealthMetricDefinition(id: "inhaler_usage", name: "Inhaler Usage", category: .respiratory, unit: "uses", healthKitIdentifier: "HKQuantityTypeIdentifierInhalerUsage", metricType: .quantity, aggregation: .cumulative),
        HealthMetricDefinition(id: "sleeping_breathing_disturbances", name: "Sleeping Breathing Disturbances", category: .respiratory, unit: "count", healthKitIdentifier: "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "sleep_apnea_event", name: "Sleep Apnea Event", category: .respiratory, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierSleepApneaEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit18),
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
        HealthMetricDefinition(id: "date_of_birth", name: "Date of Birth", category: .bodyMeasurements, unit: "profile value", healthKitIdentifier: "HKCharacteristicTypeIdentifierDateOfBirth", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true),
        HealthMetricDefinition(id: "biological_sex", name: "Biological Sex", category: .bodyMeasurements, unit: "profile value", healthKitIdentifier: "HKCharacteristicTypeIdentifierBiologicalSex", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true),
        HealthMetricDefinition(id: "blood_type", name: "Blood Type", category: .bodyMeasurements, unit: "profile value", healthKitIdentifier: "HKCharacteristicTypeIdentifierBloodType", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true),
        HealthMetricDefinition(id: "fitzpatrick_skin_type", name: "Fitzpatrick Skin Type", category: .bodyMeasurements, unit: "profile value", healthKitIdentifier: "HKCharacteristicTypeIdentifierFitzpatrickSkinType", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true),
        HealthMetricDefinition(id: "wheelchair_use", name: "Wheelchair Use", category: .bodyMeasurements, unit: "profile value", healthKitIdentifier: "HKCharacteristicTypeIdentifierWheelchairUse", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true),
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
        HealthMetricDefinition(id: "walking_steadiness_event", name: "Walking Steadiness Event", category: .mobility, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit15),
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
        HealthMetricDefinition(id: "environmental_sound_reduction", name: "Environmental Sound Reduction", category: .hearing, unit: "dBASPL", healthKitIdentifier: "HKQuantityTypeIdentifierEnvironmentalSoundReduction", metricType: .quantity, aggregation: .discreteAvg, isArchiveOnly: true, availability: .healthKit16),
        HealthMetricDefinition(id: "environmental_audio_exposure_event", name: "Environmental Audio Exposure Event", category: .hearing, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit14),
        HealthMetricDefinition(id: "headphone_audio_exposure_event", name: "Headphone Audio Exposure Event", category: .hearing, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierHeadphoneAudioExposureEvent", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit14_2),
        HealthMetricDefinition(id: "audiograms", name: "Audiograms", category: .hearing, unit: "hearing tests", healthKitIdentifier: "HKDataTypeIdentifierAudiogram", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit13),
    ]

    // MARK: - Mindfulness

    static let mindfulness: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "mindful_minutes", name: "Mindful Minutes", category: .mindfulness, unit: "min", healthKitIdentifier: "HKCategoryTypeIdentifierMindfulSession", metricType: .category, aggregation: .duration),
        HealthMetricDefinition(id: "mindful_sessions", name: "Mindful Sessions", category: .mindfulness, unit: "sessions", healthKitIdentifier: "HKCategoryTypeIdentifierMindfulSession", metricType: .category, aggregation: .count),
        // State of Mind metrics (iOS 17+)
        HealthMetricDefinition(id: "state_of_mind_entries", name: "Mood Entries", category: .mindfulness, unit: "entries", healthKitIdentifier: "HKStateOfMind", metricType: .category, aggregation: .count, availability: .healthKit18),
        HealthMetricDefinition(id: "daily_mood", name: "Daily Mood", category: .mindfulness, unit: "", healthKitIdentifier: "HKStateOfMind", metricType: .category, aggregation: .mostRecent, availability: .healthKit18),
        HealthMetricDefinition(id: "average_valence", name: "Average Mood Valence", category: .mindfulness, unit: "", healthKitIdentifier: "HKStateOfMind", metricType: .category, aggregation: .discreteAvg, availability: .healthKit18),
        HealthMetricDefinition(id: "momentary_emotions", name: "Momentary Emotions", category: .mindfulness, unit: "entries", healthKitIdentifier: "HKStateOfMind", metricType: .category, aggregation: .count, availability: .healthKit18),
        HealthMetricDefinition(id: "gad7_assessments", name: "GAD-7 Assessments", category: .mindfulness, unit: "assessments", healthKitIdentifier: "HKScoredAssessmentTypeIdentifierGAD7", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "phq9_assessments", name: "PHQ-9 Assessments", category: .mindfulness, unit: "assessments", healthKitIdentifier: "HKScoredAssessmentTypeIdentifierPHQ9", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit18),
    ]

    // MARK: - Reproductive Health

    static let reproductiveHealth: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "menstrual_flow", name: "Menstrual Flow", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierMenstrualFlow", metricType: .category, aggregation: .mostRecent),
        HealthMetricDefinition(id: "sexual_activity", name: "Sexual Activity", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierSexualActivity", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "ovulation_test", name: "Ovulation Test Result", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierOvulationTestResult", metricType: .category, aggregation: .mostRecent),
        HealthMetricDefinition(id: "cervical_mucus", name: "Cervical Mucus Quality", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierCervicalMucusQuality", metricType: .category, aggregation: .mostRecent),
        HealthMetricDefinition(id: "intermenstrual_bleeding", name: "Spotting", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierIntermenstrualBleeding", metricType: .category, aggregation: .count),
        HealthMetricDefinition(id: "bleeding_after_pregnancy", name: "Bleeding After Pregnancy", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierBleedingAfterPregnancy", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "bleeding_during_pregnancy", name: "Bleeding During Pregnancy", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierBleedingDuringPregnancy", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true, availability: .healthKit18),
        HealthMetricDefinition(id: "contraceptive", name: "Contraceptive", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierContraceptive", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true, availability: .healthKit14_3),
        HealthMetricDefinition(id: "infrequent_menstrual_cycles", name: "Infrequent Menstrual Cycles", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierInfrequentMenstrualCycles", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit16),
        HealthMetricDefinition(id: "irregular_menstrual_cycles", name: "Irregular Menstrual Cycles", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierIrregularMenstrualCycles", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit16),
        HealthMetricDefinition(id: "lactation", name: "Lactation", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierLactation", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit14_3),
        HealthMetricDefinition(id: "persistent_intermenstrual_bleeding", name: "Persistent Intermenstrual Bleeding", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierPersistentIntermenstrualBleeding", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit16),
        HealthMetricDefinition(id: "pregnancy", name: "Pregnancy", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierPregnancy", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit14_3),
        HealthMetricDefinition(id: "pregnancy_test_result", name: "Pregnancy Test Result", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierPregnancyTestResult", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true, availability: .healthKit15),
        HealthMetricDefinition(id: "progesterone_test_result", name: "Progesterone Test Result", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierProgesteroneTestResult", metricType: .category, aggregation: .mostRecent, isArchiveOnly: true, availability: .healthKit15),
        HealthMetricDefinition(id: "prolonged_menstrual_periods", name: "Prolonged Menstrual Periods", category: .reproductiveHealth, unit: "", healthKitIdentifier: "HKCategoryTypeIdentifierProlongedMenstrualPeriods", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit16),
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

    // MARK: - Clinical records, documents, and vision

    static let clinicalRecords: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "clinical_allergy_records", name: "Allergy Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierAllergyRecord", metricType: .category, aggregation: .count, isArchiveOnly: true),
        HealthMetricDefinition(id: "clinical_note_records", name: "Clinical Notes", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierClinicalNoteRecord", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit16_4),
        HealthMetricDefinition(id: "clinical_condition_records", name: "Condition Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierConditionRecord", metricType: .category, aggregation: .count, isArchiveOnly: true),
        HealthMetricDefinition(id: "clinical_coverage_records", name: "Coverage Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierCoverageRecord", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit14),
        HealthMetricDefinition(id: "clinical_immunization_records", name: "Immunization Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierImmunizationRecord", metricType: .category, aggregation: .count, isArchiveOnly: true),
        HealthMetricDefinition(id: "clinical_lab_result_records", name: "Lab Result Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierLabResultRecord", metricType: .category, aggregation: .count, isArchiveOnly: true),
        HealthMetricDefinition(id: "clinical_medication_records", name: "Clinical Medication Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierMedicationRecord", metricType: .category, aggregation: .count, isArchiveOnly: true),
        HealthMetricDefinition(id: "clinical_procedure_records", name: "Procedure Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierProcedureRecord", metricType: .category, aggregation: .count, isArchiveOnly: true),
        HealthMetricDefinition(id: "clinical_vital_sign_records", name: "Clinical Vital-Sign Records", category: .clinicalRecords, unit: "records", healthKitIdentifier: "HKClinicalTypeIdentifierVitalSignRecord", metricType: .category, aggregation: .count, isArchiveOnly: true),
    ]

    static let clinicalDocuments: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "cda_documents", name: "CDA Documents", category: .clinicalDocuments, unit: "documents", healthKitIdentifier: "HKDocumentTypeIdentifierCDA", metricType: .category, aggregation: .count, isArchiveOnly: true),
        HealthMetricDefinition(id: "verifiable_clinical_records", name: "Verifiable Clinical Records", category: .clinicalDocuments, unit: "records", healthKitIdentifier: "HKVerifiableClinicalRecordTypeIdentifier", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit15_4),
    ]

    static let vision: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "vision_prescriptions", name: "Vision Prescriptions", category: .vision, unit: "prescriptions", healthKitIdentifier: "HKVisionPrescriptionTypeIdentifier", metricType: .category, aggregation: .count, isArchiveOnly: true, availability: .healthKit16),
    ]

    // MARK: - Medications
    //
    // Medication metadata and dose events are read through HealthKit's
    // per-object authorization API on OS versions that support
    // HKUserAnnotatedMedicationType / HKMedicationDoseEvent.

    static let medications: [HealthMetricDefinition] = [
        HealthMetricDefinition(id: "medications", name: "Medications", category: .medications, unit: "doses", healthKitIdentifier: "HKMedicationDoseEventTypeIdentifierMedicationDoseEvent", metricType: .category, aggregation: .count, availability: .healthKit26),
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
        // Default: enable normal categories/metrics. Categories with separate
        // permission flows (currently Medications) are opt-in so onboarding
        // never implies access the app hasn't requested yet.
        self.enabledCategories = Set(
            HealthMetricCategory.allCases
                .filter { $0.isEnabledByDefault }
                .map { $0.rawValue }
        )
        self.enabledMetrics = Set(
            HealthMetrics.all
                .filter {
                    $0.category.isEnabledByDefault && !$0.isPendingAppleApproval &&
                        $0.availability.isAvailableOnCurrentPlatform
                }
                .map { $0.id }
        )
        #if DEBUG
        LifecycleTracker.trackCreation(of: "MetricSelectionState")
        #endif
    }

    deinit {
        #if DEBUG
        LifecycleTracker.trackDeinit(of: "MetricSelectionState")
        #endif
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decoded = try container.decode(Set<String>.self, forKey: .enabledMetrics)
        let decodedCategories = try container.decode(Set<String>.self, forKey: .enabledCategories)

        // Migration: for every enabled category, ensure all current metric IDs are
        // present in enabledMetrics. This picks up metric IDs added in new app versions
        // (e.g. sleep_bedtime / sleep_wake) for users whose saved state predates them.
        //
        // NOTE: Categories that aren't in `decodedCategories` are NOT auto-enabled,
        // because we can't distinguish "user explicitly disabled this category" from
        // "this category didn't exist when user last saved". A future migration with
        // an explicit schema version can resolve this safely.
        for category in HealthMetricCategory.allCases {
            guard decodedCategories.contains(category.rawValue) else { continue }
            guard !category.isPendingAppleApproval else { continue }
            guard !category.requiresSeparateAuthorization else { continue }
            if let metrics = HealthMetrics.byCategory[category] {
                for metric in metrics where metric.availability.isAvailableOnCurrentPlatform {
                    decoded.insert(metric.id)
                }
            }
        }

        // Enforce: metrics in pending-approval categories can never be enabled,
        // even if a stale or hand-edited persisted state references them.
        let pendingMetricIds = Set(
            HealthMetrics.all.filter { $0.isPendingAppleApproval }.map { $0.id }
        )
        let pendingCategoryNames = Set(
            HealthMetricCategory.allCases.filter { $0.isPendingAppleApproval }.map { $0.rawValue }
        )
        let unavailableMetricIds = Set(
            HealthMetrics.all
                .filter { !$0.availability.isAvailableOnCurrentPlatform }
                .map(\.id)
        )

        enabledMetrics = decoded.subtracting(pendingMetricIds).subtracting(unavailableMetricIds)
        enabledCategories = decodedCategories.subtracting(pendingCategoryNames)
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
        // Pending-approval metrics can never be toggled on.
        if let metric = HealthMetrics.all.first(where: { $0.id == metricId }),
           metric.isPendingAppleApproval || !metric.availability.isAvailableOnCurrentPlatform {
            return
        }

        var updatedMetrics = enabledMetrics
        if updatedMetrics.contains(metricId) {
            updatedMetrics.remove(metricId)
        } else {
            updatedMetrics.insert(metricId)
        }
        enabledMetrics = updatedMetrics
        updateCategoryState(for: metricId)
    }

    func toggleCategory(_ category: HealthMetricCategory) {
        // Pending-approval categories can never be toggled on.
        guard !category.isPendingAppleApproval else { return }

        let metrics = (HealthMetrics.byCategory[category] ?? []).filter {
            $0.availability.isAvailableOnCurrentPlatform
        }
        let metricIds = metrics.map { $0.id }

        var updatedMetrics = enabledMetrics
        var updatedCategories = enabledCategories

        if isCategoryFullyEnabled(category) {
            // Disable all metrics in category
            for id in metricIds {
                updatedMetrics.remove(id)
            }
            updatedCategories.remove(category.rawValue)
        } else {
            // Enable all metrics in category
            for id in metricIds {
                updatedMetrics.insert(id)
            }
            updatedCategories.insert(category.rawValue)
        }

        enabledMetrics = updatedMetrics
        enabledCategories = updatedCategories
    }

    func isCategoryFullyEnabled(_ category: HealthMetricCategory) -> Bool {
        let metrics = (HealthMetrics.byCategory[category] ?? []).filter {
            $0.availability.isAvailableOnCurrentPlatform
        }
        return !metrics.isEmpty && metrics.allSatisfy { enabledMetrics.contains($0.id) }
    }

    func isCategoryPartiallyEnabled(_ category: HealthMetricCategory) -> Bool {
        let metrics = (HealthMetrics.byCategory[category] ?? []).filter {
            $0.availability.isAvailableOnCurrentPlatform
        }
        let enabledCount = metrics.filter { enabledMetrics.contains($0.id) }.count
        return enabledCount > 0 && enabledCount < metrics.count
    }

    func enabledMetricCount(for category: HealthMetricCategory) -> Int {
        let metrics = (HealthMetrics.byCategory[category] ?? []).filter {
            $0.availability.isAvailableOnCurrentPlatform
        }
        return metrics.filter { enabledMetrics.contains($0.id) }.count
    }

    func totalMetricCount(for category: HealthMetricCategory) -> Int {
        (HealthMetrics.byCategory[category] ?? []).filter {
            $0.availability.isAvailableOnCurrentPlatform
        }.count
    }

    private func updateCategoryState(for metricId: String) {
        // Find which category this metric belongs to
        guard let metric = HealthMetrics.all.first(where: { $0.id == metricId }) else { return }
        let category = metric.category

        if isCategoryFullyEnabled(category) {
            var updatedCategories = enabledCategories
            updatedCategories.insert(category.rawValue)
            enabledCategories = updatedCategories
        } else {
            var updatedCategories = enabledCategories
            updatedCategories.remove(category.rawValue)
            enabledCategories = updatedCategories
        }
    }

    func selectAll() {
        // "Select all" includes standard metrics only. Categories that require
        // a separate authorization flow must be enabled explicitly by the UI.
        enabledMetrics = Set(
            HealthMetrics.all
                .filter {
                    !$0.isPendingAppleApproval && !$0.category.requiresSeparateAuthorization &&
                        $0.availability.isAvailableOnCurrentPlatform
                }
                .map { $0.id }
        )
        enabledCategories = Set(
            HealthMetricCategory.allCases
                .filter { $0.isEnabledByDefault }
                .map { $0.rawValue }
        )
    }

    func deselectAll() {
        enabledMetrics = []
        enabledCategories = []
    }

    var totalEnabledCount: Int {
        enabledMetrics.count
    }

    /// Total count of metrics the user can actually enable. Excludes metrics
    /// in categories that are pending Apple approval.
    var totalMetricCount: Int {
        HealthMetrics.all.lazy.filter {
            !$0.isPendingAppleApproval && $0.availability.isAvailableOnCurrentPlatform
        }.count
    }
}
