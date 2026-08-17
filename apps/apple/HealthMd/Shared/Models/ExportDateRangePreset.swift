import Foundation

struct ExportDateRange: Equatable {
    let startDate: Date
    let endDate: Date
}

struct ExportDateRangeSelection: Equatable {
    let preset: ExportDateRangePreset
    let startDate: Date
    let endDate: Date

    static func defaultSelection(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ExportDateRangeSelection {
        let today = calendar.startOfDay(for: referenceDate)
        let range = ExportDateRangePreset.today.resolvedRange(
            referenceDate: referenceDate,
            currentStartDate: today,
            currentEndDate: today,
            calendar: calendar
        ) ?? ExportDateRange(startDate: today, endDate: today)

        return ExportDateRangeSelection(
            preset: .today,
            startDate: range.startDate,
            endDate: range.endDate
        )
    }
}

struct ExportDateRangeSelectionStore {
    static let shared = ExportDateRangeSelectionStore()

    private enum Key {
        static let preset = "exportDateRangeSelection.preset"
        static let startDate = "exportDateRangeSelection.startDate"
        static let endDate = "exportDateRangeSelection.endDate"
        static let customStartDayOffset = "exportDateRangeSelection.customStartDayOffset"
        static let customEndDayOffset = "exportDateRangeSelection.customEndDayOffset"
        static let interactiveExportInFlight = "exportDateRangeSelection.interactiveExportInFlight"
    }

    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ExportDateRangeSelection {
        let fallback = ExportDateRangeSelection.defaultSelection(
            referenceDate: referenceDate,
            calendar: calendar
        )
        let preset = userDefaults.string(forKey: Key.preset)
            .flatMap(ExportDateRangePreset.init(rawValue:)) ?? .today

        switch preset {
        case .today, .yesterday:
            let range = preset.resolvedRange(
                referenceDate: referenceDate,
                currentStartDate: fallback.startDate,
                currentEndDate: fallback.endDate,
                calendar: calendar
            ) ?? ExportDateRange(startDate: fallback.startDate, endDate: fallback.endDate)
            return ExportDateRangeSelection(
                preset: preset,
                startDate: range.startDate,
                endDate: range.endDate
            )

        case .custom:
            let range = loadRollingCustomRange(
                referenceDate: referenceDate,
                calendar: calendar
            ) ?? loadStoredAbsoluteRange(calendar: calendar)
              ?? ExportDateRange(startDate: fallback.startDate, endDate: fallback.endDate)
            return ExportDateRangeSelection(
                preset: .custom,
                startDate: range.startDate,
                endDate: range.endDate
            )

        case .allTime:
            let range = loadStoredAbsoluteRange(calendar: calendar)
                ?? ExportDateRange(startDate: fallback.startDate, endDate: fallback.endDate)
            return ExportDateRangeSelection(
                preset: .allTime,
                startDate: range.startDate,
                endDate: range.endDate
            )
        }
    }

    func save(
        preset: ExportDateRangePreset,
        startDate: Date,
        endDate: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        let normalizedRange = normalizedRange(
            startDate: startDate,
            endDate: endDate,
            calendar: calendar
        )

        userDefaults.set(preset.rawValue, forKey: Key.preset)
        userDefaults.set(
            normalizedRange.startDate.timeIntervalSinceReferenceDate,
            forKey: Key.startDate
        )
        userDefaults.set(
            normalizedRange.endDate.timeIntervalSinceReferenceDate,
            forKey: Key.endDate
        )

        guard preset == .custom else { return }

        let today = calendar.startOfDay(for: referenceDate)
        let startOffset = calendar.dateComponents(
            [.day],
            from: today,
            to: normalizedRange.startDate
        ).day ?? 0
        let endOffset = min(
            calendar.dateComponents(
                [.day],
                from: today,
                to: normalizedRange.endDate
            ).day ?? 0,
            0
        )

        userDefaults.set(startOffset, forKey: Key.customStartDayOffset)
        userDefaults.set(endOffset, forKey: Key.customEndDayOffset)
    }

    private func loadRollingCustomRange(
        referenceDate: Date,
        calendar: Calendar
    ) -> ExportDateRange? {
        guard let savedStartOffset = optionalInteger(forKey: Key.customStartDayOffset),
              let savedEndOffset = optionalInteger(forKey: Key.customEndDayOffset) else {
            return nil
        }

        let endOffset = min(savedEndOffset, 0)
        let startOffset = min(savedStartOffset, endOffset)
        let today = calendar.startOfDay(for: referenceDate)
        let startDate = calendar.date(byAdding: .day, value: startOffset, to: today) ?? today
        let endDate = calendar.date(byAdding: .day, value: endOffset, to: today) ?? today

        return normalizedRange(
            startDate: startDate,
            endDate: endDate,
            calendar: calendar
        )
    }

    private func loadStoredAbsoluteRange(calendar: Calendar) -> ExportDateRange? {
        guard let startInterval = optionalTimeInterval(forKey: Key.startDate),
              let endInterval = optionalTimeInterval(forKey: Key.endDate) else {
            return nil
        }

        return normalizedRange(
            startDate: Date(timeIntervalSinceReferenceDate: startInterval),
            endDate: Date(timeIntervalSinceReferenceDate: endInterval),
            calendar: calendar
        )
    }

    private func normalizedRange(
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> ExportDateRange {
        let startOfStart = calendar.startOfDay(for: startDate)
        let startOfEnd = calendar.startOfDay(for: endDate)
        if startOfStart <= startOfEnd {
            return ExportDateRange(startDate: startOfStart, endDate: startOfEnd)
        }
        return ExportDateRange(startDate: startOfEnd, endDate: startOfStart)
    }

    private func optionalInteger(forKey key: String) -> Int? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.integer(forKey: key)
    }

    private func optionalTimeInterval(forKey key: String) -> TimeInterval? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.double(forKey: key)
    }

    // MARK: - Interactive Export Lifecycle

    /// Marks an interactive export as in flight, synchronously before any
    /// export work starts. Cleared on every terminal export path, so a value
    /// left behind means the run was interrupted (crash, kill, force quit).
    func markInteractiveExportBegan() {
        userDefaults.set(true, forKey: Key.interactiveExportInFlight)
    }

    /// Clears the in-flight marker once an interactive export reaches a
    /// terminal path (success, failure, or cancellation).
    func markInteractiveExportEnded() {
        userDefaults.set(false, forKey: Key.interactiveExportInFlight)
    }

    /// Reads and clears the marker left by the previous run. Returns true when
    /// that run ended while an interactive export was still in flight.
    @discardableResult
    func consumeInterruptedInteractiveExportMarker() -> Bool {
        let wasInFlight = userDefaults.bool(forKey: Key.interactiveExportInFlight)
        if wasInFlight {
            userDefaults.set(false, forKey: Key.interactiveExportInFlight)
        }
        return wasInFlight
    }
}

/// Chooses which date-range selection to restore when the app opens.
///
/// All Time is the only preset whose restore can trigger a serial
/// full-history HealthKit scan, so it is also the only preset that may be
/// downgraded: after an interrupted interactive export, restoring it verbatim
/// re-arms the same heavy work that froze the previous run.
enum ExportDateRangeLaunchPolicy {
    /// - Parameters:
    ///   - persisted: The selection loaded from `ExportDateRangeSelectionStore`.
    ///   - hadInterruptedInteractiveExport: True when the previous run ended
    ///     while an interactive export was still in flight.
    ///   - resolvesAllTimeRange: True only for the initial launch restore,
    ///     which may still resolve All Time with a full-history HealthKit
    ///     query. Later foreground activations must reuse the persisted
    ///     absolute range or fall back to Today.
    ///   - referenceDate: Date the restored selection is computed against.
    ///   - calendar: Calendar used for day-boundary comparisons.
    static func selectionToRestore(
        persisted: ExportDateRangeSelection,
        hadInterruptedInteractiveExport: Bool,
        resolvesAllTimeRange: Bool,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ExportDateRangeSelection {
        // Custom, Today, and Yesterday restores are cheap and never downgrade.
        guard persisted.preset == .allTime else { return persisted }

        if hadInterruptedInteractiveExport {
            return ExportDateRangeSelection.defaultSelection(
                referenceDate: referenceDate,
                calendar: calendar
            )
        }

        guard resolvesAllTimeRange || hasUsablePersistedAllTimeRange(
            persisted,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            return ExportDateRangeSelection.defaultSelection(
                referenceDate: referenceDate,
                calendar: calendar
            )
        }

        return persisted
    }

    /// The persisted absolute range is reusable only when it actually carries
    /// resolved All Time dates. The store substitutes the default Today range
    /// when the absolute keys are missing, and a clock change can leave a
    /// range dated in the future; neither should survive a foreground
    /// activation without re-querying HealthKit.
    private static func hasUsablePersistedAllTimeRange(
        _ selection: ExportDateRangeSelection,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        let today = calendar.startOfDay(for: referenceDate)
        if selection.startDate == today, selection.endDate == today {
            return false
        }
        return selection.startDate <= selection.endDate
            && selection.endDate <= today
    }
}

enum ExportDateRangePreset: String, CaseIterable, Codable, Equatable, Identifiable {
    case today
    case yesterday
    case allTime
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return String(localized: "Today")
        case .yesterday:
            return String(localized: "Yesterday")
        case .allTime:
            return String(localized: "All Time")
        case .custom:
            return String(localized: "Custom")
        }
    }

    var accessibilityHint: String {
        switch self {
        case .today:
            return String(localized: "Sets the export date range to today.")
        case .yesterday:
            return String(localized: "Sets the export date range to yesterday.")
        case .allTime:
            return String(localized: "Sets the export date range to all available health data.")
        case .custom:
            return String(localized: "Shows start and end date pickers for a custom export range.")
        }
    }

    func resolvedRange(
        referenceDate: Date = Date(),
        currentStartDate: Date,
        currentEndDate: Date,
        allTimeStartDate: Date? = nil,
        allTimeEndDate: Date? = nil,
        calendar: Calendar = .current
    ) -> ExportDateRange? {
        let today = calendar.startOfDay(for: referenceDate)

        switch self {
        case .today:
            return ExportDateRange(startDate: today, endDate: today)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return ExportDateRange(startDate: yesterday, endDate: yesterday)
        case .allTime:
            guard let allTimeStartDate else { return nil }
            let requestedEndDate = allTimeEndDate ?? referenceDate
            let endDate = requestedEndDate > referenceDate ? referenceDate : requestedEndDate
            return ExportDateRange(
                startDate: calendar.startOfDay(for: allTimeStartDate),
                endDate: calendar.startOfDay(for: endDate)
            )
        case .custom:
            return ExportDateRange(startDate: currentStartDate, endDate: currentEndDate)
        }
    }
}
