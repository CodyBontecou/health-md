import Foundation

/// The watch dashboard's metric rows, in display order. Kept free of SwiftUI so the row set and
/// value formatting are unit-testable; the view maps `id` to its tint.
enum WatchDashboardMetric: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case heartRateVariability
    case restingHeartRate
    case steps
    case activeEnergy
    case exerciseMinutes
    case standHours
    case bloodOxygen

    var id: String { rawValue }

    /// Localization key of the row title. The watch target ships its own string catalog
    /// (HealthMdWatch/Localizable.xcstrings), so each key must exist there.
    var titleKey: String {
        switch self {
        case .sleep: return "Sleep"
        case .heartRateVariability: return "HRV"
        case .restingHeartRate: return "Resting HR"
        case .steps: return "Steps"
        case .activeEnergy: return "Active energy"
        case .exerciseMinutes: return "Exercise"
        case .standHours: return "Stand"
        case .bloodOxygen: return "Blood oxygen"
        }
    }

    func value(in snapshot: WatchHealthSnapshot) -> String {
        switch self {
        case .sleep:
            return WatchDashboardFormat.hoursMinutes(snapshot.sleepHours)
        case .heartRateVariability:
            return WatchHealthFormatter.milliseconds(snapshot.heartRateVariabilityMS)
        case .restingHeartRate:
            return WatchHealthFormatter.wholeNumber(snapshot.restingHeartRate)
        case .steps:
            return WatchHealthFormatter.wholeNumber(snapshot.steps)
        case .activeEnergy:
            return WatchDashboardFormat.withUnit(snapshot.activeEnergyKilocalories, unit: "kcal")
        case .exerciseMinutes:
            return WatchDashboardFormat.withUnit(snapshot.exerciseMinutes, unit: "min")
        case .standHours:
            return WatchHealthFormatter.standHours(snapshot.standHours)
        case .bloodOxygen:
            return WatchHealthFormatter.percent(snapshot.bloodOxygenPercent)
        }
    }
}

enum WatchDashboardFormat {
    /// "7h 12m" as on WatchDashboardG; "—" when there is no sleep.
    static func hoursMinutes(_ hours: Double?) -> String {
        guard let hours, hours > 0 else { return "—" }
        let totalMinutes = Int((hours * 60).rounded())
        let wholeHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return wholeHours == 0 ? "\(minutes)m" : "\(wholeHours)h \(minutes)m"
    }

    /// "410 kcal" / "32 min"; "—" alone when the value is missing (3.5 showed "— kcal").
    static func withUnit(_ value: Double?, unit: String) -> String {
        guard value != nil else { return "—" }
        return "\(WatchHealthFormatter.wholeNumber(value)) \(unit)"
    }
}
