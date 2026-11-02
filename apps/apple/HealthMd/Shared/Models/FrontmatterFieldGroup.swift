import Foundation

/// Display groups for frontmatter fields, used by the format customization screens.
/// Grouping is presentation only: it never changes which keys are written.
enum FrontmatterFieldGroup: String, CaseIterable, Identifiable, Sendable {
    case sleep, activity, heart, vitals, body, nutrition, mindfulness, mobility, hearing, workouts
    case medications, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return String(localized: "Sleep")
        case .activity: return String(localized: "Activity")
        case .heart: return String(localized: "Heart")
        case .vitals: return String(localized: "Vitals")
        case .body: return String(localized: "Body")
        case .nutrition: return String(localized: "Nutrition")
        case .mindfulness: return String(localized: "Mindfulness")
        case .mobility: return String(localized: "Mobility")
        case .hearing: return String(localized: "Hearing")
        case .workouts: return String(localized: "Workouts")
        case .medications: return String(localized: "Medications")
        case .other: return String(localized: "Other")
        }
    }

    /// Key prefixes per group. Medications match first so `active_medication_count`
    /// is not claimed by Activity's `active_` prefix.
    private static let matchOrder: [(FrontmatterFieldGroup, [String])] = [
        (.medications, ["medication", "active_medication", "archived_medication"]),
        (.sleep, ["sleep_"]),
        (.workouts, ["workout"]),
        (.activity, ["steps", "active_", "basal_", "exercise_", "stand_", "flights_", "walking_running",
                     "cycling", "swimming", "wheelchair", "vo2"]),
        (.heart, ["resting_heart", "walking_heart", "average_heart", "heart_rate", "hrv"]),
        (.vitals, ["respiratory", "blood_oxygen", "body_temperature", "blood_pressure", "blood_glucose"]),
        (.body, ["weight", "height", "bmi", "body_fat", "lean_body", "waist"]),
        (.nutrition, ["dietary", "protein", "carbohydrates", "fat", "saturated", "fiber", "sugar", "sodium",
                      "cholesterol", "water", "caffeine"]),
        (.mindfulness, ["mindful", "mood_", "average_mood", "daily_mood", "momentary_emotion"]),
        (.mobility, ["walking_speed", "step_length", "double_support", "walking_asymmetry", "stair_", "six_min"]),
        (.hearing, ["headphone", "environmental"])
    ]

    static func group(for originalKey: String) -> FrontmatterFieldGroup {
        matchOrder.first { _, prefixes in prefixes.contains { originalKey.hasPrefix($0) } }?.0 ?? .other
    }

    /// Non-empty groups in display order, each keeping the configuration's field order.
    static func grouped(_ fields: [CustomFrontmatterField]) -> [(group: FrontmatterFieldGroup, fields: [CustomFrontmatterField])] {
        let buckets = Dictionary(grouping: fields) { group(for: $0.originalKey) }
        return allCases.compactMap { group in
            guard let fields = buckets[group], !fields.isEmpty else { return nil }
            return (group, fields)
        }
    }
}
