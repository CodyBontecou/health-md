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

    /// Logical occurrence of the most recent successful completed-day run.
    var lastExportDate: Date?
    /// Scheduled fire date of the most recent successful Today Refresh.
    var lastTodayRefreshDate: Date?

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
        self.lastExportDate = lastExportDate
        self.lastTodayRefreshDate = lastTodayRefreshDate
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
            lastExportDate: lastExportDate,
            lastTodayRefreshDate: lastTodayRefreshDate,
            enabledAt: enabledAt
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

        if let data = userDefaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ScheduledExportEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    // MARK: - Lookup

    func entry(profileID: UUID) -> ScheduledExportEntry? {
        entries.first { $0.profileID == profileID }
    }

    func entry(id: UUID) -> ScheduledExportEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - CRUD

    /// Inserts or replaces the entry for its profile. Returns false when the
    /// store is full and the entry's profile is not already present.
    @discardableResult
    func upsert(_ entry: ScheduledExportEntry) -> Bool {
        if let index = entries.firstIndex(where: { $0.profileID == entry.profileID }) {
            entries[index] = entry
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
        guard var entry = entry(profileID: profileID) else { return false }
        change(&entry)
        return upsert(entry)
    }

    /// Removes the entry bound to a profile. Deleting a profile must delete
    /// its entry; the store never orphans entries.
    @discardableResult
    func delete(profileID: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.profileID == profileID }) else {
            return false
        }
        entries.remove(at: index)
        persist()
        return true
    }

    /// Records a successful occurrence so catch-up math skips it, mirroring
    /// `ExportSchedule.updateLastExport`. Returns false when the entry is
    /// unknown.
    @discardableResult
    func recordSuccess(
        profileID: UUID,
        kind: ScheduledExportKind,
        occurrenceDate: Date
    ) -> Bool {
        update(profileID: profileID) { entry in
            switch kind {
            case .completedDay:
                entry.lastExportDate = occurrenceDate
            case .todayRefresh:
                entry.lastTodayRefreshDate = occurrenceDate
            }
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
    /// Mirrors the shipped two-layer semantics: a completed-day occurrence is
    /// only actionable when the entry also has unexported data days
    /// (`ScheduleDateMath.catchUpDatesNeeded`), and a Today Refresh occurrence
    /// is actionable when its slot boundary passed after the last refresh.
    struct DueEntryOccurrence: Equatable {
        let entryID: UUID
        let profileID: UUID
        let kind: ScheduledExportKind
        let fireDate: Date
        /// Data days to export for a completed-day occurrence. Always empty
        /// for Today Refresh, which re-exports only the current day.
        let exportDates: [Date]
    }

    /// Evaluates every enabled entry against `now` using the shipped
    /// occurrence and catch-up rules. Occurrence boundaries that carry no
    /// work (for example a daily boundary after today's run already covered
    /// yesterday) are not returned.
    func dueOccurrences(
        now: Date,
        calendar: Calendar = .current
    ) -> [DueEntryOccurrence] {
        entries
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
                        let dates = ScheduleDateMath.catchUpDatesNeeded(
                            schedule: projection,
                            now: now,
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
                        exportDates: exportDates
                    )
                }
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Persistence

    private func persist() {
        if let encoded = try? JSONEncoder().encode(entries) {
            userDefaults.set(encoded, forKey: Self.storageKey)
        }
    }
}

/// Projected monthly quota burn across scheduled entries (decision 4's
/// surfaced usage). Every exporting request — completed-day runs *and*
/// Today Refreshes — consumes one free export action, so both are counted.
enum ScheduledUsageProjection {
    /// Per-entry projection with the assumptions documented on `monthlyTotal`.
    struct EntryProjection: Equatable {
        let entryID: UUID
        let profileID: UUID
        /// Approximate exporting requests per 30-day month for this entry.
        let monthlyTotal: Int
        /// Requests per day implied by the cadence (main run + refreshes).
        let requestsPerDay: Double
    }

    /// 30-day month approximation. Daily cadence → 30 runs; weekly → 30/7;
    /// custom every N nominal days → 30/N. Today Refresh adds one request per
    /// scheduled refresh slot between the preferred time and midnight.
    static func projectedMonthlyActions(
        entries: [ScheduledExportEntry],
        calendar: Calendar = .current
    ) -> [EntryProjection] {
        entries.map { entry in
            let cadenceDays: Double
            switch entry.frequency {
            case .daily:
                cadenceDays = 1
            case .weekly:
                cadenceDays = 7
            case .custom:
                cadenceDays = Double(
                    max(entry.customInterval, 1) * entry.customUnit.nominalDayCount
                )
            }

            let mainRunsPerDay = 1.0 / cadenceDays
            var refreshesPerDay = 0.0
            if entry.todayRefreshEnabled {
                let interval = ExportSchedule.clampedTodayRefreshIntervalHours(
                    entry.todayRefreshIntervalHours
                )
                var hour = entry.preferredHour
                while hour < 24 {
                    refreshesPerDay += 1
                    hour += interval
                }
            }

            let requestsPerDay = mainRunsPerDay + refreshesPerDay
            return EntryProjection(
                entryID: entry.id,
                profileID: entry.profileID,
                monthlyTotal: Int((requestsPerDay * 30).rounded(.up)),
                requestsPerDay: requestsPerDay
            )
        }
    }

    /// Aggregate monthly request count across enabled entries only.
    static func projectedMonthlyTotal(
        entries: [ScheduledExportEntry]
    ) -> Int {
        projectedMonthlyActions(entries: entries.filter(\.isEnabled))
            .reduce(0) { $0 + $1.monthlyTotal }
    }
}
