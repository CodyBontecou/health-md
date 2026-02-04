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
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
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
        let bookmarkData = try url.bookmarkData(
            options: [],
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
            // Create the health subfolder if needed
            let healthFolderURL: URL
            if healthSubfolder.isEmpty {
                healthFolderURL = vaultURL
            } else {
                healthFolderURL = vaultURL.appendingPathComponent(healthSubfolder, isDirectory: true)
            }

            // Create directory if it doesn't exist
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: healthFolderURL.path) {
                try fileManager.createDirectory(at: healthFolderURL, withIntermediateDirectories: true)
            }

            // Generate filename using custom format
            let baseFilename = settings.formatFilename(for: date)
            let filename = "\(baseFilename).\(settings.exportFormat.fileExtension)"

            let fileURL = healthFolderURL.appendingPathComponent(filename)

            // Generate content based on format and settings
            let content = healthData.export(format: settings.exportFormat, settings: settings)

            // Write file
            try content.write(to: fileURL, atomically: true, encoding: .utf8)

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

        // Create the health subfolder if needed
        let healthFolderURL: URL
        if healthSubfolder.isEmpty {
            healthFolderURL = vaultURL
        } else {
            healthFolderURL = vaultURL.appendingPathComponent(healthSubfolder, isDirectory: true)
        }

        // Create directory if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: healthFolderURL.path) {
            try fileManager.createDirectory(at: healthFolderURL, withIntermediateDirectories: true)
        }

        // Generate filename using custom format
        let baseFilename = settings.formatFilename(for: healthData.date)
        let filename = "\(baseFilename).\(settings.exportFormat.fileExtension)"

        let fileURL = healthFolderURL.appendingPathComponent(filename)

        // Generate content based on format and settings
        let content = healthData.export(format: settings.exportFormat, settings: settings)

        // Write file
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        lastExportStatus = "Exported to \(healthSubfolder.isEmpty ? "" : healthSubfolder + "/")\(filename)"
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
