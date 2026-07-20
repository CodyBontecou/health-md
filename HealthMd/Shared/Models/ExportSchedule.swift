import Foundation

enum ScheduledExportKind: String, Codable, Equatable, CaseIterable {
    case completedDay = "completed-day"
    case todayRefresh = "today-refresh"
}

/// Represents the configuration for scheduled health data exports
struct ExportSchedule: Codable {
    /// Whether scheduled exports are enabled
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            enabledAt = isEnabled ? Date() : nil
        }
    }

    /// When the current enabled period began. Automatic runners use this to
    /// avoid treating an occurrence that was already missed before the user
    /// enabled scheduling as immediately due.
    var enabledAt: Date?

    /// The frequency of scheduled completed-day exports.
    var frequency: ScheduleFrequency

    /// Number of calendar units between custom scheduled exports.
    var customInterval: Int {
        didSet {
            customInterval = Self.clampedCustomInterval(customInterval)
        }
    }

    /// Calendar unit used by a custom scheduled export cadence.
    var customUnit: ScheduleIntervalUnit

    /// Calendar day that establishes the phase for a custom cadence.
    /// Its time component is ignored in favor of `preferredHour` and
    /// `preferredMinute`.
    var customAnchorDate: Date

    /// The preferred time of day for exports (hour in 24-hour format).
    var preferredHour: Int

    /// The preferred minute for exports (0-59).
    var preferredMinute: Int

    /// ISO weekday for weekly schedules (1 = Monday … 7 = Sunday).
    /// Ignored for daily schedules. Defaults to Monday so legacy persisted
    /// schedules without this field decode cleanly.
    var weekday: Int

    /// Destination used by scheduled exports. Legacy persisted schedules decode
    /// as local iPhone-folder exports to preserve existing behavior.
    var target: ExportTargetSelection

    /// Number of past days to include in each completed-day scheduled export.
    /// For example, 1 exports yesterday only; 2 exports yesterday + the day before.
    var lookbackDays: Int {
        didSet {
            lookbackDays = Self.clampedLookbackDays(lookbackDays)
        }
    }

    /// Whether to also refresh today's file during the current day.
    var todayRefreshEnabled: Bool

    /// Best-effort same-day refresh interval in hours. iOS may delay execution.
    var todayRefreshIntervalHours: Int {
        didSet {
            todayRefreshIntervalHours = Self.clampedTodayRefreshIntervalHours(todayRefreshIntervalHours)
        }
    }

    /// The date of the last successful completed-day export.
    var lastExportDate: Date?

    /// The scheduled fire date of the last successful Today Refresh export.
    var lastTodayRefreshDate: Date?

    static let minimumLookbackDays = 1
    static let maximumLookbackDays = 30
    static let minimumCustomInterval = 1
    static let maximumCustomInterval = 365
    static let todayRefreshIntervalOptions = [3, 6, 12]
    static let defaultTodayRefreshIntervalHours = 3

    static func defaultLookbackDays(
        for frequency: ScheduleFrequency,
        customInterval: Int = 1,
        customUnit: ScheduleIntervalUnit = .day
    ) -> Int {
        switch frequency {
        case .daily:
            return 1
        case .weekly:
            return 7
        case .custom:
            let interval = clampedCustomInterval(customInterval)
            return clampedLookbackDays(interval * customUnit.nominalDayCount)
        }
    }

    static func clampedLookbackDays(_ days: Int) -> Int {
        min(max(Self.minimumLookbackDays, days), Self.maximumLookbackDays)
    }

    static func clampedCustomInterval(_ interval: Int) -> Int {
        min(max(Self.minimumCustomInterval, interval), Self.maximumCustomInterval)
    }

    static func clampedTodayRefreshIntervalHours(_ hours: Int) -> Int {
        if Self.todayRefreshIntervalOptions.contains(hours) { return hours }
        return Self.todayRefreshIntervalOptions.min { lhs, rhs in
            abs(lhs - hours) < abs(rhs - hours)
        } ?? Self.defaultTodayRefreshIntervalHours
    }

    init(
        isEnabled: Bool = false,
        frequency: ScheduleFrequency = .daily,
        customInterval: Int = 1,
        customUnit: ScheduleIntervalUnit = .day,
        customAnchorDate: Date = Date(),
        preferredHour: Int = 8,
        preferredMinute: Int = 0,
        weekday: Int = 1,
        target: ExportTargetSelection = .localIPhoneFolder,
        lookbackDays: Int? = nil,
        todayRefreshEnabled: Bool = false,
        todayRefreshIntervalHours: Int = Self.defaultTodayRefreshIntervalHours,
        lastExportDate: Date? = nil,
        lastTodayRefreshDate: Date? = nil,
        enabledAt: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.enabledAt = enabledAt
        self.frequency = frequency
        self.customInterval = Self.clampedCustomInterval(customInterval)
        self.customUnit = customUnit
        self.customAnchorDate = customAnchorDate
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.weekday = weekday
        self.target = target
        self.lookbackDays = Self.clampedLookbackDays(
            lookbackDays ?? Self.defaultLookbackDays(
                for: frequency,
                customInterval: customInterval,
                customUnit: customUnit
            )
        )
        self.todayRefreshEnabled = todayRefreshEnabled
        self.todayRefreshIntervalHours = Self.clampedTodayRefreshIntervalHours(todayRefreshIntervalHours)
        self.lastExportDate = lastExportDate
        self.lastTodayRefreshDate = lastTodayRefreshDate
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case enabledAt
        case frequency
        case customInterval
        case customUnit
        case customAnchorDate
        case preferredHour
        case preferredMinute
        case weekday
        case target
        case lookbackDays
        case todayRefreshEnabled
        case todayRefreshIntervalHours
        case lastExportDate
        case lastTodayRefreshDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        self.enabledAt = try c.decodeIfPresent(Date.self, forKey: .enabledAt)
        self.frequency = try c.decode(ScheduleFrequency.self, forKey: .frequency)
        let decodedCustomInterval = try c.decodeIfPresent(Int.self, forKey: .customInterval) ?? 1
        self.customInterval = Self.clampedCustomInterval(decodedCustomInterval)
        self.customUnit = try c.decodeIfPresent(ScheduleIntervalUnit.self, forKey: .customUnit) ?? .day
        self.customAnchorDate = try c.decodeIfPresent(Date.self, forKey: .customAnchorDate)
            ?? self.enabledAt
            ?? Date()
        self.preferredHour = try c.decode(Int.self, forKey: .preferredHour)
        self.preferredMinute = try c.decode(Int.self, forKey: .preferredMinute)
        self.weekday = try c.decodeIfPresent(Int.self, forKey: .weekday) ?? 1
        self.target = try c.decodeIfPresent(ExportTargetSelection.self, forKey: .target) ?? .localIPhoneFolder
        let decodedLookbackDays = try c.decodeIfPresent(Int.self, forKey: .lookbackDays)
        self.lookbackDays = Self.clampedLookbackDays(
            decodedLookbackDays ?? Self.defaultLookbackDays(
                for: frequency,
                customInterval: customInterval,
                customUnit: customUnit
            )
        )
        self.todayRefreshEnabled = try c.decodeIfPresent(Bool.self, forKey: .todayRefreshEnabled) ?? false
        let decodedTodayRefreshIntervalHours = try c.decodeIfPresent(Int.self, forKey: .todayRefreshIntervalHours)
        self.todayRefreshIntervalHours = Self.clampedTodayRefreshIntervalHours(decodedTodayRefreshIntervalHours ?? Self.defaultTodayRefreshIntervalHours)
        self.lastExportDate = try c.decodeIfPresent(Date.self, forKey: .lastExportDate)
        self.lastTodayRefreshDate = try c.decodeIfPresent(Date.self, forKey: .lastTodayRefreshDate)
    }
}

/// Calendar units available for a custom scheduled export cadence.
enum ScheduleIntervalUnit: String, Codable, CaseIterable {
    case day
    case week
    case month

    var nominalDayCount: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }

    func label(for interval: Int) -> String {
        let singular: String
        switch self {
        case .day: singular = "day"
        case .week: singular = "week"
        case .month: singular = "month"
        }
        return interval == 1 ? singular : "\(singular)s"
    }
}

/// Frequency options for scheduled exports.
enum ScheduleFrequency: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case custom = "Custom"

    var description: String {
        self.rawValue
    }

    /// Returns the fixed interval in seconds for built-in frequencies.
    /// Custom cadences use calendar-aware values stored on `ExportSchedule`,
    /// so they do not have a single fixed-duration interval.
    var interval: TimeInterval {
        switch self {
        case .daily:
            return 24 * 60 * 60 // 24 hours
        case .weekly:
            return 7 * 24 * 60 * 60 // 7 days
        case .custom:
            return 0
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

    /// Updates the logical completed-day occurrence that most recently
    /// succeeded and saves. Automatic runners pass the scheduled fire date so
    /// a delayed run does not make later catch-up logic skip unexported days.
    mutating func updateLastExport(at occurrenceDate: Date = Date()) {
        self.lastExportDate = occurrenceDate
        self.save()
    }
}
