import AppIntents
import Foundation

/// Snapshot of a day's headline health metrics, returned from
/// `GetHealthSummaryForDateIntent`. Each field is exposed to Shortcuts as a
/// variable so users can pipe values into other actions (Notion, Slack,
/// LLM prompts, etc.) without going through the markdown vault.
struct HealthSummary: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Health Summary")
    }

    static var defaultQuery = HealthSummaryQuery()

    /// ISO yyyy-MM-dd of the day this summary covers — also used as the entity id.
    let id: String

    @Property(title: "Date")
    var date: Date

    @Property(title: "Steps")
    var steps: Int?

    @Property(title: "Active Calories (kcal)")
    var activeCalories: Double?

    @Property(title: "Exercise Minutes")
    var exerciseMinutes: Double?

    @Property(title: "Walking + Running Distance (m)")
    var walkingRunningDistanceMeters: Double?

    @Property(title: "Flights Climbed")
    var flightsClimbed: Int?

    @Property(title: "Sleep Hours")
    var sleepHours: Double?

    @Property(title: "Resting Heart Rate (bpm)")
    var restingHeartRate: Double?

    @Property(title: "Average Heart Rate (bpm)")
    var averageHeartRate: Double?

    @Property(title: "HRV (ms)")
    var hrv: Double?

    @Property(title: "Workouts")
    var workoutCount: Int

    var displayRepresentation: DisplayRepresentation {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let title = "Health Summary — \(formatter.string(from: date))"

        var bits: [String] = []
        if let s = steps { bits.append("\(s) steps") }
        if let c = activeCalories { bits.append("\(Int(c.rounded())) kcal") }
        if let h = sleepHours {
            let hours = Int(h)
            let minutes = Int((h - Double(hours)) * 60)
            bits.append("\(hours)h \(minutes)m sleep")
        }
        if let rhr = restingHeartRate { bits.append("\(Int(rhr.rounded())) bpm rest") }
        let subtitle: LocalizedStringResource? = bits.isEmpty
            ? "No data"
            : LocalizedStringResource(stringLiteral: bits.joined(separator: " · "))

        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: subtitle
        )
    }
}

/// HealthSummary entities are computed on demand and have no persistent
/// store — Shortcuts only ever sees them as return values, so the query
/// returns nothing.
struct HealthSummaryQuery: EntityQuery {
    func entities(for identifiers: [HealthSummary.ID]) async throws -> [HealthSummary] {
        []
    }
}

/// Returns a structured summary of a single day's health data without writing
/// to the vault. The returned entity exposes individual metrics as Shortcut
/// variables (steps, sleep hours, resting heart rate, etc.) for downstream
/// composition.
struct GetHealthSummaryForDateIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Health Summary for a Date"

    static var description = IntentDescription(
        "Returns a snapshot of a day's headline health metrics — steps, active calories, sleep, heart rate, and more — without writing to your vault.",
        categoryName: "Health"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Date",
        description: "The day to summarize. Time-of-day is ignored."
    )
    var date: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Get health summary for \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<HealthSummary> & ProvidesDialog {
        let day = Calendar.current.startOfDay(for: date)

        let healthData: HealthData
        do {
            healthData = try await HealthKitManager.shared.fetchHealthData(for: day, includeGranularData: false)
        } catch {
            throw $date.needsValueError("Couldn't read health data: \(error.localizedDescription)")
        }

        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"

        let summary = HealthSummary(id: isoFormatter.string(from: day))
        summary.date = day
        summary.steps = healthData.activity.steps
        summary.activeCalories = healthData.activity.activeCalories
        summary.exerciseMinutes = healthData.activity.exerciseMinutes
        summary.walkingRunningDistanceMeters = healthData.activity.walkingRunningDistance
        summary.flightsClimbed = healthData.activity.flightsClimbed
        summary.sleepHours = healthData.sleep.totalDuration > 0
            ? healthData.sleep.totalDuration / 3600
            : nil
        summary.restingHeartRate = healthData.heart.restingHeartRate
        summary.averageHeartRate = healthData.heart.averageHeartRate
        summary.hrv = healthData.heart.hrv
        summary.workoutCount = healthData.workouts.count

        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary.dialogString()))
    }
}

private extension HealthSummary {
    init(id: String) {
        self.id = id
        self.date = Date()
        self.steps = nil
        self.activeCalories = nil
        self.exerciseMinutes = nil
        self.walkingRunningDistanceMeters = nil
        self.flightsClimbed = nil
        self.sleepHours = nil
        self.restingHeartRate = nil
        self.averageHeartRate = nil
        self.hrv = nil
        self.workoutCount = 0
    }

    func dialogString() -> String {
        var parts: [String] = []
        if let s = steps { parts.append("\(s) steps") }
        if let c = activeCalories { parts.append("\(Int(c.rounded())) active kcal") }
        if let h = sleepHours, h > 0 {
            let hours = Int(h)
            let minutes = Int((h - Double(hours)) * 60)
            parts.append("\(hours)h \(minutes)m sleep")
        }
        if let rhr = restingHeartRate { parts.append("\(Int(rhr.rounded())) bpm resting HR") }
        if workoutCount > 0 {
            parts.append(workoutCount == 1 ? "1 workout" : "\(workoutCount) workouts")
        }
        return parts.isEmpty
            ? "No health data for that day."
            : parts.joined(separator: ", ") + "."
    }
}
