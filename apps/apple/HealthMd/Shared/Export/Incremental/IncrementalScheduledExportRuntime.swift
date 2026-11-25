import Foundation

/// Missing-file detection for incremental runs: a cheap existence check of each day's
/// aggregate daily files. Only loose daily files in a local folder can be checked;
/// archives, Daily Notes Only, summary-only, and remote targets report nothing missing.
enum IncrementalExportMissingFiles {
    /// - Parameters:
    ///   - daysWithData: days the sample index says have Health data. A day without data
    ///     legitimately has no file, so it is never reported missing.
    static func missingDays(
        windowDates: [Date],
        daysWithData: Set<Date>,
        settings: AdvancedExportSettings,
        vaultURL: URL,
        healthSubfolder: String,
        fileExists: (URL) -> Bool
    ) -> Set<Date> {
        guard !settings.archiveModeEnabled,
              !settings.summaryOnlyModeEnabled,
              !settings.dailyNotesOnlyModeEnabled,
              !settings.exportFormats.isEmpty else { return [] }
        var missing = Set<Date>()
        for day in windowDates where daysWithData.contains(day) {
            let targets = ExportPathPlanner.aggregateOutputTargets(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: day
            )
            if targets.contains(where: { !fileExists($0.url) }) {
                missing.insert(day)
            }
        }
        return missing
    }

    static func daysWithData(in state: IncrementalExportCommittedState?, calendar: Calendar) -> Set<Date> {
        guard let state else { return [] }
        var days = Set<Date>()
        for typeIndex in state.sampleDays.values {
            for (key, uuids) in typeIndex where !uuids.isEmpty {
                if let day = IncrementalExportDayMapper.date(forDayKey: key, calendar: calendar) {
                    days.insert(day)
                }
            }
        }
        return days
    }
}

/// Glue between the scheduler and the pure planner: queries HealthKit, plans, stages
/// the next state with the pending request, and commits it after success.
final class IncrementalScheduledExportRuntime {
    struct Prepared: Equatable {
        let plan: IncrementalExportPlan
        /// Dates whose range summaries this run rebuilds (`originalRequestedDates`).
        let rollupDates: [Date]
    }

    let store: IncrementalScheduledExportStore
    private let changeSource: IncrementalHealthChangeSource

    init(
        store: IncrementalScheduledExportStore = IncrementalScheduledExportStore(),
        changeSource: IncrementalHealthChangeSource = HealthKitIncrementalChangeSource()
    ) {
        self.store = store
        self.changeSource = changeSource
    }

    /// Plans one fresh scheduled occurrence and stages its next state.
    /// - Parameter missingFileDays: called with the days that have Health data; returns
    ///   those whose files are gone.
    func prepare(
        profile: ExportProfile,
        entry: ScheduledExportEntry,
        settings: ExportSettingsSnapshot,
        requestID: UUID,
        windowDates: [Date],
        calendar: Calendar,
        now: Date,
        missingFileDays: (Set<Date>) async -> Set<Date>
    ) async -> Prepared {
        let record = store.record(for: profile.id)
        let fingerprint = IncrementalExportSettingsFingerprint(
            profile: profile,
            calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            lookbackDays: entry.lookbackDays,
            includeToday: entry.includeToday
        )
        let window = windowDates.map { calendar.startOfDay(for: $0) }.sorted()
        let changes: [IncrementalTypeChanges]?
        if let windowStart = window.first {
            changes = try? await changeSource.changes(
                typeIdentifiers: changeSource.sampleTypeIdentifiers(for: profile.settings),
                anchors: record.committed?.anchors ?? [:],
                windowStart: windowStart
            )
        } else {
            changes = nil
        }
        let withData = IncrementalExportMissingFiles.daysWithData(in: record.committed, calendar: calendar)
            .intersection(window)
        let missing = record.committed == nil ? [] : await missingFileDays(withData)
        let plan = IncrementalExportPlanner.plan(.init(
            windowDates: window,
            calendar: calendar,
            now: now,
            previous: record.committed,
            fingerprint: fingerprint,
            changes: changes,
            missingFileDays: missing
        ))
        if let nextState = plan.nextState {
            try? store.stage(.init(
                requestID: requestID,
                state: nextState,
                summary: plan.summary(runAt: now, calendarTimeZoneIdentifier: calendar.timeZone.identifier)
            ), for: profile.id)
        } else {
            // HealthKit could not report changes: keep the saved anchors, but still
            // record what this full run did once it succeeds.
            var staged = record
            staged.staged = record.committed.map {
                .init(requestID: requestID, state: $0,
                      summary: plan.summary(runAt: now, calendarTimeZoneIdentifier: calendar.timeZone.identifier))
            }
            try? store.save(staged, for: profile.id)
        }
        return Prepared(
            plan: plan,
            rollupDates: IncrementalExportPlanner.rollupDates(
                plan: plan,
                windowDates: window,
                rollupPeriods: settings.operationRollupPeriods
            )
        )
    }

    @discardableResult
    func commit(requestID: UUID, profileID: UUID) -> IncrementalRunSummary? {
        try? store.commit(requestID: requestID, for: profileID)
    }

    func reset(profileID: UUID) throws {
        try store.reset(profileID: profileID)
    }

    func lastSummary(profileID: UUID) -> IncrementalRunSummary? {
        store.record(for: profileID).lastSummary
    }

    /// True when the next run will export the whole window (no saved state).
    func nextRunIsFull(profileID: UUID) -> Bool {
        store.record(for: profileID).committed == nil
    }
}

extension IncrementalScheduledExportRuntime {
    /// Hermetic default for unit-test hosts: a temporary store and a change source that
    /// always fails, so every run is a full export (the pre-#457 behavior) unless a test
    /// injects its own runtime.
    static func unavailableForTests() -> IncrementalScheduledExportRuntime {
        IncrementalScheduledExportRuntime(
            store: IncrementalScheduledExportStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("IncrementalScheduledExport-\(UUID().uuidString)", isDirectory: true)
            ),
            changeSource: UnavailableIncrementalHealthChangeSource()
        )
    }
}

struct UnavailableIncrementalHealthChangeSource: IncrementalHealthChangeSource {
    struct Unavailable: Error {}
    func sampleTypeIdentifiers(for settings: ExportSettingsSnapshot) -> [String] { [] }
    func changes(typeIdentifiers: [String], anchors: [String: Data], windowStart: Date) async throws -> [IncrementalTypeChanges] {
        throw Unavailable()
    }
}
