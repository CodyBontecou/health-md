import Foundation

/// One HealthKit source sample projected into the apple-v12 compatibility successor.
///
/// Exactly one entry exists per `HKSample`: no dedupe, interpolation, resampling, or clipping.
/// A sample belongs to the calendar day containing its start instant. Quantity samples carry
/// `value` in `unit`, which is the same `HKUnit` the daily summary of that type uses; category
/// samples carry a stable `categoryValue` string instead.
nonisolated struct DetailSample: Codable, Sendable, Equatable {
    /// Health.md metric ID (for example `steps`).
    let metric: String
    /// HealthKit object type identifier raw value (for example `HKQuantityTypeIdentifierStepCount`).
    let healthKitType: String
    let startDate: Date
    let endDate: Date
    let value: Double?
    let unit: String?
    let categoryValue: String?
    let sourceUUID: UUID?
    /// Source revision bundle identifier, when HealthKit reports one.
    let source: String?
    /// `HKSource.name`: the user-visible app or device name (for example "Withings").
    let sourceName: String?

    init(
        metric: String,
        healthKitType: String,
        startDate: Date,
        endDate: Date,
        value: Double? = nil,
        unit: String? = nil,
        categoryValue: String? = nil,
        sourceUUID: UUID? = nil,
        source: String? = nil,
        sourceName: String? = nil
    ) {
        self.metric = metric
        self.healthKitType = healthKitType
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.unit = unit
        self.categoryValue = categoryValue
        self.sourceUUID = sourceUUID
        self.source = source
        self.sourceName = sourceName
    }

    /// Deterministic order across the per-type queries of one category.
    static func sortedForExport(_ samples: [DetailSample]) -> [DetailSample] {
        samples.enumerated().sorted { lhs, rhs in
            let l = lhs.element, r = rhs.element
            if l.startDate != r.startDate { return l.startDate < r.startDate }
            if l.metric != r.metric { return l.metric < r.metric }
            if l.endDate != r.endDate { return l.endDate < r.endDate }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// Synthesized-Codable storage for category `detailSamples`. Older payloads without the key
/// decode as empty, and an empty list is omitted on encode so v8 payload bytes never change.
@propertyWrapper
nonisolated struct OmittedWhenEmptyDetailSamples: Codable, Sendable, Equatable {
    var wrappedValue: [DetailSample]

    init(wrappedValue: [DetailSample] = []) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        wrappedValue = try decoder.singleValueContainer().decode([DetailSample].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    nonisolated func decode(
        _ type: OmittedWhenEmptyDetailSamples.Type,
        forKey key: Key
    ) throws -> OmittedWhenEmptyDetailSamples {
        try decodeIfPresent(type, forKey: key) ?? OmittedWhenEmptyDetailSamples()
    }
}

extension KeyedEncodingContainer {
    nonisolated mutating func encode(_ value: OmittedWhenEmptyDetailSamples, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty else { return }
        try encode(value.wrappedValue, forKey: key)
    }
}

/// Successor compatibility profile carried by a captured/sanitized day. `nil` means the
/// historical apple-v8 (or wake-date apple-v11) grammar.
nonisolated enum AppleCompatibilityDetailProfile: String, Codable, Sendable, Equatable {
    case appleV12 = "apple-v12"
}

/// Catalog of HealthKit types projected into apple-v12 `detailSamples`. Only types whose daily
/// summary Health.md already captures are listed, so detail never widens authorization.
nonisolated enum AppleDetailSampleCatalog {
    enum Kind: Sendable, Equatable {
        case quantity(unit: String)
        case category
    }

    struct Entry: Sendable, Equatable {
        let group: ExportDetailGroup
        /// Metric ID written to `DetailSample.metric`.
        let metricID: String
        /// Any of these selected metrics retains the sample. Usually just `metricID`.
        let selectionMetricIDs: [String]
        let healthKitType: String
        let label: String
        let kind: Kind

        var unit: String? {
            if case .quantity(let unit) = kind { return unit }
            return nil
        }
    }

    private static func q(_ group: ExportDetailGroup, _ metricID: String, _ type: String,
                          _ unit: String, _ label: String) -> Entry {
        Entry(group: group, metricID: metricID, selectionMetricIDs: [metricID],
              healthKitType: "HKQuantityTypeIdentifier\(type)", label: label, kind: .quantity(unit: unit))
    }

    private static func c(_ group: ExportDetailGroup, _ metricID: String, _ type: String,
                          _ label: String, selection: [String]? = nil) -> Entry {
        Entry(group: group, metricID: metricID, selectionMetricIDs: selection ?? [metricID],
              healthKitType: "HKCategoryTypeIdentifier\(type)", label: label, kind: .category)
    }

    /// Units mirror `SystemHealthStoreAdapter.unitMap` (the summary units). A focused test
    /// compares every quantity entry with the adapter.
    static let entries: [Entry] = [
        q(.activity, "steps", "StepCount", "count", "Steps"),
        q(.activity, "active_energy", "ActiveEnergyBurned", "kcal", "Active Energy"),
        q(.activity, "basal_energy", "BasalEnergyBurned", "kcal", "Basal Energy"),
        q(.activity, "stand_time", "AppleStandTime", "min", "Stand Time"),
        q(.activity, "exercise_time", "AppleExerciseTime", "min", "Exercise Time"),
        c(.activity, "stand_hours", "AppleStandHour", "Stand Hour"),
        q(.activity, "flights_climbed", "FlightsClimbed", "count", "Flights Climbed"),
        q(.activity, "distance_walking_running", "DistanceWalkingRunning", "m", "Walking + Running Distance"),
        q(.activity, "cycling_distance", "DistanceCycling", "m", "Cycling Distance"),
        q(.activity, "distance_swimming", "DistanceSwimming", "m", "Swimming Distance"),
        q(.activity, "swimming_strokes", "SwimmingStrokeCount", "count", "Swimming Strokes"),
        q(.activity, "push_count", "PushCount", "count", "Wheelchair Pushes"),
        q(.activity, "vo2_max", "VO2Max", "mL/min·kg", "VO2 Max"),
        q(.activity, "distance_wheelchair", "DistanceWheelchair", "m", "Wheelchair Distance"),
        q(.activity, "distance_downhill_snow", "DistanceDownhillSnowSports", "m", "Downhill Snow Sports Distance"),
        q(.activity, "move_time", "AppleMoveTime", "min", "Move Time"),
        q(.activity, "physical_effort", "PhysicalEffort", "kcal/hr·kg", "Physical Effort"),

        q(.vitals, "body_temperature", "BodyTemperature", "degC", "Body Temperature"),
        q(.vitals, "basal_body_temperature", "BasalBodyTemperature", "degC", "Basal Body Temperature"),
        q(.vitals, "wrist_temperature", "AppleSleepingWristTemperature", "degC", "Wrist Temperature"),
        q(.vitals, "forced_vital_capacity", "ForcedVitalCapacity", "L", "Forced Vital Capacity"),
        q(.vitals, "fev1", "ForcedExpiratoryVolume1", "L", "FEV1"),
        q(.vitals, "peak_expiratory_flow", "PeakExpiratoryFlowRate", "L/min", "Peak Expiratory Flow"),

        q(.body, "weight", "BodyMass", "kg", "Weight"),
        q(.body, "height", "Height", "m", "Height"),
        q(.body, "bmi", "BodyMassIndex", "count", "BMI"),
        q(.body, "body_fat", "BodyFatPercentage", "%", "Body Fat Percentage"),
        q(.body, "lean_body_mass", "LeanBodyMass", "kg", "Lean Body Mass"),
        q(.body, "waist_circumference", "WaistCircumference", "m", "Waist Circumference"),

        q(.nutrition, "dietary_energy", "DietaryEnergyConsumed", "kcal", "Dietary Energy"),
        q(.nutrition, "dietary_protein", "DietaryProtein", "g", "Protein"),
        q(.nutrition, "dietary_carbs", "DietaryCarbohydrates", "g", "Carbohydrates"),
        q(.nutrition, "dietary_fat", "DietaryFatTotal", "g", "Total Fat"),
        q(.nutrition, "dietary_fat_saturated", "DietaryFatSaturated", "g", "Saturated Fat"),
        q(.nutrition, "dietary_fiber", "DietaryFiber", "g", "Fiber"),
        q(.nutrition, "dietary_sugar", "DietarySugar", "g", "Sugar"),
        q(.nutrition, "dietary_sodium", "DietarySodium", "mg", "Sodium"),
        q(.nutrition, "dietary_cholesterol", "DietaryCholesterol", "mg", "Cholesterol"),
        q(.nutrition, "dietary_water", "DietaryWater", "L", "Water"),
        q(.nutrition, "dietary_caffeine", "DietaryCaffeine", "mg", "Caffeine"),
        q(.nutrition, "dietary_fat_mono", "DietaryFatMonounsaturated", "g", "Monounsaturated Fat"),
        q(.nutrition, "dietary_fat_poly", "DietaryFatPolyunsaturated", "g", "Polyunsaturated Fat"),

        c(.mindfulness, "mindful_sessions", "MindfulSession", "Mindful Session",
          selection: ["mindful_minutes", "mindful_sessions"]),

        q(.mobility, "walking_speed", "WalkingSpeed", "m/s", "Walking Speed"),
        q(.mobility, "walking_step_length", "WalkingStepLength", "m", "Walking Step Length"),
        q(.mobility, "walking_double_support", "WalkingDoubleSupportPercentage", "%", "Double Support Time"),
        q(.mobility, "walking_asymmetry", "WalkingAsymmetryPercentage", "%", "Walking Asymmetry"),
        q(.mobility, "stair_ascent_speed", "StairAscentSpeed", "m/s", "Stair Ascent Speed"),
        q(.mobility, "stair_descent_speed", "StairDescentSpeed", "m/s", "Stair Descent Speed"),
        q(.mobility, "six_minute_walk", "SixMinuteWalkTestDistance", "m", "Six-Minute Walk Distance"),
        q(.mobility, "walking_steadiness", "AppleWalkingSteadiness", "%", "Walking Steadiness"),
        q(.mobility, "running_speed", "RunningSpeed", "m/s", "Running Speed"),
        q(.mobility, "running_stride_length", "RunningStrideLength", "m", "Running Stride Length"),
        q(.mobility, "running_ground_contact", "RunningGroundContactTime", "ms", "Ground Contact Time"),
        q(.mobility, "running_vertical_oscillation", "RunningVerticalOscillation", "cm", "Vertical Oscillation"),
        q(.mobility, "running_power", "RunningPower", "W", "Running Power"),

        c(.reproductiveHealth, "menstrual_flow", "MenstrualFlow", "Menstrual Flow"),
        c(.reproductiveHealth, "sexual_activity", "SexualActivity", "Sexual Activity"),
        c(.reproductiveHealth, "ovulation_test", "OvulationTestResult", "Ovulation Test"),
        c(.reproductiveHealth, "cervical_mucus", "CervicalMucusQuality", "Cervical Mucus Quality"),
        c(.reproductiveHealth, "intermenstrual_bleeding", "IntermenstrualBleeding", "Intermenstrual Bleeding"),
    ]

    static func entries(for group: ExportDetailGroup) -> [Entry] {
        entries.filter { $0.group == group }
    }

    static func entry(forHealthKitType type: String) -> Entry? {
        entries.first { $0.healthKitType == type }
    }

    /// A sample is retained only while one of its metrics is selected. Unknown types are dropped.
    static func isSelected(_ sample: DetailSample, enabledMetricIDs: Set<String>) -> Bool {
        guard let entry = entry(forHealthKitType: sample.healthKitType) else { return false }
        return entry.selectionMetricIDs.contains { enabledMetricIDs.contains($0) }
    }

    /// Stable category value strings. Raw values HealthKit adds later remain distinct
    /// (`raw_<n>`) instead of being folded into an existing value.
    static func categoryValueString(healthKitType: String, rawValue: Int) -> String {
        let mapping: [Int: String]
        switch healthKitType {
        case "HKCategoryTypeIdentifierAppleStandHour":
            mapping = [0: "stood", 1: "idle"]
        case "HKCategoryTypeIdentifierMenstrualFlow":
            mapping = [1: "unspecified", 2: "light", 3: "medium", 4: "heavy", 5: "none"]
        case "HKCategoryTypeIdentifierOvulationTestResult":
            mapping = [1: "negative", 2: "positive", 3: "indeterminate", 4: "estrogen_surge"]
        case "HKCategoryTypeIdentifierCervicalMucusQuality":
            mapping = [1: "dry", 2: "sticky", 3: "creamy", 4: "watery", 5: "egg_white"]
        case "HKCategoryTypeIdentifierSexualActivity",
             "HKCategoryTypeIdentifierIntermenstrualBleeding",
             "HKCategoryTypeIdentifierMindfulSession":
            mapping = [0: "not_applicable"]
        default:
            mapping = [:]
        }
        return mapping[rawValue] ?? "raw_\(rawValue)"
    }
}

nonisolated extension HealthData {
    /// True when writers must emit the apple-v12 header and `detailSamples`. Morning ends days
    /// never qualify (apple-v11 has no expansion arrays).
    var exportsAppleV12DetailExpansion: Bool {
        compatibilityDetailProfile == .appleV12 && timeContext.sleepDayAttribution != .morningEnds
    }

    func detailSamples(for group: ExportDetailGroup) -> [DetailSample] {
        switch group {
        case .activity: activity.detailSamples
        case .vitals: vitals.detailSamples
        case .body: body.detailSamples
        case .nutrition: nutrition.detailSamples
        case .mindfulness: mindfulness.detailSamples
        case .mobility: mobility.detailSamples
        case .reproductiveHealth: reproductiveHealth.detailSamples
        case .sleep, .heart, .workouts: []
        }
    }

    mutating func setDetailSamples(_ samples: [DetailSample], for group: ExportDetailGroup) {
        switch group {
        case .activity: activity.detailSamples = samples
        case .vitals: vitals.detailSamples = samples
        case .body: body.detailSamples = samples
        case .nutrition: nutrition.detailSamples = samples
        case .mindfulness: mindfulness.detailSamples = samples
        case .mobility: mobility.detailSamples = samples
        case .reproductiveHealth: reproductiveHealth.detailSamples = samples
        case .sleep, .heart, .workouts: break
        }
    }

    /// The apple-v8 projection of this day: no successor marker and no expansion samples.
    /// Daily notes, scoped notes and other v8-only consumers use it.
    func withoutDetailExpansion() -> HealthData {
        var copy = self
        copy.compatibilityDetailProfile = nil
        for group in ExportDetailGroup.appleV12ExpansionGroups {
            copy.setDetailSamples([], for: group)
        }
        copy.stripSleepStageSourceAttribution()
        return copy
    }

    /// Removes apple-v12 sleep-stage source attribution, keeping every stage interval.
    mutating func stripSleepStageSourceAttribution() {
        guard sleep.stages.contains(where: \.hasSourceAttribution) else { return }
        sleep.stages = sleep.stages.map { $0.withoutSourceAttribution() }
    }
}
