import Foundation

/// Represents the configuration for scheduled health data exports
struct ExportSchedule: Codable {
    /// Whether scheduled exports are enabled
    var isEnabled: Bool

    /// The frequency of scheduled exports
    var frequency: ScheduleFrequency

    /// The preferred time of day for exports (hour in 24-hour format)
    var preferredHour: Int

    /// The preferred minute for exports (0-59)
    var preferredMinute: Int

    /// The date of the last successful export
    var lastExportDate: Date?

    init(
        isEnabled: Bool = false,
        frequency: ScheduleFrequency = .daily,
        preferredHour: Int = 8,
        preferredMinute: Int = 0,
        lastExportDate: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.lastExportDate = lastExportDate
    }
}

/// Frequency options for scheduled exports
enum ScheduleFrequency: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"

    var description: String {
        self.rawValue
    }

    /// Returns the time interval in seconds for this frequency
    var interval: TimeInterval {
        switch self {
        case .daily:
            return 24 * 60 * 60 // 24 hours
        case .weekly:
            return 7 * 24 * 60 * 60 // 7 days
        }
    }
}

// MARK: - UserDefaults Extension
extension ExportSchedule {
    private static let scheduleKey = "exportSchedule"

    /// Saves the schedule to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.scheduleKey)
        }
    }

    /// Loads the schedule from UserDefaults
    static func load() -> ExportSchedule {
        guard let data = UserDefaults.standard.data(forKey: scheduleKey),
              let decoded = try? JSONDecoder().decode(ExportSchedule.self, from: data) else {
            return ExportSchedule()
        }
        return decoded
    }

    /// Updates the last export date and saves
    mutating func updateLastExport() {
        self.lastExportDate = Date()
        self.save()
    }
}
