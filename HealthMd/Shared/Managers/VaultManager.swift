import Foundation
import SwiftUI
import Combine
import ExportKit

private extension WriteMode {
    var exportKitWriteMode: ExportWriteMode {
        switch self {
        case .overwrite:
            return .overwrite
        case .append:
            return .append
        case .update:
            return .update
        }
    }
}

private extension ExportFileWriteAction {
    var exportStatusAction: String {
        switch self {
        case .exported:
            return "Exported to"
        case .appended:
            return "Appended to"
        case .updated:
            return "Updated"
        }
    }
}

struct HealthExportWriteOutcome: Equatable {
    var aggregateFilesWritten: Int
    var pluginFilesWritten: Int
    var displayFilenames: [String]
    var pluginSummary: HealthExportPluginSideEffectSummary

    var totalFilesWrittenIncludingPlugins: Int {
        aggregateFilesWritten + pluginFilesWritten
    }

    init(
        aggregateSummary: HealthAggregateExportAdapter.WriteSummary,
        pluginSummary: HealthExportPluginSideEffectSummary
    ) {
        self.aggregateFilesWritten = aggregateSummary.filesWritten
        self.pluginFilesWritten = pluginSummary.individualEntriesCount
        self.displayFilenames = aggregateSummary.displayFilenames
        self.pluginSummary = pluginSummary
    }
}

@MainActor
final class VaultManager: ObservableObject {
    @Published var vaultURL: URL?
    @Published var vaultName: String = "No vault selected"
    @Published var healthSubfolder: String = "Health"
    @Published var lastExportStatus: String?
    /// The folder URL of the most recent successful export (vault + health subfolder).
    /// Used to deep-link into the iOS Files app after export.
    @Published var lastExportFolderURL: URL?

    private static let bookmarkKey = "obsidianVaultBookmark"
    private static let subfolderKey = "healthSubfolder"
    private static let destinationStoreKeys = ExportDestinationStoreKeys(
        bookmarkKey: bookmarkKey,
        baseRelativePathKey: subfolderKey
    )

    private let defaults: UserDefaultsStoring
    private let fileSystem: FileSystemAccessing
    private let bookmarkResolver: BookmarkResolving
    private let destinationStore: ExportDestinationBookmarkStore
    private let destinationAccess: any DestinationAccess
    private let fileWriter: ExportFileWriter

    init(
        defaults: UserDefaultsStoring = SystemUserDefaults(),
        fileSystem: FileSystemAccessing = SystemFileSystem(),
        bookmarkResolver: BookmarkResolving = SystemBookmarkResolver()
    ) {
        self.defaults = defaults
        self.fileSystem = fileSystem
        self.bookmarkResolver = bookmarkResolver
        self.destinationStore = ExportDestinationBookmarkStore(
            storage: defaults,
            bookmarkAccess: bookmarkResolver,
            keys: Self.destinationStoreKeys,
            defaultBaseRelativePath: "Health"
        )
        self.destinationAccess = SecurityScopedDestinationAccess(bookmarkAccess: bookmarkResolver)
        self.fileWriter = ExportFileWriter(fileSystem: FileSystemAccessingExportAdapter(fileSystem))
        loadSavedSettings()
    }

    // MARK: - Bookmark Management

    private func loadSavedSettings() {
        healthSubfolder = destinationStore.loadBaseRelativePath()

        do {
            guard let destination = try destinationStore.loadDestination() else {
                return
            }
            vaultURL = destination.rootURL
            vaultName = destination.displayName
        } catch {
            print("Failed to resolve bookmark: \(error)")
        }
    }

    private func saveBookmark(for url: URL) throws {
        try destinationStore.saveBookmark(for: url)
    }

    func saveSubfolderSetting() {
        destinationStore.saveBaseRelativePath(healthSubfolder)
    }

    // MARK: - Folder Selection

    func setVaultFolder(_ url: URL) {
        let destination = ExportDestination(
            rootURL: url,
            displayName: url.lastPathComponent,
            baseRelativePath: healthSubfolder
        )

        do {
            try destinationAccess.withAccess(to: destination) {
                try saveBookmark(for: url)
            }
            vaultURL = url
            vaultName = url.lastPathComponent
            lastExportStatus = nil
        } catch ExportDestinationAccessError.accessDenied(_) {
            lastExportStatus = "Failed to access folder"
        } catch {
            lastExportStatus = "Failed to save folder access: \(error.localizedDescription)"
        }
    }

    func clearVaultFolder() {
        destinationStore.clearBookmark()
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

    private var selectedDestination: ExportDestination? {
        guard let vaultURL else { return nil }
        return ExportDestination(
            rootURL: vaultURL,
            displayName: vaultName,
            baseRelativePath: healthSubfolder
        )
    }

    var currentExportDestination: ExportDestination? {
        selectedDestination
    }

    /// Returns whether the selected vault folder can currently be accessed via
    /// its security-scoped bookmark. Used by the Mac export-agent readiness
    /// status before iOS sends an export job.
    func canAccessSelectedVaultFolder() -> Bool {
        guard let destination = selectedDestination else { return false }
        do {
            try destinationAccess.withAccess(to: destination) {}
            return true
        } catch {
            return false
        }
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
            let record = HealthExportRecord(healthData: healthData)
            let aggregatePlan = try HealthAggregateExportAdapter.planAggregateFiles(
                record: record,
                settings: settings,
                healthSubfolder: healthSubfolder
            )
            try validateExportPlugins(
                record: record,
                vaultURL: vaultURL,
                aggregateFiles: aggregatePlan.files,
                settings: settings
            )

            _ = try HealthAggregateExportAdapter.write(
                plan: aggregatePlan,
                to: ExportDestination(rootURL: vaultURL, displayName: vaultName),
                settings: settings,
                fileWriter: fileWriter
            )

            // Opt-in plugins run once per date, regardless of which aggregate formats were written.
            _ = try performExportPluginSideEffects(
                record: record,
                vaultURL: vaultURL,
                aggregateFiles: aggregatePlan.files,
                settings: settings
            )

            return true
        } catch {
            lastExportStatus = error.localizedDescription
            print("Export failed: \(error)")
            return false
        }
    }

    // MARK: - Export

    @discardableResult
    func exportHealthData(_ healthData: HealthData, settings: AdvancedExportSettings) async throws -> HealthExportWriteOutcome {
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

        let record = HealthExportRecord(healthData: healthData)
        let aggregatePlan = try HealthAggregateExportAdapter.planAggregateFiles(
            record: record,
            settings: settings,
            healthSubfolder: healthSubfolder
        )
        try validateExportPlugins(
            record: record,
            vaultURL: vaultURL,
            aggregateFiles: aggregatePlan.files,
            settings: settings
        )

        // Record the health-subfolder level so we can deep-link into Files.app
        lastExportFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder
        )

        let aggregateSummary = try HealthAggregateExportAdapter.write(
            plan: aggregatePlan,
            to: ExportDestination(rootURL: vaultURL, displayName: vaultName),
            settings: settings,
            fileWriter: fileWriter
        )
        let writtenFilenames = aggregateSummary.displayFilenames
        let leadingAction = aggregateSummary.leadingAction.exportStatusAction

        // Opt-in plugins run once per date, regardless of which aggregate formats were written.
        let pluginSummary = try performExportPluginSideEffects(
            record: record,
            vaultURL: vaultURL,
            aggregateFiles: aggregatePlan.files,
            settings: settings
        )

        // Build status message showing the relative path
        let relativeFolderPath = ExportPathPlanner.aggregateFolderRelativePath(
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: healthData.date
        )
        let relativePath = relativeFolderPath.isEmpty ? "" : relativeFolderPath + "/"
        let filenamesJoined = writtenFilenames.joined(separator: ", ")
        var statusMessage = "\(leadingAction) \(relativePath)\(filenamesJoined)"
        if pluginSummary.individualEntriesCount > 0 {
            statusMessage += " + \(pluginSummary.individualEntriesCount) individual entr\(pluginSummary.individualEntriesCount == 1 ? "y" : "ies")"
        }
        switch pluginSummary.dailyNoteStatus {
        case .updated(let path):
            statusMessage += " · injected into \(path)"
        case .failed(let description):
            statusMessage += " · daily note injection failed: \(description)"
        case .skipped(let reason):
            if reason.contains("not found") {
                statusMessage += " · daily note not found (skipped)"
            }
        case .none:
            break
        }
        lastExportStatus = statusMessage

        return HealthExportWriteOutcome(
            aggregateSummary: aggregateSummary,
            pluginSummary: pluginSummary
        )
    }

    // MARK: - Export Plugins

    private func validateExportPlugins(
        record: HealthExportRecord,
        vaultURL: URL,
        aggregateFiles: [PlannedExportFile],
        settings: AdvancedExportSettings
    ) throws {
        let runner = ExportPluginRunner(plugins: HealthExportPluginAdapter.makePlugins(
            settings: settings,
            healthSubfolder: healthSubfolder,
            fileWriter: fileWriter
        ))
        let context = HealthExportPluginAdapter.context(
            record: record,
            operation: .validation,
            destination: ExportDestination(rootURL: vaultURL, displayName: vaultName),
            aggregateFiles: aggregateFiles,
            writeMode: settings.writeMode.exportKitWriteMode
        )

        do {
            _ = try runner.validate(record: record, context: context)
        } catch let error as HealthExportPluginError {
            throw exportError(for: error)
        }
    }

    private func performExportPluginSideEffects(
        record: HealthExportRecord,
        vaultURL: URL,
        aggregateFiles: [PlannedExportFile],
        settings: AdvancedExportSettings
    ) throws -> HealthExportPluginSideEffectSummary {
        let runner = ExportPluginRunner(plugins: HealthExportPluginAdapter.makePlugins(
            settings: settings,
            healthSubfolder: healthSubfolder,
            fileWriter: fileWriter
        ))
        let context = HealthExportPluginAdapter.context(
            record: record,
            operation: .write,
            destination: ExportDestination(rootURL: vaultURL, displayName: vaultName),
            aggregateFiles: aggregateFiles,
            writeMode: settings.writeMode.exportKitWriteMode
        )

        do {
            let results = try runner.performSideEffects(record: record, context: context)
            return HealthExportPluginSideEffectSummary.make(from: results)
        } catch let error as HealthExportPluginError {
            throw exportError(for: error)
        }
    }

    private func exportError(for pluginError: HealthExportPluginError) -> ExportError {
        switch pluginError {
        case .dailyNotePathConflict(let path):
            return .dailyNotePathConflict(path: path)
        case .missingDestination:
            return .noVaultSelected
        }
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
