import Foundation
import Combine

/// One scheduled-export configuration bound to exactly one export profile.
///
/// Phase 3 model (see `docs/features/export-profiles.md`): entries carry the
/// same cadence fields as the legacy single `ExportSchedule`, plus per-entry
/// progress state so occurrence math (`enabledAt` gating, last-success
/// tracking) works independently per profile. All date math is delegated to
/// `ScheduleDateMath` through `dateMathProjection`, which reuses the shipped
/// schedule engine unchanged.
///
/// Concurrency decisions 6–7: entries are evaluated together by one coalesced
/// wake-up, runs execute concurrently per profile, and Today Refresh is
/// per-entry.
struct ScheduledExportEntry: Codable, Identifiable, Equatable {
    let id: UUID
    /// The export profile this entry runs. One entry per profile.
    let profileID: UUID

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            enabledAt = isEnabled ? Date() : nil
        }
    }
    /// When this entry's current enabled period began; gates occurrence
    /// eligibility so long-missed occurrences before opt-in are not due.
    var enabledAt: Date?

    var frequency: ScheduleFrequency
    var customInterval: Int
    var customUnit: ScheduleIntervalUnit
    var customAnchorDate: Date
    var preferredHour: Int
    var preferredMinute: Int
    /// ISO weekday for weekly entries (1 = Monday … 7 = Sunday).
    var weekday: Int
    var lookbackDays: Int
    var todayRefreshEnabled: Bool
    var todayRefreshIntervalHours: Int
    var todayRefreshIntervalMinutes: Int?
    var todayRefreshMinutes: Int {
        get { todayRefreshIntervalMinutes ?? todayRefreshIntervalHours * 60 }
        set {
            let minutes = ExportSchedule.todayRefreshMinuteOptions.contains(newValue) ? newValue : 180
            todayRefreshIntervalMinutes = minutes < 180 ? minutes : nil
            if minutes >= 180 { todayRefreshIntervalHours = minutes / 60 }
        }
    }

    /// Logical occurrence of the most recent successful completed-day run.
    var lastExportDate: Date?
    /// Scheduled fire date of the most recent successful Today Refresh.
    var lastTodayRefreshDate: Date?
    /// Durable fence for explicitly abandoned recovery; never owned by editor drafts.
    var recoveryGeneration: Int = 0
    /// Suppresses the abandoned occurrence without pretending it succeeded.
    var recoveryDiscardedAt: Date?

    init(
        id: UUID = UUID(),
        profileID: UUID,
        isEnabled: Bool = false,
        frequency: ScheduleFrequency = .daily,
        customInterval: Int = 1,
        customUnit: ScheduleIntervalUnit = .day,
        customAnchorDate: Date = Date(),
        preferredHour: Int = 8,
        preferredMinute: Int = 0,
        weekday: Int = 1,
        lookbackDays: Int? = nil,
        todayRefreshEnabled: Bool = false,
        todayRefreshIntervalHours: Int = ExportSchedule.defaultTodayRefreshIntervalHours,
        todayRefreshIntervalMinutes: Int? = nil,
        lastExportDate: Date? = nil,
        lastTodayRefreshDate: Date? = nil,
        enabledAt: Date? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.isEnabled = isEnabled
        self.enabledAt = enabledAt ?? (isEnabled ? Date() : nil)
        self.frequency = frequency
        self.customInterval = ExportSchedule.clampedCustomInterval(customInterval)
        self.customUnit = customUnit
        self.customAnchorDate = customAnchorDate
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.weekday = ExportSchedule.clampedWeekdayValue(weekday)
        self.lookbackDays = ExportSchedule.clampedLookbackDays(
            lookbackDays ?? ExportSchedule.defaultLookbackDays(
                for: frequency,
                customInterval: customInterval,
                customUnit: customUnit
            )
        )
        self.todayRefreshEnabled = todayRefreshEnabled
        self.todayRefreshIntervalHours = ExportSchedule.clampedTodayRefreshIntervalHours(
            todayRefreshIntervalHours
        )
        self.todayRefreshIntervalMinutes = todayRefreshIntervalMinutes
        self.lastExportDate = lastExportDate
        self.lastTodayRefreshDate = lastTodayRefreshDate
    }


    private enum CodingKeys: String, CodingKey {
        case id
        case profileID
        case isEnabled
        case enabledAt
        case frequency
        case customInterval
        case customUnit
        case customAnchorDate
        case preferredHour
        case preferredMinute
        case weekday
        case lookbackDays
        case todayRefreshIntervalHours
        case lastExportDate
        case lastTodayRefreshDate
        case recoveryGeneration
        case recoveryDiscardedAt
        case todayRefreshEnabled
        case todayRefreshIntervalMinutes
        case todayRefreshRequestedV2
        case todayRefreshPersistenceVersion
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(profileID, forKey: .profileID)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(enabledAt, forKey: .enabledAt)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(customInterval, forKey: .customInterval)
        try c.encode(customUnit, forKey: .customUnit)
        try c.encode(customAnchorDate, forKey: .customAnchorDate)
        try c.encode(preferredHour, forKey: .preferredHour)
        try c.encode(preferredMinute, forKey: .preferredMinute)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(lookbackDays, forKey: .lookbackDays)
        try c.encode(todayRefreshIntervalHours, forKey: .todayRefreshIntervalHours)
        try c.encode(lastExportDate, forKey: .lastExportDate)
        try c.encode(lastTodayRefreshDate, forKey: .lastTodayRefreshDate)
        try c.encode(recoveryGeneration, forKey: .recoveryGeneration)
        try c.encode(recoveryDiscardedAt, forKey: .recoveryDiscardedAt)
        try c.encode(2, forKey: .todayRefreshPersistenceVersion)
        try c.encode(todayRefreshIntervalMinutes == nil ? todayRefreshEnabled : false, forKey: .todayRefreshEnabled)
        try c.encode(todayRefreshIntervalMinutes, forKey: .todayRefreshIntervalMinutes)
        try c.encode(todayRefreshIntervalMinutes.map { _ in todayRefreshEnabled }, forKey: .todayRefreshRequestedV2)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        profileID = try c.decode(UUID.self, forKey: .profileID)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        enabledAt = try c.decodeIfPresent(Date.self, forKey: .enabledAt)
        frequency = try c.decode(ScheduleFrequency.self, forKey: .frequency)
        customInterval = try c.decode(Int.self, forKey: .customInterval)
        customUnit = try c.decode(ScheduleIntervalUnit.self, forKey: .customUnit)
        customAnchorDate = try c.decode(Date.self, forKey: .customAnchorDate)
        preferredHour = try c.decode(Int.self, forKey: .preferredHour)
        preferredMinute = try c.decode(Int.self, forKey: .preferredMinute)
        weekday = try c.decode(Int.self, forKey: .weekday)
        lookbackDays = try c.decode(Int.self, forKey: .lookbackDays)
        todayRefreshEnabled = try c.decode(Bool.self, forKey: .todayRefreshEnabled)
        todayRefreshIntervalHours = try c.decode(Int.self, forKey: .todayRefreshIntervalHours)
        todayRefreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .todayRefreshIntervalMinutes)
        if let minutes = todayRefreshIntervalMinutes {
            guard [30, 60].contains(minutes) else {
                throw DecodingError.dataCorruptedError(forKey: .todayRefreshIntervalMinutes, in: c, debugDescription: "Unsupported Today Refresh minute interval")
            }
            todayRefreshEnabled = try c.decodeIfPresent(Int.self, forKey: .todayRefreshPersistenceVersion) == 2
                && (c.decodeIfPresent(Bool.self, forKey: .todayRefreshRequestedV2) ?? false)
        }
        lastExportDate = try c.decodeIfPresent(Date.self, forKey: .lastExportDate)
        lastTodayRefreshDate = try c.decodeIfPresent(Date.self, forKey: .lastTodayRefreshDate)
        recoveryGeneration = try c.decodeIfPresent(Int.self, forKey: .recoveryGeneration) ?? 0
        recoveryDiscardedAt = try c.decodeIfPresent(Date.self, forKey: .recoveryDiscardedAt)
    }

    /// Projects this entry onto the legacy schedule shape so every shipped
    /// `ScheduleDateMath` occurrence rule applies verbatim to entries.
    /// `target` is not part of date math and carries a placeholder.
    var dateMathProjection: ExportSchedule {
        ExportSchedule(
            isEnabled: isEnabled,
            frequency: frequency,
            customInterval: customInterval,
            customUnit: customUnit,
            customAnchorDate: customAnchorDate,
            preferredHour: preferredHour,
            preferredMinute: preferredMinute,
            weekday: weekday,
            target: .localIPhoneFolder,
            lookbackDays: lookbackDays,
            todayRefreshEnabled: todayRefreshEnabled,
            todayRefreshIntervalHours: todayRefreshIntervalHours,
            todayRefreshIntervalMinutes: todayRefreshIntervalMinutes,
            lastExportDate: lastExportDate,
            lastTodayRefreshDate: lastTodayRefreshDate,
            enabledAt: recoveryDiscardedAt.map { max(enabledAt ?? $0, $0) } ?? enabledAt
        )
    }
}

extension ExportSchedule {
    /// Shared ISO-weekday clamp used by legacy schedules and entries.
    static func clampedWeekdayValue(_ weekday: Int) -> Int {
        min(max(weekday, 1), 7)
    }
}

/// Bounded, UserDefaults-backed store for scheduled export entries.
///
/// Hard bound (decision 5): `maximumScheduledEntries` is a single constant;
/// upserts beyond it fail. One entry per profile: upserting a second entry
/// for a profile replaces the first. A deleted or unknown `profileID` is the
/// caller's concern — stores treat entries as inert data, so the schedule UI
/// disables entries whose profile disappeared and never silently runs the
/// wrong profile.
final class ScheduledExportEntryStore: ObservableObject {
    /// `nonisolated deinit` keeps teardown off the MainActor back-deployed
    /// dealloc path, which trips a libmalloc
    /// POINTER_BEING_FREED_WAS_NOT_ALLOCATED abort on the iOS 26.2 runtime
    /// when nested ObservableObject stores are released (seen on CI
    /// simulators; fixed in newer runtimes). All state is already torn down
    /// by the time deinit runs, so no isolation is required.
    nonisolated deinit {}

    /// Maximum scheduled entries across all profiles (product decision 5).
    static let maximumScheduledEntries = 100

    @Published private(set) var entries: [ScheduledExportEntry]

    private let userDefaults: UserDefaults
    private let now: () -> Date

    private static let storageKey = "scheduledExportEntries.list"

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.userDefaults = userDefaults
        self.now = now
        entries = Self.decodeStoredEntries(from: userDefaults)
    }

    /// Re-reads persisted entries so instances owned by different subsystems
    /// (UI coordinator, SchedulingManager) observe each other's mutations.
    /// Safe on the main thread, matching every existing call site.
    private func reloadFromDefaults() {
        let fresh = Self.decodeStoredEntries(from: userDefaults)
        if fresh != entries {
            entries = fresh
        }
    }

    private static func decodeStoredEntries(from userDefaults: UserDefaults) -> [ScheduledExportEntry] {
        guard let data = userDefaults.data(forKey: storageKey),
              var decoded = try? JSONDecoder().decode([ScheduledExportEntry].self, from: data) else {
            return []
        }
        let archived = userDefaults.dictionary(forKey: "scheduledExportEntries.minuteIntent.v2") ?? [:]
        if let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for index in decoded.indices where objects[index]["todayRefreshPersistenceVersion"] == nil && !decoded[index].todayRefreshEnabled {
                if let minutes = archived[decoded[index].profileID.uuidString] as? Int, [30, 60].contains(minutes) {
                    decoded[index].todayRefreshIntervalMinutes = minutes
                }
            }
        }
        return decoded
    }

    // MARK: - Lookup

    /// All entries re-read from storage. Scheduling decisions made by store
    /// instances owned by other subsystems (SchedulingManager observes the UI
    /// coordinator's mutations) must read through this so a just-saved edit is
    /// visible immediately instead of serving the cached `entries` snapshot.
    func allEntries() -> [ScheduledExportEntry] {
        reloadFromDefaults()
        return entries
    }

    /// Enabled entries re-read from storage; see `allEntries()`.
    func enabledEntries() -> [ScheduledExportEntry] {
        reloadFromDefaults()
        return entries.filter(\.isEnabled)
    }

    func entry(profileID: UUID) -> ScheduledExportEntry? {
        reloadFromDefaults()
        return entries.first { $0.profileID == profileID }
    }

    func entry(id: UUID) -> ScheduledExportEntry? {
        reloadFromDefaults()
        return entries.first { $0.id == id }
    }

    // MARK: - CRUD

    /// Inserts or replaces the entry for its profile. Returns false when the
    /// store is full and the entry's profile is not already present.
    @discardableResult
    func upsert(_ entry: ScheduledExportEntry) -> Bool {
        reloadFromDefaults()
        if let index = entries.firstIndex(where: { $0.profileID == entry.profileID }) {
            let stored = entries[index]
            let startsEnabledPeriod = !stored.isEnabled && entry.isEnabled
            guard !startsEnabledPeriod || stored.recoveryGeneration < Int.max else { return false }
            var merged = entry
            merged.lastExportDate = stored.lastExportDate
            merged.lastTodayRefreshDate = stored.lastTodayRefreshDate
            merged.recoveryGeneration = stored.recoveryGeneration + (startsEnabledPeriod ? 1 : 0)
            merged.recoveryDiscardedAt = stored.recoveryDiscardedAt
            merged.enabledAt = stored.isEnabled == entry.isEnabled
                ? stored.enabledAt : (entry.isEnabled ? now() : nil)
            entries[index] = merged
            persist()
            return true
        }
        guard entries.count < Self.maximumScheduledEntries else { return false }
        entries.append(entry)
        persist()
        return true
    }

    /// Convenience mutation: reads the entry for a profile, applies a change,
    /// and upserts. Returns false when no entry exists for the profile.
    @discardableResult
    func update(profileID: UUID, _ change: (inout ScheduledExportEntry) -> Void) -> Bool {
        reloadFromDefaults()
        guard let index = entries.firstIndex(where: { $0.profileID == profileID }) else { return false }
        let current = entries[index]
        var changed = current
        change(&changed)
        if changed.isEnabled != current.isEnabled {
            if changed.isEnabled {
                guard current.recoveryGeneration < Int.max else { return false }
                changed.recoveryGeneration = current.recoveryGeneration + 1
            }
            changed.enabledAt = changed.isEnabled ? now() : nil
        }
        entries[index] = changed
        persist()
        return true
    }

    /// Removes the entry bound to a profile. Deleting a profile must delete
    /// its entry; the store never orphans entries.
    @discardableResult
    func delete(profileID: UUID) -> Bool {
        reloadFromDefaults()
        guard let index = entries.firstIndex(where: { $0.profileID == profileID }) else {
            return false
        }
        entries.remove(at: index)
        persist()
        return true
    }

    /// Records a successful occurrence without rewinding progress when an
    /// older pending request finishes later. Returns false for unknown entries.
    @discardableResult
    func recordSuccess(
        profileID: UUID,
        kind: ScheduledExportKind,
        occurrenceDate: Date,
        expectedRecoveryGeneration: Int? = nil
    ) -> Bool {
        if let expectedRecoveryGeneration,
           entry(profileID: profileID)?.recoveryGeneration != expectedRecoveryGeneration {
            return false
        }
        return update(profileID: profileID) { entry in
            switch kind {
            case .completedDay:
                entry.lastExportDate = max(entry.lastExportDate ?? occurrenceDate, occurrenceDate)
            case .todayRefresh:
                entry.lastTodayRefreshDate = max(entry.lastTodayRefreshDate ?? occurrenceDate, occurrenceDate)
            }
        }
    }

    /// Invalidate first: cancellation cannot await all export callbacks. Keep both success
    /// frontiers and schedule configuration, and wait for the next ordinary occurrence.
    @discardableResult
    func discardPendingRecovery(profileID: UUID) -> Bool {
        guard let current = entry(profileID: profileID), current.recoveryGeneration < Int.max else {
            return false
        }
        return update(profileID: profileID) {
            $0.recoveryGeneration += 1
            $0.recoveryDiscardedAt = now()
        }
    }

    // MARK: - Migration

    /// One-time migration of the legacy single schedule into an entry bound
    /// to the migration-default profile. Runs only while no entries exist,
    /// the legacy schedule is enabled, and the legacy schedule has real
    /// progress (or was enabled intentionally after profiles existed).
    @discardableResult
    func migrateLegacyScheduleIfNeeded(
        legacy: ExportSchedule,
        defaultProfileID: UUID
    ) -> Bool {
        reloadFromDefaults()
        guard entries.isEmpty, legacy.isEnabled else { return false }

        let entry = ScheduledExportEntry(
            profileID: defaultProfileID,
            isEnabled: true,
            frequency: legacy.frequency,
            customInterval: legacy.customInterval,
            customUnit: legacy.customUnit,
            customAnchorDate: legacy.customAnchorDate,
            preferredHour: legacy.preferredHour,
            preferredMinute: legacy.preferredMinute,
            weekday: legacy.weekday,
            lookbackDays: legacy.lookbackDays,
            todayRefreshEnabled: legacy.todayRefreshEnabled,
            todayRefreshIntervalHours: legacy.todayRefreshIntervalHours,
            todayRefreshIntervalMinutes: legacy.todayRefreshIntervalMinutes,
            lastExportDate: legacy.lastExportDate,
            lastTodayRefreshDate: legacy.lastTodayRefreshDate,
            enabledAt: legacy.enabledAt
        )
        entries = [entry]
        persist()
        return true
    }

    // MARK: - Coalesced due evaluation

    /// A due, actionable occurrence for one entry's profile. This is the
    /// coalesced wake-up's complete decision unit: one BGTask wake-up calls
    /// `dueOccurrences`, then launches each result concurrently (decision 6)
    /// with per-entry in-flight identity.
    ///
    /// Each new completed-day occurrence re-exports its entire lookback, even
    /// when those data days were exported by an earlier occurrence. Success
    /// deduplicates occurrence boundaries, not overlapping data days. Today
    /// Refresh remains independently due after its last successful slot.
    struct DueEntryOccurrence: Equatable {
        let entryID: UUID
        let profileID: UUID
        let kind: ScheduledExportKind
        let fireDate: Date
        let recoveryGeneration: Int
        let enabledAt: Date?
        /// Data days to export for a completed-day occurrence. Always empty
        /// for Today Refresh, which re-exports only the current day.
        let exportDates: [Date]
    }

    /// Evaluates enabled entries against `now`, excluding already-satisfied
    /// occurrence boundaries. Windows are anchored to the scheduled fire day,
    /// so a delayed wake-up cannot shift a completed-day request after midnight.
    func dueOccurrences(
        now: Date,
        calendar: Calendar = .current
    ) -> [DueEntryOccurrence] {
        reloadFromDefaults()
        return entries
            .filter(\.isEnabled)
            .flatMap { entry -> [DueEntryOccurrence] in
                let projection = entry.dateMathProjection
                return ScheduleDateMath.dueScheduledOccurrences(
                    schedule: projection,
                    now: now,
                    calendar: calendar
                )
                .compactMap { occurrence -> DueEntryOccurrence? in
                    let exportDates: [Date]
                    switch occurrence.kind {
                    case .completedDay:
                        if let lastSuccess = entry.lastExportDate, lastSuccess >= occurrence.fireDate {
                            return nil
                        }
                        let dates = ScheduleDateMath.scheduledExportDates(
                            schedule: projection,
                            fireDate: occurrence.fireDate,
                            calendar: calendar
                        )
                        guard !dates.isEmpty else { return nil }
                        exportDates = dates
                    case .todayRefresh:
                        exportDates = []
                    }
                    return DueEntryOccurrence(
                        entryID: entry.id,
                        profileID: entry.profileID,
                        kind: occurrence.kind,
                        fireDate: occurrence.fireDate,
                        recoveryGeneration: entry.recoveryGeneration,
                        enabledAt: entry.enabledAt,
                        exportDates: exportDates
                    )
                }
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Persistence

    private func persist() {
        if let encoded = try? JSONEncoder().encode(entries) {
            let minuteIntent = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
                entry.todayRefreshIntervalMinutes.map { (entry.profileID.uuidString, $0) }
            })
            userDefaults.set(minuteIntent, forKey: "scheduledExportEntries.minuteIntent.v2")
            userDefaults.set(encoded, forKey: Self.storageKey)
        }
    }
}
