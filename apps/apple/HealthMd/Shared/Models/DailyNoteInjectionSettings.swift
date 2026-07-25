//
//  DailyNoteInjectionSettings.swift
//  Health.md
//
//  Settings for injecting select health metrics into existing daily notes' YAML frontmatter.
//

import Foundation
import Combine

// MARK: - Daily Note Injection Settings

class DailyNoteInjectionSettings: ObservableObject, Codable {

    // MARK: - Published Properties

    /// Master switch — when false, nothing is injected
    @Published var enabled: Bool

    /// Vault-relative folder containing the daily notes, e.g. "Daily" or "Journal/Daily".
    /// Leave empty to look in the vault root.
    @Published var folderPath: String

    /// Filename pattern for daily notes (without extension).
    /// Supports: {date}, {year}, {YR}, {month}, {day}, {weekday}, {monthName}, {quarter}
    @Published var filenamePattern: String

    /// When true, create the daily note file if it does not exist.
    /// When false (default), skip silently if the file is missing.
    @Published var createIfMissing: Bool

    /// When true, also inject the markdown export's body sections (Sleep, Activity, …)
    /// into the note, in addition to YAML frontmatter. App-managed sections are
    /// replaced on each export; user-added sections and the existing preamble are
    /// preserved. Default false — frontmatter-only behavior.
    @Published var injectMarkdownSections: Bool

    /// When true, Daily Note Injection is the only file-destination output.
    /// Aggregate formats, archives, roll-ups, individual entries, provider
    /// sidecars, and the data dictionary remain configured but are not written.
    @Published var dailyNotesOnly: Bool

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case enabled, folderPath, filenamePattern, createIfMissing, injectMarkdownSections, dailyNotesOnly
    }

    // MARK: - Init

    init() {
        self.enabled = false
        self.folderPath = "Daily"
        self.filenamePattern = "{date}"
        self.createIfMissing = false
        self.injectMarkdownSections = false
        self.dailyNotesOnly = false
        #if DEBUG
        LifecycleTracker.trackCreation(of: "DailyNoteInjectionSettings")
        #endif
    }

    deinit {
        #if DEBUG
        LifecycleTracker.trackDeinit(of: "DailyNoteInjectionSettings")
        #endif
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled                = try c.decodeIfPresent(Bool.self,   forKey: .enabled)                ?? false
        folderPath             = try c.decodeIfPresent(String.self, forKey: .folderPath)             ?? "Daily"
        filenamePattern        = try c.decodeIfPresent(String.self, forKey: .filenamePattern)        ?? "{date}"
        createIfMissing        = try c.decodeIfPresent(Bool.self,   forKey: .createIfMissing)        ?? false
        injectMarkdownSections = try c.decodeIfPresent(Bool.self,   forKey: .injectMarkdownSections) ?? false
        dailyNotesOnly         = try c.decodeIfPresent(Bool.self,   forKey: .dailyNotesOnly)         ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled,                forKey: .enabled)
        try c.encode(folderPath,             forKey: .folderPath)
        try c.encode(filenamePattern,        forKey: .filenamePattern)
        try c.encode(createIfMissing,        forKey: .createIfMissing)
        try c.encode(injectMarkdownSections, forKey: .injectMarkdownSections)
        try c.encode(dailyNotesOnly,         forKey: .dailyNotesOnly)
    }

    // MARK: - Helpers

    func reset() {
        enabled = false
        folderPath = "Daily"
        filenamePattern = "{date}"
        createIfMissing = false
        injectMarkdownSections = false
        dailyNotesOnly = false
    }

    /// Format a filename from the pattern for a given date
    func formatFilename(for date: Date) -> String {
        let fmt = DateFormatter()
        var result = filenamePattern

        fmt.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: fmt.string(from: date))

        fmt.dateFormat = "yyyy"
        result = result.replacingOccurrences(of: "{year}", with: fmt.string(from: date))

        fmt.dateFormat = "yy"
        result = result.replacingOccurrences(of: "{YR}", with: fmt.string(from: date))

        fmt.dateFormat = "MM"
        result = result.replacingOccurrences(of: "{month}", with: fmt.string(from: date))

        fmt.dateFormat = "dd"
        result = result.replacingOccurrences(of: "{day}", with: fmt.string(from: date))

        fmt.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: "{weekday}", with: fmt.string(from: date))

        fmt.dateFormat = "MMMM"
        result = result.replacingOccurrences(of: "{monthName}", with: fmt.string(from: date))

        let month = Calendar.current.component(.month, from: date)
        result = result.replacingOccurrences(of: "{quarter}", with: "Q\((month - 1) / 3 + 1)")

        return result
    }

    /// Vault-root-relative preview path for the target daily note.
    /// e.g. healthSubfolder="Health", folderPath="Daily" → "Daily/2026-03-25.md".
    /// The `healthSubfolder` parameter is retained for source compatibility but ignored;
    /// Daily Note Injection paths resolve from the selected vault/root destination.
    func previewPath(for date: Date, healthSubfolder _: String = "") -> String {
        ExportPathPlanner.dailyNoteRelativePath(settings: self, date: date)
    }
}
