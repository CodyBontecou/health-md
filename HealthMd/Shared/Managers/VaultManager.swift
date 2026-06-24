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
    private let vaultNameKey = "obsidianVaultName"
    private let vaultPathKey = "obsidianVaultPath"
    private let subfolderKey = "healthSubfolder"

    private let defaults: UserDefaultsStoring
    private let fileSystem: FileSystemAccessing
    private let bookmarkResolver: BookmarkResolving

    /// Individual entry exporter for granular tracking
    private let individualExporter = IndividualEntryExporter()

    private static let staleBookmarkRefreshStatus = "Saved folder access needs to be refreshed. Reconnect or re-select the folder."
    private static let savedFolderUnavailableStatus = "Saved folder unavailable. Reconnect the location in Files or re-select the folder."
    private static let folderAccessDeniedStatus = "Cannot access the selected folder. Reconnect the location in Files or re-select the folder."

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
                // Bookmark is stale, need to re-save it. If the refresh fails
                // (common for temporarily disconnected File Provider/network
                // locations), keep the existing bookmark instead of forgetting
                // the user's selected vault.
                if bookmarkResolver.startAccessing(url) {
                    defer { bookmarkResolver.stopAccessing(url) }
                    do {
                        try saveBookmark(for: url)
                    } catch {
                        lastExportStatus = Self.staleBookmarkRefreshStatus
                    }
                }
            }

            vaultURL = url
            vaultName = url.lastPathComponent
            saveVaultMetadata(for: url)
            clearTransientFolderStatusIfNeeded()
        } catch {
            print("Failed to resolve bookmark: \(error)")
            // Do not remove the bookmark here. Network shares and File Provider
            // locations can fail bookmark resolution transiently; preserving the
            // bookmark lets a later app launch/retry recover once Files has
            // reconnected the location.
            vaultURL = nil
            vaultName = defaults.string(forKey: vaultNameKey) ?? "Saved vault unavailable"
            lastExportStatus = Self.savedFolderUnavailableStatus
        }
    }

    private func saveBookmark(for url: URL) throws {
        let bookmarkData = try bookmarkResolver.createBookmarkData(for: url)
        defaults.set(bookmarkData, forKey: bookmarkKey)
    }

    private func saveVaultMetadata(for url: URL) {
        defaults.set(url.lastPathComponent, forKey: vaultNameKey)
        defaults.set(url.path, forKey: vaultPathKey)
    }

    private func clearTransientFolderStatusIfNeeded() {
        switch lastExportStatus {
        case Self.savedFolderUnavailableStatus,
             Self.folderAccessDeniedStatus:
            lastExportStatus = nil
        default:
            break
        }
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
            saveVaultMetadata(for: url)
            vaultURL = url
            vaultName = url.lastPathComponent
            lastExportStatus = nil
        } catch {
            lastExportStatus = "Failed to save folder access: \(error.localizedDescription)"
        }
    }

    func clearVaultFolder() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: vaultNameKey)
        defaults.removeObject(forKey: vaultPathKey)
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

    /// Check if we have a currently resolved vault URL (for background tasks).
    var hasVaultAccess: Bool {
        vaultURL != nil
    }

    /// True when the user previously selected a vault folder, even if the
    /// security-scoped bookmark cannot currently be resolved (for example, an
    /// SMB/File Provider location that Files has disconnected).
    var hasSavedVaultFolder: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    var isVaultConfigured: Bool {
        vaultURL != nil || hasSavedVaultFolder
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
    @discardableResult
    func startVaultAccess() -> Bool {
        guard let url = vaultURL else {
            if hasSavedVaultFolder {
                lastExportStatus = Self.savedFolderUnavailableStatus
            }
            return false
        }
        let didStartAccess = bookmarkResolver.startAccessing(url)
        if !didStartAccess {
            lastExportStatus = Self.folderAccessDeniedStatus
        }
        return didStartAccess
    }

    /// Stop accessing the vault (for background tasks)
    func stopVaultAccess() {
        guard let url = vaultURL else { return }
        bookmarkResolver.stopAccessing(url)
    }

    /// Export health data without automatic security scope (for background tasks)
    func exportHealthData(_ healthData: HealthData, for date: Date, settings: AdvancedExportSettings) -> Bool {
        guard let vaultURL = vaultURL else {
            if hasSavedVaultFolder {
                lastExportStatus = Self.savedFolderUnavailableStatus
            }
            return false
        }

        guard healthData.filtered(by: settings.metricSelection).hasAnyData else {
            return false
        }

        guard !settings.exportFormats.isEmpty else { return false }

        do {
            try ensureNoDailyNoteExportCollision(vaultURL: vaultURL, date: date, settings: settings)
            if !settings.archiveExportFiles {
                try writeDataDictionary(vaultURL: vaultURL, settings: settings)
            }

            // Write one file per selected format. Each format may resolve to a
            // different folder when file-type organization is enabled.
            for format in looseExportFormats(in: settings) {
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
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
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
        if !settings.archiveExportFiles {
            try writeDataDictionary(vaultURL: vaultURL, settings: settings)
        }

        // Record the health-subfolder level so we can deep-link into Files.app
        lastExportFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder
        )

        // Write one file per selected format. Each format may resolve to a
        // different folder when file-type organization is enabled.
        var writtenFiles: [(filename: String, relativePath: String)] = []
        var leadingAction: String = "Exported to"
        for (index, format) in looseExportFormats(in: settings).enumerated() {
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
        var statusMessage: String
        if writtenFiles.isEmpty && settings.archiveExportFiles {
            statusMessage = "Prepared files for ZIP archive"
        } else {
            statusMessage = "\(leadingAction) \(statusPathSummary(for: writtenFiles))"
        }
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

    // MARK: - ZIP Archives

    @discardableResult
    func exportArchive(
        from healthData: [HealthData],
        settings: AdvancedExportSettings,
        startDate: Date,
        endDate: Date
    ) throws -> URL? {
        guard settings.archiveExportFiles else { return nil }
        let archivedFormats = settings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard !archivedFormats.isEmpty, !healthData.isEmpty else { return nil }
        guard let vaultURL = vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        var entries = [dataDictionaryArchiveEntry(settings: settings)]
        entries += healthData.sorted(by: { $0.date < $1.date }).flatMap { data in
            archivedFormats.compactMap { format -> ZipArchiveWriter.Entry? in
                let content = data.export(format: format, settings: settings)
                guard let bytes = content.data(using: .utf8) else { return nil }
                return ZipArchiveWriter.Entry(
                    path: archiveEntryPath(for: data.date, format: format, settings: settings),
                    data: bytes
                )
            }
        }
        guard !entries.isEmpty else { return nil }

        let healthFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder
        )
        if !fileSystem.fileExists(atPath: healthFolderURL.path) {
            try fileSystem.createDirectory(at: healthFolderURL, withIntermediateDirectories: true)
        }
        let archiveURL = healthFolderURL.appendingPathComponent(
            archiveFilename(startDate: startDate, endDate: endDate),
            isDirectory: false
        )
        try ZipArchiveWriter.write(entries: entries, to: archiveURL)
        lastExportFolderURL = healthFolderURL
        lastExportStatus = "Exported ZIP archive: \(archiveURL.lastPathComponent)"
        return archiveURL
    }

    private func archiveEntryPath(for date: Date, format: ExportFormat, settings: AdvancedExportSettings) -> String {
        var components: [String] = []
        if let folderPath = settings.formatFolderPath(for: date, format: format) {
            components.append(folderPath)
        }
        components.append(settings.filename(for: date, format: format))
        return components.joined(separator: "/")
    }

    private func dataDictionaryArchiveEntry(settings: AdvancedExportSettings) -> ZipArchiveWriter.Entry {
        let entries = HealthMetricDataDictionary.entries(using: settings.formatCustomization)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(entries)) ?? Data("[]".utf8)
        let normalizedData: Data
        if var json = String(data: data, encoding: .utf8) {
            json += "\n"
            normalizedData = Data(json.utf8)
        } else {
            normalizedData = data
        }
        return ZipArchiveWriter.Entry(
            path: HealthMdExportSchema.dataDictionaryFilename,
            data: normalizedData
        )
    }

    private func archiveFilename(startDate: Date, endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let range = start == end ? start : "\(start)_to_\(end)"
        return "Health.md Export \(range).zip"
    }

    // MARK: - Roll-up Summaries

    @discardableResult
    func exportRollupSummaries(
        from healthData: [HealthData],
        settings: AdvancedExportSettings,
        generatedAt: Date = Date()
    ) throws -> [HealthRollupWriteResult] {
        guard let vaultURL = vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }

        guard HealthRollupExporter.isEnabled(settings: settings) else { return [] }

        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let summaries = HealthRollupExporter.makeSummaries(
            from: healthData,
            settings: settings,
            generatedAt: generatedAt
        )
        guard !summaries.isEmpty else { return [] }

        var results: [HealthRollupWriteResult] = []
        for target in HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: healthSubfolder,
            settings: settings
        ) {
            let folderURL = HealthRollupExporter.folderURL(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                period: target.summary.period,
                format: target.format,
                settings: settings
            )
            if !fileSystem.fileExists(atPath: folderURL.path) {
                try fileSystem.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }

            let fileURL = ExportPathPlanner.fileURL(in: folderURL, filename: target.filename)
            try fileSystem.writeString(target.content, to: fileURL, atomically: true)
            results.append(target)
        }

        return results
    }

    // MARK: - Format Routing

    private func looseExportFormats(in settings: AdvancedExportSettings) -> [ExportFormat] {
        settings.exportFormats
            .filter { _ in !settings.archiveExportFiles }
            .sorted(by: { $0.rawValue < $1.rawValue })
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
            return "Cannot access the vault folder. Reconnect it in Files or re-select it."
        case .noFormatsSelected:
            return "At least one export format must be selected"
        case .dailyNotePathConflict(let path):
            return "Daily Note Injection target conflicts with export output: \(path). Change Output folder/filename or Daily Note Injection folder/filename."
        }
    }
}
