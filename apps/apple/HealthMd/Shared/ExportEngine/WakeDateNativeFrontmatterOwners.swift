import Foundation

/// Format → Custom fields that own each "Morning ends" native Bases frontmatter block (#353).
///
/// Native records stay in JSON, CSV and the Markdown body. A record's lines go into Bases
/// frontmatter only while at least one field that owns it is switched on (a blood pressure
/// pair needs both). Android applies the same rule in `HealthMdRenderInputAdapter.kt`.
nonisolated enum WakeDateNativeFrontmatterOwners {
    /// Quantity sample arrays, keyed by their JSON field, and the fields that own them.
    static let quantity: [String: [String]] = [
        "heartRateSamples": ["average_heart_rate", "heart_rate_min", "heart_rate_max"],
        "hrvSamples": ["hrv_ms"],
        "bloodOxygenSamples": ["blood_oxygen", "blood_oxygen_avg", "blood_oxygen_min", "blood_oxygen_max"],
        "bloodGlucoseSamples": ["blood_glucose", "blood_glucose_avg", "blood_glucose_min", "blood_glucose_max"],
        "respiratoryRateSamples": ["respiratory_rate", "respiratory_rate_avg", "respiratory_rate_min", "respiratory_rate_max"],
    ]

    /// Sleep stage names and the field that owns each.
    static let sleepStage: [String: String] = [
        "deep": "sleep_deep_hours", "rem": "sleep_rem_hours", "core": "sleep_core_hours",
        "awake": "sleep_awake_hours", "inBed": "sleep_in_bed_hours", "unspecified": "sleep_total_hours",
    ]

    /// Both halves of a blood pressure pair must be on.
    static let correlation = ["blood_pressure_systolic", "blood_pressure_diastolic"]

    static let mindfulness = ["mood_entries", "mood_labels", "mood_associations"]

    /// Every field in the Workouts group: the "workouts" metric's mapped keys (pinned to
    /// `HealthMetricExportMapping` by a test) plus the structured `workout_details` block.
    static let workouts: [String] = [
        "workout_count", "workout_minutes", "workout_calories", "workout_distance_km", "workout_distance_mi",
        "workouts", "workout_avg_heart_rate", "workout_max_heart_rate", "workout_min_heart_rate",
        "workout_running_cadence", "workout_running_stride_length", "workout_running_ground_contact",
        "workout_running_vertical_oscillation", "workout_cycling_cadence", "workout_avg_power", "workout_max_power",
        "workout_details",
    ]

    static func showsQuantity(field: String, _ isEnabled: (String) -> Bool) -> Bool {
        (quantity[field] ?? []).contains(where: isEnabled)
    }

    static func showsSleepStage(_ stage: String, _ isEnabled: (String) -> Bool) -> Bool {
        sleepStage[stage].map(isEnabled) ?? false
    }

    static func showsCorrelation(_ isEnabled: (String) -> Bool) -> Bool { correlation.allSatisfy(isEnabled) }
    static func showsMindfulness(_ isEnabled: (String) -> Bool) -> Bool { mindfulness.contains(where: isEnabled) }
    static func showsWorkouts(_ isEnabled: (String) -> Bool) -> Bool { workouts.contains(where: isEnabled) }
}
