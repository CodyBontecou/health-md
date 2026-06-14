import Foundation
import SwiftUI
import Combine

@MainActor
final class VaultManager: ObservableObject {
    @Published var vaultURL: URL?
    @Published var vaultName: String = "No vault selected"
    @Published var healthSubfolder: String = "Health"
    @Published var lastExportStatus: String?
    /// The folder URL of the most recent successful export (vault + health subfolder).
    /// Used to deep-link into the iOS Files app after export.
    @Published var lastExportFolderURL: URL?

    private let bookmarkKey = "obsidianVaultBookmark"
    private let subfolderKey = "healthSubfolder"

    private let defaults: UserDefaultsStoring
    private let fileSystem: FileSystemAccessing
    private let bookmarkResolver: BookmarkResolving

    /// Individual entry exporter for granular tracking
    private let individualExporter = IndividualEntryExporter()

    init(
        defaults: UserDefaultsStoring = SystemUserDefaults(),
        fileSystem: FileSystemAccessing = SystemFileSystem(),
        bookmarkResolver: BookmarkResolving = SystemBookmarkResolver()
    ) {
        self.defaults = defaults
        self.fileSystem = fileSystem
        self.bookmarkResolver = bookmarkResolver
        loadSavedSettings()
    }

    // MARK: - Bookmark Management

    private func loadSavedSettings() {
        // Load subfolder setting
        if let savedSubfolder = defaults.string(forKey: subfolderKey) {
            healthSubfolder = savedSubfolder
        }

        // Load bookmark
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            return
        }

        do {
            let (url, isStale) = try bookmarkResolver.resolveBookmark(data: bookmarkData)

            if isStale {
                // Bookmark is stale, need to re-save it
                if bookmarkResolver.startAccessing(url) {
                    defer { bookmarkResolver.stopAccessing(url) }
                    try saveBookmark(for: url)
                }
            }

            vaultURL = url
            vaultName = url.lastPathComponent
        } catch {
            print("Failed to resolve bookmark: \(error)")
            defaults.removeObject(forKey: bookmarkKey)
        }
    }

    private func saveBookmark(for url: URL) throws {
        let bookmarkData = try bookmarkResolver.createBookmarkData(for: url)
        defaults.set(bookmarkData, forKey: bookmarkKey)
    }

    func saveSubfolderSetting() {
        defaults.set(healthSubfolder, forKey: subfolderKey)
    }

    // MARK: - Folder Selection

    func setVaultFolder(_ url: URL) {
        guard bookmarkResolver.startAccessing(url) else {
            lastExportStatus = "Failed to access folder"
            return
        }

        defer { bookmarkResolver.stopAccessing(url) }

        do {
            try saveBookmark(for: url)
            vaultURL = url
            vaultName = url.lastPathComponent
            lastExportStatus = nil
        } catch {
            lastExportStatus = "Failed to save folder access: \(error.localizedDescription)"
        }
    }

    func clearVaultFolder() {
        defaults.removeObject(forKey: bookmarkKey)
        vaultURL = nil
        vaultName = "No vault selected"
    }

    /// Set a fake vault for UI testing — avoids real bookmark/security-scoped access.
    func setTestVault() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestVault")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vaultURL = tempDir
        vaultName = "TestVault"
    }

    // MARK: - Background Access

    /// Check if we have vault access (for background tasks)
    var hasVaultAccess: Bool {
        vaultURL != nil
    }

    /// Returns whether the selected vault folder can currently be accessed via
    /// its security-scoped bookmark. Used by the Mac export-agent readiness
    /// status before iOS sends an export job.
    func canAccessSelectedVaultFolder() -> Bool {
        guard let vaultURL else { return false }
        guard bookmarkResolver.startAccessing(vaultURL) else { return false }
        bookmarkResolver.stopAccessing(vaultURL)
        return true
    }

    /// Refresh vault access for background tasks
    func refreshVaultAccess() {
        loadSavedSettings()
    }

    /// Start accessing the vault (for background tasks)
    func startVaultAccess() {
        guard let url = vaultURL else { return }
        _ = bookmarkResolver.startAccessing(url)
    }

    /// Stop accessing the vault (for background tasks)
    func stopVaultAccess() {
        guard let url = vaultURL else { return }
        bookmarkResolver.stopAccessing(url)
    }

    /// Export health data without automatic security scope (for background tasks)
    func exportHealthData(_ healthData: HealthData, for date: Date, settings: AdvancedExportSettings) -> Bool {
        guard let vaultURL = vaultURL else {
            return false
        }

        guard healthData.filtered(by: settings.metricSelection).hasAnyData else {
            return false
        }

        guard !settings.exportFormats.isEmpty else { return false }

        do {
            try ensureNoDailyNoteExportCollision(vaultURL: vaultURL, date: date, settings: settings)
            try writeDataDictionary(vaultURL: vaultURL, settings: settings)

            // Write one file per selected format. Each format may resolve to a
            // different folder when file-type organization is enabled.
            for format in settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
                let targetFolderURL = ExportPathPlanner.aggregateFolderURL(
                    vaultURL: vaultURL,
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                )
                if !fileSystem.fileExists(atPath: targetFolderURL.path) {
                    try fileSystem.createDirectory(at: targetFolderURL, withIntermediateDirectories: true)
                }
                _ = try writeOneFormat(
                    healthData: healthData,
                    date: date,
                    format: format,
                    targetFolderURL: targetFolderURL,
                    settings: settings
                )
            }

            // Opt-in side effects run once per date, regardless of which aggregate formats were written.

            // Export individual entries if enabled
            if settings.individualTracking.globalEnabled {
                _ = try exportIndividualEntries(
                    from: healthData,
                    to: individualEntriesBaseFolderURL(vaultURL: vaultURL, date: date, settings: settings),
                    settings: settings
                )
            }

            // Inject selected metrics into the user's daily note if enabled.
            // Daily Note Injection resolves from the selected vault/root destination,
            // not the Health.md export subfolder.
            if settings.dailyNoteInjection.enabled {
                DailyNoteInjector.inject(
                    healthData: healthData,
                    into: vaultURL,
                    settings: settings.dailyNoteInjection,
                    customization: settings.formatCustomization,
                    metricSelection: settings.metricSelection
                )
            }

            return true
        } catch {
            lastExportStatus = error.localizedDescription
            print("Export failed: \(error)")
            return false
        }
    }

    // MARK: - Export

    func exportHealthData(_ healthData: HealthData, settings: AdvancedExportSettings) async throws {
        guard let vaultURL = vaultURL else {
            throw ExportError.noVaultSelected
        }

        guard healthData.filtered(by: settings.metricSelection).hasAnyData else {
            throw ExportError.noHealthData
        }

        guard !settings.exportFormats.isEmpty else {
            throw ExportError.noFormatsSelected
        }

        // Start accessing security-scoped resource
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }

        defer { bookmarkResolver.stopAccessing(vaultURL) }

        try ensureNoDailyNoteExportCollision(vaultURL: vaultURL, date: healthData.date, settings: settings)
        try writeDataDictionary(vaultURL: vaultURL, settings: settings)

        // Record the health-subfolder level so we can deep-link into Files.app
        lastExportFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder
        )

        // Write one file per selected format. Each format may resolve to a
        // different folder when file-type organization is enabled.
        var writtenFiles: [(filename: String, relativePath: String)] = []
        var leadingAction: String = "Exported to"
        for (index, format) in settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }).enumerated() {
            let targetFolderURL = ExportPathPlanner.aggregateFolderURL(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: healthData.date,
                format: format
            )
            if !fileSystem.fileExists(atPath: targetFolderURL.path) {
                try fileSystem.createDirectory(at: targetFolderURL, withIntermediateDirectories: true)
            }
            let result = try writeOneFormat(
                healthData: healthData,
                date: healthData.date,
                format: format,
                targetFolderURL: targetFolderURL,
                settings: settings
            )
            writtenFiles.append((
                filename: result.filename,
                relativePath: ExportPathPlanner.aggregateRelativePath(
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: healthData.date,
                    format: format
                )
            ))
            if index == 0 {
                leadingAction = result.action
            }
        }

        // Opt-in side effects run once per date, regardless of which aggregate formats were written.

        // Export individual entries if enabled
        var individualEntriesCount = 0
        if settings.individualTracking.globalEnabled {
            individualEntriesCount = try exportIndividualEntries(
                from: healthData,
                to: individualEntriesBaseFolderURL(vaultURL: vaultURL, date: healthData.date, settings: settings),
                settings: settings
            )
        }

        // Inject selected metrics into the user's daily note if enabled.
        // Daily Note Injection resolves from the selected vault/root destination,
        // not the Health.md export subfolder.
        var dailyNoteResult: DailyNoteInjector.InjectionResult?
        if settings.dailyNoteInjection.enabled {
            dailyNoteResult = DailyNoteInjector.inject(
                healthData: healthData,
                into: vaultURL,
                settings: settings.dailyNoteInjection,
                customization: settings.formatCustomization,
                metricSelection: settings.metricSelection
            )
        }

        // Build status message showing the relative path. Preserve the concise
        // old shape when all files share one folder; otherwise list per-format paths.
        var statusMessage = "\(leadingAction) \(statusPathSummary(for: writtenFiles))"
        if individualEntriesCount > 0 {
            statusMessage += " + \(individualEntriesCount) individual entr\(individualEntriesCount == 1 ? "y" : "ies")"
        }
        switch dailyNoteResult {
        case .updated(let path):
            statusMessage += " · injected into \(path)"
        case .failed(let error):
            statusMessage += " · daily note injection failed: \(error.localizedDescription)"
        case .skipped(let reason):
            if reason.contains("not found") {
                statusMessage += " · daily note not found (skipped)"
            }
        case .none:
            break
        }
        lastExportStatus = statusMessage
    }

    // MARK: - Data Dictionary

    private func writeDataDictionary(vaultURL: URL, settings: AdvancedExportSettings) throws {
        let folderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder
        )
        if !fileSystem.fileExists(atPath: folderURL.path) {
            try fileSystem.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let entries = HealthMetricDataDictionary.entries(using: settings.formatCustomization)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        guard let json = String(data: data, encoding: .utf8) else { return }
        let fileURL = folderURL.appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename)
        try fileSystem.writeString(json + "\n", to: fileURL, atomically: true)
    }

    // MARK: - Collision Safety

    private func ensureNoDailyNoteExportCollision(
        vaultURL: URL,
        date: Date,
        settings: AdvancedExportSettings
    ) throws {
        if let collision = ExportPathPlanner.dailyNoteExportCollision(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        ) {
            throw ExportError.dailyNotePathConflict(path: collision.dailyNoteRelativePath)
        }
    }

    // MARK: - Per-Format Writer

    /// Writes a single format's file for a single date, honoring the configured write mode.
    /// `.update` merges only for markdown; for non-markdown formats it falls back to overwrite
    /// because they have no heading structure to merge into.
    private func writeOneFormat(
        healthData: HealthData,
        date: Date,
        format: ExportFormat,
        targetFolderURL: URL,
        settings: AdvancedExportSettings
    ) throws -> (filename: String, action: String) {
        let filename = settings.filename(for: date, format: format)
        let fileURL = ExportPathPlanner.fileURL(in: targetFolderURL, filename: filename)
        let parentURL = fileURL.deletingLastPathComponent()
        if !fileSystem.fileExists(atPath: parentURL.path) {
            try fileSystem.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }
        let newContent = healthData.export(format: format, settings: settings)

        let finalContent: String
        let action: String
        if fileSystem.fileExists(atPath: fileURL.path) {
            switch settings.writeMode {
            case .append:
                let existing = try fileSystem.contentsOfFile(at: fileURL)
                finalContent = existing + "\n\n" + newContent
                action = "Appended to"
            case .update:
                if format == .markdown {
                    let existing = try fileSystem.contentsOfFile(at: fileURL)
                    finalContent = MarkdownMerger.merge(existing: existing, new: newContent)
                    action = "Updated"
                } else {
                    finalContent = newContent
                    action = "Exported to"
                }
            case .overwrite:
                finalContent = newContent
                action = "Exported to"
            }
        } else {
            finalContent = newContent
            action = "Exported to"
        }

        try fileSystem.writeString(finalContent, to: fileURL, atomically: true)
        return (filename, action)
    }

    private func individualEntriesBaseFolderURL(
        vaultURL: URL,
        date: Date,
        settings: AdvancedExportSettings
    ) -> URL {
        ExportPathPlanner.aggregateFolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date,
            format: settings.organizeFormatsIntoFolders ? .markdown : nil
        )
    }

    private func statusPathSummary(for writtenFiles: [(filename: String, relativePath: String)]) -> String {
        guard !writtenFiles.isEmpty else { return "" }

        let folderToFilenames = Dictionary(grouping: writtenFiles) { file in
            Self.parentPath(for: file.relativePath)
        }.mapValues { files in
            files.map { $0.filename }
        }

        if folderToFilenames.count == 1,
           let folder = folderToFilenames.keys.first,
           let filenames = folderToFilenames[folder] {
            let prefix = folder.isEmpty ? "" : folder + "/"
            return prefix + filenames.joined(separator: ", ")
        }

        return writtenFiles.map { $0.relativePath }.joined(separator: ", ")
    }

    private static func parentPath(for relativePath: String) -> String {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    // MARK: - Individual Entry Export

    /// Export individual timestamped entries for configured metrics
    private func exportIndividualEntries(
        from healthData: HealthData,
        to baseURL: URL,
        settings: AdvancedExportSettings
    ) throws -> Int {
        let trackingSettings = settings.individualTracking

        // Extract samples that should be tracked individually
        let samples = individualExporter.extractIndividualSamples(
            from: healthData,
            settings: trackingSettings
        )

        guard !samples.isEmpty else { return 0 }

        // Export the samples
        return try individualExporter.exportIndividualEntries(
            samples: samples,
            to: baseURL,
            settings: trackingSettings,
            formatSettings: settings.formatCustomization
        )
    }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case noVaultSelected
    case noHealthData
    case accessDenied
    case noFormatsSelected
    case dailyNotePathConflict(path: String)

    var errorDescription: String? {
        switch self {
        case .noVaultSelected:
            return "Please select an Obsidian vault folder first"
        case .noHealthData:
            return "No health data available for the selected date"
        case .accessDenied:
            return "Cannot access the vault folder. Please re-select it."
        case .noFormatsSelected:
            return "At least one export format must be selected"
        case .dailyNotePathConflict(let path):
            return "Daily Note Injection target conflicts with export output: \(path). Change Output folder/filename or Daily Note Injection folder/filename."
        }
    }
}
