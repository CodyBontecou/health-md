import Foundation
import SwiftUI
import Combine

@MainActor
final class VaultManager: ObservableObject {
    @Published var vaultURL: URL?
    @Published var vaultName: String = "No vault selected"
    @Published var healthSubfolder: String = "Health"
    @Published var lastExportStatus: String?

    private let bookmarkKey = "obsidianVaultBookmark"
    private let subfolderKey = "healthSubfolder"
    
    /// Individual entry exporter for granular tracking
    private let individualExporter = IndividualEntryExporter()

    init() {
        loadSavedSettings()
    }

    // MARK: - Bookmark Management

    private func loadSavedSettings() {
        // Load subfolder setting
        if let savedSubfolder = UserDefaults.standard.string(forKey: subfolderKey) {
            healthSubfolder = savedSubfolder
        }

        // Load bookmark
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return
        }

        do {
            var isStale = false
            #if os(iOS)
            let bookmarkOptions: URL.BookmarkResolutionOptions = []
            #elseif os(macOS)
            let bookmarkOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #endif
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: bookmarkOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark is stale, need to re-save it
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    try saveBookmark(for: url)
                }
            }

            vaultURL = url
            vaultName = url.lastPathComponent
        } catch {
            print("Failed to resolve bookmark: \(error)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    private func saveBookmark(for url: URL) throws {
        #if os(iOS)
        let bookmarkOptions: URL.BookmarkCreationOptions = []
        #elseif os(macOS)
        let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
        #endif
        let bookmarkData = try url.bookmarkData(
            options: bookmarkOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }

    func saveSubfolderSetting() {
        UserDefaults.standard.set(healthSubfolder, forKey: subfolderKey)
    }

    // MARK: - Folder Selection

    func setVaultFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            lastExportStatus = "Failed to access folder"
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

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
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        vaultURL = nil
        vaultName = "No vault selected"
    }

    // MARK: - Background Access

    /// Check if we have vault access (for background tasks)
    var hasVaultAccess: Bool {
        vaultURL != nil
    }

    /// Refresh vault access for background tasks
    func refreshVaultAccess() {
        loadSavedSettings()
    }

    /// Start accessing the vault (for background tasks)
    func startVaultAccess() {
        guard let url = vaultURL else { return }
        _ = url.startAccessingSecurityScopedResource()
    }

    /// Stop accessing the vault (for background tasks)
    func stopVaultAccess() {
        guard let url = vaultURL else { return }
        url.stopAccessingSecurityScopedResource()
    }

    /// Export health data without automatic security scope (for background tasks)
    func exportHealthData(_ healthData: HealthData, for date: Date, settings: AdvancedExportSettings) -> Bool {
        guard let vaultURL = vaultURL else {
            return false
        }

        guard healthData.hasAnyData else {
            return false
        }

        do {
            // Build the full folder path: vault / healthSubfolder / folderStructure
            var targetFolderURL = vaultURL

            // Add health subfolder if set
            if !healthSubfolder.isEmpty {
                targetFolderURL = targetFolderURL.appendingPathComponent(healthSubfolder, isDirectory: true)
            }

            // Add date-based folder structure if configured
            if let folderPath = settings.formatFolderPath(for: date) {
                targetFolderURL = targetFolderURL.appendingPathComponent(folderPath, isDirectory: true)
            }

            // Create directory if it doesn't exist
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: targetFolderURL.path) {
                try fileManager.createDirectory(at: targetFolderURL, withIntermediateDirectories: true)
            }

            // Generate filename using custom format
            let baseFilename = settings.formatFilename(for: date)
            let filename = "\(baseFilename).\(settings.exportFormat.fileExtension)"

            let fileURL = targetFolderURL.appendingPathComponent(filename)

            // Generate content based on format and settings
            let newContent = healthData.export(format: settings.exportFormat, settings: settings)

            // Handle write mode (overwrite vs append)
            let finalContent: String
            if settings.writeMode == .append && fileManager.fileExists(atPath: fileURL.path) {
                // Read existing content and append
                let existingContent = try String(contentsOf: fileURL, encoding: .utf8)
                finalContent = existingContent + "\n\n" + newContent
            } else {
                finalContent = newContent
            }

            // Write file
            try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Export individual entries if enabled
            if settings.individualTracking.globalEnabled {
                _ = try exportIndividualEntries(
                    from: healthData,
                    to: targetFolderURL,
                    settings: settings
                )
            }

            return true
        } catch {
            print("Export failed: \(error)")
            return false
        }
    }

    // MARK: - Export

    func exportHealthData(_ healthData: HealthData, settings: AdvancedExportSettings) async throws {
        guard let vaultURL = vaultURL else {
            throw ExportError.noVaultSelected
        }

        guard healthData.hasAnyData else {
            throw ExportError.noHealthData
        }

        // Start accessing security-scoped resource
        guard vaultURL.startAccessingSecurityScopedResource() else {
            throw ExportError.accessDenied
        }

        defer { vaultURL.stopAccessingSecurityScopedResource() }

        // Build the full folder path: vault / healthSubfolder / folderStructure
        var targetFolderURL = vaultURL

        // Add health subfolder if set
        if !healthSubfolder.isEmpty {
            targetFolderURL = targetFolderURL.appendingPathComponent(healthSubfolder, isDirectory: true)
        }

        // Add date-based folder structure if configured
        if let folderPath = settings.formatFolderPath(for: healthData.date) {
            targetFolderURL = targetFolderURL.appendingPathComponent(folderPath, isDirectory: true)
        }

        // Create directory if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: targetFolderURL.path) {
            try fileManager.createDirectory(at: targetFolderURL, withIntermediateDirectories: true)
        }

        // Generate filename using custom format
        let baseFilename = settings.formatFilename(for: healthData.date)
        let filename = "\(baseFilename).\(settings.exportFormat.fileExtension)"

        let fileURL = targetFolderURL.appendingPathComponent(filename)

        // Generate content based on format and settings
        let newContent = healthData.export(format: settings.exportFormat, settings: settings)

        // Handle write mode (overwrite vs append)
        let finalContent: String
        let didAppend: Bool
        if settings.writeMode == .append && fileManager.fileExists(atPath: fileURL.path) {
            // Read existing content and append
            let existingContent = try String(contentsOf: fileURL, encoding: .utf8)
            finalContent = existingContent + "\n\n" + newContent
            didAppend = true
        } else {
            finalContent = newContent
            didAppend = false
        }

        // Write file
        try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        // Export individual entries if enabled
        var individualEntriesCount = 0
        if settings.individualTracking.globalEnabled {
            individualEntriesCount = try exportIndividualEntries(
                from: healthData,
                to: targetFolderURL,
                settings: settings
            )
        }

        // Build status message showing the relative path
        var relativePath = ""
        if !healthSubfolder.isEmpty {
            relativePath += healthSubfolder + "/"
        }
        if let folderPath = settings.formatFolderPath(for: healthData.date) {
            relativePath += folderPath + "/"
        }
        let action = didAppend ? "Appended to" : "Exported to"
        var statusMessage = "\(action) \(relativePath)\(filename)"
        if individualEntriesCount > 0 {
            statusMessage += " + \(individualEntriesCount) individual entr\(individualEntriesCount == 1 ? "y" : "ies")"
        }
        lastExportStatus = statusMessage
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

    var errorDescription: String? {
        switch self {
        case .noVaultSelected:
            return "Please select an Obsidian vault folder first"
        case .noHealthData:
            return "No health data available for the selected date"
        case .accessDenied:
            return "Cannot access the vault folder. Please re-select it."
        }
    }
}
