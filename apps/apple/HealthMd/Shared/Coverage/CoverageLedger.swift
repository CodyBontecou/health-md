import Foundation

/// Health-free coverage facts for one `(profile, date)`. Failure reasons are kept
/// as raw values, so this file never persists error text, file names or health values.
struct CoverageDateRecord: Codable, Equatable {
    /// Best result from runs after the date ended. These are the runs that can heal a gap.
    var settledOutcome: CoverageOutcome?
    /// Best result from runs on the date itself, such as Today Refresh.
    var sameDayOutcome: CoverageOutcome?
    var sameDayAttempts = 0
    var sameDaySuccesses = 0
    /// Files for this date. Exact only when a run covered this single date.
    var filesWritten: Int?
    var filesWrittenIsExact = false
    var lastWriter: CoverageWriter?
    /// Raw `ExportFailureReason` from the latest unresolved issue.
    var issueReason: String?
    var warningCount = 0
    /// The run finished but Apple Health had no samples for this date.
    var hadNoData = false
    var updatedAt: Date

    var bestOutcome: CoverageOutcome? {
        [settledOutcome, sameDayOutcome].compactMap { $0 }.max()
    }
}

/// One schedule enable or pause. `enabledAt` is cleared on pause, so without this
/// timeline the pause date would be lost.
struct CoverageScheduleEvent: Codable, Equatable {
    let date: Date
    let isEnabled: Bool
}

/// One finished export attempt, reduced to what coverage needs.
struct CoverageRun: Equatable {
    struct DateIssue: Equatable {
        let date: Date
        let reason: String
    }

    let timestamp: Date
    let rangeStart: Date
    let rangeEnd: Date
    let writer: CoverageWriter
    let successCount: Int
    let totalCount: Int
    let fileCount: Int?
    let dailyNoteUpdateCount: Int
    let dailyNoteSkipCount: Int
    let runFailureReason: String?
    let failedDates: [DateIssue]
    let warningDates: [Date]
    /// Dates the exporter confirmed. Nil when the caller only knows counts.
    let completedDates: [Date]?
}

extension CoverageRun {
    init(entry: ExportHistoryEntry, completedDates: [Date]? = nil) {
        let writer: CoverageWriter
        if entry.operationDetails != nil || entry.isCLIRawDelivery {
            writer = .cli
        } else {
            switch entry.source {
            case .scheduled: writer = .schedule
            case .shortcut: writer = .shortcut
            case .manual, .macAgent: writer = .manual
            }
        }
        self.init(
            timestamp: entry.timestamp,
            rangeStart: entry.dateRangeStart,
            rangeEnd: entry.dateRangeEnd,
            writer: writer,
            successCount: entry.successCount,
            totalCount: entry.totalCount,
            fileCount: entry.fileCount,
            dailyNoteUpdateCount: entry.dailyNoteUpdateCount,
            dailyNoteSkipCount: entry.dailyNoteSkipCount,
            runFailureReason: entry.failureReason?.rawValue,
            failedDates: entry.failedDateDetails.map {
                DateIssue(date: $0.date, reason: $0.reason.rawValue)
            },
            warningDates: entry.partialFailures.filter(\.degradesSuccess).map(\.date),
            completedDates: completedDates
        )
    }
}

/// The durable per-date record behind the Archive calendar. The 50-entry export
/// history cannot supply this: it holds about four days of Today Refresh runs and
/// has no per-date success record.
struct CoverageLedger: Codable, Equatable {
    static let currentVersion = 1
    static let retentionDays = 400
    static let maximumEventsPerProfile = 200

    private static let noHealthDataReason = "no_health_data"

    var version = CoverageLedger.currentVersion
    /// When recording began. Dates before this and before any record have no history.
    var startedAt: Date
    var profiles: [UUID: [String: CoverageDateRecord]] = [:]
    var scheduleEvents: [UUID: [CoverageScheduleEvent]] = [:]
    var didSeedFromHistory = false

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    // MARK: - Recording

    /// Merges one run. A later run can improve a date but never downgrades it, so a
    /// failed look-back cannot erase a file that was already written.
    mutating func apply(_ run: CoverageRun, profileID: UUID, now: Date, calendar: Calendar) {
        let dates = Self.boundedDates(run: run, now: now, calendar: calendar)
        guard !dates.isEmpty else { return }

        let failures = Dictionary(
            run.failedDates.map { (CoverageDateKey.key(for: $0.date, calendar: calendar), $0.reason) },
            uniquingKeysWith: { first, _ in first }
        )
        let warnings = Set(run.warningDates.map { CoverageDateKey.key(for: $0, calendar: calendar) })
        let completed = run.completedDates.map { dates in
            Set(dates.map { CoverageDateKey.key(for: $0, calendar: calendar) })
        }
        let runDayKey = CoverageDateKey.key(for: run.timestamp, calendar: calendar)
        let filesPerDate = run.fileCount.map { $0 / max(dates.count, 1) }
        var records = profiles[profileID] ?? [:]

        for date in dates {
            let key = CoverageDateKey.key(for: date, calendar: calendar)
            let result = Self.result(
                for: key,
                run: run,
                failures: failures,
                warnings: warnings,
                completed: completed
            )
            var record = records[key] ?? CoverageDateRecord(updatedAt: run.timestamp)
            let previousBest = record.bestOutcome

            if key == runDayKey {
                record.sameDayAttempts += 1
                if result.outcome > .failed { record.sameDaySuccesses += 1 }
                record.sameDayOutcome = max(record.sameDayOutcome ?? result.outcome, result.outcome)
            } else {
                record.settledOutcome = max(record.settledOutcome ?? result.outcome, result.outcome)
            }

            if result.outcome > .failed {
                record.lastWriter = run.writer
                if let filesPerDate, filesPerDate > 0 {
                    record.filesWritten = max(record.filesWritten ?? 0, filesPerDate)
                    record.filesWrittenIsExact = dates.count == 1
                }
            }

            if result.outcome == .complete {
                record.issueReason = nil
                record.warningCount = 0
                record.hadNoData = result.hadNoData
            } else if previousBest != .complete {
                record.issueReason = result.reason ?? record.issueReason
                record.warningCount = warnings.contains(key) ? max(record.warningCount, 1) : record.warningCount
            }

            record.updatedAt = run.timestamp
            records[key] = record
        }

        profiles[profileID] = records
        prune(now: now, calendar: calendar)
    }

    mutating func recordScheduleTransition(profileID: UUID, isEnabled: Bool, at date: Date) {
        var events = scheduleEvents[profileID] ?? []
        guard events.last?.isEnabled != isEnabled else { return }
        events.append(CoverageScheduleEvent(date: date, isEnabled: isEnabled))
        scheduleEvents[profileID] = Array(events.suffix(Self.maximumEventsPerProfile))
    }

    mutating func prune(now: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        let cutoffKey = CoverageDateKey.key(for: cutoff, calendar: calendar)
        for (profileID, records) in profiles {
            let kept = records.filter { $0.key >= cutoffKey }
            profiles[profileID] = kept.isEmpty ? nil : kept
        }
    }

    // MARK: - Per-date result

    private struct DateResult {
        let outcome: CoverageOutcome
        var reason: String?
        var hadNoData = false
    }

    private static func result(
        for key: String,
        run: CoverageRun,
        failures: [String: String],
        warnings: Set<String>,
        completed: Set<String>?
    ) -> DateResult {
        if let reason = failures[key] {
            return reason == noHealthDataReason
                ? DateResult(outcome: .complete, hadNoData: true)
                : DateResult(outcome: .failed, reason: reason)
        }

        if let completed {
            guard completed.contains(key) else {
                return runFailureResult(run)
            }
        } else if run.successCount == 0 {
            // Daily-note-only output counts as written, with skips as partial.
            if run.dailyNoteUpdateCount > 0 || run.dailyNoteSkipCount > 0 {
                return DateResult(outcome: .partial, reason: run.runFailureReason)
            }
            return runFailureResult(run)
        } else if run.successCount < run.totalCount && run.failedDates.isEmpty {
            // Counts show a shortfall but not which dates, so claim no date as complete.
            return DateResult(outcome: .partial, reason: run.runFailureReason)
        }

        return warnings.contains(key)
            ? DateResult(outcome: .partial, reason: run.runFailureReason)
            : DateResult(outcome: .complete)
    }

    private static func runFailureResult(_ run: CoverageRun) -> DateResult {
        run.runFailureReason == noHealthDataReason
            ? DateResult(outcome: .complete, hadNoData: true)
            : DateResult(outcome: .failed, reason: run.runFailureReason ?? "unknown")
    }

    /// Days in the run's inclusive range that fall inside the retention window. An
    /// all-time export can span decades, so enumeration starts at the window.
    private static func boundedDates(run: CoverageRun, now: Date, calendar: Calendar) -> [Date] {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return [] }
        var current = calendar.startOfDay(for: max(run.rangeStart, cutoff))
        let last = calendar.startOfDay(for: run.rangeEnd)
        var dates: [Date] = []
        while current <= last, dates.count <= retentionDays {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}

// MARK: - Attribution

/// Resolves which profile a run belongs to. `ExportHistoryEntry` stores only a display
/// name, and interactive exports record neither a name nor an ID.
enum CoverageAttribution {
    static func profileID(
        explicitID: UUID?,
        entry: ExportHistoryEntry,
        profiles: [ExportProfile],
        activeProfileID: UUID?
    ) -> UUID? {
        if let explicitID { return explicitID }
        if let name = entry.profileName ?? entry.operationDetails?.profile {
            let matches = profiles.filter { $0.name == name }
            return matches.count == 1 ? matches[0].id : nil
        }
        switch entry.source {
        case .manual, .shortcut: return activeProfileID
        case .scheduled, .macAgent: return nil
        }
    }
}

// MARK: - One-time seed

extension CoverageLedger {
    /// Seeds from retained history, once. Older entries carry no profile ID, so an
    /// unnamed run is attributed only when a single profile exists. Disabled entries
    /// that have run before get a pause from `now`, because the real date was not kept.
    mutating func seedIfNeeded(
        history: [ExportHistoryEntry],
        profiles profileList: [ExportProfile],
        scheduleEntries: [ScheduledExportEntry],
        now: Date,
        calendar: Calendar
    ) {
        guard !didSeedFromHistory else { return }
        didSeedFromHistory = true

        let soleProfileID = profileList.count == 1 ? profileList[0].id : nil
        for entry in history.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let profileID = CoverageAttribution.profileID(
                explicitID: nil,
                entry: entry,
                profiles: profileList,
                activeProfileID: soleProfileID
            ) else { continue }
            apply(CoverageRun(entry: entry), profileID: profileID, now: now, calendar: calendar)
        }

        for entry in scheduleEntries where !entry.isEnabled && entry.lastExportDate != nil {
            recordScheduleTransition(profileID: entry.profileID, isEnabled: false, at: now)
        }
    }
}
