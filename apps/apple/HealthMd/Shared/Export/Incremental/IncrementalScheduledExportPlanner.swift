import Foundation

// Incremental scheduled exports (issue #457).
//
// A scheduled profile run with "Only update days that changed" on rewrites only the
// days in its look-back window whose HealthKit data changed since the last successful
// run, plus days whose files are missing and a short trailing safety window. Everything
// here is pure so the rules are unit-tested without HealthKit or a vault:
// - `IncrementalExportDayMapper` maps sample intervals to the calendar days they touch.
// - `IncrementalExportSettingsFingerprint` detects output-affecting setting changes.
// - `IncrementalExportPlanner` turns anchored-query deltas into the days to export and
//   the next state, which the runtime saves only after the export succeeds.

/// One added (or edited, which HealthKit reports as delete + add) sample.
struct IncrementalSampleChange: Codable, Equatable, Sendable {
    let uuid: UUID
    let startDate: Date
    let endDate: Date
}

/// Changes to one HealthKit sample type since its saved anchor.
struct IncrementalTypeChanges: Equatable, Sendable {
    /// `HKSampleType.identifier`.
    let typeIdentifier: String
    /// True when the query started without a saved anchor (first run for this type,
    /// reinstall, HealthKit reset, or an anchor that could not be decoded). `added`
    /// then lists every sample in the window rather than a delta.
    let startedWithoutAnchor: Bool
    let added: [IncrementalSampleChange]
    let deletedUUIDs: [UUID]
    /// Archived `HKQueryAnchor` to save once the export succeeds.
    let newAnchor: Data?
}

enum IncrementalExportDayMapper {
    /// Calendar days (start of day in `calendar`'s timezone) that a sample covers.
    ///
    /// A sample spanning midnight touches every day it overlaps. The end is exclusive:
    /// a sample ending exactly at midnight does not touch the next day. A zero-length
    /// sample (or one whose end precedes its start) belongs to its start day.
    static func days(start: Date, end: Date, calendar: Calendar) -> [Date] {
        let firstDay = calendar.startOfDay(for: start)
        guard end > start else { return [firstDay] }
        let lastInstant = end.addingTimeInterval(-0.001)
        let lastDay = calendar.startOfDay(for: max(lastInstant, start))
        var days: [Date] = []
        var current = firstDay
        // Bound the walk so a corrupt multi-year sample cannot spin.
        while current <= lastDay, days.count < 400 {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// Stable day key (yyyy-MM-dd) in the calendar's timezone, used for persistence.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(forDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// Everything about a profile that changes which bytes a run writes, or where. When
/// it differs from the last successful run's value, every day in the window is stale
/// even though the Health data is not, so the run exports the whole window once.
///
/// Compared with `==` rather than hashed: settings contain sets, whose encoded order
/// is not stable across launches, and ordered lists (field order) that must count.
struct IncrementalExportSettingsFingerprint: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var settings: ExportSettingsSnapshot
    var target: ExportTargetSelection
    var folderVaultID: UUID?
    var apiEndpointID: UUID?
    var googleDriveDestinationID: UUID?
    /// Day boundaries come from this timezone, so a change re-maps every day.
    var calendarTimeZoneIdentifier: String
    var lookbackDays: Int
    var includeToday: Bool

    init(profile: ExportProfile, calendarTimeZoneIdentifier: String, lookbackDays: Int, includeToday: Bool) {
        settings = profile.settings
        target = profile.target
        folderVaultID = profile.folderVaultID
        apiEndpointID = profile.apiEndpointID
        googleDriveDestinationID = profile.googleDriveDestinationID
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
        self.lookbackDays = lookbackDays
        self.includeToday = includeToday
    }
}

/// The last successful run's anchors, sample-day index and settings.
struct IncrementalExportCommittedState: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var fingerprint: IncrementalExportSettingsFingerprint
    /// Archived `HKQueryAnchor` per `HKSampleType.identifier`.
    var anchors: [String: Data]
    /// Sample UUIDs per type and day key inside the window. HealthKit reports a deleted
    /// sample only by UUID, so this index is how a deletion finds the day it affected.
    var sampleDays: [String: [String: [UUID]]]
}

enum IncrementalExportMode: String, Codable, Equatable {
    case incremental
    case full
}

enum IncrementalExportFullReason: String, Codable, Equatable {
    /// No saved state: first run, reinstall, or "Re-export everything".
    case noSavedState
    /// A data type had no usable anchor (new metric, HealthKit reset, decode failure).
    case anchorUnavailable
    case settingsChanged
    /// HealthKit could not report changes, so nothing can be skipped safely.
    case changeQueryFailed
}

/// What a run did, shown on the schedule page.
struct IncrementalRunSummary: Codable, Equatable {
    let runAt: Date
    let mode: IncrementalExportMode
    let fullReason: IncrementalExportFullReason?
    /// Days written (start of day in `calendarTimeZoneIdentifier`), sorted.
    let updatedDays: [Date]
    /// Days written because Health data changed or the file was missing; excludes days
    /// written only by the trailing safety window.
    let changedDayCount: Int
    let unchangedDayCount: Int
    let calendarTimeZoneIdentifier: String

    var statusText: String {
        let total = updatedDays.count + unchangedDayCount
        if mode == .full {
            let reason: String
            switch fullReason {
            case .settingsChanged:
                reason = String(localized: "export settings changed", comment: "Reason a scheduled run re-exported every day")
            case .changeQueryFailed:
                reason = String(localized: "Health changes were unavailable", comment: "Reason a scheduled run re-exported every day")
            case .anchorUnavailable, .noSavedState, nil:
                reason = String(localized: "first run", comment: "Reason a scheduled run re-exported every day")
            }
            return String(localized: "Exported all \(total) days (\(reason))", comment: "Scheduled run status after a full export")
        }
        let days = Self.dayList(updatedDays, timeZoneIdentifier: calendarTimeZoneIdentifier)
        // The rewritten-days phrase is its own plural string ("Updated 1 day (Nov 24)"),
        // since a one-day look-back updates exactly one day on every run.
        let updated = String(
            localized: "Updated \(updatedDays.count) days (\(days))",
            comment: "Days a scheduled run rewrote, e.g. Updated 3 days (Nov 18, 22, 23)"
        )
        return String(
            localized: "\(changedDayCount) changed · \(updated) · \(unchangedDayCount) unchanged",
            comment: "Scheduled run status after an incremental export, e.g. 1 changed · Updated 3 days (Nov 18, 22, 23) · 27 unchanged"
        )
    }

    /// "Nov 18, 21, 23": the month is repeated only when it changes.
    static func dayList(_ days: [Date], timeZoneIdentifier: String, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let monthDay = DateFormatter()
        monthDay.locale = locale
        monthDay.timeZone = calendar.timeZone
        monthDay.setLocalizedDateFormatFromTemplate("MMMd")
        let dayOnly = DateFormatter()
        dayOnly.locale = locale
        dayOnly.timeZone = calendar.timeZone
        dayOnly.setLocalizedDateFormatFromTemplate("d")
        var previousMonth: Int?
        return days.sorted().map { day in
            let month = calendar.component(.month, from: day)
            defer { previousMonth = month }
            return month == previousMonth ? dayOnly.string(from: day) : monthDay.string(from: day)
        }.joined(separator: ", ")
    }
}

struct IncrementalExportPlan: Equatable {
    let mode: IncrementalExportMode
    let fullReason: IncrementalExportFullReason?
    /// Daily work for this run, sorted, always a subset of the window.
    let datesToExport: [Date]
    /// Window days whose Health data changed (added, edited or deleted samples).
    let dataChangedDays: [Date]
    /// Window days whose daily file is missing.
    let missingFileDays: [Date]
    let unchangedDayCount: Int
    /// State to save only after this run succeeds. Nil when HealthKit reported no
    /// usable changes; the saved state then stays as it was.
    let nextState: IncrementalExportCommittedState?

    func summary(runAt: Date, calendarTimeZoneIdentifier: String) -> IncrementalRunSummary {
        let changed = Set(dataChangedDays).union(missingFileDays).intersection(datesToExport)
        return IncrementalRunSummary(
            runAt: runAt,
            mode: mode,
            fullReason: fullReason,
            updatedDays: datesToExport,
            changedDayCount: mode == .full ? datesToExport.count : changed.count,
            unchangedDayCount: unchangedDayCount,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
    }
}

enum IncrementalExportPlanner {
    /// Days always rewritten at the end of the window: today and yesterday relative to
    /// the run. HealthKit recomputes some values in place (sleep scoring, HRV) without
    /// surfacing them as anchored changes.
    static let safetyWindowDays = 2

    struct Input {
        /// The full look-back window, as the schedule computed it.
        var windowDates: [Date]
        var calendar: Calendar
        /// When the run happens; the safety window ends on this day.
        var now: Date
        var previous: IncrementalExportCommittedState?
        var fingerprint: IncrementalExportSettingsFingerprint
        /// Nil when the anchored queries failed.
        var changes: [IncrementalTypeChanges]?
        var missingFileDays: Set<Date> = []
    }

    static func plan(_ input: Input) -> IncrementalExportPlan {
        let calendar = input.calendar
        let window = Array(Set(input.windowDates.map { calendar.startOfDay(for: $0) })).sorted()
        let windowSet = Set(window)
        let missing = input.missingFileDays.map { calendar.startOfDay(for: $0) }.filter(windowSet.contains)

        guard let changes = input.changes else {
            return IncrementalExportPlan(
                mode: .full, fullReason: .changeQueryFailed, datesToExport: window,
                dataChangedDays: [], missingFileDays: missing.sorted(),
                unchangedDayCount: 0, nextState: nil
            )
        }

        let previousIndex = input.previous?.sampleDays ?? [:]
        var anchors = input.previous?.anchors ?? [:]
        var index = previousIndex
        var changedDays = Set<Date>()
        var anchorUnavailable = false

        for typeChanges in changes {
            let type = typeChanges.typeIdentifier
            if typeChanges.startedWithoutAnchor {
                anchorUnavailable = true
                // A fresh query lists the whole window: rebuild this type's index.
                index[type] = [:]
            }
            var typeIndex = index[type] ?? [:]
            if !typeChanges.deletedUUIDs.isEmpty {
                let deleted = Set(typeChanges.deletedUUIDs)
                for (key, uuids) in typeIndex {
                    let remaining = uuids.filter { !deleted.contains($0) }
                    guard remaining.count != uuids.count else { continue }
                    if let day = IncrementalExportDayMapper.date(forDayKey: key, calendar: calendar) {
                        changedDays.insert(day)
                    }
                    typeIndex[key] = remaining.isEmpty ? nil : remaining
                }
            }
            for sample in typeChanges.added {
                for day in IncrementalExportDayMapper.days(start: sample.startDate, end: sample.endDate, calendar: calendar)
                where windowSet.contains(day) {
                    changedDays.insert(day)
                    typeIndex[IncrementalExportDayMapper.dayKey(for: day, calendar: calendar), default: []].append(sample.uuid)
                }
            }
            index[type] = typeIndex
            if let anchor = typeChanges.newAnchor {
                anchors[type] = anchor
            } else {
                anchors[type] = nil
            }
        }

        // Drop index days that left the window and types no longer exported.
        let windowKeys = Set(window.map { IncrementalExportDayMapper.dayKey(for: $0, calendar: calendar) })
        let queriedTypes = Set(changes.map(\.typeIdentifier))
        index = index.filter { queriedTypes.contains($0.key) }.mapValues { $0.filter { windowKeys.contains($0.key) } }
        anchors = anchors.filter { queriedTypes.contains($0.key) }

        let nextState = IncrementalExportCommittedState(
            fingerprint: input.fingerprint,
            anchors: anchors,
            sampleDays: index
        )

        let fullReason: IncrementalExportFullReason?
        if input.previous == nil {
            fullReason = .noSavedState
        } else if input.previous?.fingerprint != input.fingerprint {
            fullReason = .settingsChanged
        } else if anchorUnavailable {
            fullReason = .anchorUnavailable
        } else {
            fullReason = nil
        }
        let dataChanged = changedDays.intersection(windowSet).sorted()
        if let fullReason {
            return IncrementalExportPlan(
                mode: .full, fullReason: fullReason, datesToExport: window,
                dataChangedDays: dataChanged, missingFileDays: missing.sorted(),
                unchangedDayCount: 0, nextState: nextState
            )
        }

        var selected = Set(dataChanged).union(missing)
        selected.formUnion(safetyWindow(now: input.now, calendar: calendar).filter(windowSet.contains))
        if selected.isEmpty, let last = window.last {
            // A completed-day window always ends on yesterday or today, so this only
            // guards odd windows: never schedule an empty run.
            selected.insert(last)
        }
        let dates = selected.sorted()
        return IncrementalExportPlan(
            mode: .incremental, fullReason: nil, datesToExport: dates,
            dataChangedDays: dataChanged, missingFileDays: missing.sorted(),
            unchangedDayCount: window.count - dates.count, nextState: nextState
        )
    }

    static func safetyWindow(now: Date, calendar: Calendar) -> Set<Date> {
        let today = calendar.startOfDay(for: now)
        return Set((0..<safetyWindowDays).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        })
    }

    /// Dates whose range summaries the run must rebuild. The v9 range summary covers
    /// the whole window, and any written day lies inside it, so it is rebuilt from the
    /// full window. Pinned historical calendar summaries (weekly/monthly/yearly) are
    /// rebuilt only for periods that contain a written day; the orchestrator expands
    /// each date to its full period.
    static func rollupDates(
        plan: IncrementalExportPlan,
        windowDates: [Date],
        rollupPeriods: [HealthRollupPeriod]
    ) -> [Date] {
        guard plan.mode == .incremental, !rollupPeriods.contains(.range) else { return windowDates }
        return plan.datesToExport
    }
}
