import Foundation

/// Onboarding's "What goes in your daily note?" packs.
///
/// Packs replace the full metric picker during first-run setup: each one maps to a
/// small, curated set of real metric IDs from `HealthMetrics.all`. Pack IDs are
/// shared with Android (`sleep`, `activity`, `heart`, `body`, `mind`, `nutrition`,
/// `cycle`); the member metrics are platform-specific because HealthKit and Health
/// Connect expose different record types (for example HealthKit HRV is SDNN and
/// Android's is RMSSD, and State of Mind exists only on Apple).
enum OnboardingMetricPack: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case activity
    case heart
    case body
    case mind
    case nutrition
    case cycle

    var id: String { rawValue }

    /// Sleep & Recovery, Activity, and Heart are preselected; Cycle Tracking is
    /// sensitive and always opt-in.
    static let defaultSelection: Set<OnboardingMetricPack> = [.sleep, .activity, .heart]

    var title: String {
        switch self {
        case .sleep: return String(localized: "Sleep & Recovery", comment: "Onboarding metric pack")
        case .activity: return String(localized: "Activity", comment: "Onboarding metric pack")
        case .heart: return String(localized: "Heart", comment: "Onboarding metric pack")
        case .body: return String(localized: "Body", comment: "Onboarding metric pack")
        case .mind: return String(localized: "Mind", comment: "Onboarding metric pack")
        case .nutrition: return String(localized: "Nutrition", comment: "Onboarding metric pack")
        case .cycle: return String(localized: "Cycle Tracking", comment: "Onboarding metric pack")
        }
    }

    var sample: String {
        switch self {
        case .sleep: return String(localized: "Stages, bedtime, HRV, resting HR", comment: "Onboarding metric pack contents")
        case .activity: return String(localized: "Steps, energy, exercise, workouts", comment: "Onboarding metric pack contents")
        case .heart: return String(localized: "Heart rate, blood oxygen, pressure", comment: "Onboarding metric pack contents")
        case .body: return String(localized: "Weight, body fat, BMI, lean mass", comment: "Onboarding metric pack contents")
        case .mind: return String(localized: "Mindful minutes, state of mind", comment: "Onboarding metric pack contents")
        case .nutrition: return String(localized: "Calories, macros, water, caffeine", comment: "Onboarding metric pack contents")
        case .cycle: return String(localized: "Period, ovulation. Off by default", comment: "Onboarding metric pack contents")
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.fill"
        case .activity: return "bolt.fill"
        case .heart: return "heart.text.square.fill"
        case .body: return "scalemass.fill"
        case .mind: return "brain.head.profile"
        case .nutrition: return "fork.knife"
        case .cycle: return "drop.fill"
        }
    }

    /// Candidate metric IDs, in note order. Filtered by `metricIDs` to what this
    /// build and OS can actually read.
    var candidateMetricIDs: [String] {
        switch self {
        case .sleep:
            return ["sleep_total", "sleep_bedtime", "sleep_wake", "sleep_deep", "sleep_rem",
                    "sleep_core", "sleep_awake", "sleep_in_bed", "hrv", "resting_heart_rate",
                    "respiratory_rate", "wrist_temperature"]
        case .activity:
            return ["steps", "active_energy", "basal_energy", "exercise_time", "stand_hours",
                    "flights_climbed", "distance_walking_running", "workouts", "vo2_max"]
        case .heart:
            return ["heart_rate_avg", "heart_rate_min", "heart_rate_max", "walking_heart_rate",
                    "blood_oxygen", "blood_pressure_systolic", "blood_pressure_diastolic"]
        case .body:
            return ["weight", "body_fat", "bmi", "lean_body_mass", "height"]
        case .mind:
            return ["mindful_minutes", "mindful_sessions", "state_of_mind_entries"]
        case .nutrition:
            return ["dietary_energy", "dietary_protein", "dietary_carbs", "dietary_fat",
                    "dietary_fiber", "dietary_sugar", "dietary_water", "dietary_caffeine"]
        case .cycle:
            return ["menstrual_flow", "ovulation_test", "cervical_mucus",
                    "basal_body_temperature", "intermenstrual_bleeding"]
        }
    }

    /// Metric IDs that exist in the catalog and are readable on this platform.
    var metricIDs: [String] {
        let available = Self.availableMetricIDs
        return candidateMetricIDs.filter { available.contains($0) }
    }

    var metricCount: Int { metricIDs.count }

    private static let availableMetricIDs: Set<String> = Set(
        HealthMetrics.all
            .filter { !$0.isPendingAppleApproval && $0.availability.isAvailableOnCurrentPlatform }
            .map(\.id)
    )

    /// Union of the selected packs' metric IDs.
    static func metricIDs(for packs: Set<OnboardingMetricPack>) -> Set<String> {
        Set(packs.flatMap(\.metricIDs))
    }

    /// Packs fully covered by an existing selection, so replaying onboarding shows
    /// what is already exported instead of resetting to the defaults.
    static func packs(coveredBy enabledMetricIDs: Set<String>) -> Set<OnboardingMetricPack> {
        Set(allCases.filter { pack in
            let ids = pack.metricIDs
            return !ids.isEmpty && Set(ids).isSubset(of: enabledMetricIDs)
        })
    }

    /// Replaces the selection with exactly the packs' metrics. Everything outside
    /// the packs is switched off so the permission request and the first note match
    /// what the user picked; more can be added from Automations later.
    @MainActor
    static func apply(_ packs: Set<OnboardingMetricPack>, to selection: MetricSelectionState) {
        let wanted = metricIDs(for: packs)
        for metric in HealthMetrics.all where selection.enabledMetrics.contains(metric.id) && !wanted.contains(metric.id) {
            selection.setMetric(metric.id, enabled: false)
        }
        for id in wanted.sorted() {
            selection.setMetric(id, enabled: true)
        }
    }
}
