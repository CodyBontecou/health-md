import Foundation

enum ScheduledExportKind: String, Codable, Equatable, CaseIterable {
    case completedDay = "completed-day"
    case todayRefresh = "today-refresh"
}

/// Represents the configuration for scheduled health data exports
struct ExportSchedule: Codable, Equatable {
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

    /// Ends each completed-day run on the fire date instead of the day before. The window
    /// keeps its size, and today's data is partial until the day ends. Off unless requested.
    var includeToday: Bool

    /// Whether to also refresh today's file during the current day.
    var todayRefreshEnabled: Bool

    /// Shipped hour-only field. Local v2 minute intent takes precedence; iOS may delay runs.
    var todayRefreshIntervalHours: Int {
        didSet {
            todayRefreshIntervalHours = Self.clampedTodayRefreshIntervalHours(todayRefreshIntervalHours)
        }
    }

    /// Local persistence v2; nil keeps the shipped integer-hour representation.
    var todayRefreshIntervalMinutes: Int?
    var todayRefreshMinutes: Int {
        get { todayRefreshIntervalMinutes ?? todayRefreshIntervalHours * 60 }
        set {
            let minutes = Self.todayRefreshMinuteOptions.contains(newValue) ? newValue : 180
            todayRefreshIntervalMinutes = minutes < 180 ? minutes : nil
            if minutes >= 180 { todayRefreshIntervalHours = minutes / 60 }
        }
    }
    static let todayRefreshMinuteOptions = [30, 60, 180, 360, 720]
    static func todayRefreshLabel(_ minutes: Int) -> String {
        minutes < 60 ? String(localized: "Every \(minutes) minutes")
            : (minutes == 60 ? String(localized: "Every hour") : String(localized: "Every \(minutes / 60) hours"))
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
        includeToday: Bool = false,
        todayRefreshEnabled: Bool = false,
        todayRefreshIntervalHours: Int = Self.defaultTodayRefreshIntervalHours,
        todayRefreshIntervalMinutes: Int? = nil,
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
        self.includeToday = includeToday
        self.todayRefreshEnabled = todayRefreshEnabled
        self.todayRefreshIntervalHours = Self.clampedTodayRefreshIntervalHours(todayRefreshIntervalHours)
        self.todayRefreshIntervalMinutes = todayRefreshIntervalMinutes
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
        case includeToday
        case todayRefreshEnabled
        case todayRefreshIntervalHours
        case todayRefreshIntervalMinutes, todayRefreshRequestedV2, todayRefreshPersistenceVersion
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
        self.includeToday = try c.decodeIfPresent(Bool.self, forKey: .includeToday) ?? false
        self.todayRefreshEnabled = try c.decodeIfPresent(Bool.self, forKey: .todayRefreshEnabled) ?? false
        let decodedTodayRefreshIntervalHours = try c.decodeIfPresent(Int.self, forKey: .todayRefreshIntervalHours)
        self.todayRefreshIntervalHours = Self.clampedTodayRefreshIntervalHours(decodedTodayRefreshIntervalHours ?? Self.defaultTodayRefreshIntervalHours)
        self.todayRefreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .todayRefreshIntervalMinutes)
        if let minutes = todayRefreshIntervalMinutes {
            guard [30, 60].contains(minutes) else {
                throw DecodingError.dataCorruptedError(forKey: .todayRefreshIntervalMinutes, in: c, debugDescription: "Unsupported Today Refresh minute interval")
            }
            self.todayRefreshEnabled = try c.decodeIfPresent(Int.self, forKey: .todayRefreshPersistenceVersion) == 2
                && (c.decodeIfPresent(Bool.self, forKey: .todayRefreshRequestedV2) ?? false)
        }
        self.lastExportDate = try c.decodeIfPresent(Date.self, forKey: .lastExportDate)
        self.lastTodayRefreshDate = try c.decodeIfPresent(Date.self, forKey: .lastTodayRefreshDate)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(enabledAt, forKey: .enabledAt)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(customInterval, forKey: .customInterval)
        try c.encode(customUnit, forKey: .customUnit)
        try c.encode(customAnchorDate, forKey: .customAnchorDate)
        try c.encode(preferredHour, forKey: .preferredHour)
        try c.encode(preferredMinute, forKey: .preferredMinute)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(target, forKey: .target)
        try c.encode(lookbackDays, forKey: .lookbackDays)
        try c.encode(includeToday, forKey: .includeToday)
        try c.encode(todayRefreshIntervalHours, forKey: .todayRefreshIntervalHours)
        try c.encode(lastExportDate, forKey: .lastExportDate)
        try c.encode(lastTodayRefreshDate, forKey: .lastTodayRefreshDate)
        try c.encode(2, forKey: .todayRefreshPersistenceVersion)
        try c.encode(todayRefreshIntervalMinutes == nil ? todayRefreshEnabled : false, forKey: .todayRefreshEnabled)
        try c.encode(todayRefreshIntervalMinutes, forKey: .todayRefreshIntervalMinutes)
        try c.encode(todayRefreshIntervalMinutes.map { _ in todayRefreshEnabled }, forKey: .todayRefreshRequestedV2)
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
        switch self {
        case .daily: return String(localized: "Daily", comment: "Scheduled export frequency")
        case .weekly: return String(localized: "Weekly", comment: "Scheduled export frequency")
        case .custom: return String(localized: "Custom", comment: "Scheduled export frequency")
        }
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
    func save(userDefaults: UserDefaults = .standard) {
        if let encoded = try? JSONEncoder().encode(self) {
            userDefaults.set(todayRefreshIntervalMinutes, forKey: "exportSchedule.minuteIntent.v2")
            userDefaults.set(encoded, forKey: Self.scheduleKey)
        }
    }

    /// Loads the schedule from UserDefaults
    static func load(userDefaults: UserDefaults = .standard) -> ExportSchedule {
        guard let data = userDefaults.data(forKey: scheduleKey),
              let decoded = try? JSONDecoder().decode(ExportSchedule.self, from: data) else {
            return ExportSchedule()
        }
        var schedule = decoded
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["todayRefreshPersistenceVersion"] == nil, !schedule.todayRefreshEnabled,
           let minutes = userDefaults.object(forKey: "exportSchedule.minuteIntent.v2") as? Int,
           [30, 60].contains(minutes) {
            // An older writer disabled refresh and dropped unknown v2 fields. Retain the choice,
            // but never restore activation after a downgrade edit/disable round trip.
            schedule.todayRefreshIntervalMinutes = minutes
        }
        return schedule
    }

    /// Updates the logical completed-day occurrence that most recently
    /// succeeded and saves. Automatic runners pass the scheduled fire date so
    /// a delayed run does not make later catch-up logic skip unexported days.
    mutating func updateLastExport(at occurrenceDate: Date = Date()) {
        self.lastExportDate = occurrenceDate
        self.save()
    }
}
