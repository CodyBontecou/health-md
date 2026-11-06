#if os(iOS)
import Foundation

/// Where one automation writes a date, for the Archive day rows.
enum ArchiveOutputPath: Equatable {
    /// Files under a folder root: the Health subfolder, the dated folder structure
    /// and the filename come from the profile's own output settings.
    case files(root: String, healthSubfolder: String, settings: ExportSettingsSnapshot)
    /// An HTTP destination. `line` is already `POST host/path`.
    case endpoint(line: String)
    /// Nothing more specific is known than the destination label.
    case label(String)

    /// The root alone, shown for dates with no file of their own.
    var root: String {
        switch self {
        case .files(let root, _, _): return root
        case .endpoint(let line): return line
        case .label(let label): return label
        }
    }

    /// `Vault/Health/2026-10-19.md` for written or due dates, the root otherwise.
    func display(on date: Date, status: CoverageStatus) -> String {
        guard status != .notDue, status != .paused else { return root }
        guard case .files(let root, let subfolder, let snapshot) = self,
              let relative = Self.relativeFilePath(on: date, healthSubfolder: subfolder, settings: snapshot) else {
            return root
        }
        guard !root.isEmpty else { return relative }
        return root.hasSuffix("/") ? root + relative : root + "/" + relative
    }

    /// The date's file relative to the destination folder, or nil for destinations
    /// without one (endpoints, labels, daily-note-only output).
    func relativeFilePath(on date: Date) -> String? {
        guard case .files(_, let subfolder, let snapshot) = self else { return nil }
        return Self.relativeFilePath(on: date, healthSubfolder: subfolder, settings: snapshot)
    }

    /// The exact file the automation wrote for a date under its folder root.
    func fileURL(on date: Date, rootURL: URL) -> URL? {
        relativeFilePath(on: date).map { ArchiveFileLocation.fileURL(relativePath: $0, rootURL: rootURL) }
    }

    /// The first format's file for a date, built the way the exporter builds it.
    static func relativeFilePath(
        on date: Date,
        healthSubfolder: String,
        settings snapshot: ExportSettingsSnapshot
    ) -> String? {
        guard let format = ExportProfileCardSummary.sortedFormats(snapshot.exportFormats).first,
              !snapshot.dailyNotesOnlyModeEnabled,
              let defaults = UserDefaults(suiteName: "com.healthmd.glass.archive-path") else { return nil }
        let settings = snapshot.makeAdvancedExportSettings(userDefaults: defaults)
        return ExportPathPlanner.aggregateRelativePath(
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date,
            format: format
        )
    }

    /// `POST api.example.com/health`. Scheme, credentials, query and fragment are left out.
    static func endpointLine(_ url: URL?) -> String? {
        guard let url, let host = url.host(), !host.isEmpty else { return nil }
        var path = url.path()
        if path == "/" { path = "" }
        let port = url.port.map { ":\($0)" } ?? ""
        return "POST \(host)\(port)\(path)"
    }
}

/// What an Archive day's "Open" shows, decided off the main thread.
enum ArchiveFileLocation: Equatable {
    /// The automation's own file for the date.
    case file(URL)
    /// The file is gone; its folder (or the destination root) still exists.
    case folder(URL)
    case unavailable

    /// Resolves the folder (a saved bookmark, else `fallbackRootURL`), then checks the
    /// expected file, its folder and the root. Reads the disk, so call it off the main actor.
    nonisolated static func locate(
        relativePath: String,
        bookmarkData: Data?,
        fallbackRootURL: URL?
    ) -> (location: ArchiveFileLocation, rootURL: URL?) {
        var rootURL = fallbackRootURL
        if let bookmarkData {
            var isStale = false
            rootURL = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
        guard let rootURL else { return (.unavailable, nil) }
        let didAccess = rootURL.startAccessingSecurityScopedResource()
        defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
        let file = fileURL(relativePath: relativePath, rootURL: rootURL)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return (.file(file), rootURL)
        }
        let folder = file.deletingLastPathComponent()
        if fileManager.fileExists(atPath: folder.path) { return (.folder(folder), rootURL) }
        if fileManager.fileExists(atPath: rootURL.path) { return (.folder(rootURL), rootURL) }
        return (.unavailable, rootURL)
    }

    /// `root/Health/2026-10-19.md` from the planner's slash-separated relative path.
    nonisolated static func fileURL(relativePath: String, rootURL: URL) -> URL {
        let segments = relativePath.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return segments.enumerated().reduce(rootURL) { url, item in
            url.appendingPathComponent(item.element, isDirectory: item.offset < segments.count - 1)
        }
    }
}

/// Weekly cadence facts for the day rows.
enum ArchiveWeekly {
    /// The first scheduled weekday after `date`; a weekly run covers the days before it.
    /// `isoWeekday` is 1 = Monday … 7 = Sunday, as `ExportSchedule.weekday` stores it.
    static func coveringFireDay(for date: Date, isoWeekday: Int, calendar: Calendar) -> Date? {
        let target = isoWeekday % 7 + 1
        let day = calendar.startOfDay(for: date)
        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: day) else { return nil }
            if calendar.component(.weekday, from: candidate) == target { return candidate }
        }
        return nil
    }

    /// The days one weekly file covers: the look-back window ending the day before it runs.
    static func coveredRange(
        for date: Date,
        isoWeekday: Int,
        lookbackDays: Int,
        calendar: Calendar
    ) -> ClosedRange<Date>? {
        guard let fire = coveringFireDay(for: date, isoWeekday: isoWeekday, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: -1, to: fire),
              let start = calendar.date(byAdding: .day, value: -max(1, lookbackDays), to: fire),
              start <= end else { return nil }
        return start...end
    }

    /// Localized name of the scheduled weekday, e.g. "Sunday".
    static func weekdayName(isoWeekday: Int, calendar: Calendar) -> String {
        let symbols = calendar.weekdaySymbols
        let index = isoWeekday % 7
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

enum ArchivePause {
    /// When the current pause began, from the ledger's schedule timeline. A pause the
    /// ledger only inferred while seeding from older history has no real date, so it
    /// returns nil rather than the seeding time.
    static func since(
        events: [CoverageScheduleEvent],
        isPaused: Bool,
        ledgerStartedAt: Date,
        didSeedFromHistory: Bool
    ) -> Date? {
        guard isPaused, let last = events.last, !last.isEnabled else { return nil }
        let inferredAtSeeding = didSeedFromHistory
            && events.count == 1
            && abs(last.date.timeIntervalSince(ledgerStartedAt)) < 120
        return inferredAtSeeding ? nil : last.date
    }
}

/// Facts behind the Needs attention copy, kept pure for tests.
enum ArchiveAttention {
    /// `HTTP 503` in a stored, status-only error description.
    static func httpStatus(in text: String?) -> Int? {
        guard let text, let range = text.range(of: #"HTTP (\d{3})"#, options: .regularExpression) else {
            return nil
        }
        return Int(text[range].dropFirst(5))
    }

    /// Failed runs in a row, newest first, before the first run that wrote anything.
    static func consecutiveFailures(_ statuses: [ExportHistoryEntry.PresentationStatus]) -> Int {
        statuses.prefix { $0 == .failed }.count
    }

    /// The status repeated across the failure streak, if every failure reported the same one.
    static func repeatedStatus(_ descriptions: [String?]) -> Int? {
        let codes = descriptions.map(httpStatus(in:))
        guard let first = codes.first ?? nil, codes.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}
#endif
