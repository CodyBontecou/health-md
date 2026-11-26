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

    /// The Workouts group owns the workout block: `workouts` and every `workout_*` key, which
    /// includes the structured `workout_details` block. A rule rather than a list, as on Android, so
    /// a new workout field joins it without an edit here.
    ///
    /// Each record in the block holds every workout property (calories, heart rate, distance, …),
    /// so the block shows only while *every* Workouts field is on (#465). A customized Workouts
    /// group writes exactly the fields switched on and no record block with the others.
    static func isWorkoutField(_ key: String) -> Bool { key == "workouts" || key.hasPrefix("workout_") }

    static func showsQuantity(field: String, _ isEnabled: (String) -> Bool) -> Bool {
        (quantity[field] ?? []).contains(where: isEnabled)
    }

    static func showsSleepStage(_ stage: String, _ isEnabled: (String) -> Bool) -> Bool {
        sleepStage[stage].map(isEnabled) ?? false
    }

    static func showsCorrelation(_ isEnabled: (String) -> Bool) -> Bool { correlation.allSatisfy(isEnabled) }
    static func showsMindfulness(_ isEnabled: (String) -> Bool) -> Bool { mindfulness.contains(where: isEnabled) }
    /// `fieldKeys` are the keys Format → Custom lists (see `FrontmatterConfiguration.nativeOwnerCandidateKeys`).
    static func showsWorkouts(fieldKeys: [String], _ isEnabled: (String) -> Bool) -> Bool {
        let workoutKeys = fieldKeys.filter(isWorkoutField)
        return !workoutKeys.isEmpty && workoutKeys.allSatisfy(isEnabled)
    }
}

extension FrontmatterConfiguration {
    /// Every key Format → Custom lists for this configuration, including defaults an older saved
    /// configuration lacks (those read as switched on).
    var nativeOwnerCandidateKeys: [String] {
        fields.map(\.originalKey) + Self.defaultFields.map(\.originalKey)
    }

    /// Whether per-workout record blocks (`workout_details`, `native_workout_details`) may enter
    /// frontmatter: only while every Workouts field is on (#465).
    var writesWorkoutRecordBlocks: Bool {
        WakeDateNativeFrontmatterOwners.showsWorkouts(fieldKeys: nativeOwnerCandidateKeys, isFieldEnabled)
    }
}
