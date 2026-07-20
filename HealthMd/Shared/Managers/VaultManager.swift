import Foundation
import SwiftUI
import Combine

nonisolated struct RenderedHealthDataArchiveEntryFile: Sendable {
    let date: Date
    let archivePath: String
    let order: Int
    let url: URL
}

nonisolated private enum HealthDataArchiveSource: Sendable {
    case inMemory(HealthData)
    case file(RenderedHealthDataArchiveEntryFile)

    var date: Date {
        switch self {
        case .inMemory(let record): return record.date
        case .file(let file): return file.date
        }
    }

    var order: Int {
        switch self {
        case .inMemory: return 0
        case .file(let file): return file.order
        }
    }
}

struct DailyExportWriteResult {
    let aggregateFileCount: Int
    let individualEntryFileCount: Int
    let dailyNoteResult: DailyNoteInjector.InjectionResult?

    var dailyNoteUpdatedCount: Int {
        if case .updated = dailyNoteResult { return 1 }
        return 0
    }

    var dailyNoteSkippedCount: Int {
        if case .skipped = dailyNoteResult { return 1 }
        return 0
    }

    var dailyNoteFailure: Error? {
        if case .failed(let error) = dailyNoteResult { return error }
        return nil
    }

    static let noOutput = DailyExportWriteResult(
        aggregateFileCount: 0,
        individualEntryFileCount: 0,
        dailyNoteResult: nil
    )
}

@MainActor
final class VaultManager: ObservableObject {
    static let defaultHealthSubfolder = "Health"

    @Published var vaultURL: URL?
    @Published var vaultName: String = "No vault selected"
    @Published var healthSubfolder: String = VaultManager.defaultHealthSubfolder
    @Published var lastExportStatus: String?
    /// The folder URL of the most recent successful export (vault + health subfolder).
    /// Used to deep-link into the iOS Files app after export.
    @Published var lastExportFolderURL: URL?

    private let bookmarkKey = "obsidianVaultBookmark"
    private let vaultNameKey = "obsidianVaultName"
    private let vaultPathKey = "obsidianVaultPath"
    private static let subfolderKey = "healthSubfolder"

    private let defaults: UserDefaultsStoring
    private let fileSystem: FileSystemAccessing
    private let bookmarkResolver: BookmarkResolving

    #if DEBUG
    var archiveEntryWillAppendForTesting: (() -> Void)?
    #endif

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

    static func savedHealthSubfolder(
        defaults: UserDefaultsStoring = SystemUserDefaults()
    ) -> String {
        defaults.string(forKey: subfolderKey) ?? defaultHealthSubfolder
    }

    private func loadSavedSettings() {
        healthSubfolder = Self.savedHealthSubfolder(defaults: defaults)

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
        defaults.set(healthSubfolder, forKey: Self.subfolderKey)
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

    /// Export health data without automatic security scope (for background tasks).
    /// The Boolean compatibility wrapper reports whether the configured primary
    /// output completed; callers that need Daily Note outcome details should use
    /// `exportHealthDataResult`.
    func exportHealthData(_ healthData: HealthData, for date: Date, settings: AdvancedExportSettings) -> Bool {
        do {
            let result = try exportHealthDataResult(healthData, for: date, settings: settings)
            return !settings.dailyNotesOnlyModeEnabled || result.dailyNoteUpdatedCount > 0
        } catch {
            lastExportStatus = error.localizedDescription
            print("Export failed: \(error)")
            return false
        }
    }

    func exportHealthDataResult(
        _ healthData: HealthData,
        for date: Date,
        settings: AdvancedExportSettings,
        writeDataDictionary shouldWriteDataDictionary: Bool = true,
        preparedExport suppliedPreparedExport: PreparedHealthDataExport? = nil
    ) throws -> DailyExportWriteResult {
        guard let vaultURL else {
            if hasSavedVaultFolder {
                lastExportStatus = Self.savedFolderUnavailableStatus
            }
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        let preparedExport = suppliedPreparedExport
            ?? healthData.preparedExport(settings: settings)
        guard preparedExport.hasAnyData else {
            throw ExportError.noHealthData
        }
        guard settings.hasFileDestinationOutput else {
            throw ExportError.noFormatsSelected
        }
        guard !settings.summaryOnlyModeEnabled else {
            lastExportStatus = "Skipped daily files in summary-only mode"
            return .noOutput
        }

        return try writeHealthDataOutputs(
            healthData,
            date: date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            shouldWriteDataDictionary: shouldWriteDataDictionary,
            preparedExport: preparedExport
        )
    }

    // MARK: - Export

    @discardableResult
    func exportHealthData(
        _ healthData: HealthData,
        settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        writeDataDictionary shouldWriteDataDictionary: Bool = true
    ) async throws -> DailyExportWriteResult {
        guard let vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        let preparedExport = healthData.preparedExport(settings: settings)
        guard preparedExport.hasAnyData else {
            throw ExportError.noHealthData
        }
        guard settings.hasFileDestinationOutput else {
            throw ExportError.noFormatsSelected
        }
        guard !settings.summaryOnlyModeEnabled else {
            lastExportStatus = "Skipped daily files in summary-only mode"
            return .noOutput
        }
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        return try writeHealthDataOutputs(
            healthData,
            date: healthData.date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder,
            settings: settings,
            shouldWriteDataDictionary: shouldWriteDataDictionary,
            preparedExport: preparedExport
        )
    }

    private func writeHealthDataOutputs(
        _ healthData: HealthData,
        date: Date,
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        shouldWriteDataDictionary: Bool,
        preparedExport: PreparedHealthDataExport
    ) throws -> DailyExportWriteResult {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        #endif
        if !settings.dailyNotesOnlyModeEnabled {
            try ensureNoDailyNoteExportCollision(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                date: date,
                settings: settings
            )
            if !settings.archiveModeEnabled && shouldWriteDataDictionary {
                try writeDataDictionary(
                    vaultURL: vaultURL,
                    healthSubfolder: healthSubfolder,
                    settings: settings
                )
            }
            lastExportFolderURL = ExportPathPlanner.healthSubfolderURL(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder
            )
        } else {
            lastExportFolderURL = ExportPathPlanner.dailyNoteURL(
                vaultURL: vaultURL,
                settings: settings.dailyNoteInjection,
                date: date
            ).deletingLastPathComponent()
        }

        var writtenFiles: [(filename: String, relativePath: String)] = []
        var leadingAction = "Exported to"
        for (index, format) in looseExportFormats(in: settings).enumerated() {
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
            let result = try writeOneFormat(
                preparedExport: preparedExport,
                date: date,
                format: format,
                targetFolderURL: targetFolderURL,
                settings: settings
            )
            writtenFiles.append((
                filename: result.filename,
                relativePath: ExportPathPlanner.aggregateRelativePath(
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                )
            ))
            if index == 0 { leadingAction = result.action }
        }

        var individualEntriesCount = 0
        if settings.writesIndividualEntryFiles {
            individualEntriesCount = try exportIndividualEntries(
                from: healthData,
                to: individualEntriesBaseFolderURL(
                    vaultURL: vaultURL,
                    healthSubfolder: healthSubfolder,
                    date: date,
                    settings: settings
                ),
                settings: settings
            )
        }

        let dailyNoteResult: DailyNoteInjector.InjectionResult? = settings.dailyNoteInjection.enabled
            ? DailyNoteInjector.inject(
                healthData: healthData,
                into: vaultURL,
                settings: settings.dailyNoteInjection,
                customization: settings.formatCustomization,
                metricSelection: settings.metricSelection
            )
            : nil

        if settings.dailyNotesOnlyModeEnabled {
            switch dailyNoteResult {
            case .updated(let path):
                lastExportStatus = "Updated daily note \(path)"
            case .failed(let error):
                lastExportStatus = "Daily note update failed: \(error.localizedDescription)"
            case .skipped(let reason):
                lastExportStatus = "Daily note skipped: \(reason)"
            case .none:
                lastExportStatus = "Daily note update was not performed"
            }
        } else {
            var statusMessage: String
            if writtenFiles.isEmpty && settings.archiveModeEnabled {
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
            case .skipped(let reason) where reason.contains("not found"):
                statusMessage += " · daily note not found (skipped)"
            case .skipped, .none:
                break
            }
            lastExportStatus = statusMessage
        }

        #if DEBUG
        ExportPerformanceInstrumentation.completed(
            pipeline: "local-files",
            phase: "daily-write",
            timer: performanceTimer,
            itemCount: writtenFiles.count + individualEntriesCount
        )
        #endif
        return DailyExportWriteResult(
            aggregateFileCount: writtenFiles.count,
            individualEntryFileCount: individualEntriesCount,
            dailyNoteResult: dailyNoteResult
        )
    }

    // MARK: - External Provider Sidecar Exports

    @discardableResult
    func exportExternalDailyRecords(
        _ records: [ExternalDailyRecord],
        healthSubfolder: String? = nil
    ) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        guard let vaultURL = vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }

        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let healthFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder
        )
        let integrationsFolderURL = healthFolderURL.appendingPathComponent("integrations", isDirectory: true)

        var writtenCount = 0
        for record in records where record.shouldExport {
            guard record.hasValidExportDate else {
                throw ExternalProviderExportError.invalidDate(record.date)
            }
            let providerFolderURL = integrationsFolderURL.appendingPathComponent(record.provider.exportFolderName, isDirectory: true)
            if !fileSystem.fileExists(atPath: providerFolderURL.path) {
                try fileSystem.createDirectory(at: providerFolderURL, withIntermediateDirectories: true)
            }

            let data = try encoder.encode(record)
            guard let json = String(data: data, encoding: .utf8) else { continue }
            let fileURL = providerFolderURL.appendingPathComponent("\(record.date).json")
            try fileSystem.writeString(json, to: fileURL, atomically: true)
            writtenCount += 1
        }

        if writtenCount > 0 {
            lastExportFolderURL = healthFolderURL
        }
        return writtenCount
    }

    // MARK: - ZIP Archives

    @discardableResult
    func exportArchive(
        from healthData: [HealthData],
        rollupHealthData: [HealthData] = [],
        settings: AdvancedExportSettings,
        startDate: Date,
        endDate: Date,
        healthSubfolder: String? = nil
    ) async throws -> URL? {
        try await exportArchive(
            sources: healthData.map(HealthDataArchiveSource.inMemory),
            rollupHealthData: rollupHealthData,
            settings: settings,
            startDate: startDate,
            endDate: endDate,
            healthSubfolder: healthSubfolder
        )
    }

    @discardableResult
    func exportArchive(
        fromRenderedFiles files: [RenderedHealthDataArchiveEntryFile],
        rollupHealthData: [HealthData] = [],
        settings: AdvancedExportSettings,
        startDate: Date,
        endDate: Date,
        healthSubfolder: String? = nil
    ) async throws -> URL? {
        try await exportArchive(
            sources: files.map(HealthDataArchiveSource.file),
            rollupHealthData: rollupHealthData,
            settings: settings,
            startDate: startDate,
            endDate: endDate,
            healthSubfolder: healthSubfolder
        )
    }

    private func exportArchive(
        sources: [HealthDataArchiveSource],
        rollupHealthData: [HealthData],
        settings: AdvancedExportSettings,
        startDate: Date,
        endDate: Date,
        healthSubfolder: String?
    ) async throws -> URL? {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "local-files",
                phase: "zip-archive",
                timer: performanceTimer,
                itemCount: sources.count
            )
        }
        #endif
        guard settings.archiveModeEnabled else { return nil }
        let archivedFormats = settings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard !archivedFormats.isEmpty else { return nil }
        guard !sources.isEmpty || (settings.summaryOnlyModeEnabled && !rollupHealthData.isEmpty) else { return nil }
        guard let vaultURL = vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let rollupEntries = rollupArchiveEntries(from: rollupHealthData, settings: settings)
        if settings.summaryOnlyModeEnabled && rollupEntries.isEmpty { return nil }

        let healthFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder
        )
        if !fileSystem.fileExists(atPath: healthFolderURL.path) {
            try fileSystem.createDirectory(at: healthFolderURL, withIntermediateDirectories: true)
        }
        let archiveURL = healthFolderURL.appendingPathComponent(
            archiveFilename(startDate: startDate, endDate: endDate),
            isDirectory: false
        )
        let checkpointURL = healthFolderURL.appendingPathComponent(
            ".\(archiveURL.lastPathComponent).zip-checkpoint-\(UUID().uuidString)",
            isDirectory: false
        )
        let writer = try ZipArchiveWriter.begin(
            to: archiveURL,
            checkpointURL: checkpointURL
        )
        do {
            let dictionaryEntry = dataDictionaryArchiveEntry(settings: settings)
            #if DEBUG
            archiveEntryWillAppendForTesting?()
            #endif
            try await Self.performArchiveIO {
                try writer.append(
                    dictionaryEntry,
                    cancellationCheck: { Task.isCancelled }
                )
            }
            if !settings.summaryOnlyModeEnabled {
                let orderedSources = sources.sorted {
                    if $0.date != $1.date { return $0.date < $1.date }
                    return $0.order < $1.order
                }
                for source in orderedSources {
                    try Task.checkCancellation()
                    switch source {
                    case .inMemory(let data):
                        let preparedExport = data.preparedExport(settings: settings)
                        for format in archivedFormats {
                            try Task.checkCancellation()
                            let content = try preparedExport.content(format: format, settings: settings)
                            guard let bytes = content.data(using: .utf8) else {
                                throw CocoaError(.fileWriteInapplicableStringEncoding)
                            }
                            let entry = ZipArchiveWriter.Entry(
                                path: archiveEntryPath(
                                    for: data.date,
                                    format: format,
                                    settings: settings
                                ),
                                data: bytes
                            )
                            try await Self.performArchiveIO {
                                try writer.append(entry, cancellationCheck: { Task.isCancelled })
                            }
                            await Task.yield()
                        }
                    case .file(let file):
                        try await Self.performArchiveIO {
                            try writer.append(
                                ZipArchiveWriter.FileEntry(
                                    path: file.archivePath,
                                    sourceURL: file.url
                                ),
                                cancellationCheck: { Task.isCancelled }
                            )
                        }
                        await Task.yield()
                    }
                }
            }
            for entry in rollupEntries {
                try Task.checkCancellation()
                try await Self.performArchiveIO {
                    try writer.append(entry, cancellationCheck: { Task.isCancelled })
                }
                await Task.yield()
            }
            try await Self.performArchiveIO {
                try writer.finish(cancellationCheck: { Task.isCancelled })
            }
        } catch {
            try? await Self.performArchiveIO { writer.abandon() }
            throw error
        }
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

    private func rollupArchiveEntries(from healthData: [HealthData], settings: AdvancedExportSettings) -> [ZipArchiveWriter.Entry] {
        guard HealthRollupExporter.isEnabled(settings: settings), !healthData.isEmpty else { return [] }
        let summaries = HealthRollupExporter.makeSummaries(from: healthData, settings: settings)
        return HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: "",
            settings: settings
        ).compactMap { target in
            guard let data = target.content.data(using: .utf8) else { return nil }
            return ZipArchiveWriter.Entry(path: target.relativePath, data: data)
        }
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

    private func archiveFilename(
        startDate: Date,
        endDate: Date,
        timeZone: TimeZone? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone ?? .current
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
        generatedAt: Date = Date(),
        healthSubfolder: String? = nil,
        writeDataDictionary shouldWriteDataDictionary: Bool = true
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

        let effectiveHealthSubfolder = healthSubfolder ?? self.healthSubfolder
        if shouldWriteDataDictionary {
            try writeDataDictionary(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                settings: settings
            )
        }

        var results: [HealthRollupWriteResult] = []
        for target in HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: effectiveHealthSubfolder,
            settings: settings
        ) {
            let folderURL = HealthRollupExporter.folderURL(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
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

    nonisolated private static func performArchiveIO<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func writeCompactRollupProjection(
        sourceURL: URL,
        destinationURL: URL
    ) async throws -> Bool {
        try Task.checkCancellation()
        let payload = try JSONDecoder().decode(
            ConnectedCorpusHealthDayPayload.self,
            from: Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        )
        guard let record = payload.record else { return false }
        let projection = ConnectedExportGranularMode.sanitized(
            record,
            includesGranularData: false
        )
        try JSONEncoder().encode(projection).write(to: destinationURL, options: .atomic)
        return true
    }

    nonisolated private static func decodeHealthData(from url: URL) async throws -> HealthData {
        try Task.checkCancellation()
        return try JSONDecoder().decode(
            HealthData.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
    }

    nonisolated private static func decodeConnectedHealthData(
        from url: URL
    ) async throws -> HealthData? {
        try Task.checkCancellation()
        return try JSONDecoder().decode(
            ConnectedCorpusHealthDayPayload.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        ).record
    }

    /// Finalizes derived output for a partitioned connected export while
    /// retaining at most one roll-up window (or one archive day) in memory.
    /// Dense payloads are decoded once into compact disk-backed roll-up
    /// projections, while archive rendering still reads one source day at a time.
    func finalizeCorpusDerivedOutputs(
        recordPayloadFiles: [URL],
        recordSourceDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        requestedDates: [Date],
        startDate: Date,
        endDate: Date,
        healthSubfolder: String? = nil,
        archiveWorkDirectoryURL: URL? = nil,
        unavailableRollupDates: Set<Date> = [],
        writeDataDictionary shouldWriteDataDictionary: Bool = true,
        progress: ((_ processed: Int, _ total: Int, _ date: Date?) -> Void)? = nil,
        cancellationCheck: () -> Bool = { false }
    ) async throws -> MacCorpusDerivedOutputResult {
        func checkCancellation() throws {
            if Task.isCancelled || cancellationCheck() { throw CancellationError() }
        }
        try checkCancellation()
        guard settings.archiveModeEnabled || HealthRollupExporter.isEnabled(settings: settings) else {
            return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 0)
        }
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "connected-mac",
                phase: "derived-finalization",
                timer: performanceTimer,
                itemCount: recordPayloadFiles.count
            )
        }
        #endif
        guard let vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        guard bookmarkResolver.startAccessing(vaultURL) else { throw ExportError.accessDenied }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let decoder = JSONDecoder()
        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = settings.exportTimeZoneOverride ?? .current
        var datedFiles: [(date: Date, url: URL)] = []
        datedFiles.reserveCapacity(recordPayloadFiles.count)
        if let recordSourceDates,
           recordSourceDates.count == recordPayloadFiles.count {
            datedFiles = Array(zip(recordSourceDates, recordPayloadFiles)).map {
                (date: $0.0, url: $0.1)
            }
        } else {
            // Backward-compatible fallback for callers that predate journal
            // source-date metadata. Current connected sessions avoid decoding
            // each dense payload merely to rediscover its date.
            for url in recordPayloadFiles {
                try checkCancellation()
                let payload = try decoder.decode(
                    ConnectedCorpusHealthDayPayload.self,
                    from: Data(contentsOf: url, options: [.mappedIfSafe])
                )
                if payload.record != nil { datedFiles.append((payload.sourceDate, url)) }
                await Task.yield()
            }
        }
        datedFiles.sort { $0.date < $1.date }

        var projectionDirectoryToCleanup: URL?
        defer {
            if let projectionDirectoryToCleanup {
                try? FileManager.default.removeItem(at: projectionDirectoryToCleanup)
            }
        }
        var rollupProjectionFiles: [(date: Date, url: URL)] = []
        if HealthRollupExporter.isEnabled(settings: settings) {
            let parent = archiveWorkDirectoryURL ?? FileManager.default.temporaryDirectory
            let projectionDirectory = parent.appendingPathComponent(
                ".healthmd-rollup-projections-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: projectionDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            projectionDirectoryToCleanup = projectionDirectory
            for (index, item) in datedFiles.enumerated() {
                try checkCancellation()
                let projectionURL = projectionDirectory.appendingPathComponent(
                    "\(index).json",
                    isDirectory: false
                )
                if try await Self.writeCompactRollupProjection(
                    sourceURL: item.url,
                    destinationURL: projectionURL
                ) {
                    rollupProjectionFiles.append((item.date, projectionURL))
                }
                await Task.yield()
            }
        }

        var summaries: [HealthRollupSummary] = []
        var finalizedUnits = 0
        let estimatedUnits = max(datedFiles.count + requestedDates.count, 1)
        if HealthRollupExporter.isEnabled(settings: settings) {
            for period in settings.enabledRollupPeriods {
                let windows = Set(requestedDates.map {
                    HealthRollupPeriodWindow.window(containing: $0, period: period, calendar: sourceCalendar)
                }).sorted { $0.startDate < $1.startDate }
                for window in windows {
                    try checkCancellation()
                    if unavailableRollupDates.contains(where: {
                        $0 >= window.startDate && $0 <= window.endDate
                    }) {
                        finalizedUnits += 1
                        progress?(finalizedUnits, estimatedUnits, window.endDate)
                        await Task.yield()
                        continue
                    }
                    var records: [HealthData] = []
                    for item in rollupProjectionFiles
                        where item.date >= window.startDate && item.date <= window.endDate {
                        records.append(try await Self.decodeHealthData(from: item.url))
                    }
                    let windowSummaries = HealthRollupExporter.makeSummaries(
                        from: records,
                        settings: settings,
                        periods: [period],
                        calendar: sourceCalendar
                    ).filter { $0.window == window }
                    summaries.append(contentsOf: windowSummaries)
                    finalizedUnits += 1
                    progress?(finalizedUnits, estimatedUnits, window.endDate)
                    await Task.yield()
                }
            }
        }

        let effectiveHealthSubfolder = healthSubfolder ?? self.healthSubfolder
        if settings.archiveModeEnabled {
            guard !datedFiles.isEmpty || (settings.summaryOnlyModeEnabled && !summaries.isEmpty) else {
                return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 0)
            }
            let healthFolderURL = ExportPathPlanner.healthSubfolderURL(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder
            )
            if !fileSystem.fileExists(atPath: healthFolderURL.path) {
                try fileSystem.createDirectory(at: healthFolderURL, withIntermediateDirectories: true)
            }
            let archiveURL = healthFolderURL.appendingPathComponent(
                archiveFilename(
                    startDate: startDate,
                    endDate: endDate,
                    timeZone: settings.exportTimeZoneOverride
                ),
                isDirectory: false
            )
            let workDirectory = archiveWorkDirectoryURL ?? healthFolderURL
            try FileManager.default.createDirectory(
                at: workDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let checkpointURL = workDirectory.appendingPathComponent(
                "archive-checkpoint.json",
                isDirectory: false
            )
            let fileManager = FileManager.default
            let writer: ZipArchiveWriter.Writer
            var committedArchivePaths: Set<String>
            if fileManager.fileExists(atPath: checkpointURL.path) {
                let checkpoint = try ZipArchiveWriter.loadCheckpoint(from: checkpointURL)
                guard checkpoint.destinationURL.standardizedFileURL == archiveURL.standardizedFileURL,
                      checkpoint.checkpointURL.standardizedFileURL == checkpointURL.standardizedFileURL else {
                    throw ZipArchiveWriter.ArchiveError.invalidCheckpoint
                }
                committedArchivePaths = Set(checkpoint.entryPaths)
                writer = try ZipArchiveWriter.recover(from: checkpointURL)
            } else {
                committedArchivePaths = []
                writer = try ZipArchiveWriter.begin(
                    to: archiveURL,
                    checkpointURL: checkpointURL,
                    workingDirectoryURL: workDirectory
                )
            }
            do {
                let dictionaryEntry = dataDictionaryArchiveEntry(settings: settings)
                if !committedArchivePaths.contains(dictionaryEntry.path) {
                    try checkCancellation()
                    try await Self.performArchiveIO {
                        try writer.append(dictionaryEntry, cancellationCheck: { Task.isCancelled })
                        _ = try writer.checkpoint()
                    }
                    committedArchivePaths.insert(dictionaryEntry.path)
                }

                if !settings.summaryOnlyModeEnabled {
                    let requestedDateSet = Set(requestedDates)
                    for item in datedFiles where requestedDateSet.contains(item.date) {
                        try checkCancellation()
                        progress?(finalizedUnits, estimatedUnits, item.date)
                        guard let record = try await Self.decodeConnectedHealthData(
                            from: item.url
                        ) else { continue }
                        let preparedExport = record.preparedExport(settings: settings)
                        for format in settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
                            let content = try preparedExport.content(format: format, settings: settings)
                            guard let data = content.data(using: .utf8) else {
                                throw CocoaError(.fileWriteInapplicableStringEncoding)
                            }
                            let entry = ZipArchiveWriter.Entry(
                                path: archiveEntryPath(for: record.date, format: format, settings: settings),
                                data: data
                            )
                            if !committedArchivePaths.contains(entry.path) {
                                try checkCancellation()
                                try await Self.performArchiveIO {
                                    try writer.append(entry, cancellationCheck: { Task.isCancelled })
                                    _ = try writer.checkpoint()
                                }
                                committedArchivePaths.insert(entry.path)
                            }
                        }
                        finalizedUnits += 1
                        progress?(finalizedUnits, estimatedUnits, item.date)
                        await Task.yield()
                    }
                }
                for target in HealthRollupExporter.outputTargets(
                    for: summaries,
                    healthSubfolder: "",
                    settings: settings
                ) {
                    guard let data = target.content.data(using: .utf8) else { continue }
                    let entry = ZipArchiveWriter.Entry(path: target.relativePath, data: data)
                    if !committedArchivePaths.contains(entry.path) {
                        try checkCancellation()
                        try await Self.performArchiveIO {
                            try writer.append(entry, cancellationCheck: { Task.isCancelled })
                            _ = try writer.checkpoint()
                        }
                        committedArchivePaths.insert(entry.path)
                    }
                }
                try checkCancellation()
                try await Self.performArchiveIO {
                    try writer.finish(cancellationCheck: { Task.isCancelled })
                }
                lastExportFolderURL = healthFolderURL
                lastExportStatus = "Exported ZIP archive: \(archiveURL.lastPathComponent)"
                return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 1)
            } catch {
                try? await Self.performArchiveIO { writer.abandon() }
                throw error
            }
        }

        guard !summaries.isEmpty else {
            return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 0)
        }
        if shouldWriteDataDictionary {
            try writeDataDictionary(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                settings: settings
            )
        }
        let targets = HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: effectiveHealthSubfolder,
            settings: settings
        )
        for target in targets {
            try checkCancellation()
            let folderURL = HealthRollupExporter.folderURL(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                period: target.summary.period,
                format: target.format,
                settings: settings
            )
            if !fileSystem.fileExists(atPath: folderURL.path) {
                try fileSystem.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            let fileURL = ExportPathPlanner.fileURL(in: folderURL, filename: target.filename)
            try fileSystem.writeString(target.content, to: fileURL, atomically: true)
            progress?(finalizedUnits, estimatedUnits, target.summary.window.endDate)
            await Task.yield()
        }
        try checkCancellation()
        return MacCorpusDerivedOutputResult(rollupFileCount: targets.count, archiveFileCount: 0)
    }

    // MARK: - Format Routing

    private func looseExportFormats(in settings: AdvancedExportSettings) -> [ExportFormat] {
        settings.exportFormats
            .filter { _ in settings.writesDailyAggregateFiles }
            .sorted(by: { $0.rawValue < $1.rawValue })
    }

    // MARK: - Data Dictionary

    private func writeDataDictionary(
        vaultURL: URL,
        healthSubfolder: String? = nil,
        settings: AdvancedExportSettings
    ) throws {
        let folderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder
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
        healthSubfolder: String? = nil,
        date: Date,
        settings: AdvancedExportSettings
    ) throws {
        if let collision = ExportPathPlanner.dailyNoteExportCollision(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder,
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
        preparedExport: PreparedHealthDataExport,
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
        let newContent = try preparedExport.content(format: format, settings: settings)

        let finalContent: String
        let action: String
        if fileSystem.fileExists(atPath: fileURL.path) {
            switch settings.writeMode {
            case .append:
                let existing = try fileSystem.contentsOfFile(at: fileURL)
                let appendedBlock = "\n\n" + newContent
                if existing == newContent || existing.hasSuffix(appendedBlock) {
                    // A scheduled retry may revisit a date after another format
                    // failed. Do not append the exact same aggregate block twice.
                    finalContent = existing
                    action = "Already present in"
                } else {
                    finalContent = existing + appendedBlock
                    action = "Appended to"
                }
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
        healthSubfolder: String? = nil,
        date: Date,
        settings: AdvancedExportSettings
    ) -> URL {
        ExportPathPlanner.aggregateFolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder,
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
